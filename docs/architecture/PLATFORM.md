# Per-Platform Policy

`lib/core/utils/player_platform.dart`
`lib/presentation/screens/player/web_view_player_config.dart`

`PlayerPlatform` is the single source of truth for platform-conditional
behaviour in the player and its surrounding code.

Three goals shaped it:

1. **One place to read.** Every `Platform.isWindows` check used to live
   inline in `webview_player_screen.dart`; adding a platform tweak meant
   grepping a 2 k-line file.
2. **Web-safe.** Every getter combines its `Platform.is*` check with
   `!kIsWeb`, so `dart:io` is never dereferenced on the web target.
3. **Semantic getters, not flag spaghetti.** Callers say
   `PlayerPlatform.useHardwareAcceleration`, not `!Platform.isAndroid` —
   the "why" lives at the definition.

---

## Policy getters

### `useNativeAdBlocking` → `!isWindows`

Network-level blocking via `shouldInterceptRequest`. Disabled on Windows:
`flutter_inappwebview`'s Win32/WebView2 adapter routes every chunk
through the platform channel, which is too slow for HLS playback.

### `useHardwareAcceleration` → `!isAndroid`

Disabled on Android: some Xiaomi/Redmi GPUs render the WebView as a fully
black surface under Impeller when hardware acceleration is on.

### `useMobileContentMode` → `isIOS || isAndroid`

MOBILE vs DESKTOP `UserPreferredContentMode`. Always matches the UA
branch — mobile platforms send a mobile UA and ask for mobile content;
desktops send a desktop UA and ask for desktop content.

Consistent signals across the UA string, the `sec-ch-ua-mobile` client
hint, and `navigator.userAgentData.mobile` is the entire reason this
getter exists.

### `needsAdGuardFetchPatch` → `isWindows`

The JS-side `fetch`/`XHR`/`WebSocket` blocker (`player_adguard.js`).

Windows-only. On Android and iOS the native `shouldInterceptRequest`
callback already runs every resource through the same blocklist at the
platform layer — earlier and cheaper than a JS wrapper can. Windows
WebView2's `shouldInterceptRequest` is too slow on the platform channel
for HLS playback (see `useNativeAdBlocking`), so JS-side patching is the
only blocking layer Windows gets.

The script patches the same APIs every plugin uses to talk to streaming
providers; running it on Android/iOS where the native layer already does
the job has been observed to break Cloudflare Turnstile and some HLS
shims for no incremental benefit.

### `needsFullscreenSuppression` → `isIOS`

iOS-only. WKWebView hands `<video>.requestFullscreen` to a native
AVPlayer overlay that sits outside the WebView surface, killing the
progress tracker, overlay chrome, and JS bridge until the user dismisses
it.

No equivalent takeover exists on Android (landscape immersive already
covers the screen) or Windows (WebView2 fullscreen stays inside the
WebView surface), so the no-ops are dead weight there and risk surprising
sites that legitimately use the Fullscreen API for DRM playback.

### `needsAndroidBrandHide` → `isAndroid`

Replaces the system's `"Android WebView"` brand in
`navigator.userAgentData.brands` with stock Chromium values.

The HTTP `sec-ch-ua` header is set by System WebView at the native layer
and cannot be changed from app code, but every JS-side site reading
`navigator.userAgentData.brands` would otherwise see `"Android WebView"`
and either degrade the layout or block outright.

This is the **single spoof** shipped — `platform`, `mobile`,
`architecture` and everything else pass through honestly from the real
`userAgentData`, so signals stay consistent across the page.

### `needsIosInlineVideoFix` → `isIOS`

iOS WKWebView needs the `playsinline` attribute patch. Harmless
elsewhere, but no point injecting it.

### `needsConsoleKiller` → `true`

Replaces `console.log`/`warn`/`error`/`clear` with no-ops so pages that
flood the log — most commonly a `console.clear()` in a tight loop to
defeat dev-tools — cannot drown the bridge or starve the UI thread.

Enabled everywhere. The trimmed script only assigns no-ops to `console.*`
and no longer touches `navigator.webdriver` / `outerWidth` /
`outerHeight`.

### `supportsOrientationLock` → `isMobile`

Orientation lock and immersive system UI are mobile-only APIs.

---

## User agents

Each branch sends the real native browser UA for that OS — exactly what a
stock Chrome/Safari user on the same OS would send. The **UA string is
fully honest**; the only thing hidden is the `"Android WebView"` brand in
`navigator.userAgentData` (see `needsAndroidBrandHide`).

| Platform | UA |
|---|---|
| iOS | iPhone Safari 17.0 |
| Android | Linux; Android 10; K — Chrome 148 Mobile |
| macOS | Safari 17.0 (matches the WKWebView engine we actually render with) |
| Linux | X11; Linux x86_64 — Chrome 148 |
| Windows | Windows NT 10.0; Win64; x64 — Chrome 148 |

Chrome version is bumped together across platforms — that is how real
Chrome ships, in lockstep across desktop and Android.

### Why per-platform real UAs

- Bot detectors flag **inconsistency** between UA / content mode / client
  hints far more than they flag any individual value. Matching everything
  to the platform's native browser produces the cleanest signal.
- Streaming sites built mobile layouts because mobile users exist.
  Letting them serve mobile to mobile is more reliable than fighting
  their device detection.
- Updates are one branch per OS instead of hunting for one UA that works
  everywhere.

### MIUI footnote

Xiaomi/Redmi/Poco System WebView mangles the words "Android" and "Mobile"
in the wire UA as a fingerprint-resistance feature. Cloudflare-protected
sources may misbehave on those devices. That is a system-level behaviour
app code cannot override, and using a fake desktop UA "to dodge MIUI"
punishes every non-MIUI Android user with an inconsistent UA.
Per-platform honesty wins on average.

---

## WebView settings

### Multi-window support

Gates the `onCreateWindow` callback. The trade-off is platform-specific:

**iOS / Android — keep ON.** Without it, ad popups can bypass the WebView
entirely and trigger external app intents (`intent://`, `market://`). The
callback is needed to intercept them.

**Windows — turn OFF.** On WebView2, `supportMultipleWindows: true` plus
a rejected `onCreateWindow` (returning `false`) does not actually
suppress the popup. WebView2 instead:

1. Spawns a hidden child `WebView2: about:blank` process for the
   would-be popup. That process is never reclaimed — they accumulate in
   alt-tab on each click.
2. Falls back to navigating the current frame to the anchor's href
   (`about:blank`), which wipes the player.

With the flag off, WebView2 silently rejects popups at the native layer:
no child process, no orphan tabs, no fallback. There is no Windows
analogue of Android intent URIs to worry about.

### Other settings

- **Inline playback** is required so iOS does not hand off to AVPlayer.
- **PiP is disabled** — it tears the video out of the WebView context.
- **iOS swipe-back disabled** so horizontal swipes inside the player UI
  (carousels, tab bars) are not intercepted.

---

## Injected script order

As built in `web_view_player_config.dart`:

1. `isAd` first, so every later script can use `window.__spoviesIsAd`.
2. Ad removal (DOM hide + `window.open` allowlist).
3. No-select CSS.
4. Console killer (where enabled).
5. Platform-gated, all at `AT_DOCUMENT_START`: AdGuard `fetch`/XHR/WS
   patches (Windows), fullscreen suppression and the inline-video fix
   (iOS), brand hide (Android). All are in place before the page's own
   scripts run, so before its first network call.
6. App bridge (`AT_DOCUMENT_END`: it needs `flutter_inappwebview`'s
   bridge), the user-activity tracker (`AT_DOCUMENT_START`: it only
   listens for input) and the video-progress tracker
   (`AT_DOCUMENT_END`).

`forMainFrameOnly: false` everywhere, because streaming sites embed the
player inside cross-origin iframes and both the fix and the tracker have
to run in those frames too.

### Gating summary

The set is intentionally minimal. The rule is *platform-essential ad and
popup defence, plus app integration*. Anything that is pure fingerprint
evasion, or that compensates for a native gap on a **different**
platform, is gated off — each target only pays for what it needs.

| Script | Platforms |
|---|---|
| `isAd` — URL pattern matcher | all |
| `adRemoval` — DOM hide + `window.open` allowlist | all |
| `noSelectCss` — disable long-press callout | all |
| `bridge` — app ↔ page comms | all |
| `userActivity` — controls timer | all |
| `videoProgress` — progress tracking | all |
| `consoleKiller` | all |
| `adGuard` — fetch/XHR/WS blocker | Windows only |
| `suppressFullscreen` | iOS only |
| `iosInlineVideo` | iOS only |
| `brandHide` | Android only |
