// Regression tests for WatchStatusRepositoryImpl — locks in the mediaType
// filter so a TMDB id collision between a movie and a TV show can never
// silently cross-contaminate again.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:spovies/data/datasources/local/hive_service.dart';
import 'package:spovies/data/repositories/watch_status_repository_impl.dart';
import 'package:spovies/domain/entities/watch_status.dart';

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('spovies_status_test_');
    Hive.init(tmpDir.path);
    // Open the box under the same name HiveService uses, so the repo's
    // static accessor finds it. Avoids pulling path_provider into tests.
    HiveService.listStatusBox = await Hive.openBox<Map>(
      HiveService.listStatusBoxName,
    );
  });

  tearDownAll(() async {
    await Hive.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  late WatchStatusRepositoryImpl repo;
  setUp(() async {
    repo = WatchStatusRepositoryImpl();
    await HiveService.listStatusBox.clear();
  });

  MediaStatus entry(
    String mediaId, {
    required String mediaType,
    WatchStatus status = WatchStatus.watching,
    int? season,
    int? episode,
  }) => MediaStatus(
    mediaId: mediaId,
    mediaType: mediaType,
    status: status,
    season: season,
    episode: episode,
    updatedAt: DateTime(2025),
  );

  test('getStatusesForMedia filters by both mediaId and mediaType', () async {
    await repo.saveStatus(entry('123', mediaType: 'movie'));
    await repo.saveStatus(entry('123', mediaType: 'tv', season: 1, episode: 1));

    final movies = await repo.getStatusesForMedia('123', mediaType: 'movie');
    final shows = await repo.getStatusesForMedia('123', mediaType: 'tv');

    expect(movies, hasLength(1));
    expect(movies.single.mediaType, 'movie');
    expect(shows, hasLength(1));
    expect(shows.single.mediaType, 'tv');
  });

  test(
    'deleteAllStatusesForMedia only touches the matching mediaType',
    () async {
      await repo.saveStatus(entry('123', mediaType: 'movie'));
      await repo.saveStatus(
        entry('123', mediaType: 'tv', season: 1, episode: 1),
      );
      await repo.saveStatus(
        entry('123', mediaType: 'tv', season: 1, episode: 2),
      );

      await repo.deleteAllStatusesForMedia('123', mediaType: 'movie');

      // Movie row is gone…
      final movies = await repo.getStatusesForMedia('123', mediaType: 'movie');
      expect(movies, isEmpty);
      // …but both TV rows survive.
      final shows = await repo.getStatusesForMedia('123', mediaType: 'tv');
      expect(shows, hasLength(2));
    },
  );
}
