import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../providers/search_providers.dart';
import '../../providers/media_providers.dart';
import '../../widgets/media_card.dart';
import '../../widgets/shimmer_placeholder.dart';
import '../details/details_screen.dart';

/// Full-screen search with glass surface input and live TMDB results.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(searchResultsProvider);
    final genreMapAsync = ref.watch(genreMapProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Search Header ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  // Back button
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),

                  // Search field
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusBase,
                      ),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          style: AppTextStyles.body,
                          onChanged: (value) {
                            ref
                                .read(searchQueryProvider.notifier)
                                .update(value);
                          },
                          decoration: InputDecoration(
                            hintText: 'Search movies & TV shows...',
                            hintStyle: AppTextStyles.body.copyWith(
                              color: AppColors.textMuted,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceDark,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusBase,
                              ),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: AppColors.textSecondary,
                            ),
                            suffixIcon: _controller.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      color: AppColors.textSecondary,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      _controller.clear();
                                      ref
                                          .read(searchQueryProvider.notifier)
                                          .update('');
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ─── Results ──────────────────────────────────────────
            Expanded(
              child: resultsAsync.when(
                loading: () => _buildShimmerGrid(),
                error: (e, _) {
                  if (e.toString().contains('cancelled')) {
                    return _buildShimmerGrid();
                  }
                  return Center(
                    child: Text(
                      'Search failed: $e',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
                data: (results) {
                  if (ref.read(searchQueryProvider).trim().length < 2) {
                    return _buildEmptyState();
                  }
                  if (results.isEmpty) {
                    return _buildNoResults();
                  }
                  return _buildResultsGrid(results, genreMapAsync);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Empty State ──────────────────────────────────────────────────────

  Widget _buildEmptyState() {
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

  // ─── No Results ───────────────────────────────────────────────────────

  Widget _buildNoResults() {
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
            'No results found',
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

  // ─── Shimmer Grid ─────────────────────────────────────────────────────

  Widget _buildShimmerGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sectionPaddingH,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 9,
      itemBuilder: (context, index) => const ShimmerPlaceholder(),
    );
  }

  // ─── Results Grid ─────────────────────────────────────────────────────

  Widget _buildResultsGrid(
    List<dynamic> results,
    AsyncValue<Map<int, String>> genreMapAsync,
  ) {
    final genreMap = genreMapAsync.value ?? {};

    return GridView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sectionPaddingH,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: results.length,
      itemBuilder: (_, index) {
        final item = results[index];
        final genreText = (item.metadata.genreIds as List<int>)
            .take(2)
            .map((id) => genreMap[id] ?? '')
            .where((String s) => s.isNotEmpty)
            .join(' • ');

        return MediaCard(
          movie: item,
          genreText: genreText,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DetailsScreen(media: item)),
          ),
        );
      },
    );
  }
}
