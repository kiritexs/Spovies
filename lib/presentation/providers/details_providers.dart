import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/episode.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_type.dart';
import 'media_providers.dart';

/// Fetches movie/TV details with all appended data (credits, videos, etc.).
///
/// Automatically routes to the correct TMDB endpoint based on [MediaItem.type].
final movieDetailsProvider = FutureProvider.family<MediaItem, int>((
  ref,
  tmdbId,
) async {
  final repo = ref.watch(mediaRepositoryProvider);
  return repo.getMovieDetails(tmdbId);
});

/// Fetches TV show details.
final tvDetailsProvider = FutureProvider.family<MediaItem, int>((
  ref,
  tmdbId,
) async {
  final repo = ref.watch(mediaRepositoryProvider);
  return repo.getTvDetails(tmdbId);
});

/// Helper that picks the right details provider based on media type.
final mediaDetailsProvider =
    FutureProvider.family<MediaItem, ({int tmdbId, MediaType type})>((
      ref,
      args,
    ) async {
      if (args.type == MediaType.tv) {
        return ref.watch(tvDetailsProvider(args.tmdbId).future);
      }
      return ref.watch(movieDetailsProvider(args.tmdbId).future);
    });

/// Fetches all episodes for a given TV season.
final tvSeasonEpisodesProvider =
    FutureProvider.family<List<Episode>, ({int tvId, int season})>((
      ref,
      args,
    ) async {
      final api = ref.watch(tmdbApiProvider);
      return api.getTvSeasonEpisodes(args.tvId, args.season);
    });
