// A movie and a TV show can share a TMDB id. Watch progress for one must
// never merge with, or be deleted alongside, the other.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:spovies/data/datasources/local/hive_service.dart';
import 'package:spovies/data/repositories/watch_history_repository_impl.dart';
import 'package:spovies/domain/entities/user_progress.dart';

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('spovies_history_test_');
    Hive.init(tmpDir.path);
    HiveService.watchHistoryBox = await Hive.openBox<Map>(
      HiveService.watchHistoryBoxName,
    );
  });

  tearDownAll(() async {
    await Hive.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  late WatchHistoryRepositoryImpl repo;
  setUp(() async {
    repo = WatchHistoryRepositoryImpl();
    await HiveService.watchHistoryBox.clear();
  });

  UserProgress progress(
    String type, {
    int? season,
    int? episode,
    required DateTime played,
  }) => UserProgress(
    mediaId: '123',
    mediaType: type,
    title: '$type 123',
    percentage: 40,
    currentTime: 400,
    duration: 1000,
    season: season,
    episode: episode,
    lastPlayedDate: played,
  );

  test('a movie and a show with the same id keep separate progress', () async {
    await repo.saveProgress(progress('movie', played: DateTime(2026, 1, 1)));
    await repo.saveProgress(
      progress('tv', season: 1, episode: 2, played: DateTime(2026, 1, 2)),
    );

    expect(await repo.getProgress('123', mediaType: 'movie'), isNotNull);
    expect(
      await repo.getProgress('123', mediaType: 'tv', season: 1, episode: 2),
      isNotNull,
    );

    final row = await repo.getContinueWatching();
    expect(row.map((p) => p.mediaType), unorderedEquals(['movie', 'tv']));
  });

  test('deleteProgressForMedia leaves the other type untouched', () async {
    await repo.saveProgress(progress('movie', played: DateTime(2026, 1, 1)));
    await repo.saveProgress(
      progress('tv', season: 1, episode: 1, played: DateTime(2026, 1, 2)),
    );

    await repo.deleteProgressForMedia('123', mediaType: 'movie');

    expect(await repo.getProgress('123', mediaType: 'movie'), isNull);
    expect(
      await repo.getProgress('123', mediaType: 'tv', season: 1, episode: 1),
      isNotNull,
    );
  });
}
