import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/tmdb_image_url.dart';
import '../../core/config/app_config.dart';
import '../../domain/entities/media_item.dart';
import 'shimmer_placeholder.dart';

/// Hero Featured Card — 4:5 cinematic poster with overlay, badge, and actions.
class HeroCard extends StatelessWidget {
  final MediaItem movie;
  final String genreText;
  final VoidCallback? onTap;
  final VoidCallback? onAddTap;

  const HeroCard({
    super.key,
    required this.movie,
    this.genreText = '',
    this.onTap,
    this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.sectionPadding,
      child: GestureDetector(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: AppSpacing.heroAspectRatio,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppSpacing.borderRadius2Xl,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 30,
                  offset: Offset(0, 15),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: AppSpacing.borderRadius2Xl,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ─── Poster Image ──────────────────
                  _buildPosterImage(),

                  // ─── Gradient Overlay ──────────────
                  DecoratedBox(
                    decoration: BoxDecoration(gradient: AppColors.heroOverlay),
                  ),

                  // ─── Featured Badge ────────────────
                  Positioned(top: 16, left: 16, child: _buildFeaturedBadge()),

                  // ─── Content Overlay ────────────────
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildContentOverlay(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPosterImage() {
    final url = buildImageUrl(movie.posterPath, AppConfig.posterLarge);
    if (url.isEmpty) {
      return Container(color: AppColors.surfaceDark);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => const ShimmerPlaceholder(),
      errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
    );
  }

  Widget _buildFeaturedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryMuted,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8)],
      ),
      child: Text('Featured Premiere', style: AppTextStyles.tag),
    );
  }

  Widget _buildContentOverlay() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Text(
            movie.title,
            style: AppTextStyles.heroTitle.copyWith(
              shadows: [
                const Shadow(
                  color: Color(0x80000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 12),

          // Metadata row: rating • genre • runtime
          Row(
            children: [
              // Rating
              Icon(
                Icons.star_rounded,
                color: AppColors.primary,
                size: AppSpacing.iconSm,
              ),
              const SizedBox(width: 4),
              Text(
                movie.metadata.rating?.toStringAsFixed(1) ?? '—',
                style: AppTextStyles.metadata,
              ),

              _dot(),

              // Genre
              Text(
                genreText.isNotEmpty ? genreText : 'Movie',
                style: AppTextStyles.metadata,
              ),

              if (movie.metadata.formattedRuntime.isNotEmpty) ...[
                _dot(),
                Text(
                  movie.metadata.formattedRuntime,
                  style: AppTextStyles.metadata,
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              // Watch Trailer button
              Expanded(child: _buildWatchButton()),
              const SizedBox(width: 12),
              // Add button
              _buildAddButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWatchButton() {
    return Container(
      height: AppSpacing.buttonHeight,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: AppSpacing.borderRadiusLg,
        boxShadow: AppColors.primaryGlowShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppSpacing.borderRadiusLg,
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: AppSpacing.iconMd,
              ),
              const SizedBox(width: 8),
              Text('Watch Trailer', style: AppTextStyles.label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Container(
      width: AppSpacing.iconButtonSize,
      height: AppSpacing.iconButtonSize,
      decoration: BoxDecoration(
        color: AppColors.buttonGlass,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.buttonGlassBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppSpacing.borderRadiusLg,
          onTap: onAddTap,
          child: const Icon(
            Icons.add,
            color: Colors.white,
            size: AppSpacing.iconMd,
          ),
        ),
      ),
    );
  }

  Widget _dot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.dotSeparator,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
