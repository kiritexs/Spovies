import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/watch_status_repository_impl.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/watch_status.dart';
import '../../domain/repositories/watch_status_repository.dart';
import 'watchlist_providers.dart';

// ─── Infrastructure ─────────────────────────────────────────────────────

final watchStatusRepositoryProvider = Provider<WatchStatusRepository>((ref) {
  return WatchStatusRepositoryImpl();
});

// ─── Data ───────────────────────────────────────────────────────────────

/// Status for a single media or episode. Parameters: mediaId, optional season, optional episode.
final mediaStatusProvider = FutureProvider.family<MediaStatus?, ({
  String mediaId,
  int? season,
  int? episode,
})>((ref, args) async {
  final repo = ref.watch(watchStatusRepositoryProvider);
  return repo.getStatus(
    args.mediaId,
    season: args.season,
    episode: args.episode,
  );
});

/// All status entries for a show (for episode list).
final mediaStatusesForShowProvider =
    FutureProvider.family<List<MediaStatus>, String>((ref, mediaId) async {
  final repo = ref.watch(watchStatusRepositoryProvider);
  return repo.getStatusesForMedia(mediaId);
});

/// All entries with a given status.
final entriesByStatusProvider =
    FutureProvider.family<List<MediaStatus>, WatchStatus>((ref, status) async {
  final repo = ref.watch(watchStatusRepositoryProvider);
  return repo.getEntriesByStatus(status);
});

// ─── Notifier: set status and invalidate ─────────────────────────────────

class WatchStatusNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> setStatus(MediaStatus entry, {MediaItem? mediaItem}) async {
    final repo = ref.read(watchStatusRepositoryProvider);
    await repo.saveStatus(entry);
    
    if (mediaItem != null) {
      final watchlist = ref.read(watchlistProvider.notifier);
      if (!watchlist.contains(mediaItem.tmdbId)) {
        watchlist.add(mediaItem);
      }
    }
    
    ref.invalidate(mediaStatusProvider);
    ref.invalidate(mediaStatusesForShowProvider);
    ref.invalidate(entriesByStatusProvider);
  }

  Future<void> deleteStatus(String mediaId, {int? season, int? episode}) async {
    final repo = ref.read(watchStatusRepositoryProvider);
    await repo.deleteStatus(mediaId, season: season, episode: episode);
    
    ref.invalidate(mediaStatusProvider);
    ref.invalidate(mediaStatusesForShowProvider);
    ref.invalidate(entriesByStatusProvider);
  }
}

final watchStatusNotifierProvider =
    NotifierProvider<WatchStatusNotifier, void>(WatchStatusNotifier.new);
