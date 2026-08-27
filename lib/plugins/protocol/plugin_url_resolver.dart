import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_type.dart';
import '../../domain/entities/plugin_manifest.dart';

/// Resolves a plugin's URL template against real media data.
///
/// Placeholders: `{{tmdbId}}`, `{{type}}`, `{{title}}`, `{{imdbId}}`,
/// `{{season}}`, `{{episode}}`. When a TV show is resolved and no
/// season/episode placeholder appears, they are appended as path
/// segments instead — see `docs/architecture/PLUGINS.md`.
class PluginUrlResolver {
  /// Picks a plugin: [savedId], then [preferredId], then `plugins.first`.
  /// Returns `null` only when [plugins] is empty.
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
    // No placeholder but a TV show — append /season/episode as segments.
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
          url =
              '${url.endsWith('/') ? url.substring(0, url.length - 1) : url}/$s/$e';
        } else {
          final base = url.substring(0, qIdx);
          final query = url.substring(qIdx);
          final trimmed = base.endsWith('/')
              ? base.substring(0, base.length - 1)
              : base;
          url = '$trimmed/$s/$e$query';
        }
      }
    }

    return url;
  }
}
