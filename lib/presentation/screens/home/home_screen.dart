import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:spovies/core/config/app_config.dart';
import 'package:spovies/core/config/feature_flags.dart';
import 'package:spovies/presentation/widgets/app_snack_bar.dart';
import 'package:spovies/core/theme/app_colors.dart';
import 'package:spovies/core/theme/app_spacing.dart';
import 'package:spovies/core/theme/app_text_styles.dart';
import 'package:spovies/core/utils/responsive_grid.dart';
import 'package:spovies/core/utils/tmdb_image_url.dart';
import 'package:spovies/domain/entities/media_item.dart';
import 'package:spovies/domain/entities/media_type.dart';
import 'package:spovies/domain/entities/user_progress.dart';
import 'package:spovies/plugins/protocol/plugin_url_resolver.dart';
import 'package:spovies/plugins/protocol/trigger_hook.dart';
import 'package:spovies/presentation/providers/details_providers.dart';
import 'package:spovies/presentation/providers/media_providers.dart';
import 'package:spovies/presentation/providers/plugin_providers.dart';
import 'package:spovies/presentation/providers/settings_providers.dart';
import 'package:spovies/presentation/providers/watch_history_providers.dart';
import 'package:spovies/presentation/providers/watchlist_providers.dart';
import 'package:spovies/presentation/screens/explore/all_media_screen.dart';
import 'package:spovies/presentation/providers/tab_provider.dart';
import 'package:spovies/presentation/router/app_router.dart';
import 'package:spovies/presentation/widgets/app_header.dart';
import 'package:spovies/presentation/widgets/continue_watching_card.dart';
import 'package:spovies/presentation/widgets/hero_card.dart';
import 'package:spovies/presentation/widgets/media_row.dart';
import 'package:spovies/presentation/widgets/retry_row.dart';
import 'package:spovies/presentation/widgets/shimmer_placeholder.dart';

/// Home tab — cinematic layout with Hero, Trending, Continue Watching,
/// and Top Rated rows.
///
/// Navigation:
///   - Details  → context.push('/details', extra: media)   (top-level route)
///   - Search   → writes currentTabProvider = 1            (switches IndexedStack)
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      extendBodyBehindAppBar: true,
      extendBody: true,
      body: Stack(
        children: [
          // ─── Scrollable content ──────────────────────────────────
          _HomeContent(),

          // ─── Fixed header overlay ────────────────────────────────
          Positioned(
            top: -30,
            left: 0,
            right: 0,
            child: AppHeader(
              // Switch to the Explore (search) tab. With the new
              // MainScaffold + IndexedStack architecture, tab switching
              // is just a provider write — no URL hop required.
              onSearchTap: () =>
                  ref.read(currentTabProvider.notifier).state = 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Scrollable Content ───────────────────────────────────────────────────────

class _HomeContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendingAsync = ref.watch(trendingMoviesProvider);
    final topRatedAsync = ref.watch(topRatedMoviesProvider);
    final genreMapAsync = ref.watch(genreMapProvider);
    final genreMap = genreMapAsync.value ?? {};

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Space for the fixed header
          SizedBox(height: MediaQuery.of(context).padding.top + 80),

          // ── Hero ────────────────────────────────────────────────
          trendingAsync.when(
            data: (movies) {
              if (movies.isEmpty) return const SizedBox.shrink();
              final hero = movies.first;
              final saved = ref
                  .watch(watchlistProvider)
                  .any((m) => m.tmdbId == hero.tmdbId && m.type == hero.type);
              return HeroCard(
                movie: hero,
                genreText: _resolveGenres(hero, genreMap),
                inLibrary: saved,
                onTap: () => context.push('/details', extra: hero),
                onAddTap: () {
                  if (saved) {
                    context.push('/details', extra: hero);
                    return;
                  }
                  ref.read(watchlistProvider.notifier).add(hero);
                  showAppSnackBar(context, 'Added to Library', aboveNav: true);
                },
              );
            },
            loading: () => const HeroCardShimmer(),
            error: (_, _) => _ErrorCard(
              onRetry: () {
                ref.invalidate(trendingMoviesProvider);
                ref.invalidate(topRatedMoviesProvider);
              },
            ),
          ),

          const SizedBox(height: 32),

          // ── Now Trending ─────────────────────────────────────────
          trendingAsync.when(
            data: (movies) => MediaRow(
              title: 'Now Trending',
              movies: movies.length > 1 ? movies.sublist(1) : movies,
              genreMap: genreMap,
              onMovieTap: (m) => context.push('/details', extra: m),
              onSeeAllTap: () => context.push(
                '/all-media',
                extra: AllMediaArgs(
                  title: 'Now Trending',
                  category: BrowseCategory.trendingMovies,
                  genreMap: genreMap,
                ),
              ),
            ),
            loading: () => const MediaRow(
              title: 'Now Trending',
              movies: [],
              isLoading: true,
            ),
            error: (_, _) => RetryRow(
              title: 'Now Trending',
              onRetry: () => ref.invalidate(trendingMoviesProvider),
            ),
          ),

          const SizedBox(height: 32),

          // ── Continue Watching ────────────────────────────────────
          _ContinueWatchingSection(),

          const SizedBox(height: 32),

          // ── Top Rated ────────────────────────────────────────────
          topRatedAsync.when(
            data: (movies) => MediaRow(
              title: 'Top Rated',
              movies: movies,
              genreMap: genreMap,
              onMovieTap: (m) => context.push('/details', extra: m),
              onSeeAllTap: () => context.push(
                '/all-media',
                extra: AllMediaArgs(
                  title: 'Top Rated',
                  category: BrowseCategory.topRatedMovies,
                  genreMap: genreMap,
                ),
              ),
            ),
            loading: () =>
                const MediaRow(title: 'Top Rated', movies: [], isLoading: true),
            error: (_, _) => RetryRow(
              title: 'Top Rated',
              onRetry: () => ref.invalidate(topRatedMoviesProvider),
            ),
          ),

          // Bottom padding clears the floating nav bar
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  String _resolveGenres(MediaItem movie, Map<int, String> genreMap) {
    if (movie.metadata.genres.isNotEmpty) {
      return movie.metadata.genres.take(2).join(' • ');
    }
    final ids = movie.metadata.genreIds;
    if (ids.isEmpty || genreMap.isEmpty) return movie.type.displayName;
    return ids
        .take(2)
        .map((id) => genreMap[id] ?? '')
        .where((n) => n.isNotEmpty)
        .join(' • ');
  }
}

// ─── Continue Watching (open player at resume position) ─────────────────────

Future<void> _continueWatching(
  BuildContext context,
  WidgetRef ref,
  UserProgress item,
) async {
  if (!kPluginsEnabled) {
    showPlaybackUnavailableSnack(context, aboveNav: true);
    return;
  }
  final tmdbId = int.tryParse(item.mediaId);
  if (tmdbId == null || tmdbId == 0) return;

  final mediaType = MediaType.fromString(item.mediaType);
  final detailsAsync = ref.read(
    mediaDetailsProvider((tmdbId: tmdbId, type: mediaType)).future,
  );

  MediaItem media;
  try {
    media = await detailsAsync;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
    return;
  }

  final plugins = await ref.read(
    pluginsForHookProvider(TriggerHook.mediaHeader).future,
  );
  if (plugins.isEmpty && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No watch plugin available')));
    return;
  }

  final activePlugin = PluginUrlResolver.pickPlugin(
    plugins,
    savedId: item.lastPluginId,
    preferredId: ref.read(preferredPluginProvider),
  );
  if (activePlugin == null) return;

  final url = PluginUrlResolver.resolve(
    activePlugin,
    media,
    season: item.season ?? 1,
    episode: item.episode ?? 1,
  );

  if (!context.mounted) return;
  // Fire-and-forget — GoRouter's push returns Future<T?> tracking the route
  // result, but the caller doesn't need it.
  unawaited(
    context.push(
      '/player',
      extra: PlayerArgs(
        url: url,
        media: media,
        pluginName: activePlugin.name,
        pluginId: activePlugin.pluginId,
        resumeTimeSeconds: item.currentTime,
        season: item.season,
        episode: item.episode,
      ),
    ),
  );
}

/// Opens player for the next episode (used when current ep is >= 95%).
Future<void> _openNextEpisode(
  BuildContext context,
  WidgetRef ref,
  UserProgress item,
  int nextSeason,
  int nextEpisode,
) async {
  if (!kPluginsEnabled) {
    showPlaybackUnavailableSnack(context, aboveNav: true);
    return;
  }
  final tmdbId = int.tryParse(item.mediaId);
  if (tmdbId == null || tmdbId == 0) return;
  final detailsAsync = ref.read(
    mediaDetailsProvider((tmdbId: tmdbId, type: MediaType.tv)).future,
  );
  MediaItem media;
  try {
    media = await detailsAsync;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not load show')));
    }
    return;
  }
  final plugins = await ref.read(
    pluginsForHookProvider(TriggerHook.mediaHeader).future,
  );
  if (plugins.isEmpty && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No watch plugin available')));
    return;
  }
  final activePlugin = PluginUrlResolver.pickPlugin(
    plugins,
    preferredId: ref.read(preferredPluginProvider),
  );
  if (activePlugin == null) return;
  final url = PluginUrlResolver.resolve(
    activePlugin,
    media,
    season: nextSeason,
    episode: nextEpisode,
  );
  if (!context.mounted) return;
  unawaited(
    context.push(
      '/player',
      extra: PlayerArgs(
        url: url,
        media: media,
        pluginName: activePlugin.name,
        pluginId: activePlugin.pluginId,
        resumeTimeSeconds: 0,
        season: nextSeason,
        episode: nextEpisode,
      ),
    ),
  );
}

// ─── Single Continue Watching card (resolves next-episode for completed TV) ───

class _ContinueWatchingCardItem extends ConsumerWidget {
  final UserProgress item;

  const _ContinueWatchingCardItem({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextEpisodeAsync = ref.watch(nextEpisodeForProgressProvider(item));
    final nextEpisode = nextEpisodeAsync.value;
    final isCompleted = item.percentage >= 95;
    final isTV = item.mediaType == 'tv';

    String remainingTime;
    VoidCallback? onContinueTap;
    if (!isCompleted) {
      remainingTime = item.remainingTime;
      onContinueTap = () => _continueWatching(context, ref, item);
    } else if (isTV && nextEpisode != null) {
      remainingTime =
          'Next: S${nextEpisode.seasonNumber} E${nextEpisode.episodeNumber}';
      onContinueTap = () => _openNextEpisode(
        context,
        ref,
        item,
        nextEpisode.seasonNumber,
        nextEpisode.episodeNumber,
      );
    } else {
      remainingTime = isTV ? 'Up to date' : 'Finished';
      onContinueTap = null;
    }

    final thumbUrl = buildImageUrl(item.posterPath, AppConfig.posterSmall);
    final mediaItem = MediaItem(
      id: item.mediaId,
      tmdbId: int.tryParse(item.mediaId) ?? 0,
      type: MediaType.fromString(item.mediaType),
      title: item.title,
      posterPath: item.posterPath,
    );

    return ContinueWatchingCard(
      title: item.title,
      remainingTime: remainingTime,
      progress: (item.percentage / 100).clamp(0.0, 1.0),
      thumbnailUrl: thumbUrl,
      episodeLabel: (item.season != null && item.episode != null)
          ? 'S${item.season} E${item.episode}'
          : null,
      onTap: () => context.push('/details', extra: mediaItem),
      onContinueTap: onContinueTap,
    );
  }
}

// ─── Continue Watching Section ────────────────────────────────────────────────

class _ContinueWatchingSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cwAsync = ref.watch(continueWatchingProvider);

    return cwAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: AppSpacing.sectionPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Continue Watching', style: AppTextStyles.sectionTitle),
                  if (items.length > 1)
                    Text(
                      '${items.length} items',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primaryOnDark,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  // Grid only when two cards fit side by side comfortably;
                  // measured on the content width, not the window (the
                  // desktop side nav takes 250px of the window).
                  if (constraints.maxWidth < 720) {
                    return Column(
                      children: [
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ContinueWatchingCardItem(item: item),
                          ),
                      ],
                    );
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: continueWatchingColumns(
                        constraints.maxWidth,
                      ),
                      mainAxisExtent: AppSpacing.continueWatchingHeight,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 12,
                    ),
                    itemBuilder: (context, index) =>
                        _ContinueWatchingCardItem(item: items[index]),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Small Error Widgets ──────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white54, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Failed to load content.\nCheck your connection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryOnDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
