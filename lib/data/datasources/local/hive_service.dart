import 'package:hive_flutter/hive_flutter.dart';

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
  }
}
