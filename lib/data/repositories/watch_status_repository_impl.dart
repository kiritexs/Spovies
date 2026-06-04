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
  Future<List<MediaStatus>> getStatusesForMedia(
    String mediaId, {
    required String mediaType,
  }) async {
    // Filter by the stored mediaId AND mediaType — TMDB issues independent
    // id spaces for movies and TV, so id "123" can refer to both an
    // unrelated movie and an unrelated show. The previous implementation
    // only filtered by mediaId and would mix them up.
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
  Future<void> deleteStatus(String mediaId, {int? season, int? episode}) async {
    final key = _key(mediaId, season: season, episode: episode);
    await _box.delete(key);
  }

  @override
  Future<void> deleteAllStatusesForMedia(
    String mediaId, {
    required String mediaType,
  }) async {
    // Collect matching keys via toMap() so we pay one box traversal and
    // then a single batched deleteAll instead of N awaited deletes.
    // Filter on BOTH mediaId and mediaType — see getStatusesForMedia for
    // why mediaType matters (independent TMDB id spaces).
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
}
