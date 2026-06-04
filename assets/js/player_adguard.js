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
  var _origWS = window.WebSocket;
  window.WebSocket = function(url, protocols) {
    if (isBlocked(url)) {
      throw new Error('Blocked by Spovies AdGuard');
    }
    return new _origWS(url, protocols);
  };
  window.WebSocket.prototype = _origWS.prototype;
})();
