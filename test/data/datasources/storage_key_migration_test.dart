// The one-time key migration must move old bare-id keys to type-prefixed
// keys without losing data, and keep the newer entry when two collide.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:spovies/data/datasources/local/hive_service.dart';
import 'package:spovies/data/datasources/local/storage_keys.dart';

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('spovies_migration_test_');
    Hive.init(tmpDir.path);
    HiveService.settingsBox = await Hive.openBox(HiveService.settingsBoxName);
    HiveService.watchHistoryBox = await Hive.openBox<Map<dynamic, dynamic>>(
      HiveService.watchHistoryBoxName,
    );
    HiveService.watchlistBox = await Hive.openBox<Map<dynamic, dynamic>>(
      HiveService.watchlistBoxName,
    );
    HiveService.listStatusBox = await Hive.openBox<Map<dynamic, dynamic>>(
      HiveService.listStatusBoxName,
    );
  });

  tearDownAll(() async {
    await Hive.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  setUp(() async {
    await HiveService.settingsBox.clear();
    await HiveService.watchHistoryBox.clear();
    await HiveService.watchlistBox.clear();
    await HiveService.listStatusBox.clear();
  });

  test('re-keys statuses, progress, and watchlist by media type', () async {
    await HiveService.listStatusBox.put('status_7', {
      'mediaId': '7',
      'mediaType': 'tv',
      'status': 'watching',
      'updatedAt': '2026-01-01T00:00:00.000',
    });
    await HiveService.listStatusBox.put('status_7_s1_e2', {
      'mediaId': '7',
      'mediaType': 'tv',
      'status': 'completed',
      'season': 1,
      'episode': 2,
      'updatedAt': '2026-01-01T00:00:00.000',
    });
    await HiveService.watchHistoryBox.put('9', {
      'mediaId': '9',
      'mediaType': 'movie',
      'lastPlayedDate': '2026-01-01T00:00:00.000',
    });
    await HiveService.watchlistBox.put('7', {'tmdbId': 7, 'type': 'tv'});

    await HiveService.migrateStorageKeys();

    expect(
      HiveService.listStatusBox.keys,
      unorderedEquals(['status_tv_7', 'status_tv_7_s1_e2']),
    );
    expect(HiveService.watchHistoryBox.keys, ['movie_9']);
    expect(HiveService.watchlistBox.keys, ['tv_7']);
    expect(
      HiveService.settingsBox.get(StorageKeys.versionSettingKey),
      StorageKeys.version,
    );
  });

  test('when old entries collide, the newer one wins', () async {
    // An already-migrated entry and an old-format entry for the same title.
    await HiveService.watchHistoryBox.put('movie_5', {
      'mediaId': '5',
      'mediaType': 'movie',
      'percentage': 80,
      'lastPlayedDate': '2026-03-01T00:00:00.000',
    });
    await HiveService.watchHistoryBox.put('5', {
      'mediaId': '5',
      'mediaType': 'movie',
      'percentage': 10,
      'lastPlayedDate': '2026-01-01T00:00:00.000',
    });

    await HiveService.migrateStorageKeys();

    expect(HiveService.watchHistoryBox.keys, ['movie_5']);
    expect(HiveService.watchHistoryBox.get('movie_5')?['percentage'], 80);
  });

  test(
    'old entries colliding on one key: the newer wins in any order',
    () async {
      Future<void> run(List<(String, String, String)> rows) async {
        await HiveService.settingsBox.clear();
        await HiveService.listStatusBox.clear();
        for (final (key, status, date) in rows) {
          await HiveService.listStatusBox.put(key, {
            'mediaId': '3',
            'mediaType': 'movie',
            'status': status,
            'updatedAt': date,
          });
        }
        await HiveService.migrateStorageKeys();
      }

      await run([
        ('status_3', 'completed', '2026-05-01T00:00:00.000'),
        ('legacy_3', 'dropped', '2026-01-01T00:00:00.000'),
      ]);
      expect(HiveService.listStatusBox.keys, ['status_movie_3']);
      expect(
        HiveService.listStatusBox.get('status_movie_3')?['status'],
        'completed',
      );

      await run([
        ('legacy_3', 'completed', '2026-05-01T00:00:00.000'),
        ('status_3', 'dropped', '2026-01-01T00:00:00.000'),
      ]);
      expect(HiveService.listStatusBox.keys, ['status_movie_3']);
      expect(
        HiveService.listStatusBox.get('status_movie_3')?['status'],
        'completed',
      );
    },
  );

  test('entries without an id are left alone, not merged', () async {
    await HiveService.listStatusBox.put('bad_a', {'status': 'watching'});
    await HiveService.listStatusBox.put('bad_b', {'status': 'dropped'});
    await HiveService.watchlistBox.put('bad_c', {'type': 'tv'});

    await HiveService.migrateStorageKeys();

    expect(HiveService.listStatusBox.keys, unorderedEquals(['bad_a', 'bad_b']));
    expect(HiveService.watchlistBox.keys, ['bad_c']);
  });

  test('runs only once', () async {
    await HiveService.settingsBox.put(
      StorageKeys.versionSettingKey,
      StorageKeys.version,
    );
    await HiveService.watchHistoryBox.put('5', {
      'mediaId': '5',
      'mediaType': 'movie',
    });

    await HiveService.migrateStorageKeys();

    expect(HiveService.watchHistoryBox.keys, ['5']);
  });
}
