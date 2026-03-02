import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../domain/entities/media_item.dart';
import '../../providers/media_providers.dart';
import '../../providers/search_providers.dart';
import '../../widgets/media_card.dart';
import '../../widgets/media_row.dart';
import '../../widgets/shimmer_placeholder.dart';
import 'all_media_screen.dart';

// ─── Main Screen ──────────────────────────────────────────────────────────────

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _searchController = TextEditingController();
  bool _isSearching = false;

  int? _selectedGenreId;
  String? _selectedGenreName;

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
          SizedBox(height: topPad),
          _SearchBar(
            controller: _searchController,
            isSearching: _isSearching,
            onClear: _clearSearch,
          ),
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
        10,
        AppSpacing.sectionPaddingH,
        10,
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

// ─── Discovery Content ────────────────────────────────────────────────────────

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
    final genreMap = ref.watch(genreMapProvider).value ?? {};

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── 1. Trending Now ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _TrendingSection(
            showMovies: trendingMovies,
            onToggle: onToggleTrending,
            genreMap: genreMap,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),

        // ── 2. Browse Genres ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _GenreGrid(
            selectedId: selectedGenreId,
            onSelect: onSelectGenre,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 28)),

        // ── 3. Genre results OR sectioned popular rows ──────────────────
        if (selectedGenreId != null) ...[
          SliverToBoxAdapter(
            child: _GenreHeader(
              name: selectedGenreName!,
              onClear: () =>
                  onSelectGenre(selectedGenreId!, selectedGenreName!),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: _GenreResults(
              genreId: selectedGenreId!,
              genreMap: genreMap,
            ),
          ),
        ] else ...[
          // ── Movies section ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionDivider(
              icon: Icons.movie_filter_rounded,
              label: 'Movies',
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          // Popular Movies
          SliverToBoxAdapter(
            child: ref.watch(popularMoviesProvider).when(
              data: (movies) => MediaRow(
                title: 'Popular',
                movies: movies,
                genreMap: genreMap,
                onMovieTap: (m) => context.push('/details', extra: m),
                onSeeAllTap: () => context.push(
                  '/all-media',
                  extra: AllMediaArgs(
                    title: 'Popular Movies',
                    category: BrowseCategory.popularMovies,
                    genreMap: genreMap,
                  ),
                ),
              ),
              loading: () => const MediaRow(
                title: 'Popular',
                movies: [],
                isLoading: true,
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 28)),

          // Top Rated Movies
          SliverToBoxAdapter(
            child: ref.watch(topRatedMoviesProvider).when(
              data: (movies) => MediaRow(
                title: 'Top Rated',
                movies: movies,
                genreMap: genreMap,
                onMovieTap: (m) => context.push('/details', extra: m),
                onSeeAllTap: () => context.push(
                  '/all-media',
                  extra: AllMediaArgs(
                    title: 'Top Rated Movies',
                    category: BrowseCategory.topRatedMovies,
                    genreMap: genreMap,
                  ),
                ),
              ),
              loading: () => const MediaRow(
                title: 'Top Rated',
                movies: [],
                isLoading: true,
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 36)),

          // ── TV Shows section ───────────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionDivider(
              icon: Icons.live_tv_rounded,
              label: 'TV Shows',
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          // Popular TV
          SliverToBoxAdapter(
            child: ref.watch(popularTvProvider).when(
              data: (shows) => MediaRow(
                title: 'Popular',
                movies: shows,
                genreMap: genreMap,
                onMovieTap: (m) => context.push('/details', extra: m),
                onSeeAllTap: () => context.push(
                  '/all-media',
                  extra: AllMediaArgs(
                    title: 'Popular TV Shows',
                    category: BrowseCategory.popularTv,
                    genreMap: genreMap,
                  ),
                ),
              ),
              loading: () => const MediaRow(
                title: 'Popular',
                movies: [],
                isLoading: true,
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 28)),

          // Top Rated TV
          SliverToBoxAdapter(
            child: ref.watch(topRatedTvProvider).when(
              data: (shows) => MediaRow(
                title: 'Top Rated',
                movies: shows,
                genreMap: genreMap,
                onMovieTap: (m) => context.push('/details', extra: m),
                onSeeAllTap: () => context.push(
                  '/all-media',
                  extra: AllMediaArgs(
                    title: 'Top Rated TV Shows',
                    category: BrowseCategory.topRatedTv,
                    genreMap: genreMap,
                  ),
                ),
              ),
              loading: () => const MediaRow(
                title: 'Top Rated',
                movies: [],
                isLoading: true,
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

// ─── Section Divider ──────────────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionDivider({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.sectionPadding,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.6),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text(label, style: AppTextStyles.sectionTitle.copyWith(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.glassBorder,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Genre Header (when genre selected) ──────────────────────────────────────

class _GenreHeader extends StatelessWidget {
  final String name;
  final VoidCallback onClear;

  const _GenreHeader({required this.name, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.sectionPadding,
      child: Row(
        children: [
          Text(name, style: AppTextStyles.sectionTitle),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          const Spacer(),
          GestureDetector(
            onTap: onClear,
            child: Row(
              children: [
                const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Clear',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    final listAsync =
        showMovies ? ref.watch(trendingMoviesProvider) : ref.watch(trendingTvProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: AppSpacing.sectionPadding,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Trending Now', style: AppTextStyles.sectionTitle),
              _ToggleChips(selected: showMovies, onToggle: onToggle),
            ],
          ),
        ),
        const SizedBox(height: 12),
        listAsync.when(
          data: (items) => MediaRow(
            title: '',
            movies: items,
            genreMap: genreMap,
            onMovieTap: (m) => context.push('/details', extra: m),
            showTitle: false,
            onSeeAllTap: () => context.push(
              '/all-media',
              extra: AllMediaArgs(
                title: showMovies ? 'Trending Movies' : 'Trending TV',
                category: showMovies
                    ? BrowseCategory.trendingMovies
                    : BrowseCategory.trendingTv,
                genreMap: genreMap,
              ),
            ),
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

// ─── Movie / TV Toggle ────────────────────────────────────────────────────────

class _ToggleChips extends StatelessWidget {
  final bool selected; // true = Movies
  final ValueChanged<bool> onToggle;

  const _ToggleChips({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleOption(
            label: 'Movies',
            active: selected,
            onTap: () => onToggle(true),
          ),
          _ToggleOption(
            label: 'TV',
            active: !selected,
            onTap: () => onToggle(false),
          ),
        ],
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleOption({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: active ? Colors.white : AppColors.textSecondary,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ─── Genre Grid ───────────────────────────────────────────────────────────────

class _GenreGrid extends ConsumerWidget {
  final int? selectedId;
  final void Function(int id, String name) onSelect;

  const _GenreGrid({required this.selectedId, required this.onSelect});

  static const _genreColors = <int, List<Color>>{
    28: [Color(0xFFE53935), Color(0xFFB71C1C)],
    12: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
    16: [Color(0xFFAB47BC), Color(0xFF6A1B9A)],
    35: [Color(0xFFFFB300), Color(0xFFE65100)],
    80: [Color(0xFF546E7A), Color(0xFF263238)],
    99: [Color(0xFF26A69A), Color(0xFF004D40)],
    18: [Color(0xFF5C6BC0), Color(0xFF283593)],
    10751: [Color(0xFF66BB6A), Color(0xFF1B5E20)],
    14: [Color(0xFFBA68C8), Color(0xFF4A148C)],
    36: [Color(0xFF8D6E63), Color(0xFF3E2723)],
    27: [Color(0xFF1A237E), Color(0xFF000000)],
    10402: [Color(0xFFEC407A), Color(0xFF880E4F)],
    9648: [Color(0xFF455A64), Color(0xFF102027)],
    10749: [Color(0xFFEF5350), Color(0xFFB71C1C)],
    878: [Color(0xFF1565C0), Color(0xFF4A148C)],
    53: [Color(0xFF37474F), Color(0xFF000000)],
    10752: [Color(0xFF6D4C41), Color(0xFF1B0000)],
    37: [Color(0xFFD4890A), Color(0xFF4E342E)],
    10759: [Color(0xFFEF5350), Color(0xFFE65100)],
    10762: [Color(0xFF43A047), Color(0xFF1B5E20)],
    10763: [Color(0xFF0288D1), Color(0xFF01579B)],
    10764: [Color(0xFFFF7043), Color(0xFFBF360C)],
    10765: [Color(0xFF5E35B1), Color(0xFF1A237E)],
    10767: [Color(0xFF00BCD4), Color(0xFF006064)],
    10768: [Color(0xFF827717), Color(0xFF33691E)],
  };

  static const _genreIcons = <int, IconData>{
    28: Icons.bolt_rounded,
    12: Icons.explore_rounded,
    16: Icons.brush_rounded,
    35: Icons.sentiment_very_satisfied_rounded,
    80: Icons.search_rounded,
    99: Icons.videocam_rounded,
    18: Icons.theater_comedy_rounded,
    10751: Icons.family_restroom_rounded,
    14: Icons.auto_awesome_rounded,
    36: Icons.history_edu_rounded,
    27: Icons.nightlight_rounded,
    10402: Icons.music_note_rounded,
    9648: Icons.psychology_rounded,
    10749: Icons.favorite_rounded,
    878: Icons.rocket_launch_rounded,
    10770: Icons.tv_rounded,
    53: Icons.remove_red_eye_rounded,
    10752: Icons.military_tech_rounded,
    37: Icons.landscape_rounded,
    10759: Icons.sports_martial_arts_rounded,
    10762: Icons.child_care_rounded,
    10763: Icons.newspaper_rounded,
    10764: Icons.emoji_events_rounded,
    10765: Icons.science_rounded,
    10767: Icons.mic_rounded,
    10768: Icons.flag_rounded,
  };

  static const _fallbackColors = [Color(0xFF37474F), Color(0xFF102027)];

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
        const SizedBox(height: 14),
        genresAsync.when(
          loading: _buildShimmer,
          error: (_, __) => const SizedBox.shrink(),
          data: (genres) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sectionPaddingH,
              ),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1.45,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: genres.length,
                itemBuilder: (_, i) {
                  final g = genres[i];
                  final isActive = selectedId == g.id;
                  final colors = _genreColors[g.id] ?? _fallbackColors;
                  final icon = _genreIcons[g.id] ?? Icons.movie_outlined;

                  return GestureDetector(
                    onTap: () => onSelect(g.id, g.name),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isActive
                              ? [
                                  AppColors.primary,
                                  AppColors.primary.withValues(alpha: 0.7),
                                ]
                              : colors,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: isActive
                            ? Border.all(
                                color: Colors.white.withValues(alpha: 0.6),
                                width: 1.5,
                              )
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: (isActive ? AppColors.primary : colors.first)
                                .withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -8,
                            bottom: -8,
                            child: Icon(
                              icon,
                              size: 52,
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(icon, size: 18, color: Colors.white),
                                const SizedBox(height: 5),
                                Text(
                                  g.name,
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sectionPaddingH,
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.45,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: 12,
        itemBuilder: (_, __) => ShimmerPlaceholder(
          borderRadius: BorderRadius.circular(12),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        moviesAsync.when(
          data: (movies) => movies.isEmpty
              ? const SizedBox.shrink()
              : MediaRow(
                  title: 'Movies',
                  movies: movies,
                  genreMap: genreMap,
                  onMovieTap: (m) => context.push('/details', extra: m),
                  onSeeAllTap: () => context.push(
                    '/all-media',
                    extra: AllMediaArgs(
                      title: 'Movies',
                      category: BrowseCategory.discoverMoviesByGenre,
                      genreId: genreId,
                      genreMap: genreMap,
                    ),
                  ),
                ),
          loading: () => const MediaRow(
            title: 'Movies',
            movies: [],
            isLoading: true,
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 28),
        tvAsync.when(
          data: (shows) => shows.isEmpty
              ? const SizedBox.shrink()
              : MediaRow(
                  title: 'TV Shows',
                  movies: shows,
                  genreMap: genreMap,
                  onMovieTap: (m) => context.push('/details', extra: m),
                  onSeeAllTap: () => context.push(
                    '/all-media',
                    extra: AllMediaArgs(
                      title: 'TV Shows',
                      category: BrowseCategory.discoverTvByGenre,
                      genreId: genreId,
                      genreMap: genreMap,
                    ),
                  ),
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
      loading: _shimmerGrid,
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
