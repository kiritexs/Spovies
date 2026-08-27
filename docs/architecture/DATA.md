# Data Export & Import

`lib/data/services/export_import_service.dart`

Format: JSON → gzip → `.spovies` extension. Covers watch history,
watchlist, installed plugins, and settings.

---

## Two-phase import

Import is split into `previewImport` and `applyImport` rather than a
single call, because **plugins are the high-risk surface**. Every
imported manifest becomes a potential `launchUrl` /
`InAppWebView.initialUrlRequest` target on subsequent taps.

### `previewImport`

Picks a `.spovies` file and parses it **without touching local storage**.
Returns `null` if the user cancelled the picker; throws on a real error
(corrupt file, version mismatch, IO error).

Only manifests passing `PluginManifestModel.fromJson` validation —
`urlTemplate` is `http(s)://`, known `actionType`, required fields
present — reach `ImportPreview.plugins`. Rejected entries are summarised
in `rejectedPlugins` so the UI can warn that the backup may have been
tampered with.

### Confirmation dialog

`settings_screen.dart` shows the user exactly which plugins will be
installed and which were rejected, listing names and `urlTemplate`s. The
dialog states plainly that plugins can launch arbitrary HTTPS URLs when
tapped.

### `applyImport`

Merges the confirmed preview into the local database. Validation runs
**again** here — re-validating defends against a TOCTOU window between
preview and apply.

---

## Search state ownership

`lib/presentation/providers/search_providers.dart`

`isSearchActiveProvider` is the single source of truth for whether a
search is active. `DiscoverScreen` watches it directly rather than
mirroring it into a local `bool`.

The mirror caused a real bug: after a `/player → /details → back` trip
the player's `SystemChrome` orientation and immersive-UI changes
propagated a `MediaQuery` rebuild that re-instantiated
`_DiscoverScreenState`. The local flag reset to `false` while the
provider survived as `true`, so the UI showed Discovery content with the
bottom nav still hidden.

`initState` also restores `_searchController.text` from
`searchQueryProvider` — belt-and-braces, so the search UI comes back even
if the State is recreated despite the `ValueKey`s described in
[NAVIGATION.md](NAVIGATION.md#tab-state-preservation). The text is set
**before** the listener is attached, avoiding a spurious provider update.

### `searchClearSignalProvider`

A one-shot counter incremented when the user presses system back with an
active search. `DiscoverScreen` listens and calls its own clear logic.

A signal rather than driving the controller from a provider: the
controller's text and selection are widget-owned and short-lived, while
the provider is app-lifetime. Inverting that would force the provider to
track ephemeral UI state for no benefit.

There used to be a `deactivate()` override resetting
`isSearchActiveProvider` whenever the user left the tab. It produced a
sneaky bug — the controller text and local flag stayed set but the
provider lied, so a system back press after returning switched tabs
instead of clearing the search. The nav-bar visibility logic it was
working around now lives in `MainScaffold` and gates on the active tab
index.

### `searchResultsProvider`

Debounces 500 ms after the last keystroke. If the query changed during
the delay, it throws `SearchCancelledException` — a dedicated type rather
than a string match, because string-matching the exception text would
silently break if the class moved or its message changed. The UI catches
it and shows the shimmer placeholder instead of an error.
