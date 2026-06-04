// iOS inline-video fix — injected at document-start.
//
// On iOS, any <video> element that lacks the `playsinline` attribute is
// captured by the native AVPlayer full-screen overlay, killing the web-
// based player controls. This script:
//   1. Stamps `playsinline` + `webkit-playsinline` on every existing
//      <video>.
//   2. Installs a MutationObserver so dynamically-injected <video>
//      elements (the norm for streaming sites) are patched before they
//      can trigger the native player.
//   3. Overrides `HTMLMediaElement.play` to re-apply the attributes on
//      every play attempt as a last-resort safety net.
//
// Injected at AT_DOCUMENT_START so the observer is live before the
// page's own scripts run and add any <video> nodes.
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
