import 'package:hive_flutter/hive_flutter.dart';

import '../datasources/local/hive_service.dart';
import '../datasources/local/storage_keys.dart';
import '../../domain/entities/user_progress.dart';
import '../../domain/repositories/watch_history_repository.dart';

/// Hive-backed implementation of [WatchHistoryRepository].
class WatchHistoryRepositoryImpl implements WatchHistoryRepository {
  Box<Map<dynamic, dynamic>> get _box => HiveService.watchHistoryBox;

  @override
  Future<void> saveProgress(UserProgress progress) async {
    final key = StorageKeys.progress(
      progress.mediaType,
      progress.mediaId,
      season: progress.season,
      episode: progress.episode,
    );
    await _box.put(key, progress.toMap());
  }

  @override
  Future<UserProgress?> getProgress(
    String mediaId, {
    required String mediaType,
    int? season,
    int? episode,
  }) async {
    final key = StorageKeys.progress(
      mediaType,
      mediaId,
      season: season,
      episode: episode,
    );
    final data = _box.get(key);
    if (data == null) return null;
    return UserProgress.fromMap(data);
  }

  @override
  Future<List<UserProgress>> getContinueWatching({int limit = 10}) async {
    // One entry per title (media type + id): keep the most recently played.
    final byMedia = <String, UserProgress>{};
    for (final data in _box.values) {
      final p = UserProgress.fromMap(data);
      final id = StorageKeys.media(p.mediaType, p.mediaId);
      final existing = byMedia[id];
      if (existing == null ||
          p.lastPlayedDate.isAfter(existing.lastPlayedDate)) {
        byMedia[id] = p;
      }
    }
    final entries = byMedia.values.toList()
      ..sort((a, b) => b.lastPlayedDate.compareTo(a.lastPlayedDate));
    return entries.take(limit).toList();
  }

  @override
  Future<List<UserProgress>> getProgressForMedia(
    String mediaId, {
    required String mediaType,
  }) async {
    return [
      for (final value in _box.values)
        if (value['mediaId']?.toString() == mediaId &&
            value['mediaType']?.toString() == mediaType)
          UserProgress.fromMap(value),
    ];
  }

  @override
  Future<void> deleteProgressForMedia(
    String mediaId, {
    required String mediaType,
  }) async {
    final keysToRemove = <dynamic>[];
    for (final entry in _box.toMap().entries) {
      final value = entry.value;
      if (value['mediaId']?.toString() == mediaId &&
          value['mediaType']?.toString() == mediaType) {
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
