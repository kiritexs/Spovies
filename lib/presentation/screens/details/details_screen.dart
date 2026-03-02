import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
import '../../../plugins/protocol/action_type.dart';
import '../../../plugins/protocol/plugin_url_resolver.dart';
import 'package:go_router/go_router.dart';

import '../../../plugins/protocol/trigger_hook.dart';
import '../../providers/details_providers.dart';
import '../../providers/plugin_providers.dart';
import '../../providers/watchlist_providers.dart';
import '../../router/app_router.dart';
import '../../widgets/shimmer_placeholder.dart';

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

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: detailsAsync.when(
        loading: () => _buildLoading(context),
        error: (e, _) => _buildError(context, e.toString()),
        data: (details) =>
            _buildContent(context, details, pluginsAsync.value ?? []),
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
  ) {
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
              _buildActionRow(context, details, plugins),
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
                _buildEpisodeSection(context, details, plugins),
              ],
            ],
          ),
        ),
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
  ) {
    final isInWatchlist = ref.watch(
      watchlistProvider.select(
        (list) => list.any((m) => m.tmdbId == details.tmdbId),
      ),
    );

    return Row(
      children: [
        // Watch button (if plugin available)
        if (plugins.isNotEmpty)
          Expanded(
            child: Container(
              height: AppSpacing.buttonHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                boxShadow: AppColors.primaryGlowShadow,
              ),
              child: ElevatedButton.icon(
                onPressed: () =>
                    _executePlugin(context, plugins.first, details),
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  'Watch with ${plugins.first.name}',
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

        if (plugins.isNotEmpty) const SizedBox(width: 12),

        // Watchlist toggle button
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              height: AppSpacing.buttonHeight,
              width: AppSpacing.buttonHeight,
              decoration: BoxDecoration(
                color: isInWatchlist
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.glass,
                borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                border: Border.all(
                  color: isInWatchlist
                      ? AppColors.primary
                      : AppColors.glassBorder,
                ),
              ),
              child: IconButton(
                icon: Icon(
                  isInWatchlist
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: isInWatchlist ? AppColors.primary : Colors.white,
                  size: 20,
                ),
                onPressed: () =>
                    ref.read(watchlistProvider.notifier).toggle(details),
                tooltip: isInWatchlist
                    ? 'Remove from Watchlist'
                    : 'Add to Watchlist',
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Episode Section (TV) ──────────────────────────────────────────────

  Widget _buildEpisodeSection(
    BuildContext context,
    MediaItem details,
    List<PluginManifest> plugins,
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
              return _EpisodeRow(
                episode: ep,
                plugins: episodePlugins,
                onPlay: episodePlugins.isEmpty
                    ? null
                    : () => _executePlugin(
                          context,
                          episodePlugins.first,
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

  void _executePlugin(
    BuildContext context,
    PluginManifest plugin,
    MediaItem media, {
    int? season,
    int? episode,
  }) {
    final url = PluginUrlResolver.resolve(
      plugin,
      media,
      season: season,
      episode: episode,
    );

    switch (plugin.actionType) {
      case ActionType.externalLink:
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        break;
      case ActionType.webview:
        context.push(
          '/player',
          extra: PlayerArgs(url: url, media: media, pluginName: plugin.name),
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
      onPressed: () => launchUrl(url, mode: LaunchMode.externalApplication),
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

class _EpisodeRow extends StatelessWidget {
  final Episode episode;
  final List<PluginManifest> plugins;
  final VoidCallback? onPlay;

  const _EpisodeRow({
    required this.episode,
    required this.plugins,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final stillUrl = buildImageUrl(episode.stillPath, AppConfig.backdropSmall);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Episode thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
            child: SizedBox(
              width: 120,
              height: 68,
              child: stillUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: stillUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.surfaceDark,
                      ),
                      errorWidget: (_, __, ___) =>
                          Container(color: AppColors.surfaceDark),
                    )
                  : Container(
                      color: AppColors.surfaceDark,
                      child: const Icon(
                        Icons.tv_rounded,
                        color: AppColors.textMuted,
                        size: 24,
                      ),
                    ),
            ),
          ),

          const SizedBox(width: 12),

          // Episode info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  episode.label,
                  style: AppTextStyles.tag.copyWith(
                    color: AppColors.primary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  episode.name,
                  style: AppTextStyles.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (episode.formattedRuntime.isNotEmpty)
                  Text(
                    episode.formattedRuntime,
                    style: AppTextStyles.cardSubtitle,
                  ),
                if (episode.overview != null &&
                    episode.overview!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    episode.overview!,
                    style: AppTextStyles.cardSubtitle.copyWith(fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Play button
          if (onPlay != null)
            IconButton(
              onPressed: onPlay,
              icon: const Icon(
                Icons.play_circle_outline_rounded,
                color: AppColors.primary,
                size: 28,
              ),
              tooltip: 'Play ${episode.label}',
            ),
        ],
      ),
    );
  }
}
