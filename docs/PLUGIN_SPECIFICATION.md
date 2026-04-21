# Spovies Plugin Specification

**For 3rd Party Developers**

This document explains how to build a plugin for Spovies — a modular, plugin-based media discovery platform. Plugins extend Spovies by adding streaming sources, metadata providers, or external links.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Plugin Manifest](#2-plugin-manifest)
3. [Trigger Hooks](#3-trigger-hooks)
4. [Action Types](#4-action-types)
5. [URL Templates](#5-url-templates)
6. [Event Bridge (WebView Plugins)](#6-event-bridge-webview-plugins)
7. [Metadata Fetch Plugins](#7-metadata-fetch-plugins)
8. [Hosting & Discovery](#8-hosting--discovery)
9. [Security & Sandboxing](#9-security--sandboxing)
10. [Examples](#10-examples)

---

## 1. Overview

A Spovies plugin is defined by a **JSON manifest** hosted at a public URL. The app fetches this manifest and registers your plugin based on its configuration. **No app update is required** — users add your plugin by pasting the manifest URL in Settings.

### What a Plugin Can Do

| Capability | Description |
|------------|-------------|
| **Add a "Watch" button** | Your streaming site appears as an option when users want to watch content |
| **Add metadata** | Enrich movie/show details with ratings, cast, or other data |
| **Link externally** | Open your website or app when user taps your action |
| **Track progress** | (WebView only) Send play progress so Spovies can show "Continue Watching" |

### What a Plugin Cannot Do

- Access the user's device or other apps directly
- Run arbitrary code outside a sandboxed WebView
- Override or remove other plugins
- Access TMDB or Spovies internal APIs

---

## 2. Plugin Manifest

Your plugin is a **single JSON file** with the following schema.

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `pluginId` | string | Unique identifier (e.g., `example-source`, `my-stream-site`). Use lowercase, no spaces. Cannot be empty. |
| `name` | string | Display name shown in the app |
| `urlTemplate` | string | URL with placeholders (see [URL Templates](#5-url-templates)) |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `version` | string | `"1.0.0"` | Semantic version |
| `description` | string | `""` | Short description of what your plugin does |
| `iconUrl` | string | — | URL to your plugin's icon (recommended: 128x128 PNG) |
| `hooks` | string[] | `["media_header"]` | Array of [Trigger Hooks](#3-trigger-hooks) where your action appears |
| `actionType` | string | `"webview"` | One of: `webview`, `externalLink`, `metadataFetch` |
| `presentationMode` | string | `"fullscreen"` | For WebView: `fullscreen` or `popover` |
| `eventBridgeConfig` | object | — | For WebView plugins that track progress (see [Event Bridge](#6-event-bridge-webview-plugins)) |

### Minimal Example

```json
{
  "pluginId": "my-plugin",
  "name": "My Streaming Site",
  "urlTemplate": "https://mystream.com/watch/{{type}}/{{tmdbId}}"
}
```

---

## 3. Trigger Hooks

Trigger hooks define **where** your plugin's action appears in the Spovies UI. The app defines these slots; you choose which ones to use.

| Hook | Location | Use Case |
|------|----------|----------|
| `media_header` | Main action button on Movie/Show details page | Primary "Watch" or "Stream" CTA |
| `episode_item` | Play icon next to each episode in a TV show | Per-episode streaming |
| `media_card_context` | Long-press menu or quick-play overlay on home/search cards | Quick access from discovery |

### Multiplicity

You can register for **multiple hooks** in a single manifest:

```json
{
  "hooks": ["media_header", "episode_item"]
}
```

This means your plugin will appear:
- On the details page as a Watch option
- Next to each episode in a TV series

---

## 4. Action Types

| Action Type | Behavior |
|-------------|----------|
| `webview` | Opens your URL inside Spovies in a full-screen WebView. Supports progress tracking via postMessage. |
| `externalLink` | Opens your URL in the device's default browser or external app. |
| `metadataFetch` | Your plugin provides metadata only; no user-facing action. Used for enriching details (e.g., ratings). |

### When to Use Each

- **webview:** Streaming sites where users watch inside the app. Enables "Continue Watching" and progress tracking.
- **externalLink:** Sites that require login, or apps that should open natively (e.g., Netflix, Prime).
- **metadataFetch:** APIs or services that add data (ratings, cast) but don't have a "watch" action.

---

## 5. URL Templates

The `urlTemplate` is a string with `{{placeholder}}` tokens (double curly braces) that Spovies replaces when the user taps your action.

### Supported Placeholders

| Placeholder | Replaced With | Example |
|-------------|---------------|---------|
| `{{tmdbId}}` | TMDB ID of the movie/show | `12345` |
| `{{id}}` | Alias for `{{tmdbId}}` | `12345` |
| `{{type}}` | `movie` or `tv` | `movie` |
| `{{title}}` | URL-encoded title | `Inception` |
| `{{imdbId}}` | IMDb ID (if available, else empty) | `tt1375666` |
| `{{season}}` | Season number (for TV) | `1` |
| `{{episode}}` | Episode number (for TV) | `5` |

**TV path fallback:** If your template does **not** contain `{{season}}` or `{{episode}}` but the media is a TV show, the app appends `/season/episode` as path segments (e.g. `/1/1` for S1E1).

### Examples

```
https://example.com/embed/{{type}}/{{tmdbId}}
https://mystream.com/search?q={{title}}
https://example.com/movie/{{imdbId}}
https://example.com/show/{{tmdbId}}/s{{season}}e{{episode}}
```

### Encoding

- `{{title}}` is automatically URL-encoded.
- Other values are inserted as-is. Ensure your server handles special characters.

---

## 6. Event Bridge (WebView Plugins)

If your plugin uses `actionType: "webview"` and you want Spovies to track watch progress (for "Continue Watching"), you must:

1. Add `eventBridgeConfig` to your manifest
2. Send `postMessage` events from your web page to the Spovies WebView

### Manifest Configuration

```json
{
  "actionType": "webview",
  "eventBridgeConfig": {
    "postMessageOrigin": "*",
    "allowedEventTypes": ["progress", "pause", "stop", "heartbeat"]
  }
}
```

| Field | Description |
|-------|-------------|
| `postMessageOrigin` | Allowed origin for `postMessage` (use `"*"` to allow any, or your domain for security). |
| `allowedEventTypes` | Optional allowlist of events your page will send. Default includes `progress`, `pause`, `stop`, `heartbeat`. |

### PostMessage Format (Recommended: PLAYER_EVENT)

The recommended format wraps events in a `PLAYER_EVENT` type:

```javascript
window.postMessage(JSON.stringify({
  type: "PLAYER_EVENT",
  data: {
    event: "timeupdate",    // timeupdate, play, pause, ended, seeked
    currentTime: 120.5,     // Current position in seconds
    duration: 7200,         // Total duration in seconds
    progress: 1.6,          // Progress percentage (0–100)
    id: "299534",           // TMDB ID (string)
    mediaType: "movie",     // "movie" or "tv"
    season: 1,              // Optional; for TV
    episode: 8              // Optional; for TV
  }
}), "*");
```

### Supported Event Formats

The Event Bridge auto-detects multiple postMessage formats:

| Format | Structure | Used By |
|--------|-----------|---------|
| **PLAYER_EVENT** (recommended) | `{ type: "PLAYER_EVENT", data: { event, currentTime, duration, ... } }` | Provider A, custom plugins |
| **Provider D** | `{ channel, event, time, duration, percent }` | Provider D |
| **Provider C native** | `{ event: "time"\|"pause"\|"userpause", time, duration }` | Provider C |

### Throttling Behavior

| Event | Behavior |
|-------|----------|
| `timeupdate`, `seeked`, `play` | Throttled to 1 write per 5 seconds |
| `pause`, `ended` | Saved immediately (no throttle) |

### Universal HTML5 Fallback

Even if your plugin does **not** implement `postMessage`, Spovies injects a universal script that monitors any `<video>` element on the page. This means basic progress tracking works out of the box for most streaming pages.

### Best Practices

- **Send events on both `timeupdate` and `pause`** — the app throttles `timeupdate` automatically.
- **Include both `currentTime` and `duration`** so the app can calculate percentage accurately.
- **The `ended` event triggers immediate save** — send it when playback finishes.

---

## 7. Metadata Fetch Plugins

If `actionType` is `metadataFetch`, your plugin does not add a button. Instead, Spovies calls your URL and expects a JSON response to **merge** into the media details.

### Expected Response Format

```json
{
  "rating": 8.4,
  "imdbId": "tt1375666",
  "trailerUrl": "https://youtube.com/watch?v=...",
  "cast": [
    { "name": "Leonardo DiCaprio", "role": "Cobb" }
  ]
}
```

### URL Template

Use the same placeholders as for actions. Spovies will fetch your URL when loading details:

```json
{
  "urlTemplate": "https://api.myratings.com/movie/{{tmdbId}}",
  "actionType": "metadataFetch"
}
```

### Merge Behavior

- Spovies merges your response with TMDB data.
- Your fields **override** TMDB only if TMDB has no value, or if your field is "richer" (e.g., you provide IMDb when TMDB doesn't).
- Conflicting ratings: first non-null wins unless user has a preference.

---

## 8. Hosting & Discovery

### Hosting Your Manifest

1. Host your `manifest.json` at a public HTTPS URL.
2. Ensure CORS allows `GET` from any origin (or at least from Spovies).
3. Use a stable URL — users will add it in Settings.

### Example URLs

```
https://example.com/spovies/manifest.json
https://raw.githubusercontent.com/yourorg/spovies-plugin/main/manifest.json
```

### Plugin Registries

A single URL can return **multiple plugins** by responding with either:

- A **JSON array** of manifest objects: `[ { manifest1 }, { manifest2 } ]`
- A **registry object** with a `plugins` key: `{ "plugins": [ { manifest1 }, { manifest2 } ] }`

This lets you distribute a collection of plugins from one URL.

### User Installation

1. User opens Spovies → Settings → Manage Plugins
2. User pastes your manifest URL (or registry URL)
3. Spovies fetches, validates, and registers the plugin(s)
4. Plugins appear in the configured hook zones
5. User can toggle enable/disable, set preferred provider, or remove

### Validation

Spovies validates your manifest against the schema. Invalid manifests are rejected with a detailed error message. Ensure:
- All required fields are present (`pluginId`, `name`, `urlTemplate`)
- `hooks` (if provided) contains only valid values: `media_header`, `episode_item`, `media_card_context`
- `actionType` (if provided) is one of: `webview`, `externalLink`, `metadataFetch`
- `urlTemplate` is a valid URL format

---

## 9. Security & Sandboxing

### What Spovies Does

- **WebView isolation:** Your page runs in a sandboxed WebView. No direct access to the Flutter app or device.
- **Origin validation:** `postMessage` is filtered by `eventBridgeConfig.postMessageOrigin` (`"*"` allows any origin).
- **HTTPS only:** Manifests and URLs must use HTTPS (except localhost for development).

### What You Should Do

- **Use HTTPS** for your manifest and all URLs.
- **Validate `mediaId`** on your server — never trust it blindly for sensitive operations.
- **Rate limit** your metadata API if applicable.
- **Keep your manifest minimal** — don't include secrets or API keys.

---

## 10. Examples

### Example 1: Simple External Link Plugin

```json
{
  "pluginId": "justwatch",
  "version": "1.0.0",
  "name": "JustWatch",
  "description": "Find where to stream on JustWatch",
  "iconUrl": "https://justwatch.com/favicon.png",
  "hooks": ["media_header", "media_card_context"],
  "urlTemplate": "https://www.justwatch.com/search?q={{title}}",
  "actionType": "externalLink"
}
```

### Example 2: WebView Plugin with Progress Tracking

```json
{
  "pluginId": "example-source",
  "version": "1.2.0",
  "name": "Provider A",
  "description": "Stream movies and shows",
  "iconUrl": "https://example.com/icon.png",
  "hooks": ["media_header", "episode_item"],
  "urlTemplate": "https://example.com/embed/{{type}}/{{tmdbId}}",
  "actionType": "webview",
  "presentationMode": "fullscreen",
  "eventBridgeConfig": {
    "postMessageOrigin": "*",
    "allowedEventTypes": ["progress", "pause", "stop", "heartbeat"]
  }
}
```

### Example 3: Metadata-Only Plugin

```json
{
  "pluginId": "imdb-ratings",
  "version": "1.0.0",
  "name": "IMDb Ratings",
  "description": "Add IMDb ratings to details",
  "hooks": ["media_header"],
  "urlTemplate": "https://api.myimdb.com/movie/{{tmdbId}}/rating",
  "actionType": "metadataFetch"
}
```

### Example 4: Minimal Plugin (required fields only)

```json
{
  "pluginId": "my-plugin",
  "name": "My Plugin",
  "urlTemplate": "https://mysite.com/watch/{{type}}/{{tmdbId}}"
}
```

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-03-02 | Initial specification |
| 2.0 | 2026-04-21 | Updated placeholder format to `{{tmdbId}}`/`{{type}}`, added registry support, documented multi-format Event Bridge (Provider A, Provider D, Provider C), added universal HTML5 fallback, corrected required/optional fields |

---

*For questions or to submit your plugin for inclusion in the official Spovies plugin directory, contact the Spovies team.*
