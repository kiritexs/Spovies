import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/tmdb_image_url.dart';
import '../../core/config/app_config.dart';
import '../../domain/entities/media_item.dart';
import 'shimmer_placeholder.dart';

/// Poster card: 2:3 poster, rating badge, title and genres.
///
/// In a horizontal row (unbounded width) it is 140px wide; in a grid it
/// fills its cell. Focusable, activates with Enter/Space, and reads as one
/// button to screen readers.
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
  bool _focused = false;

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

  String get _subtitle => widget.genreText.isNotEmpty
      ? widget.genreText
      : widget.movie.type.displayName;

  String get _semanticLabel {
    final rating = widget.movie.metadata.rating;
    return [
      widget.movie.title,
      _subtitle,
      if (rating != null) 'rated ${rating.toStringAsFixed(1)}',
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      enabled: widget.onTap != null,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: Semantics(
        button: widget.onTap != null,
        label: _semanticLabel,
        excludeSemantics: true,
        onTap: widget.onTap,
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: (_) => _scaleController.forward(),
          onTapUp: (_) => _scaleController.reverse(),
          onTapCancel: () => _scaleController.reverse(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Row: fixed width. Grid: fill the cell.
              final width = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : AppSpacing.mediaCardWidth;
              return SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Poster: 2:3, shrinking if the cell is short.
                    Flexible(
                      child: LayoutBuilder(
                        builder: (context, posterConstraints) {
                          final preferred =
                              width / AppSpacing.mediaCardAspectRatio;
                          final h = posterConstraints.maxHeight.isFinite
                              ? preferred.clamp(
                                  0.0,
                                  posterConstraints.maxHeight,
                                )
                              : preferred;
                          return SizedBox(
                            height: h,
                            width: width,
                            child: _buildPosterContent(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.movie.title,
                      style: AppTextStyles.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      style: AppTextStyles.cardSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Poster content (decoration, image, badge). Fills its parent.
  Widget _buildPosterContent() {
    return Container(
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
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: AppSpacing.borderRadiusLg,
              border: Border.all(color: AppColors.focus, width: 2),
            )
          : null,
      child: ClipRRect(
        borderRadius: AppSpacing.borderRadiusLg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (_, child) =>
                  Transform.scale(scale: _scaleAnimation.value, child: child),
              child: _buildImage(),
            ),
            if (widget.movie.metadata.rating != null)
              Positioned(top: 8, right: 8, child: _buildRatingBadge()),
          ],
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
      placeholder: (_, _) => const ShimmerPlaceholder(),
      errorWidget: (_, _, _) => Container(color: AppColors.surfaceDark),
    );
  }

  /// Plain translucent circle. A BackdropFilter here ran a blur per card,
  /// which is costly in scrolling rows and barely visible at 32px.
  Widget _buildRatingBadge() {
    return Container(
      width: AppSpacing.ratingBadgeSize,
      height: AppSpacing.ratingBadgeSize,
      decoration: BoxDecoration(
        color: AppColors.ratingBadgeBg,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.glassBorder),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.movie.metadata.rating!.toStringAsFixed(1),
        style: AppTextStyles.ratingBadge,
      ),
    );
  }
}
