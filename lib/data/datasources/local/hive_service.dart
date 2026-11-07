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

  static late Box<Map<dynamic, dynamic>> pluginsBox;
  static late Box<dynamic> settingsBox;
  static late Box<Map<dynamic, dynamic>> watchHistoryBox;
  static late Box<Map<dynamic, dynamic>> watchlistBox;
  static late Box<Map<dynamic, dynamic>> listStatusBox;
  static late Box<Map<dynamic, dynamic>> tmdbCacheBox;

  /// Initialize Hive and open all application boxes.
  ///
  /// Call this once in `main()` before `runApp()`.
  static Future<void> init() async {
    await Hive.initFlutter();

    pluginsBox = await Hive.openBox<Map<dynamic, dynamic>>(pluginsBoxName);
    settingsBox = await Hive.openBox<dynamic>(settingsBoxName);
    watchHistoryBox = await Hive.openBox<Map<dynamic, dynamic>>(
      watchHistoryBoxName,
    );
    watchlistBox = await Hive.openBox<Map<dynamic, dynamic>>(watchlistBoxName);
    listStatusBox = await Hive.openBox<Map<dynamic, dynamic>>(
      listStatusBoxName,
    );
    tmdbCacheBox = await Hive.openBox<Map<dynamic, dynamic>>(tmdbCacheBoxName);

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
      (v) => _id(v['mediaId']) == null
          ? null
          : StorageKeys.status(
              _type(v['mediaType']),
              _id(v['mediaId'])!,
              season: _int(v['season']),
              episode: _int(v['episode']),
            ),
      dateField: 'updatedAt',
    );
    await _rekey(
      watchHistoryBox,
      (v) => _id(v['mediaId']) == null
          ? null
          : StorageKeys.progress(
              _type(v['mediaType']),
              _id(v['mediaId'])!,
              season: _int(v['season']),
              episode: _int(v['episode']),
            ),
      dateField: 'lastPlayedDate',
    );
    await _rekey(
      watchlistBox,
      (v) => _int(v['tmdbId']) == null
          ? null
          : StorageKeys.watchlist(_type(v['type']), _int(v['tmdbId'])!),
    );

    await settingsBox.put(StorageKeys.versionSettingKey, StorageKeys.version);
  }

  /// Move each entry to the key [newKeyOf] gives it. Entries it returns
  /// null for (no id) stay where they are. When several entries map to one
  /// new key — including an entry already there — the newest by
  /// [dateField] wins; without a date field the last one read wins.
  static Future<void> _rekey(
    Box<Map<dynamic, dynamic>> box,
    String? Function(Map<dynamic, dynamic> value) newKeyOf, {
    String? dateField,
  }) async {
    final winners = <String, Map<dynamic, dynamic>>{};
    final oldKeys = <dynamic>[];
    for (final entry in box.toMap().entries) {
      final String? newKey;
      try {
        newKey = newKeyOf(entry.value);
      } catch (_) {
        continue; // malformed entry: leave it where it is
      }
      if (newKey == null || newKey == entry.key) continue;
      oldKeys.add(entry.key);

      final current = winners[newKey] ?? box.get(newKey);
      if (current == null ||
          dateField == null ||
          _isNewer(entry.value[dateField], current[dateField])) {
        winners[newKey] = entry.value;
      }
    }
    if (oldKeys.isEmpty) return;

    await box.putAll(winners);
    await box.deleteAll(oldKeys.where((k) => !winners.containsKey(k)));
  }

  /// A non-empty id string, or null.
  static String? _id(dynamic v) {
    final id = v?.toString() ?? '';
    return id.isEmpty || id == 'null' ? null : id;
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
