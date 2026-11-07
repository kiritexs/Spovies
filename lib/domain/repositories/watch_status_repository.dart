import '../entities/watch_status.dart';

/// Repository for media list status (watching, completed, dropped, etc.).
///
/// Every lookup takes a `mediaType` ('movie' or 'tv') because TMDB issues
/// independent ids for movies and TV shows — id `123` can be two unrelated
/// titles.
abstract class WatchStatusRepository {
  /// Save or update status for a media item or episode.
  Future<void> saveStatus(MediaStatus entry);

  /// Get status for a media item. For TV, pass [season] and [episode] for
  /// episode-level, or both null for show-level.
  Future<MediaStatus?> getStatus(
    String mediaId, {
    required String mediaType,
    int? season,
    int? episode,
  });

  /// Get all status entries for a show (for episode list display).
  Future<List<MediaStatus>> getStatusesForMedia(
    String mediaId, {
    required String mediaType,
  });

  /// Get all entries with the given status (for filters/lists).
  Future<List<MediaStatus>> getEntriesByStatus(WatchStatus status);

  /// Every title-level (not episode-level) status entry.
  Future<List<MediaStatus>> getAllTitleStatuses();

  /// Remove status for a media item or episode.
  Future<void> deleteStatus(
    String mediaId, {
    required String mediaType,
    int? season,
    int? episode,
  });

  /// Remove all status entries for a media (show-level + all episode-level).
  /// Use when removing a title from the library.
  Future<void> deleteAllStatusesForMedia(
    String mediaId, {
    required String mediaType,
  });

  /// Remove every status entry.
  Future<void> clearAll();
}
