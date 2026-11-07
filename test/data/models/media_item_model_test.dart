// Locks in how TMDB JSON maps to MediaItem, so refactors of the parsing
// code (typed casts, lint fixes) can't silently change what the app shows.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:spovies/data/models/media_item_model.dart';
import 'package:spovies/domain/entities/media_type.dart';

/// Fixtures go through a JSON round trip so they have the same runtime
/// types as real API responses (`List<dynamic>`, `Map<String, dynamic>`),
/// not the narrower types Dart infers for literals.
Map<String, dynamic> api(Map<String, Object?> fixture) =>
    jsonDecode(jsonEncode(fixture)) as Map<String, dynamic>;

void main() {
  group('fromTmdbJson (list results)', () {
    test('trending item uses its media_type', () {
      final item = MediaItemModel.fromTmdbJson(
        api({
          'id': 42,
          'media_type': 'tv',
          'name': 'A Show',
          'first_air_date': '2024-05-01',
          'genre_ids': [18, 35],
          'vote_average': 8,
          'vote_count': 100,
        }),
      ).toEntity();

      expect(item.type, MediaType.tv);
      expect(item.tmdbId, 42);
      expect(item.id, '42');
      expect(item.title, 'A Show');
      expect(item.releaseDate, '2024-05-01');
      expect(item.metadata.genreIds, [18, 35]);
      expect(item.metadata.rating, 8.0);
      expect(item.metadata.voteCount, 100);
    });

    test('falls back to defaultType, then movie', () {
      final tv = MediaItemModel.fromTmdbJson(
        api({'id': 1, 'name': 'x'}),
        defaultType: MediaType.tv,
      ).toEntity();
      final movie = MediaItemModel.fromTmdbJson(
        api({'id': 2, 'title': 'y'}),
      ).toEntity();

      expect(tv.type, MediaType.tv);
      expect(movie.type, MediaType.movie);
      expect(movie.metadata.genreIds, isEmpty);
      expect(movie.metadata.rating, isNull);
    });
  });

  group('fromTmdbDetailJson (movie)', () {
    Map<String, Object?> movie() => {
      'id': 7,
      'title': 'A Movie',
      'release_date': '2020-01-01',
      'imdb_id': 'tt0000007',
      'runtime': 118,
      'genres': [
        {'id': 28, 'name': 'Action'},
        {'id': 12, 'name': 'Adventure'},
      ],
      'videos': {
        'results': [
          {'type': 'Teaser', 'site': 'YouTube', 'key': 'teaser'},
          {'type': 'Trailer', 'site': 'Vimeo', 'key': 'vimeo'},
          {'type': 'Trailer', 'site': 'YouTube', 'key': 'trailer'},
        ],
      },
      'release_dates': {
        'results': [
          {
            'iso_3166_1': 'GB',
            'release_dates': [
              {'certification': '15'},
            ],
          },
          {
            'iso_3166_1': 'US',
            'release_dates': [
              {'certification': 'PG-13'},
            ],
          },
        ],
      },
      'credits': {
        'cast': [
          for (var i = 0; i < 25; i++)
            {'id': i, 'name': 'Actor $i', 'character': 'Role $i'},
        ],
      },
    };

    test('maps fields, picks the YouTube trailer and US certification', () {
      final item = MediaItemModel.fromTmdbDetailJson(api(movie())).toEntity();

      expect(item.type, MediaType.movie);
      expect(item.title, 'A Movie');
      expect(item.metadata.imdbId, 'tt0000007');
      expect(item.metadata.runtime, 118);
      expect(item.metadata.genres, ['Action', 'Adventure']);
      expect(item.metadata.genreIds, [28, 12]);
      expect(item.metadata.trailerKey, 'trailer');
      expect(item.metadata.certification, 'PG-13');
      expect(item.metadata.cast, hasLength(20)); // top 20 only
      expect(item.metadata.cast.first.character, 'Role 0');
    });

    test('no YouTube trailer falls back to the first video', () {
      final json = movie()
        ..['videos'] = {
          'results': [
            {'type': 'Clip', 'site': 'YouTube', 'key': 'clip'},
          ],
        };
      final item = MediaItemModel.fromTmdbDetailJson(api(json)).toEntity();
      expect(item.metadata.trailerKey, 'clip');
    });

    test('a video hosted outside YouTube is never used', () {
      final json = movie()
        ..['videos'] = {
          'results': [
            {'type': 'Trailer', 'site': 'Vimeo', 'key': 'vimeo'},
          ],
        };
      final item = MediaItemModel.fromTmdbDetailJson(api(json)).toEntity();
      expect(item.metadata.trailerKey, isNull);
    });

    test('empty US certification becomes null', () {
      final json = movie()
        ..['release_dates'] = {
          'results': [
            {
              'iso_3166_1': 'US',
              'release_dates': [
                {'certification': ''},
              ],
            },
          ],
        };
      final item = MediaItemModel.fromTmdbDetailJson(api(json)).toEntity();
      expect(item.metadata.certification, isNull);
    });

    test('tolerates missing optional sections', () {
      final item = MediaItemModel.fromTmdbDetailJson(
        api({'id': 8, 'title': 'Bare'}),
      ).toEntity();
      expect(item.metadata.genres, isEmpty);
      expect(item.metadata.trailerKey, isNull);
      expect(item.metadata.certification, isNull);
      expect(item.metadata.cast, isEmpty);
    });
  });

  group('fromTmdbTvDetailJson', () {
    test('maps seasons, aggregate cast roles and the IMDb id', () {
      final item = MediaItemModel.fromTmdbTvDetailJson(
        api({
          'id': 9,
          'name': 'A Show',
          'first_air_date': '2019-09-09',
          'number_of_seasons': 2,
          'external_ids': {'imdb_id': 'tt0000009'},
          'genres': [
            {'id': 18, 'name': 'Drama'},
          ],
          'seasons': [
            {'season_number': 0, 'episode_count': 3, 'name': 'Specials'},
            {'season_number': 1, 'episode_count': 10, 'name': 'Season 1'},
            {'season_number': 2, 'episode_count': 8},
          ],
          'aggregate_credits': {
            'cast': [
              {
                'id': 1,
                'name': 'Lead',
                'roles': [
                  {'character': 'Hero'},
                ],
              },
              {'id': 2, 'name': 'Guest', 'roles': <dynamic>[]},
            ],
          },
          'credits': {
            'cast': [
              {'id': 99, 'name': 'Ignored', 'character': 'x'},
            ],
          },
        }),
      ).toEntity();

      expect(item.type, MediaType.tv);
      expect(item.title, 'A Show');
      expect(item.releaseDate, '2019-09-09');
      expect(item.metadata.imdbId, 'tt0000009');
      expect(item.metadata.numberOfSeasons, 2);
      expect(item.metadata.genres, ['Drama']);
      // Specials (season 0) are skipped.
      expect(item.metadata.seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(item.metadata.seasons.first.episodeCount, 10);
      // aggregate_credits wins over credits; character comes from roles.
      expect(item.metadata.cast.map((c) => c.name), ['Lead', 'Guest']);
      expect(item.metadata.cast.first.character, 'Hero');
      expect(item.metadata.cast.last.character, isNull);
    });

    test('falls back to credits when there are no aggregate credits', () {
      final item = MediaItemModel.fromTmdbTvDetailJson(
        api({
          'id': 10,
          'name': 'Old Show',
          'credits': {
            'cast': [
              {'id': 5, 'name': 'Actor', 'character': 'Self'},
            ],
          },
        }),
      ).toEntity();

      expect(item.metadata.cast.single.character, 'Self');
      expect(item.metadata.imdbId, isNull);
      expect(item.metadata.seasons, isEmpty);
    });
  });
}
