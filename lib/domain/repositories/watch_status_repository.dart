import '../entities/watch_status.dart';

/// Repository for media list status (watching, completed, dropped, etc.).
abstract class WatchStatusRepository {
  /// Save or update status for a media item or episode.
  Future<void> saveStatus(MediaStatus entry);

  /// Get status for a media item. For TV, pass [season] and [episode] for
  /// episode-level, or both null for show-level.
  Future<MediaStatus?> getStatus(
    String mediaId, {
    int? season,
    int? episode,
  });

  /// Get all status entries for a show (for episode list display).
  ///
  /// [mediaType] disambiguates the TMDB id space: TMDB issues independent
  /// ids for movies and TV shows, so id `123` can refer to two unrelated
  /// titles. Pass `'movie'` or `'tv'` to avoid mixing.
  Future<List<MediaStatus>> getStatusesForMedia(
    String mediaId, {
    required String mediaType,
  });

  /// Get all entries with the given status (for filters/lists).
  Future<List<MediaStatus>> getEntriesByStatus(WatchStatus status);

  /// Remove status for a media item or episode.
  Future<void> deleteStatus(String mediaId, {int? season, int? episode});

  /// Remove all status entries for a media (show-level + all episode-level).
  /// Use when removing a title from the library.
  ///
  /// [mediaType] disambiguates the TMDB id space — see [getStatusesForMedia].
  Future<void> deleteAllStatusesForMedia(
    String mediaId, {
    required String mediaType,
  });
}
