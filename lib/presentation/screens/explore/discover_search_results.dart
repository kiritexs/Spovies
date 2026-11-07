part of 'discover_screen.dart';

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
        // Superseded by a newer query: that query's results are coming.
        if (e is SearchCancelledException) return _shimmerGrid();
        return Center(
          child: RetryRow(
            title: 'Search failed',
            onRetry: () => ref.invalidate(searchResultsProvider),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = posterGridColumns(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sectionPaddingH,
            8,
            AppSpacing.sectionPaddingH,
            120,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.52,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          // Fill at least 2 rows worth of shimmer cards so the loading
          // state looks the same density as the eventual results.
          itemCount: cols * 3,
          itemBuilder: (_, _) => const ShimmerPlaceholder(),
        );
      },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sectionPaddingH,
            8,
            AppSpacing.sectionPaddingH,
            120,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: posterGridColumns(constraints.maxWidth),
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
      },
    );
  }
}
