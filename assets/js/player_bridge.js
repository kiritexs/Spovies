// Forwards postMessage events from the page's own scripts (e.g. Provider A's
// PLAYER_EVENT) to the Dart side. Kept as a supplementary source; the
// primary tracking lives in player_video_progress.js.
(function() {
  if (window.__spoviesBridgeInit) return;
  window.__spoviesBridgeInit = true;

  // Third-party widget noise that posts very frequent messages we never
  // care about. Each forwarded message is one platform-channel IPC +
  // one failed PlayerEvent parse on the Dart side, so dropping these at
  // the JS edge directly improves Android frame budget.
  var NOISE_PREFIXES = ['__ym', 'adscore'];
  var NOISE_SOURCES = [
    '"source":"cloudflare-challenge"', // Turnstile invisible captcha
    '"type":"MEDIA_DATA"',             // Provider B internal watch-history sync —
                                        // not a per-event progress update; real
                                        // tracking comes from player_video_progress.js
                                        // hooking the <video> element directly.
  ];

  window.addEventListener('message', function(e) {
    try {
      var data = e.data;
      if (!data) return;

      // Cheap string-prefix filter for common tracking pings.
      if (typeof data === 'string') {
        for (var i = 0; i < NOISE_PREFIXES.length; i++) {
          if (data.startsWith(NOISE_PREFIXES[i])) return;
        }
      }

      var d = (typeof data === 'string') ? data : JSON.stringify(data);
      if (!d || !window.flutter_inappwebview) return;

      // Substring filter for known noisy event sources that DO look like
      // PlayerEvent shapes (contain "event"/"type") but aren't ours.
      for (var j = 0; j < NOISE_SOURCES.length; j++) {
        if (d.indexOf(NOISE_SOURCES[j]) !== -1) return;
      }

      // Only forward if the shape looks like a PlayerEvent / activity /
      // channel event. Plain "Hello world" postMessages are ignored.
      if (d.indexOf('"type"') !== -1 ||
          d.indexOf('"event"') !== -1 ||
          d.indexOf('"channel"') !== -1) {
        window.flutter_inappwebview.callHandler('spoviesEventBridge', d);
      }
    } catch (ex) {}
  });
})();
