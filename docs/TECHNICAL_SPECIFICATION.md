# Spovies — Technical Specification Document (TSD)

**Version:** 2.0  
**Status:** Implemented  
**Last Updated:** April 21, 2026

---

## Table of Contents

1. [System Vision & Smart Handling](#1-system-vision--smart-handling)
2. [Technical Architecture](#2-technical-architecture)
3. [Data Model Schema](#3-data-model-schema)
4. [Smart Features](#4-smart-features)
5. [Project Roadmap (5 Phases)](#5-project-roadmap-5-phases)
6. [State Management Flow & Riverpod Structure](#6-state-management-flow--riverpod-structure)
7. [Local-First Data Strategy](#7-local-first-data-strategy)
8. [UI/UX Design System](#8-uiux-design-system)
9. [TMDB API Integration Reference](#9-tmdb-api-integration-reference)

---

## 1. System Vision & Smart Handling

### 1.1 The Plugin Protocol (Core)

The **SpoviesPlugin** interface is the contract between the app and any media provider. It defines:

| Concept | Description |
|--------|-------------|
| **TriggerHooks** | Where the plugin's action appears in the UI. App-defined slots, plugin chooses which to occupy. |
| **ActionTypes** | What happens when the user taps: `WebView`, `ExternalLink`, or `MetadataFetch`. |
| **Manifest** | JSON fetched from a remote URL; defines plugin identity, hooks, URL templates, and event bridge config. |

**Available TriggerHook Zones:**

| Zone | Location | Use Case |
|------|----------|----------|
| `media_header` | Main action button on Movie/Show details page | Primary "Watch" CTA |
| `episode_item` | Play icon next to each episode in a list | Per-episode streaming |
| `media_card_context` | Long-press menu or quick-play overlay on home/search cards | Quick access from discovery |

**Multiplicity:** A single plugin (e.g., an example source) can register for multiple hooks via `hooks: ["media_header", "episode_item"]`.

---

### 1.2 Event-Driven Progress

| Event | Source | Action |
|-------|--------|--------|
| `progress` | WebView `postMessage` | Update local `WatchHistory` |
| `pause` / `stop` | WebView `postMessage` | Update progress + timestamp |
| `heartbeat` | WebView (every 5–10 sec) | Continuous sync for crash resilience |

**Flow:** WebView → `EventBridge` → `WebViewProviders` → `WatchHistoryRepository` → Hive

**Continue Watching:** Home screen reads `WatchHistory` sorted by `LastPlayedDate`, shows items with `Percentage < 90`.

---

### 1.3 Plugin Sandboxing & Dynamic Loading

- **Sandboxing:** WebViews run in isolated contexts; no direct DOM access to app.
- **Dynamic Loading:** App fetches `PluginManifest` JSON from a remote URL; no app update required.
- **Validation:** Manifest must pass schema validation; invalid plugins are rejected.

---

## 2. Technical Architecture

### 2.1 Clean Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                            │
│  (Screens, Widgets, Riverpod Providers, State Notifiers)         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     DOMAIN LAYER                                 │
│  (Entities, Use Cases, Repository Interfaces)                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DATA LAYER                                  │
│  (Repositories, Data Sources, TMDB API, Plugin Discovery, Hive)   │
└─────────────────────────────────────────────────────────────────┘
```

---

### 2.2 Folder Structure

```
lib/
├── main.dart
│
├── core/                              # Shared utilities, constants, config
│   ├── config/
│   │   ├── app_config.dart            # App constants
│   │   └── env.dart                   # TMDB API key (envied)
│   ├── errors/
│   │   ├── app_exception.dart
│   │   └── plugin_exception.dart
│   ├── theme/
│   │   ├── app_theme.dart             # ThemeData setup
│   │   ├── app_colors.dart            # Dark theme palette
│   │   ├── app_text_styles.dart       # Spline Sans typography
│   │   └── app_spacing.dart           # Spacing tokens
│   └── utils/
│       ├── url_validator.dart
│       └── tmdb_image_url.dart
│
├── data/
│   ├── datasources/
│   │   ├── remote/
│   │   │   ├── tmdb_api.dart          # Dio wrapper for TMDB
│   │   │   ├── retry_interceptor.dart
│   │   │   └── tmdb_cache_interceptor.dart
│   │   └── local/
│   │       └── hive_service.dart      # Hive initialization & box refs
│   ├── models/
│   │   ├── media_item_model.dart
│   │   ├── genre_model.dart
│   │   └── plugin_manifest_model.dart
│   ├── repositories/
│   │   ├── media_repository_impl.dart
│   │   ├── plugin_repository_impl.dart
│   │   ├── watch_history_repository_impl.dart
│   │   └── watch_status_repository_impl.dart
│   └── services/
│       ├── export_import_service.dart  # .spovies backup/restore
│       └── remote_blocklist.dart       # Ad/tracking domain blocklist
│
├── domain/
│   ├── entities/
│   │   ├── media_item.dart
│   │   ├── media_type.dart
│   │   ├── media_metadata.dart
│   │   ├── episode.dart
│   │   ├── cast_member.dart
│   │   ├── plugin_manifest.dart
│   │   ├── user_progress.dart
│   │   └── watch_status.dart          # WatchStatus enum + MediaStatus
│   └── repositories/
│       ├── media_repository.dart
│       ├── plugin_repository.dart
│       ├── watch_history_repository.dart
│       └── watch_status_repository.dart
│
├── presentation/
│   ├── providers/                     # Riverpod providers
│   │   ├── media_providers.dart
│   │   ├── plugin_providers.dart
│   │   ├── details_providers.dart
│   │   ├── watch_history_providers.dart
│   │   ├── watch_status_providers.dart
│   │   ├── watchlist_providers.dart
│   │   ├── search_providers.dart
│   │   ├── settings_providers.dart
│   │   └── webview_providers.dart
│   ├── router/
│   │   ├── app_router.dart            # GoRouter with shell + full-screen routes
│   │   └── shell_scaffold.dart        # Tab shell with glass bottom nav
│   ├── screens/
│   │   ├── home/
│   │   │   └── home_screen.dart
│   │   ├── explore/
│   │   │   ├── discover_screen.dart
│   │   │   └── all_media_screen.dart
│   │   ├── search/
│   │   │   └── search_screen.dart
│   │   ├── details/
│   │   │   └── details_screen.dart
│   │   ├── watchlist/
│   │   │   └── watchlist_screen.dart
│   │   ├── player/
│   │   │   └── webview_player_screen.dart
│   │   └── settings/
│   │       ├── settings_screen.dart
│   │       └── plugin_management_screen.dart
│   └── widgets/
│       ├── app_header.dart
│       ├── hero_card.dart
│       ├── media_card.dart
│       ├── media_row.dart
│       ├── continue_watching_card.dart
│       ├── glass_bottom_nav.dart
│       ├── shimmer_placeholder.dart
│       ├── desktop_side_nav.dart
│       └── desktop_window_frame.dart
│
└── plugins/                           # Plugin runtime & protocol
    ├── protocol/
    │   ├── trigger_hook.dart
    │   ├── action_type.dart
    │   └── plugin_url_resolver.dart   # URL template placeholder replacement
    ├── event_bridge/
    │   └── event_bridge.dart          # Parses postMessage from WebView
    └── discovery/
        └── plugin_discovery_service.dart  # Manifest fetch & validation
```

---

### 2.3 Layer Responsibilities

| Layer | Responsibility |
|-------|----------------|
| **Data** | TMDB API (Dio), HTTP for plugin manifests, Hive persistence, model serialization, export/import service, remote blocklist |
| **Domain** | Entities (pure Dart), repository contracts (interfaces) |
| **Presentation** | Riverpod providers, UI screens & widgets, GoRouter navigation, theme application |

---

## 3. Data Model Schema

### 3.1 MediaItem

```json
{
  "id": "12345",
  "tmdbId": 12345,
  "type": "movie",
  "title": "Inception",
  "overview": "...",
  "posterPath": "/path.jpg",
  "backdropPath": "/backdrop.jpg",
  "releaseDate": "2010-07-16",
  "metadata": {
    "imdbId": "tt1375666",
    "runtime": 148,
    "genres": ["Action", "Sci-Fi"],
    "rating": 8.4,
    "voteCount": 25000
  }
}
```

**Dart Class (Entity):**

```dart
class MediaItem {
  final String id;
  final int tmdbId;
  final MediaType type;  // movie | tv
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final MediaMetadata metadata;
  final List<Episode>? episodes;  // For TV series
}
```

---

### 3.2 PluginManifest

```json
{
  "pluginId": "example-source",
  "version": "1.2.0",
  "name": "Example Source",
  "description": "Stream movies and shows",
  "iconUrl": "https://example.com/icon.png",
  "hooks": ["media_header", "episode_item"],
  "urlTemplate": "https://example.com/watch/{{type}}/{{tmdbId}}",
  "actionType": "webview",
  "presentationMode": "fullscreen",
  "eventBridgeConfig": {
    "postMessageOrigin": "https://example.com",
    "allowedEventTypes": ["progress", "pause", "stop", "heartbeat"]
  }
}
```

**Dart Class (Entity):**

```dart
class PluginManifest {
  final String pluginId;
  final String version;
  final String name;
  final String description;
  final String? iconUrl;
  final List<TriggerHook> hooks;
  final String urlTemplate;
  final ActionType actionType;
  final PresentationMode presentationMode;
  final EventBridgeConfig eventBridgeConfig;
}
```

---

### 3.3 UserProgress

```json
{
  "mediaId": "12345",
  "mediaType": "movie",
  "title": "Inception",
  "posterPath": "/path.jpg",
  "percentage": 65.5,
  "currentTime": 3600,
  "duration": 5500,
  "season": null,
  "episode": null,
  "lastPlayedDate": "2026-03-02T14:30:00Z",
  "lastPluginId": "example-source"
}
```

**Dart Class (Entity):**

```dart
class UserProgress {
  final String mediaId;
  final MediaType mediaType;
  final String title;
  final String? posterPath;
  final double percentage;
  final double currentTime;
  final double duration;
  final int? season;
  final int? episode;
  final DateTime lastPlayedDate;
  final String? lastPluginId;
}
```

---

### 3.4 WatchStatus & MediaStatus

```dart
enum WatchStatus {
  watching,
  completed,
  dropped,
  onHold,
  planToWatch,
}
```

```dart
class MediaStatus {
  final String mediaId;
  final String mediaType;
  final WatchStatus status;
  final int? season;
  final int? episode;
  final DateTime updatedAt;
}
```

---

## 4. Smart Features

### 4.1 Intelligent Fallback

| Scenario | Behavior |
|----------|----------|
| Plugin fails to load URL | Show "Provider unavailable" toast; suggest alternative plugin in dropdown if available |
| All plugins fail | Show "No providers available" message |
| Network error | Retry with exponential backoff via `RetryInterceptor`; show cached data if available |
| Invalid manifest | Reject plugin with detailed error; notify user in Settings > Plugins |

### 4.2 Remote Ad Blocklist

The app maintains a community-sourced blocklist of ad/tracking domains that are filtered in the WebView player:

- **Multiple sources**: OISD, Peter Lowe, AdGuard, NoCoin, Steven Black
- **24-hour cache TTL** — blocklist refreshes daily
- **Built-in fallback** — ~70 hardcoded domains when network is unavailable
- **O(1) lookup** via `HashSet` + LRU cache for domain checks
- Exported as JavaScript array (capped at 40k domains) and injected into WebView

### 4.3 Dual Progress Tracking

The WebView player uses two independent systems to capture playback progress:

1. **Plugin-emitted events** — `postMessage` events from the embedded player (if the plugin supports it)
2. **Universal HTML5 tracker** — Injected script that directly monitors any `<video>` element on the page

This ensures progress is captured even for plugins that don't implement the Event Bridge.

### 4.4 TMDB Response Caching

API responses are cached locally in Hive with configurable TTLs via `TmdbCacheInterceptor`:

| Data Type | Cache TTL |
|-----------|-----------|
| Configuration | 24 hours |
| Genre lists | 24 hours |
| Trending lists | 30 minutes |
| Movie/TV details | 1 hour |
| Search results | Not cached |

---

## 5. Project Roadmap (5 Phases)

### Phase 1: Foundation ✅

- [x] Project setup: Flutter, dependencies (Riverpod, Hive, Dio, `google_fonts`, `cached_network_image`)
- [x] Folder structure per Clean Architecture
- [x] Design system: `AppTheme`, `AppColors`, `AppTextStyles`, `AppSpacing` matching the original design mockup's tokens
- [x] TMDB API wrapper: `TmdbApi` class with Bearer token auth, retry & cache interceptors
- [x] Image loading with `CachedNetworkImage` + shimmer placeholder
- [x] Core entities: `MediaItem`, `Episode`, `CastMember`, `MediaMetadata`
- [x] Home screen with Hero card (4:5), "Now Trending" horizontal snap row, glass bottom nav

**Deliverable:** App renders TMDB content with full design-system fidelity; Hero + Trending row + glass nav functional.

---

### Phase 2: Plugin Protocol & Discovery ✅

- [x] `PluginManifest` entity and model
- [x] Plugin Discovery Service (fetch manifest from URL, supports registries)
- [x] TriggerHook enum and ActionType enum
- [x] Plugin management screen (add by URL, toggle enable/disable, set preferred, remove)
- [x] Plugin repository + local cache of manifests in Hive
- [x] Plugin URL resolver with `{{tmdbId}}`, `{{type}}`, `{{season}}`, `{{episode}}` placeholders

**Deliverable:** App can load, validate, and manage plugin manifests; Settings shows installed plugins.

---

### Phase 3: Details & Plugin Actions ✅

- [x] Details screen: backdrop hero, cast row, trailer chip, rating badge — all from `append_to_response` single call
- [x] Primary Watch button + dropdown for alternate providers
- [x] User preference: Preferred Provider in Settings
- [x] TV show support: season selector, episode list with still images, per-episode Watch buttons
- [x] Watchlist toggle (add/remove from saved titles)

**Deliverable:** Details page shows TMDB metadata with cinematic layout; Watch button opens plugin.

---

### Phase 4: WebView Player & Progress Tracking ✅

- [x] Full-screen WebView container with landscape support
- [x] EventBridge: `postMessage` listener with multi-format support (PLAYER_EVENT, flat channel, native time-event)
- [x] Universal HTML5 `<video>` element tracker (fallback for all plugins)
- [x] `WatchHistoryRepository` + Hive persistence for `UserProgress`
- [x] Auto-resume: seeks to last saved position
- [x] Throttled progress writes (5-second throttle for continuous, immediate for pause/ended)
- [x] Continue Watching row on home screen
- [x] `episode_item` hook for TV episodes
- [x] Remote ad blocklist injected into WebView

**Deliverable:** Watch in WebView; progress saved and resumed; Continue Watching works.

---

### Phase 5: Polish & Export/Import ✅

- [x] Intelligent fallback (plugin failure handling, retry interceptor)
- [x] Settings screen: all sections (Data, Plugins, Appearance, Playback, About)
- [x] Export / Import feature (`ExportImportService`, `.spovies` gzip file format)
- [x] Share export via `share_plus`; import via `file_picker`
- [x] Shimmer/skeleton loading states on all screens
- [x] Watch status system (watching, completed, dropped, on-hold, plan-to-watch)
- [x] Watchlist with status filtering
- [x] Desktop support: Windows (window_manager, side nav, window frame); macOS/Linux runners are not configured in this repository
- [x] Search screen with live TMDB results
- [x] All Media paginated browsing screen

**Deliverable:** Production-ready, fully local app across mobile and desktop. Users can back up and restore all data.

---

## 6. State Management Flow & Riverpod Structure

### 6.1 Data Flow Overview

```
TMDB API ──► MediaRepository ──► detailsProviders
                                      │
Plugin Discovery ──► PluginRepository ──► pluginProviders
                                      │
                                      ▼
                            DetailsScreen (UI)
                                      │
                            PluginUrlResolver ──► WebViewPlayerScreen
                                      │
                            EventBridge ──► webviewProviders ──► WatchHistoryRepository
```

---

### 6.2 Riverpod Provider Architecture

#### A. Media Providers (TMDB Data)

```dart
// Repository providers
final mediaRepositoryProvider = Provider<MediaRepository>((ref) => ...);

// Trending & curated lists
final trendingMoviesProvider = FutureProvider<List<MediaItem>>((ref) => ...);
final topRatedMoviesProvider = FutureProvider<List<MediaItem>>((ref) => ...);

// Details (with append_to_response for cast, videos, images)
final movieDetailsProvider = FutureProvider.family<MediaItem, int>((ref, id) => ...);
final tvDetailsProvider = FutureProvider.family<MediaItem, int>((ref, id) => ...);

// Search
final searchResultsProvider = FutureProvider.family<List<MediaItem>, String>((ref, query) => ...);

// Genre map (cached)
final genreMapProvider = FutureProvider<Map<int, String>>((ref) => ...);
```

#### B. Plugin Providers

```dart
// All installed plugins (from Hive)
final installedPluginsProvider = FutureProvider<List<PluginManifest>>((ref) => ...);

// Plugins for a specific hook - used by UI to render buttons
final pluginsForHookProvider = FutureProvider.family<List<PluginManifest>, TriggerHook>((ref, hook) => ...);

// Per-plugin enabled/disabled state
final pluginEnabledProvider = Provider.family<bool, String>((ref, pluginId) => ...);

// User's preferred provider (from Settings, persisted in Hive)
final preferredPluginProvider = StateProvider<String?>((ref) => ...);
```

#### C. Watch History & Status Providers

```dart
// Continue Watching (items with percentage < 90, sorted by lastPlayedDate)
final continueWatchingProvider = FutureProvider<List<UserProgress>>((ref) => ...);

// For a specific media: current progress (for auto-resume)
final progressForMediaProvider = FutureProvider.family<UserProgress?, String>((ref, mediaId) => ...);

// Watch status (watching, completed, dropped, on-hold, plan-to-watch)
final libraryEntriesByStatusProvider = FutureProvider.family<List<MediaStatus>, WatchStatus>((ref, status) => ...);
```

#### D. WebView & Settings Providers

```dart
// WebView event and progress tracking (receives EventBridge events, writes to WatchHistoryRepository)
final webviewProgressProvider = ...;

// Watchlist (saved media items)
final watchlistProvider = NotifierProvider<WatchlistNotifier, List<MediaItem>>(...);

// App settings (persisted to Hive)
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(...);
```

#### E. Provider Dependencies Diagram

```
                    ┌─────────────────────┐
                    │ mediaRepository     │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              ��                ▼                ▼
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │ trending     │ │ details      │ │ search       │
    │ Providers    │ │ Providers    │ │ Providers    │
    └──────┬───────┘ └──────┬───────┘ └──────────────┘
           │                │
           ▼                ▼
    ┌──────────────┐ ┌──────────────────────────┐
    │ HomeScreen   │ │ DetailsScreen            │
    └──────────────┘ └──────────┬───────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │ plugin       │ │ PluginUrl    │ │ watchlist     │
    │ Providers    │ │ Resolver     │ │ Provider     │
    └──────────────┘ └──────┬───────┘ └──────────────┘
                            │
                   ┌────────▼────────┐
                   │ WebViewPlayer   │
                   │ Screen          │
                   └────────┬────────┘
                            │
              ┌─────────────┼─────────────┐
              ▼                           ▼
    ┌──────────────┐            ┌──────────────┐
    │ EventBridge  │            │ HTML5 Video  │
    │              │            │ Tracker      │
    └──────┬───────┘            └──────┬───────┘
           └────────────┬──────────────┘
                        ▼
              ┌──────────────────┐
              │ webviewProviders │
              └────────┬─────────┘
                       ▼
              ┌──────────────────┐
              │ WatchHistory     │
              │ Repository       │
              └──────────────────┘
```

---

### 6.3 Handling Plugin Action Execution

When user taps "Watch" (or selects from dropdown):

```dart
// 1. PluginUrlResolver replaces placeholders in urlTemplate:
//    {{tmdbId}}, {{type}}, {{title}}, {{imdbId}}, {{season}}, {{episode}}
// 2. If actionType == webview: Navigate to WebViewPlayerScreen with resolved URL
// 3. If actionType == externalLink: Launch url_launcher
// 4. If actionType == metadataFetch: Reserved for future use
```

The `WebViewPlayerScreen`:
- Loads the resolved URL in a full-screen `InAppWebView`
- Injects remote blocklist as JavaScript to filter ad/tracking domains
- Injects universal HTML5 `<video>` element tracker script
- Listens for `postMessage` events via `EventBridge`
- Auto-resumes playback from last saved position (`resumeTimeSeconds`)
- Writes progress to `WatchHistoryRepository` via `webviewProviders`
- Throttles `timeupdate` writes (5-second interval); immediate for `pause`/`ended`

---

## 7. Local-First Data Strategy

> **Decision:** There is no backend. The app is fully local. All user data lives in Hive on-device. Users can back up and restore their data via an **Export / Import** feature in Settings. No auth, no cloud sync, no server.

---

### 7.1 What is Stored Locally (Hive)

| Data | Box | Description |
|------|-----|-------------|
| `WatchHistory` | `watchHistoryBox` | Progress records per media item (`UserProgress`) |
| `Watchlist` | `watchlistBox` | User's saved/bookmarked media |
| `WatchStatus` | `watchStatusBox` | Per-media status tracking (`MediaStatus`) |
| `InstalledPlugins` | `pluginsBox` | Cached plugin manifests (fetched from URLs) |
| `TmdbCache` | `tmdbCacheBox` | Cached API responses with TTL |
| `GenreCache` | `genreCacheBox` | Movie + TV genre lists |
| `TmdbConfig` | `configBox` | TMDB image configuration |
| `AppSettings` | `settingsBox` | Theme mode, preferred provider, etc. |

---

### 7.2 Export / Import (Settings Screen)

Users can export all their data to a single `.spovies` file (JSON under the hood, zipped) and import it on the same or a new device.

#### Export Flow

```
AppSettings + WatchHistory + Watchlist + InstalledPlugins
       │
       ▼
  ExportService.export()
       │
  Serialize to JSON → Compress (gzip) → Write to file
       │
  Share via share_plus (share sheet: Files, Drive, AirDrop, etc.)
  — or —
  Save to user-chosen directory via file_picker
```

#### Import Flow

```
User picks .spovies file (via file_picker)
       │
       ▼
  ImportService.import()
       │
  Decompress → Validate schema version → Deserialize JSON
       │
  ┌────▼─────────────────────────────────────┐
  │  Merge strategy:                          │
  │  - WatchHistory: merge, keep latest date  │
  │  - Watchlist: union (add missing items)   │
  │  - Plugins: union (add missing manifests) │
  │  - Settings: user chooses (keep or overwrite) │
  └───────────────────────────────────────────┘
       │
  Write to Hive → Notify providers → UI refreshes
```

#### Export File Format (`.spovies`)

```json
{
  "schemaVersion": 1,
  "exportedAt": "2026-03-02T14:30:00Z",
  "appVersion": "1.0.0",
  "watchHistory": [ /* UserProgress[] */ ],
  "watchlist": [ /* MediaItem[] (id, type, title, posterPath) */ ],
  "plugins": [ /* PluginManifest[] */ ],
  "settings": {
    "preferredProvider": "example-source",
    "themeMode": "dark",
    "language": "en-US"
  }
}
```

---

### 7.3 Settings Screen Sections

| Section | Options |
|---------|---------|
| **Plugins** | Manage plugins → Add by URL, toggle enable/disable, set preferred, remove. Supports registries (single URL → multiple plugins). |
| **Data** | Export Data, Import Data, Clear Watch History, Clear Watchlist |
| **Appearance** | Theme mode (Dark default) |
| **Playback** | Preferred Provider (dropdown of installed plugins) |
| **About** | App version, TMDB attribution, licenses |

---

### 7.4 Riverpod Providers for Local Data

```dart
// Watchlist
final watchlistProvider = NotifierProvider<WatchlistNotifier, List<MediaItem>>(...);

// Watch history (Continue Watching)
final continueWatchingProvider = FutureProvider<List<UserProgress>>(...);
final watchHistoryProvider = FutureProvider<List<UserProgress>>(...);

// Watch status (library)
final libraryEntriesByStatusProvider = FutureProvider.family<List<MediaStatus>, WatchStatus>(...);

// App settings (persisted to Hive, reactive)
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(...);

// Export/Import
final exportImportServiceProvider = Provider<ExportImportService>((ref) => ...);
```

---

### 7.5 Flutter Packages for Local Data & Export

| Package | Purpose |
|---------|---------|
| `hive_flutter` | Primary local database |
| `path_provider` | Get app documents directory |
| `share_plus` | Share export file via OS share sheet |
| `file_picker` | Let user pick `.spovies` file to import |
| `dart:io` (gzip) | Compress/decompress the export file |

---

## 8. UI/UX Design System

> **Reference:** the original Stitch design mockup (not included in this repository) — The delivered app must match or exceed the visual and interaction quality of this reference at every screen. No component should feel "less polished" than the reference. This section is a binding constraint, not a suggestion.

---

### 8.1 Visual Identity

| Token | Value | Usage |
|-------|-------|-------|
| **Primary** | `#6C2BEE` | Buttons, active states, rating badges glow, progress bars, bottom nav indicator |
| **Background (dark)** | `#0A0A0C` | App background |
| **Surface (dark)** | `#1A1A1E` | Cards, modals, bottom nav |
| **Glass overlay** | `rgba(26, 26, 30, 0.70)` + `blur(12px)` | Glass panels, floating nav, Continue Watching cards |
| **Border (subtle)** | `rgba(255, 255, 255, 0.08)` | Card and glass borders |
| **Text primary** | `#FFFFFF` | Titles, main content |
| **Text secondary** | Slate 400 (`#94A3B8`) | Subtitles, metadata, genres |
| **Glow** | `box-shadow: 0 0 20px -5px rgba(108, 43, 238, 0.3)` | Primary buttons, active elements |
| **Selection** | bg: `#6C2BEE`, text: white | Text selection highlight |

**Flutter mapping:**
- `ThemeData.colorScheme` → seed color `Color(0xFF6C2BEE)`, brightness `Brightness.dark`
- Custom `ColorScheme` extension for `glass`, `surface`, `backgroundDark`

---

### 8.2 Typography

| Role | Font | Weight | Usage |
|------|------|--------|-------|
| **Display** | Spline Sans | 700 | Titles, Hero title, section headers |
| **Body** | Spline Sans | 400 | Overviews, descriptions |
| **Label** | Spline Sans | 600 | Buttons, tags, nav labels |
| **Caption** | Spline Sans | 400 | Metadata, ratings, genres, timestamps |

**Flutter mapping:** Use `google_fonts` package → `GoogleFonts.splineSans(...)`. Define a `AppTextStyles` class with all variants.

---

### 8.3 Iconography

- **Icon set:** Material Symbols Outlined  
- **Flutter package:** `material_symbols_icons`  
- **Icon sizes:** 20px (buttons), 24px (nav), 16px (inline metadata)  
- **Fill variation:** Filled (1) for active states, unfilled (0) for inactive  

---

### 8.4 Spacing & Shape

| Token | Value |
|-------|-------|
| **Base border radius** | 8px (0.5rem) |
| **Large radius** | 16px (1rem) — cards, inputs |
| **XL radius** | 24px (1.5rem) — hero card, bottom nav |
| **2XL radius** | 32px (2rem) — hero poster |
| **Card padding** | 12px |
| **Section padding H** | 24px |
| **Section gap** | 32px between sections |

---

### 8.5 Component Specifications

#### Hero Featured Card
- **Aspect ratio:** 4:5
- **Border radius:** 2xl (32px)
- **Overlay:** `gradient-to-t from-background-dark via-transparent`
- **"Featured Premiere" badge:** `#6C2BEE/90`, `blur(8px)`, rounded-full, top-left
- **Hover/press:** scale `1.05` on poster image (700ms ease-in-out)
- **Primary watch button:** Full width minus icon button, `h: 44px`, purple, `blur glow shadow`
- **Watchlist icon button:** `44x44px`, glass bg, border `white/20`

#### Media Card (Trending / Top Rated rows)
- **Size:** 140px wide, `2:3` aspect ratio
- **Border radius:** xl (16px)
- **Rating badge:** Top-right, `32x32px`, `bg-black/60 blur(8px)`, white bold text, `border: white/10`
- **Hover/press:** poster scale `1.10` (500ms)
- **Snap scroll:** horizontal `snap-x`, no visible scrollbar
- **Card gap:** 16px
- **Text below:** Title (bold, truncated), Genre/Type (slate-400, xs)

#### Continue Watching Glass Panel
- **Height:** `96px` (fixed)
- **Border radius:** xl (16px)
- **Background:** glass panel (blur 12px, gradient)
- **Progress bar:** 4px height, at card bottom, `#6C2BEE`, full-width track `white/5`
- **Thumbnail:** 112px wide, 16px radius, inside card, with `play_circle` overlay on `black/40`
- **Info:** Title (bold, truncated), remaining time (slate-400)

#### Floating Glass Bottom Navigation
- **Position:** Fixed, `bottom: 24px`, `left/right: 24px`
- **Border radius:** 2xl (32px)
- **Background:** glass panel (blur, gradient)
- **Shadow:** `shadow-2xl shadow-black/50`
- **4 tabs:** Home, Explore, Browse (Tickets icon), Profile
- **Active state:** `#6C2BEE` color + dot indicator below icon
- **Inactive state:** Slate-400, hover → white
- **Icon scale on hover:** 1.10 with smooth transition

#### Header / Search Bar
- **Fixed top**, full-width
- **Background:** gradient-to-b from `background-dark` via `background-dark/90` to transparent
- **Logo + greeting:** "Welcome back" label (primary, uppercase tracking-widest xs) + App name (xl, bold, white)
- **Search button:** `40x40px`, rounded-full, surface-dark, `border: white/10`

---

### 8.6 Motion & Animation

| Interaction | Animation |
|-------------|-----------|
| Poster card hover | scale 1.05–1.10, 500–700ms ease-in-out |
| Button tap | `active:scale-95` (95%), instant |
| Screen transitions | Slide/fade, ~300ms |
| WebView open | Full-screen push |
| Continue Watching progress | Animated width change on mount |

---

### 8.7 Dark/Light Mode

- **Default:** Dark mode is the primary and default experience.
- **Light mode:** `background-light: #F6F6F8`, text `slate-900`. Optional — dark is priority.
- **Flutter:** `ThemeMode.dark` default; `ThemeMode.system` can be offered in Settings.

---

### 8.8 Home Screen Layout (Section Order)

1. Header (fixed, top)
2. Hero Featured Movie (first item of `trending/movie/week`)
3. "Now Trending" horizontal scroll row
4. "Continue Watching" glass card (only shown if user has watch history with progress < 90%)
5. "Top Rated" horizontal scroll row
6. Floating Glass Bottom Nav (fixed, bottom)

---

## 9. TMDB API Integration Reference

> **Base URL:** `https://api.themoviedb.org/3`  
> **Auth:** Bearer token in `Authorization` header (API Read Access Token from TMDB account settings)  
> **Rate limit:** ~50 requests per second per IP (TMDB enforced)

---

### 9.1 Authentication

All requests use the **Bearer token** method:

```
Authorization: Bearer <TMDB_READ_ACCESS_TOKEN>
accept: application/json
```

Store the token in `.env` and access via `envied` package (code-generated `Env.tmdbReadAccessToken`). In Flutter, use `Dio` with a base interceptor that attaches this header to every request.

---

### 9.2 Image Base URLs

TMDB images are composed as:

```
https://image.tmdb.org/t/p/{size}/{path}
```

| Size | Use Case |
|------|----------|
| `w92` | Tiny thumbnails |
| `w185` | Card thumbnails (Trending row) |
| `w342` | Standard card posters |
| `w500` | Hero card poster |
| `w780` | Details backdrop |
| `original` | Full-res download |

Always fetch available sizes from `/configuration` on app init and cache locally.

---

### 9.3 Key Endpoints

#### Trending
```
GET /trending/movie/day        → Daily trending movies
GET /trending/movie/week       → Weekly trending (used for Hero)
GET /trending/tv/day           → Daily trending TV
GET /trending/tv/week          → Weekly trending TV
```

Response fields used by Spovies:
- `id`, `title` / `name`, `poster_path`, `backdrop_path`, `vote_average`, `overview`, `genre_ids`, `media_type`, `release_date`

---

#### Movie Details
```
GET /movie/{movie_id}
GET /movie/{movie_id}?append_to_response=credits,videos,images,release_dates
```

Key fields:
- `id`, `imdb_id`, `title`, `overview`, `runtime`, `genres[]`, `vote_average`, `vote_count`
- `poster_path`, `backdrop_path`
- `credits.cast[]` (from append)
- `videos.results[]` → filter `type == "Trailer"` and `site == "YouTube"` for trailer URL
- `release_dates.results[]` → extract certification by country

---

#### TV Show Details
```
GET /tv/{series_id}
GET /tv/{series_id}?append_to_response=credits,videos,aggregate_credits
GET /tv/{series_id}/season/{season_number}
GET /tv/{series_id}/season/{season_number}/episode/{episode_number}
```

Key fields:
- `id`, `name`, `overview`, `first_air_date`, `number_of_seasons`, `number_of_episodes`
- `seasons[]` → `season_number`, `episode_count`, `poster_path`
- Season details: `episodes[]` → `episode_number`, `name`, `overview`, `still_path`, `runtime`

---

#### Search
```
GET /search/multi?query={query}&page=1
GET /search/movie?query={query}&page=1
GET /search/tv?query={query}&page=1
```

Returns `media_type: "movie" | "tv" | "person"` — filter to `movie` and `tv` for display.

---

#### Discover (for curated rows like "Top Rated")
```
GET /movie/top_rated?page=1
GET /movie/popular?page=1
GET /movie/upcoming?page=1
GET /movie/now_playing?page=1
GET /tv/top_rated?page=1
GET /tv/popular?page=1
```

---

#### Genres
```
GET /genre/movie/list
GET /genre/tv/list
```

Map `genre_ids[]` from list results to names using cached genre list. Cache on app init.

---

#### Configuration (run once on init, cache with Hive)
```
GET /configuration
```

Returns image base URLs and available sizes. Cache this permanently with a TTL of 24 hours.

---

### 9.4 Flutter API Wrapper Design

```dart
// lib/data/datasources/remote/tmdb_api.dart

class TmdbApi {
  final Dio _dio;

  TmdbApi(this._dio);

  // Trending
  Future<List<MediaItemModel>> getTrendingMovies();
  Future<List<MediaItemModel>> getTrendingTv();

  // Details (with append_to_response)
  Future<MediaItemModel> getMovieDetails(int id);  // credits,videos,images,release_dates
  Future<MediaItemModel> getTvDetails(int id);      // credits,videos,aggregate_credits
  Future<List<Episode>> getTvSeasonEpisodes(int seriesId, int seasonNumber);

  // Search
  Future<List<MediaItemModel>> search(String query);  // multi-search, filters to movie+tv

  // Curated lists
  Future<List<MediaItemModel>> getTopRatedMovies({int page = 1});
  Future<List<MediaItemModel>> getTopRatedTv({int page = 1});
  Future<List<MediaItemModel>> getPopularMovies({int page = 1});
  Future<List<MediaItemModel>> getPopularTv({int page = 1});

  // Discover by genre
  Future<List<MediaItemModel>> discoverMoviesByGenre(int genreId, {int page = 1});
  Future<List<MediaItemModel>> discoverTvByGenre(int genreId, {int page = 1});

  // Genres
  Future<List<GenreModel>> getMovieGenres();
  Future<List<GenreModel>> getTvGenres();
}
```

**Dio Setup:**

```dart
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://api.themoviedb.org/3',
    headers: {
      'Authorization': 'Bearer ${Env.tmdbReadAccessToken}',
      'accept': 'application/json',
    },
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  dio.interceptors.add(RetryInterceptor(dio, retries: 3));
  dio.interceptors.add(TmdbCacheInterceptor());  // Hive-backed response cache with TTL

  return dio;
});
```

---

### 9.5 Image Loading in Flutter

Use `cached_network_image` for all TMDB images:

```dart
CachedNetworkImage(
  imageUrl: 'https://image.tmdb.org/t/p/w500${media.posterPath}',
  placeholder: (context, url) => ShimmerPlaceholder(),
  errorWidget: (context, url, error) => FallbackPosterWidget(),
  fit: BoxFit.cover,
)
```

- **Shimmer loading state** for all poster/backdrop images (match card dimensions)
- **Fallback widget:** App logo or genre icon on dark surface
- Cache size limit configurable via `CacheManager`

---

### 9.6 Append-to-Response Strategy

To minimize round trips on the Details screen, use a single call with `append_to_response`:

```
GET /movie/{id}?append_to_response=credits,videos,images,release_dates&language=en-US
```

This returns cast, trailer info, additional images, and age rating in one request. Map to:
- `MediaItem.metadata.trailerKey` → YouTube video key for trailer
- `MediaItem.metadata.cast` → List of `CastMember`
- `MediaItem.metadata.certification` → "PG-13", "R", etc.

---

### 9.7 Rate Limiting & Caching Strategy

Caching is handled by `TmdbCacheInterceptor`, a custom Hive-backed Dio interceptor. See [§ 4.4](#44-tmdb-response-caching) for TTL details.

User data (progress, watchlist, watch status) is persisted permanently in Hive and is not subject to TTL expiration.

---

*End of UI/UX Design System & TMDB API Reference*

---

## Appendix A: TriggerHook Constants

```dart
enum TriggerHook {
  mediaHeader,
  episodeItem,
  mediaCardContext,
}

extension TriggerHookX on TriggerHook {
  String get value => switch (this) {
    TriggerHook.mediaHeader => 'media_header',
    TriggerHook.episodeItem => 'episode_item',
    TriggerHook.mediaCardContext => 'media_card_context',
  };
}
```

---

## Appendix B: ActionType & PresentationMode

```dart
enum ActionType {
  webview,
  externalLink,
  metadataFetch,
}

enum PresentationMode {
  fullscreen,
  popover,
}
```

---

*End of Technical Specification Document*
