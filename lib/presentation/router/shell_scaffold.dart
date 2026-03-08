import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../providers/search_providers.dart';
import '../widgets/glass_bottom_nav.dart';
import '../widgets/desktop_side_nav.dart';
import '../widgets/desktop_window_frame.dart';

/// Shell scaffold rendered by [StatefulShellRoute].
///
/// Handles responsive branching between a DesktopSideNav for large screens
/// and a GlassBottomNav for smaller, mobile screens.
class ShellScaffold extends ConsumerWidget {
  final StatefulNavigationShell shell;

  const ShellScaffold({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSearching = ref.watch(isSearchActiveProvider);
    final isDesktop =
        MediaQuery.of(context).size.width >= 800; // Desktop breakpoint

    if (isDesktop) {
      return Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: DesktopWindowFrame(
          child: Row(
            children: [
              DesktopSideNav(
                currentIndex: shell.currentIndex,
                onTap: (index) => shell.goBranch(
                  index,
                  initialLocation: index == shell.currentIndex,
                ),
              ),
              // Divider for visual separation
              Container(width: 1, color: Colors.white.withValues(alpha: 0.05)),
              Expanded(child: shell),
            ],
          ),
        ),
      );
    }

    // Mobile Layout
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
