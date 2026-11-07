/// Hive keys for per-title data.
///
/// TMDB uses separate id spaces for movies and TV shows, so the media type
/// must be part of every key — otherwise movie 123 and show 123 overwrite
/// each other's status, progress, and watchlist entry.
abstract final class StorageKeys {
  /// Current key-format version, stored in the settings box so the one-time
  /// migration in `HiveService` runs only once.
  static const int version = 2;
  static const String versionSettingKey = 'storageKeysVersion';

  /// Watch-status entry: `status_tv_123` or `status_tv_123_s1_e2`.
  static String status(
    String mediaType,
    String mediaId, {
    int? season,
    int? episode,
  }) {
    final base = 'status_${mediaType}_$mediaId';
    return (season != null && episode != null)
        ? '${base}_s${season}_e$episode'
        : base;
  }

  /// Watch-progress entry: `movie_123` or `tv_123_s1_e2`.
  static String progress(
    String mediaType,
    String mediaId, {
    int? season,
    int? episode,
  }) {
    final base = '${mediaType}_$mediaId';
    return (season != null && episode != null)
        ? '${base}_s${season}_e$episode'
        : base;
  }

  /// Watchlist entry: `movie_123`.
  static String watchlist(String mediaType, int tmdbId) =>
      '${mediaType}_$tmdbId';

  /// Identity of a title across both id spaces, for de-duplication.
  static String media(String mediaType, String mediaId) =>
      '${mediaType}_$mediaId';
}
