// Backups: parseBackup validates before anything is written, and
// applyImport re-validates and re-keys every entry by media type.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:spovies/data/datasources/local/hive_service.dart';
import 'package:spovies/data/services/export_import_service.dart';

Uint8List _backup(Map<String, Object?> payload) =>
    Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(payload))));

Map<String, Object?> _payload() => {
  'schemaVersion': 2,
  'watchHistory': [
    {
      'mediaId': '5',
      'mediaType': 'tv',
      'title': 'Show',
      'percentage': 50,
      'currentTime': 600,
      'duration': 1200,
      'season': 1,
      'episode': 3,
      'lastPlayedDate': '2026-02-01T00:00:00.000',
    },
    {'garbage': true},
  ],
  'watchlist': [
    {'tmdbId': 5, 'type': 'movie', 'title': 'Movie 5'},
    {'tmdbId': 5, 'type': 'tv', 'title': 'Show 5'},
    {'tmdbId': 'not-an-int', 'type': 'movie'},
  ],
  'listStatus': [
    {
      'mediaId': '5',
      'mediaType': 'tv',
      'status': 'watching',
      'updatedAt': '2026-02-01T00:00:00.000',
    },
  ],
  'plugins': [
    {
      'pluginId': 'good',
      'name': 'Good',
      'urlTemplate': 'https://example.com/{{tmdbId}}',
    },
    {'pluginId': 'evil', 'name': 'Evil', 'urlTemplate': 'javascript:alert(1)'},
  ],
  'settings': {
    'preferredPlugin': 'good',
    'plugin_enabled:good': true,
    'themeMode': 'light', // no longer read: dropped
    'injected': 'nope',
  },
};

void main() {
  group('parseBackup', () {
    test('counts entries and screens plugins and settings', () {
      final preview = ExportImportService.parseBackup(_backup(_payload()));

      expect(preview.watchHistoryCount, 2);
      expect(preview.watchlistCount, 3);
      expect(preview.statusCount, 1);
      expect(preview.settingsCount, 2);
      expect(preview.plugins.map((p) => p.key), ['good']);
      expect(preview.rejectedPlugins.map((p) => p.key), ['evil']);
    });

    test('rejects a backup from a newer version', () {
      expect(
        () => ExportImportService.parseBackup(
          _backup({..._payload(), 'schemaVersion': 99}),
        ),
        throwsFormatException,
      );
    });

    test('rejects JSON that is not an object', () {
      // An empty object is a valid, empty backup...
      expect(
        () => ExportImportService.parseBackup(_backup({})),
        returnsNormally,
      );
      // ...but a list is not a backup at all.
      expect(
        () => ExportImportService.parseBackup(
          Uint8List.fromList(gzip.encode(utf8.encode('[1, 2, 3]'))),
        ),
        throwsFormatException,
      );
    });

    test('stops a file that decompresses past the size cap', () {
      // ~51 MB of zeros gzips to a few dozen KB.
      final bomb = Uint8List.fromList(gzip.encode(Uint8List(51 << 20)));
      expect(
        () => ExportImportService.parseBackup(bomb),
        throwsFormatException,
      );
    });
  });

  group('applyImport', () {
    late Directory tmpDir;

    setUpAll(() async {
      tmpDir = await Directory.systemTemp.createTemp('spovies_backup_test_');
      Hive.init(tmpDir.path);
      HiveService.watchHistoryBox = await Hive.openBox<Map<dynamic, dynamic>>(
        HiveService.watchHistoryBoxName,
      );
      HiveService.watchlistBox = await Hive.openBox<Map<dynamic, dynamic>>(
        HiveService.watchlistBoxName,
      );
      HiveService.listStatusBox = await Hive.openBox<Map<dynamic, dynamic>>(
        HiveService.listStatusBoxName,
      );
      HiveService.pluginsBox = await Hive.openBox<Map<dynamic, dynamic>>(
        HiveService.pluginsBoxName,
      );
      HiveService.settingsBox = await Hive.openBox(HiveService.settingsBoxName);
    });

    tearDownAll(() async {
      await Hive.close();
      if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
    });

    test('writes valid entries under type-prefixed keys only', () async {
      final preview = ExportImportService.parseBackup(_backup(_payload()));

      expect(await ExportImportService.applyImport(preview), isTrue);

      expect(HiveService.watchHistoryBox.keys, ['tv_5_s1_e3']);
      expect(
        HiveService.watchlistBox.keys,
        unorderedEquals(['movie_5', 'tv_5']),
      );
      expect(HiveService.listStatusBox.keys, ['status_tv_5']);
      expect(HiveService.pluginsBox.keys, ['good']);
      expect(HiveService.settingsBox.get('preferredPlugin'), 'good');
      expect(HiveService.settingsBox.containsKey('themeMode'), isFalse);
      expect(HiveService.settingsBox.containsKey('injected'), isFalse);
    });

    test('keeps newer local progress over an older backup', () async {
      await HiveService.watchHistoryBox.put('tv_5_s1_e3', {
        'mediaId': '5',
        'mediaType': 'tv',
        'title': 'Show',
        'percentage': 90,
        'currentTime': 1080,
        'duration': 1200,
        'season': 1,
        'episode': 3,
        'lastPlayedDate': '2026-06-01T00:00:00.000',
      });

      final preview = ExportImportService.parseBackup(_backup(_payload()));
      await ExportImportService.applyImport(preview);

      expect(HiveService.watchHistoryBox.get('tv_5_s1_e3')?['percentage'], 90);
    });
  });
}
