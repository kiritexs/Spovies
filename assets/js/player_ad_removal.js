// Safe-by-default ad + popup block — injected at document-start.
//
// Two layers, both deliberately small:
//
//   1. CSS-based DOM hide. A single `<style>` element with `display:none
//      !important` rules for known ad selectors. The browser applies the
//      rule to every matching element AS IT APPEARS in the DOM — no
//      MutationObserver, no `querySelectorAll` sweeps, no
//      `getComputedStyle` forced layouts. Dynamically-added ads are
//      caught the moment they're inserted.
//
//   2. `window.open` allowlist. The only behaviour CSS can't replicate.
//      Delegates to `__spoviesIsAd` so legitimate popups (Cloudflare
//      Turnstile, OAuth, share dialogs) pass through unchanged.
//
// What this script DELIBERATELY does NOT do — and why we removed it:
//
//   • MutationObserver + `getComputedStyle` sweep — caused 30–100 ms
//     forced-layout stalls on Android with Next.js pages.
//   • `EventTarget.prototype.addEventListener` wrapper — broke sites
//     whose own click handlers nested click dispatch; risk much greater
//     than the popunder protection it bought us.
//   • `document.createElement` override — broke site code that
//     legitimately creates iframes.
//   • `Object.defineProperty(iframe, 'src', …)` — broke site bundlers
//     that redefine iframe descriptors for their own analytics.
//   • `Location.prototype.assign/replace` patches — redundant with the
//     native `shouldOverrideUrlLoading` scheme block, and the JS-side
//     `getBase()` used a naive PSL heuristic that disagreed with the
//     Dart side.
//
// All of the above were tried, all of them broke something. CSS + one
// function override is the minimum that actually removes ads + popups
// without becoming the cause of bigger problems than the ones it
// solves.
(function() {
  if (window.__spoviesAdBlock) return;
  window.__spoviesAdBlock = true;

  // ── 1. CSS-based ad hide ─────────────────────────────────────────────
  //
  // Selector design rules:
  //   • Anchor every match on a token specific to ads — `ad-`, `ads-`,
  //     `adsbygoogle`, `popunder`, or a known ad-network identifier in
  //     an iframe's src.
  //   • NEVER use generic UI words alone — `popup`, `modal`, `overlay`,
  //     `banner` — they catch the streaming site's own server picker /
  //     quality menu / caption picker and shred the player UI.
  //   • Use the `display:none !important` declaration plus
  //     `pointer-events:none` so any element that escapes the hide via
  //     `position:fixed; z-index:max` still can't intercept clicks.
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
    // Append to <html> rather than <head> — at document-start <head>
    // doesn't exist yet, but <html> always does, and CSS in a <style>
    // attached anywhere in the document applies the same way.
    document.documentElement.appendChild(style);
    return true;
  }
  inject();

  // ── 2. window.open allowlist ─────────────────────────────────────────
  //
  // The only thing CSS can't do. Site code that calls `window.open(url)`
  // is checked against `__spoviesIsAd` — only ad-domain URLs are
  // swallowed. Legitimate popups (Cloudflare Turnstile interactive
  // challenge, OAuth login, "share" dialogs) pass through to the real
  // window.open and reach `onCreateWindow` natively.
  var _origOpen = window.open;
  window.open = function(url, target, features) {
    var isAd = window.__spoviesIsAd || function() { return false; };
    if (isAd(url)) return null;
    return _origOpen.call(this, url, target, features);
  };
})();
