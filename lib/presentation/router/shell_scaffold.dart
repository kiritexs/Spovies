import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../providers/search_providers.dart';
import '../widgets/glass_bottom_nav.dart';

/// Shell scaffold rendered by [StatefulShellRoute].
///
/// Wraps the current branch's content in a [Stack] and overlays the
/// [GlassBottomNav] at the bottom. The nav bar slides away when the user is
/// actively typing in the search field (watches [isSearchActiveProvider]).
class ShellScaffold extends ConsumerWidget {
  final StatefulNavigationShell shell;

  const ShellScaffold({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSearching = ref.watch(isSearchActiveProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Current tab's full-screen content
          shell,

          // Floating glass nav bar — slides down when search is active
          AnimatedSlide(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            offset: isSearching ? const Offset(0, 1.5) : Offset.zero,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: isSearching ? 0.0 : 1.0,
              child: IgnorePointer(
                ignoring: isSearching,
                child: GlassBottomNav(
                  currentIndex: shell.currentIndex,
                  onTap: (index) {
                    shell.goBranch(
                      index,
                      initialLocation: index == shell.currentIndex,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
