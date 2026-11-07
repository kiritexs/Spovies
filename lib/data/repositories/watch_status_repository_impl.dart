import 'package:hive_flutter/hive_flutter.dart';

import '../datasources/local/hive_service.dart';
import '../datasources/local/storage_keys.dart';
import '../../domain/entities/watch_status.dart';
import '../../domain/repositories/watch_status_repository.dart';

/// Hive-backed implementation of [WatchStatusRepository].
class WatchStatusRepositoryImpl implements WatchStatusRepository {
  Box<Map<dynamic, dynamic>> get _box => HiveService.listStatusBox;

  @override
  Future<void> saveStatus(MediaStatus entry) async {
    final key = StorageKeys.status(
      entry.mediaType,
      entry.mediaId,
      season: entry.season,
      episode: entry.episode,
    );
    await _box.put(key, entry.toMap());
  }

  @override
  Future<MediaStatus?> getStatus(
    String mediaId, {
    required String mediaType,
    int? season,
    int? episode,
  }) async {
    final key = StorageKeys.status(
      mediaType,
      mediaId,
      season: season,
      episode: episode,
    );
    final data = _box.get(key);
    if (data == null) return null;
    return MediaStatus.fromMap(data);
  }

  @override
  Future<List<MediaStatus>> getStatusesForMedia(
    String mediaId, {
    required String mediaType,
  }) async {
    final list = <MediaStatus>[];
    for (final data in _box.values) {
      final entry = MediaStatus.fromMap(data);
      if (entry.mediaId == mediaId && entry.mediaType == mediaType) {
        list.add(entry);
      }
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
  Future<List<MediaStatus>> getAllTitleStatuses() async {
    return [
      for (final data in _box.values)
        if (data['season'] == null && data['episode'] == null)
          MediaStatus.fromMap(data),
    ];
  }

  @override
  Future<void> deleteStatus(
    String mediaId, {
    required String mediaType,
    int? season,
    int? episode,
  }) async {
    await _box.delete(
      StorageKeys.status(mediaType, mediaId, season: season, episode: episode),
    );
  }

  @override
  Future<void> deleteAllStatusesForMedia(
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
  Future<void> clearAll() async {
    await _box.clear();
  }
}
