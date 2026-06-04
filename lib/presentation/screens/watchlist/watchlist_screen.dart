import 'dart:async';

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

import '../../../domain/entities/watch_status.dart';
import '../../providers/watch_status_providers.dart';

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  WatchStatus? _selectedStatus;

  @override
  Widget build(BuildContext context) {
    final allItems = ref.watch(watchlistProvider);
    final statusEntries = _selectedStatus == null
        ? null
        : ref.watch(libraryEntriesByStatusProvider(_selectedStatus!)).value ?? [];
    final filteredItems = _selectedStatus == null
        ? allItems
        : allItems
            .where((item) =>
                statusEntries!.any((e) => e.mediaId == item.tmdbId.toString()))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        title: Text('My Library', style: AppTextStyles.appTitle),
        centerTitle: false,
        actions: [
          if (allItems.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClearAll(context),
              child: Text(
                'Clear All',
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.redAccent,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: _buildFilterBar(),
        ),
      ),
      body: filteredItems.isEmpty 
          ? _buildEmpty() 
          : _buildGrid(context, filteredItems),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sectionPaddingH),
        children: [
          _StatusFilterChip(
            label: 'All',
            isSelected: _selectedStatus == null,
            onTap: () => setState(() => _selectedStatus = null),
          ),
          ...WatchStatus.values.map((status) {
            return _StatusFilterChip(
              label: status.displayName,
              isSelected: _selectedStatus == status,
              onTap: () => setState(() => _selectedStatus = status),
            );
          }),
        ],
      ),
    );
  }

  // ─── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _selectedStatus == null 
                ? Icons.bookmark_border_rounded 
                : Icons.filter_list_off_rounded,
            size: 72,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedStatus == null ? 'No saved titles' : 'No titles found',
            style: AppTextStyles.cardTitle.copyWith(
              color: AppColors.textSecondary,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedStatus == null 
                ? 'Tap the bookmark icon on any title\nto save it here'
                : 'Try selecting a different category',
            style: AppTextStyles.cardSubtitle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── Grid ──────────────────────────────────────────────────────────────────

  Widget _buildGrid(BuildContext context, List<MediaItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Dynamic column count for Windows/Desktop improvement
        int crossAxisCount = 3;
        if (constraints.maxWidth > 1200) {
          crossAxisCount = 6;
        } else if (constraints.maxWidth > 800) {
          crossAxisCount = 4;
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sectionPaddingH,
            AppSpacing.lg,
            AppSpacing.sectionPaddingH,
            120,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
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
              onRemove: () {
                unawaited(
                  ref
                      .read(watchStatusNotifierProvider.notifier)
                      .deleteAllStatusesForMedia(
                        item.tmdbId.toString(),
                        mediaType: item.type.name,
                      ),
                );
                ref.read(watchlistProvider.notifier).remove(item.tmdbId);
              },
            );
          },
        );
      },
    );
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        title: Text('Clear Library', style: AppTextStyles.sectionTitle),
        content: Text(
          'Remove all saved titles from your library?',
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
      // Snapshot the watchlist BEFORE we start mutating it so we keep the
      // (tmdbId, type) pairs needed for per-item deletion.
      final snapshot = ref
          .read(watchlistProvider)
          .map((m) => (id: m.tmdbId.toString(), type: m.type.name))
          .toList();
      // Await each delete so failures surface (and so the watchlist clear
      // below happens only after status rows are gone).
      for (final item in snapshot) {
        if (!mounted) return;
        await ref
            .read(watchStatusNotifierProvider.notifier)
            .deleteAllStatusesForMedia(item.id, mediaType: item.type);
      }
      if (!mounted) return;
      ref.read(watchlistProvider.notifier).clearAll();
    }
  }
}

class _StatusFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
        backgroundColor: AppColors.surfaceDark,
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        labelStyle: AppTextStyles.labelSmall.copyWith(
          color: isSelected ? AppColors.primary : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
          side: BorderSide(
            color: isSelected ? AppColors.primary : Colors.transparent,
          ),
        ),
        showCheckmark: false,
      ),
    );
  }
}

// ─── Individual Grid Item ──────────────────────────────────────────────────

class _WatchlistItem extends ConsumerWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _WatchlistItem({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posterUrl = buildImageUrl(item.posterPath, AppConfig.posterMedium);
    final statusAsync = ref.watch(
      mediaStatusProvider((
        mediaId: item.tmdbId.toString(),
        season: null,
        episode: null,
      )),
    );
    final status = statusAsync.value;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
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
                      if (status != null) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: status.status.displayName,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceDark.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Icon(
                              status.status.icon,
                              size: 12,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            style: AppTextStyles.cardTitle.copyWith(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
