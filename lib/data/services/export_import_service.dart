import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../../domain/entities/user_progress.dart';
import '../../domain/entities/watch_status.dart';
import '../datasources/local/hive_service.dart';
import '../datasources/local/storage_keys.dart';
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
  final int statusCount;
  final int settingsCount;
  final List<({String key, String name, String urlTemplate})> plugins;
  final List<({String key, String reason})> rejectedPlugins;
  final Map<String, dynamic> rawPayload;

  const ImportPreview({
    required this.watchHistoryCount,
    required this.watchlistCount,
    required this.statusCount,
    required this.settingsCount,
    required this.plugins,
    required this.rejectedPlugins,
    required this.rawPayload,
  });
}

/// Handles export and import of all user data as compressed `.spovies` files.
///
/// Data includes: watch history, watchlist, watch statuses, installed
/// plugins, and settings. Format: JSON → gzip → `.spovies` extension.
class ExportImportService {
  /// v2 added `listStatus`. v1 backups (no statuses) still import.
  static const int _schemaVersion = 2;

  /// Largest backup file accepted, and the largest it may decompress to.
  /// Real backups are a few hundred KB; the caps stop a zip bomb.
  static const int _maxFileBytes = 10 * 1024 * 1024;
  static const int _maxDecodedBytes = 50 * 1024 * 1024;

  // ─── Export ──────────────────────────────────────────────────────────

  /// Export all user data as a `.spovies` file and open the share sheet.
  static Future<void> exportData() async {
    final payload = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'watchHistory': _boxValues(HiveService.watchHistoryBox),
      'watchlist': _boxValues(HiveService.watchlistBox),
      'listStatus': _boxValues(HiveService.listStatusBox),
      'plugins': _boxValues(HiveService.pluginsBox),
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
    if (await file.length() > _maxFileBytes) {
      throw const FormatException('Backup file is too large.');
    }
    return parseBackup(await file.readAsBytes());
  }

  /// Decode and validate a backup. Public so it can be tested without a
  /// file picker.
  @visibleForTesting
  static ImportPreview parseBackup(Uint8List compressed) {
    final jsonStr = utf8.decode(_gunzipCapped(compressed));
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Not a Spovies backup file.');
    }
    final data = decoded;

    final version = data['schemaVersion'] as int? ?? 0;
    if (version > _schemaVersion) {
      throw FormatException(
        'Backup file is from a newer version (v$version). '
        'Please update the app.',
      );
    }

    final accepted = <({String key, String name, String urlTemplate})>[];
    final rejected = <({String key, String reason})>[];
    for (final raw in _list(data['plugins'])) {
      final map = Map<String, dynamic>.from(raw);
      final key =
          (map['pluginId'] as String?) ?? (map['_key'] as String?) ?? '';
      try {
        final manifest = PluginManifestModel.fromJson(map);
        accepted.add((
          key: manifest.pluginId,
          name: manifest.name,
          urlTemplate: manifest.urlTemplate,
        ));
      } catch (e) {
        rejected.add((key: key.isEmpty ? '(unknown)' : key, reason: '$e'));
      }
    }

    return ImportPreview(
      watchHistoryCount: _list(data['watchHistory']).length,
      watchlistCount: _list(data['watchlist']).length,
      statusCount: _list(data['listStatus']).length,
      settingsCount: _allowedSettings(data['settings']).length,
      plugins: accepted,
      rejectedPlugins: rejected,
      rawPayload: data,
    );
  }

  /// Merge a [preview] into the local database after the UI has confirmed
  /// with the user. Every entry is re-validated and re-keyed from its own
  /// content, so a malformed or tampered backup is skipped entry by entry
  /// instead of being written raw (which could crash the app on launch).
  ///
  /// Returns `true` if anything was actually written.
  static Future<bool> applyImport(ImportPreview preview) async {
    final data = preview.rawPayload;
    var written = 0;
    written += await _mergeWatchHistory(_list(data['watchHistory']));
    written += await _mergeWatchlist(_list(data['watchlist']));
    written += await _mergeStatuses(_list(data['listStatus']));
    written += await _mergePlugins(_list(data['plugins']));
    written += await _importSettings(_allowedSettings(data['settings']));
    return written > 0;
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  static List<int> _gunzipCapped(Uint8List compressed) {
    final collector = _CappedCollector(_maxDecodedBytes);
    gzip.decoder.startChunkedConversion(collector)
      ..add(compressed)
      ..close();
    return collector.bytes;
  }

  static List<Map<dynamic, dynamic>> _list(dynamic raw) =>
      raw is List ? raw.whereType<Map<dynamic, dynamic>>().toList() : const [];

  static List<Map<String, dynamic>> _boxValues(Box<dynamic> box) {
    final entries = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final value = box.get(key);
      if (value is Map) entries.add(Map<String, dynamic>.from(value));
    }
    return entries;
  }

  static const _pluginEnabledPrefix = 'plugin_enabled:';

  /// Only settings the app actually reads, with the type it expects.
  static Map<String, dynamic> _allowedSettings(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      final ok = switch (key) {
        'preferredPlugin' => value == null || value is String,
        _ => key.startsWith(_pluginEnabledPrefix) && value is bool,
      };
      if (ok) out[key] = value;
    }
    return out;
  }

  static Map<String, dynamic> _settingsToMap() {
    return _allowedSettings({
      for (final key in HiveService.settingsBox.keys)
        key.toString(): HiveService.settingsBox.get(key),
    });
  }

  static Future<int> _mergeWatchHistory(
    List<Map<dynamic, dynamic>> items,
  ) async {
    var written = 0;
    for (final item in items) {
      final raw = _withMediaType(item);
      if (raw == null) continue;
      final UserProgress progress;
      try {
        progress = UserProgress.fromMap(raw);
      } catch (_) {
        continue;
      }
      if (progress.mediaId.isEmpty) continue;
      final key = StorageKeys.progress(
        progress.mediaType,
        progress.mediaId,
        season: progress.season,
        episode: progress.episode,
      );
      final existing = HiveService.watchHistoryBox.get(key);
      if (existing != null &&
          !_importWins(raw['lastPlayedDate'], existing['lastPlayedDate'])) {
        continue; // keep the more recent (or only dated) local entry
      }
      await HiveService.watchHistoryBox.put(key, progress.toMap());
      written++;
    }
    return written;
  }

  static Future<int> _mergeWatchlist(List<Map<dynamic, dynamic>> items) async {
    var written = 0;
    for (final raw in items) {
      final tmdbId = raw['tmdbId'];
      if (tmdbId is! int || tmdbId <= 0) continue;
      final type = _mediaType(raw['type']) ?? 'movie';
      final key = StorageKeys.watchlist(type, tmdbId);
      if (HiveService.watchlistBox.containsKey(key)) continue;
      await HiveService.watchlistBox.put(key, _watchlistEntry(raw, type));
      written++;
    }
    return written;
  }

  /// A watchlist entry rebuilt field by field with the types the app
  /// reads back. Copying the raw map let a wrong type (e.g. `"title": 7`)
  /// through, which then failed on every launch.
  static Map<String, dynamic> _watchlistEntry(
    Map<dynamic, dynamic> raw,
    String type,
  ) {
    String? text(String k) => raw[k] is String ? raw[k] as String : null;
    final genreIds = raw['genreIds'];
    return {
      'tmdbId': raw['tmdbId'],
      'type': type,
      'title': text('title') ?? '',
      'posterPath': text('posterPath'),
      'backdropPath': text('backdropPath'),
      'overview': text('overview'),
      'releaseDate': text('releaseDate'),
      'rating': raw['rating'] is num ? raw['rating'] : null,
      'genreIds': genreIds is List
          ? genreIds.whereType<int>().toList()
          : <int>[],
    };
  }

  /// `movie` or `tv` (any case), else null: other values are rejected so
  /// an entry can't land under a key nothing else looks up.
  static String? _mediaType(Object? raw) {
    final type = raw?.toString().toLowerCase();
    return type == 'movie' || type == 'tv' ? type : null;
  }

  /// [raw] with `mediaType` normalised, or null if it isn't movie/tv.
  static Map<dynamic, dynamic>? _withMediaType(Map<dynamic, dynamic> raw) {
    final type = _mediaType(raw['mediaType']);
    return type == null ? null : (Map.of(raw)..['mediaType'] = type);
  }

  /// Whether an imported entry dated [incoming] should replace a local
  /// one dated [local]. An undated import never replaces a local entry
  /// (it would otherwise parse as "now" and always win).
  static bool _importWins(Object? incoming, Object? local) {
    final inDate = DateTime.tryParse(incoming?.toString() ?? '');
    if (inDate == null) return false;
    final localDate = DateTime.tryParse(local?.toString() ?? '');
    return localDate == null || inDate.isAfter(localDate);
  }

  static Future<int> _mergeStatuses(List<Map<dynamic, dynamic>> items) async {
    var written = 0;
    for (final item in items) {
      final raw = _withMediaType(item);
      if (raw == null) continue;
      final MediaStatus status;
      try {
        status = MediaStatus.fromMap(raw);
      } catch (_) {
        continue;
      }
      if (status.mediaId.isEmpty) continue;
      final key = StorageKeys.status(
        status.mediaType,
        status.mediaId,
        season: status.season,
        episode: status.episode,
      );
      final existing = HiveService.listStatusBox.get(key);
      if (existing != null &&
          !_importWins(raw['updatedAt'], existing['updatedAt'])) {
        continue;
      }
      await HiveService.listStatusBox.put(key, status.toMap());
      written++;
    }
    return written;
  }

  static Future<int> _mergePlugins(List<Map<dynamic, dynamic>> items) async {
    var written = 0;
    for (final raw in items) {
      final map = Map<String, dynamic>.from(raw)..remove('_key');
      // Re-validate at write time (defends against a TOCTOU between preview
      // and apply), and store under the validated pluginId — the key that
      // uninstall uses — never under a key taken from the file.
      final String pluginId;
      try {
        pluginId = PluginManifestModel.fromJson(map).pluginId;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('ExportImportService: skipping invalid plugin: $e');
        }
        continue;
      }
      if (HiveService.pluginsBox.containsKey(pluginId)) continue;
      await HiveService.pluginsBox.put(pluginId, map);
      written++;
    }
    return written;
  }

  static Future<int> _importSettings(Map<String, dynamic> settings) async {
    for (final entry in settings.entries) {
      await HiveService.settingsBox.put(entry.key, entry.value);
    }
    return settings.length;
  }
}

/// Collects decoded bytes and throws once more than [limit] arrive.
class _CappedCollector implements Sink<List<int>> {
  final int limit;
  final BytesBuilder _out = BytesBuilder(copy: false);

  _CappedCollector(this.limit);

  List<int> get bytes => _out.toBytes();

  @override
  void add(List<int> data) {
    if (_out.length + data.length > limit) {
      throw const FormatException('Backup file expands to an unsafe size.');
    }
    _out.add(data);
  }

  @override
  void close() {}
}
