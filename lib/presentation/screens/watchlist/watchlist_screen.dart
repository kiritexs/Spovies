import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/tmdb_image_url.dart';
import '../../../domain/entities/media_item.dart';
import '../../providers/watchlist_providers.dart';
import '../../widgets/shimmer_placeholder.dart';

/// Watchlist screen — grid of saved media items with remove option.
class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(watchlistProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        title: Text('My Watchlist', style: AppTextStyles.appTitle),
        centerTitle: false,
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClearAll(context, ref),
              child: Text(
                'Clear All',
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.redAccent,
                ),
              ),
            ),
        ],
      ),
      body: items.isEmpty ? _buildEmpty() : _buildGrid(context, ref, items),
    );
  }

  // ─── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bookmark_border_rounded,
            size: 72,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No saved titles',
            style: AppTextStyles.cardTitle.copyWith(
              color: AppColors.textSecondary,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the bookmark icon on any title\nto save it here',
            style: AppTextStyles.cardSubtitle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── Grid ──────────────────────────────────────────────────────────────────

  Widget _buildGrid(
    BuildContext context,
    WidgetRef ref,
    List<MediaItem> items,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sectionPaddingH,
        AppSpacing.lg,
        AppSpacing.sectionPaddingH,
        120,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.58,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _WatchlistItem(
          item: item,
          onTap: () => context.push('/details', extra: item),
          onRemove: () =>
              ref.read(watchlistProvider.notifier).remove(item.tmdbId),
        );
      },
    );
  }

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        title: Text('Clear Watchlist', style: AppTextStyles.sectionTitle),
        content: Text(
          'Remove all saved titles?',
          style: AppTextStyles.body.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.label.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear',
              style: AppTextStyles.label.copyWith(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(watchlistProvider.notifier).clearAll();
    }
  }
}

// ─── Individual Grid Item ──────────────────────────────────────────────────

class _WatchlistItem extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _WatchlistItem({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final posterUrl = buildImageUrl(item.posterPath, AppConfig.posterMedium);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  child: posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const ShimmerPlaceholder(),
                          errorWidget: (_, __, ___) =>
                              Container(color: AppColors.surfaceDark),
                        )
                      : Container(color: AppColors.surfaceDark),
                ),
                // Remove badge
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Type badge
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.type.displayName.toUpperCase(),
                      style: AppTextStyles.tag.copyWith(fontSize: 9),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Title
          Text(
            item.title,
            style: AppTextStyles.cardTitle.copyWith(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // Year
          if (item.year != null)
            Text(
              item.year!,
              style: AppTextStyles.cardSubtitle.copyWith(fontSize: 11),
            ),
        ],
      ),
    );
  }
}
