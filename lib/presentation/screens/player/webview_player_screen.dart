import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/user_progress.dart';
import '../../../plugins/event_bridge/event_bridge.dart';
import '../../providers/watch_history_providers.dart';

// ─── Bridge JS — injected at document-end, guarded by flag ───────────────────
//
// Forwards postMessage events from the page’s own scripts (e.g. Provider A’s
// PLAYER_EVENT) to the Dart side.  Kept as a supplementary source; the
// primary tracking is now in _kVideoProgressJs.

const _kBridgeJs = '''
(function() {
  if (window.__spoviesBridgeInit) return;
  window.__spoviesBridgeInit = true;
  window.addEventListener('message', function(e) {
    var d = (typeof e.data === 'string') ? e.data : JSON.stringify(e.data);
    if (d && window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('spoviesEventBridge', d);
    }
  });
})();
''';

// ─── Universal video progress tracking + auto-resume ─────────────────────
//
// Hooks directly into the HTML5 <video> element’s native events so watch
// progress is tracked for **every** plugin — not just those that emit their
// own postMessage events (like Provider A).
//
// Also handles auto-resume: if [resumeTime] > 0, the script seeks the
// <video> to that position as soon as the media metadata is loaded.
//
// IMPORTANT: this UserScript must be injected with `forMainFrameOnly: false`
// because streaming sites put their <video> inside cross-origin iframes.

String _videoProgressJs(double resumeTime) =>
    '''
(function() {
  if (window.__spoviesVideoTracker) return;
  window.__spoviesVideoTracker = true;

  var THROTTLE_MS = 3000;
  var lastSent = 0;
  var RESUME_TARGET = $resumeTime;
  var seekDone = false;

  function send(eventName, video) {
    if (!video || !video.duration || isNaN(video.duration)) return;
    var now = Date.now();
    if (eventName === 'timeupdate' && (now - lastSent) < THROTTLE_MS) return;
    lastSent = now;

    var progress = (video.currentTime / video.duration) * 100;
    var payload = JSON.stringify({
      type: 'PLAYER_EVENT',
      data: {
        event: eventName,
        currentTime: video.currentTime,
        duration: video.duration,
        progress: progress
      }
    });
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('spoviesEventBridge', payload);
    }
  }

  var patched = new WeakSet();

  function hookVideo(video) {
    if (patched.has(video)) return;
    patched.add(video);

    // --- progress tracking listeners ---
    ['timeupdate', 'play', 'pause', 'ended', 'seeked'].forEach(function(ev) {
      video.addEventListener(ev, function() { send(ev, video); });
    });

    // --- auto-resume seek ---
    if (RESUME_TARGET > 0 && !seekDone) {
      function doSeek() {
        if (seekDone) return;
        if (video.duration && video.duration > 0 && RESUME_TARGET < video.duration) {
          seekDone = true;
          video.currentTime = RESUME_TARGET;
        }
      }
      // Try immediately if metadata already loaded.
      if (video.readyState >= 1) {
        doSeek();
      } else {
        video.addEventListener('loadedmetadata', doSeek, { once: true });
      }
      // Safety net: also try on canplay in case loadedmetadata already fired.
      video.addEventListener('canplay', doSeek, { once: true });
    }
  }

  function scanDoc(root) {
    if (!root || !root.querySelectorAll) return;
    root.querySelectorAll('video').forEach(hookVideo);
  }

  scanDoc(document);

  var mo = new MutationObserver(function(mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var added = mutations[i].addedNodes;
      for (var j = 0; j < added.length; j++) {
        var node = added[j];
        if (node.nodeName === 'VIDEO') hookVideo(node);
        if (node.querySelectorAll) {
          node.querySelectorAll('video').forEach(hookVideo);
        }
      }
    }
  });
  mo.observe(document.documentElement, { childList: true, subtree: true });

  // Interval fallback: scan same-origin iframes every 2s.
  setInterval(function() {
    try {
      var frames = document.querySelectorAll('iframe');
      for (var i = 0; i < frames.length; i++) {
        try {
          var doc = frames[i].contentDocument || frames[i].contentWindow.document;
          scanDoc(doc);
        } catch(e) {}
      }
    } catch(e) {}
  }, 2000);
})();
''';

// ─── iOS inline-video fix — injected at document-start ───────────────────────
//
// On iOS, any <video> element that lacks the `playsinline` attribute is
// captured by the native AVPlayer full-screen overlay, killing the web-based
// player controls. This script:
//   1. Stamps `playsinline` + `webkit-playsinline` on every existing <video>.
//   2. Installs a MutationObserver so dynamically-injected <video> elements
//      (the norm for streaming sites) are patched before they can trigger the
//      native player.
//   3. Overrides `HTMLMediaElement.play` to re-apply the attributes on every
//      play attempt as a last-resort safety net.
//
// This is injected at AT_DOCUMENT_START so the observer is live before the
// page's own scripts run and add any <video> nodes.

const _kIosInlineVideoFix = '''
(function() {
  if (window.__spoviesInlineFixed) return;
  window.__spoviesInlineFixed = true;

  function patchVideo(v) {
    v.setAttribute('playsinline', '');
    v.setAttribute('webkit-playsinline', '');
    v.setAttribute('x-webkit-airplay', 'deny');
  }

  // Patch all videos present right now (usually none at document-start,
  // but safe to run anyway).
  document.querySelectorAll('video').forEach(patchVideo);

  // Watch for new video elements added by the streaming site's scripts.
  var mo = new MutationObserver(function(mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var nodes = mutations[i].addedNodes;
      for (var j = 0; j < nodes.length; j++) {
        var n = nodes[j];
        if (n.nodeName === 'VIDEO') { patchVideo(n); }
        if (n.querySelectorAll) {
          n.querySelectorAll('video').forEach(patchVideo);
        }
      }
    }
  });
  mo.observe(document.documentElement, { childList: true, subtree: true });

  // Last-resort: re-patch on every play() call, because some players
  // recreate the <video> element or strip attributes before calling play().
  var _origPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function() {
    patchVideo(this);
    return _origPlay.apply(this, arguments);
  };
})();
''';

// ─── Suppress native Fullscreen API — injected at document-start ─────────────
//
// Both iOS and Android WebViews intercept the Fullscreen API and hand the
// video to a native player overlay, which kills the web-based subtitle
// rendering and player controls.  This script no-ops every fullscreen
// entry-point so the video stays inside the WebView at all times.
// The player is already running in landscape immersive mode, so the user
// experience is effectively fullscreen without the native takeover.

const _kSuppressFullscreenJs = '''
(function() {
  if (window.__spoviesNoNativeFS) return;
  window.__spoviesNoNativeFS = true;

  // No-op all fullscreen entry points.
  Element.prototype.requestFullscreen = function() { return Promise.resolve(); };
  if (Element.prototype.webkitRequestFullscreen) {
    Element.prototype.webkitRequestFullscreen = function() {};
  }
  if (typeof HTMLVideoElement !== 'undefined') {
    var vp = HTMLVideoElement.prototype;
    if (vp.webkitEnterFullscreen)  vp.webkitEnterFullscreen  = function() {};
    if (vp.webkitEnterFullScreen)  vp.webkitEnterFullScreen  = function() {};
  }

  // Tell the page that fullscreen is not available, so players fall back
  // to their CSS-based "theater" / inline mode.
  Object.defineProperty(document, 'fullscreenEnabled',        { get: function() { return false; } });
  Object.defineProperty(document, 'webkitFullscreenEnabled',  { get: function() { return false; } });
})();
''';

// ─── CSS — injected at document-start ────────────────────────────────────────
// • Disables text selection & long-press callouts globally.
// • Constrains popup/dialog dimensions so they don't overflow on mobile.
// Does NOT touch pointer-events so scrollable lists remain fully interactive.

const _kNoSelectCss = '''
(function() {
  var s = document.createElement('style');
  s.textContent = [
    '* {',
    '  -webkit-user-select: none !important;',
    '  user-select: none !important;',
    '  -webkit-touch-callout: none !important;',
    '}',
    '.modal, .popup, [class*="dialog"], [class*="Dialog"],',
    '[class*="dropdown"], [class*="menu-popup"], [class*="select-menu"] {',
    '  max-height: 60vh !important;',
    '  max-width: 80vw !important;',
    '  overflow-y: auto !important;',
    '}',
  ].join('');
  (document.head || document.documentElement).appendChild(s);
})();
''';

// ─── Ad & popup removal JS — injected at document-end ─────────────────────────
//
// Removes common ad overlays, tracking iframes, and misbehaving click-jackers
// from the DOM.  A MutationObserver ensures dynamically-injected ads are caught
// throughout the page’s lifetime.

const _kAdRemovalJs = '''
(function() {
  if (window.__spoviesAdBlock) return;
  window.__spoviesAdBlock = true;

  // Comprehensive ad selectors — covers streaming-site overlay patterns.
  var adSelectors = [
    // --- iframes ---
    'iframe[src*="ads"]', 'iframe[src*="doubleclick"]',
    'iframe[src*="googlesyndication"]', 'iframe[src*="adservice"]',
    'iframe[src*="popads"]', 'iframe[src*="popcash"]',
    'iframe[src*="juicyads"]', 'iframe[src*="exoclick"]',
    'iframe[src*="trafficjunky"]', 'iframe[src*="propellerads"]',
    'iframe[src*="adsterra"]', 'iframe[src*="onclkds"]',
    'iframe[src*="onclickmax"]', 'iframe[src*="pushame"]',
    // --- div class/id patterns ---
    'div[class*="ad-overlay"]', 'div[class*="ad-container"]',
    'div[class*="ads-"]', 'div[class*="-ads"]',
    'div[class*="adsbygoogle"]', 'div[class*="ad-banner"]',
    'div[class*="ad_"]', 'div[id*="ad_"]',
    'div[class*="ads_"]', 'div[id*="ads_"]',
    'div[class*="popup"]', 'div[id*="popup"]',
    'div[class*="overlay-ad"]', 'div[id*="overlay-ad"]',
    'div[class*="banner-ad"]', 'div[class*="ad-banner"]',
    'div[class*="sticky-ad"]', 'div[class*="ad-sticky"]',
    'div[class*="ad-float"]', 'div[class*="float-ad"]',
    'div[class*="interstitial"]', 'div[class*="preroll"]',
    'div[class*="popunder"]', 'div[id*="popunder"]',
    'div[class*="modal-ad"]', 'div[class*="ad-modal"]',
    // --- generic overlay/click-jacker patterns ---
    'div[class*="overlay"][style*="z-index"]',
    'div[id*="overlay"][style*="z-index"]',
    // --- target blank + nofollow ---
    'a[target="_blank"][rel*="nofollow"]',
    'a[target="_blank"][href*="click"]',
    'a[target="_blank"][href*="track"]',
    '[onclick*="window.open"]',
    // --- ins (Google AdSense containers) ---
    'ins.adsbygoogle',
  ].join(',');

  function removeAds() {
    document.querySelectorAll(adSelectors).forEach(function(el) {
      el.remove();
    });
    // Remove fixed-position overlays that cover the entire viewport
    // (common click-jacker pattern) but skip the actual video player.
    document.querySelectorAll('div, section, aside').forEach(function(el) {
      var cs = window.getComputedStyle(el);
      if (cs.position === 'fixed' && cs.zIndex && parseInt(cs.zIndex) > 999) {
        // Skip if it contains a video element (it's the actual player).
        if (!el.querySelector('video') && !el.querySelector('iframe[src*="embed"]')) {
          el.remove();
        }
      }
    });
  }

  // Initial sweep.
  removeAds();

  // Watch for dynamically-injected ad elements.
  var mo = new MutationObserver(function() { removeAds(); });
  mo.observe(document.documentElement, { childList: true, subtree: true });

  // Periodic fallback sweep — catches ads injected via timers.
  setInterval(removeAds, 1500);

  // Neuter window.open so JS-driven popups are silently swallowed.
  window.open = function() { return null; };

  // Neuter document.createElement for ad iframes/scripts.
  var _origCreate = document.createElement.bind(document);
  document.createElement = function(tag) {
    var el = _origCreate(tag);
    if (tag.toLowerCase() === 'iframe') {
      // Override the src setter to block ad iframes.
      var _origSrc = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'src');
      if (_origSrc && _origSrc.set) {
        var origSet = _origSrc.set;
        Object.defineProperty(el, 'src', {
          set: function(v) {
            var blocked = ['ads','doubleclick','googlesyndication','popads',
                           'popcash','exoclick','trafficjunky','propellerads',
                           'adsterra','onclkds','onclickmax','juicyads'];
            for (var i = 0; i < blocked.length; i++) {
              if (v && v.indexOf(blocked[i]) !== -1) return;
            }
            origSet.call(this, v);
          },
          get: function() { return _origSrc.get ? _origSrc.get.call(this) : ''; }
        });
      }
    }
    return el;
  };
})();
''';

// ─── Anti click-jacking JS — injected at document-start ──────────────────────
//
// Intercepts click events at the capture phase to block popunder scripts
// and click-jacking overlays that redirect to ad pages.

const _kAntiClickjackJs = '''
(function() {
  if (window.__spoviesAntiCJ) return;
  window.__spoviesAntiCJ = true;

  // List of ad domain fragments to detect in href/action attributes.
  var adDomains = ['doubleclick','googlesyndication','popads','popcash',
    'exoclick','trafficjunky','propellerads','adsterra','juicyads',
    'onclkds','onclickmax','pushame','hilltopads','adtng','adrunnr',
    'adskeeper','clickadu','clickaine'];

  function isAdUrl(url) {
    if (!url) return false;
    for (var i = 0; i < adDomains.length; i++) {
      if (url.indexOf(adDomains[i]) !== -1) return true;
    }
    return false;
  }

  document.addEventListener('click', function(e) {
    var t = e.target;
    // Walk up to find an anchor.
    while (t && t.nodeName !== 'A' && t.nodeName !== 'BODY') {
      t = t.parentNode;
    }
    if (t && t.nodeName === 'A') {
      var href = t.getAttribute('href') || '';
      if (isAdUrl(href) || (t.target === '_blank' && isAdUrl(href))) {
        e.preventDefault();
        e.stopImmediatePropagation();
        return false;
      }
    }
  }, true);

  // Block popunder: intercept addEventListener on body/document for click
  // events that call window.open.
  var _origAEL = EventTarget.prototype.addEventListener;
  EventTarget.prototype.addEventListener = function(type, fn, opts) {
    if (type === 'click' && (this === document || this === document.body || this === window)) {
      // Wrap the listener to block window.open calls.
      var wrapped = function(e) {
        var _openBackup = window.open;
        window.open = function() { return null; };
        try { fn.call(this, e); } catch(ex) {}
        window.open = _openBackup;
      };
      return _origAEL.call(this, type, wrapped, opts);
    }
    return _origAEL.call(this, type, fn, opts);
  };
})();
''';

// Domain fragments used by shouldOverrideUrlLoading and
// shouldInterceptRequest to reject ad navigations and resource loads.
const _kBlockedDomainFragments = [
  // Google ads & tracking
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'adservice.google.',
  'pagead2.googlesyndication.com',
  'google-analytics.com',
  'analytics.google.com',
  // Yahoo / Oath
  'ads.yahoo.com',
  'advertising.com',
  // Major ad exchanges
  'adnxs.com',
  'adsrvr.org',
  'outbrain.com',
  'taboola.com',
  // Pop / redirect ad networks
  'popads.net',
  'popcash.net',
  'juicyads.com',
  'exoclick.com',
  'trafficjunky.com',
  'propellerads.com',
  'hilltopads.net',
  'adsterra.com',
  'revenuehits.com',
  'onclkds.com',
  'onclickmax.com',
  'pushame.com',
  'clickadu.com',
  'clickaine.com',
  'adtng.com',
  'adrunnr.com',
  'adskeeper.co.uk',
  'a-ads.com',
  'ad-maven.com',
  'admaven.co',
  'revcontent.com',
  'mgid.com',
  'bidvertiser.com',
  'richpush.co',
  'galaksion.com',
  'acint.net',
  // URL shorteners / link monetization
  'adf.ly',
  'shorte.st',
  'linkvertise.com',
  'bc.vc',
  'ouo.io',
  'sh.st',
  // Social trackers
  'facebook.net/tr',
  'connect.facebook.net',
  // Analytics / heatmaps
  'hotjar.com',
  'cdn.mouseflow.com',
  'clarity.ms',
  // Common streaming-site ad domains
  'betrad.com',
  'serving-sys.com',
  'yieldmanager.com',
  'cpmstar.com',
];

/// Full-screen WebView player.
///
/// Design decisions:
/// - **No full-body GestureDetector** — the previous swipe-to-dismiss
///   wrapper was claiming all vertical drags in Flutter's gesture arena
///   before the WebView could receive them, breaking internal list scrolling.
///   Dismiss is handled by the × button and the Android back button only.
/// - **`gestureRecognizers`** — explicitly transfers vertical drag, horizontal
///   drag, and scale gesture ownership to the WebView so Flutter widgets
///   above it never compete.
/// - **`gestureNavigationEnabled: false`** — disables iOS WebView's built-in
///   swipe-to-navigate-back, which would otherwise conflict with content
///   that needs horizontal swiping (e.g. carousels, tab bars inside the player).
/// - **Landscape lock** — `SystemChrome.setPreferredOrientations` is called
///   in `initState`; `dispose` fully restores portrait + system UI.
///   The iOS `Info.plist` already declares both landscape orientations so the
///   lock works identically on iOS and Android.
class WebViewPlayerScreen extends ConsumerStatefulWidget {
  final String url;
  final MediaItem media;
  final String pluginName;

  /// If > 0, the player will attempt to seek the <video> to this position
  /// (in seconds) once the page finishes loading.
  final double resumeTimeSeconds;

  const WebViewPlayerScreen({
    super.key,
    required this.url,
    required this.media,
    required this.pluginName,
    this.resumeTimeSeconds = 0,
  });

  @override
  ConsumerState<WebViewPlayerScreen> createState() =>
      _WebViewPlayerScreenState();
}

class _WebViewPlayerScreenState extends ConsumerState<WebViewPlayerScreen> {
  InAppWebViewController? _controller;
  late final EventBridge _eventBridge;

  int _loadProgress = 0;
  bool _hasError = false;
  String _errorMsg = '';

  // ─── Gesture recognizers — transferred to the WebView ────────────────────
  // Giving explicit ownership of these gestures to the WebView prevents the
  // Flutter widget tree from competing, which is the root cause of scroll
  // breakage in embedded lists.
  // NOTE: LongPressGestureRecognizer was intentionally removed — it causes
  // a ~500 ms delay in the gesture arena before taps are forwarded to the
  // WebView, making buttons appear to require a "double click".  The
  // _kNoSelectCss script already disables the browser's long-press context
  // menu, so there is no loss of functionality.
  static final _webViewGestures = <Factory<OneSequenceGestureRecognizer>>{
    Factory<VerticalDragGestureRecognizer>(VerticalDragGestureRecognizer.new),
    Factory<HorizontalDragGestureRecognizer>(
      HorizontalDragGestureRecognizer.new,
    ),
    Factory<ScaleGestureRecognizer>(ScaleGestureRecognizer.new),
  };

  @override
  void initState() {
    super.initState();
    _lockLandscape();
    _eventBridge = EventBridge(onProgressUpdate: _onProgressUpdate);
  }

  @override
  void dispose() {
    _restorePortrait();
    super.dispose();
  }

  // ─── Orientation ─────────────────────────────────────────────────────────

  void _lockLandscape() {
    // Works on Android and iOS (Info.plist already allows landscape).
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Immersive mode: hides nav bar + status bar for full viewport.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restorePortrait() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  // ─── Progress Tracking ───────────────────────────────────────────────────

  void _onProgressUpdate(PlayerEvent event) {
    if (event.duration <= 0) return;
    final progress = UserProgress(
      mediaId: widget.media.tmdbId.toString(),
      mediaType: widget.media.type.name,
      title: widget.media.title,
      posterPath: widget.media.posterPath,
      percentage: event.progress,
      currentTime: event.currentTime,
      duration: event.duration,
      season: event.season,
      episode: event.episode,
      lastPlayedDate: DateTime.now(),
    );
    ref.read(watchHistoryRepositoryProvider).saveProgress(progress);
    ref.invalidate(continueWatchingProvider);
  }

  // ─── Settings ────────────────────────────────────────────────────────────

  InAppWebViewSettings get _settings => InAppWebViewSettings(
    // Playback — inline is required so iOS does not hand off to AVPlayer.
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    // Disable PiP: entering Picture-in-Picture tears the video out of the
    // WebView context and hands it to AVPlayer, killing the web controls.
    allowsPictureInPictureMediaPlayback: false,

    // JavaScript & Storage
    javaScriptEnabled: true,
    domStorageEnabled: true,
    cacheEnabled: true,

    // ── Performance ──────────────────────────────────────────────────
    // GPU rendering on Android — biggest impact on scroll/video lag.
    hardwareAcceleration: true,
    // Skip expensive initial layout/zoom computations.
    useWideViewPort: false,
    loadWithOverviewMode: false,
    // Remove Android overscroll glow that triggers recompositing.
    overScrollMode: OverScrollMode.NEVER,
    // We show our own error state — skip the default error page.
    disableDefaultErrorPage: true,

    // Scroll & touch
    // NOTE: do NOT set isScrollEnabled: false — lists inside the player
    // depend on the WebView's native scroll.
    supportZoom: false,
    disableContextMenu: true,

    // iOS: disable swipe-back/forward navigation so it doesn't intercept
    // horizontal swipes inside the player UI (e.g. carousels, tab bars).
    allowsBackForwardNavigationGestures: false,

    // Rendering
    transparentBackground: false,

    // Reduce unnecessary resource tracking
    useOnLoadResource: false,

    // Enable network-level ad blocking via shouldInterceptRequest.
    useShouldInterceptRequest: true,

    // Enable multi-window support so onCreateWindow is called — we block
    // every popup attempt there.  Without this, some ad popups bypass the
    // WebView entirely and trigger external browser intents.
    supportMultipleWindows: true,

    // Block JavaScript from opening alert/confirm/prompt dialogs that ad
    // scripts abuse to prevent the user from closing the page.
    javaScriptCanOpenWindowsAutomatically: false,

    // NOTE: ContentBlocker rules were removed — on Android,
    // flutter_inappwebview's ContentBlockerHandler makes HTTP
    // connections to blocked domains to determine resource type,
    // causing ConnectException floods.  Ad blocking is handled by:
    //   1. shouldOverrideUrlLoading (blocks navigation)
    //   2. shouldInterceptRequest (blocks ad resource loads)
    //   3. _kAdRemovalJs (removes DOM elements)
    //   4. _kAntiClickjackJs (prevents click-jacking)
    //   5. onCreateWindow → false (blocks popups)
  );

  List<UserScript> get _userScripts => [
    // Must be AT_DOCUMENT_START so overrides are live before the streaming
    // site's own scripts execute.
    UserScript(
      source: _kSuppressFullscreenJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    UserScript(
      source: _kIosInlineVideoFix,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    UserScript(
      source: _kNoSelectCss,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    UserScript(
      source: _kBridgeJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
    ),
    // forMainFrameOnly: false — the <video> element is often inside a
    // cross-origin iframe.  This script must run in EVERY frame.
    UserScript(
      source: _videoProgressJs(widget.resumeTimeSeconds),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
      forMainFrameOnly: false,
    ),
    UserScript(
      source: _kAdRemovalJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
      forMainFrameOnly: false,
    ),
    // Anti click-jacking — must be AT_DOCUMENT_START to intercept
    // click handlers before ad scripts register them.
    UserScript(
      source: _kAntiClickjackJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    ),
  ];

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // No GestureDetector wrapper — touch events go directly to WebView.
        body: Stack(
          children: [
            _hasError ? _buildErrorState() : _buildWebView(),
            _buildLoadingOverlay(),
            _buildProgressBar(),
            _buildCloseButton(),
          ],
        ),
      ),
    );
  }

  // ─── WebView ─────────────────────────────────────────────────────────────

  Widget _buildWebView() {
    return InAppWebView(
      preventGestureDelay: true,
      gestureRecognizers: _webViewGestures,
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
      initialSettings: _settings,
      initialUserScripts: UnmodifiableListView(_userScripts),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'spoviesEventBridge',
          callback: (args) {
            if (args.isNotEmpty) {
              _eventBridge.handleMessage(args[0].toString());
            }
          },
        );
      },
      onProgressChanged: (controller, progress) {
        if (!mounted) return;
        setState(() {
          _loadProgress = progress;
          if (progress > 0 && _hasError) _hasError = false;
        });
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) {
          if (!mounted) return;
          setState(() {
            _hasError = true;
            _errorMsg = error.description;
          });
        }
      },
      onConsoleMessage: (controller, message) {
        if (kDebugMode) {
          // Filter out noisy streaming-site log spam.
          final msg = message.message;
          if (msg == 'undefined' || msg.startsWith('[object Object]')) return;
          debugPrint('WebView: $msg');
        }
      },
      // ── Block popup windows (ad popups) ────────────────────────────
      onCreateWindow: (controller, createWindowAction) async {
        // Return false to prevent ANY new window from opening.
        // Streaming players don't need popups; only ad scripts do.
        return false;
      },
      // ── Block navigation to ad domains ─────────────────────────────
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        for (final domain in _kBlockedDomainFragments) {
          if (url.contains(domain)) {
            return NavigationActionPolicy.CANCEL;
          }
        }
        return NavigationActionPolicy.ALLOW;
      },
      // ── Block ad resource loads at the network level ───────────────
      // Fires for every sub-resource (scripts, images, iframes).
      // Returning null allows the request; returning an empty
      // WebResourceResponse effectively blocks it.
      shouldInterceptRequest: (controller, request) async {
        final url = request.url.toString();
        for (final domain in _kBlockedDomainFragments) {
          if (url.contains(domain)) {
            return WebResourceResponse(contentType: 'text/plain', data: null);
          }
        }
        return null;
      },
    );
  }

  // ─── Progress Bar ─────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    if (_loadProgress >= 100 || _hasError) return const SizedBox.shrink();
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: LinearProgressIndicator(
        value: _loadProgress / 100,
        backgroundColor: Colors.white12,
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
        minHeight: 2,
      ),
    );
  }

  // ─── Initial Loading Overlay ──────────────────────────────────────────────

  Widget _buildLoadingOverlay() {
    // Only shown during the very first load (progress ≤ 15%).
    // Wrapped in IgnorePointer so taps pass through to the WebView
    // even while the spinner is visible — fixes laggy play button.
    if (_hasError || _loadProgress > 15) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }

  // ─── Error State ─────────────────────────────────────────────────────────

  Widget _buildErrorState() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Colors.white38,
                size: 56,
              ),
              const SizedBox(height: 16),
              const Text(
                'Failed to load player',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMsg,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Close Button ─────────────────────────────────────────────────────────

  Widget _buildCloseButton() {
    return Positioned(
      top: 12,
      right: 16,
      child: SafeArea(
        child: Material(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
            onTap: _dismiss,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  void _dismiss() {
    if (mounted) Navigator.pop(context);
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _loadProgress = 0;
    });
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.url)));
  }
}
