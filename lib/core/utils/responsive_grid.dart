/// Grid column counts by available width.
///
/// Pass `LayoutBuilder.constraints.maxWidth`, not `MediaQuery.size.width`.
/// See `docs/architecture/UI_LAYOUT.md`.
library;

/// Columns for a portrait-poster grid (childAspectRatio ≈ 0.52–0.58).
int posterGridColumns(double width) {
  if (width > 1600) return 8;
  if (width > 1200) return 6;
  if (width > 800) return 5;
  if (width > 500) return 4;
  return 3;
}

/// Columns for short landscape genre tiles (childAspectRatio ≈ 1.45).
int genreGridColumns(double width) {
  if (width > 1600) return 8;
  if (width > 1200) return 7;
  if (width > 800) return 5;
  if (width > 500) return 4;
  return 3;
}

/// Columns for Continue Watching cards (fixed `mainAxisExtent`).
int continueWatchingColumns(double width) {
  if (width > 1800) return 5;
  if (width > 1400) return 4;
  if (width > 1000) return 3;
  return 2;
}
