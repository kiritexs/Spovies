// AdGuard-style request interceptor — injected at document-start.
//
// Patches the browser's networking APIs (fetch, XHR, sendBeacon,
// WebSocket) to block requests to known ad domains before they leave
// the WebView. Mimics DNS-level blocking without the overhead of a
// platform-channel round-trip per request.
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
  // Wrapping the constructor is straightforward, but a NAKED wrapper
  // loses two things every real site depends on:
  //
  //   • The static ready-state constants: `WebSocket.CONNECTING`,
  //     `WebSocket.OPEN`, `WebSocket.CLOSING`, `WebSocket.CLOSED`.
  //     Site code writes `if (ws.readyState === WebSocket.OPEN)`
  //     literally everywhere; without these it evaluates to
  //     `undefined === 1` and never fires the "socket ready" branch.
  //   • The `.prototype` chain so `ws instanceof WebSocket` still
  //     returns `true` for messages the site's own code creates.
  //
  // Both are fixed below. The static-property copy is explicit rather
  // than a `for-in` on the original constructor because the spec-
  // defined properties are enumerable-false in most engines and a
  // `for-in` sweep would miss them.
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
