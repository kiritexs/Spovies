import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/utils/player_platform.dart';
import 'player_scripts.dart';

/// Constructs the `InAppWebViewSettings` and the ordered `UserScript`
/// list for the player. Extracted from `webview_player_screen.dart` so
/// the configuration lives next to the asset-loaded JS and the
/// platform-policy decisions are one indirection away from a reviewer
/// auditing the security model.
abstract final class WebViewPlayerConfig {
  /// The `InAppWebViewSettings` used by every `WebViewPlayerScreen`.
  ///
  /// Each option's "why" is documented at the call site — see
  /// `PlayerPlatform` for the policy semantics (mobile-vs-desktop content
  /// mode, native ad blocking, hardware acceleration).
  static InAppWebViewSettings buildSettings() => InAppWebViewSettings(
    // User-Agent & Content Mode.
    //
    // iOS    → real mobile Safari UA + MOBILE content mode
    //          (WKWebView's inline-video behaviour requires both).
    // Android → no UA override (System WebView's stock UA) + MOBILE
    //          content mode. No spoofing — sec-ch-ua-platform,
    //          sec-ch-ua-mobile, navigator.platform, and the UA string
    //          all agree that we're an Android WebView. Letting sites
    //          serve their mobile layout is the honest path.
    // Windows → desktop Chrome UA + DESKTOP content mode
    //          (correct for desktop).
    //
    // See PlayerPlatform.defaultUserAgent and useMobileContentMode for
    // the per-platform rationale.
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

    // Multi-window support gates the `onCreateWindow` callback. The
    // trade-off is platform-specific:
    //
    //   • iOS / Android — keep ON. Without it, ad popups can bypass
    //     the WebView entirely and trigger external app intents (e.g.
    //     `intent://`, `market://`). We need the callback to intercept.
    //
    //   • Windows — turn OFF. On WebView2, `supportMultipleWindows:true`
    //     + a rejected `onCreateWindow` (return false) doesn't actually
    //     suppress the popup. WebView2:
    //       1. Spawns a hidden child `WebView2: about:blank` process for
    //          the would-be popup. That process is never reclaimed —
    //          you can watch them accumulate in alt-tab on each click.
    //       2. Falls back to navigating the CURRENT frame to the
    //          anchor's href (about:blank), which is what wipes the
    //          player.
    //     With this flag off, WebView2 silently rejects popups at the
    //     native layer: no child process, no orphan tabs, no fallback.
    //     There's no Windows analogue of Android intent URIs to worry
    //     about.
    supportMultipleWindows: !PlayerPlatform.isWindows,
    javaScriptCanOpenWindowsAutomatically: false,
  );

  /// Build the ordered `UserScript` list for a single player session.
  ///
  /// The order matters:
  ///   1. `isAd` first so every later script can use `window.__spoviesIsAd`.
  ///   2. UA-data spoof on Android before any feature detection.
  ///   3. AdGuard (fetch/XHR patches) before any network calls.
  ///   4. Console killer on iOS/Windows.
  ///   5. Ad removal + anti-clickjack (DOM defence).
  ///   6. Fullscreen suppression + iOS inline-video fix + no-select CSS.
  ///   7. App-specific bridge, user-activity tracker, and video-progress
  ///      tracker — these depend on flutter_inappwebview's bridge so they
  ///      run at AT_DOCUMENT_END.
  ///
  /// `forMainFrameOnly: false` everywhere because streaming sites embed
  /// the player inside cross-origin iframes; the fix and the tracker
  /// have to run in those frames too.
  static List<UserScript> buildUserScripts({
    required PlayerScripts scripts,
    required double resumeTimeSeconds,
  }) {
    const docStart = UserScriptInjectionTime.AT_DOCUMENT_START;
    const docEnd = UserScriptInjectionTime.AT_DOCUMENT_END;
    // The script set is intentionally minimal — the rule is "platform-
    // essential ad / popup defence + app integration". Anything that's
    // pure fingerprint evasion or that compensates for a native gap on
    // a different platform is gated off here, so each target only pays
    // for what it actually needs.
    //
    //   isAd           : URL pattern matcher  — all platforms
    //   adGuard        : fetch/XHR/WS blocker — all platforms
    //   adRemoval      : DOM hide + window.open allowlist — all
    //   noSelectCss    : disable long-press callout — all
    //   bridge         : app ↔ page comms — all
    //   userActivity   : controls timer — all
    //   videoProgress  : progress tracking — all
    //   consoleKiller  : iOS + Windows (sites flood console)
    //   antiClickjack  : Windows ONLY (about:blank fallback gap in
    //                    WebView2; Android & iOS have reliable
    //                    shouldOverrideUrlLoading)
    //   suppressFullscreen: iOS ONLY (AVPlayer takeover)
    //   iosInlineVideo : iOS ONLY (WKWebView playsinline patch)
    return [
      // ── Cross-platform basics ───────────────────────────────────────
      // 1. URL block predicate (window.__spoviesIsAd). Used by the CSS-
      //    based ad block + window.open allowlist below, plus the
      //    Windows-only adGuard fetch/XHR wrapper. Defines a function;
      //    no side effects.
      UserScript(
        source: scripts.isAd,
        injectionTime: docStart,
        forMainFrameOnly: false,
      ),

      // 2. CSS-based ad/popup hider + single-line window.open allowlist.
      //    Safe by construction: no MutationObserver, no `getComputedStyle`
      //    sweep, no prototype patches. CSS applies to dynamically-added
      //    elements automatically. The window.open override is gated by
      //    `__spoviesIsAd` so legitimate popups (Cloudflare Turnstile,
      //    OAuth) pass through.
      UserScript(
        source: scripts.adRemoval,
        injectionTime: docStart,
        forMainFrameOnly: false,
      ),

      // 3. No long-press text-selection callout on the player surface.
      UserScript(
        source: scripts.noSelectCss,
        injectionTime: docStart,
        // Must reach cross-origin iframes — that's where streaming
        // sites host the actual <video> + caption overlay.
        forMainFrameOnly: false,
      ),

      // 4. Console mute — replaces `console.*` with no-ops so pages
      //    that flood the log (the `console.clear()` in a loop pattern)
      //    can't starve the UI thread. Trimmed, no defineProperty's.
      if (PlayerPlatform.needsConsoleKiller)
        UserScript(
          source: scripts.consoleKiller,
          injectionTime: docStart,
          forMainFrameOnly: false,
        ),

      // ── Platform-conditional ────────────────────────────────────────
      // 5. fetch/XHR/WebSocket ad blocker. Windows only — on Android/iOS
      //    the native `shouldInterceptRequest` already does this at the
      //    platform layer; running it twice has been observed breaking
      //    Cloudflare Turnstile and HLS shims.
      if (PlayerPlatform.needsAdGuardFetchPatch)
        UserScript(
          source: scripts.adGuard,
          injectionTime: docStart,
          forMainFrameOnly: false,
        ),
      // 6. Fullscreen API noop. iOS only — that's where WKWebView hands
      //    the <video> to a native AVPlayer overlay outside our control.
      if (PlayerPlatform.needsFullscreenSuppression)
        UserScript(
          source: scripts.suppressFullscreen,
          injectionTime: docStart,
          forMainFrameOnly: false,
        ),
      // 7. iOS inline-video attribute patch (iOS only).
      if (PlayerPlatform.needsIosInlineVideoFix)
        UserScript(
          source: scripts.iosInlineVideo,
          injectionTime: docStart,
          forMainFrameOnly: false,
        ),
      // 8. Android-only: hide the "Android WebView" brand from
      //    navigator.userAgentData. Light, single-defineProperty spoof
      //    — see PlayerPlatform.needsAndroidBrandHide.
      if (PlayerPlatform.needsAndroidBrandHide)
        UserScript(
          source: scripts.brandHide,
          injectionTime: docStart,
          forMainFrameOnly: false,
        ),

      // ── App-specific (always on) ────────────────────────────────────
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
