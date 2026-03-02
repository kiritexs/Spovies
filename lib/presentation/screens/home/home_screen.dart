import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:spovies/domain/entities/media_item.dart';
import 'package:spovies/presentation/providers/media_providers.dart';
import 'package:spovies/presentation/widgets/app_header.dart';
import 'package:spovies/presentation/widgets/continue_watching_card.dart';
import 'package:spovies/presentation/widgets/glass_bottom_nav.dart';
import 'package:spovies/presentation/widgets/hero_card.dart';
import 'package:spovies/presentation/widgets/media_row.dart';
import 'package:spovies/presentation/widgets/shimmer_placeholder.dart';
import 'package:spovies/presentation/screens/settings/settings_screen.dart';
import 'package:spovies/presentation/screens/details/details_screen.dart';
import 'package:spovies/presentation/screens/search/search_screen.dart';
import 'package:spovies/presentation/screens/watchlist/watchlist_screen.dart';
import 'package:spovies/presentation/providers/watch_history_providers.dart';
import 'package:spovies/core/utils/tmdb_image_url.dart';
import 'package:spovies/core/config/app_config.dart';
import 'package:spovies/core/theme/app_spacing.dart';
import 'package:spovies/core/theme/app_text_styles.dart';
import 'package:spovies/core/theme/app_colors.dart';
import 'package:spovies/domain/entities/media_type.dart';

/// Main home screen — cinematic layout matching stitch/code.html.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ─── Scrollable Content ────────────────
          _buildContent(),

          // ─── Fixed Header ──────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppHeader(
              onSearchTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              },
            ),
          ),

          // ─── Glass Bottom Nav ──────────────────
          GlassBottomNav(
            currentIndex: _navIndex,
          onTap: (index) {
            if (index == 3) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            } else if (index == 1) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              );
            } else if (index == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WatchlistScreen()),
              );
            } else {
              setState(() => _navIndex = index);
            }
          },
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final trendingAsync = ref.watch(trendingMoviesProvider);
    final topRatedAsync = ref.watch(topRatedMoviesProvider);
    final genreMapAsync = ref.watch(genreMapProvider);

    final genreMap = genreMapAsync.value ?? {};

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top padding for header
          SizedBox(height: MediaQuery.of(context).padding.top + 80),

          // ─── Hero Featured Card ────────────────
          trendingAsync.when(
            data: (movies) => movies.isNotEmpty
                ? HeroCard(
                    movie: movies.first,
                    genreText: _resolveGenres(movies.first, genreMap),
                  )
                : const SizedBox.shrink(),
            loading: () => const HeroCardShimmer(),
            error: (_, __) => _buildErrorCard(),
          ),

          const SizedBox(height: 32),

          // ─── Now Trending Row ──────────────────
          trendingAsync.when(
            data: (movies) => MediaRow(
              title: 'Now Trending',
              movies: movies.length > 1 ? movies.sublist(1) : movies,
              genreMap: genreMap,
              onMovieTap: _onMovieTap,
            ),
            loading: () => MediaRow(
              title: 'Now Trending',
              movies: const [],
              isLoading: true,
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 32),

          // ─── Continue Watching (Live) ───────
          _buildContinueWatching(),

          const SizedBox(height: 32),

          // ─── Top Rated Row ─────────────────────
          topRatedAsync.when(
            data: (movies) => MediaRow(
              title: 'Top Rated',
              movies: movies,
              genreMap: genreMap,
              onMovieTap: _onMovieTap,
            ),
            loading: () =>
                MediaRow(title: 'Top Rated', movies: const [], isLoading: true),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // Bottom padding for glass nav
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.white54, size: 48),
              SizedBox(height: 16),
              Text(
                'Failed to load content.\nCheck your API key.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContinueWatching() {
    final cwAsync = ref.watch(continueWatchingProvider);

    return cwAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: AppSpacing.sectionPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Continue Watching', style: AppTextStyles.sectionTitle),
                  if (items.length > 1)
                    Text(
                      '${items.length} items',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Horizontal list of cards
              ...items.map((item) {
                final thumbUrl = buildImageUrl(
                  item.posterPath,
                  AppConfig.posterSmall,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ContinueWatchingCard(
                    title: item.title,
                    remainingTime: item.remainingTime,
                    progress: (item.percentage / 100).clamp(0.0, 1.0),
                    thumbnailUrl: thumbUrl,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetailsScreen(
                            media: MediaItem(
                              id: item.mediaId,
                              tmdbId: int.tryParse(item.mediaId) ?? 0,
                              type: MediaType.fromString(item.mediaType),
                              title: item.title,
                              posterPath: item.posterPath,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _onMovieTap(MediaItem movie) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailsScreen(media: movie)),
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
