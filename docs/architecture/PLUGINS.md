# Plugin System

`lib/plugins/discovery/plugin_discovery_service.dart`
`lib/plugins/protocol/plugin_url_resolver.dart`
`lib/plugins/event_bridge/event_bridge.dart`
`lib/core/config/feature_flags.dart`

For the manifest schema see
[../PLUGIN_SPECIFICATION.md](../PLUGIN_SPECIFICATION.md).

---

## Feature gating

`kPluginsEnabled` in `core/config/feature_flags.dart` is a compile-time
`const`, so a `false` value dead-code-eliminates the plugin paths in
release builds.

When disabled, the UI stays **visible but unavailable** — users can see
the features exist:

| Surface | Disabled behaviour |
|---|---|
| Settings → Manage Plugins | Tile at 55 % opacity, muted colours, block icon, "Currently unavailable" |
| Settings → Preferred Provider | Same treatment, replaces the dropdown |
| Details → Watch Movie/Series | "Playback is currently unavailable" snackbar |
| Home → Continue Watching tap | Same snackbar |
| `/plugins` deep link | `_PluginsDisabledView` placeholder with a back-navigable AppBar |

`showPlaybackUnavailableSnack(context)` centralises the snackbar so the
flag is checked once per entry point rather than at every
`_executePlugin` / `_openFromStart` / `_openContinue` /
`_openNextEpisode` call site.

Flipping the flag to `true` restores everything; nothing else needs to
change.

---

## Discovery & validation

`PluginDiscoveryService` fetches, parses, and validates manifests from
remote URLs. It accepts three shapes:

- A single manifest object
- A JSON array of manifest URLs (strings) or inline manifest objects
- An object with a `"plugins"` array

Invalid entries inside arrays are skipped rather than failing the batch.

### Size cap enforced mid-stream

`_kMaxManifestBytes` is generous for any legitimate manifest (typically
<10 KB) or registry (<256 KB), but the enforcement matters more than the
number.

Without **mid-stream** cancellation, a hostile server that omits
`Content-Length` — or lies about it — simply streams gigabytes. Dio
buffers the whole `ResponseType.bytes` body before returning, so a
post-hoc length check fires far too late to prevent OOM.

The implementation therefore:

1. Pre-flight `Content-Length` check — a cheap reject for honest servers.
2. `onReceiveProgress` + `CancelToken` — aborts as soon as `received`
   crosses the cap.
3. Post-hoc check as defence-in-depth, catching very small bodies that
   arrive in a single chunk without the progress callback firing.

Our own cancellation surfaces as `DioExceptionType.cancel`, which is
translated back into `PluginNetworkException` so callers see the
size-cap message rather than a generic "request cancelled".

### `urlTemplate` scheme validation

`urlTemplate` is loaded directly into a WebView, so `javascript:`,
`data:`, `file:` and friends would execute in the WebView context.
`UrlValidator.validateUrlTemplate` enforces `http(s)` and bounds length
against pathological payloads.

The player repeats this check at construction time as defence-in-depth —
see [PLAYER.md](PLAYER.md#navigation-security-guards).

---

## URL resolution

`PluginUrlResolver.resolve` substitutes `{{tmdbId}}`, `{{type}}`,
`{{title}}`, `{{imdbId}}`, `{{season}}`, `{{episode}}`.

### TV fallback when no placeholders exist

Many embed services use a path-based scheme —
`…/tv/{id}/{season}/{episode}` — but a plugin author may write a short
template without `{{season}}`/`{{episode}}`. When a TV show is resolved
and neither placeholder appears, the resolver appends season and episode
as extra path segments, defaulting to S1E1 when called from the
media-header hook.

```
template  : https://example.com/embed/{{type}}/{{tmdbId}}?color=…
movie     : https://example.com/embed/movie/12345?color=…
tv header : https://example.com/embed/tv/12345/1/1?color=…   (S1E1)
tv ep 3   : https://example.com/embed/tv/12345/1/3?color=…
```

`Uri.tryParse` is used rather than `parse` — a malformed template (or a
weird substitution result) should not take down the resolver; it falls
back to plain string concatenation, appending before any query or
fragment.

For movies, explicit season/episode placeholders are cleared.

### `pickPlugin` resolution order

1. `savedId` — the plugin previously used for this exact item
2. `preferredId` — the user's globally preferred plugin
3. `plugins.first`

Centralised because this logic was previously duplicated — and had
subtly diverged — between the home screen's Continue Watching path and
the in-player Play Next Episode overlay. Returns `null` only when
`plugins` is empty.

---

## Event bridge

`EventBridge` parses `postMessage` payloads from the player WebView and
throttles progress writes.

### Supported payload shapes

**1. Standard `PLAYER_EVENT`** (Provider A, Provider C, Provider B). Provider C omits
`progress` and sends `tmdbId: "false"`, so progress is computed from
`currentTime / duration`.

Provider B uses the same outer wrapper but renames two fields:

| Provider A | Provider B |
|---|---|
| `data.currentTime` | `data.timestamp` |
| `data.mediaType` | `data.type` |

The outer `type` is still the literal `"PLAYER_EVENT"` that was matched
on. The `?? data['timestamp']` fallback is what makes Provider B progress
save at all — without it every Provider B `timeupdate` stored
`currentTime = 0`. Confirmed in the player log 2026-06-04; see the
Watch-Progress-Tracking section of the Provider B docs.

**2. Provider D flat format** —
`{"channel":"example-channel","event":"time","time":…,"duration":…,"percent":…}`

**3. Provider C native format** —
`{"event":"time"|"pause"|"paused"|"userpause","time":…,"data":…,"duration":…}`
with no `type` or `channel`; current time in `time` or `data`. The
progress bar read 0 until these were parsed.

### Type safety

`_asInt` returns `null` for non-numeric values — plugins send `false` for
movie season/episode fields.

`_allowedMediaTypes` restricts what the `data['type']` fallback accepts.
Without the restriction, a plugin sending an arbitrary `type` string
inside `data` could poison `UserProgress.mediaType` and bypass the
Continue-Watching filters that key on it.

### Throttling

Only `ended` and `pause` skip the throttle — they are the only events
where an immediate save matters (the user stopped or finished).

`seeked` is throttled deliberately: scrubbing fires it dozens of times
per second and writing on each one is Hive I/O with no UX benefit. The
final resting `currentTime` is captured by the next throttled
`timeupdate` or a subsequent `pause`/`ended`.

`play` is throttled too — it carries the same time value as the preceding
`timeupdate`.

Everything else writes at most once per 5 s.
