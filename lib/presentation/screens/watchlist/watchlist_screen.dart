import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/responsive_grid.dart';
import '../../../core/utils/tmdb_image_url.dart';
import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/media_type.dart';
import '../../../domain/entities/watch_status.dart';
import '../../providers/details_providers.dart';
import '../../providers/watch_status_providers.dart';
import '../../providers/watchlist_providers.dart';
import '../../router/app_tabs.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/shimmer_placeholder.dart';

/// One card in the Library: a saved title, a title with a watch status,
/// or both. Titles that only have a status (no saved item) load their
/// poster and name from TMDB.
class _LibraryEntry {
  final int tmdbId;
  final MediaType type;
  final MediaItem? item;
  final WatchStatus? status;

  const _LibraryEntry({
    required this.tmdbId,
    required this.type,
    this.item,
    this.status,
  });

  String get key => '${type.name}_$tmdbId';
}

enum _LibraryMenu { clear }

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  WatchStatus? _selectedStatus;

  /// Titles whose removal is in progress; a second tap would snapshot
  /// nothing and its snackbar would replace the first one's Undo.
  final Set<String> _removing = {};

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(watchlistProvider);
    final statusesAsync = ref.watch(titleStatusesProvider);
    final entries = _entries(saved, statusesAsync.value ?? const []);
    final visible = _selectedStatus == null
        ? entries
        : entries.where((e) => e.status == _selectedStatus).toList();

    final Widget body;
    if (statusesAsync.hasError && !statusesAsync.hasValue) {
      body = _buildError();
    } else if (statusesAsync.isLoading && !statusesAsync.hasValue) {
      body = const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    } else if (visible.isEmpty) {
      body = _buildEmpty();
    } else {
      body = _buildGrid(context, visible);
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        title: Text(AppTab.library.label, style: AppTextStyles.appTitle),
        centerTitle: false,
        actions: [
          if (entries.isNotEmpty)
            // Values are non-null: PopupMenuButton treats null as "cancelled".
            PopupMenuButton<_LibraryMenu>(
              tooltip: 'More options',
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AppColors.textSecondary,
              ),
              color: AppColors.surfaceDark,
              onSelected: (_) => _confirmClearAll(context),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _LibraryMenu.clear,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_sweep_rounded,
                        color: AppColors.danger,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Clear Library',
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: _buildFilterBar(),
        ),
      ),
      body: body,
    );
  }

  /// Saved titles first (in saved order), then titles that only have a
  /// status, most recently updated first.
  List<_LibraryEntry> _entries(
    List<MediaItem> saved,
    List<MediaStatus> statuses,
  ) {
    final statusByKey = {
      for (final s in statuses) '${s.mediaType}_${s.mediaId}': s,
    };
    final out = <_LibraryEntry>[];
    final seen = <String>{};
    for (final item in saved) {
      final entry = _LibraryEntry(
        tmdbId: item.tmdbId,
        type: item.type,
        item: item,
        status: statusByKey['${item.type.name}_${item.tmdbId}']?.status,
      );
      seen.add(entry.key);
      out.add(entry);
    }
    final statusOnly =
        statuses
            .where((s) => !seen.contains('${s.mediaType}_${s.mediaId}'))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final s in statusOnly) {
      final id = int.tryParse(s.mediaId);
      if (id == null) continue;
      final entry = _LibraryEntry(
        tmdbId: id,
        type: s.mediaType == 'tv' ? MediaType.tv : MediaType.movie,
        status: s.status,
      );
      out.add(entry);
    }
    return out;
  }

  Widget _buildFilterBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sectionPaddingH,
        ),
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

  // ─── Empty / Error ─────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    final filtered = _selectedStatus != null;
    return _message(
      icon: filtered
          ? Icons.filter_list_off_rounded
          : Icons.bookmark_border_rounded,
      title: filtered
          ? 'Nothing marked ${_selectedStatus!.displayName}'
          : 'Your library is empty',
      body: filtered
          ? 'Set a status from a title\'s page and it shows up here.'
          : 'Open any title and choose Add to Library to save it here.',
    );
  }

  Widget _buildError() {
    return _message(
      icon: Icons.error_outline_rounded,
      title: 'Couldn\'t load your library',
      body: 'Your saved titles are still on this device.',
      action: TextButton.icon(
        onPressed: () => ref.invalidate(titleStatusesProvider),
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Retry'),
        style: TextButton.styleFrom(foregroundColor: AppColors.primaryOnDark),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 72,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.cardTitle.copyWith(
                color: AppColors.textSecondary,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: AppTextStyles.cardSubtitle,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 12), action],
          ],
        ),
      ),
    );
  }

  // ─── Grid ──────────────────────────────────────────────────────────────────

  Widget _buildGrid(BuildContext context, List<_LibraryEntry> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sectionPaddingH,
            AppSpacing.lg,
            AppSpacing.sectionPaddingH,
            120,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: posterGridColumns(constraints.maxWidth),
            childAspectRatio: 0.58,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _LibraryCard(
              key: ValueKey(entry.key),
              entry: entry,
              onRemove: () => unawaited(_remove(entry)),
            );
          },
        );
      },
    );
  }

  /// Remove now and offer Undo, which restores the saved item, its
  /// statuses and its progress exactly as they were.
  Future<void> _remove(_LibraryEntry entry) async {
    if (!_removing.add(entry.key)) return;
    final notifier = ref.read(watchStatusNotifierProvider.notifier);
    final RemovedTitle removed;
    try {
      removed = await notifier.removeTitle(
        entry.tmdbId.toString(),
        mediaType: entry.type.name,
        item: entry.item,
      );
    } finally {
      _removing.remove(entry.key);
    }
    if (!mounted) return;
    showAppSnackBar(
      context,
      'Removed from Library',
      aboveNav: true,
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'Undo',
        textColor: AppColors.primaryOnDark,
        onPressed: () => unawaited(notifier.restoreTitle(removed)),
      ),
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
          'Remove every saved title and watch status? This can\'t be undone.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
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
              style: AppTextStyles.label.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(watchlistProvider.notifier).clearAll();
    await ref.read(watchStatusNotifierProvider.notifier).clearAll();
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
          color: isSelected ? AppColors.primaryOnDark : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
          side: BorderSide(
            color: isSelected ? AppColors.primaryOnDark : Colors.transparent,
          ),
        ),
        showCheckmark: false,
      ),
    );
  }
}

// ─── Library Card ────────────────────────────────────────────────────────────

class _LibraryCard extends ConsumerWidget {
  final _LibraryEntry entry;
  final VoidCallback onRemove;

  const _LibraryCard({super.key, required this.entry, required this.onRemove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Status-only titles have no saved metadata; fetch it (cached by Dio).
    final AsyncValue<MediaItem> itemAsync = entry.item != null
        ? AsyncData(entry.item!)
        : ref.watch(
            mediaDetailsProvider((tmdbId: entry.tmdbId, type: entry.type)),
          );
    final item = itemAsync.value;
    final failed = item == null && itemAsync.hasError;
    final title =
        item?.title ?? (failed ? 'Couldn\'t load · tap to retry' : '');
    final posterUrl = buildImageUrl(item?.posterPath, AppConfig.posterMedium);
    final status = entry.status;

    final description = [
      title,
      entry.type.displayName,
      ?item?.year,
      ?status?.displayName,
    ].join(', ');

    return Semantics(
      container: true,
      label: description,
      button: item != null || failed,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: item != null
              ? () => context.push('/details', extra: item)
              : failed
              ? () => _retryDetails(ref)
              : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          focusColor: AppColors.focus.withValues(alpha: 0.2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      child: itemAsync.isLoading && item == null
                          ? const ShimmerPlaceholder()
                          : posterUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: posterUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => const ShimmerPlaceholder(),
                              errorWidget: (_, _, _) =>
                                  Container(color: AppColors.surfaceDark),
                            )
                          : Container(color: AppColors.surfaceDark),
                    ),
                    // 48px target; the visible circle stays 28px.
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip: 'Remove from Library',
                        onPressed: onRemove,
                        style: IconButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 48),
                        ),
                        icon: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // One badge: the status, when there is one.
                    if (status != null)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        right: 6,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: ExcludeSemantics(
                            child: _Badge(
                              text: status.displayName,
                              background: AppColors.surfaceDark.withValues(
                                alpha: 0.9,
                              ),
                              foreground: AppColors.primaryOnDark,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              ExcludeSemantics(
                child: Text(
                  title,
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Type and year on one quiet line: "Movie · 2020".
              ExcludeSemantics(
                child: Text(
                  [entry.type.displayName, ?item?.year].join(' · '),
                  style: AppTextStyles.cardSubtitle.copyWith(fontSize: 11),
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
}

extension on _LibraryCard {
  /// mediaDetailsProvider only re-watches the movie/TV details provider,
  /// which holds the error (auto-retry is off), so invalidate that one.
  void _retryDetails(WidgetRef ref) {
    if (entry.type == MediaType.tv) {
      ref.invalidate(tvDetailsProvider(entry.tmdbId));
    } else {
      ref.invalidate(movieDetailsProvider(entry.tmdbId));
    }
    ref.invalidate(
      mediaDetailsProvider((tmdbId: entry.tmdbId, type: entry.type)),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;

  const _Badge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.tag.copyWith(fontSize: 9, color: foreground),
      ),
    );
  }
}
