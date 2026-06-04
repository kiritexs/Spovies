// JS-level instant blocklist for fetch/XHR/WebSocket interception.
// The full ~35 k native blocklist (OISD / AdGuard / Steven Black) does
// the heavy lifting in shouldInterceptRequest; this list is just a
// belt-and-braces guard for substring matches that load before the
// Dart side has had a chance to intercept.
//
// SUBSTRING MATCH FOOTGUN: every entry below is matched as a raw
// substring against the *entire* URL. Generic words like "ads" must
// never appear here — they trigger false positives on innocuous paths
// ("loads", "uploads", "headers", "payloads", "downloads"...) and can
// starve legitimate API endpoints. Legitimate streaming-host domains
// (host-a / host-b / host-c / host-d / …) must never appear
// either — many aggregators fetch their server menu through those
// hosts, and blocking the fetch leaves the picker UI empty.
(function() {
  if (window.__spoviesIsAdReady) return;
  window.__spoviesIsAdReady = true;

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
    'gamerhit', 'trakzon', 'goosebomb', 'gryphline',
    // brightadnetwork.com — example.com's server-side redirect target.
    // Microsoft Defender SmartScreen blocks this domain outright and
    // replaces the player with a red warning page when the redirect
    // fires. Blocking client-side stops the redirect before SmartScreen
    // sees it.
    'brightadnetwork'
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
