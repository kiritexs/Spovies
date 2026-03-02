import '../entities/user_progress.dart';

/// Abstract repository for watch history operations.
abstract class WatchHistoryRepository {
  /// Save or update progress for a media item.
  Future<void> saveProgress(UserProgress progress);

  /// Get progress for a specific media item (+ optional season/episode for TV).
  Future<UserProgress?> getProgress(
    String mediaId, {
    int? season,
    int? episode,
  });

  /// Get the "Continue Watching" list, sorted by last played, filtered < 90%.
  Future<List<UserProgress>> getContinueWatching({int limit = 10});

  /// Clear all watch history.
  Future<void> clearHistory();
}
