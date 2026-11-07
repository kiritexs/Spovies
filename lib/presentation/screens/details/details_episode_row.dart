part of 'details_screen.dart';

// ─── Episode Row ──────────────────────────────────────────────────────────────

class _EpisodeRow extends ConsumerWidget {
  final String mediaId;

  /// The show this episode belongs to. Setting an episode status saves it to
  /// the Library so the tracked title always has a visible card.
  final MediaItem show;
  final Episode episode;
  final List<PluginManifest> plugins;
  final VoidCallback? onPlay;

  const _EpisodeRow({
    required this.mediaId,
    required this.show,
    required this.episode,
    required this.plugins,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stillUrl = buildImageUrl(episode.stillPath, AppConfig.backdropSmall);

    final statusAsync = ref.watch(
      mediaStatusProvider((
        mediaId: mediaId,
        mediaType: 'tv',
        season: episode.seasonNumber,
        episode: episode.episodeNumber,
      )),
    );

    final progressAsync = ref.watch(
      episodeProgressProvider((
        mediaId: mediaId,
        mediaType: 'tv',
        season: episode.seasonNumber,
        episode: episode.episodeNumber,
      )),
    );

    return progressAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ShimmerPlaceholder(
              width: 140,
              height: 120,
              borderRadius: BorderRadius.circular(20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ShimmerPlaceholder(height: 14, width: 60),
                  const SizedBox(height: 8),
                  const ShimmerPlaceholder(height: 16, width: 120),
                ],
              ),
            ),
          ],
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (progress) {
        final status = statusAsync.value?.status;
        final bool isWatched =
            status == WatchStatus.completed ||
            (progress != null && progress.percentage >= 95);
        final bool isWatching =
            !isWatched &&
            (status == WatchStatus.watching ||
                (progress != null && progress.percentage > 0));

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: InkWell(
            onTap: () {
              if (!kPluginsEnabled) {
                // Don't mark the episode as Watching: nothing will play.
                showPlaybackUnavailableSnack(context);
                return;
              }
              if (onPlay != null) {
                if (!isWatched && status != WatchStatus.watching) {
                  ref
                      .read(watchStatusNotifierProvider.notifier)
                      .setStatus(
                        MediaStatus(
                          mediaId: mediaId,
                          mediaType: 'tv',
                          status: WatchStatus.watching,
                          season: episode.seasonNumber,
                          episode: episode.episodeNumber,
                          updatedAt: DateTime.now(),
                        ),
                        mediaItem: show,
                      );
                }
                onPlay!();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('No playback source configured'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.surfaceDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusBase,
                      ),
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isWatching
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : AppColors.glassBorder,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    isWatching
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.03),
                    Colors.white.withValues(alpha: 0.01),
                  ],
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- 1. Thumbnail + Play Overlay ---
                    Stack(
                      children: [
                        SizedBox(
                          width: 140,
                          height: 120,
                          child: stillUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: stillUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) =>
                                      const ShimmerPlaceholder(),
                                  errorWidget: (_, _, _) =>
                                      Container(color: AppColors.surfaceDark),
                                )
                              : Container(
                                  color: AppColors.surfaceDark,
                                  child: const Icon(
                                    Icons.tv_rounded,
                                    color: Colors.white24,
                                    size: 32,
                                  ),
                                ),
                        ),
                        // Watched Overlay
                        if (isWatched)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.primaryOnDark,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                        // Simple Play hint if unwatched
                        if (!isWatched)
                          Positioned.fill(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black26,
                                  border: Border.all(
                                    color: Colors.white30,
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  isWatching
                                      ? Icons.play_arrow_rounded
                                      : Icons.play_arrow_outlined,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        // Progress Bar (Slim at the bottom)
                        if (isWatching)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 3,
                              color: Colors.white10,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor:
                                      ((progress?.percentage ?? 0) / 100).clamp(
                                        0.0,
                                        1.0,
                                      ),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                    // --- 2. Content Info ---
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(
                                  episode.label,
                                  style: AppTextStyles.tag.copyWith(
                                    color: isWatched
                                        ? AppColors.textMuted
                                        : AppColors.primaryOnDark,
                                    letterSpacing: 1,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (isWatching) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${progress?.percentage.toInt()}%',
                                      style: AppTextStyles.tag.copyWith(
                                        color: AppColors.primaryOnDark,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                _EpisodeStatusPicker(
                                  mediaId: mediaId,
                                  show: show,
                                  episode: episode,
                                  currentStatus: status,
                                  isWatchedByDefault:
                                      isWatched &&
                                      status != WatchStatus.completed,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              episode.name,
                              style: AppTextStyles.cardTitle.copyWith(
                                fontSize: 15,
                                color: isWatched
                                    ? Colors.white70
                                    : Colors.white,
                                fontWeight: isWatching
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (episode.overview != null &&
                                episode.overview!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                episode.overview!,
                                style: AppTextStyles.body.copyWith(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EpisodeStatusPicker extends ConsumerWidget {
  final String mediaId;
  final MediaItem show;
  final Episode episode;
  final WatchStatus? currentStatus;
  final bool isWatchedByDefault;

  const _EpisodeStatusPicker({
    required this.mediaId,
    required this.show,
    required this.episode,
    this.currentStatus,
    this.isWatchedByDefault = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Each value is wrapped in a record: PopupMenuButton reports a null value
    // as "cancelled" (onCanceled), so a bare `null` meaning "reset" would
    // never reach onSelected.
    return PopupMenuButton<({WatchStatus? status})>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: (currentStatus != null || isWatchedByDefault)
            ? AppColors.primaryOnDark
            : AppColors.textMuted,
      ),
      tooltip: 'Change status (always editable)',
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
      ),
      color: AppColors.surfaceDark,
      onSelected: (choice) {
        final status = choice.status;
        final notifier = ref.read(watchStatusNotifierProvider.notifier);
        if (status == null) {
          unawaited(
            notifier.deleteStatus(
              mediaId,
              mediaType: 'tv',
              season: episode.seasonNumber,
              episode: episode.episodeNumber,
            ),
          );
          return;
        }
        unawaited(
          notifier.setStatus(
            MediaStatus(
              mediaId: mediaId,
              mediaType: 'tv',
              status: status,
              season: episode.seasonNumber,
              episode: episode.episodeNumber,
              updatedAt: DateTime.now(),
            ),
            mediaItem: show,
          ),
        );
      },
      itemBuilder: (context) =>
          [
                null, // Clear status
                WatchStatus.watching,
                WatchStatus.completed,
                WatchStatus.planToWatch,
                WatchStatus.onHold,
                WatchStatus.dropped,
              ]
              .map(
                (s) => PopupMenuItem<({WatchStatus? status})>(
                  value: (status: s),
                  child: Row(
                    children: [
                      Icon(
                        s?.icon ?? Icons.delete_outline_rounded,
                        size: 18,
                        color: s == currentStatus
                            ? AppColors.primaryOnDark
                            : Colors.white70,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        s == null
                            ? 'Reset Status'
                            : s == WatchStatus.completed
                            ? 'Mark Watched'
                            : s.displayName,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: s == currentStatus
                              ? AppColors.primaryOnDark
                              : Colors.white,
                        ),
                      ),
                      const Spacer(),
                      if (s == currentStatus && s != null)
                        const Icon(
                          Icons.check,
                          color: AppColors.primaryOnDark,
                          size: 16,
                        ),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }
}
