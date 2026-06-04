// Console mute — injected at document-start on iOS / Windows only
// (Android has its own console behaviour where this script causes more
// harm than good).
//
// The script's job is narrow: replace `console.log`/`warn`/`error`/etc.
// with no-ops so streaming sites that flood the console (the most
// common attack pattern: `setInterval(() => console.clear(), 1)` to
// defeat dev-tools) can't drown the bridge or starve the UI thread on
// Windows. Previous versions of this script also spoofed
// `navigator.webdriver`, `outerWidth`, and `outerHeight` to defeat
// fingerprinting; those have been removed because (a) sites have many
// other detection vectors, (b) the prototype-pollution risk wasn't
// worth the small benefit, and (c) the "less spoof" stance we apply to
// Android consistently across platforms now.
(function() {
  if (window.__spoviesConsoleKiller) return;
  window.__spoviesConsoleKiller = true;

  var noOp = function() {};
  var originalConsole = window.console;
  if (!originalConsole) return;
  window.console.log    = noOp;
  window.console.warn   = noOp;
  window.console.error  = noOp;
  window.console.debug  = noOp;
  window.console.info   = noOp;
  window.console.clear  = noOp;
  window.console.table  = noOp;
  window.console.count  = noOp;
  window.console.dir    = noOp;
})();
