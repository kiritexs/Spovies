import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';

/// "Continue Watching" glass panel card with progress bar.
///
/// Phase 1: Static placeholder. Phase 4 will connect to WatchHistoryRepository.
class ContinueWatchingCard extends StatelessWidget {
  final String title;
  final String remainingTime;
  final double progress; // 0.0 – 1.0
  final String? thumbnailUrl;
  final VoidCallback? onTap;

  const ContinueWatchingCard({
    super.key,
    required this.title,
    required this.remainingTime,
    required this.progress,
    this.thumbnailUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.sectionPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Continue Watching', style: AppTextStyles.sectionTitle),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: AppSpacing.borderRadiusLg,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: AppSpacing.continueWatchingHeight,
                  decoration: BoxDecoration(
                    gradient: AppColors.glassGradient,
                    borderRadius: AppSpacing.borderRadiusLg,
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Stack(
                    children: [
                      // Content
                      Padding(
                        padding: AppSpacing.cardContentPadding,
                        child: Row(
                          children: [
                            // Thumbnail
                            _buildThumbnail(),
                            const SizedBox(width: 16),
                            // Info
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
                                  const SizedBox(height: 4),
                                  Text(
                                    remainingTime,
                                    style: AppTextStyles.cardSubtitle,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Progress bar at bottom
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
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    return SizedBox(
      width: AppSpacing.continueWatchingThumbWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail image or placeholder
            Container(
              color: AppColors.surfaceDark,
              child: thumbnailUrl != null && thumbnailUrl!.isNotEmpty
                  ? Image.network(thumbnailUrl!, fit: BoxFit.cover)
                  : const Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: AppColors.textSecondary,
                        size: 28,
                      ),
                    ),
            ),
            // Play icon overlay
            Container(
              color: AppColors.overlayDark,
              child: const Center(
                child: Icon(
                  Icons.play_circle_filled_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return SizedBox(
      height: AppSpacing.progressBarHeight,
      child: Stack(
        children: [
          // Track
          Container(width: double.infinity, color: AppColors.progressTrack),
          // Fill
          FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
