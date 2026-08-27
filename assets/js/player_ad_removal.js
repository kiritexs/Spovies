// Safe-by-default ad + popup block — injected at document-start.
//
// Two layers: a CSS DOM hide and a window.open allowlist. Several other
// approaches were tried and removed for breaking real sites — before
// adding anything here, read docs/architecture/AD_BLOCKING.md.
(function() {
  if (window.__spoviesAdBlock) return;
  window.__spoviesAdBlock = true;

  // ── 1. CSS-based ad hide ─────────────────────────────────────────────
  //
  // Anchor every selector on an ad-specific token (`ad-`, `adsbygoogle`,
  // `popunder`, a known network in an iframe src). NEVER match generic UI
  // words alone — `popup`, `modal`, `overlay`, `banner` catch the site's
  // own server picker and quality menu.
  var rules = [
    // ── ad iframes ──
    'iframe[src*="doubleclick.net"]',
    'iframe[src*="googlesyndication"]',
    'iframe[src*="adservice.google"]',
    'iframe[src*="adsbygoogle"]',
    'iframe[src*="popads"]',
    'iframe[src*="popcash"]',
    'iframe[src*="juicyads"]',
    'iframe[src*="exoclick"]',
    'iframe[src*="trafficjunky"]',
    'iframe[src*="propellerads"]',
    'iframe[src*="adsterra"]',
    'iframe[src*="onclkds"]',
    'iframe[src*="onclickmax"]',
    'iframe[src*="pushame"]',
    'iframe[src*="hilltopads"]',
    'iframe[src*="brightadnetwork"]',
    // ── AdSense / Google Tag ──
    'ins.adsbygoogle',
    'div[id^="google_ads"]',
    'div[class*="adsbygoogle"]',
    // ── explicit ad containers ──
    'div[class*="ad-overlay"]',
    'div[class*="ad-container"]',
    'div[class*="ad-banner"]',
    'div[class*="ad-block"]',
    'div[class*="ad-slot"]',
    'div[class*="ad-modal"]',
    'div[class*="ad-popup"]',
    'div[class*="ad-wrapper"]',
    'div[class*="ad-frame"]',
    'div[class*="ad-float"]',
    'div[class*="ad-sticky"]',
    'div[class~="ads"]',
    'div[id~="ads"]',
    'div[class*="banner-ad"]',
    'div[class*="popup-ad"]',
    'div[class*="modal-ad"]',
    'div[class*="float-ad"]',
    'div[class*="sticky-ad"]',
    'div[class*="overlay-ad"]',
    'div[id*="ad-popup"]',
    'div[id*="popup-ad"]',
    'div[id*="ad-overlay"]',
    'div[id*="overlay-ad"]',
    // ── popunders (the word is virtually never legitimate UI) ──
    'div[class*="popunder"]',
    'div[id*="popunder"]',
    // ── pre-roll / interstitial ad slots ──
    'div[class*="preroll-ad"]',
    'div[class*="ad-preroll"]',
    'div[class*="interstitial-ad"]',
    'div[class*="ad-interstitial"]',
    // ── ad-redirect anchor patterns ──
    'a[target="_blank"][rel*="nofollow"][href*="click"]',
    'a[target="_blank"][rel*="nofollow"][href*="track"]',
    'a[target="_blank"][href*="redirect.php"]',
    // ── click-jacker about:blank anchor (overlaid on player) ──
    'a[href="about:blank"]'
  ].join(',') +
    ' { display: none !important; pointer-events: none !important; }';

  function inject() {
    if (!document.documentElement) return false;
    var style = document.createElement('style');
    style.setAttribute('data-spovies', 'ad-block');
    style.textContent = rules;
    // <html>, not <head> — at document-start <head> doesn't exist yet.
    document.documentElement.appendChild(style);
    return true;
  }
  inject();

  // ── 2. window.open allowlist ─────────────────────────────────────────
  //
  // Gated on __spoviesIsAd so Turnstile, OAuth, and share dialogs still
  // reach onCreateWindow natively.
  var _origOpen = window.open;
  window.open = function(url, target, features) {
    var isAd = window.__spoviesIsAd || function() { return false; };
    if (isAd(url)) return null;
    return _origOpen.call(this, url, target, features);
  };
})();
