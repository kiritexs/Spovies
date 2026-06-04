// User Activity Tracker — injected at document-start.
//
// Detects mouse movement, touches, and key presses inside the WebView
// and relays them to Flutter to wake up the auto-hiding UI controls.
// This avoids putting a Flutter Listener over the WebView, which breaks
// native gesture routing on Android and Windows.
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
  window.addEventListener('mousemove',  reportActivity, { passive: true });
  window.addEventListener('touchstart', reportActivity, { passive: true });
  window.addEventListener('click',      reportActivity, { passive: true });
  window.addEventListener('keydown',    reportActivity, { passive: true });
})();
