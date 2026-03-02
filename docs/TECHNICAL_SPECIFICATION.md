# Spovies — Technical Specification Document (TSD)

**Version:** 1.1  
**Status:** Architecture & Logic (Pre-Implementation)  
**Last Updated:** March 2, 2026

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

**Multiplicity:** A single plugin (e.g., Provider A) can register for multiple hooks via `hooks: ["media_header", "episode_item"]`.

---

### 1.2 Smart Metadata Merging

Multiple plugins may contribute metadata for the same media item:

- **Plugin A:** Stream URL, quality info  
- **Plugin B:** IMDb rating, cast  
- **Plugin C:** Trailer link  

The app merges these into a **Unified Details View** using:

1. **Source Priority:** TMDB (canonical) > Plugin metadata (enrichment)
2. **Conflict Resolution:** First non-null wins per field; user preference can override for ratings
3. **Aggregation:** Arrays (e.g., stream sources) are concatenated and deduplicated

---

### 1.3 Event-Driven Progress

| Event | Source | Action |
|-------|--------|--------|
| `progress` | WebView `postMessage` | Update local `WatchHistory` |
| `pause` / `stop` | WebView `postMessage` | Update progress + timestamp |
| `heartbeat` | WebView (every 5–10 sec) | Continuous sync for crash resilience |

**Flow:** WebView → `EventBridge` → `TrackProgressUseCase` → `WatchHistoryRepository` → Hive/Isar

**Continue Watching:** Home screen reads `WatchHistory` sorted by `LastPlayedDate`, shows items with `Percentage < 90`.

---

### 1.4 Plugin Sandboxing & Dynamic Loading

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
├── core/                          # Shared utilities, constants, config
│   ├── config/
│   │   ├── app_config.dart
│   │   └── deep_link_config.dart
│   ├── constants/
│   │   └── trigger_hooks.dart
│   ├── errors/
│   │   ├── app_exception.dart
│   │   └── plugin_exception.dart
│   ├── theme/
│   │   ├── app_theme.dart
│   │   └── palette_extractor.dart
│   └── utils/
│       └── url_validator.dart
│
├── data/
│   ├── datasources/
│   │   ├── remote/
│   │   │   ├── tmdb_api.dart
│   │   │   └── plugin_manifest_api.dart
│   │   └── local/
│   │       ├── watch_history_repository_impl.dart
│   │       └── hive_box.dart
│   ├── models/
│   │   ├── media_item_model.dart
│   │   ├── plugin_manifest_model.dart
│   │   └── user_progress_model.dart
│   └── repositories/
│       ├── media_repository_impl.dart
│       ├── plugin_repository_impl.dart
│       └── watch_history_repository_impl.dart
│
├── domain/
│   ├── entities/
│   │   ├── media_item.dart
│   │   ├── plugin.dart
│   │   ├── episode.dart
│   │   └── user_progress.dart
│   ├── repositories/
│   │   ├── media_repository.dart
│   │   ├── plugin_repository.dart
│   │   └── watch_history_repository.dart
│   └── usecases/
│       ├── fetch_details_usecase.dart
│       ├── execute_plugin_action_usecase.dart
│       ├── track_progress_usecase.dart
│       ├── merge_metadata_usecase.dart
│       └── get_continue_watching_usecase.dart
│
├── presentation/
│   ├── providers/                  # Riverpod providers
│   │   ├── media_providers.dart
│   │   ├── plugin_providers.dart
│   │   ├── details_providers.dart
│   │   └── watch_history_providers.dart
│   ├── screens/
│   │   ├── home/
│   │   ├── details/
│   │   ├── search/
│   │   └── settings/
│   └── widgets/
│       ├── media_card.dart
│       ├── plugin_action_button.dart
│       ├── unified_details_view.dart
│       └── webview_player.dart
│
└── plugins/                       # Plugin runtime & protocol
    ├── protocol/
    │   ├── spovies_plugin.dart
    │   ├── trigger_hook.dart
    │   └── action_type.dart
    ├── event_bridge/
    │   ├── event_bridge.dart
    │   └── post_message_handler.dart
    └── discovery/
        └── plugin_discovery_service.dart
```

---

### 2.3 Layer Responsibilities

| Layer | Responsibility |
|-------|----------------|
| **Data** | TMDB API, HTTP for plugin manifests, Hive/Isar persistence, model serialization |
| **Domain** | Entities (pure Dart), use case interfaces, repository contracts |
| **Presentation** | Riverpod state, UI widgets, screens, theme application |

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
  "name": "Provider A",
  "description": "Stream movies and shows",
  "iconUrl": "https://example.com/icon.png",
  "hooks": ["media_header", "episode_item"],
  "urlTemplate": "https://example.com/watch/{mediaId}?type={mediaType}",
  "actionType": "webview",
  "presentationMode": "fullscreen",
  "eventBridgeConfig": {
    "postMessageOrigin": "https://example.com",
    "allowedEvents": ["progress", "pause", "stop", "heartbeat"]
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
  "episodeId": null,
  "timestamp": 3600,
  "percentage": 65.5,
  "lastPlayedDate": "2025-03-02T14:30:00Z",
  "pluginId": "example-source"
}
```

**Dart Class (Entity):**

```dart
class UserProgress {
  final String mediaId;
  final MediaType mediaType;
  final String? episodeId;
  final int timestamp;
  final double percentage;
  final DateTime lastPlayedDate;
  final String? pluginId;
}
```

---

## 4. Smart Features

### 4.1 Intelligent Fallback

| Scenario | Behavior |
|----------|----------|
| Plugin fails to load URL | Show "Provider unavailable" toast; suggest alternative plugin in dropdown if available |
| All plugins fail | Show "No providers available" with retry button; log for analytics |
| Network error | Retry with exponential backoff; show cached data if available |
| Invalid manifest | Skip plugin; log error; notify user in Settings > Plugins |

### 4.2 Deep-Link Handling

**Scheme:** `spovies://details/{type}/{id}`

**Examples:**
- `spovies://details/movie/12345`
- `spovies://details/tv/67890`

**Flow:** Parse URI → `DeepLinkHandler` → `FetchDetailsUseCase` → Navigate to Details screen with `MediaItem` loaded.

### 4.3 Theming Engine

- **Palette Generator:** Extract dominant color from poster image (e.g., `palette_generator` package).
- **Apply:** Use as accent color for buttons, progress bars, highlights.
- **Fallback:** Default theme if no poster or extraction fails.

---

## 5. Project Roadmap (5 Phases)

### Phase 1: Foundation (Weeks 1–2)

- [ ] Project setup: Flutter, dependencies (Riverpod, Hive/Isar, Dio, `google_fonts`, `cached_network_image`, `material_symbols_icons`)
- [ ] Folder structure per Clean Architecture
- [ ] Design system: `AppTheme`, `AppColors`, `AppTextStyles`, `AppSpacing` matching `stitch/code.html` tokens
- [ ] TMDB API wrapper: `TmdbApi` class with Bearer token auth, `/configuration`, `/genre/movie/list`, `/trending/movie/week`
- [ ] Image loading with `CachedNetworkImage` + shimmer placeholder
- [ ] Core entities: `MediaItem`, `Episode`
- [ ] Home screen with Hero card (4:5), "Now Trending" horizontal snap row, glass bottom nav
- [ ] Deep-link parsing (no navigation yet)

**Deliverable:** App renders TMDB content with full design-system fidelity matching `code.html`; Hero + Trending row + glass nav functional.

---

### Phase 2: Plugin Protocol & Discovery (Weeks 3–4)

- [ ] `SpoviesPlugin` interface and `PluginManifest` model
- [ ] Plugin Discovery Service (fetch manifest from URL)
- [ ] TriggerHook enum and zone constants
- [ ] Mock plugin for testing
- [ ] Plugin list in Settings (manual URL entry)
- [ ] Plugin repository + local cache of manifests

**Deliverable:** App can load and display plugin manifests; Settings shows installed plugins.

---

### Phase 3: Unified Details & Plugin Actions (Weeks 5–6)

- [ ] Details screen: backdrop hero, cast row, trailer chip, rating badge, age cert — all from `append_to_response` single call
- [ ] `MergeMetadataUseCase` for combining TMDB + plugin data
- [ ] `ExecutePluginActionUseCase` (ExternalLink, WebView stubs)
- [ ] Primary + "More Providers" dropdown UI (glass bottom sheet)
- [ ] User preference: Preferred Provider in Settings
- [ ] `media_card_context` hook (long-press glass context menu on cards)
- [ ] Palette generator: extract dominant color from poster, animate accent color

**Deliverable:** Details page shows merged metadata with cinematic layout; Watch button opens plugin; accent color adapts to content.

---

### Phase 4: WebView Player & Progress Tracking (Weeks 7–8)

- [ ] Full-screen WebView container with landscape support
- [ ] Swipe-down to minimize → PiP mini-player
- [ ] EventBridge: `postMessage` listener
- [ ] `TrackProgressUseCase` + `WatchHistoryRepository`
- [ ] Hive/Isar schema for `UserProgress`
- [ ] Continue Watching row on home screen
- [ ] `episode_item` hook for TV episodes

**Deliverable:** Watch in WebView; progress saved; Continue Watching works.

---

### Phase 5: Polish & Export/Import (Weeks 9–10)

- [ ] Theming engine (poster palette → accent color)
- [ ] Intelligent fallback (plugin failure handling)
- [ ] Deep-link navigation to Details
- [ ] Settings screen: all sections (Data, Plugins, Appearance, Playback, About)
- [ ] Export / Import feature (`ExportService`, `ImportService`, `.spovies` file format)
- [ ] Share export via `share_plus`; import via `file_picker`
- [ ] Performance tuning, error handling, shimmer/skeleton states on all loading UI

**Deliverable:** Production-ready, fully local app. Users can back up and restore all data without any server.

---

## 6. State Management Flow & Riverpod Structure

### 6.1 Data Flow Overview

```
TMDB API ──► MediaRepository ──► FetchDetailsUseCase
                                      │
Plugin Discovery ──► PluginRepository ──► GetPluginsForHookUseCase
                                      │
                                      ▼
                            MergeMetadataUseCase
                                      │
                                      ▼
                            detailsProvider (AsyncValue<UnifiedDetails>)
                                      │
                                      ▼
                            UnifiedDetailsView (UI)
```

---

### 6.2 Riverpod Provider Architecture

#### A. Media Providers (TMDB Data)

```dart
// Raw TMDB data - single source of truth from API
final mediaRepositoryProvider = Provider<MediaRepository>((ref) => ...);

final mediaDetailsProvider = FutureProvider.family<MediaItem, String>((ref, mediaId) async {
  final repo = ref.watch(mediaRepositoryProvider);
  return repo.getDetails(mediaId);
});

// For TV: fetches season/episode structure
final tvDetailsProvider = FutureProvider.family<MediaItem, String>((ref, mediaId) async {
  final repo = ref.watch(mediaRepositoryProvider);
  return repo.getTvDetails(mediaId);
});
```

#### B. Plugin Providers

```dart
// All installed plugins (from discovery + user config)
final pluginRepositoryProvider = Provider<PluginRepository>((ref) => ...);

final installedPluginsProvider = FutureProvider<List<PluginManifest>>((ref) async {
  final repo = ref.watch(pluginRepositoryProvider);
  return repo.getInstalledPlugins();
});

// Plugins for a specific hook - used by UI to render buttons
final pluginsForHookProvider = FutureProvider.family<List<PluginManifest>, TriggerHook>((ref, hook) async {
  final plugins = await ref.watch(installedPluginsProvider.future);
  return plugins.where((p) => p.hooks.contains(hook)).toList();
});

// User's preferred provider (from Settings)
final preferredProviderProvider = StateProvider<String?>((ref) => null);
```

#### C. Unified Details Provider (The Merge Logic)

This is the core provider that combines TMDB + Plugin data:

```dart
// Input: mediaId, mediaType
// Output: UnifiedDetails (TMDB data + plugin actions + enriched metadata)

final unifiedDetailsProvider = FutureProvider.family<UnifiedDetails, UnifiedDetailsParams>((ref, params) async {
  // 1. Fetch TMDB data (base)
  final mediaFuture = params.mediaType == MediaType.movie
      ? ref.watch(mediaDetailsProvider(params.mediaId).future)
      : ref.watch(tvDetailsProvider(params.mediaId).future);
  
  final media = await mediaFuture;
  
  // 2. Fetch plugins for media_header (and episode_item if TV)
  final pluginsForHeader = await ref.watch(pluginsForHookProvider(TriggerHook.mediaHeader).future);
  final preferredId = ref.watch(preferredProviderProvider);
  
  // 3. Merge metadata from plugins (if any provide MetadataFetch)
  final metadataPlugins = pluginsForHeader.where((p) => p.actionType == ActionType.metadataFetch);
  final mergedMetadata = await ref.read(mergeMetadataUseCaseProvider).execute(
    MergeMetadataParams(media: media, plugins: metadataPlugins),
  );
  
  // 4. Build ordered plugin actions (Primary + List)
  //    - If preferredId set and found: that plugin first, rest after
  //    - Else: plugins in discovery order (first = primary, rest in dropdown)
  final preferred = preferredId != null
      ? pluginsForHeader.where((p) => p.pluginId == preferredId).toList()
      : <PluginManifest>[];
  final rest = preferredId != null
      ? pluginsForHeader.where((p) => p.pluginId != preferredId).toList()
      : pluginsForHeader;
  final orderedPlugins = preferred.isNotEmpty ? [...preferred, ...rest] : rest;
  
  // 5. For TV: get plugins per episode
  List<Map<Episode, List<PluginManifest>>>? episodePlugins;
  if (params.mediaType == MediaType.tv && media.episodes != null) {
    final pluginsForEpisode = await ref.watch(pluginsForHookProvider(TriggerHook.episodeItem).future);
    episodePlugins = media.episodes!.map((ep) => {ep: pluginsForEpisode}).toList();
  }
  
  return UnifiedDetails(
    media: media.copyWith(metadata: mergedMetadata),
    headerPlugins: orderedPlugins,
    episodePlugins: episodePlugins,
  );
});
```

#### D. Watch History Providers

```dart
final watchHistoryRepositoryProvider = Provider<WatchHistoryRepository>((ref) => ...);

final continueWatchingProvider = FutureProvider<List<UserProgress>>((ref) async {
  final repo = ref.watch(watchHistoryRepositoryProvider);
  return repo.getContinueWatching(limit: 10);
});

// For a specific media: current progress (for "Resume" button)
final progressForMediaProvider = FutureProvider.family<UserProgress?, String>((ref, mediaId) async {
  final repo = ref.watch(watchHistoryRepositoryProvider);
  return repo.getProgress(mediaId);
});
```

#### E. Provider Dependencies Diagram

```
                    ┌─────────────────────┐
                    │ mediaRepository     │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │ mediaDetailsProvider│
                    └──────────┬──────────┘
                               │
┌─────────────────────┐       │       ┌─────────────────────┐
│ pluginRepository     │       │       │ preferredProvider    │
└──────────┬──────────┘       │       └──────────┬──────────┘
           │                  │                  │
           ▼                  │                  │
┌─────────────────────┐       │                  │
│ pluginsForHook      │       │                  │
└──────────┬──────────┘       │                  │
           │                  │                  │
           └──────────────────┼──────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │ mergeMetadataUseCase│
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │ unifiedDetailsProvider│  ◄── THE MERGE
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │ DetailsScreen       │
                    └────────────────────┘
```

---

### 6.3 Handling Plugin Action Execution

When user taps "Watch" (or selects from dropdown):

```dart
// In ExecutePluginActionUseCase
// 1. Resolve URL from template: urlTemplate.replaceAll('{mediaId}', media.id)
// 2. If actionType == webview: Open WebViewPlayer with URL + EventBridge
// 3. If actionType == externalLink: Launch url_launcher
// 4. If actionType == metadataFetch: Already handled in merge; no action
```

The `WebViewPlayer` widget:
- Injects JavaScript to listen for `postMessage` from the loaded page
- Forwards events to `EventBridge` → `TrackProgressUseCase`
- Handles swipe-down for PiP

---

## 7. Local-First Data Strategy

> **Decision:** There is no backend. The app is fully local. All user data lives in Hive/Isar on-device. Users can back up and restore their data via an **Export / Import** feature in Settings. No auth, no cloud sync, no server.

---

### 7.1 What is Stored Locally (Hive/Isar)

| Data | Box / Collection | Description |
|------|-----------------|-------------|
| `WatchHistory` | `watchHistoryBox` | Progress records per media item (`UserProgress`) |
| `Watchlist` | `watchlistBox` | User's saved/bookmarked media |
| `InstalledPlugins` | `pluginsBox` | Cached plugin manifests (fetched from URLs) |
| `TmdbCache` | `tmdbCacheBox` | Cached API responses with TTL |
| `GenreCache` | `genreCacheBox` | Movie + TV genre lists |
| `TmdbConfig` | `configBox` | TMDB image configuration |
| `AppSettings` | `settingsBox` | Theme mode, preferred provider, language, etc. |

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
| **Data** | Export Data, Import Data, Clear Watch History, Clear Watchlist |
| **Plugins** | Add Plugin (paste URL), installed plugin list, remove plugin |
| **Appearance** | Theme mode (Dark / Light / System), Language |
| **Playback** | Preferred Provider (dropdown of installed plugins) |
| **About** | App version, TMDB attribution, Spovies plugin docs link |

---

### 7.4 Riverpod Providers for Local Data

```dart
// Watchlist
final watchlistProvider = NotifierProvider<WatchlistNotifier, List<MediaItem>>(...);

// Watch history (Continue Watching)
final watchHistoryProvider = NotifierProvider<WatchHistoryNotifier, List<UserProgress>>(...);

// App settings (persisted to Hive, reactive)
final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(...);

// Export/Import
final exportServiceProvider = Provider<ExportService>((ref) => ExportService(ref));
final importServiceProvider = Provider<ImportService>((ref) => ImportService(ref));
```

---

### 7.5 Flutter Packages for Local Data & Export

| Package | Purpose |
|---------|---------|
| `hive_flutter` / `isar` | Primary local database |
| `path_provider` | Get app documents directory |
| `share_plus` | Share export file via OS share sheet |
| `file_picker` | Let user pick `.spovies` file to import |
| `archive` | gzip compress/decompress the export file |

---

## 8. UI/UX Design System

> **Reference:** `stitch/code.html` — The delivered app must match or exceed the visual and interaction quality of this reference at every screen. No component should feel "less polished" than the reference. This section is a binding constraint, not a suggestion.

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
| WebView open | Bottom sheet slide-up or full-screen push |
| Mini-player appear | Slide up from bottom, 300ms spring |
| Palette color change | Animated color interpolation, 500ms |
| Continue Watching progress | Animated width change on mount |

---

### 8.7 Dark/Light Mode

- **Default:** Dark mode is the primary and default experience.
- **Light mode:** `background-light: #F6F6F8`, text `slate-900`. Optional — dark is priority.
- **Flutter:** `ThemeMode.dark` default; `ThemeMode.system` can be offered in Settings.

---

### 8.8 Home Screen Layout (Section Order)

1. Header (fixed, top)
2. Hero Featured Movie (first item of `trending/movie/week` or editor-picked)
3. "Now Trending" horizontal scroll row
4. "Continue Watching" glass card (only shown if user has watch history)
5. "Top Rated" horizontal scroll row
6. (Phase 5+) "New Releases", "For You" rows
7. Floating Glass Bottom Nav (fixed, bottom)

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

Store the token in `flutter_secure_storage` or `.env` (never hardcoded). In Flutter, use `Dio` with a base interceptor that attaches this header to every request.

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
  Future<List<MediaItemModel>> getTrendingMovies({String window = 'week'});
  Future<List<MediaItemModel>> getTrendingTv({String window = 'day'});

  // Details
  Future<MediaItemModel> getMovieDetails(int id);
  Future<MediaItemModel> getTvDetails(int id);
  Future<SeasonModel> getSeason(int seriesId, int seasonNumber);

  // Search
  Future<List<MediaItemModel>> search(String query);

  // Curated lists
  Future<List<MediaItemModel>> getTopRatedMovies({int page = 1});
  Future<List<MediaItemModel>> getPopularMovies({int page = 1});
  Future<List<MediaItemModel>> getUpcomingMovies({int page = 1});

  // Config & genres
  Future<TmdbConfigModel> getConfiguration();
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
  dio.interceptors.add(LogInterceptor()); // remove in production

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

| Data Type | Cache TTL | Storage |
|-----------|-----------|---------|
| Configuration | 24 hours | Hive |
| Genre lists | 24 hours | Hive |
| Trending lists | 30 minutes | Hive |
| Movie/TV details | 1 hour | Hive |
| Search results | No cache | In-memory only |
| User progress | Persistent | Hive/Isar |

Use `dio_cache_interceptor` or a custom Hive-backed cache layer.

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
