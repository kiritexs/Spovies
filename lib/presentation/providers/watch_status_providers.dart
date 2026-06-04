import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/watch_status_repository_impl.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/watch_status.dart';
import '../../domain/repositories/watch_status_repository.dart';
import 'watch_history_providers.dart';
import 'watchlist_providers.dart';

// ─── Infrastructure ─────────────────────────────────────────────────────

final watchStatusRepositoryProvider = Provider<WatchStatusRepository>((ref) {
  return WatchStatusRepositoryImpl();
});

// ─── Data ───────────────────────────────────────────────────────────────

/// Status for a single media or episode. Parameters: mediaId, optional season, optional episode.
final mediaStatusProvider =
    FutureProvider.family<
      MediaStatus?,
      ({String mediaId, int? season, int? episode})
    >((ref, args) async {
      final repo = ref.watch(watchStatusRepositoryProvider);
      return repo.getStatus(
        args.mediaId,
        season: args.season,
        episode: args.episode,
      );
    });

/// All status entries for a show (for episode list).
///
/// The family arg includes `mediaType` because TMDB uses independent id
/// spaces for movies and TV shows — see [WatchStatusRepository.getStatusesForMedia].
final mediaStatusesForShowProvider =
    FutureProvider.family<
      List<MediaStatus>,
      ({String mediaId, String mediaType})
    >((ref, args) async {
      final repo = ref.watch(watchStatusRepositoryProvider);
      return repo.getStatusesForMedia(args.mediaId, mediaType: args.mediaType);
    });

/// All entries with a given status.
final entriesByStatusProvider =
    FutureProvider.family<List<MediaStatus>, WatchStatus>((ref, status) async {
      final repo = ref.watch(watchStatusRepositoryProvider);
      return repo.getEntriesByStatus(status);
    });

/// Media-level only (season == null, episode == null). Use for library filter.
final libraryEntriesByStatusProvider =
    FutureProvider.family<List<MediaStatus>, WatchStatus>((ref, status) async {
      final repo = ref.watch(watchStatusRepositoryProvider);
      final all = await repo.getEntriesByStatus(status);
      return all.where((e) => e.season == null && e.episode == null).toList();
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
    ref.invalidate(libraryEntriesByStatusProvider);
  }

  Future<void> deleteStatus(String mediaId, {int? season, int? episode}) async {
    final repo = ref.read(watchStatusRepositoryProvider);
    await repo.deleteStatus(mediaId, season: season, episode: episode);

    ref.invalidate(mediaStatusProvider);
    ref.invalidate(mediaStatusesForShowProvider);
    ref.invalidate(entriesByStatusProvider);
    ref.invalidate(libraryEntriesByStatusProvider);
  }

  /// Remove all statuses for a media (show + all episodes). Use when removing
  /// from library.
  ///
  /// Also deletes any progress entries for the same media so the title stops
  /// appearing in the "Continue Watching" row, then invalidates the related
  /// list providers.
  Future<void> deleteAllStatusesForMedia(
    String mediaId, {
    required String mediaType,
  }) async {
    final statusRepo = ref.read(watchStatusRepositoryProvider);
    final historyRepo = ref.read(watchHistoryRepositoryProvider);

    await statusRepo.deleteAllStatusesForMedia(mediaId, mediaType: mediaType);
    await historyRepo.deleteProgressForMedia(mediaId);

    ref.invalidate(mediaStatusProvider);
    ref.invalidate(mediaStatusesForShowProvider);
    ref.invalidate(entriesByStatusProvider);
    ref.invalidate(libraryEntriesByStatusProvider);
    // Continue Watching reads from watchHistoryBox; refresh it now so the
    // just-removed title disappears from the Home row.
    ref.invalidate(continueWatchingProvider);
    ref.invalidate(episodeProgressProvider);
  }
}

final watchStatusNotifierProvider = NotifierProvider<WatchStatusNotifier, void>(
  WatchStatusNotifier.new,
);
