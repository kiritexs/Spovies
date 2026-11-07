// Details shows what it already knows while loading, and if the full
// details fail it keeps that content with a Retry banner (not a blank
// error page). Retry re-runs the request.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:spovies/data/datasources/local/hive_service.dart';
import 'package:spovies/domain/entities/media_item.dart';
import 'package:spovies/domain/entities/media_metadata.dart';
import 'package:spovies/domain/entities/media_type.dart';
import 'package:spovies/presentation/providers/details_providers.dart';
import 'package:spovies/presentation/screens/details/details_screen.dart';

void main() {
  // In-memory boxes: no disk IO inside the fake-async test zone.
  setUpAll(() async {
    Future<Box<Map<dynamic, dynamic>>> mem(String name) =>
        Hive.openBox<Map<dynamic, dynamic>>(name, bytes: Uint8List(0));
    HiveService.pluginsBox = await mem(HiveService.pluginsBoxName);
    HiveService.watchHistoryBox = await mem(HiveService.watchHistoryBoxName);
    HiveService.watchlistBox = await mem(HiveService.watchlistBoxName);
    HiveService.listStatusBox = await mem(HiveService.listStatusBoxName);
    HiveService.tmdbCacheBox = await mem(HiveService.tmdbCacheBoxName);
    HiveService.settingsBox = await Hive.openBox(
      HiveService.settingsBoxName,
      bytes: Uint8List(0),
    );
  });

  tearDownAll(Hive.close);

  const listItem = MediaItem(
    id: 'movie_7',
    tmdbId: 7,
    type: MediaType.movie,
    title: 'Partial Title',
    overview: 'Overview from the list result.',
    metadata: MediaMetadata(rating: 7.1),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('failed load keeps partial content and Retry recovers', (
    tester,
  ) async {
    var calls = 0;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        movieDetailsProvider.overrideWith((ref, id) async {
          calls++;
          if (calls == 1) throw Exception('offline');
          return listItem.copyWith(title: 'Full Title');
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DetailsScreen(media: listItem)),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Partial Title'), findsWidgets);
    expect(find.text('Couldn\'t load the full details.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await settle(tester);

    expect(calls, 2);
    expect(find.text('Full Title'), findsWidgets);
    expect(find.text('Couldn\'t load the full details.'), findsNothing);
  });
}
