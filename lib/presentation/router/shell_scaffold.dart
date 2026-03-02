import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../widgets/glass_bottom_nav.dart';

/// Shell scaffold rendered by [StatefulShellRoute].
///
/// Wraps the current branch's content in a [Stack] and overlays the
/// [GlassBottomNav] at the bottom. Switching tabs calls [shell.goBranch],
/// which preserves each branch's scroll position and state independently.
class ShellScaffold extends StatelessWidget {
  final StatefulNavigationShell shell;

  const ShellScaffold({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      // extendBody lets content scroll under the floating nav bar without
      // being clipped at the bottom.
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Current tab's full-screen content
          shell,

          // Floating glass nav bar overlaid at the bottom
          GlassBottomNav(
            currentIndex: shell.currentIndex,
            onTap: (index) {
              shell.goBranch(
                index,
                // Re-tapping the active tab scrolls back to the initial
                // location of that branch (pops sub-routes, resets scroll).
                initialLocation: index == shell.currentIndex,
              );
            },
          ),
        ],
      ),
    );
  }
}
