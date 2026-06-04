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
    // One entry per media: keep the most recently played progress per
    // mediaId. We iterate `_box.values` directly (Hive regular boxes hold
    // everything in memory, so this skips the per-key disk lookup) and
    // dedupe in a single pass instead of materialising the full list first.
    final byMedia = <String, UserProgress>{};
    for (final data in _box.values) {
      final p = UserProgress.fromMap(data);
      final existing = byMedia[p.mediaId];
      if (existing == null ||
          p.lastPlayedDate.isAfter(existing.lastPlayedDate)) {
        byMedia[p.mediaId] = p;
      }
    }
    final entries = byMedia.values.toList()
      ..sort((a, b) => b.lastPlayedDate.compareTo(a.lastPlayedDate));
    return entries.take(limit).toList();
  }

  @override
  Future<void> deleteProgressForMedia(String mediaId) async {
    // Watch-history keys are either `$mediaId` (movie) or
    // `${mediaId}_s${season}_e${episode}` (episode), so we can match on
    // the stored mediaId field via the in-memory value cache — one
    // traversal, one batched deleteAll.
    final keysToRemove = <dynamic>[];
    for (final entry in _box.toMap().entries) {
      if (entry.value['mediaId']?.toString() == mediaId) {
        keysToRemove.add(entry.key);
      }
    }
    if (keysToRemove.isNotEmpty) {
      await _box.deleteAll(keysToRemove);
    }
  }

  @override
  Future<void> clearHistory() async {
    await _box.clear();
  }
}
