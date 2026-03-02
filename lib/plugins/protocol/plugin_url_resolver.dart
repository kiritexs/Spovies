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
  /// Resolve URL template with media item data.
  static String resolve(
    PluginManifest plugin,
    MediaItem media, {
    int? season,
    int? episode,
  }) {
    final template = plugin.urlTemplate;

    final hasSeasonPlaceholder = template.contains('{{season}}');
    final hasEpisodePlaceholder = template.contains('{{episode}}');

    var url = template;

    // ── Basic substitutions ────────────────────────────────────────────────
    url = url.replaceAll('{{tmdbId}}', media.tmdbId.toString());
    url = url.replaceAll('{{type}}', media.type.name);
    url = url.replaceAll('{{title}}', Uri.encodeComponent(media.title));
    url = url.replaceAll('{{imdbId}}', media.metadata.imdbId ?? '');

    // ── Explicit season / episode placeholders ─────────────────────────────
    if (hasSeasonPlaceholder) {
      url = url.replaceAll('{{season}}', (season ?? 1).toString());
    }
    if (hasEpisodePlaceholder) {
      url = url.replaceAll('{{episode}}', (episode ?? 1).toString());
    }

    // ── TV path-based fallback ─────────────────────────────────────────────
    // When neither placeholder exists but we're dealing with a TV show,
    // append /season/episode as path segments before any query string.
    // Defaults to 1/1 so the media-header "Watch" button always lands on
    // a valid episode instead of the service's homepage.
    if (media.type == MediaType.tv &&
        !hasSeasonPlaceholder &&
        !hasEpisodePlaceholder) {
      final s = season ?? 1;
      final e = episode ?? 1;
      final uri = Uri.parse(url);
      // Ensure no trailing slash before appending
      final cleanPath = uri.path.endsWith('/')
          ? uri.path.substring(0, uri.path.length - 1)
          : uri.path;
      url = uri.replace(path: '$cleanPath/$s/$e').toString();
    }

    return url;
  }
}
