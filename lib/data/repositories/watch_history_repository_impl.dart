import 'package:hive_flutter/hive_flutter.dart';
import '../datasources/local/hive_service.dart';

import '../../domain/entities/user_progress.dart';
import '../../domain/repositories/watch_history_repository.dart';

/// Hive-backed implementation of [WatchHistoryRepository].
class WatchHistoryRepositoryImpl implements WatchHistoryRepository {
  Box<Map> get _box => HiveService.watchHistoryBox;

  /// Unique key for a progress entry (handles episodes separately).
  String _key(String mediaId, {int? season, int? episode}) {
    if (season != null && episode != null) {
      return '${mediaId}_s${season}_e$episode';
    }
    return mediaId;
  }

  @override
  Future<void> saveProgress(UserProgress progress) async {
    final key = _key(
      progress.mediaId,
      season: progress.season,
      episode: progress.episode,
    );
    await _box.put(key, progress.toMap());
  }

  @override
  Future<UserProgress?> getProgress(
    String mediaId, {
    int? season,
    int? episode,
  }) async {
    final key = _key(mediaId, season: season, episode: episode);
    final data = _box.get(key);
    if (data == null) return null;
    return UserProgress.fromMap(data);
  }

  @override
  Future<List<UserProgress>> getContinueWatching({int limit = 10}) async {
    final entries = <UserProgress>[];
    for (final key in _box.keys) {
      final data = _box.get(key);
      if (data != null) {
        final progress = UserProgress.fromMap(data);
        // Only include items watched less than 95% (consistent with "Watched" threshold)
        if (progress.percentage < 95) {
          entries.add(progress);
        }
      }
    }
    // Sort by last played (newest first)
    entries.sort((a, b) => b.lastPlayedDate.compareTo(a.lastPlayedDate));
    return entries.take(limit).toList();
  }

  @override
  Future<void> clearHistory() async {
    await _box.clear();
  }
}
