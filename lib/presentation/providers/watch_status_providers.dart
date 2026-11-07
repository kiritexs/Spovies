import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/watch_status_repository_impl.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/user_progress.dart';
import '../../domain/entities/watch_status.dart';
import '../../domain/repositories/watch_status_repository.dart';
import 'watch_history_providers.dart';
import 'watchlist_providers.dart';

// ─── Infrastructure ─────────────────────────────────────────────────────

final watchStatusRepositoryProvider = Provider<WatchStatusRepository>((ref) {
  return WatchStatusRepositoryImpl();
});

// ─── Data ───────────────────────────────────────────────────────────────

/// Status for a single title or episode.
final mediaStatusProvider =
    FutureProvider.family<
      MediaStatus?,
      ({String mediaId, String mediaType, int? season, int? episode})
    >((ref, args) async {
      final repo = ref.watch(watchStatusRepositoryProvider);
      return repo.getStatus(
        args.mediaId,
        mediaType: args.mediaType,
        season: args.season,
        episode: args.episode,
      );
    });

/// All status entries for a show (for episode list).
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

/// Every title-level status (movie or show, not episodes). Drives the
/// Library, which lists saved titles plus any title that has a status.
final titleStatusesProvider = FutureProvider<List<MediaStatus>>((ref) async {
  final repo = ref.watch(watchStatusRepositoryProvider);
  return repo.getAllTitleStatuses();
});

// ─── Notifier: set status and invalidate ─────────────────────────────────

/// Everything [WatchStatusNotifier.removeTitle] deleted for one title, so
/// Undo can put it back exactly.
typedef RemovedTitle = ({
  MediaItem? savedItem,
  List<MediaStatus> statuses,
  List<UserProgress> progress,
});

class WatchStatusNotifier extends Notifier<void> {
  @override
  void build() {}

  void _invalidateStatuses() {
    ref.invalidate(mediaStatusProvider);
    ref.invalidate(mediaStatusesForShowProvider);
    ref.invalidate(entriesByStatusProvider);
    ref.invalidate(titleStatusesProvider);
  }

  /// Save a status. Pass [mediaItem] to also save the title to the Library,
  /// so every tracked title has the metadata needed to show its card.
  Future<void> setStatus(MediaStatus entry, {MediaItem? mediaItem}) async {
    final repo = ref.read(watchStatusRepositoryProvider);
    await repo.saveStatus(entry);

    if (mediaItem != null) {
      final watchlist = ref.read(watchlistProvider.notifier);
      if (!watchlist.contains(mediaItem)) {
        watchlist.add(mediaItem);
      }
    }
    _invalidateStatuses();
  }

  Future<void> deleteStatus(
    String mediaId, {
    required String mediaType,
    int? season,
    int? episode,
  }) async {
    final repo = ref.read(watchStatusRepositoryProvider);
    await repo.deleteStatus(
      mediaId,
      mediaType: mediaType,
      season: season,
      episode: episode,
    );
    _invalidateStatuses();
  }

  /// Remove all statuses for a title (show + all episodes) and its watch
  /// progress, so it also leaves the "Continue Watching" row.
  Future<void> deleteAllStatusesForMedia(
    String mediaId, {
    required String mediaType,
  }) async {
    final statusRepo = ref.read(watchStatusRepositoryProvider);
    final historyRepo = ref.read(watchHistoryRepositoryProvider);

    await statusRepo.deleteAllStatusesForMedia(mediaId, mediaType: mediaType);
    await historyRepo.deleteProgressForMedia(mediaId, mediaType: mediaType);

    _invalidateStatuses();
    ref.invalidate(continueWatchingProvider);
    ref.invalidate(episodeProgressProvider);
  }

  /// Remove a title from the Library now: its saved item, every status
  /// (title and episodes) and its watch progress. Returns what was removed
  /// so [restoreTitle] can undo it. Deleting at once (rather than when an
  /// Undo snackbar closes) means nothing set on the title afterwards can
  /// be wiped by a late delete.
  Future<RemovedTitle> removeTitle(
    String mediaId, {
    required String mediaType,
    MediaItem? item,
  }) async {
    final statusRepo = ref.read(watchStatusRepositoryProvider);
    final historyRepo = ref.read(watchHistoryRepositoryProvider);
    final watchlist = ref.read(watchlistProvider.notifier);

    final saved = item != null && watchlist.contains(item) ? item : null;
    final removed = (
      savedItem: saved,
      statuses: await statusRepo.getStatusesForMedia(
        mediaId,
        mediaType: mediaType,
      ),
      progress: await historyRepo.getProgressForMedia(
        mediaId,
        mediaType: mediaType,
      ),
    );

    if (saved != null) watchlist.remove(saved);
    await deleteAllStatusesForMedia(mediaId, mediaType: mediaType);
    return removed;
  }

  /// Put back what [removeTitle] removed.
  Future<void> restoreTitle(RemovedTitle removed) async {
    final statusRepo = ref.read(watchStatusRepositoryProvider);
    final historyRepo = ref.read(watchHistoryRepositoryProvider);

    final item = removed.savedItem;
    if (item != null) ref.read(watchlistProvider.notifier).add(item);
    for (final status in removed.statuses) {
      await statusRepo.saveStatus(status);
    }
    for (final progress in removed.progress) {
      await historyRepo.saveProgress(progress);
    }

    _invalidateStatuses();
    ref.invalidate(continueWatchingProvider);
    ref.invalidate(episodeProgressProvider);
  }

  /// Remove every status entry. Used when the whole Library is cleared, so
  /// no status is left behind without a visible title.
  Future<void> clearAll() async {
    await ref.read(watchStatusRepositoryProvider).clearAll();
    _invalidateStatuses();
  }
}

final watchStatusNotifierProvider = NotifierProvider<WatchStatusNotifier, void>(
  WatchStatusNotifier.new,
);
