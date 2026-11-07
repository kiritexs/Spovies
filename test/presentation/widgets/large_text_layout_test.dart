// Cards must not overflow at 1.3x text size on a phone-width screen.
// Overflows are reported as exceptions in widget tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spovies/domain/entities/media_item.dart';
import 'package:spovies/domain/entities/media_metadata.dart';
import 'package:spovies/domain/entities/media_type.dart';
import 'package:spovies/presentation/widgets/continue_watching_card.dart';
import 'package:spovies/presentation/widgets/hero_card.dart';
import 'package:spovies/presentation/widgets/media_card.dart';

Widget _phone(Widget child) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(
      size: Size(375, 812),
      textScaler: TextScaler.linear(1.3),
    ),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

const _item = MediaItem(
  id: 'movie_1',
  tmdbId: 1,
  type: MediaType.movie,
  title: 'A Very Long Movie Title That Keeps Going And Going',
  metadata: MediaMetadata(rating: 8.4),
);

void main() {
  testWidgets('ContinueWatchingCard fits at 1.3x', (tester) async {
    await tester.pumpWidget(
      _phone(
        const SizedBox(
          width: 343,
          child: ContinueWatchingCard(
            title: 'A Very Long Show Title That Keeps Going',
            remainingTime: '1h 42m remaining',
            progress: 0.4,
            episodeLabel: 'S12 E104',
            onContinueTap: _noop,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('HeroCard metadata fits at 1.3x', (tester) async {
    await tester.pumpWidget(
      _phone(
        HeroCard(
          movie: _item,
          genreText: 'Science Fiction • Adventure • Animation',
          onTap: _noop,
          onAddTap: _noop,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('View Details'), findsOneWidget);
    expect(find.byTooltip('Add to Library'), findsOneWidget);
  });

  testWidgets('MediaCard fills a wide grid cell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 220,
            height: 420,
            child: MediaCard(movie: _item, onTap: _noop),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // Poster is as wide as the cell, not the 140px row width.
    final poster = tester.getSize(find.byType(ClipRRect).first);
    expect(poster.width, 220);
  });
}

void _noop() {}
