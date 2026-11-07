import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/responsive_grid.dart';
import '../../../domain/entities/media_item.dart';
import '../../providers/media_providers.dart';
import '../../providers/search_providers.dart';
import '../../widgets/retry_row.dart';
import '../../widgets/media_card.dart';
import '../../widgets/media_row.dart';
import '../../widgets/shimmer_placeholder.dart';
import 'all_media_screen.dart';

part 'discover_sections.dart';
part 'discover_search_results.dart';

// ─── Main Screen ──────────────────────────────────────────────────────────────

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _searchController = TextEditingController();

  int? _selectedGenreId;
  String? _selectedGenreName;

  bool _trendingMovies = true;

  @override
  void initState() {
    super.initState();
    // Riverpod is the source of truth for search text + active flag. If
    // our State is being recreated (this happens after a
    // `/player` → `/details` → back trip, because the player's
    // SystemChrome orientation/immersive-UI changes propagate a
    // MediaQuery rebuild that re-instantiates the IndexedStack child's
    // State), restore the controller text from the provider so the
    // search UI comes back exactly as the user left it. We then add
    // the listener — order matters: setting `text` BEFORE attaching
    // the listener avoids a spurious provider update.
    final savedQuery = ref.read(searchQueryProvider);
    if (savedQuery.isNotEmpty) {
      _searchController.text = savedQuery;
    }
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
    ref.read(isSearchActiveProvider.notifier).state = query.trim().isNotEmpty;
    // No setState — `isSearchActiveProvider` is watched in `build`, so the
    // rebuild happens through Riverpod. Keeping the active-flag in the
    // provider only (instead of mirrored to a local bool) means it
    // CANNOT desync from the controller text if our State is recreated
    // mid-session — which used to leave the UI showing Discovery content
    // but with the bottom-nav still hidden.
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).update('');
    ref.read(isSearchActiveProvider.notifier).state = false;
    // Drop focus too, so the soft keyboard goes away whether _clearSearch
    // was triggered by the X button, by the system back gesture (via the
    // shell's clear signal), or by leaving and returning to the tab.
    FocusManager.instance.primaryFocus?.unfocus();
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
    final isSearching = ref.watch(isSearchActiveProvider);

    // Shell asks us to clear the search whenever the user presses system
    // back while typing. The signal increments; we just react to any change.
    ref.listen<int>(searchClearSignalProvider, (_, _) {
      if (_searchController.text.isNotEmpty ||
          ref.read(isSearchActiveProvider)) {
        _clearSearch();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      extendBody: true,
      body: Column(
        children: [
          SizedBox(height: topPad),
          _SearchBar(
            controller: _searchController,
            isSearching: isSearching,
            onClear: _clearSearch,
          ),
          Expanded(
            child: isSearching
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
            // Tap on anything outside the field (results grid, genre tiles,
            // discovery rows, even empty space) drops focus and the soft
            // keyboard. The TextField itself, the keyboard, and any other
            // descendants of this TextField are exempt automatically.
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
                      tooltip: 'Clear search',
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
