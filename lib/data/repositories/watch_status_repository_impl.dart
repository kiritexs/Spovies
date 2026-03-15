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
    final prefix = 'status_${mediaId}_';
    final list = <MediaStatus>[];
    for (final key in _box.keys) {
      if (key is String && (key == 'status_$mediaId' || key.startsWith(prefix))) {
        final data = _box.get(key);
        if (data != null) list.add(MediaStatus.fromMap(data));
      }
    }
    return list;
  }

  @override
  Future<List<MediaStatus>> getEntriesByStatus(WatchStatus status) async {
    final list = <MediaStatus>[];
    for (final key in _box.keys) {
      final data = _box.get(key);
      if (data != null) {
        final entry = MediaStatus.fromMap(data);
        if (entry.status == status) list.add(entry);
      }
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
    final keysToRemove = <String>[];
    final prefix = 'status_${mediaId}_';
    final exactKey = 'status_$mediaId';
    for (final key in _box.keys) {
      if (key is String && (key == exactKey || key.startsWith(prefix))) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      await _box.delete(key);
    }
  }
}
