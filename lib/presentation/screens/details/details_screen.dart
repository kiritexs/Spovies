import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/tmdb_image_url.dart';
import '../../../domain/entities/cast_member.dart';
import '../../../domain/entities/episode.dart';
import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/media_type.dart';
import '../../../domain/entities/plugin_manifest.dart';
import '../../../domain/entities/user_progress.dart';
import '../../../plugins/protocol/action_type.dart';
import '../../../plugins/protocol/plugin_url_resolver.dart';
import 'package:go_router/go_router.dart';

import '../../../plugins/protocol/trigger_hook.dart';
import '../../providers/details_providers.dart';
import '../../providers/plugin_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/watch_history_providers.dart';
import '../../providers/watch_status_providers.dart';
import '../../providers/watchlist_providers.dart';
import '../../router/app_router.dart';
import '../../../domain/entities/watch_status.dart';
import '../../widgets/shimmer_placeholder.dart';

/// Sentinel for next-episode provider when there is no progress.
final _noProgressSentinel = UserProgress(
  mediaId: '',
  mediaType: 'movie',
  title: '',
  percentage: 0,
  currentTime: 0,
  duration: 0,
  lastPlayedDate: DateTime(0),
);

/// Cinematic full-screen movie/TV details page.
///
/// Includes backdrop parallax, poster, cast row, trailer chip,
/// plugin "Watch" button, genre chips, expandable overview,
/// and episode list for TV shows (episode_item hook).
class DetailsScreen extends ConsumerStatefulWidget {
  final MediaItem media;

  const DetailsScreen({super.key, required this.media});

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  int _selectedSeason = 1;

  MediaItem get media => widget.media;

  @override
  Widget build(BuildContext context) {
    final isTV = media.type == MediaType.tv;
    final detailsAsync = isTV
        ? ref.watch(tvDetailsProvider(media.tmdbId))
        : ref.watch(movieDetailsProvider(media.tmdbId));
    final pluginsAsync = ref.watch(
      pluginsForHookProvider(TriggerHook.mediaHeader),
    );
    final preferredId = ref.watch(preferredPluginProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: detailsAsync.when(
        loading: () => _buildLoading(context),
        error: (e, _) => _buildError(context, e.toString()),
        data: (details) {
          final cwList =
              ref
                  .watch(continueWatchingProvider)
                  .whenOrNull(data: (list) => list) ??
              [];
          UserProgress? continueProgress;
          for (final p in cwList) {
            if (p.mediaId == details.tmdbId.toString()) {
              continueProgress = p;
              break;
            }
          }
          final progressForNext = continueProgress ?? _noProgressSentinel;
          final nextEpisode = ref
              .watch(nextEpisodeForProgressProvider(progressForNext))
              .value;
          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 900;
              return _buildContent(
                context,
                details,
                pluginsAsync.value ?? [],
                preferredId,
                isDesktop,
                continueProgress: continueProgress,
                nextEpisode:
                    continueProgress != null &&
                        continueProgress.percentage >= 95 &&
                        details.type == MediaType.tv
                    ? nextEpisode
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  // ─── Loading ──────────────────────────────────────────────────────────

  Widget _buildLoading(BuildContext context) {
    return Stack(
      children: [
        // Backdrop placeholder
        Container(
          height: 360,
          color: AppColors.surfaceDark,
          child: const ShimmerPlaceholder(),
        ),
        // Back button
        _buildBackButton(context),
      ],
    );
  }

  // ─── Error ────────────────────────────────────────────────────────────

  Widget _buildError(BuildContext context, String error) {
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Failed to load details:\n$error',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        _buildBackButton(context),
      ],
    );
  }

  // ─── Main Content ─────────────────────────────────────────────────────

  Widget _buildContent(
    BuildContext context,
    MediaItem details,
    List<PluginManifest> plugins,
    String? preferredId,
    bool isDesktop, {
    UserProgress? continueProgress,
    ({int season, int episode})? nextEpisode,
  }) {
    if (isDesktop) {
      return _buildDesktopContent(
        context,
        details,
        plugins,
        preferredId,
        continueProgress: continueProgress,
        nextEpisode: nextEpisode,
      );
    }

    final isTV = details.type == MediaType.tv;

    return CustomScrollView(
      slivers: [
        // ── Backdrop Hero ─────────────────────────────────────────
        SliverToBoxAdapter(child: _buildBackdrop(context, details)),

        // ── Info Section ──────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sectionPaddingH,
            0,
            AppSpacing.sectionPaddingH,
            AppSpacing.xxl,
          ),
          sliver: SliverList.list(
            children: [
              const SizedBox(height: 16),

              // Title
              Text(details.title, style: AppTextStyles.heroTitle),
              const SizedBox(height: 8),

              // Metadata row: year • runtime/seasons • certification • rating
              _buildMetadataRow(details),
              const SizedBox(height: 16),

              // Genre chips
              _buildGenreChips(details),
              const SizedBox(height: 20),

              // Action buttons row
              _buildActionRow(
                context,
                details,
                plugins,
                preferredId,
                continueProgress: continueProgress,
                nextEpisode: nextEpisode,
              ),
              const SizedBox(height: 8),

              // Trailer chip
              if (details.metadata.trailerKey != null)
                _buildTrailerChip(details.metadata.trailerKey!),
              const SizedBox(height: 20),

              // Overview
              _buildOverview(details),
              const SizedBox(height: 24),

              // Cast
              if (details.metadata.cast.isNotEmpty) ...[
                Text('Cast', style: AppTextStyles.sectionTitle),
                const SizedBox(height: 12),
                _buildCastRow(details.metadata.cast),
                const SizedBox(height: 24),
              ],

              // Episode list — TV only
              if (isTV && details.metadata.seasons.isNotEmpty) ...[
                _buildEpisodeSection(context, details, plugins, preferredId),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopContent(
    BuildContext context,
    MediaItem details,
    List<PluginManifest> plugins,
    String? preferredId, {
    UserProgress? continueProgress,
    ({int season, int episode})? nextEpisode,
  }) {
    final isTV = details.type == MediaType.tv;
    final backdropUrl = buildImageUrl(
      details.backdropPath ?? details.posterPath,
      AppConfig.backdropLarge,
    );

    return Stack(
      children: [
        // 1. Full Screen Blurred Background
        if (backdropUrl.isNotEmpty)
          Positioned.fill(
            child: Opacity(
              opacity: 0.4,
              child: CachedNetworkImage(
                imageUrl: backdropUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(color: Colors.black.withValues(alpha: 0.4)),
          ),
        ),

        // 2. Main Content
        SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Poster
              Padding(
                padding: const EdgeInsets.all(48.0),
                child: Hero(
                  tag: 'poster_${details.tmdbId}',
                  child: Container(
                    width: 340,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 40,
                          offset: Offset(0, 20),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: CachedNetworkImage(
                          imageUrl: buildImageUrl(
                            details.posterPath,
                            AppConfig.posterLarge,
                          ),
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const ShimmerPlaceholder(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Right: Info (Scrollable)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(0, 48, 64, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Subtitle / Year
                      if (details.year != null)
                        Text(
                          details.year!,
                          style: AppTextStyles.tag.copyWith(
                            color: AppColors.primary,
                            letterSpacing: 2,
                          ),
                        ),
                      const SizedBox(height: 8),

                      // Title
                      Text(
                        details.title,
                        style: AppTextStyles.heroTitle.copyWith(
                          fontSize: 56,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Metadata Row
                      _buildMetadataRow(details),
                      const SizedBox(height: 24),

                      // Actions
                      _buildDesktopActionRow(
                        context,
                        details,
                        plugins,
                        preferredId,
                        continueProgress: continueProgress,
                        nextEpisode: nextEpisode,
                      ),
                      const SizedBox(height: 32),

                      // Overview
                      Text('Synopsis', style: AppTextStyles.sectionTitle),
                      const SizedBox(height: 12),
                      _buildOverview(details),
                      const SizedBox(height: 32),

                      // Cast
                      if (details.metadata.cast.isNotEmpty) ...[
                        Text('Cast & Crew', style: AppTextStyles.sectionTitle),
                        const SizedBox(height: 16),
                        _buildCastRow(details.metadata.cast),
                        const SizedBox(height: 32),
                      ],

                      // Episodes
                      if (isTV && details.metadata.seasons.isNotEmpty)
                        _buildEpisodeSection(
                          context,
                          details,
                          plugins,
                          preferredId,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (Platform.isWindows)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DragToMoveArea(child: SizedBox(height: 80)),
          ),

        // Back Button
        _buildBackButton(context),
      ],
    );
  }

  Widget _buildDesktopActionRow(
    BuildContext context,
    MediaItem details,
    List<PluginManifest> plugins,
    String? preferredId, {
    UserProgress? continueProgress,
    ({int season, int episode})? nextEpisode,
  }) {
    final activePlugin = _resolvePlugin(plugins, preferredId);
    final isTV = details.type == MediaType.tv;
    final showResume =
        continueProgress != null &&
        continueProgress.percentage < 95 &&
        plugins.isNotEmpty;
    final showNextEp =
        continueProgress != null &&
        continueProgress.percentage >= 95 &&
        isTV &&
        nextEpisode != null &&
        plugins.isNotEmpty;

    return Row(
      children: [
        if (showResume) ...[
          Flexible(
            child: SizedBox(
              width: 280,
              height: 56,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppColors.primaryGlowShadow,
                ),
                child: ElevatedButton.icon(
                  onPressed: () =>
                      _openContinue(context, details, continueProgress!),
                  icon: const Icon(Icons.play_circle_rounded, size: 28),
                  label: Text(
                    'Continue (${continueProgress.remainingTime})',
                    style: AppTextStyles.label.copyWith(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ),
          if (activePlugin != null) ...[
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _openFromStart(context, details, activePlugin),
              icon: const Icon(Icons.replay_rounded, size: 20),
              label: Text('Start over', style: AppTextStyles.labelSmall),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.glassBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
          const SizedBox(width: 12),
        ],
        if (showNextEp) ...[
          SizedBox(
            width: 260,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => _openNextEpisode(
                context,
                details,
                nextEpisode!.season,
                nextEpisode.episode,
              ),
              icon: const Icon(Icons.skip_next_rounded, size: 24),
              label: Text(
                'Start next (S${nextEpisode.season} E${nextEpisode.episode})',
                style: AppTextStyles.label.copyWith(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        if (!showResume && !showNextEp && activePlugin != null) ...[
          SizedBox(
            width: 220,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () => _executePlugin(context, activePlugin, details),
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: Text(
                isTV ? 'Watch Series' : 'Watch Movie',
                style: AppTextStyles.label.copyWith(fontSize: 16),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppColors.glassBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],

        _buildLibraryAction(context, details),

        if (details.metadata.trailerKey != null) ...[
          const SizedBox(width: 12),
          IconButton(
            onPressed: () async {
              final uri = Uri.parse(
                'https://www.youtube.com/watch?v=${details.metadata.trailerKey}',
              );
              if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open trailer')),
                  );
                }
              }
            },
            icon: const Icon(Icons.movie_outlined, size: 24),
            tooltip: 'Watch trailer',
          ),
        ],
      ],
    );
  }

  // ─── Backdrop ─────────────────────────────────────────────────────────

  Widget _buildBackdrop(BuildContext context, MediaItem details) {
    final backdropUrl = buildImageUrl(
      details.backdropPath,
      AppConfig.backdropMedium,
    );

    return Stack(
      children: [
        // Image
        SizedBox(
          height: 360,
          width: double.infinity,
          child: backdropUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: backdropUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const ShimmerPlaceholder(),
                  errorWidget: (context, url, error) =>
                      Container(color: AppColors.surfaceDark),
                )
              : Container(color: AppColors.surfaceDark),
        ),

        // Gradient overlays
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.backgroundDark.withValues(alpha: 0.7),
                  AppColors.backgroundDark,
                ],
                stops: const [0.3, 0.7, 1.0],
              ),
            ),
          ),
        ),

        // Back button
        _buildBackButton(context),
        if (Platform.isWindows)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DragToMoveArea(child: SizedBox(height: 80)),
          ),
      ],
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Metadata Row ─────────────────────────────────────────────────────

  Widget _buildMetadataRow(MediaItem details) {
    final items = <Widget>[];

    // Year
    if (details.year != null) {
      items.add(Text(details.year!, style: AppTextStyles.metadata));
    }

    // Runtime (movies) or season count (TV)
    if (details.type == MediaType.tv) {
      final count = details.metadata.numberOfSeasons;
      if (count != null && count > 0) {
        items.add(_dot());
        items.add(
          Text(
            '$count ${count == 1 ? 'Season' : 'Seasons'}',
            style: AppTextStyles.metadata,
          ),
        );
      }
    } else if (details.metadata.formattedRuntime.isNotEmpty) {
      items.add(_dot());
      items.add(
        Text(details.metadata.formattedRuntime, style: AppTextStyles.metadata),
      );
    }

    // Certification
    if (details.metadata.certification != null) {
      items.add(_dot());
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.textSecondary),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            details.metadata.certification!,
            style: AppTextStyles.tag.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ),
      );
    }

    // Rating
    if (details.metadata.rating != null) {
      items.add(_dot());
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: AppColors.primary, size: 16),
            const SizedBox(width: 4),
            Text(
              details.metadata.rating!.toStringAsFixed(1),
              style: AppTextStyles.metadata,
            ),
          ],
        ),
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 0,
      children: items,
    );
  }

  Widget _dot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 4,
        height: 4,
        decoration: const BoxDecoration(
          color: AppColors.dotSeparator,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  // ─── Genre Chips ──────────────────────────────────────────────────────

  Widget _buildGenreChips(MediaItem details) {
    if (details.metadata.genres.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: details.metadata.genres.map((genre) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Text(genre, style: AppTextStyles.labelSmall),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Watch Button ─────────────────────────────────────────────────────

  Widget _buildActionRow(
    BuildContext context,
    MediaItem details,
    List<PluginManifest> plugins,
    String? preferredId, {
    UserProgress? continueProgress,
    ({int season, int episode})? nextEpisode,
  }) {
    final activePlugin = _resolvePlugin(plugins, preferredId);
    final showResume =
        continueProgress != null &&
        continueProgress.percentage < 95 &&
        plugins.isNotEmpty;
    final showNextEp =
        continueProgress != null &&
        continueProgress.percentage >= 95 &&
        details.type == MediaType.tv &&
        nextEpisode != null &&
        plugins.isNotEmpty;

    return Row(
      children: [
        if (showResume) ...[
          Expanded(
            child: Container(
              height: AppSpacing.buttonHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                boxShadow: AppColors.primaryGlowShadow,
              ),
              child: ElevatedButton.icon(
                onPressed: () =>
                    _openContinue(context, details, continueProgress!),
                icon: const Icon(Icons.play_circle_rounded, size: 24),
                label: Text(
                  'Continue (${continueProgress.remainingTime})',
                  style: AppTextStyles.label,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
          if (activePlugin != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _openFromStart(context, details, activePlugin),
              icon: const Icon(Icons.replay_rounded, size: 20),
              label: Text('Start over', style: AppTextStyles.labelSmall),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.glassBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                ),
              ),
            ),
          ],
        ],
        if (showNextEp) ...[
          Expanded(
            child: Container(
              height: AppSpacing.buttonHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                boxShadow: AppColors.primaryGlowShadow,
              ),
              child: ElevatedButton.icon(
                onPressed: () => _openNextEpisode(
                  context,
                  details,
                  nextEpisode!.season,
                  nextEpisode.episode,
                ),
                icon: const Icon(Icons.skip_next_rounded, size: 24),
                label: Text(
                  'Start next (S${nextEpisode.season} E${nextEpisode.episode})',
                  style: AppTextStyles.label,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],

        if (!showResume && !showNextEp && activePlugin != null)
          Expanded(
            child: Container(
              height: AppSpacing.buttonHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: OutlinedButton.icon(
                onPressed: () => _executePlugin(context, activePlugin, details),
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  details.type == MediaType.tv ? 'Watch Series' : 'Watch Movie',
                  style: AppTextStyles.label,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.glassBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                  ),
                ),
              ),
            ),
          ),

        if (plugins.isNotEmpty) const SizedBox(width: 12),

        // Consolidated Library/Status Button
        Expanded(child: _buildLibraryAction(context, details)),
      ],
    );
  }

  Widget _buildLibraryAction(BuildContext context, MediaItem details) {
    final statusAsync = ref.watch(
      mediaStatusProvider((
        mediaId: details.tmdbId.toString(),
        season: null,
        episode: null,
      )),
    );

    return statusAsync.when(
      data: (current) {
        final isInLibrary = current != null;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showLibraryStatusModal(context, details, current),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 56,
              constraints: const BoxConstraints(minWidth: 56),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isInLibrary
                      ? AppColors.primary.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.15),
                  width: 1.5,
                ),
                boxShadow: isInLibrary
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isInLibrary
                      ? [
                          AppColors.primary.withValues(alpha: 0.18),
                          AppColors.primary.withValues(alpha: 0.08),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.03),
                        ],
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    current?.status.icon ?? Icons.playlist_add_rounded,
                    color: isInLibrary ? AppColors.primary : Colors.white70,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      current?.status.displayName ?? 'Add to Library',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isInLibrary ? AppColors.primary : Colors.white70,
                        fontWeight: isInLibrary
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox(width: 56, height: 56),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _showLibraryStatusModal(
    BuildContext context,
    MediaItem details,
    MediaStatus? current,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundDark.withValues(alpha: 0.8),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radiusXl),
              ),
              border: Border.all(color: AppColors.glassBorder),
            ),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.library_add_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Update Library Status',
                      style: AppTextStyles.sectionTitle.copyWith(fontSize: 18),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Status List
                ...WatchStatus.values.map((s) {
                  final isSelected = current?.status == s;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () {
                        ref
                            .read(watchStatusNotifierProvider.notifier)
                            .setStatus(
                              MediaStatus(
                                mediaId: details.tmdbId.toString(),
                                mediaType: details.type.name,
                                status: s,
                                season: null,
                                episode: null,
                                updatedAt: DateTime.now(),
                              ),
                              mediaItem: details,
                            );
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusBase,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : AppColors.glass,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusBase,
                          ),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.glassBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              s.icon,
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.white70,
                              size: 24,
                            ),
                            const SizedBox(width: 16),
                            Text(
                              s.displayName,
                              style: AppTextStyles.label.copyWith(
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.white,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            const Spacer(),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                // Remove from library (if exists)
                if (current != null)
                  TextButton.icon(
                    onPressed: () {
                      ref
                          .read(watchStatusNotifierProvider.notifier)
                          .deleteAllStatusesForMedia(details.tmdbId.toString());
                      ref
                          .read(watchlistProvider.notifier)
                          .remove(details.tmdbId);
                      Navigator.pop(context);
                    },
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                    ),
                    label: Text(
                      'Remove from Library',
                      style: AppTextStyles.label.copyWith(
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                SizedBox(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          ),
        );
      },
    );
  }

  // (Removed _buildStatusDropdown as it is replaced by _buildLibraryAction)

  // ─── Episode Section (TV) ──────────────────────────────────────────────

  Widget _buildEpisodeSection(
    BuildContext context,
    MediaItem details,
    List<PluginManifest> plugins,
    String? preferredId,
  ) {
    final seasons = details.metadata.seasons;
    // Ensure selected season is valid
    final season = seasons.any((s) => s.seasonNumber == _selectedSeason)
        ? _selectedSeason
        : seasons.first.seasonNumber;

    final episodesAsync = ref.watch(
      tvSeasonEpisodesProvider((tvId: details.tmdbId, season: season)),
    );

    // Episode-item hook plugins
    final episodePluginsAsync = ref.watch(
      pluginsForHookProvider(TriggerHook.episodeItem),
    );
    final episodePlugins = episodePluginsAsync.value ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title + season selector
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Episodes', style: AppTextStyles.sectionTitle),
            if (seasons.length > 1)
              DropdownButton<int>(
                value: season,
                dropdownColor: AppColors.surfaceDark,
                underline: const SizedBox.shrink(),
                style: AppTextStyles.labelSmall,
                onChanged: (v) {
                  if (v != null) setState(() => _selectedSeason = v);
                },
                items: seasons.map((s) {
                  return DropdownMenuItem(
                    value: s.seasonNumber,
                    child: Text(
                      s.name ?? 'Season ${s.seasonNumber}',
                      style: AppTextStyles.labelSmall,
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Episode list
        episodesAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          ),
          error: (e, _) => Text(
            'Could not load episodes',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          data: (episodes) => Column(
            children: episodes.map((ep) {
              final epPlugin = _resolvePlugin(episodePlugins, preferredId);
              return _EpisodeRow(
                mediaId: details.tmdbId.toString(),
                episode: ep,
                plugins: episodePlugins,
                onPlay: epPlugin == null
                    ? null
                    : () => _executePlugin(
                        context,
                        epPlugin,
                        details,
                        season: ep.seasonNumber,
                        episode: ep.episodeNumber,
                      ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Opens the player for the next episode (e.g. after current ep is >= 95%).
  void _openNextEpisode(
    BuildContext context,
    MediaItem details,
    int season,
    int episode,
  ) {
    final plugins =
        ref
            .read(pluginsForHookProvider(TriggerHook.mediaHeader))
            .whenOrNull(data: (list) => list) ??
        [];
    if (plugins.isEmpty) return;
    final preferredId = ref.read(preferredPluginProvider);
    final plugin = _resolvePlugin(plugins, preferredId);
    if (plugin == null) return;
    final url = PluginUrlResolver.resolve(
      plugin,
      details,
      season: season,
      episode: episode,
    );
    if (!context.mounted) return;
    context.push(
      '/player',
      extra: PlayerArgs(
        url: url,
        media: details,
        pluginName: plugin.name,
        pluginId: plugin.pluginId,
        resumeTimeSeconds: 0,
        season: season,
        episode: episode,
      ),
    );
  }

  /// Opens the player from the beginning (season 1 episode 1 for TV).
  void _openFromStart(
    BuildContext context,
    MediaItem details,
    PluginManifest plugin,
  ) {
    final isTV = details.type == MediaType.tv;
    final url = PluginUrlResolver.resolve(
      plugin,
      details,
      season: isTV ? 1 : null,
      episode: isTV ? 1 : null,
    );
    if (!context.mounted) return;
    context.push(
      '/player',
      extra: PlayerArgs(
        url: url,
        media: details,
        pluginName: plugin.name,
        pluginId: plugin.pluginId,
        resumeTimeSeconds: 0,
        season: isTV ? 1 : null,
        episode: isTV ? 1 : null,
      ),
    );
  }

  /// Opens the player at the resume position for [progress].
  void _openContinue(
    BuildContext context,
    MediaItem details,
    UserProgress progress,
  ) {
    final plugins =
        ref
            .read(pluginsForHookProvider(TriggerHook.mediaHeader))
            .whenOrNull(data: (list) => list) ??
        [];
    if (plugins.isEmpty) return;
    final preferredId = ref.read(preferredPluginProvider);
    var activePlugin = plugins.first;
    if (progress.lastPluginId != null) {
      final match = plugins.where((p) => p.pluginId == progress.lastPluginId);
      if (match.isNotEmpty) activePlugin = match.first;
    } else if (preferredId != null) {
      final match = plugins.where((p) => p.pluginId == preferredId);
      if (match.isNotEmpty) activePlugin = match.first;
    }
    final url = PluginUrlResolver.resolve(
      activePlugin,
      details,
      season: progress.season ?? 1,
      episode: progress.episode ?? 1,
    );
    context.push(
      '/player',
      extra: PlayerArgs(
        url: url,
        media: details,
        pluginName: activePlugin.name,
        pluginId: activePlugin.pluginId,
        resumeTimeSeconds: progress.currentTime,
        season: progress.season,
        episode: progress.episode,
      ),
    );
  }

  // ─── Resolve Preferred Plugin ─────────────────────────────────────────

  /// Returns the user's preferred plugin if it's in [plugins], otherwise
  /// falls back to the first plugin.  Returns null if the list is empty.
  PluginManifest? _resolvePlugin(
    List<PluginManifest> plugins,
    String? preferredId,
  ) {
    if (plugins.isEmpty) return null;
    if (preferredId != null) {
      final match = plugins.where((p) => p.pluginId == preferredId);
      if (match.isNotEmpty) return match.first;
    }
    return plugins.first;
  }

  Future<void> _executePlugin(
    BuildContext context,
    PluginManifest plugin,
    MediaItem media, {
    int? season,
    int? episode,
  }) async {
    final url = PluginUrlResolver.resolve(
      plugin,
      media,
      season: season,
      episode: episode,
    );

    switch (plugin.actionType) {
      case ActionType.externalLink:
        final launched = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!launched && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Could not open link')));
        }
        break;
      case ActionType.webview:
        // Look up saved progress to auto-resume from last position.
        final repo = ref.read(watchHistoryRepositoryProvider);
        final saved = await repo.getProgress(
          media.tmdbId.toString(),
          season: season,
          episode: episode,
        );
        // Only resume if the user hasn't finished the content (< 95%).
        final resumeTime = (saved != null && saved.percentage < 95)
            ? saved.currentTime
            : 0.0;

        if (!context.mounted) return;
        context.push(
          '/player',
          extra: PlayerArgs(
            url: url,
            media: media,
            pluginName: plugin.name,
            pluginId: plugin.pluginId,
            resumeTimeSeconds: resumeTime,
            season: season,
            episode: episode,
          ),
        );
        break;
      case ActionType.metadataFetch:
        break;
    }
  }

  // ─── Trailer Chip ─────────────────────────────────────────────────────

  Widget _buildTrailerChip(String key) {
    final url = Uri.parse('https://www.youtube.com/watch?v=$key');

    return OutlinedButton.icon(
      onPressed: () async {
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open trailer')),
            );
          }
        }
      },
      icon: const Icon(Icons.play_circle_outline, size: 20),
      label: Text('Watch Trailer', style: AppTextStyles.labelSmall),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: AppColors.glassBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  // ─── Overview ─────────────────────────────────────────────────────────

  Widget _buildOverview(MediaItem details) {
    if (details.overview == null || details.overview!.isEmpty) {
      return const SizedBox.shrink();
    }

    return _ExpandableOverview(text: details.overview!);
  }

  // ─── Cast Row ─────────────────────────────────────────────────────────

  Widget _buildCastRow(List<CastMember> cast) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (_, index) {
          final member = cast[index];
          final profileUrl = buildImageUrl(
            member.profilePath,
            AppConfig.posterSmall,
          );

          return SizedBox(
            width: 72,
            child: Column(
              children: [
                // Avatar
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: ClipOval(
                    child: profileUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: profileUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: AppColors.surfaceDark),
                            errorWidget: (context, url, error) =>
                                Container(color: AppColors.surfaceDark),
                          )
                        : Container(
                            color: AppColors.surfaceDark,
                            child: const Icon(
                              Icons.person,
                              color: AppColors.textMuted,
                              size: 28,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                // Name
                Text(
                  member.name,
                  style: AppTextStyles.cardSubtitle.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (member.character != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    member.character!,
                    style: AppTextStyles.cardSubtitle.copyWith(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Expandable Overview ──────────────────────────────────────────────────

class _ExpandableOverview extends StatefulWidget {
  final String text;
  const _ExpandableOverview({required this.text});

  @override
  State<_ExpandableOverview> createState() => _ExpandableOverviewState();
}

class _ExpandableOverviewState extends State<_ExpandableOverview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedCrossFade(
        firstChild: Text(
          widget.text,
          style: AppTextStyles.body.copyWith(
            color: AppColors.textSecondary,
            height: 1.6,
          ),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        secondChild: Text(
          widget.text,
          style: AppTextStyles.body.copyWith(
            color: AppColors.textSecondary,
            height: 1.6,
          ),
        ),
        crossFadeState: _expanded
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 300),
      ),
    );
  }
}

// ─── Episode Row ──────────────────────────────────────────────────────────────

class _EpisodeRow extends ConsumerWidget {
  final String mediaId;
  final Episode episode;
  final List<PluginManifest> plugins;
  final VoidCallback? onPlay;

  const _EpisodeRow({
    required this.mediaId,
    required this.episode,
    required this.plugins,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stillUrl = buildImageUrl(episode.stillPath, AppConfig.backdropSmall);

    final statusAsync = ref.watch(
      mediaStatusProvider((
        mediaId: mediaId,
        season: episode.seasonNumber,
        episode: episode.episodeNumber,
      )),
    );

    final progressAsync = ref.watch(
      episodeProgressProvider((
        mediaId: mediaId,
        season: episode.seasonNumber,
        episode: episode.episodeNumber,
      )),
    );

    return progressAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ShimmerPlaceholder(
              width: 140,
              height: 120,
              borderRadius: BorderRadius.circular(20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ShimmerPlaceholder(height: 14, width: 60),
                  const SizedBox(height: 8),
                  const ShimmerPlaceholder(height: 16, width: 120),
                ],
              ),
            ),
          ],
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (progress) {
        final status = statusAsync.value?.status;
        final bool isWatched =
            status == WatchStatus.completed ||
            (progress != null && progress.percentage >= 95);
        final bool isWatching =
            !isWatched &&
            (status == WatchStatus.watching ||
                (progress != null && progress.percentage > 0));

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: InkWell(
            onTap: () {
              if (onPlay != null) {
                if (!isWatched && status != WatchStatus.watching) {
                  ref
                      .read(watchStatusNotifierProvider.notifier)
                      .setStatus(
                        MediaStatus(
                          mediaId: mediaId,
                          mediaType: 'tv',
                          status: WatchStatus.watching,
                          season: episode.seasonNumber,
                          episode: episode.episodeNumber,
                          updatedAt: DateTime.now(),
                        ),
                      );
                }
                onPlay!();
              } else if (!isWatched && !isWatching) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('No playback source configured'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.surfaceDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusBase,
                      ),
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isWatching
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : AppColors.glassBorder,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    isWatching
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.03),
                    Colors.white.withValues(alpha: 0.01),
                  ],
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- 1. Thumbnail + Play Overlay ---
                    Stack(
                      children: [
                        SizedBox(
                          width: 140,
                          height: 120,
                          child: stillUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: stillUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) =>
                                      const ShimmerPlaceholder(),
                                  errorWidget: (_, _, _) =>
                                      Container(color: AppColors.surfaceDark),
                                )
                              : Container(
                                  color: AppColors.surfaceDark,
                                  child: const Icon(
                                    Icons.tv_rounded,
                                    color: Colors.white24,
                                    size: 32,
                                  ),
                                ),
                        ),
                        // Watched Overlay
                        if (isWatched)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.primary,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                        // Simple Play hint if unwatched
                        if (!isWatched)
                          Positioned.fill(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black26,
                                  border: Border.all(
                                    color: Colors.white30,
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  isWatching
                                      ? Icons.play_arrow_rounded
                                      : Icons.play_arrow_outlined,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        // Progress Bar (Slim at the bottom)
                        if (isWatching)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 3,
                              color: Colors.white10,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: (progress?.percentage ?? 0 / 100)
                                      .clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                    // --- 2. Content Info ---
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(
                                  episode.label,
                                  style: AppTextStyles.tag.copyWith(
                                    color: isWatched
                                        ? AppColors.textMuted
                                        : AppColors.primary,
                                    letterSpacing: 1,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (isWatching) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${progress?.percentage.toInt()}%',
                                      style: AppTextStyles.tag.copyWith(
                                        color: AppColors.primary,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                _EpisodeStatusPicker(
                                  mediaId: mediaId,
                                  episode: episode,
                                  currentStatus: status,
                                  isWatchedByDefault:
                                      isWatched &&
                                      status != WatchStatus.completed,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              episode.name,
                              style: AppTextStyles.cardTitle.copyWith(
                                fontSize: 15,
                                color: isWatched
                                    ? Colors.white70
                                    : Colors.white,
                                fontWeight: isWatching
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (episode.overview != null &&
                                episode.overview!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                episode.overview!,
                                style: AppTextStyles.body.copyWith(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EpisodeStatusPicker extends ConsumerWidget {
  final String mediaId;
  final Episode episode;
  final WatchStatus? currentStatus;
  final bool isWatchedByDefault;

  const _EpisodeStatusPicker({
    required this.mediaId,
    required this.episode,
    this.currentStatus,
    this.isWatchedByDefault = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<WatchStatus?>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: (currentStatus != null || isWatchedByDefault)
            ? AppColors.primary
            : AppColors.textMuted,
      ),
      tooltip: 'Change status (always editable)',
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
      ),
      color: AppColors.surfaceDark,
      onSelected: (status) {
        if (status == null) {
          ref
              .read(watchStatusNotifierProvider.notifier)
              .deleteStatus(
                mediaId,
                season: episode.seasonNumber,
                episode: episode.episodeNumber,
              );
          return;
        }

        ref
            .read(watchStatusNotifierProvider.notifier)
            .setStatus(
              MediaStatus(
                mediaId: mediaId,
                mediaType: 'tv',
                status: status,
                season: episode.seasonNumber,
                episode: episode.episodeNumber,
                updatedAt: DateTime.now(),
              ),
            );
      },
      itemBuilder: (context) =>
          [
                null, // Clear status
                WatchStatus.watching,
                WatchStatus.completed,
                WatchStatus.planToWatch,
                WatchStatus.onHold,
                WatchStatus.dropped,
              ]
              .map(
                (s) => PopupMenuItem<WatchStatus?>(
                  value: s,
                  child: Row(
                    children: [
                      Icon(
                        s?.icon ?? Icons.delete_outline_rounded,
                        size: 18,
                        color: s == currentStatus
                            ? AppColors.primary
                            : Colors.white70,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        s == null
                            ? 'Reset Status'
                            : s == WatchStatus.completed
                            ? 'Mark Watched'
                            : s.displayName,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: s == currentStatus
                              ? AppColors.primary
                              : Colors.white,
                        ),
                      ),
                      const Spacer(),
                      if (s == currentStatus && s != null)
                        const Icon(
                          Icons.check,
                          color: AppColors.primary,
                          size: 16,
                        ),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }
}
