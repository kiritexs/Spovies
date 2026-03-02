import '../../domain/entities/media_item.dart';
import '../../domain/entities/plugin_manifest.dart';

/// Resolves a plugin's URL template with actual media data.
///
/// Supports placeholders: `{{tmdbId}}`, `{{type}}`, `{{title}}`,
/// `{{imdbId}}`, `{{season}}`, `{{episode}}`.
class PluginUrlResolver {
  /// Resolve URL template with media item data.
  static String resolve(
    PluginManifest plugin,
    MediaItem media, {
    int? season,
    int? episode,
  }) {
    var url = plugin.urlTemplate;

    final typeStr = media.type.name; // 'movie' or 'tv'

    url = url.replaceAll('{{tmdbId}}', media.tmdbId.toString());
    url = url.replaceAll('{{type}}', typeStr);
    url = url.replaceAll('{{title}}', Uri.encodeComponent(media.title));
    url = url.replaceAll('{{imdbId}}', media.metadata.imdbId ?? '');

    if (season != null) {
      url = url.replaceAll('{{season}}', season.toString());
    }
    if (episode != null) {
      url = url.replaceAll('{{episode}}', episode.toString());
    }

    return url;
  }
}
