import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/watch_history_repository_impl.dart';
import '../../domain/entities/user_progress.dart';
import '../../domain/repositories/watch_history_repository.dart';

// ─── Infrastructure ─────────────────────────────────────────────────────

/// Watch history repository.
final watchHistoryRepositoryProvider = Provider<WatchHistoryRepository>((ref) {
  return WatchHistoryRepositoryImpl();
});

// ─── Data ───────────────────────────────────────────────────────────────

/// Continue Watching list — items watched < 90%, sorted by last played.
final continueWatchingProvider = FutureProvider<List<UserProgress>>((
  ref,
) async {
  final repo = ref.watch(watchHistoryRepositoryProvider);
  return repo.getContinueWatching();
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
