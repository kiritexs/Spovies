# UI Layout

`lib/core/utils/responsive_grid.dart`

---

## Responsive grid columns

Three pure functions compute grid column counts, one per grid shape in
the app. No `BuildContext` dependency, so they are unit-testable and safe
to call from `build` or a `LayoutBuilder` callback.

### Always pass available width, never screen width

Every helper takes `LayoutBuilder.constraints.maxWidth` (or
`SliverLayoutBuilder`'s `crossAxisExtent`) — **not**
`MediaQuery.of(context).size.width`.

On desktop the side nav eats ~60–80 px off the side, and in any
multi-pane layout the difference is arbitrary. Screen width is the wrong
reference everywhere except a fullscreen mobile page.

### Breakpoints

The **child aspect ratio** determines a good column count, so there is
one ladder per shape. All target roughly 150–220 px per card, so posters
never collapse below the legible TMDB W342 rendition nor balloon past
W500.

| Width | `posterGridColumns`<br>(ratio ≈ 0.52–0.58) | `genreGridColumns`<br>(ratio ≈ 1.45) | `continueWatchingColumns`<br>(fixed extent) |
|---|---|---|---|
| < 500 | 3 | 3 | — |
| 500–800 | 4 | 4 | — |
| 800–1000 | 5 | 5 | 2 |
| 1000–1200 | 5 | 5 | 3 |
| 1200–1400 | 6 | 7 | 3 |
| 1400–1600 | 6 | 7 | 4 |
| 1600–1800 | 8 | 8 | 4 |
| > 1800 | 8 | 8 | 5 |

Genre tiles are wider than tall, so more fit per row at the same width
budget than posters do.

Below 600 px, callers typically render Continue Watching as a vertical
list rather than a 1-column grid — see the gate in `home_screen.dart`.

### Call sites

| File | Grid | Helper |
|---|---|---|
| `discover_screen.dart` | Genre tiles | `genreGridColumns` |
| `discover_screen.dart` | Genre shimmer | `genreGridColumns` |
| `discover_screen.dart` | Search results | `posterGridColumns` |
| `discover_screen.dart` | Search shimmer | `posterGridColumns` |
| `all_media_screen.dart` | Items | `posterGridColumns` |
| `all_media_screen.dart` | Loading shimmer | `posterGridColumns` |
| `watchlist_screen.dart` | Items | `posterGridColumns` |
| `home_screen.dart` | Continue Watching | `continueWatchingColumns` |

Before extraction each file had its own inline ladder and they had
drifted apart — watchlist used 1200/800, all-media used 800/500,
discover used 800/500.

Shimmer placeholders scale with the same column count (`cols * 3` for
search, `cols * 4` for all-media) so the loading state matches the
density about to replace it, instead of showing a 3-card loading bar
followed by an 8-column burst.

---

## Expected results per platform

| Context | Poster | Genre | Continue Watching |
|---|---|---|---|
| Android phone (~360 px) | 3 | 3 | list mode |
| Tablet (~820 px) | 5 | 5 | 2 |
| Windowed desktop (~1200 px content) | 6 | 7 | 3 |
| Full-HD desktop (~1840 px content) | 8 | 8 | 5 |
| 1440p / ultrawide | 8 | 8 | 5 |
