<p align="center">
  <img src="assets/logo.png" alt="Spovies" width="96" height="96" />
</p>

<h1 align="center">Spovies</h1>

<p align="center">
  A cross-platform movie & TV discovery app — browse, search, track, and pick up where you left off.
</p>

> **Portfolio project — source-available, not open source. See [LICENSE](LICENSE).**

<p align="center">
  Project page: <a href="https://kiritex.com/work/spovies">kiritex.com/work/spovies</a>
</p>

---

## Features

- **Home** — trending hero, *Now Trending* and *Top Rated* rows, and a *Continue Watching* row.
- **Explore** — debounced search across movies and TV, genre tiles, trending movies/TV toggle, and paginated "See all" grids.
- **Details** — backdrop, poster, rating, genres, expandable overview, cast row, and trailers.
- **TV shows** — season picker and episode list with per-episode watch status.
- **Watchlist** — saved titles filtered by status: watching, completed, plan to watch, on hold, dropped.
- **Watch status** — set per title, per season, and per episode.
- **Export / import** — back up history, watchlist and settings to a single compressed `.spovies` file, with a confirmation preview before anything is written.
- **Adaptive layout** — bottom nav on phones, side nav and custom window frame on desktop; grids reflow by available width.
- **Plugin architecture** — manifest-based content sources, a sandboxed WebView player, progress tracking and ad blocking. *Present in the code, disabled in this build* (see below).

## Screenshots

<p align="center">
  <img src="https://kiritex.com/spovies/sv-hero.jpg" alt="Three phones showing Spovies — home, a title detail page, and the genre browser — with the app icon" width="720" />
</p>

### Mobile

| Home | Discover | Details |
|---|---|---|
| <img src="https://kiritex.com/spovies/sv-m-home.jpg" alt="Spovies mobile home with a featured hero and glass bottom nav" width="240" /> | <img src="https://kiritex.com/spovies/sv-m-discover.jpg" alt="Spovies mobile discover with search, trending, and genre grid" width="240" /> | <img src="https://kiritex.com/spovies/sv-m-detail.jpg" alt="Spovies mobile title detail with synopsis and cast" width="240" /> |

### Desktop

| Home | Discover |
|---|---|
| <img src="https://kiritex.com/spovies/sv-home.jpg" alt="Spovies desktop home with sidebar navigation and a featured hero" /> | <img src="https://kiritex.com/spovies/sv-discover.jpg" alt="Spovies desktop discover with trending row and genre grid" /> |

| Details | Library | Settings |
|---|---|---|
| <img src="https://kiritex.com/spovies/sv-detail.jpg" alt="Spovies desktop title detail with cast and crew" /> | <img src="https://kiritex.com/spovies/sv-watchlist.jpg" alt="Spovies desktop library with watch-status tabs" /> | <img src="https://kiritex.com/spovies/sv-settings.jpg" alt="Spovies desktop settings" /> |

More on the [project page](https://kiritex.com/work/spovies).

## Tech stack

| Area | Technology |
|---|---|
| Framework | Flutter (Android, iOS, Windows) |
| State | Riverpod 3 |
| Routing | go_router |
| Storage | Hive |
| Data | TMDB API via Dio |
| Secrets | envied (compile-time, obfuscated) |
| Desktop | window_manager |
| Player (disabled) | flutter_inappwebview |

## Architecture

Design notes live in [`docs/architecture/`](docs/architecture/README.md):

- [Navigation & system back](docs/architecture/NAVIGATION.md) — a single root `PopScope` over an `IndexedStack`, and why `StatefulShellRoute` was abandoned.
- [UI layout](docs/architecture/UI_LAYOUT.md) — responsive grid breakpoints.
- [Data](docs/architecture/DATA.md) — two-phase import and search-state ownership.
- [Plugins](docs/architecture/PLUGINS.md), [Player](docs/architecture/PLAYER.md), [Platform policy](docs/architecture/PLATFORM.md), [Ad blocking](docs/architecture/AD_BLOCKING.md).

## Getting started

1. Get a free TMDB **API Read Access Token** at <https://www.themoviedb.org/settings/api>.
2. Copy the env template and add your token:
   ```bash
   cp .env.example .env
   ```
3. Generate code (envied, freezed, json, riverpod):
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```
4. Run:
   ```bash
   flutter run
   ```

## Playback is intentionally disabled

This build ships with `kPluginsEnabled = false` in
[`lib/core/config/feature_flags.dart`](lib/core/config/feature_flags.dart).
Plugin settings are shown as unavailable and every *Watch* action reports
that playback is unavailable. **No content sources are included** — the
plugin, player and event-bridge code are kept for review only, and every
embed URL in the code and docs is a placeholder.

## TMDB attribution

This product uses the TMDB API but is not endorsed or certified by TMDB.

## Credits

Thanks to abdvlrqhman for contributions.

## License

Spovies Source-Available Portfolio License — view and evaluate only. See [LICENSE](LICENSE).
Copyright (c) 2026 Kiritex. All rights reserved.

Bug reports and pull requests are welcome under the terms in the LICENSE.
For permission requests or questions, see the
[project page](https://kiritex.com/work/spovies) or [github.com/kiritexs](https://github.com/kiritexs).
