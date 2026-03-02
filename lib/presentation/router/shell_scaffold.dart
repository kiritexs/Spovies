import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../providers/search_providers.dart';
import '../widgets/glass_bottom_nav.dart';

/// Shell scaffold rendered by [StatefulShellRoute].
///
/// Owns the [Positioned] for the nav bar so that the animation wrappers
/// ([AnimatedSlide], [AnimatedOpacity], [IgnorePointer]) live *inside* the
/// Positioned rather than outside it — `Positioned` must always be a direct
/// child of a [Stack].
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

          // Nav bar: Positioned must be a direct Stack child.
          // All animation widgets live INSIDE the Positioned.
          Positioned(
            bottom: AppSpacing.navBarBottom,
            left: AppSpacing.navBarHorizontal,
            right: AppSpacing.navBarHorizontal,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              offset: isSearching ? const Offset(0, 2.0) : Offset.zero,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: isSearching ? 0.0 : 1.0,
                child: IgnorePointer(
                  ignoring: isSearching,
                  child: GlassBottomNav(
                    currentIndex: shell.currentIndex,
                    onTap: (index) => shell.goBranch(
                      index,
                      initialLocation: index == shell.currentIndex,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
