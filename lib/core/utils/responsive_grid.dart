/// Helpers for computing grid column counts based on **available width**.
///
/// Pass `LayoutBuilder.constraints.maxWidth` rather than
/// `MediaQuery.of(context).size.width` so the count reflects the actual
/// space the grid has — on desktop the side nav eats ~60-80 px off the
/// side, in a multi-pane layout it could be anything. The screen width
/// is the wrong reference everywhere except a fullscreen mobile page.
///
/// The aspect-ratio of the GRID CHILDREN is what really determines a
/// "good" column count, so we expose three breakpoint ladders here —
/// one per shape we actually use:
///
///   • [posterGridColumns]    — portrait posters (`childAspectRatio` ≈ 0.52)
///   • [genreGridColumns]     — short landscape tiles (≈ 1.45)
///   • [continueWatchingColumns] — fixed-height cards (mainAxisExtent)
///
/// All three are pure functions — easy to unit-test, no `BuildContext`
/// dependency, safe to call from `build` or a `LayoutBuilder` callback.
library;

/// Columns for a portrait-poster grid (childAspectRatio ≈ 0.52-0.58).
///
/// Targets roughly 150-220 px per card across breakpoints so posters
/// never collapse below the legible TMDB W342 thumbnail rendition and
/// never balloon past the W500 rendition.
///
/// Breakpoints reflect typical viewports:
///   • < 500   phones (3 cols)
///   • 500-800 small tablets / split-screen (4 cols)
///   • 800-1200 large tablets / windowed desktop (5 cols)
///   • 1200-1600 full-screen 1080p desktop (6 cols)
///   • > 1600 1440p+ / ultrawide (8 cols)
int posterGridColumns(double width) {
  if (width > 1600) return 8;
  if (width > 1200) return 6;
  if (width > 800) return 5;
  if (width > 500) return 4;
  return 3;
}

/// Columns for short landscape genre tiles (childAspectRatio ≈ 1.45).
///
/// Tiles are wider than tall, so more fit per row at the same width
/// budget compared to the poster grid.
int genreGridColumns(double width) {
  if (width > 1600) return 8;
  if (width > 1200) return 7;
  if (width > 800) return 5;
  if (width > 500) return 4;
  return 3;
}

/// Columns for Continue Watching cards (cards use a fixed
/// `mainAxisExtent`, so the only thing scaling is column count).
///
/// At <600 callers typically render a vertical list rather than a
/// 1-column grid; see `home_screen.dart`'s gate.
int continueWatchingColumns(double width) {
  if (width > 1800) return 5;
  if (width > 1400) return 4;
  if (width > 1000) return 3;
  return 2;
}
