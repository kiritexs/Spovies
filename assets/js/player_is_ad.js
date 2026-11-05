// Shared URL predicate — window.__spoviesIsAd.
//
// A belt-and-braces guard for requests that fire before the Dart side
// can intercept; the ~35 k native blocklist does the heavy lifting.
//
// FOOTGUN: entries match as raw substrings against the ENTIRE URL.
// Never add generic words ("ads" matches "uploads", "payloads") and
// never add streaming hosts (embed/CDN domains) — aggregators
// fetch their server menu through those. See AD_BLOCKING.md.
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
    // An embed host's redirect target. SmartScreen blocks it and replaces
    // the player with a red warning — block it before that fires.
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
