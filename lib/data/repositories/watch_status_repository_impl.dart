import 'package:hive_flutter/hive_flutter.dart';

import '../datasources/local/hive_service.dart';
import '../../domain/entities/watch_status.dart';
import '../../domain/repositories/watch_status_repository.dart';

/// Hive-backed implementation of [WatchStatusRepository].
class WatchStatusRepositoryImpl implements WatchStatusRepository {
  Box<Map> get _box => HiveService.listStatusBox;

  String _key(String mediaId, {int? season, int? episode}) {
    if (season != null && episode != null) {
      return 'status_${mediaId}_s${season}_e$episode';
    }
    return 'status_$mediaId';
  }

  @override
  Future<void> saveStatus(MediaStatus entry) async {
    final key = _key(
      entry.mediaId,
      season: entry.season,
      episode: entry.episode,
    );
    await _box.put(key, entry.toMap());
  }

  @override
  Future<MediaStatus?> getStatus(
    String mediaId, {
    int? season,
    int? episode,
  }) async {
    final key = _key(mediaId, season: season, episode: episode);
    final data = _box.get(key);
    if (data == null) return null;
    return MediaStatus.fromMap(data);
  }

  @override
  Future<List<MediaStatus>> getStatusesForMedia(String mediaId) async {
    // Filter by the stored mediaId field rather than the Hive key prefix —
    // this also avoids the false-positive case where a media id is a
    // prefix of another (e.g. "1234" vs "12345").
    final list = <MediaStatus>[];
    for (final data in _box.values) {
      final entry = MediaStatus.fromMap(data);
      if (entry.mediaId == mediaId) list.add(entry);
    }
    return list;
  }

  @override
  Future<List<MediaStatus>> getEntriesByStatus(WatchStatus status) async {
    final list = <MediaStatus>[];
    for (final data in _box.values) {
      final entry = MediaStatus.fromMap(data);
      if (entry.status == status) list.add(entry);
    }
    return list;
  }

  @override
  Future<void> deleteStatus(String mediaId, {int? season, int? episode}) async {
    final key = _key(mediaId, season: season, episode: episode);
    await _box.delete(key);
  }

  @override
  Future<void> deleteAllStatusesForMedia(String mediaId) async {
    // Collect matching keys via toMap() so we pay one box traversal and
    // then a single batched deleteAll instead of N awaited deletes.
    final keysToRemove = <dynamic>[];
    // `_box` is Box<Map>, so entry.value is already a Map — no need for
    // an extra `is Map` check.
    for (final entry in _box.toMap().entries) {
      if (entry.value['mediaId']?.toString() == mediaId) {
        keysToRemove.add(entry.key);
      }
    }
    if (keysToRemove.isNotEmpty) {
      await _box.deleteAll(keysToRemove);
    }
  }
}
