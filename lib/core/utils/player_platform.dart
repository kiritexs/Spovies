import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Single source of truth for platform-conditional behaviour in the
/// WebView player and its surrounding code.
///
/// Every getter combines its `Platform.is*` check with `!kIsWeb`, so
/// `dart:io` is never dereferenced on the web target.
///
/// See `docs/architecture/PLATFORM.md` for the rationale behind each
/// policy below.
abstract final class PlayerPlatform {
  // ── Bare OS probes ────────────────────────────────────────────────────
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  // ── Compound categories ───────────────────────────────────────────────

  static bool get isDesktop => isWindows || isMacOS || isLinux;
  static bool get isMobile => isIOS || isAndroid;

  // ── Player policy ─────────────────────────────────────────────────────

  /// Native `shouldInterceptRequest` ad blocking. Off on Windows —
  /// WebView2's platform channel is too slow for HLS.
  static bool get useNativeAdBlocking => !isWindows;

  /// Off on Android — some Xiaomi/Redmi GPUs render the WebView fully
  /// black under Impeller with hardware acceleration on.
  static bool get useHardwareAcceleration => !isAndroid;

  /// MOBILE vs DESKTOP `UserPreferredContentMode`. Always matches the UA
  /// branch below so UA, client hints, and content mode agree.
  static bool get useMobileContentMode => isIOS || isAndroid;

  static bool get supportsOrientationLock => isMobile;

  /// iOS WKWebView needs the `playsinline` patch.
  static bool get needsIosInlineVideoFix => isIOS;

  /// Rewrites the `"Android WebView"` brand in
  /// `navigator.userAgentData.brands`. The only spoof we ship.
  static bool get needsAndroidBrandHide => isAndroid;

  /// Mutes `console.*` so pages that flood the log can't starve the UI
  /// thread. Enabled everywhere.
  static bool get needsConsoleKiller => true;

  /// JS-side fetch/XHR/WebSocket blocker. Windows only — elsewhere the
  /// native layer already does this, and doubling up breaks Turnstile.
  static bool get needsAdGuardFetchPatch => isWindows;

  /// Fullscreen API no-ops. iOS only — WKWebView hands `<video>` to a
  /// native AVPlayer overlay outside our control.
  static bool get needsFullscreenSuppression => isIOS;

  /// The real native browser UA for each OS. Chrome version is bumped
  /// together across platforms, as real Chrome ships.
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
      return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
          'Safari/605.1.15';
    }
    if (isLinux) {
      return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
    }
    // Windows, and any future desktop fallback.
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
  }
}
