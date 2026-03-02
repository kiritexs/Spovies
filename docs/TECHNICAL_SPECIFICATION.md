# Spovies — Technical Specification Document (TSD)

**Version:** 1.0  
**Status:** Architecture & Logic (Pre-Implementation)  
**Last Updated:** March 2, 2025

---

## Table of Contents

1. [System Vision & Smart Handling](#1-system-vision--smart-handling)
2. [Technical Architecture](#2-technical-architecture)
3. [Data Model Schema](#3-data-model-schema)
4. [Smart Features](#4-smart-features)
5. [Project Roadmap (5 Phases)](#5-project-roadmap-5-phases)
6. [State Management Flow & Riverpod Structure](#6-state-management-flow--riverpod-structure)
7. [Backend Integration Plan](#7-backend-integration-plan)

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

- [ ] Project setup: Flutter, dependencies (Riverpod, Hive/Isar, Dio)
- [ ] Folder structure per Clean Architecture
- [ ] TMDB API wrapper (search, details, trending)
- [ ] Core entities: `MediaItem`, `Episode`
- [ ] Basic home screen with trending movies
- [ ] Deep-link parsing (no navigation yet)

**Deliverable:** App displays TMDB content; deep links parse correctly.

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

- [ ] Details screen with `media_header` hook zone
- [ ] `MergeMetadataUseCase` for combining TMDB + plugin data
- [ ] `ExecutePluginActionUseCase` (ExternalLink, WebView stubs)
- [ ] Primary + "More Providers" dropdown UI
- [ ] User preference: Preferred Provider in Settings
- [ ] `media_card_context` hook (long-press menu on cards)

**Deliverable:** Details page shows merged metadata; Watch button opens plugin (ExternalLink or WebView placeholder).

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

### Phase 5: Polish & Backend Prep (Weeks 9–10)

- [ ] Theming engine (poster palette → accent color)
- [ ] Intelligent fallback (plugin failure handling)
- [ ] Deep-link navigation to Details
- [ ] Backend API client (Django REST) for watchlist sync
- [ ] Auth flow placeholder for future cloud sync
- [ ] Performance tuning, error handling, analytics hooks

**Deliverable:** Production-ready app; backend integration ready for Phase 6.

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

## 7. Backend Integration Plan

### 7.1 Django REST API (Future)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/auth/token/` | POST | Login; returns JWT |
| `/api/watchlist/` | GET | User's watchlist |
| `/api/watchlist/` | POST | Add to watchlist |
| `/api/watchlist/{id}/` | DELETE | Remove from watchlist |
| `/api/progress/` | GET | Sync user progress (batch) |
| `/api/progress/` | POST | Upload progress |
| `/api/progress/sync/` | POST | Conflict resolution (last-write-wins or merge) |

### 7.2 Flutter Client Strategy

- **Offline-first:** Local Hive/Isar is source of truth; sync when online.
- **Background sync:** Use `workmanager` or similar for periodic upload.
- **Conflict resolution:** Server timestamp wins; client sends `lastPlayedDate` for comparison.
- **Auth:** Store JWT in `flutter_secure_storage`; refresh token flow.

### 7.3 Data Sync Flow

```
Local Hive ──► SyncService ──► Django REST ──► PostgreSQL
     ▲                │
     │                │ (on success)
     └────────────────┘
```

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
