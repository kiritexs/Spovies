import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/utils/player_platform.dart';
import 'player_scripts.dart';

/// Builds the `InAppWebViewSettings` and the ordered `UserScript` list.
///
/// Kept next to the asset-loaded JS so the platform-policy decisions are
/// one indirection from anyone auditing the security model. See
/// `docs/architecture/PLATFORM.md`.
abstract final class WebViewPlayerConfig {
  static InAppWebViewSettings buildSettings() => InAppWebViewSettings(
    // UA and content mode always agree — see PlayerPlatform.
    userAgent: PlayerPlatform.defaultUserAgent,
    preferredContentMode: PlayerPlatform.useMobileContentMode
        ? UserPreferredContentMode.MOBILE
        : UserPreferredContentMode.DESKTOP,

    // Playback — inline is required so iOS does not hand off to AVPlayer.
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    // PiP tears the video out of the WebView context.
    allowsPictureInPictureMediaPlayback: false,

    // JavaScript & Storage.
    javaScriptEnabled: true,
    domStorageEnabled: true,
    cacheEnabled: true,

    // Performance.
    hardwareAcceleration: PlayerPlatform.useHardwareAcceleration,
    useWideViewPort: false,
    loadWithOverviewMode: false,
    overScrollMode: OverScrollMode.NEVER,
    disableDefaultErrorPage: true,

    // Scroll & touch.
    supportZoom: false,
    disableContextMenu: true,
    // iOS: disable swipe-back so horizontal swipes inside the player UI
    // (carousels, tab bars) aren't intercepted.
    allowsBackForwardNavigationGestures: false,

    // Rendering.
    transparentBackground: true,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    useOnLoadResource: false,

    // Network-level ad blocking — see PlayerPlatform.useNativeAdBlocking.
    useShouldInterceptRequest: PlayerPlatform.useNativeAdBlocking,

    // Gates `onCreateWindow`. ON for mobile so we can intercept popups
    // before they fire external app intents; OFF on Windows, where
    // WebView2 leaks a child process per rejected popup and then wipes
    // the player. See PLATFORM.md § Multi-window support.
    supportMultipleWindows: !PlayerPlatform.isWindows,
    javaScriptCanOpenWindowsAutomatically: false,
  );

  /// Build the ordered `UserScript` list for a single player session.
  ///
  /// Order matters and `forMainFrameOnly` is `false` everywhere —
  /// streaming sites embed the player in cross-origin iframes. The set is
  /// intentionally minimal: platform-essential ad/popup defence plus app
  /// integration, nothing that is pure fingerprint evasion. See
  /// `docs/architecture/PLATFORM.md` § Injected script order.
  static List<UserScript> buildUserScripts({
    required PlayerScripts scripts,
    required double resumeTimeSeconds,
  }) {
    const docStart = UserScriptInjectionTime.AT_DOCUMENT_START;
    const docEnd = UserScriptInjectionTime.AT_DOCUMENT_END;
    return [
      // ── Cross-platform ──────────────────────────────────────────────
      // Defines window.__spoviesIsAd; must come first.
      UserScript(
        source: scripts.isAd,
        injectionTime: docStart,
        forMainFrameOnly: false,
      ),

      // CSS ad hide + window.open allowlist.
      UserScript(
        source: scripts.adRemoval,
        injectionTime: docStart,
        forMainFrameOnly: false,
      ),

      // No long-press selection callout on the player surface.
      UserScript(
        source: scripts.noSelectCss,
        injectionTime: docStart,
        forMainFrameOnly: false,
      ),

      if (PlayerPlatform.needsConsoleKiller)
        UserScript(
          source: scripts.consoleKiller,
          injectionTime: docStart,
          forMainFrameOnly: false,
        ),

      // ── Platform-conditional ────────────────────────────────────────
      if (PlayerPlatform.needsAdGuardFetchPatch)
        UserScript(
          source: scripts.adGuard,
          injectionTime: docStart,
          forMainFrameOnly: false,
        ),
      if (PlayerPlatform.needsFullscreenSuppression)
        UserScript(
          source: scripts.suppressFullscreen,
          injectionTime: docStart,
          forMainFrameOnly: false,
        ),
      if (PlayerPlatform.needsIosInlineVideoFix)
        UserScript(
          source: scripts.iosInlineVideo,
          injectionTime: docStart,
          forMainFrameOnly: false,
        ),
      if (PlayerPlatform.needsAndroidBrandHide)
        UserScript(
          source: scripts.brandHide,
          injectionTime: docStart,
          forMainFrameOnly: false,
        ),

      // ── App-specific — depend on the inappwebview bridge ─────────────
      UserScript(
        source: scripts.bridge,
        injectionTime: docEnd,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: scripts.userActivity,
        injectionTime: docStart,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: scripts.videoProgress(resumeTimeSeconds),
        injectionTime: docEnd,
        forMainFrameOnly: false,
      ),
    ];
  }
}
