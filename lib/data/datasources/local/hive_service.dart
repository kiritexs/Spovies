import 'package:hive_flutter/hive_flutter.dart';

import 'storage_keys.dart';

/// Centralized Hive box management.
///
/// All boxes are opened once at startup and shared across the app.
class HiveService {
  static const String pluginsBoxName = 'plugins';
  static const String settingsBoxName = 'settings';
  static const String watchHistoryBoxName = 'watch_history';
  static const String watchlistBoxName = 'watchlist';
  static const String listStatusBoxName = 'list_status';
  static const String tmdbCacheBoxName = 'tmdb_cache';

  static late Box<Map> pluginsBox;
  static late Box<dynamic> settingsBox;
  static late Box<Map> watchHistoryBox;
  static late Box<Map> watchlistBox;
  static late Box<Map> listStatusBox;
  static late Box<Map> tmdbCacheBox;

  /// Initialize Hive and open all application boxes.
  ///
  /// Call this once in `main()` before `runApp()`.
  static Future<void> init() async {
    await Hive.initFlutter();

    pluginsBox = await Hive.openBox<Map>(pluginsBoxName);
    settingsBox = await Hive.openBox<dynamic>(settingsBoxName);
    watchHistoryBox = await Hive.openBox<Map>(watchHistoryBoxName);
    watchlistBox = await Hive.openBox<Map>(watchlistBoxName);
    listStatusBox = await Hive.openBox<Map>(listStatusBoxName);
    tmdbCacheBox = await Hive.openBox<Map>(tmdbCacheBoxName);

    await migrateStorageKeys();
  }

  /// One-time migration to [StorageKeys] version 2, which adds the media
  /// type to every per-title key. Older keys used the bare TMDB id, so a
  /// movie and a show with the same id overwrote each other.
  ///
  /// Each entry is re-keyed from the `mediaType` stored in its own value.
  /// When two old entries map to the same new key, the newer one wins.
  static Future<void> migrateStorageKeys() async {
    final current = settingsBox.get(StorageKeys.versionSettingKey);
    if (current is int && current >= StorageKeys.version) return;

    await _rekey(
      listStatusBox,
      (v) => StorageKeys.status(
        _type(v['mediaType']),
        v['mediaId'].toString(),
        season: _int(v['season']),
        episode: _int(v['episode']),
      ),
      dateField: 'updatedAt',
    );
    await _rekey(
      watchHistoryBox,
      (v) => StorageKeys.progress(
        _type(v['mediaType']),
        v['mediaId'].toString(),
        season: _int(v['season']),
        episode: _int(v['episode']),
      ),
      dateField: 'lastPlayedDate',
    );
    await _rekey(
      watchlistBox,
      (v) => StorageKeys.watchlist(_type(v['type']), _int(v['tmdbId']) ?? 0),
    );

    await settingsBox.put(StorageKeys.versionSettingKey, StorageKeys.version);
  }

  static Future<void> _rekey(
    Box<Map> box,
    String Function(Map value) newKeyOf, {
    String? dateField,
  }) async {
    final moves = <dynamic, MapEntry<String, Map>>{};
    for (final entry in box.toMap().entries) {
      final String newKey;
      try {
        newKey = newKeyOf(entry.value);
      } catch (_) {
        continue; // malformed entry: leave it where it is
      }
      if (newKey == entry.key) continue;

      final existing = moves[newKey]?.value ?? box.get(newKey);
      if (existing != null &&
          dateField != null &&
          !_isNewer(entry.value[dateField], existing[dateField])) {
        moves[entry.key] = MapEntry(newKey, existing); // drop the older one
        continue;
      }
      moves[entry.key] = MapEntry(newKey, entry.value);
    }
    if (moves.isEmpty) return;

    final puts = <String, Map>{};
    for (final move in moves.values) {
      puts[move.key] = move.value;
    }
    await box.putAll(puts);
    await box.deleteAll(moves.keys.where((k) => !puts.containsKey(k)));
  }

  static String _type(dynamic raw) => raw == 'tv' ? 'tv' : 'movie';

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static bool _isNewer(dynamic a, dynamic b) {
    final da = a is String ? DateTime.tryParse(a) : null;
    final db = b is String ? DateTime.tryParse(b) : null;
    if (da == null) return false;
    if (db == null) return true;
    return da.isAfter(db);
  }
}
