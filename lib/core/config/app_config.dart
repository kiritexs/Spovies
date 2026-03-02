/// TMDB API configuration constants.
abstract final class AppConfig {
  static const String tmdbBaseUrl = 'https://api.themoviedb.org/3';
  static const String tmdbImageBaseUrl = 'https://image.tmdb.org/t/p';

  // Image size constants
  static const String posterSmall = 'w185';
  static const String posterMedium = 'w342';
  static const String posterLarge = 'w500';
  static const String backdropMedium = 'w780';
  static const String backdropLarge = 'w1280';
  static const String imageOriginal = 'original';

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  // Cache TTLs
  static const Duration configCacheTtl = Duration(hours: 24);
  static const Duration genreCacheTtl = Duration(hours: 24);
  static const Duration trendingCacheTtl = Duration(minutes: 30);
  static const Duration detailsCacheTtl = Duration(hours: 1);
}
