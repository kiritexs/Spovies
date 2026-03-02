import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/tmdb_image_url.dart';
import '../../core/config/app_config.dart';
import '../../domain/entities/media_item.dart';
import 'shimmer_placeholder.dart';

/// Media card for trending/top-rated rows — 140px wide, 2:3 poster, rating badge.
class MediaCard extends StatefulWidget {
  final MediaItem movie;
  final String genreText;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MediaCard({
    super.key,
    required this.movie,
    this.genreText = '',
    this.onTap,
    this.onLongPress,
  });

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.10).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) => _scaleController.reverse(),
      onTapCancel: () => _scaleController.reverse(),
      child: SizedBox(
        width: AppSpacing.mediaCardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Poster ──────────────────────────
            _buildPoster(),
            const SizedBox(height: 8),
            // ─── Info ────────────────────────────
            Text(
              widget.movie.title,
              style: AppTextStyles.cardTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              widget.genreText.isNotEmpty
                  ? widget.genreText
                  : widget.movie.type.displayName,
              style: AppTextStyles.cardSubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPoster() {
    return AspectRatio(
      aspectRatio: AppSpacing.mediaCardAspectRatio,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppSpacing.borderRadiusLg,
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppSpacing.borderRadiusLg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Poster image with scale animation
              AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (_, child) =>
                    Transform.scale(scale: _scaleAnimation.value, child: child),
                child: _buildImage(),
              ),

              // Rating badge
              if (widget.movie.metadata.rating != null)
                Positioned(top: 8, right: 8, child: _buildRatingBadge()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    final url = buildImageUrl(widget.movie.posterPath, AppConfig.posterMedium);
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

  Widget _buildRatingBadge() {
    return Container(
      width: AppSpacing.ratingBadgeSize,
      height: AppSpacing.ratingBadgeSize,
      decoration: BoxDecoration(
        color: AppColors.ratingBadgeBg,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Center(
            child: Text(
              widget.movie.metadata.rating!.toStringAsFixed(1),
              style: AppTextStyles.ratingBadge,
            ),
          ),
        ),
      ),
    );
  }
}
