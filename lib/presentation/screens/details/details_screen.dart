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
import '../../providers/settings_providers.dart';
import '../../providers/watch_history_providers.dart';
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
    final preferredId = ref.watch(preferredPluginProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: detailsAsync.when(
        loading: () => _buildLoading(context),
        error: (e, _) => _buildError(context, e.toString()),
        data: (details) => LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 900;
            return _buildContent(
              context,
              details,
              pluginsAsync.value ?? [],
              preferredId,
              isDesktop,
            );
          },
        ),
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
    bool isDesktop,
  ) {
    if (isDesktop) {
      return _buildDesktopContent(context, details, plugins, preferredId);
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
              _buildActionRow(context, details, plugins, preferredId),
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
    String? preferredId,
  ) {
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
            child: Container(color: Colors.black.withOpacity(0.4)),
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
    String? preferredId,
  ) {
    final activePlugin = _resolvePlugin(plugins, preferredId);
    final isTV = details.type == MediaType.tv;
    final isInWatchlist = ref.watch(
      watchlistProvider.select(
        (list) => list.any((m) => m.tmdbId == details.tmdbId),
      ),
    );

    return Row(
      children: [
        if (activePlugin != null)
          SizedBox(
            width: 280,
            height: 56,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.primaryGlowShadow,
              ),
              child: ElevatedButton.icon(
                onPressed: () => _executePlugin(context, activePlugin, details),
                icon: const Icon(Icons.play_arrow_rounded, size: 28),
                label: Text(
                  isTV ? 'Watch Series' : 'Watch Movie',
                  style: AppTextStyles.label.copyWith(fontSize: 18),
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
        const SizedBox(width: 16),
        // Watchlist
        _buildCircularDesktopAction(
          icon: isInWatchlist
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          color: isInWatchlist ? AppColors.primary : Colors.white,
          onPressed: () => ref.read(watchlistProvider.notifier).toggle(details),
          isActive: isInWatchlist,
        ),
        const SizedBox(width: 12),
        // Trailer
        if (details.metadata.trailerKey != null)
          _buildCircularDesktopAction(
            icon: Icons.movie_outlined,
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
          ),
      ],
    );
  }

  Widget _buildCircularDesktopAction({
    required IconData icon,
    required VoidCallback onPressed,
    Color color = Colors.white,
    bool isActive = false,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withOpacity(0.15)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AppColors.primary : Colors.white.withOpacity(0.15),
          width: 1.5,
        ),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 24),
        onPressed: onPressed,
      ),
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
    String? preferredId,
  ) {
    final activePlugin = _resolvePlugin(plugins, preferredId);
    final isInWatchlist = ref.watch(
      watchlistProvider.select(
        (list) => list.any((m) => m.tmdbId == details.tmdbId),
      ),
    );

    return Row(
      children: [
        // Watch button (if plugin available)
        if (activePlugin != null)
          Expanded(
            child: Container(
              height: AppSpacing.buttonHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                boxShadow: AppColors.primaryGlowShadow,
              ),
              child: ElevatedButton.icon(
                onPressed: () => _executePlugin(context, activePlugin, details),
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: Text(
                  'Watch with ${activePlugin.name}',
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

        if (activePlugin != null) const SizedBox(width: 12),

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open link')),
          );
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
        // Only resume if the user hasn't finished the content (< 90%).
        final resumeTime = (saved != null && saved.percentage < 90)
            ? saved.currentTime
            : 0.0;

        if (!context.mounted) return;
        context.push(
          '/player',
          extra: PlayerArgs(
            url: url,
            media: media,
            pluginName: plugin.name,
            resumeTimeSeconds: resumeTime,
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
                      placeholder: (_, __) =>
                          Container(color: AppColors.surfaceDark),
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
