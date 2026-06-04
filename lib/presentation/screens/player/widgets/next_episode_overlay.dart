import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/tmdb_image_url.dart';
import '../../../../domain/entities/user_progress.dart';
import '../../../providers/watch_history_providers.dart';

/// "Up Next" overlay shown in the bottom-right of the player when the
/// current TV episode crosses the next-episode threshold.
///
/// Self-contained `ConsumerWidget`:
///   • watches `nextEpisodeForProgressProvider(progressKey)` for the next
///     episode metadata.
///   • renders its own slide / fade animation via `AnimatedPositioned` +
///     `AnimatedOpacity` driven by the `active` flag.
///   • surfaces three callbacks to the host screen: play the next ep,
///     dismiss, and the hover-pause callbacks for the auto-hide timer.
///
/// Extracted from `webview_player_screen.dart` so the overlay's
/// presentation can be tweaked independently of the WebView lifecycle.
class NextEpisodeOverlay extends ConsumerWidget {
  const NextEpisodeOverlay({
    super.key,
    required this.progressKey,
    required this.fallbackBackdropPath,
    required this.active,
    required this.onPlayNext,
    required this.onDismiss,
    required this.onHoverEnter,
    required this.onHoverExit,
  });

  /// Stable family-key — built once by the host screen and passed in so we
  /// don't re-allocate a `UserProgress` per rebuild (its `==`/`hashCode`
  /// already ignore the volatile fields).
  final UserProgress progressKey;

  /// Used as the thumbnail when the episode itself has no `still_path`.
  final String? fallbackBackdropPath;

  /// Controls the slide-in / fade-in animation. When `false` the card is
  /// off-screen with opacity 0.
  final bool active;

  final void Function(int season, int episode) onPlayNext;
  final VoidCallback onDismiss;
  final VoidCallback onHoverEnter;
  final VoidCallback onHoverExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextEpisodeAsync = ref.watch(
      nextEpisodeForProgressProvider(progressKey),
    );
    final nextEpisode = nextEpisodeAsync.value;
    if (nextEpisode == null) return const SizedBox.shrink();

    final thumbUrl = buildImageUrl(
      nextEpisode.stillPath ?? fallbackBackdropPath,
      AppConfig.backdropSmall,
    );

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutQuart,
      bottom: 100,
      right: active ? 32 : -400,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 500),
        opacity: active ? 1.0 : 0.0,
        // Listener fires for ALL pointer kinds (mouse AND touch), so
        // tapping/holding the card on a phone pauses the parent's
        // auto-hide timer the same way mouse hover does on desktop.
        // MouseRegion alone would never fire on touch, so the card
        // could slide out from under a user mid-tap.
        child: Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: (_) => onHoverEnter(),
          onPointerUp: (_) => onHoverExit(),
          child: MouseRegion(
            onEnter: (_) => onHoverEnter(),
            onExit: (_) => onHoverExit(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 380,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: Colors.white12, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _Thumbnail(url: thumbUrl),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UP NEXT',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            nextEpisode.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'S${nextEpisode.seasonNumber} '
                            'E${nextEpisode.episodeNumber}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => onPlayNext(
                                    nextEpisode.seasonNumber,
                                    nextEpisode.episodeNumber,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'Play Next',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: onDismiss,
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white70,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Dismiss',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 140,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
            color: Colors.white10,
          ),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const Center(
              child: Icon(Icons.movie_rounded, color: Colors.white24),
            ),
          ),
        ),
        Positioned.fill(
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.4),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
