import '../config/app_config.dart';

/// Builds a full TMDB image URL from a path and size.
///
/// Example: `buildImageUrl('/abc123.jpg', AppConfig.posterLarge)`
/// → `https://image.tmdb.org/t/p/w500/abc123.jpg`
String buildImageUrl(String? path, [String size = AppConfig.posterLarge]) {
  if (path == null || path.isEmpty) return '';
  return '${AppConfig.tmdbImageBaseUrl}/$size$path';
}
