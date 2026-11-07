import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/responsive_grid.dart';
import '../../../domain/entities/media_item.dart';
import '../../providers/media_providers.dart';
import '../../widgets/media_card.dart';
import '../../widgets/shimmer_placeholder.dart';

// ─── Browse Category ──────────────────────────────────────────────────────────

/// Identifies which TMDB endpoint backs a "See All" grid.
enum BrowseCategory {
  trendingMovies,
  trendingTv,
  popularMovies,
  popularTv,
  topRatedMovies,
  topRatedTv,
  discoverMoviesByGenre,
  discoverTvByGenre,
}

/// Data passed via GoRouter `extra` to the `/all-media` route.
class AllMediaArgs {
  final String title;
  final BrowseCategory category;

  /// Required for [BrowseCategory.discoverMoviesByGenre] /
  /// [BrowseCategory.discoverTvByGenre].
  final int? genreId;
  final Map<int, String> genreMap;

  const AllMediaArgs({
    required this.title,
    required this.category,
    this.genreId,
    this.genreMap = const {},
  }) : assert(
         (category != BrowseCategory.discoverMoviesByGenre &&
                 category != BrowseCategory.discoverTvByGenre) ||
             genreId != null,
         'genreId is required for discover-by-genre categories',
       );
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class AllMediaScreen extends ConsumerStatefulWidget {
  final AllMediaArgs args;

  const AllMediaScreen({super.key, required this.args});

  @override
  ConsumerState<AllMediaScreen> createState() => _AllMediaScreenState();
}

class _AllMediaScreenState extends ConsumerState<AllMediaScreen> {
  final _scrollController = ScrollController();

  final List<MediaItem> _items = [];

  /// Keys of titles already shown. Trending is followed by popular pages,
  /// which overlap it, so later pages can repeat a title.
  final Set<String> _seen = {};
  int _page = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNextPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // After an error only the Retry button loads again, so scrolling near
    // the bottom doesn't fire a request on every scroll event.
    if (_error != null) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final nextPage = _page + 1;
      final api = ref.read(tmdbApiProvider);
      final cat = widget.args.category;
      final genreId = widget.args.genreId;

      List<MediaItem> newItems;

      switch (cat) {
        case BrowseCategory.trendingMovies:
          // Trending only has one page on TMDB; for variety load popular on p>1
          if (nextPage == 1) {
            newItems = (await api.getTrendingMovies())
                .map((m) => m.toEntity())
                .toList();
          } else {
            newItems = (await api.getPopularMovies(
              page: nextPage - 1,
            )).map((m) => m.toEntity()).toList();
          }
        case BrowseCategory.trendingTv:
          if (nextPage == 1) {
            newItems = (await api.getTrendingTv())
                .map((m) => m.toEntity())
                .toList();
          } else {
            newItems = (await api.getPopularTv(
              page: nextPage - 1,
            )).map((m) => m.toEntity()).toList();
          }
        case BrowseCategory.popularMovies:
          newItems = (await api.getPopularMovies(
            page: nextPage,
          )).map((m) => m.toEntity()).toList();
        case BrowseCategory.popularTv:
          newItems = (await api.getPopularTv(
            page: nextPage,
          )).map((m) => m.toEntity()).toList();
        case BrowseCategory.topRatedMovies:
          newItems = (await api.getTopRatedMovies(
            page: nextPage,
          )).map((m) => m.toEntity()).toList();
        case BrowseCategory.topRatedTv:
          newItems = (await api.getTopRatedTv(
            page: nextPage,
          )).map((m) => m.toEntity()).toList();
        case BrowseCategory.discoverMoviesByGenre:
        case BrowseCategory.discoverTvByGenre:
          // Constructor asserts genreId is non-null for these cases, but in
          // release builds asserts are stripped — fail loudly with a typed
          // error instead of NoSuchMethodError on a null force-unwrap.
          if (genreId == null) {
            throw StateError(
              'genreId is required for ${cat.name} but was null',
            );
          }
          final results = cat == BrowseCategory.discoverMoviesByGenre
              ? await api.discoverMoviesByGenre(genreId, page: nextPage)
              : await api.discoverTvByGenre(genreId, page: nextPage);
          newItems = results.map((m) => m.toEntity()).toList();
      }

      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _items.addAll(
          newItems.where((m) => _seen.add('${m.type.name}_${m.tmdbId}')),
        );
        // TMDB returns 20 results per page max; fewer = last page. Count the
        // raw page, not what survived de-duplication.
        if (newItems.length < 20) _hasMore = false;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── App bar ──────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.backgroundDark,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => context.pop(),
            ),
            title: Text(widget.args.title, style: AppTextStyles.appTitle),
            centerTitle: false,
          ),

          // ── Count / loading badge ─────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sectionPaddingH,
                8,
                AppSpacing.sectionPaddingH,
                16,
              ),
              child: _items.isEmpty
                  ? const SizedBox.shrink()
                  : Text(
                      '${_items.length} titles${_hasMore ? '+' : ''}',
                      style: AppTextStyles.cardSubtitle,
                    ),
            ),
          ),

          // ── Grid ─────────────────────────────────────────────────────
          if (_items.isEmpty && _isLoading)
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sectionPaddingH,
              ),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final cols = posterGridColumns(constraints.crossAxisExtent);
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      childAspectRatio: 0.52,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, _) => const ShimmerPlaceholder(),
                      childCount: cols * 4,
                    ),
                  );
                },
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sectionPaddingH,
                0,
                AppSpacing.sectionPaddingH,
                0,
              ),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: posterGridColumns(
                        constraints.crossAxisExtent,
                      ),
                      childAspectRatio: 0.52,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final item = _items[i];
                      final genreText = item.metadata.genreIds
                          .take(2)
                          .map((id) => widget.args.genreMap[id] ?? '')
                          .where((s) => s.isNotEmpty)
                          .join(' • ');
                      return MediaCard(
                        movie: item,
                        genreText: genreText,
                        onTap: () => context.push('/details', extra: item),
                      );
                    }, childCount: _items.length),
                  );
                },
              ),
            ),

          // ── Error state ───────────────────────────────────────────────
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.textSecondary,
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _items.isEmpty
                            ? "Couldn't load titles"
                            : "Couldn't load more titles",
                        style: AppTextStyles.cardSubtitle,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _loadNextPage,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Load more indicator ───────────────────────────────────────
          if (_isLoading && _items.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),

          // ── End-of-list message ───────────────────────────────────────
          if (!_hasMore && _items.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'All ${_items.length} titles loaded',
                    style: AppTextStyles.cardSubtitle,
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}
