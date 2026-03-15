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
  Future<List<MediaStatus>> getStatusesForMedia(String mediaId);

  /// Get all entries with the given status (for filters/lists).
  Future<List<MediaStatus>> getEntriesByStatus(WatchStatus status);

  /// Remove status for a media item or episode.
  Future<void> deleteStatus(String mediaId, {int? season, int? episode});

  /// Remove all status entries for a media (show-level + all episode-level).
  /// Use when removing a title from the library.
  Future<void> deleteAllStatusesForMedia(String mediaId);
}
