// Library screen: lists saved titles and titles that only have a status,
// filters by status, and removes with Undo (deleting only once the
// snackbar closes without it).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:spovies/data/datasources/local/hive_service.dart';
import 'package:spovies/data/datasources/local/storage_keys.dart';
import 'package:spovies/domain/entities/media_item.dart';
import 'package:spovies/domain/entities/media_type.dart';
import 'package:spovies/domain/entities/watch_status.dart';
import 'package:spovies/presentation/providers/details_providers.dart';
import 'package:spovies/presentation/providers/watchlist_providers.dart';
import 'package:spovies/presentation/screens/watchlist/watchlist_screen.dart';

void main() {
  // In-memory boxes: no disk IO, which would never complete inside
  // testWidgets' fake-async zone.
  setUpAll(() async {
    HiveService.watchlistBox = await Hive.openBox<Map<dynamic, dynamic>>(
      HiveService.watchlistBoxName,
      bytes: Uint8List(0),
    );
    HiveService.listStatusBox = await Hive.openBox<Map<dynamic, dynamic>>(
      HiveService.listStatusBoxName,
      bytes: Uint8List(0),
    );
    HiveService.watchHistoryBox = await Hive.openBox<Map<dynamic, dynamic>>(
      HiveService.watchHistoryBoxName,
      bytes: Uint8List(0),
    );
  });

  tearDownAll(Hive.close);

  setUp(() async {
    await HiveService.watchlistBox.clear();
    await HiveService.listStatusBox.clear();
    await HiveService.watchHistoryBox.clear();
  });

  const savedMovie = MediaItem(
    id: 'movie_1',
    tmdbId: 1,
    type: MediaType.movie,
    title: 'Saved Movie',
  );
  const statusOnlyShow = MediaItem(
    id: 'tv_2',
    tmdbId: 2,
    type: MediaType.tv,
    title: 'Status-only Show',
  );

  Future<void> putStatus(String type, int id, WatchStatus status) =>
      HiveService.listStatusBox.put(StorageKeys.status(type, '$id'), {
        'mediaId': '$id',
        'mediaType': type,
        'status': status.value,
        'updatedAt': DateTime(2026).toIso8601String(),
      });

  // Bounded settle: an endless animation (spinner, shimmer) would make
  // pumpAndSettle spin until it times out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpLibrary(WidgetTester tester) async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        // Status-only titles load their metadata from TMDB.
        mediaDetailsProvider.overrideWith((ref, args) async => statusOnlyShow),
      ],
    );
    addTearDown(container.dispose);
    container.read(watchlistProvider.notifier).add(savedMovie);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WatchlistScreen()),
      ),
    );
    await settle(tester);
  }

  testWidgets('All lists saved titles and status-only titles', (tester) async {
    await putStatus('movie', 1, WatchStatus.completed);
    await putStatus('tv', 2, WatchStatus.dropped);
    await pumpLibrary(tester);

    expect(find.text('Saved Movie'), findsOneWidget);
    expect(find.text('Status-only Show'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Dropped'));
    await settle(tester);
    expect(find.text('Saved Movie'), findsNothing);
    expect(find.text('Status-only Show'), findsOneWidget);
  });

  testWidgets('Undo restores a removed title', (tester) async {
    await putStatus('movie', 1, WatchStatus.completed);
    await pumpLibrary(tester);

    await tester.tap(find.byTooltip('Remove from Library'));
    await tester.pump();
    expect(find.text('Saved Movie'), findsNothing);
    await settle(tester); // let the snackbar finish sliding in

    await tester.tap(find.text('Undo'));
    await settle(tester);

    expect(find.text('Saved Movie'), findsOneWidget);
    expect(HiveService.watchlistBox.length, 1);
    expect(HiveService.listStatusBox.length, 1);
  });

  testWidgets('without Undo the title and its status are deleted', (
    tester,
  ) async {
    await putStatus('movie', 1, WatchStatus.completed);
    await pumpLibrary(tester);

    await tester.tap(find.byTooltip('Remove from Library'));
    await settle(tester); // the 5 s timer starts once it has slid in
    expect(HiveService.watchlistBox.length, 1); // not deleted yet
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);

    expect(find.text('Saved Movie'), findsNothing);
    expect(HiveService.watchlistBox.length, 0);
    expect(HiveService.listStatusBox.length, 0);
  });
}
