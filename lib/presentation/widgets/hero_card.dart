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

/// Hero Featured Card — Cinematic wide layout for desktop, 4:5 poster for mobile.
class HeroCard extends StatelessWidget {
  final MediaItem movie;
  final String genreText;
  final VoidCallback? onTap;

  /// Adds the title to the Library. The button is hidden when null.
  final VoidCallback? onAddTap;

  /// Shows the add button as a check ("In Library").
  final bool inLibrary;

  const HeroCard({
    super.key,
    required this.movie,
    this.genreText = '',
    this.onTap,
    this.inLibrary = false,
    this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        return Padding(
          padding: AppSpacing.sectionPadding,
          child: GestureDetector(
            onTap: onTap,
            child: AspectRatio(
              aspectRatio: isDesktop ? 16 / 7 : AppSpacing.heroAspectRatio,
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
                      // ─── Background (Backdrop for Desktop, Poster for Mobile) ──
                      isDesktop ? _buildBackdropImage() : _buildPosterImage(),

                      // ─── Gradient Overlay ──────────────
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: isDesktop
                              ? LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.9),
                                    Colors.black.withValues(alpha: 0.4),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.45, 1.0],
                                )
                              : AppColors.heroOverlay,
                        ),
                      ),

                      // ─── Featured Badge ────────────────
                      Positioned(
                        top: isDesktop ? 24 : 16,
                        left: isDesktop ? 32 : 16,
                        child: _buildFeaturedBadge(),
                      ),

                      // ─── Content Overlay ────────────────
                      if (isDesktop)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: constraints.maxWidth * 0.45,
                          child: _buildDesktopContent(),
                        )
                      else
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
      },
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
      placeholder: (_, _) => const ShimmerPlaceholder(),
      errorWidget: (_, _, _) => Container(color: AppColors.surfaceDark),
    );
  }

  Widget _buildBackdropImage() {
    final url = buildImageUrl(
      movie.backdropPath ?? movie.posterPath,
      AppConfig.backdropLarge,
    );
    if (url.isEmpty) {
      return Container(color: AppColors.surfaceDark);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 500),
      placeholder: (_, _) => const ShimmerPlaceholder(),
      errorWidget: (_, _, _) => Container(color: AppColors.surfaceDark),
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

  Widget _buildDesktopContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          // Title
          Text(
            movie.title,
            style: AppTextStyles.heroTitle.copyWith(
              fontSize: 40,
              height: 1.1,
              shadows: [
                const Shadow(
                  color: Color(0x80000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      color: AppColors.primaryOnDark,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      movie.metadata.rating?.toStringAsFixed(1) ?? '—',
                      style: AppTextStyles.metadata.copyWith(
                        color: AppColors.primaryOnDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              _dot(),

              // Genre: shrinks first, so large text sizes don't overflow.
              Flexible(
                child: Text(
                  genreText.isNotEmpty ? genreText : 'Movie',
                  style: AppTextStyles.metadata.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              if (movie.metadata.formattedRuntime.isNotEmpty) ...[
                _dot(),
                Text(
                  movie.metadata.formattedRuntime,
                  style: AppTextStyles.metadata.copyWith(fontSize: 14),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          // Overview (only on desktop)
          if (movie.overview != null && movie.overview!.isNotEmpty)
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      movie.overview!,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              // Watch Button
              SizedBox(width: 200, child: _buildWatchButton()),
              if (onAddTap != null) ...[
                const SizedBox(width: 16),
                _buildAddButton(),
              ],
            ],
          ),
        ],
      ),
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
                color: AppColors.primaryOnDark,
                size: AppSpacing.iconSm,
              ),
              const SizedBox(width: 4),
              Text(
                movie.metadata.rating?.toStringAsFixed(1) ?? '—',
                style: AppTextStyles.metadata,
              ),

              _dot(),

              // Genre: shrinks first, so large text sizes don't overflow.
              Flexible(
                child: Text(
                  genreText.isNotEmpty ? genreText : 'Movie',
                  style: AppTextStyles.metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
              Expanded(child: _buildWatchButton()),
              if (onAddTap != null) ...[
                const SizedBox(width: 12),
                _buildAddButton(),
              ],
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
                Icons.info_outline_rounded,
                color: Colors.white,
                size: AppSpacing.iconMd,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'View Details',
                  style: AppTextStyles.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    final label = inLibrary ? 'In Library' : 'Add to Library';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: _buildAddButtonBody(),
      ),
    );
  }

  Widget _buildAddButtonBody() {
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
          child: Icon(
            inLibrary ? Icons.check_rounded : Icons.add,
            color: inLibrary ? AppColors.primaryOnDark : Colors.white,
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
