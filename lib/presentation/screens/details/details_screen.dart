import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/feature_flags.dart';
import '../../widgets/app_snack_bar.dart';
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

part 'details_overview.dart';
part 'details_episode_row.dart';

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

  /// Long seasons (some shows have 100+ episodes) build the first
  /// [_episodePage] rows, then the rest on request.
  static const int _episodePage = 25;
  bool _showAllEpisodes = false;

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

    // While the full details load (or if they fail), show the list item we
    // were opened with: title, poster, overview and rating are already
    // known. Cast, seasons and similar sections fill in when it arrives.
    final details = detailsAsync.value ?? media;
    final failed = detailsAsync.hasError && !detailsAsync.hasValue;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          Builder(
            builder: (context) {
              final cwList =
                  ref
                      .watch(continueWatchingProvider)
                      .whenOrNull(data: (list) => list) ??
                  [];
              UserProgress? continueProgress;
              for (final p in cwList) {
                // Match the type too: a movie and a show can share an id.
                if (p.mediaId == details.tmdbId.toString() &&
                    p.mediaType == details.type.name) {
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
          if (detailsAsync.isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.primaryOnDark,
                backgroundColor: Colors.transparent,
              ),
            ),
          if (failed) _buildErrorBanner(context, isTV),
        ],
      ),
    );
  }

  // ─── Error ────────────────────────────────────────────────────────────

  /// Shown over the partial content when the full details fail to load.
  Widget _buildErrorBanner(BuildContext context, bool isTV) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 16,
      child: Material(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Couldn\'t load the full details.',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => isTV
                    ? ref.invalidate(tvDetailsProvider(media.tmdbId))
                    : ref.invalidate(movieDetailsProvider(media.tmdbId)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryOnDark,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Error ────────────────────────────────────────────────────────────

  // ─── Main Content ─────────────────────────────────────────────────────

  Widget _buildContent(
    BuildContext context,
    MediaItem details,
    List<PluginManifest> plugins,
    String? preferredId,
    bool isDesktop, {
    UserProgress? continueProgress,
    Episode? nextEpisode,
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
    Episode? nextEpisode,
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
                          placeholder: (_, _) => const ShimmerPlaceholder(),
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
                            color: AppColors.primaryOnDark,
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
    Episode? nextEpisode,
  }) {
    final activePlugin = PluginUrlResolver.pickPlugin(
      plugins,
      preferredId: preferredId,
    );
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
    final showWatch = _showWatch(activePlugin, showResume, showNextEp);

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
                      _openContinue(context, details, continueProgress),
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
                nextEpisode.seasonNumber,
                nextEpisode.episodeNumber,
              ),
              icon: const Icon(Icons.skip_next_rounded, size: 24),
              label: Text(
                'Start next (S${nextEpisode.seasonNumber} E${nextEpisode.episodeNumber})',
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
        if (showWatch) ...[
          SizedBox(
            width: 220,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _watchAction(context, activePlugin, details),
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: Text(
                isTV ? 'Watch Series' : 'Watch Movie',
                style: AppTextStyles.label.copyWith(fontSize: 16),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _watchForeground,
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
              tooltip: 'Back',
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
            const Icon(
              Icons.star_rounded,
              color: AppColors.primaryOnDark,
              size: 16,
            ),
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

  /// The plain Watch button shows when there's no Continue / Next button.
  /// With playback disabled it still shows, muted, so the action is
  /// discoverable and explains itself on tap.
  bool _showWatch(
    PluginManifest? activePlugin,
    bool showResume,
    bool showNextEp,
  ) => !showResume && !showNextEp && (activePlugin != null || !kPluginsEnabled);

  static const Color _watchForeground = kPluginsEnabled
      ? Colors.white
      : AppColors.textSecondary;

  VoidCallback _watchAction(
    BuildContext context,
    PluginManifest? activePlugin,
    MediaItem details,
  ) {
    if (!kPluginsEnabled || activePlugin == null) {
      return () => showPlaybackUnavailableSnack(context);
    }
    return () => _executePlugin(context, activePlugin, details);
  }

  Widget _buildActionRow(
    BuildContext context,
    MediaItem details,
    List<PluginManifest> plugins,
    String? preferredId, {
    UserProgress? continueProgress,
    Episode? nextEpisode,
  }) {
    final activePlugin = PluginUrlResolver.pickPlugin(
      plugins,
      preferredId: preferredId,
    );
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
    final showWatch = _showWatch(activePlugin, showResume, showNextEp);

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
                    _openContinue(context, details, continueProgress),
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
                  nextEpisode.seasonNumber,
                  nextEpisode.episodeNumber,
                ),
                icon: const Icon(Icons.skip_next_rounded, size: 24),
                label: Text(
                  'Start next (S${nextEpisode.seasonNumber} E${nextEpisode.episodeNumber})',
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

        if (showWatch)
          Expanded(
            child: Container(
              height: AppSpacing.buttonHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: OutlinedButton.icon(
                onPressed: _watchAction(context, activePlugin, details),
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  details.type == MediaType.tv ? 'Watch Series' : 'Watch Movie',
                  style: AppTextStyles.label,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _watchForeground,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: const BorderSide(color: AppColors.glassBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                  ),
                ),
              ),
            ),
          ),

        if (showResume || showNextEp || showWatch) const SizedBox(width: 12),

        // Consolidated Library/Status Button
        Expanded(child: _buildLibraryAction(context, details)),
      ],
    );
  }

  Widget _buildLibraryAction(BuildContext context, MediaItem details) {
    final statusAsync = ref.watch(
      mediaStatusProvider((
        mediaId: details.tmdbId.toString(),
        mediaType: details.type.name,
        season: null,
        episode: null,
      )),
    );

    final saved = ref
        .watch(watchlistProvider)
        .any((m) => m.tmdbId == details.tmdbId && m.type == details.type);

    return statusAsync.when(
      data: (current) {
        // Saved with no status yet (e.g. from Home's "+") is in the Library.
        final isInLibrary = current != null || saved;
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
                    current?.status.icon ??
                        (saved
                            ? Icons.bookmark_rounded
                            : Icons.playlist_add_rounded),
                    color: isInLibrary
                        ? AppColors.primaryOnDark
                        : Colors.white70,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      current?.status.displayName ??
                          (saved ? 'In Library' : 'Add to Library'),
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isInLibrary
                            ? AppColors.primaryOnDark
                            : Colors.white70,
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
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Future<bool?> _confirmRemove(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text('Remove from Library?', style: AppTextStyles.sectionTitle),
        content: Text(
          'This also clears its watch status and progress.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showLibraryStatusModal(
    BuildContext context,
    MediaItem details,
    MediaStatus? current,
  ) {
    unawaited(
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
                        color: AppColors.primaryOnDark,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Update Library Status',
                        style: AppTextStyles.sectionTitle.copyWith(
                          fontSize: 18,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Close',
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
                          unawaited(
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
                                ),
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
                                  ? AppColors.primaryOnDark
                                  : AppColors.glassBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                s.icon,
                                color: isSelected
                                    ? AppColors.primaryOnDark
                                    : Colors.white70,
                                size: 24,
                              ),
                              const SizedBox(width: 16),
                              Text(
                                s.displayName,
                                style: AppTextStyles.label.copyWith(
                                  color: isSelected
                                      ? AppColors.primaryOnDark
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
                                  color: AppColors.primaryOnDark,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  // Remove from library (if saved or tracked)
                  if (current != null ||
                      ref.read(watchlistProvider.notifier).contains(details))
                    TextButton.icon(
                      onPressed: () async {
                        final sheet = Navigator.of(context);
                        final confirmed = await _confirmRemove(context);
                        if (confirmed != true) return;
                        // The notifier also drops watch progress and refreshes
                        // Continue Watching, so the title leaves every list.
                        unawaited(
                          ref
                              .read(watchStatusNotifierProvider.notifier)
                              .deleteAllStatusesForMedia(
                                details.tmdbId.toString(),
                                mediaType: details.type.name,
                              ),
                        );
                        ref.read(watchlistProvider.notifier).remove(details);
                        if (sheet.mounted) sheet.pop();
                      },
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.danger,
                      ),
                      label: Text(
                        'Remove from Library',
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          );
        },
      ),
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
                  if (v != null) {
                    setState(() {
                      _selectedSeason = v;
                      _showAllEpisodes = false;
                    });
                  }
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
            children: [
              ...(_showAllEpisodes || episodes.length <= _episodePage
                      ? episodes
                      : episodes.take(_episodePage))
                  .map((ep) {
                    final epPlugin = PluginUrlResolver.pickPlugin(
                      episodePlugins,
                      preferredId: preferredId,
                    );
                    return _EpisodeRow(
                      mediaId: details.tmdbId.toString(),
                      show: details,
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
                  }),
              if (!_showAllEpisodes && episodes.length > _episodePage)
                TextButton(
                  onPressed: () => setState(() => _showAllEpisodes = true),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryOnDark,
                  ),
                  child: Text('Show all ${episodes.length} episodes'),
                ),
            ],
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
    if (!kPluginsEnabled) {
      showPlaybackUnavailableSnack(context);
      return;
    }
    final plugins =
        ref
            .read(pluginsForHookProvider(TriggerHook.mediaHeader))
            .whenOrNull(data: (list) => list) ??
        [];
    if (plugins.isEmpty) return;
    final preferredId = ref.read(preferredPluginProvider);
    final plugin = PluginUrlResolver.pickPlugin(
      plugins,
      preferredId: preferredId,
    );
    if (plugin == null) return;
    final url = PluginUrlResolver.resolve(
      plugin,
      details,
      season: season,
      episode: episode,
    );
    if (!context.mounted) return;
    unawaited(
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
      ),
    );
  }

  /// Opens the player from the beginning (season 1 episode 1 for TV).
  void _openFromStart(
    BuildContext context,
    MediaItem details,
    PluginManifest plugin,
  ) {
    if (!kPluginsEnabled) {
      showPlaybackUnavailableSnack(context);
      return;
    }
    final isTV = details.type == MediaType.tv;
    final url = PluginUrlResolver.resolve(
      plugin,
      details,
      season: isTV ? 1 : null,
      episode: isTV ? 1 : null,
    );
    if (!context.mounted) return;
    unawaited(
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
      ),
    );
  }

  /// Opens the player at the resume position for [progress].
  void _openContinue(
    BuildContext context,
    MediaItem details,
    UserProgress progress,
  ) {
    if (!kPluginsEnabled) {
      showPlaybackUnavailableSnack(context);
      return;
    }
    final plugins =
        ref
            .read(pluginsForHookProvider(TriggerHook.mediaHeader))
            .whenOrNull(data: (list) => list) ??
        [];
    // pickPlugin handles savedId/preferredId fallback in one place — keeping
    // it centralised so the resolution order can't drift between call sites.
    final activePlugin = PluginUrlResolver.pickPlugin(
      plugins,
      savedId: progress.lastPluginId,
      preferredId: ref.read(preferredPluginProvider),
    );
    if (activePlugin == null) return;
    final url = PluginUrlResolver.resolve(
      activePlugin,
      details,
      season: progress.season ?? 1,
      episode: progress.episode ?? 1,
    );
    unawaited(
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
      ),
    );
  }

  Future<void> _executePlugin(
    BuildContext context,
    PluginManifest plugin,
    MediaItem media, {
    int? season,
    int? episode,
  }) async {
    if (!kPluginsEnabled) {
      showPlaybackUnavailableSnack(context);
      return;
    }
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
          mediaType: media.type.name,
          season: season,
          episode: episode,
        );
        // Only resume if the user hasn't finished the content (< 95%).
        final resumeTime = (saved != null && saved.percentage < 95)
            ? saved.currentTime
            : 0.0;

        if (!context.mounted) return;
        unawaited(
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
          // Use the State's `mounted` (not context.mounted) so the lint can
          // see the guard is tied to this widget's own lifecycle.
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open trailer')),
          );
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
