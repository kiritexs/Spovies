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
| `pluginId` | string | Unique identifier (e.g., `example-source`, `my-stream-site`). Use lowercase, no spaces. |
| `version` | string | Semantic version (e.g., `1.0.0`) |
| `name` | string | Display name shown in the app |
| `description` | string | Short description of what your plugin does |
| `hooks` | string[] | Array of [Trigger Hooks](#3-trigger-hooks) where your action appears |
| `urlTemplate` | string | URL with placeholders (see [URL Templates](#5-url-templates)) |
| `actionType` | string | One of: `webview`, `externalLink`, `metadataFetch` |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `iconUrl` | string | URL to your plugin's icon (recommended: 128x128 PNG) |
| `presentationMode` | string | For WebView: `fullscreen` (default) or `popover` |
| `eventBridgeConfig` | object | Required for WebView plugins that track progress (see [Event Bridge](#6-event-bridge-webview-plugins)) |

### Minimal Example

```json
{
  "pluginId": "my-plugin",
  "version": "1.0.0",
  "name": "My Streaming Site",
  "description": "Watch movies and shows on MyStream",
  "hooks": ["media_header"],
  "urlTemplate": "https://mystream.com/watch/{mediaId}",
  "actionType": "externalLink"
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

- **webview:** Streaming sites where users watch inside the app. Enables "Continue Watching" and PiP.
- **externalLink:** Sites that require login, or apps that should open natively (e.g., Netflix, Prime).
- **metadataFetch:** APIs or services that add data (ratings, cast) but don't have a "watch" action.

---

## 5. URL Templates

The `urlTemplate` is a string with placeholders that Spovies replaces when the user taps your action.

### Supported Placeholders

| Placeholder | Replaced With | Example |
|-------------|---------------|---------|
| `{mediaId}` | TMDB ID of the movie/show | `12345` |
| `{mediaType}` | `movie` or `tv` | `movie` |
| `{title}` | URL-encoded title | `Inception` |
| `{imdbId}` | IMDb ID (if available) | `tt1375666` |
| `{season}` | Season number (episode_item only) | `1` |
| `{episode}` | Episode number (episode_item only) | `5` |

### Examples

```
https://example.com/watch/{mediaId}?type={mediaType}
https://mystream.com/search?q={title}
https://example.com/movie/{imdbId}
https://example.com/show/{mediaId}/s{season}e{episode}
```

### Encoding

- `{title}` is automatically URL-encoded.
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
    "postMessageOrigin": "https://your-domain.com",
    "allowedEvents": ["progress", "pause", "stop", "heartbeat"]
  }
}
```

| Field | Description |
|-------|-------------|
| `postMessageOrigin` | The origin of your page (must match `window.location.origin`). Used for security validation. |
| `allowedEvents` | Events your page will send. Spovies ignores events not in this list. |

### PostMessage Format

Send messages from your page to the Spovies WebView:

```javascript
// Progress update (send every 5-10 seconds and on pause/stop)
window.parent.postMessage({
  type: 'progress',
  payload: {
    timestamp: 3600,      // Current position in seconds
    percentage: 65.5,     // 0-100
    duration: 5500        // Total duration in seconds (optional)
  }
}, 'https://your-domain.com');

// User paused
window.parent.postMessage({
  type: 'pause',
  payload: {
    timestamp: 3600,
    percentage: 65.5
  }
}, 'https://your-domain.com');

// User stopped / closed
window.parent.postMessage({
  type: 'stop',
  payload: {
    timestamp: 3600,
    percentage: 65.5
  }
}, 'https://your-domain.com');

// Heartbeat (every 5-10 sec) - ensures progress is saved even if app crashes
window.parent.postMessage({
  type: 'heartbeat',
  payload: {
    timestamp: 3600,
    percentage: 65.5
  }
}, 'https://your-domain.com');
```

### Best Practices

- **Send `heartbeat` every 5-10 seconds** during playback. Do not rely only on `stop` — the app may crash or the phone may die.
- **Send `progress` or `heartbeat` on pause** so the user can resume accurately.
- **Include both `timestamp` and `percentage`** for redundancy.

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
  "urlTemplate": "https://api.myratings.com/movie/{mediaId}",
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

### User Installation

1. User opens Spovies → Settings → Plugins
2. User pastes your manifest URL
3. Spovies fetches, validates, and registers your plugin
4. Your plugin appears in the configured hook zones

### Validation

Spovies validates your manifest against the schema. Invalid manifests are rejected with an error. Ensure:
- All required fields are present
- `hooks` contains only valid values: `media_header`, `episode_item`, `media_card_context`
- `actionType` is one of: `webview`, `externalLink`, `metadataFetch`
- `urlTemplate` is a valid URL format

---

## 9. Security & Sandboxing

### What Spovies Does

- **WebView isolation:** Your page runs in a sandboxed WebView. No direct access to the Flutter app or device.
- **Origin validation:** `postMessage` is only accepted if the origin matches `eventBridgeConfig.postMessageOrigin`.
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
  "urlTemplate": "https://www.justwatch.com/search?q={title}",
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
  "urlTemplate": "https://example.com/watch/{mediaId}?type={mediaType}&s={season}&e={episode}",
  "actionType": "webview",
  "presentationMode": "fullscreen",
  "eventBridgeConfig": {
    "postMessageOrigin": "https://example.com",
    "allowedEvents": ["progress", "pause", "stop", "heartbeat"]
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
  "urlTemplate": "https://api.myimdb.com/movie/{mediaId}/rating",
  "actionType": "metadataFetch"
}
```

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-03-02 | Initial specification |

---

*For questions or to submit your plugin for inclusion in the official Spovies plugin directory, contact the Spovies team.*
