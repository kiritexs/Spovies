import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_type.dart';
import '../../domain/entities/plugin_manifest.dart';

/// Resolves a plugin's URL template with actual media data.
///
/// Supported explicit placeholders:
///   `{{tmdbId}}`, `{{type}}`, `{{title}}`, `{{imdbId}}`,
///   `{{season}}`, `{{episode}}`
///
/// **TV show fallback (no placeholders in template):**
/// Many embed services (e.g. Provider A) use a path-based season/episode
/// scheme — `…/tv/{id}/{season}/{episode}` — but the plugin author may
/// write a short template without `{{season}}/{{episode}}`.  When a TV
/// show is resolved and neither placeholder appears in the template, this
/// resolver appends the season and episode automatically as extra path
/// segments, defaulting to S1E1 when called from the media-header hook
/// (no season/episode arguments passed).
///
/// Example
/// ```
/// template : https://example.com/embed/{{type}}/{{tmdbId}}?color=…
/// movie    : https://example.com/embed/movie/12345?color=…       ✓
/// tv header: https://example.com/embed/tv/12345/1/1?color=…     ✓ (S1E1)
/// tv ep 3  : https://example.com/embed/tv/12345/1/3?color=…     ✓
/// ```
class PluginUrlResolver {
  /// Pick the most appropriate plugin from [plugins] for the given preferences.
  ///
  /// Resolution order:
  ///   1. [savedId] — the plugin previously used for this exact item (if any)
  ///   2. [preferredId] — the user's globally preferred plugin (if any)
  ///   3. `plugins.first` as a last resort
  ///
  /// Centralises the logic that was previously duplicated (and subtly diverged)
  /// between the home screen's "Continue Watching" path and the in-player
  /// "Play Next Episode" overlay. Returns `null` only when [plugins] is empty.
  static PluginManifest? pickPlugin(
    List<PluginManifest> plugins, {
    String? savedId,
    String? preferredId,
  }) {
    if (plugins.isEmpty) return null;

    if (savedId != null) {
      for (final p in plugins) {
        if (p.pluginId == savedId) return p;
      }
    }
    if (preferredId != null) {
      for (final p in plugins) {
        if (p.pluginId == preferredId) return p;
      }
    }
    return plugins.first;
  }

  /// Resolve URL template with media item data.
  static String resolve(
    PluginManifest plugin,
    MediaItem media, {
    int? season,
    int? episode,
  }) {
    final template = plugin.urlTemplate;

    final hasSeasonPlaceholder =
        template.contains('{{season}}') || template.contains('{{/season}}');
    final hasEpisodePlaceholder =
        template.contains('{{episode}}') || template.contains('{{/episode}}');

    var url = template;

    // ── Basic substitutions ────────────────────────────────────────────────
    url = url.replaceAll('{{tmdbId}}', media.tmdbId.toString());
    url = url.replaceAll('{{id}}', media.tmdbId.toString());
    url = url.replaceAll('{{type}}', media.type.name);
    url = url.replaceAll('{{title}}', Uri.encodeComponent(media.title));
    url = url.replaceAll('{{imdbId}}', media.metadata.imdbId ?? '');

    // ── Explicit season / episode placeholders ─────────────────────────────
    final sVal = (season ?? 1).toString();
    final eVal = (episode ?? 1).toString();

    if (media.type == MediaType.tv) {
      url = url.replaceAll('{{season}}', sVal);
      url = url.replaceAll('{{/season}}', '/$sVal');
      url = url.replaceAll('{{episode}}', eVal);
      url = url.replaceAll('{{/episode}}', '/$eVal');
    } else {
      // For movies, explicit season/episode placeholders are cleared
      url = url.replaceAll('{{season}}', '');
      url = url.replaceAll('{{/season}}', '');
      url = url.replaceAll('{{episode}}', '');
      url = url.replaceAll('{{/episode}}', '');
    }

    // ── TV path-based fallback ─────────────────────────────────────────────
    // When no season/episode placeholder exists but we're dealing with a TV show,
    // append /season/episode as path segments before any query string.
    if (media.type == MediaType.tv &&
        !hasSeasonPlaceholder &&
        !hasEpisodePlaceholder) {
      final s = season ?? 1;
      final e = episode ?? 1;
      // tryParse instead of parse: a malformed plugin template (or a weird
      // substitution result) shouldn't take down the whole resolver — fall
      // back to plain string concatenation instead.
      final uri = Uri.tryParse(url);
      if (uri != null) {
        final cleanPath = uri.path.endsWith('/')
            ? uri.path.substring(0, uri.path.length - 1)
            : uri.path;
        url = uri.replace(path: '$cleanPath/$s/$e').toString();
      } else {
        // Last-resort: append before any query/fragment.
        final qIdx = url.indexOf('?');
        if (qIdx == -1) {
          url = '${url.endsWith('/') ? url.substring(0, url.length - 1) : url}/$s/$e';
        } else {
          final base = url.substring(0, qIdx);
          final query = url.substring(qIdx);
          final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
          url = '$trimmed/$s/$e$query';
        }
      }
    }

    return url;
  }
}
