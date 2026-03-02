import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/tmdb_image_url.dart';
import '../../../domain/entities/media_item.dart';
import '../../providers/media_providers.dart';
import '../../providers/search_providers.dart';
import '../../widgets/media_card.dart';
import '../../widgets/media_row.dart';
import '../../widgets/shimmer_placeholder.dart';

/// Full Discovery / Explore tab.
///
/// Layout:
///  • Sticky glass search bar at the top
///  • [Empty query] — Discovery mode:
///      - Trending section with Movie ↔ TV chip toggle
///      - Genre filter chips (horizontal scroll)
///      - If genre selected → genre results grid (movies + TV columns)
///      - If no genre   → Popular Movies row + Popular TV Shows row
///  • [Non-empty query] — Search mode:
///      - Debounced TMDB multi-search results grid
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSearching = false;

  /// null = no genre filter active
  int? _selectedGenreId;
  String? _selectedGenreName;

  /// Movie | TV toggle for Trending section
  bool _trendingMovies = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    ref.read(searchQueryProvider.notifier).update(query);
    setState(() => _isSearching = query.trim().isNotEmpty);
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).update('');
    setState(() => _isSearching = false);
  }

  void _selectGenre(int id, String name) {
    setState(() {
      if (_selectedGenreId == id) {
        _selectedGenreId = null;
        _selectedGenreName = null;
      } else {
        _selectedGenreId = id;
        _selectedGenreName = name;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      extendBody: true,
      body: Column(
        children: [
          // ── Status bar space + search bar ──────────────────────────────
          SizedBox(height: topPad),
          _SearchBar(
            controller: _searchController,
            isSearching: _isSearching,
            onClear: _clearSearch,
          ),

          // ── Content ────────────────────────────────────────────────────
          Expanded(
            child: _isSearching
                ? _SearchResults(controller: _searchController)
                : _DiscoveryContent(
                    trendingMovies: _trendingMovies,
                    selectedGenreId: _selectedGenreId,
                    selectedGenreName: _selectedGenreName,
                    onToggleTrending: (v) =>
                        setState(() => _trendingMovies = v),
                    onSelectGenre: _selectGenre,
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Search Bar ───────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSearching;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.isSearching,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sectionPaddingH,
        12,
        AppSpacing.sectionPaddingH,
        12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: TextField(
            controller: controller,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: 'Search movies & TV shows…',
              hintStyle: AppTextStyles.body.copyWith(
                color: AppColors.textMuted,
              ),
              filled: true,
              fillColor: AppColors.surfaceDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.textSecondary,
              ),
              suffixIcon: isSearching
                  ? IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                      onPressed: onClear,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Discovery Content (no query) ────────────────────────────────────────────

class _DiscoveryContent extends ConsumerWidget {
  final bool trendingMovies;
  final int? selectedGenreId;
  final String? selectedGenreName;
  final ValueChanged<bool> onToggleTrending;
  final void Function(int id, String name) onSelectGenre;

  const _DiscoveryContent({
    required this.trendingMovies,
    required this.selectedGenreId,
    required this.selectedGenreName,
    required this.onToggleTrending,
    required this.onSelectGenre,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genreMapAsync = ref.watch(genreMapProvider);
    final genreMap = genreMapAsync.value ?? {};

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Trending section ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _TrendingSection(
            showMovies: trendingMovies,
            onToggle: onToggleTrending,
            genreMap: genreMap,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 28)),

        // ── Genre chips ───────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _GenreChips(
            selectedId: selectedGenreId,
            onSelect: onSelectGenre,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 28)),

        // ── Genre results OR popular rows ──────────────────────────────────
        if (selectedGenreId != null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: AppSpacing.sectionPadding,
              child: Row(
                children: [
                  Text(selectedGenreName!, style: AppTextStyles.sectionTitle),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Genre',
                      style: AppTextStyles.tag.copyWith(
                        color: AppColors.primary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _GenreResults(
              genreId: selectedGenreId!,
              genreMap: genreMap,
            ),
          ),
        ] else ...[
          // Popular Movies row
          SliverToBoxAdapter(
            child: ref.watch(popularMoviesProvider).when(
              data: (movies) => MediaRow(
                title: 'Popular Movies',
                movies: movies,
                genreMap: genreMap,
                onMovieTap: (m) => context.push('/details', extra: m),
              ),
              loading: () => const MediaRow(
                title: 'Popular Movies',
                movies: [],
                isLoading: true,
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 28)),

          // Popular TV Shows row
          SliverToBoxAdapter(
            child: ref.watch(popularTvProvider).when(
              data: (shows) => MediaRow(
                title: 'Popular TV Shows',
                movies: shows,
                genreMap: genreMap,
                onMovieTap: (m) => context.push('/details', extra: m),
              ),
              loading: () => const MediaRow(
                title: 'Popular TV Shows',
                movies: [],
                isLoading: true,
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ],

        // Bottom padding for nav bar
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

// ─── Trending Section ─────────────────────────────────────────────────────────

class _TrendingSection extends ConsumerWidget {
  final bool showMovies;
  final ValueChanged<bool> onToggle;
  final Map<int, String> genreMap;

  const _TrendingSection({
    required this.showMovies,
    required this.onToggle,
    required this.genreMap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = showMovies
        ? ref.watch(trendingMoviesProvider)
        : ref.watch(trendingTvProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title + toggle
        Padding(
          padding: AppSpacing.sectionPadding,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Trending', style: AppTextStyles.sectionTitle),
              _ToggleChips(
                selected: showMovies,
                onToggle: onToggle,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Horizontal cards
        listAsync.when(
          data: (items) => MediaRow(
            title: '',
            movies: items,
            genreMap: genreMap,
            onMovieTap: (m) => context.push('/details', extra: m),
            showTitle: false,
          ),
          loading: () => const MediaRow(
            title: '',
            movies: [],
            isLoading: true,
            showTitle: false,
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ─── Movie / TV Toggle Chips ──────────────────────────────────────────────────

class _ToggleChips extends StatelessWidget {
  final bool selected; // true = Movies
  final ValueChanged<bool> onToggle;

  const _ToggleChips({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Chip(label: 'Movies', active: selected, onTap: () => onToggle(true)),
        const SizedBox(width: 8),
        _Chip(label: 'TV', active: !selected, onTap: () => onToggle(false)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─── Genre Chips ──────────────────────────────────────────────────────────────

class _GenreChips extends ConsumerWidget {
  final int? selectedId;
  final void Function(int id, String name) onSelect;

  const _GenreChips({required this.selectedId, required this.onSelect});

  static const _genreIcons = <int, IconData>{
    28: Icons.bolt_rounded,          // Action
    12: Icons.explore_rounded,       // Adventure
    16: Icons.brush_rounded,         // Animation
    35: Icons.sentiment_very_satisfied_rounded, // Comedy
    80: Icons.search_rounded,        // Crime
    99: Icons.videocam_rounded,      // Documentary
    18: Icons.theater_comedy_rounded, // Drama
    10751: Icons.family_restroom_rounded, // Family
    14: Icons.auto_awesome_rounded,  // Fantasy
    36: Icons.history_edu_rounded,   // History
    27: Icons.nightlight_rounded,    // Horror
    10402: Icons.music_note_rounded, // Music
    9648: Icons.psychology_rounded,  // Mystery
    10749: Icons.favorite_rounded,   // Romance
    878: Icons.rocket_launch_rounded, // Science Fiction
    10770: Icons.tv_rounded,         // TV Movie
    53: Icons.remove_red_eye_rounded, // Thriller
    10752: Icons.military_tech_rounded, // War
    37: Icons.landscape_rounded,     // Western
    10759: Icons.sports_martial_arts_rounded, // Action & Adventure (TV)
    10762: Icons.child_care_rounded, // Kids
    10763: Icons.newspaper_rounded,  // News
    10764: Icons.emoji_events_rounded, // Reality
    10765: Icons.science_rounded,    // Sci-Fi & Fantasy (TV)
    10766: Icons.format_list_bulleted_rounded, // Soap
    10767: Icons.mic_rounded,        // Talk
    10768: Icons.flag_rounded,       // War & Politics (TV)
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(allGenresProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: AppSpacing.sectionPadding,
          child: Text('Browse by Genre', style: AppTextStyles.sectionTitle),
        ),
        const SizedBox(height: 12),
        genresAsync.when(
          loading: () => _buildShimmer(),
          error: (_, __) => const SizedBox.shrink(),
          data: (genres) => SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sectionPaddingH,
              ),
              itemCount: genres.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final g = genres[i];
                final isActive = selectedId == g.id;
                final icon = _genreIcons[g.id] ?? Icons.movie_outlined;

                return GestureDetector(
                  onTap: () => onSelect(g.id, g.name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 0,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primary
                          : AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isActive
                            ? AppColors.primary
                            : AppColors.glassBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 15,
                          color: isActive
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          g.name,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: isActive
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShimmer() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sectionPaddingH,
        ),
        itemCount: 8,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, __) => ShimmerPlaceholder(
          width: 90,
          height: 38,
          borderRadius: BorderRadius.circular(22),
        ),
      ),
    );
  }
}

// ─── Genre Results ────────────────────────────────────────────────────────────

class _GenreResults extends ConsumerWidget {
  final int genreId;
  final Map<int, String> genreMap;

  const _GenreResults({required this.genreId, required this.genreMap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moviesAsync = ref.watch(discoverMoviesByGenreProvider(genreId));
    final tvAsync = ref.watch(discoverTvByGenreProvider(genreId));

    return Column(
      children: [
        // Movies sub-row
        moviesAsync.when(
          data: (movies) => movies.isEmpty
              ? const SizedBox.shrink()
              : MediaRow(
                  title: 'Movies',
                  movies: movies,
                  genreMap: genreMap,
                  onMovieTap: (m) => context.push('/details', extra: m),
                ),
          loading: () => const MediaRow(
            title: 'Movies',
            movies: [],
            isLoading: true,
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),

        const SizedBox(height: 24),

        // TV sub-row
        tvAsync.when(
          data: (shows) => shows.isEmpty
              ? const SizedBox.shrink()
              : MediaRow(
                  title: 'TV Shows',
                  movies: shows,
                  genreMap: genreMap,
                  onMovieTap: (m) => context.push('/details', extra: m),
                ),
          loading: () => const MediaRow(
            title: 'TV Shows',
            movies: [],
            isLoading: true,
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ─── Search Results ───────────────────────────────────────────────────────────

class _SearchResults extends ConsumerWidget {
  final TextEditingController controller;

  const _SearchResults({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider);
    final genreMap = ref.watch(genreMapProvider).value ?? {};

    return resultsAsync.when(
      loading: () => _shimmerGrid(),
      error: (e, _) {
        if (e.toString().contains('cancelled')) return _shimmerGrid();
        return Center(
          child: Text(
            'Search failed',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        );
      },
      data: (results) {
        final query = ref.read(searchQueryProvider).trim();
        if (query.length < 2) return _emptyState();
        if (results.isEmpty) return _noResults(query);
        return _ResultsGrid(results: results, genreMap: genreMap);
      },
    );
  }

  Widget _shimmerGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sectionPaddingH,
        8,
        AppSpacing.sectionPaddingH,
        120,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.52,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 9,
      itemBuilder: (_, __) => const ShimmerPlaceholder(),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.movie_filter_outlined,
            size: 64,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Discover movies & TV shows',
            style: AppTextStyles.cardTitle.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text('Start typing to search', style: AppTextStyles.cardSubtitle),
        ],
      ),
    );
  }

  Widget _noResults(String query) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No results for "$query"',
            style: AppTextStyles.cardTitle.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: AppTextStyles.cardSubtitle,
          ),
        ],
      ),
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  final List<MediaItem> results;
  final Map<int, String> genreMap;

  const _ResultsGrid({required this.results, required this.genreMap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sectionPaddingH,
        8,
        AppSpacing.sectionPaddingH,
        120,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.52,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: results.length,
      itemBuilder: (_, i) {
        final item = results[i];
        final genreText = item.metadata.genreIds
            .take(2)
            .map((id) => genreMap[id] ?? '')
            .where((s) => s.isNotEmpty)
            .join(' • ');
        return MediaCard(
          movie: item,
          genreText: genreText,
          onTap: () => context.push('/details', extra: item),
        );
      },
    );
  }
}
