// Suppress native Fullscreen API — injected at document-start.
//
// Both iOS and Android WebViews intercept the Fullscreen API and hand the
// video to a native player overlay, which kills the web-based subtitle
// rendering and player controls. This script no-ops every fullscreen
// entry-point so the video stays inside the WebView at all times. The
// player is already running in landscape immersive mode, so the user
// experience is effectively fullscreen without the native takeover.
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
  //
  // `configurable: true` is required: without it the descriptor defaults
  // to non-configurable, and a second injection (multi-frame replace,
  // soft navigation that shares the JS realm) would throw TypeError on
  // re-define and abort the rest of the script.
  Object.defineProperty(document, 'fullscreenEnabled', {
    configurable: true,
    get: function() { return false; },
  });
  Object.defineProperty(document, 'webkitFullscreenEnabled', {
    configurable: true,
    get: function() { return false; },
  });
})();
