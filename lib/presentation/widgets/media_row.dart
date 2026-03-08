import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/entities/media_item.dart';
import 'media_card.dart';
import 'shimmer_placeholder.dart';

/// Horizontal snap-scroll row with optional section title and "See All" action.
class MediaRow extends StatelessWidget {
  final String title;
  final List<MediaItem> movies;
  final Map<int, String> genreMap;
  final bool isLoading;
  final bool showTitle;
  final VoidCallback? onSeeAllTap;
  final void Function(MediaItem)? onMovieTap;

  const MediaRow({
    super.key,
    required this.title,
    required this.movies,
    this.genreMap = const {},
    this.isLoading = false,
    this.showTitle = true,
    this.onSeeAllTap,
    this.onMovieTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ─── Section Header ──────────────────
        if (showTitle) ...[
          Padding(
            padding: AppSpacing.sectionPadding,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: AppTextStyles.sectionTitle),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onSeeAllTap,
                    child: Text(
                      'See All',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ─── Horizontal Scroll ───────────────
        SizedBox(
          height: 275, // Increased from 260 to fit poster + 2 lines of text
          child: isLoading
              ? _buildShimmerRow()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: AppSpacing.sectionPadding,
                  itemCount: movies.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.cardGap),
                  itemBuilder: (context, index) {
                    final movie = movies[index];
                    return MediaCard(
                      movie: movie,
                      genreText: _resolveGenres(movie),
                      onTap: () => onMovieTap?.call(movie),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShimmerRow() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: AppSpacing.sectionPadding,
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.cardGap),
      itemBuilder: (_, __) => const MediaCardShimmer(),
    );
  }

  /// Resolve first 2 genre names from genreIds.
  String _resolveGenres(MediaItem movie) {
    if (movie.metadata.genres.isNotEmpty) {
      return movie.metadata.genres.take(2).join(' • ');
    }
    final ids = movie.metadata.genreIds;
    if (ids.isEmpty || genreMap.isEmpty) return movie.type.displayName;
    return ids
        .take(2)
        .map<String>((id) => genreMap[id] ?? '')
        .where((String n) => n.isNotEmpty)
        .join(' • ');
  }
}
