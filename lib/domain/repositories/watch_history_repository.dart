import '../entities/user_progress.dart';

/// Abstract repository for watch history operations.
///
/// Lookups take a `mediaType` ('movie' or 'tv') because TMDB ids are only
/// unique within a media type.
abstract class WatchHistoryRepository {
  /// Save or update progress for a media item.
  Future<void> saveProgress(UserProgress progress);

  /// Get progress for a specific media item (+ optional season/episode for TV).
  Future<UserProgress?> getProgress(
    String mediaId, {
    required String mediaType,
    int? season,
    int? episode,
  });

  /// Get the "Continue Watching" list, sorted by last played.
  Future<List<UserProgress>> getContinueWatching({int limit = 10});

  /// Every progress entry for one title (movie, or show + all episodes).
  Future<List<UserProgress>> getProgressForMedia(
    String mediaId, {
    required String mediaType,
  });

  /// Remove every progress entry for one title (movie, or show + all
  /// episodes). Use when removing a title from the library — otherwise it
  /// lingers in the "Continue Watching" row.
  Future<void> deleteProgressForMedia(
    String mediaId, {
    required String mediaType,
  });

  /// Clear all watch history.
  Future<void> clearHistory();
}
