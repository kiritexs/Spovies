import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../domain/entities/media_item.dart';
import '../../widgets/media_card.dart';
import '../../widgets/shimmer_placeholder.dart';

/// Args passed via GoRouter `extra` to the `/all-media` route.
class AllMediaArgs {
  final String title;
  final List<MediaItem> items;
  final Map<int, String> genreMap;

  const AllMediaArgs({
    required this.title,
    required this.items,
    required this.genreMap,
  });
}

/// Full-screen grid of media items, reached via "See All".
class AllMediaScreen extends StatelessWidget {
  final AllMediaArgs args;

  const AllMediaScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── App bar ────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.backgroundDark,
            surfaceTintColor: Colors.transparent,
            expandedHeight: topPad + 56,
            collapsedHeight: kToolbarHeight,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => context.pop(),
            ),
            title: Text(args.title, style: AppTextStyles.appTitle),
            centerTitle: false,
          ),

          // ── Count badge ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sectionPaddingH,
                8,
                AppSpacing.sectionPaddingH,
                16,
              ),
              child: Text(
                '${args.items.length} titles',
                style: AppTextStyles.cardSubtitle,
              ),
            ),
          ),

          // ── Grid ───────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sectionPaddingH,
              0,
              AppSpacing.sectionPaddingH,
              40,
            ),
            sliver: args.items.isEmpty
                ? SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.52,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, __) => const ShimmerPlaceholder(),
                      childCount: 12,
                    ),
                  )
                : SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.52,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final item = args.items[i];
                        final genreText = item.metadata.genreIds
                            .take(2)
                            .map((id) => args.genreMap[id] ?? '')
                            .where((s) => s.isNotEmpty)
                            .join(' • ');
                        return MediaCard(
                          movie: item,
                          genreText: genreText,
                          onTap: () =>
                              context.push('/details', extra: item),
                        );
                      },
                      childCount: args.items.length,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
