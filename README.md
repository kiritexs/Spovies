<p align="center">
  <a href="https://github.com/kiritexs">
    <img src="assets/logo.png" alt="Kiritex" width="320" height="61" />
  </a>
</p>

<h1 align="center">Spovies</h1>
<p align="center">
  <strong>Movie & TV discovery · Watchlist · Continue watching · Plugin-based streaming</strong>
</p>
<p align="center">
  <sub>© Kiritex. All rights reserved.</sub>
</p>

---

## Table of contents

- [What is Spovies?](#what-is-spovies)
- [Features](#features)
- [Plugins](#plugins)
- [Creating your own plugin](#creating-your-own-plugin)
- [Data & backup](#data--backup)
- [Tech stack](#tech-stack)

---

## What is Spovies?

**Spovies** is a movie and TV show discovery app that lets you:

| Discover | Watch | Track | Customize |
|----------|--------|--------|-----------|
| Browse trending & top-rated titles, search by name, filter by genre. All metadata (posters, cast, overviews, trailers) comes from **TMDB**. | Use **Watch** from an installed plugin to open the stream in the in-app WebView player. | Save titles to a **watchlist** and use **Continue watching** to resume where you left off (when the plugin reports progress). | Install plugins, export/import your data as a `.spovies` backup, and tweak appearance and playback in **Settings**. |

The app does **not** host or stream content itself. Plugins provide the watch links; you explore and organize everything in one place.

---

## Features

### Home
- **Hero** — Spotlight for a trending movie.
- **Trending** & **Top rated** — Horizontal rows.
- **Continue watching** — Resumes from last position when the plugin supports progress.

### Explore
- **Search** — By movie or TV show name.
- **Movies / TV** — Toggle for trending content.
- **Genre filters** — Narrow results.
- Tap any poster to open **details**.

### Browse (Watchlist)
- Grid of saved titles.
- Remove items or clear the list.

### Details
- Backdrop, poster, title, genres, overview.
- **Cast** row.
- **Trailer** — Opens in browser.
- **Watch** — From installed plugins; opens in-app WebView player.
- **TV shows** — Season and episode list.

### Player
- In-app **WebView** when you tap **Watch**.
- Plugins can report **progress** for continue-watching and history.
- Tuned for inline playback (e.g. on iOS).

### Profile (Settings)
- **Manage plugins** — Add (by manifest URL), remove, view installed plugins.
- **Export data** — Back up to a `.spovies` file (watch history, watchlist, plugins, settings).
- **Import data** — Restore from a `.spovies` backup.
- **Clear watch history** / **Clear watchlist**.
- **Theme** — Dark.
- **Playback** — Player options.
- **About** — App info and licenses.

---

## Plugins

Plugins are add-ons that define:

- **Where** the Watch action appears (e.g. on the details screen or on episode rows).
- **Which URL** (or URL template) opens in the in-app WebView.
- **Optional** progress reporting so Continue watching and watch history work.

Install plugins in **Settings → Manage Plugins** by entering the **HTTPS URL** of a plugin manifest (a JSON file). Each plugin can optionally send progress events to the app via the Event Bridge.

---

## Creating your own plugin

You can create a Spovies plugin by hosting a **manifest JSON file** on HTTPS and sharing its URL. When a user adds that URL in **Manage Plugins**, the app fetches the manifest, validates it, and installs the plugin.

### 1. Manifest URL

- Must be **HTTPS**.
- The app fetches it with a GET request and expects **JSON** in the response.

### 2. Manifest schema

Your manifest must be valid JSON with at least these **required** fields:

| Field | Type | Description |
|-------|------|-------------|
| `pluginId` | string | Unique ID (e.g. `my-streaming-plugin`). Cannot be empty. |
| `name` | string | Display name shown in the app. |
| `urlTemplate` | string | URL template with optional placeholders (see below). |

**Optional** fields:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `version` | string | `"1.0.0"` | Plugin version. |
| `description` | string | `""` | Short description. |
| `iconUrl` | string | — | URL of an icon image. |
| `hooks` | string[] | `["media_header"]` | Where the plugin appears (see [Trigger hooks](#trigger-hooks)). |
| `actionType` | string | `"webview"` | What happens when the user taps: `webview`, `externalLink`, or `metadataFetch`. |
| `presentationMode` | string | `"fullscreen"` | How WebView is shown: `fullscreen` or `popover`. |
| `eventBridgeConfig` | object | — | If you want to report progress (see [Event Bridge](#event-bridge)). |

### 3. URL template placeholders

The app replaces these placeholders in `urlTemplate` with the current media data:

| Placeholder | Replaced with |
|-------------|----------------|
| `{{tmdbId}}` | TMDB ID of the movie or show. |
| `{{type}}` | `movie` or `tv`. |
| `{{title}}` | URL-encoded title. |
| `{{imdbId}}` | IMDB ID if available, else empty. |
| `{{season}}` | Season number (for TV). |
| `{{episode}}` | Episode number (for TV). |

**TV path fallback:** If your template does **not** contain `{{season}}` or `{{episode}}` but the media is a TV show, the app appends `/season/episode` as path segments (e.g. `/1/1` for S1E1 when opening from the main details “Watch” button).

**Example:**

```json
{
  "pluginId": "example-stream",
  "name": "Example Stream",
  "version": "1.0.0",
  "description": "Watch movies and TV via Example.",
  "urlTemplate": "https://example.com/embed/{{type}}/{{tmdbId}}",
  "hooks": ["media_header", "episode_item"],
  "actionType": "webview",
  "presentationMode": "fullscreen"
}
```

- Movie: `https://example.com/embed/movie/12345`
- TV from header (no episode): `https://example.com/embed/tv/67890/1/1`
- TV episode 3: `https://example.com/embed/tv/67890/1/3` (if you pass season/episode when resolving)

### 4. Trigger hooks

Control where your plugin’s action appears:

| Hook value | Where it appears |
|------------|-------------------|
| `media_header` | On the movie/TV details screen (main “Watch” area). |
| `episode_item` | On each episode row for TV shows. |
| `media_card_context` | In context menus or actions on media cards. |

Use the `hooks` array to list one or more of these values.

### 5. Action types

| Value | Behavior |
|-------|----------|
| `webview` | Opens the resolved URL inside the app’s WebView player. |
| `externalLink` | Opens the URL in the device browser (or external app). |
| `metadataFetch` | For future use (metadata-only plugins). |

### 6. Event Bridge (progress & continue watching)

If your streaming page runs inside the app’s WebView, you can send **progress events** so Spovies can:

- Update **Continue watching**.
- Store **watch history** (position, duration, etc.).

Your page must post JSON messages that the app listens for. The app injects a bridge that forwards `message` events to Flutter.

**Expected postMessage format:**

```json
{
  "type": "PLAYER_EVENT",
  "data": {
    "event": "timeupdate",
    "currentTime": 120.5,
    "duration": 7200,
    "progress": 1.6,
    "id": "299534",
    "mediaType": "movie",
    "season": 1,
    "episode": 8
  }
}
```

| Field | Description |
|-------|-------------|
| `type` | Must be `"PLAYER_EVENT"`. |
| `data.event` | e.g. `timeupdate`, `play`, `pause`, `ended`, `seeked`. Critical events (pause, ended, seeked) are saved immediately; `timeupdate` is throttled (e.g. once per 5 seconds). |
| `data.currentTime` | Current playback time in seconds. |
| `data.duration` | Total duration in seconds. |
| `data.progress` | Progress percentage (0–100). |
| `data.id` | TMDB ID (string). |
| `data.mediaType` | `"movie"` or `"tv"`. |
| `data.season` / `data.episode` | Optional; for TV. |

**Manifest config for Event Bridge:**

```json
"eventBridgeConfig": {
  "postMessageOrigin": "*",
  "allowedEventTypes": ["progress", "pause", "stop", "heartbeat"]
}
```

- `postMessageOrigin` — Allowed origin for `postMessage` (use `"*"` to allow any, or your domain).
- `allowedEventTypes` — Optional allowlist; default includes `progress`, `pause`, `stop`, `heartbeat`.

Your page should call `window.postMessage(…)` with the JSON above (e.g. from the video player’s `timeupdate` or `pause` handlers). The app will parse it and update watch history when the format matches.

### 7. Minimal and full example manifests

**Minimal (required only):**

```json
{
  "pluginId": "my-plugin",
  "name": "My Plugin",
  "urlTemplate": "https://mysite.com/watch/{{type}}/{{tmdbId}}"
}
```

**Full (with Event Bridge):**

```json
{
  "pluginId": "my-plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "description": "Stream with progress tracking.",
  "iconUrl": "https://mysite.com/icon.png",
  "hooks": ["media_header", "episode_item"],
  "urlTemplate": "https://mysite.com/embed/{{type}}/{{tmdbId}}",
  "actionType": "webview",
  "presentationMode": "fullscreen",
  "eventBridgeConfig": {
    "postMessageOrigin": "*",
    "allowedEventTypes": ["progress", "pause", "stop", "heartbeat"]
  }
}
```

Host this JSON at an HTTPS URL (e.g. `https://mysite.com/spovies-manifest.json`) and share that URL with users. They add it in **Settings → Manage Plugins** to install your plugin.

---

## Data & backup

- **Watch history** and **watchlist** are stored locally on the device.
- **Export** produces a single `.spovies` file (watch history, watchlist, installed plugins, settings). You can share or back it up.
- **Import** reads a `.spovies` file and merges its data into the app (e.g. after reinstall or on a new device).

---

## Tech stack

| Layer | Technology |
|-------|------------|
| App | Flutter (Android & iOS) |
| Metadata | TMDB (images, cast, genres, etc.) |
| State & routing | Riverpod, GoRouter |
| Local storage | Hive (history, watchlist, plugins, settings) |
| Player | InAppWebView + Event Bridge for plugin progress |

---

<p align="center">
  <sub><strong>Spovies</strong> — Discovery, watchlist, and continue watching with plugin-based streaming.</sub><br />
  <sub>© <a href="https://github.com/kiritexs">Kiritex</a>. All rights reserved.</sub>
</p>
