import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/host_utils.dart';
import '../../../core/utils/tmdb_image_url.dart';
import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/media_type.dart';
import '../../../domain/entities/user_progress.dart';
import '../../../plugins/event_bridge/event_bridge.dart';
import '../../../plugins/protocol/plugin_url_resolver.dart';
import '../../../plugins/protocol/trigger_hook.dart';
import '../../providers/plugin_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/watch_history_providers.dart';
import '../../providers/webview_providers.dart';
import '../../router/app_router.dart';
import '../../../data/services/remote_blocklist.dart';

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
    try {
      var data = e.data;
      if (!data) return;
      
      // Filter out common tracking/ad noise (Yandex Metrica, etc.)
      if (typeof data === 'string' && (data.startsWith('__ym') || data.startsWith('adscore'))) {
        return;
      }

      var d = (typeof data === 'string') ? data : JSON.stringify(data);
      if (d && window.flutter_inappwebview) {
        // Only forward if it looks like one of our events (PlayerEvent or activity)
        if (d.includes('"type"') || d.includes('"event"') || d.includes('"channel"')) {
          window.flutter_inappwebview.callHandler('spoviesEventBridge', d);
        }
      }
    } catch (ex) {}
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

// ─── Android WebView identity spoof — injected at document-start ─────────────
//
// Even when a custom desktop User-Agent string is set, Android WebView still
// injects `sec-ch-ua: "Android WebView"` HTTP headers AND exposes
// `navigator.userAgentData.brands` containing "Android WebView" to JavaScript.
// Many streaming sites (e.g. example.com) check these hints and either:
//   a) Serve a mobile HTML layout whose DOM is missing elements the desktop
//      player script expects → `null.addEventListener` crash, blank player.
//   b) Outright block or degrade the experience for detected WebViews.
//
// This script overrides `navigator.userAgentData` to present as a standard
// desktop Chrome browser.  It does NOT affect HTTP `sec-ch-ua` headers
// (those are set at the native layer), but covers all JS-side detections.

const _kSpoofUserAgentDataJs = '''
(function() {
  if (window.__spoviesUASpoof) return;
  window.__spoviesUASpoof = true;

  if (typeof navigator.userAgentData === 'undefined') return;

  var brands = [
    { brand: 'Not/A)Brand',  version: '8'   },
    { brand: 'Chromium',     version: '124' },
    { brand: 'Google Chrome', version: '124' }
  ];

  var spoofed = {
    brands:   brands,
    mobile:   false,
    platform: 'Windows',
    getHighEntropyValues: function(hints) {
      var r = {};
      for (var i = 0; i < hints.length; i++) {
        switch (hints[i]) {
          case 'brands':          r.brands          = brands;    break;
          case 'mobile':          r.mobile          = false;     break;
          case 'platform':        r.platform        = 'Windows'; break;
          case 'platformVersion': r.platformVersion = '15.0.0';  break;
          case 'uaFullVersion':   r.uaFullVersion   = '124.0.6367.60'; break;
          case 'architecture':    r.architecture    = 'x86';     break;
          case 'model':           r.model           = '';        break;
        }
      }
      return Promise.resolve(r);
    },
    toJSON: function() {
      return { brands: brands, mobile: false, platform: 'Windows' };
    }
  };

  try {
    Object.defineProperty(navigator, 'userAgentData', {
      get: function() { return spoofed; },
      configurable: true
    });
  } catch(e) {}
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

// ─── User Activity Tracker — injected at document-start ─────────────────────
//
// Detects mouse movement, touches, and key presses inside the WebView and
// relays them to Flutter to wake up the auto-hiding UI controls.
// This avoids putting a Flutter Listener over the WebView, which breaks
// native gesture routing on Android and Windows.
const _kUserActivityJs = '''
(function() {
  if (window.__spoviesActivityTracker) return;
  window.__spoviesActivityTracker = true;
  var THROTTLE_MS = 500;
  var lastSent = 0;
  function reportActivity() {
    var now = Date.now();
    if (now - lastSent < THROTTLE_MS) return;
    lastSent = now;
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('spoviesEventBridge', JSON.stringify({ type: 'USER_ACTIVITY' }));
    }
  }
  window.addEventListener('mousemove', reportActivity, { passive: true });
  window.addEventListener('touchstart', reportActivity, { passive: true });
  window.addEventListener('click', reportActivity, { passive: true });
  window.addEventListener('keydown', reportActivity, { passive: true });
})();
''';

// ─── Ad & popup removal JS — injected at document-end ─────────────────────────
//
// Removes common ad overlays, tracking iframes, and misbehaving click-jackers
// from the DOM.  A MutationObserver ensures dynamically-injected ads are caught
// throughout the page’s lifetime.

// ─── AdGuard-style Request Interceptor — injected at document-start ──────────
//
// Patches the browser's networking APIs (fetch and XHR) to block requests
// to known ad domains before they leave the WebView.  This mimics DNS-level
// blocking without the overhead of platform channel communication.

const String _kSpoviesIsAdJs = '''
  (function() {
    if (window.__spoviesIsAdReady) return;
    window.__spoviesIsAdReady = true;

    // JS-level instant blocklist for fetch/XHR/WebSocket interception.
    // The full ~35 k native blocklist (OISD / AdGuard / Steven Black) does
    // the heavy lifting in shouldInterceptRequest; this list is just a
    // belt-and-braces guard for substring matches that load before the
    // Dart side has had a chance to intercept.
    //
    // SUBSTRING MATCH FOOTGUN: every entry below is matched as a raw
    // substring against the *entire* URL. Generic words like \"ads\" must
    // never appear here — they trigger false positives on innocuous paths
    // (\"loads\", \"uploads\", \"headers\", \"payloads\", \"downloads\"…) and
    // can starve legitimate API endpoints. Legitimate streaming-host
    // domains (host-a / host-b / host-c / host-d / …) must never
    // appear either — many aggregators fetch their server menu through
    // those hosts, and blocking the fetch leaves the picker UI empty.
    var quickAds = [
      // Google ad stack
      'doubleclick.net', 'googlesyndication', 'adservice.google',
      'adsbygoogle',
      // Pop/popunder networks
      'popads.net', 'popcash.net', 'juicyads', 'exoclick',
      'trafficjunky', 'propellerads', 'adsterra', 'onclkds.com',
      'onclickmax', 'pushame', 'hilltopads', 'adtng', 'adrunnr',
      'adskeeper', 'clickadu', 'clickaine',
      // Aggressive ad redirector domains seen on streaming sites
      'gamerhit', 'trakzon', 'goosebomb', 'gryphline'
    ];

    window.__spoviesIsAd = function(url) {
      if (!url) return false;
      var s = url.toString().toLowerCase();
      for (var i = 0; i < quickAds.length; i++) {
        if (s.indexOf(quickAds[i]) !== -1) return true;
      }
      return false;
    };
  })();
''';

const String _kAdGuardJs = '''
    (function() {
      if (window.__spoviesAdGuard) return;
      window.__spoviesAdGuard = true;

      var isBlocked = window.__spoviesIsAd || function() { return false; };

      // 1. Patch Fetch API
      var _origFetch = window.fetch;
      window.fetch = function(input, init) {
        var url = (typeof input === 'string') ? input : (input && input.url);
        if (isBlocked(url)) {
          return Promise.reject(new TypeError('Blocked by Spovies AdGuard'));
        }
        return _origFetch.apply(this, arguments);
      };

      // 2. Patch XMLHttpRequest
      var _origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        if (isBlocked(url)) {
          this.__blocked = true;
          return;
        }
        return _origOpen.apply(this, arguments);
      };
      var _origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function() {
        if (this.__blocked) return;
        return _origSend.apply(this, arguments);
      };

      // 3. Patch sendBeacon (tracking)
      if (navigator.sendBeacon) {
        var _origBeacon = navigator.sendBeacon;
        navigator.sendBeacon = function(url, data) {
          if (isBlocked(url)) return true; 
          return _origBeacon.apply(this, arguments);
        };
      }

      // 4. Patch WebSocket
      var _origWS = window.WebSocket;
      window.WebSocket = function(url, protocols) {
        if (isBlocked(url)) {
          throw new Error('Blocked by Spovies AdGuard');
        }
        return new _origWS(url, protocols);
      };
      window.WebSocket.prototype = _origWS.prototype;
    })();
''';

const String _kConsoleKillerJs = '''
    (function() {
      // Brutally disable console functions to stop plugin event flood on Windows.
      // Many streaming sites use console.clear() in loops to detect/prevent devtools.
      var noOp = function() {};
      var originalConsole = window.console;
      if (originalConsole) {
        window.console.log = noOp;
        window.console.warn = noOp;
        window.console.error = noOp;
        window.console.debug = noOp;
        window.console.info = noOp;
        window.console.clear = noOp;
        window.console.table = noOp;
        window.console.count = noOp;
        window.console.dir = noOp;
      }
      
      // Attempt to bypass "DEVTOOL" detection by spoofing common checks.
      // Sites often check if outerWidth/Height matches innerWidth/Height.
      Object.defineProperty(window, 'outerWidth', { get: () => window.innerWidth });
      Object.defineProperty(window, 'outerHeight', { get: () => window.innerHeight });
      
      // Spoof webdriver property.
      Object.defineProperty(navigator, 'webdriver', { get: () => false });
    })();
  ''';

const _kAdRemovalJs = '''
(function() {
  if (window.__spoviesAdBlock) return;
  window.__spoviesAdBlock = true;

  // -------- Ad selectors --------
  //
  // SURGICAL ONLY. Generic UI words like \"popup\", \"modal\", or \"overlay\"
  // (without an `ad-` qualifier) are EXCLUDED on purpose — streaming-site
  // server-pickers, caption-pickers and quality-pickers virtually always
  // ship with class names like `server-popup` / `quality-modal` /
  // `caption-overlay`, and matching them shreds the player's own UI on
  // Android & iOS (mobile content mode). EasyList convention is the
  // template here: anchor every selector with `ad`, `ads`, `adsbygoogle`,
  // or a known ad-network identifier.
  var adSelectors = [
    // --- iframes ---
    'iframe[src*="doubleclick.net"]', 'iframe[src*="googlesyndication"]',
    'iframe[src*="adservice.google"]', 'iframe[src*="adsbygoogle"]',
    'iframe[src*="popads"]', 'iframe[src*="popcash"]',
    'iframe[src*="juicyads"]', 'iframe[src*="exoclick"]',
    'iframe[src*="trafficjunky"]', 'iframe[src*="propellerads"]',
    'iframe[src*="adsterra"]', 'iframe[src*="onclkds"]',
    'iframe[src*="onclickmax"]', 'iframe[src*="pushame"]',
    // --- AdSense / Google Tag ---
    'ins.adsbygoogle', 'div[id^="google_ads"]',
    'div[class*="adsbygoogle"]',
    // --- explicit ad containers (ad- / -ad / ads- / _ad_ / etc.) ---
    'div[class*="ad-overlay"]', 'div[class*="ad-container"]',
    'div[class*="ad-banner"]', 'div[class*="ad-banner-"]',
    'div[class*="ad-block"]', 'div[class*="ad-slot"]',
    'div[class*="ad-modal"]', 'div[class*="ad-popup"]',
    'div[class*="ad-wrapper"]', 'div[class*="ad-frame"]',
    'div[class*="ad-float"]', 'div[class*="ad-sticky"]',
    'div[class~="ads"]', 'div[id~="ads"]',
    'div[class*="banner-ad"]', 'div[class*="popup-ad"]',
    'div[class*="modal-ad"]', 'div[class*="float-ad"]',
    'div[class*="sticky-ad"]', 'div[class*="overlay-ad"]',
    'div[id*="ad-popup"]', 'div[id*="popup-ad"]',
    'div[id*="ad-overlay"]', 'div[id*="overlay-ad"]',
    // --- popunders (kept; \"popunder\" is virtually never legitimate UI) ---
    'div[class*="popunder"]', 'div[id*="popunder"]',
    // --- pre-roll / interstitial ad slots ---
    'div[class*="preroll-ad"]', 'div[class*="ad-preroll"]',
    'div[class*="interstitial-ad"]', 'div[class*="ad-interstitial"]',
    // --- anchor patterns specific to ad redirects ---
    'a[target="_blank"][rel*="nofollow"][href*="click"]',
    'a[target="_blank"][rel*="nofollow"][href*="track"]',
    'a[target="_blank"][href*="redirect.php"]',
  ].join(',');

  // -------- User-gesture tracking --------
  //
  // Click-jacker overlays usually appear *between* user gestures, while
  // legitimate UI (server menu, caption menu) appears as a direct result
  // of the user tapping a button. Recording the most recent user input
  // lets the fixed-position sweep skip elements that almost certainly
  // belong to the user's own interaction.
  var __lastUserInput = 0;
  ['pointerdown', 'mousedown', 'touchstart', 'click', 'keydown']
    .forEach(function(ev) {
      window.addEventListener(ev, function() {
        __lastUserInput = Date.now();
      }, { capture: true, passive: true });
    });

  // -------- Legitimate-UI heuristic --------
  //
  // The ARIA role list is taken from the WAI-ARIA \"widget\" roles plus
  // common implicit dialog patterns. Elements containing interactive
  // children are also exempt — popunders almost never have form controls
  // or menu items inside them.
  var __uiRoles = {
    dialog: 1, alertdialog: 1, menu: 1, menubar: 1,
    listbox: 1, combobox: 1, tablist: 1, tabpanel: 1,
    tooltip: 1, tree: 1, treeitem: 1, grid: 1, group: 1
  };
  var __interactiveQ = 'button, select, input, textarea,' +
    ' [role="button"], [role="menuitem"], [role="option"],' +
    ' [role="tab"], [role="checkbox"], [role="radio"]';

  function isLikelyUserUi(el) {
    var role = (el.getAttribute('role') || '').toLowerCase();
    if (__uiRoles[role]) return true;
    if (el.querySelector(__interactiveQ)) return true;
    if (el.hasAttribute('aria-modal')) return true;
    // Recently-appeared element following a user tap is almost certainly
    // a user-initiated menu/dialog, not a popunder.
    if (Date.now() - __lastUserInput < 1500) return true;
    return false;
  }

  function removeAds() {
    var style = 'display:none!important;visibility:hidden!important;pointer-events:none!important;opacity:0!important;width:0px!important;height:0px!important;';

    document.querySelectorAll(adSelectors).forEach(function(el) {
      if (el.style.display !== 'none') {
        el.setAttribute('style', style);
      }
    });

    // Heuristic fixed-position sweep — only catches click-jackers that
    // slipped past the selector list. The threshold is z-index >= 1000:
    // legitimate menus & dialogs on streaming sites typically sit in the
    // 100-999 range, while click-jacker overlays use 9999+.
    document.querySelectorAll('div, section, aside').forEach(function(el) {
      if (el.getAttribute('data-spovies') === 'handled') return;
      var cs = window.getComputedStyle(el);
      if (cs.position !== 'fixed') return;
      var z = parseInt(cs.zIndex, 10);
      if (!z || z < 1000) return;
      // Skip the actual video player and anything containing it.
      if (el.querySelector('video') ||
          el.querySelector('iframe[src*="embed"]')) return;
      // Skip user UI (ARIA roles, interactive children, recent gesture).
      if (isLikelyUserUi(el)) return;
      el.setAttribute('style', style);
      el.setAttribute('data-spovies', 'handled');
    });
  }

  removeAds();

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
      var _origSrc = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'src');
      if (_origSrc && _origSrc.set) {
        var origSet = _origSrc.set;
        Object.defineProperty(el, 'src', {
          set: function(v) {
            var isBlocked = window.__spoviesIsAd || function() { return false; };
            if (isBlocked(v)) return;
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

  var isAdUrl = window.__spoviesIsAd || function() { return false; };

  // ── 1. Block <a> clicks to known ad domains and about:blank ──────────
  //
  // Only reject anchors whose destination href matches a known ad pattern
  // OR is the empty-page click-jacker. `about:blank` anchors overlaid on
  // the player are how some streaming sites blank out the main frame when
  // the user taps — onCreateWindow returns false on the Dart side, but
  // Windows WebView2's fallback is to load the link in the current frame,
  // killing playback. Catching it here prevents the navigation from being
  // dispatched at all.
  //
  // Real user-initiated `target=\"_blank\"` clicks are still allowed —
  // popup creation is blocked at the native onCreateWindow layer.
  function isBlankishHref(h) {
    if (!h) return true; // empty href = same-page anchor or click-jacker stub
    var s = h.toLowerCase().trim();
    return s === 'about:blank' || s === '#' || s === 'javascript:void(0)' ||
           s === 'javascript:void(0);' || s.indexOf('about:') === 0;
  }
  document.addEventListener('click', function(e) {
    var t = e.target;
    while (t && t.nodeName !== 'A' && t.nodeName !== 'BODY') {
      t = t.parentNode;
    }
    if (t && t.nodeName === 'A') {
      var href = t.getAttribute('href') || '';
      var target = (t.getAttribute('target') || '').toLowerCase();
      // about:blank / javascript:void(0) + target=_blank is the canonical
      // click-jacker overlay shape — kill it. Pure same-page `#` anchors
      // without target=_blank are left alone (legitimate scroll links).
      if (isAdUrl(href) ||
          (isBlankishHref(href) && target === '_blank')) {
        e.preventDefault();
        e.stopImmediatePropagation();
        return false;
      }
    }
  }, true);

  // ── 2. Block window.open / popunder via wrapped click listeners ───────
  var _origAEL = EventTarget.prototype.addEventListener;
  EventTarget.prototype.addEventListener = function(type, fn, opts) {
    if (type === 'click' && (this === document || this === document.body || this === window)) {
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

  // ── 3. Block Location.prototype navigations ───────────────────────────
  //
  // The "skip button opens an ad" pattern most commonly works by placing
  // a transparent div over the skip button whose onclick calls
  // location.assign() or location.replace() with an ad URL.
  // shouldOverrideUrlLoading on Android does NOT reliably fire for all
  // programmatic same-page navigations, so we patch them in JS too.
  //
  // We block:
  //  a. Known ad domains (as above)
  //  b. Any non-http(s) scheme (intent://, market://, fb:// etc.) —
  //     these are Android deep-link tricks that open external apps.

  function isSuspiciousNavigation(url) {
    if (!url) return false;
    var s = url.toString();
    // Block non-standard schemes — the player only needs http/https/blob/data.
    var scheme = s.split(':')[0].toLowerCase();
    if (scheme !== 'http' && scheme !== 'https' &&
        scheme !== 'blob' && scheme !== 'data' &&
        scheme !== 'about' && scheme !== 'javascript') {
      return true;
    }
    
    // Check known ad domains quickly
    if (isAdUrl(s)) return true;

    // Aggressive click-hijack prevention:
    // If JS is trying to navigate the main frame to a completely different domain,
    // block it. The player should never navigate away from itself programmatically.
    try {
      var newUrl = new URL(s, window.location.href);
      if (newUrl.protocol === 'about:' || newUrl.protocol === 'data:') {
         return true; // Programmatic navigation to about:blank or data: is blocked
      }

      var currentHost = window.location.hostname;
      var newHost = newUrl.hostname;
      
      var getBase = function(h) {
        var p = h.split('.');
        if (p.length < 2) return h;
        return p[p.length - 2] + '.' + p[p.length - 1];
      };
      
      if (currentHost && newHost && getBase(currentHost) !== getBase(newHost)) {
         return true; // Block cross-domain hijack!
      }
    } catch(e) {}

    return false;
  }

  var _origAssign = Location.prototype.assign;
  Location.prototype.assign = function(url) {
    if (isSuspiciousNavigation(url)) return;
    return _origAssign.apply(this, arguments);
  };

  var _origReplace = Location.prototype.replace;
  Location.prototype.replace = function(url) {
    if (isSuspiciousNavigation(url)) return;
    return _origReplace.apply(this, arguments);
  };

  // ── 4. Catch setTimeout-delayed navigations that bypass click checks ──
  //
  // Some ad scripts do: elem.onclick = function() { setTimeout(function() {
  //   location.href = 'ad-url'; }, 0); }
  // The click interceptor above (step 1) doesn't block this because the
  // navigation is scheduled asynchronously.  We catch it by also patching
  // the href setter on the location object.
  try {
    var locProto = Location.prototype;
    var origHrefDescriptor = Object.getOwnPropertyDescriptor(locProto, 'href');
    if (origHrefDescriptor && origHrefDescriptor.set) {
      var origSet = origHrefDescriptor.set;
      Object.defineProperty(locProto, 'href', {
        get: origHrefDescriptor.get,
        set: function(url) {
          if (isSuspiciousNavigation(url)) return;
          origSet.call(this, url);
        },
        configurable: true,
      });
    }
  } catch(e) {
    // Location.prototype may not be patchable on all WebView versions; safe to ignore.
  }

  // ── 5. Neuter programmatic clicks on unattached links and forms ──
  //
  // Drop the blanket `target === '_blank'` reject for the same reason as
  // step 1 — many player UIs script `<a target=\"_blank\">.click()` to open
  // server choices; popup creation itself is already blocked natively.
  var _origAnchorClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function() {
    if (isAdUrl(this.href) || isSuspiciousNavigation(this.href)) return;
    return _origAnchorClick.apply(this, arguments);
  };

  var _origFormSubmit = HTMLFormElement.prototype.submit;
  HTMLFormElement.prototype.submit = function() {
    if (isAdUrl(this.action) || isSuspiciousNavigation(this.action)) return;
    return _origFormSubmit.apply(this, arguments);
  };
})();
''';

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

  /// Plugin ID for saving as [UserProgress.lastPluginId] when progress is saved.
  final String? pluginId;

  /// If > 0, the player will attempt to seek the <video> to this position
  /// (in seconds) once the page finishes loading.
  final double resumeTimeSeconds;

  /// For TV episodes — used when the bridge event has null season/episode.
  final int? season;
  final int? episode;

  const WebViewPlayerScreen({
    super.key,
    required this.url,
    required this.media,
    required this.pluginName,
    this.pluginId,
    this.resumeTimeSeconds = 0,
    this.season,
    this.episode,
  });

  @override
  ConsumerState<WebViewPlayerScreen> createState() =>
      _WebViewPlayerScreenState();
}

class _WebViewPlayerScreenState extends ConsumerState<WebViewPlayerScreen>
    with WidgetsBindingObserver {
  double _loadProgress = 0;
  bool _isNavigating = false;

  /// `true` when this screen is being torn down because the user pressed
  /// "Play Next" — i.e. we're handing off to another `/player` route.
  ///
  /// `dispose()` consults this to decide whether to call `_restorePortrait`.
  /// On iOS, route transition + dispose ordering means the OLD screen's
  /// `_restorePortrait` would otherwise queue `setPreferredOrientations`
  /// for portrait *after* the NEW screen's `_lockLandscape` had already
  /// queued landscape — iOS honours the most recent preference and forces
  /// a rotation to portrait under the new player. Skipping the restore on
  /// handoff keeps the device in landscape across episodes.
  bool _navigatingToAnotherPlayer = false;

  EventBridge? _eventBridge;

  // Stored so imperative operations (reload, goBack, etc.) are possible.
  InAppWebViewController? _controller;

  bool _hasError = false;
  String _errorMsg = '';
  bool _isFullScreen = false;

  Timer? _controlsTimer;
  bool _showControls = true;

  bool _showNextEpisodeOverlay = false;
  bool _overlayActive = false; // Controls animation (slide/fade)
  bool _dismissedNextEpisodeOverlay = false;
  int? _lastNextEpisodeTriggered; // episode number to avoid repeat popups
  Timer? _overlayTimer;

  /// Delay between the iOS 16+ "supported orientations" relaxation call and
  /// the actual landscape lock. Without it, the second
  /// `setPreferredOrientations` call can land before the system has finished
  /// committing the first, producing the *"None of the requested
  /// orientations are supported"* runtime error.
  ///
  /// 50 ms has held up reliably on iPhones from XS through 15 Pro; bump this
  /// (or switch to `addPostFrameCallback`) if the error reappears on slower
  /// devices.
  static const Duration _kIosOrientationCommitDelay =
      Duration(milliseconds: 50);

  /// Latches `true` the first time the main frame finishes loading. Once set,
  /// any subsequent main-frame navigation is checked against the original
  /// host base — even if `_loadProgress` has dropped to 0 because the
  /// navigation that's being inspected is itself the redirect. Without this
  /// latch, programmatic `location.assign('evil.com')` calls slip through
  /// the cross-domain gate during the brief window when progress is < 100.
  bool _initialLoadComplete = false;

  /// Cached "base" of the originally requested URL's host (e.g. `example.com`
  /// for `https://www.example.com/embed/123`). Computed once in [initState] so
  /// every navigation check is an O(1) string compare.
  ///
  /// Backed by the Public Suffix List (see [HostUtils]) so multi-part TLDs
  /// like `foo.co.uk` are handled correctly.
  late final String _initialHostBase = HostUtils.registeredDomain(
    Uri.tryParse(widget.url)?.host ?? '',
  );

  /// Stable cache key for [nextEpisodeForProgressProvider] — only mediaId,
  /// mediaType, season, episode participate in `UserProgress.==`/`hashCode`,
  /// so we don't need to allocate a new instance per build with a fresh
  /// `DateTime.now()`. Hoisted into a field to remove allocator pressure
  /// from the player-chrome rebuild hot path.
  late final UserProgress _nextEpisodeKey = UserProgress(
    mediaId: widget.media.tmdbId.toString(),
    mediaType: 'tv',
    title: widget.media.title,
    percentage: 100,
    currentTime: 0,
    duration: 0,
    season: widget.season,
    episode: widget.episode,
    lastPlayedDate: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Cached `ProviderContainer` for use inside `dispose()`.
  ///
  /// Riverpod 3.x throws
  /// `Bad state: Using "ref" when a widget is about to or has been unmounted`
  /// if `ref` is touched during `dispose()` — `ref` depends on
  /// `BuildContext`, which is being deactivated. The framework's own
  /// error message points to the fix: cache the `ProviderContainer` in a
  /// field while the widget is still active and call `.invalidate(...)`
  /// on it directly.
  ///
  /// Captured in `initState` with `listen: false` so we don't register an
  /// InheritedWidget dependency that would cause `didChangeDependencies`
  /// to fire (and re-assign a `late final` — the previous source of the
  /// `LateInitializationError`).
  late final ProviderContainer _providerContainer;

  // ─── Gesture recognizers — transferred to the WebView ────────────────────
  // Giving explicit ownership of these gestures to the WebView prevents the
  // Flutter widget tree from competing, which is the root cause of scroll
  // breakage in embedded lists.
  // NOTE: LongPressGestureRecognizer was intentionally removed — it causes
  // a ~500 ms delay in the gesture arena before taps are forwarded to the
  // WebView, making buttons appear to require a "double click" to interact.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Cache the ProviderContainer NOW (widget is mounted, context is
    // active) so dispose() can call .invalidate() without touching `ref`.
    // `listen: false` uses `getElementForInheritedWidgetOfExactType` under
    // the hood, which — unlike `dependOnInheritedWidgetOfExactType` — is
    // safe in `initState` and doesn't register a dependency that would
    // make `didChangeDependencies` fire later.
    _providerContainer = ProviderScope.containerOf(context, listen: false);

    // Fail-closed if the route handed us a URL with no resolvable host —
    // otherwise `_initialHostBase` is empty and the cross-domain navigation
    // guard at the bottom of `shouldOverrideUrlLoading` silently disables
    // itself, letting any cross-frame redirect through.
    final initialHost = Uri.tryParse(widget.url)?.host ?? '';
    if (initialHost.isEmpty) {
      _hasError = true;
      _errorMsg = 'Invalid stream URL (no host)';
      return;
    }

    // Delay the orientation lock until after the first frame on iOS to
    // prevent race conditions with the screen transition.
    if (Platform.isIOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lockLandscape();
      });
    } else {
      _lockLandscape();
    }

    _eventBridge = EventBridge(onProgressUpdate: _onProgressUpdate);
    if (Platform.isWindows) {
      _checkFullScreen();
    }
    _resetControlsTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // The WebView's JS bridge only forwards a `pause` event when the
    // streaming provider's <video> element itself fires `pause` — that's
    // unreliable across plugins (HLS.js wrappers, custom MSE, etc.). When
    // the OS sends us to the background we flush the Continue Watching row
    // ourselves so the Home screen reflects the latest saved progress on
    // the way back in.
    //
    // Uses the cached `_providerContainer` — same rationale as in dispose:
    // the lifecycle callback can race with widget deactivation, and `ref`
    // throws once the BuildContext is unmounted.
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden) &&
        _progressDirty) {
      _providerContainer.invalidate(continueWatchingProvider);
      _providerContainer.invalidate(episodeProgressProvider);
      _progressDirty = false;
    }
  }

  void _resetControlsTimer() {
    if (!mounted) return;

    // The hot path: pointer move + JS user-activity events fire continuously.
    // The JS bridge already throttles to 500 ms, but we still get pointer
    // moves on every frame on Windows/desktop. Only call setState when
    // something actually needs to change — otherwise we're scheduling an
    // entire rebuild of the player chrome on every mouse twitch.
    final overlayShouldShow =
        _showNextEpisodeOverlay && !_dismissedNextEpisodeOverlay;
    final overlayNeedsUpdate = overlayShouldShow && !_overlayActive;

    if (!_showControls || overlayNeedsUpdate) {
      setState(() {
        _showControls = true;
        if (overlayNeedsUpdate) {
          _overlayActive = true;
          _startOverlayTimer();
        }
      });
    }

    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _startOverlayTimer() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _overlayActive) {
        setState(() => _overlayActive = false);
      }
    });
  }

  Future<void> _checkFullScreen() async {
    final isFullscreen = await windowManager.isFullScreen();
    if (mounted) setState(() => _isFullScreen = isFullscreen);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
    _overlayTimer?.cancel();
    _cleanupWebView();
    // If progress was written during this session but never flushed via a
    // pause/ended event (e.g. the user just closed the player), refresh
    // the Continue Watching row once on the way out.
    //
    // Use the cached `_providerContainer` directly — `ref.invalidate(...)`
    // here throws `Bad state: Using "ref" when a widget is about to or has
    // been unmounted is unsafe` in Riverpod 3.x because `ref` depends on
    // the deactivating BuildContext.
    if (_progressDirty) {
      _providerContainer.invalidate(continueWatchingProvider);
      _providerContainer.invalidate(episodeProgressProvider);
    }
    // Skip the orientation restore when handing off to another player —
    // see [_navigatingToAnotherPlayer] for the iOS race this avoids.
    if (!_navigatingToAnotherPlayer) {
      _restorePortrait();
    }
    super.dispose();
  }

  /// Centralized cleanup to ensure the WebView stops all background work.
  /// Called before navigation and during disposal.
  void _cleanupWebView() {
    final controller = _controller;
    if (controller != null) {
      // Windows is sensitive to imperative calls during disposal transitions.
      // We nullify the reference and let the native platform view dispose itself.
      if (!Platform.isWindows) {
        controller.stopLoading();
      }
      _controller = null;
    }
  }

  // ─── Orientation ─────────────────────────────────────────────────────────

  Future<void> _lockLandscape() async {
    // Orientation lock and immersive mode are mobile-only APIs.
    if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return;
    }

    if (Platform.isIOS) {
      // First, relax the supported set so iOS 16+ doesn't reject the
      // landscape-only call below with "None of the requested orientations
      // are supported".
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);
      await Future.delayed(_kIosOrientationCommitDelay);
    }

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Immersive mode: hides nav bar + status bar for full viewport.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _restorePortrait() async {
    if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return;
    }
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  // ─── Progress Tracking ───────────────────────────────────────────────────

  /// Tracks whether anything has been persisted this session so we know to
  /// invalidate the Continue Watching list once on lifecycle events.
  bool _progressDirty = false;

  void _onProgressUpdate(PlayerEvent event) {
    if (!mounted) return;
    if (event.duration <= 0) return;

    final progress = UserProgress(
      mediaId: widget.media.tmdbId.toString(),
      mediaType: widget.media.type.name,
      title: widget.media.title,
      posterPath: widget.media.posterPath,
      percentage: event.progress,
      currentTime: event.currentTime,
      duration: event.duration,
      season: event.season ?? widget.season,
      episode: event.episode ?? widget.episode,
      lastPlayedDate: DateTime.now(),
      lastPluginId: widget.pluginId,
    );

    // Fire-and-forget write with explicit error handling so a Hive write
    // failure can't escape as an unhandled async error.
    unawaited(
      ref
          .read(watchHistoryRepositoryProvider)
          .saveProgress(progress)
          .catchError((Object e, StackTrace st) {
            if (kDebugMode) debugPrint('saveProgress failed: $e');
          }),
    );
    _progressDirty = true;

    // Invalidate the Continue Watching row only on pause/ended — the
    // throttled timeupdate fires every ~5s during playback and used to
    // rebuild the home screen continuously. The repository write above
    // still happens every update so progress survives a crash.
    final isLifecycle =
        event.eventType == 'pause' || event.eventType == 'ended';
    if (isLifecycle) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(episodeProgressProvider);
      _progressDirty = false;
    }

    // PlayerEvent.tryParse normalises progress to the 0–100 scale at the
    // parse boundary, so we use it directly here. The previous
    // "if (progress <= 1.0) *= 100" heuristic mis-fired at <1 % real
    // progress (e.g. 0.83 % → 83 %) and triggered the Next-Episode
    // overlay seconds into playback.
    final currentEp = event.episode ?? widget.episode;
    final pct = event.progress;

    if (widget.media.type == MediaType.tv && pct >= 95.0) {
      if (!_showNextEpisodeOverlay &&
          !_dismissedNextEpisodeOverlay &&
          _lastNextEpisodeTriggered != currentEp) {
        // _lastNextEpisodeTriggered is bookkeeping (read only in this method,
        // never in build) — assigning it inside setState is just convenient
        // grouping with _showNextEpisodeOverlay/_overlayActive which DO drive
        // the overlay's visibility.
        setState(() {
          _showNextEpisodeOverlay = true;
          _overlayActive = true;
          _lastNextEpisodeTriggered = currentEp;
          _startOverlayTimer();
        });
      }
    } else {
      // Reset dismissal + trigger-tracking when the user has scrubbed back
      // far enough to "re-arm" the overlay for this episode. Neither field
      // is read in build, so plain assignment is correct — wrapping in
      // setState would schedule a rebuild that does nothing.
      if (pct < 90.0) {
        _dismissedNextEpisodeOverlay = false;
        _lastNextEpisodeTriggered = null;
      }

      if (_showNextEpisodeOverlay && pct < 95.0) {
        _overlayTimer?.cancel();
        setState(() {
          _showNextEpisodeOverlay = false;
          _overlayActive = false;
        });
      }
    }
  }

  // ─── Settings ────────────────────────────────────────────────────────────

  InAppWebViewSettings get _settings => InAppWebViewSettings(
    // User-Agent & Content Mode.
    //
    // Windows & Android → Desktop Chrome UA + DESKTOP content mode.
    // Streaming embed sites (e.g. example.com, example.*) serve their desktop
    // player layout when they see a desktop UA.  The mobile layout is often
    // missing player DOM elements that the site's own JS expects, causing
    // `null.addEventListener` crashes and a blank/broken player on Android.
    //
    // iOS → Mobile Safari UA + MOBILE content mode.
    // iOS playback works correctly in mobile mode thanks to `allowsInlineMediaPlayback`
    // and the `_kIosInlineVideoFix` script.  Switching iOS to desktop mode can
    // break `playsinline` behaviour on WKWebView.
    userAgent: Platform.isIOS
        ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
        : Platform.isAndroid
        ? 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36'
        : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36',

    preferredContentMode: Platform.isIOS || Platform.isAndroid
        ? UserPreferredContentMode.MOBILE
        : UserPreferredContentMode.DESKTOP,

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
    // NOTE: Disabled on Android by default to prevent black screen rendering
    // issues on specific GPUs (Xiaomi/Redmi) when using Impeller.
    hardwareAcceleration: !Platform.isAndroid,
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
    transparentBackground: true,

    // Allow mixed content for maximal provider compatibility.
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,

    // Reduce unnecessary resource tracking
    useOnLoadResource: false,

    // Enable network-level ad blocking via shouldInterceptRequest.
    // Extremely slow on Windows due to platform channel overhead for every HLS video chunk.
    useShouldInterceptRequest: !Platform.isWindows,

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
    // 0. Inject instant block heuristic for JS level blocking.
    UserScript(
      source: _kSpoviesIsAdJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    ),
    // 1. Android: Spoof navigator.userAgentData ASAP so any inline scripts that
    //    run at document-start see a regular Chrome identity, not "Android WebView".
    //    Applied before all other scripts so site feature-detection runs against
    //    the spoofed data.
    if (Platform.isAndroid)
      UserScript(
        source: _kSpoofUserAgentDataJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
    // 2. Spovies AdGuard (DNS-level block replacement).
    UserScript(
      source: _kAdGuardJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    ),
    // 3. Suppress console and spoof devtool checks ASAP.
    if (!Platform.isAndroid)
      UserScript(
        source: _kConsoleKillerJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
    // 4. Block ad scripts and popups (Cross-platform).
    UserScript(
      source: _kAdRemovalJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    ),
    // 3. Block click-jacking.
    UserScript(
      source: _kAntiClickjackJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    ),
    // 4. Styling and general fixes.
    // forMainFrameOnly: false — streaming sites embed their <video> in
    // cross-origin iframes; fullscreen suppression and inline-video fixes
    // must run inside those frames to be effective.
    UserScript(
      source: _kSuppressFullscreenJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    ),
    UserScript(
      source: _kIosInlineVideoFix,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    ),
    UserScript(
      source: _kNoSelectCss,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    // 5. App-specific bridge, activity tracking, and progress tracking
    UserScript(
      source: _kBridgeJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
      forMainFrameOnly: false,
    ),
    UserScript(
      source: _kUserActivityJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    ),
    UserScript(
      source: _videoProgressJs(widget.resumeTimeSeconds),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
      forMainFrameOnly: false,
    ),
  ];

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (Platform.isWindows) {
      final envAsync = ref.watch(webViewEnvironmentProvider);
      content = envAsync.when(
        data: (env) {
          if (_hasError) return _buildErrorState();
          return _buildWebView(env);
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        // Render the error state directly without mutating widget state during
        // build — that would either trigger a setState-in-build assertion or
        // permanently latch _hasError, leaving the screen stuck if the env
        // provider later recovers. Retry simply invalidates the provider.
        error: (err, _) => _buildErrorState(
          overrideMessage: 'WebView initialization failed: $err',
          onRetry: () => ref.invalidate(webViewEnvironmentProvider),
        ),
      );
    } else {
      content = _hasError ? _buildErrorState() : _buildWebView();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _resetControlsTimer(),
          child: Listener(
            onPointerDown: (_) => _resetControlsTimer(),
            onPointerMove: (_) => _resetControlsTimer(),
            behavior: HitTestBehavior.translucent,
            child: Stack(
              children: [
                content,
                _buildLoadingOverlay(),
                _buildProgressBar(),
                _buildWindowActions(),
                _buildNextEpisodeOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── WebView ─────────────────────────────────────────────────────────────

  Widget _buildWebView([WebViewEnvironment? environment]) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.expand();
        }

        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            // Always allow system volume keys to bubble up.
            if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
                event.logicalKey == LogicalKeyboardKey.audioVolumeDown ||
                event.logicalKey == LogicalKeyboardKey.audioVolumeMute) {
              return KeyEventResult.ignored;
            }

            // Ignore modifier keys to prevent Flutter's internal state tracker
            // from getting desynchronized (fixes "Alt Left" assertion crash).
            if (event.logicalKey == LogicalKeyboardKey.altLeft ||
                event.logicalKey == LogicalKeyboardKey.altRight ||
                event.logicalKey == LogicalKeyboardKey.controlLeft ||
                event.logicalKey == LogicalKeyboardKey.controlRight ||
                event.logicalKey == LogicalKeyboardKey.shiftLeft ||
                event.logicalKey == LogicalKeyboardKey.shiftRight) {
              return KeyEventResult.ignored;
            }

            // On Windows, we must return .handled for all other keys to prevent
            // the WebView from triggering framework assertions during layout.
            // On other platforms (Android/iOS), we return .ignored so system
            // and hardware keys work naturally.
            return Platform.isWindows
                ? KeyEventResult.handled
                : KeyEventResult.ignored;
          },
          child: InAppWebView(
            // Full URL (not hashCode) — String hashCode collides, and a
            // collision here causes the framework to reuse the previous
            // WebView state for a different URL.
            key: ValueKey('spovies_player_${widget.url}'),
            webViewEnvironment: environment,
            preventGestureDelay: true,
            gestureRecognizers:
                (!kIsWeb &&
                    (Platform.isWindows ||
                        Platform.isMacOS ||
                        Platform.isLinux))
                ? const <Factory<OneSequenceGestureRecognizer>>{}
                : <Factory<OneSequenceGestureRecognizer>>{
                    Factory<VerticalDragGestureRecognizer>(
                      VerticalDragGestureRecognizer.new,
                    ),
                    Factory<HorizontalDragGestureRecognizer>(
                      HorizontalDragGestureRecognizer.new,
                    ),
                    Factory<ScaleGestureRecognizer>(ScaleGestureRecognizer.new),
                  },
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: _settings,
            initialUserScripts: UnmodifiableListView(_userScripts),
            onWebViewCreated: (controller) {
              _controller = controller;
              controller.addJavaScriptHandler(
                handlerName: 'spoviesEventBridge',
                callback: (args) {
                  if (args.isNotEmpty) {
                    final rawMessage = args[0].toString();
                    if (rawMessage.contains('"type":"USER_ACTIVITY"')) {
                      _resetControlsTimer();
                      return;
                    }
                    if (mounted) _eventBridge?.handleMessage(rawMessage);
                  }
                },
              );
            },
            onProgressChanged: (controller, progress) {
              if (!mounted) return;
              // Latch once: powers the post-load cross-domain check in
              // shouldOverrideUrlLoading. Set before setState so the next
              // build sees a consistent state.
              if (progress >= 100) _initialLoadComplete = true;
              setState(() {
                _loadProgress = progress.toDouble();
              });
            },
            onReceivedError: (controller, request, error) {
              final isMainFrame = request.isForMainFrame ?? false;
              if (isMainFrame && _loadProgress < 50 && mounted) {
                setState(() {
                  _hasError = true;
                  _errorMsg = error.description;
                });
              }
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              final isMainFrame = request.isForMainFrame ?? false;
              final statusCode = errorResponse.statusCode ?? 0;
              if (isMainFrame && statusCode >= 500 && mounted) {
                setState(() {
                  _hasError = true;
                  _errorMsg = 'Server error ($statusCode)';
                });
              }
            },
            onConsoleMessage: (controller, message) {
              if (kDebugMode) {
                final msg = message.message;
                // Still filter out the most common noise.
                if (msg == 'undefined' ||
                    msg.toLowerCase().contains('console.clear') ||
                    msg.startsWith('[object Object]') ||
                    msg.startsWith('Array')) {
                  return;
                }
                // On Windows, some sites flood with Bot/Proxy detection logs (Adscore).
                if (Platform.isWindows && msg.contains('Adscore')) return;

                debugPrint('WebView: $msg');
              }
            },
            onPermissionRequest: (controller, request) async {
              // Whitelist: only DRM (Widevine) — required for protected
              // streaming. Camera, microphone, geolocation, MIDI, etc. are
              // never needed by a video player and must always be denied.
              // (PermissionResourceType isn't a real Dart enum, so the set
              // can't be `const`.)
              final allowedResources = <PermissionResourceType>{
                PermissionResourceType.PROTECTED_MEDIA_ID,
              };

              final isAllSafe = request.resources.every(
                allowedResources.contains,
              );

              if (isAllSafe) {
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                );
              }

              if (kDebugMode) {
                debugPrint(
                  'Blocked unauthorized permission request: ${request.resources}',
                );
              }
              return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.DENY,
              );
            },
            onCreateWindow: (controller, createWindowAction) async {
              return false;
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final urlRequest = navigationAction.request;
              final url = urlRequest.url?.toString() ?? '';
              if (url.isEmpty) return NavigationActionPolicy.ALLOW;

              final scheme = urlRequest.url?.scheme ?? '';
              if (scheme.isNotEmpty &&
                  scheme != 'https' &&
                  scheme != 'http' &&
                  scheme != 'blob' &&
                  scheme != 'data' &&
                  scheme != 'about' &&
                  scheme != 'javascript') {
                return NavigationActionPolicy.CANCEL;
              }

              // Click-jacker about:blank guard.
              //
              // A common pattern on streaming sites — especially visible
              // on Windows WebView2 — is an invisible
              // `<a href="about:blank" target="_blank">` overlaid on top of
              // the player. The user click fires onCreateWindow (which we
              // reject by returning false), but WebView2's fallback for a
              // suppressed `target="_blank"` navigation is to load the
              // link in the CURRENT frame instead, blanking out the video.
              //
              // After the initial load, any main-frame navigation to
              // about:blank is treated as that hijack and cancelled. Sub-
              // frames are left alone — some legitimate players use a
              // brief about:blank intermediate inside iframes.
              if (navigationAction.isForMainFrame &&
                  _initialLoadComplete &&
                  (url == 'about:blank' || scheme == 'about')) {
                return NavigationActionPolicy.CANCEL;
              }

              final blocklist =
                  ref.read(adBlocklistProvider).value ??
                  ref.read(adBlocklistFallbackProvider);
              if (blocklist?.isBlocked(url) ?? false) {
                return NavigationActionPolicy.CANCEL;
              }

              // Cross-domain main-frame guard.
              //
              // We use _initialLoadComplete (latched true on the first
              // progress=100 event) instead of the live _loadProgress, because
              // a programmatic location.assign('evil.com') triggers
              // shouldOverrideUrlLoading *while* progress is dropping back to
              // 0 — gating on `_loadProgress == 100` would let the redirect
              // through. Once the original page has loaded, every cross-base
              // main-frame nav is treated as a hijack and cancelled.
              if (navigationAction.isForMainFrame &&
                  _initialLoadComplete &&
                  _initialHostBase.isNotEmpty) {
                final newBase = HostUtils.registeredDomain(
                  urlRequest.url?.host ?? '',
                );
                if (newBase.isNotEmpty && newBase != _initialHostBase) {
                  return NavigationActionPolicy.CANCEL;
                }
              }
              return NavigationActionPolicy.ALLOW;
            },
            shouldInterceptRequest: Platform.isWindows
                ? null
                : (controller, request) async {
                    final url = request.url.toString();
                    final blocklist =
                        ref.read(adBlocklistProvider).value ??
                        ref.read(adBlocklistFallbackProvider);
                    if (blocklist?.isBlocked(url) ?? false) {
                      return WebResourceResponse(
                        contentType: 'text/plain',
                        data: null,
                      );
                    }
                    return null;
                  },
          ),
        );
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

  /// [overrideMessage] / [onRetry] let transient errors (e.g. WebView env
  /// initialisation failure on Windows) render their own message and retry
  /// behaviour without touching `_hasError`/`_errorMsg`, which are owned by
  /// the in-WebView load lifecycle.
  Widget _buildErrorState({String? overrideMessage, VoidCallback? onRetry}) {
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
                overrideMessage ?? _errorMsg,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry ?? _retry,
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

  // ─── Window Actions ───────────────────────────────────────────────────────

  Widget _buildNextEpisodeOverlay() {
    if (!_showNextEpisodeOverlay) return const SizedBox.shrink();

    // Use the cached sentinel so we don't allocate a fresh UserProgress (and
    // a DateTime) on every player-chrome rebuild — see `_nextEpisodeKey`.
    final nextEpisodeAsync = ref.watch(
      nextEpisodeForProgressProvider(_nextEpisodeKey),
    );

    final nextEpisode = nextEpisodeAsync.value;
    if (nextEpisode == null) return const SizedBox.shrink();

    // Use episode stillPath if available, otherwise fallback to media backdrop.
    final thumbUrl = buildImageUrl(
      nextEpisode.stillPath ?? widget.media.backdropPath,
      AppConfig.backdropSmall,
    );

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutQuart,
      bottom: 100,
      right: _overlayActive ? 32 : -400, // Slide in from right
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 500),
        opacity: _overlayActive ? 1.0 : 0.0,
        child: MouseRegion(
          onEnter: (_) => _overlayTimer?.cancel(),
          onExit: (_) => _startOverlayTimer(),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 380,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: Colors.white12, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Episode Thumbnail with Play icon overlay
                  Stack(
                    children: [
                      Container(
                        width: 140,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusBase,
                          ),
                          color: Colors.white10,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: CachedNetworkImage(
                          imageUrl: thumbUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Center(
                            child: Icon(
                              Icons.movie_rounded,
                              color: Colors.white24,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.4),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),

                  // Episode Info
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'UP NEXT',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nextEpisode.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'S${nextEpisode.seasonNumber} E${nextEpisode.episodeNumber}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _playNextEpisode(
                                  nextEpisode.seasonNumber,
                                  nextEpisode.episodeNumber,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Play Next',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () {
                                // Also flip _showNextEpisodeOverlay so the
                                // build short-circuits at the top — leaving
                                // it `true` keeps `ref.watch` subscribed to
                                // nextEpisodeForProgressProvider for the rest
                                // of the session even though the widget is
                                // off-screen.
                                _overlayTimer?.cancel();
                                setState(() {
                                  _showNextEpisodeOverlay = false;
                                  _overlayActive = false;
                                  _dismissedNextEpisodeOverlay = true;
                                });
                              },
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white70,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Dismiss',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _playNextEpisode(int nextSeason, int nextEpisode) {
    if (!mounted) return;

    // Resolve the plugin and new URL before navigating
    final plugins =
        ref.read(pluginsForHookProvider(TriggerHook.mediaHeader)).value ?? [];
    final plugin = PluginUrlResolver.pickPlugin(
      plugins,
      savedId: widget.pluginId,
      preferredId: ref.read(preferredPluginProvider),
    );
    if (plugin == null) return;

    final nextUrl = PluginUrlResolver.resolve(
      plugin,
      widget.media,
      season: nextSeason,
      episode: nextEpisode,
    );

    if (_isNavigating) return;
    _isNavigating = true;
    // Tell our own dispose() to NOT restore portrait — the new player
    // route will re-lock landscape in its initState and we'd otherwise
    // race against it (iOS forces a rotation to whichever
    // setPreferredOrientations call landed last).
    _navigatingToAnotherPlayer = true;

    // Clean up current webview before navigating to free resources.
    _cleanupWebView();

    Future.microtask(() {
      if (!mounted) {
        // The route disappeared before the microtask ran. Reset both flags
        // so we don't leave the (now detached) state stuck pretending it's
        // mid-navigation.
        _isNavigating = false;
        _navigatingToAnotherPlayer = false;
        return;
      }
      try {
        context.pushReplacement(
          '/player',
          extra: PlayerArgs(
            url: nextUrl,
            media: widget.media,
            pluginName: plugin.name,
            pluginId: plugin.pluginId,
            season: nextSeason,
            episode: nextEpisode,
          ),
        );
      } catch (e) {
        _isNavigating = false;
        _navigatingToAnotherPlayer = false;
        if (kDebugMode) debugPrint('_playNextEpisode push failed: $e');
      }
    });
  }

  Widget _buildWindowActions() {
    return Positioned(
      top: 0,
      left: 50,
      right: 100,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: IgnorePointer(
          ignoring: !_showControls,
          child: Row(
            children: [
              // Drag area
              if (Platform.isWindows)
                Expanded(
                  child: DragToMoveArea(
                    child: Container(
                      height:
                          60, // Tall enough for dragging but don't block controls
                      color: Colors.transparent,
                    ),
                  ),
                )
              else
                const Spacer(),

              Padding(
                padding: const EdgeInsets.only(top: 12, right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (Platform.isWindows) ...[
                      _buildActionButton(
                        icon: _isFullScreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        onTap: _toggleFullScreen,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _buildActionButton(
                      icon: Icons.close_rounded,
                      onTap: _dismiss,
                    ),
                  ],
                ),
              ),
              // Buttons
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SafeArea(
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFullScreen() async {
    final isFull = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFull);
    if (mounted) {
      setState(() {
        _isFullScreen = !isFull;
      });
    }
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _dismiss() async {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      if (Platform.isWindows) {
        await windowManager.setFullScreen(false);
      }
      if (!mounted) {
        // The widget is already being torn down; nothing to pop. Reset the
        // flag so a re-entrant call after a quick rebuild isn't wedged.
        _isNavigating = false;
        return;
      }
      context.pop();
    } catch (e) {
      // Any failure (windowManager error, GoRouter pop refused) must
      // unwedge the screen so the user can try again.
      _isNavigating = false;
      if (kDebugMode) debugPrint('_dismiss failed: $e');
    }
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _loadProgress = 0;
    });
  }
}
