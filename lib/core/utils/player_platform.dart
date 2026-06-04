import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Single source of truth for platform-conditional behaviour in the
/// WebView player and its surrounding code.
///
/// Three goals:
///   1. **One place to read.** Previously every `Platform.isWindows` check
///      lived inline in `webview_player_screen.dart`; adding a new
///      platform tweak meant grepping a 2 k-line file.
///   2. **Web-safe.** Every getter combines its `Platform.is*` check with
///      `!kIsWeb` so `dart:io` is never dereferenced on the web target.
///   3. **Semantic getters, not flag-spaghetti.** Callers say
///      `PlayerPlatform.useHardwareAcceleration` instead of
///      `!Platform.isAndroid` — the "why" lives at the definition.
abstract final class PlayerPlatform {
  // ── Bare OS probes ────────────────────────────────────────────────────
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  // ── Compound categories ───────────────────────────────────────────────

  /// Desktop platforms (no orientation lock, has window chrome / drag area,
  /// uses DESKTOP content mode in the WebView).
  static bool get isDesktop => isWindows || isMacOS || isLinux;

  /// Mobile platforms (orientation lock, immersive UI, MOBILE content mode).
  static bool get isMobile => isIOS || isAndroid;

  // ── Player-specific policy ────────────────────────────────────────────

  /// Native network-level ad blocking via `shouldInterceptRequest`.
  ///
  /// Disabled on Windows: `flutter_inappwebview`'s Win32/WebView2 adapter
  /// routes every chunk through the platform channel, which is too slow
  /// for HLS playback.
  static bool get useNativeAdBlocking => !isWindows;

  /// WebView hardware acceleration.
  ///
  /// Disabled on Android: some Xiaomi/Redmi GPUs render the WebView as a
  /// fully-black surface under Impeller when hardware acceleration is on.
  static bool get useHardwareAcceleration => !isAndroid;

  /// MOBILE vs DESKTOP `UserPreferredContentMode` for the WebView.
  ///
  /// Always matches the UA branch below — mobile platforms send a mobile
  /// UA and ask for mobile content; desktops send a desktop UA and ask
  /// for desktop content. Consistent signals across UA string,
  /// `sec-ch-ua-mobile` Client-Hint, and `navigator.userAgentData.mobile`
  /// are the entire reason this getter exists.
  static bool get useMobileContentMode => isIOS || isAndroid;

  /// Orientation lock + immersive system UI are mobile-only.
  static bool get supportsOrientationLock => isMobile;

  /// iOS WKWebView needs the inline-video patch; the script is harmless
  /// on other platforms but no point injecting it.
  static bool get needsIosInlineVideoFix => isIOS;

  /// Minimal `navigator.userAgentData.brands` rewrite — replaces the
  /// system's `"Android WebView"` brand with stock Chromium values.
  ///
  /// Android-only. The HTTP `sec-ch-ua` header is set by System WebView
  /// at the native layer and we can't change it, but every JS-side site
  /// that reads `navigator.userAgentData.brands` would otherwise see
  /// `"Android WebView"` and either degrade the layout or block. This
  /// is the single spoof we ship — `platform`, `mobile`, `architecture`
  /// etc. all pass through honestly from the real `userAgentData`, so
  /// signals stay consistent across the page.
  static bool get needsAndroidBrandHide => isAndroid;

  /// Console-mute script — replaces `console.log`/`warn`/`error`/`clear`
  /// etc. with no-ops so pages that flood the log (the most common
  /// pattern is a `console.clear()` in a tight loop to defeat dev-tools)
  /// can't drown the bridge or starve the UI thread. Enabled on every
  /// platform; the trimmed version of this script only assigns no-ops to
  /// `console.*` and no longer touches `navigator.webdriver` /
  /// `outerWidth` / `outerHeight`.
  static bool get needsConsoleKiller => true;

  /// JS-side `fetch`/`XHR`/`WebSocket` ad blocker
  /// (`player_adguard.js`).
  ///
  /// **Windows-only.** On Android and iOS the native
  /// `shouldInterceptRequest` callback already runs every resource
  /// through the same blocklist at the platform layer — earlier and
  /// cheaper than a JS wrapper can. Windows WebView2's
  /// `shouldInterceptRequest` is too slow on the platform channel for
  /// HLS playback (see [useNativeAdBlocking]), so JS-side fetch/XHR
  /// patching is the only blocking layer Windows gets.
  ///
  /// The script patches the same APIs every plugin uses to talk to
  /// streaming providers; running it on Android/iOS where the native
  /// layer already does the job has been observed to break Cloudflare
  /// Turnstile and some HLS shims for no incremental benefit.
  static bool get needsAdGuardFetchPatch => isWindows;

  /// JS-side Fullscreen API suppression
  /// (`player_suppress_fullscreen.js`).
  ///
  /// **iOS-only.** WKWebView hands `<video>.requestFullscreen` to a
  /// native AVPlayer overlay that sits outside the WebView surface,
  /// killing our progress tracker, overlay chrome, and JS bridge until
  /// the user dismisses it. No equivalent takeover exists on Android
  /// (landscape immersive already covers the screen) or Windows
  /// (WebView2 fullscreen stays inside the WebView surface), so the
  /// noop's are dead weight on those targets and risk surprising sites
  /// that legitimately use the Fullscreen API for DRM playback.
  static bool get needsFullscreenSuppression => isIOS;

  /// UA override per platform.
  ///
  /// Each branch sends the real native browser UA for that OS — exactly
  /// what a stock Chrome / Safari user on the same OS would send. The
  /// only thing we still hide is the `"Android WebView"` brand in
  /// `navigator.userAgentData` on Android (see [needsAndroidBrandHide]);
  /// the UA STRING is fully honest.
  ///
  /// Per-platform real UAs are the best-practice baseline because:
  ///   • Sites' bot detectors flag *inconsistency* between UA / content
  ///     mode / Client-Hints far more than they flag any individual
  ///     value, so matching everything to the platform's native browser
  ///     produces the cleanest signal.
  ///   • Streaming sites built mobile layouts because mobile users
  ///     exist — letting them serve mobile to mobile is more reliable
  ///     than fighting their device-detection.
  ///   • Updates are one branch per OS instead of "find one UA that
  ///     works everywhere".
  ///
  /// Chrome version is bumped together across platforms (148) — that's
  /// how real Chrome ships in lockstep across desktop and Android.
  ///
  /// MIUI footnote: Xiaomi/Redmi/Poco System WebView mangles the words
  /// "Android" and "Mobile" in the wire UA as a fingerprint-resistance
  /// feature. Cloudflare-protected sources may misbehave on those
  /// devices — that's a system-level behaviour we can't override from
  /// app code, and using a fake desktop UA "to dodge MIUI" punishes
  /// every non-MIUI Android user with an inconsistent UA. Per-platform
  /// honesty wins on average.
  static String? get defaultUserAgent {
    if (isIOS) {
      return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
          'Mobile/15E148 Safari/604.1';
    }
    if (isAndroid) {
      return 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36';
    }
    if (isMacOS) {
      // Safari on macOS — matches the WKWebView engine we actually
      // render with on this target.
      return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
          'Safari/605.1.15';
    }
    if (isLinux) {
      return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
    }
    // Windows (and any future desktop fallback).
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
  }
}
