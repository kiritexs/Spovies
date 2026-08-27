// AdGuard-style request interceptor — injected at document-start.
//
// Patches fetch, XHR, sendBeacon, and WebSocket to block known ad
// domains before the request leaves the WebView. Windows only; see
// docs/architecture/AD_BLOCKING.md.
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
  //
  // The static constants and prototype MUST be carried over — site code
  // writes `ws.readyState === WebSocket.OPEN` everywhere, and a naked
  // wrapper makes that `undefined === 1`. Copied explicitly because the
  // spec properties are enumerable-false, so `for-in` would miss them.
  var _origWS = window.WebSocket;
  var WrappedWS = function(url, protocols) {
    if (isBlocked(url)) {
      throw new Error('Blocked by Spovies AdGuard');
    }
    return new _origWS(url, protocols);
  };
  WrappedWS.prototype = _origWS.prototype;
  WrappedWS.CONNECTING = _origWS.CONNECTING;
  WrappedWS.OPEN = _origWS.OPEN;
  WrappedWS.CLOSING = _origWS.CLOSING;
  WrappedWS.CLOSED = _origWS.CLOSED;
  window.WebSocket = WrappedWS;
})();
