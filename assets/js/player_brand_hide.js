// Minimal navigator.userAgentData brand replacement — Android only.
//
// Android System WebView injects `"Android WebView"` into:
//   • the HTTP `sec-ch-ua` Client-Hints header (set natively; we cannot
//     override it from JS, so sites that read THAT will still see it)
//   • `navigator.userAgentData.brands` (settable from JS)
//
// Streaming sites commonly grep `brands` for the literal string and
// either downgrade the layout or run a stricter bot challenge. This
// script replaces the brand list with the values a stock Chrome browser
// would advertise. Everything else on `userAgentData` — `mobile`,
// `platform`, `architecture`, `model`, `uaFullVersion` — reads through
// to the original `userAgentData` object via the closure, so the values
// stay HONEST. The earlier (deleted) version of this script also lied
// about platform=Windows / mobile=false / architecture=x86, which
// produced inconsistent signals to any site that cross-checked the JS
// values against the system Client-Hints. This trimmed version is the
// minimum effective spoof and the most aligned with the rest of the
// stack (Linux desktop UA + DESKTOP content mode + brand-hide here).
(function() {
  if (window.__spoviesUaBrand) return;
  window.__spoviesUaBrand = true;

  if (typeof navigator.userAgentData === 'undefined') return;

  var orig = navigator.userAgentData;
  var brands = [
    { brand: 'Not/A)Brand',   version: '8'   },
    { brand: 'Chromium',      version: '130' },
    { brand: 'Google Chrome', version: '130' }
  ];

  var spoofed = {
    brands:   brands,
    mobile:   orig.mobile,
    platform: orig.platform,
    getHighEntropyValues: function(hints) {
      // Defer to the real implementation, then overwrite only the
      // brands field on the way out. Anything we don't replace
      // (architecture, model, platformVersion, …) stays accurate.
      return orig.getHighEntropyValues(hints).then(function(r) {
        if (r && typeof r === 'object' && 'brands' in r) {
          r.brands = brands;
        }
        return r;
      });
    },
    toJSON: function() {
      return { brands: brands, mobile: orig.mobile, platform: orig.platform };
    }
  };

  try {
    Object.defineProperty(navigator, 'userAgentData', {
      configurable: true,
      get: function() { return spoofed; }
    });
  } catch (e) {}
})();
