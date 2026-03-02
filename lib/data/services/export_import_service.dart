import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../datasources/local/hive_service.dart';

/// Handles export and import of all user data as compressed `.spovies` files.
///
/// Data includes: watch history, watchlist, installed plugins, and settings.
/// Format: JSON → gzip → `.spovies` extension.
class ExportImportService {
  static const int _schemaVersion = 1;

  // ─── Export ──────────────────────────────────────────────────────────

  /// Export all user data as a `.spovies` file and open the share sheet.
  static Future<void> exportData() async {
    final payload = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'watchHistory': _boxToList(HiveService.watchHistoryBox),
      'watchlist': _boxToList(HiveService.watchlistBox),
      'plugins': _boxToMapEntries(HiveService.pluginsBox),
      'settings': _settingsToMap(),
    };

    final jsonBytes = utf8.encode(jsonEncode(payload));
    final compressed = gzip.encode(jsonBytes);

    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/spovies_backup_$timestamp.spovies');
    await file.writeAsBytes(compressed);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'Spovies Backup'),
    );
  }

  // ─── Import ─────────────────────────────────────────────────────────

  /// Pick a `.spovies` file and merge its data into the local database.
  ///
  /// Returns `true` if import succeeded, `false` if cancelled or failed.
  static Future<bool> importData() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return false;

    final path = result.files.single.path;
    if (path == null) return false;

    try {
      final file = File(path);
      final compressed = await file.readAsBytes();
      final jsonBytes = gzip.decode(compressed);
      final jsonStr = utf8.decode(Uint8List.fromList(jsonBytes));
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Validate schema
      final version = data['schemaVersion'] as int? ?? 0;
      if (version > _schemaVersion) {
        throw FormatException(
          'Backup file is from a newer version (v$version). '
          'Please update the app.',
        );
      }

      // Merge watch history (keep latest per key)
      await _mergeWatchHistory(data['watchHistory'] as List<dynamic>?);

      // Merge watchlist (union)
      await _mergeWatchlist(data['watchlist'] as List<dynamic>?);

      // Merge plugins (union by pluginId)
      await _mergePlugins(data['plugins'] as List<dynamic>?);

      // Import settings (overwrite)
      await _importSettings(data['settings'] as Map<String, dynamic>?);

      return true;
    } catch (e) {
      if (kDebugMode) print('Import error: $e');
      return false;
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _boxToList(dynamic box) {
    final entries = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final value = box.get(key);
      if (value != null) {
        entries.add({
          '_key': key.toString(),
          ...Map<String, dynamic>.from(value as Map),
        });
      }
    }
    return entries;
  }

  static List<Map<String, dynamic>> _boxToMapEntries(dynamic box) {
    final entries = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final value = box.get(key);
      if (value != null) {
        entries.add({
          '_key': key.toString(),
          ...Map<String, dynamic>.from(value as Map),
        });
      }
    }
    return entries;
  }

  static Map<String, dynamic> _settingsToMap() {
    final map = <String, dynamic>{};
    for (final key in HiveService.settingsBox.keys) {
      map[key.toString()] = HiveService.settingsBox.get(key);
    }
    return map;
  }

  static Future<void> _mergeWatchHistory(List<dynamic>? items) async {
    if (items == null) return;
    for (final item in items) {
      final map = Map<String, dynamic>.from(item as Map);
      final key = map.remove('_key') as String?;
      if (key == null) continue;

      final existing = HiveService.watchHistoryBox.get(key);
      if (existing != null) {
        // Keep the one with the more recent lastPlayedAt
        final existingTime = existing['lastPlayedAt'] as int? ?? 0;
        final importTime = map['lastPlayedAt'] as int? ?? 0;
        if (importTime <= existingTime) continue;
      }
      await HiveService.watchHistoryBox.put(key, map);
    }
  }

  static Future<void> _mergeWatchlist(List<dynamic>? items) async {
    if (items == null) return;
    for (final item in items) {
      final map = Map<String, dynamic>.from(item as Map);
      final key = map.remove('_key') as String?;
      if (key == null) continue;

      // Union: only add if not already present
      if (!HiveService.watchlistBox.containsKey(key)) {
        await HiveService.watchlistBox.put(key, map);
      }
    }
  }

  static Future<void> _mergePlugins(List<dynamic>? items) async {
    if (items == null) return;
    for (final item in items) {
      final map = Map<String, dynamic>.from(item as Map);
      final key = map.remove('_key') as String?;
      if (key == null) continue;

      // Union: only add if not already installed
      if (!HiveService.pluginsBox.containsKey(key)) {
        await HiveService.pluginsBox.put(key, map);
      }
    }
  }

  static Future<void> _importSettings(Map<String, dynamic>? settings) async {
    if (settings == null) return;
    for (final entry in settings.entries) {
      await HiveService.settingsBox.put(entry.key, entry.value);
    }
  }
}
