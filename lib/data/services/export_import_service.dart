import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../datasources/local/hive_service.dart';
import '../models/plugin_manifest_model.dart';

/// What [ExportImportService.applyImport] would write, so the UI can
/// confirm with the user **before** anything lands.
///
/// [plugins] is the high-risk surface — each entry becomes a potential
/// `launchUrl` target. Only validated manifests reach it; the rest are
/// summarised in [rejectedPlugins]. See `docs/architecture/DATA.md`.
final class ImportPreview {
  final int watchHistoryCount;
  final int watchlistCount;
  final int settingsCount;
  final List<({String key, String name, String urlTemplate})> plugins;
  final List<({String key, String reason})> rejectedPlugins;
  final Map<String, dynamic> rawPayload;

  const ImportPreview({
    required this.watchHistoryCount,
    required this.watchlistCount,
    required this.settingsCount,
    required this.plugins,
    required this.rejectedPlugins,
    required this.rawPayload,
  });
}

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

  /// Pick a `.spovies` file and parse it WITHOUT touching local storage.
  ///
  /// Returns `null` if the user cancelled the file picker. Throws on any
  /// real error (corrupt file, version mismatch, IO error). The caller is
  /// expected to show a confirmation dialog using the returned
  /// [ImportPreview] and then call [applyImport] with it.
  static Future<ImportPreview?> previewImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final path = result.files.single.path;
    if (path == null) return null;

    final file = File(path);
    final compressed = await file.readAsBytes();
    final jsonBytes = gzip.decode(compressed);
    final jsonStr = utf8.decode(jsonBytes);
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final version = data['schemaVersion'] as int? ?? 0;
    if (version > _schemaVersion) {
      throw FormatException(
        'Backup file is from a newer version (v$version). '
        'Please update the app.',
      );
    }

    final watchHistory = data['watchHistory'] as List<dynamic>?;
    final watchlist = data['watchlist'] as List<dynamic>?;
    final settings = data['settings'] as Map<String, dynamic>?;
    final rawPlugins = data['plugins'] as List<dynamic>? ?? const [];

    final accepted = <({String key, String name, String urlTemplate})>[];
    final rejected = <({String key, String reason})>[];
    for (final raw in rawPlugins) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final key =
          (map['_key'] as String?) ?? (map['pluginId'] as String?) ?? '';
      try {
        final manifest = PluginManifestModel.fromJson(map);
        accepted.add((
          key: key,
          name: manifest.name,
          urlTemplate: manifest.urlTemplate,
        ));
      } catch (e) {
        rejected.add((key: key.isEmpty ? '(unknown)' : key, reason: '$e'));
      }
    }

    return ImportPreview(
      watchHistoryCount: watchHistory?.length ?? 0,
      watchlistCount: watchlist?.length ?? 0,
      settingsCount: settings?.length ?? 0,
      plugins: accepted,
      rejectedPlugins: rejected,
      rawPayload: data,
    );
  }

  /// Merge a [preview] into the local database after the UI has confirmed
  /// with the user. Plugins that failed validation in [previewImport] are
  /// skipped here too — re-running validation defends against a TOCTOU
  /// between preview and apply.
  ///
  /// Returns `true` if anything was actually written.
  static Future<bool> applyImport(ImportPreview preview) async {
    final data = preview.rawPayload;
    await _mergeWatchHistory(data['watchHistory'] as List<dynamic>?);
    await _mergeWatchlist(data['watchlist'] as List<dynamic>?);
    await _mergePlugins(data['plugins'] as List<dynamic>?);
    await _importSettings(data['settings'] as Map<String, dynamic>?);
    return true;
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
        // Keep the entry with the more recent lastPlayedDate.
        // UserProgress.toMap() stores the date as an ISO-8601 string
        // under 'lastPlayedDate', NOT as an integer 'lastPlayedAt'.
        final existingDateStr = existing['lastPlayedDate'] as String?;
        final importDateStr = map['lastPlayedDate'] as String?;
        if (existingDateStr != null && importDateStr != null) {
          final existingDate = DateTime.tryParse(existingDateStr);
          final importDate = DateTime.tryParse(importDateStr);
          if (existingDate != null &&
              importDate != null &&
              !importDate.isAfter(existingDate)) {
            continue;
          }
        }
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
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final key = map.remove('_key') as String?;
      if (key == null) continue;

      // Re-validate at write time. Even though `previewImport` already
      // filtered the list, going through [PluginManifestModel.fromJson]
      // again here protects against:
      //   • callers that skipped the preview path
      //   • TOCTOU between preview and apply (file tampering is unlikely
      //     locally but the validation is cheap)
      //   • future code paths that construct an ImportPreview directly.
      try {
        PluginManifestModel.fromJson(map);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('ExportImportService: skipping invalid plugin "$key": $e');
        }
        continue;
      }

      // Union: only add if not already installed.
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
