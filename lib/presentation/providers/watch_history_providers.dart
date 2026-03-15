import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/watch_history_repository_impl.dart';
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

/// Next episode (season, episode) for a TV progress. Returns null if not TV,
/// no season/episode, or no next episode. Pass a sentinel (e.g. mediaId: '')
/// to skip when you have no progress.
final nextEpisodeForProgressProvider =
    FutureProvider.family<({int season, int episode})?, UserProgress>((
  ref,
  progress,
) async {
  if (progress.mediaId.isEmpty || progress.mediaType != 'tv' ||
      progress.season == null || progress.episode == null) return null;
  final tmdbId = int.tryParse(progress.mediaId);
  if (tmdbId == null) return null;
  final details = await ref.watch(tvDetailsProvider(tmdbId).future);
  final seasons = details.metadata.seasons;
  if (seasons.isEmpty) return null;
  final currentSeasonList =
      seasons.where((s) => s.seasonNumber == progress.season).toList();
  final currentSeason = currentSeasonList.isNotEmpty ? currentSeasonList.first : null;
  final currentEp = progress.episode!;
  if (currentSeason != null && currentEp < currentSeason.episodeCount) {
    return (season: progress.season!, episode: currentEp + 1);
  }
  final nextSeasonNum = progress.season! + 1;
  final nextSeasonList =
      seasons.where((s) => s.seasonNumber == nextSeasonNum).toList();
  final nextSeason = nextSeasonList.isNotEmpty ? nextSeasonList.first : null;
  if (nextSeason != null && nextSeason.episodeCount > 0) {
    return (season: nextSeasonNum, episode: 1);
  }
  return null;
});

/// Progress for a single episode.
final episodeProgressProvider = FutureProvider.family<UserProgress?, ({
  String mediaId,
  int? season,
  int? episode,
})>((ref, args) async {
  final repo = ref.watch(watchHistoryRepositoryProvider);
  return repo.getProgress(
    args.mediaId,
    season: args.season,
    episode: args.episode,
  );
});
