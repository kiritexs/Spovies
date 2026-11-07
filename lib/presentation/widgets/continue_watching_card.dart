import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';

/// Individual "Continue Watching" glass card.
///
/// Shows thumbnail, title, remaining time, and a progress bar at the bottom.
/// Used in the horizontal Continue Watching row on the home screen.
class ContinueWatchingCard extends StatelessWidget {
  final String title;
  final String remainingTime;

  /// 0.0 – 1.0
  final double progress;
  final String? thumbnailUrl;
  final VoidCallback? onTap;

  /// When set, a play icon button is shown on the left to continue playback directly.
  final VoidCallback? onContinueTap;

  /// Optional episode label, e.g. "S2 E4". Shown below the title for TV shows.
  final String? episodeLabel;

  const ContinueWatchingCard({
    super.key,
    required this.title,
    required this.remainingTime,
    required this.progress,
    this.thumbnailUrl,
    this.onTap,
    this.onContinueTap,
    this.episodeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppSpacing.borderRadiusLg,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: double.infinity,
            height: AppSpacing.continueWatchingHeight,
            decoration: BoxDecoration(
              gradient: AppColors.glassGradient,
              borderRadius: AppSpacing.borderRadiusLg,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Stack(
              children: [
                // ─── Content Row ──────────────────────────────────
                Padding(
                  padding: AppSpacing.cardContentPadding,
                  child: Row(
                    children: [
                      _buildThumbnail(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              style: AppTextStyles.cardTitle.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (episodeLabel != null) ...[
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  episodeLabel!,
                                  style: AppTextStyles.cardSubtitle.copyWith(
                                    color: AppColors.primaryOnDark,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              remainingTime,
                              style: AppTextStyles.cardSubtitle,
                            ),
                          ],
                        ),
                      ),
                      if (onContinueTap != null) ...[
                        IconButton(
                          onPressed: onContinueTap,
                          icon: const Icon(
                            Icons.play_circle_filled_rounded,
                            color: AppColors.primaryOnDark,
                            size: 36,
                          ),
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(4),
                            minimumSize: const Size(44, 44),
                          ),
                          tooltip: 'Continue',
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),

                // ─── Progress Bar ──────────────────────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildProgressBar(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    return SizedBox(
      width: AppSpacing.continueWatchingThumbWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: AppColors.surfaceDark,
              child: thumbnailUrl != null && thumbnailUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _thumbPlaceholder(),
                    )
                  : _thumbPlaceholder(),
            ),
            // Dim overlay
            Container(color: AppColors.overlayDark),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return const Center(
      child: Icon(
        Icons.movie_outlined,
        color: AppColors.textSecondary,
        size: 28,
      ),
    );
  }

  Widget _buildProgressBar() {
    return SizedBox(
      height: AppSpacing.progressBarHeight,
      child: Stack(
        children: [
          Container(width: double.infinity, color: AppColors.progressTrack),
          FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
