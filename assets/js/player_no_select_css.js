// CSS injected at document-start.
//
// Disables text selection & long-press callouts globally. Does NOT touch
// pointer-events so scrollable lists remain fully interactive.
//
// Previously also force-capped `.modal/.popup/[class*=dialog]…` to
// `max-height: 60vh / max-width: 80vw` — that was crushing legitimate
// server / quality pickers on phones in landscape (60vh ≈ 216 px) so the
// cap was dropped. The site's own CSS sizes its dialogs for the active
// viewport already; we no longer second-guess it.
(function() {
  var s = document.createElement('style');
  s.textContent = '* {' +
    ' -webkit-user-select: none !important;' +
    ' user-select: none !important;' +
    ' -webkit-touch-callout: none !important;' +
    '}';
  (document.head || document.documentElement).appendChild(s);
})();
