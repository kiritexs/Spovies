import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/watch_history_repository_impl.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/user_progress.dart';
import '../../domain/repositories/watch_history_repository.dart';
import 'details_providers.dart';

// ─── Infrastructure ─────────────────────────────────────────────────────

/// Watch history repository.
final watchHistoryRepositoryProvider = Provider<WatchHistoryRepository>((ref) {
  return WatchHistoryRepositoryImpl();
});

// ─── Data ───────────────────────────────────────────────────────────────

/// Continue Watching — one entry per media (most recent progress), including
/// completed episodes so UI can show "Continue with next" or card without button.
final continueWatchingProvider = FutureProvider<List<UserProgress>>((
  ref,
) async {
  final repo = ref.watch(watchHistoryRepositoryProvider);
  return repo.getContinueWatching();
});

/// Next episode (full details) for a TV progress. Returns null if not TV,
/// no season/episode, or no next episode. Pass a sentinel (e.g. mediaId: '')
/// to skip when you have no progress.
final nextEpisodeForProgressProvider =
    FutureProvider.family<Episode?, UserProgress>((ref, progress) async {
      if (progress.mediaId.isEmpty ||
          progress.mediaType != 'tv' ||
          progress.season == null ||
          progress.episode == null) {
        return null;
      }
      final tmdbId = int.tryParse(progress.mediaId);
      if (tmdbId == null) return null;
      // First read is fine to `ref.watch` because it runs synchronously
      // before any await — Riverpod registers the dependency normally.
      // The post-await reads further down switch to `ref.read` (see
      // comment there).
      final details = await ref.watch(tvDetailsProvider(tmdbId).future);
      final seasons = details.metadata.seasons;
      if (seasons.isEmpty) return null;
      final currentSeasonList = seasons
          .where((s) => s.seasonNumber == progress.season)
          .toList();
      final currentSeason = currentSeasonList.isNotEmpty
          ? currentSeasonList.first
          : null;
      final currentEpNum = progress.episode!;

      int? nextSeasonNum;
      int? nextEpNum;

      if (currentSeason != null && currentEpNum < currentSeason.episodeCount) {
        nextSeasonNum = progress.season!;
        nextEpNum = currentEpNum + 1;
      } else {
        final nextS = progress.season! + 1;
        final nextSeasonList = seasons
            .where((s) => s.seasonNumber == nextS)
            .toList();
        final nextSeason = nextSeasonList.isNotEmpty
            ? nextSeasonList.first
            : null;
        if (nextSeason != null && nextSeason.episodeCount > 0) {
          nextSeasonNum = nextS;
          nextEpNum = 1;
        }
      }

      if (nextSeasonNum != null && nextEpNum != null) {
        // `ref.read`, NOT `ref.watch`, after the await. Registering a
        // watch dependency after an async gap is a Riverpod anti-pattern
        // — the dependency tracking gets attached lazily, and on certain
        // re-evaluation paths the provider can run with a partial or
        // stale dependency graph. We only need a one-shot snapshot of the
        // next season's episode list to look up the episode by number;
        // there's no value in re-running this whole provider when the
        // upstream season-episodes provider invalidates.
        final episodes = await ref.read(
          tvSeasonEpisodesProvider((
            tvId: tmdbId,
            season: nextSeasonNum,
          )).future,
        );
        return episodes.firstWhere(
          (e) => e.episodeNumber == nextEpNum,
          orElse: () => Episode(
            seasonNumber: nextSeasonNum!,
            episodeNumber: nextEpNum!,
            name: 'Episode $nextEpNum',
          ),
        );
      }

      return null;
    });

/// Progress for a single episode (or a movie, with season/episode null).
final episodeProgressProvider =
    FutureProvider.family<
      UserProgress?,
      ({String mediaId, String mediaType, int? season, int? episode})
    >((ref, args) async {
      final repo = ref.watch(watchHistoryRepositoryProvider);
      return repo.getProgress(
        args.mediaId,
        mediaType: args.mediaType,
        season: args.season,
        episode: args.episode,
      );
    });
