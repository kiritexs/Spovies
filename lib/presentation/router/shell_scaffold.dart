import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
///
/// ─── System back-button stack ───────────────────────────────────────────
///
/// On Android (and any platform that surfaces a system pop request) the
/// [PopScope] below intercepts the back gesture and routes it through a
/// hierarchy that matches user expectation:
///
///   1. **Keyboard up + text focus** → dismiss the keyboard.
///   2. **Search active on Explore** → cancel the search.
///   3. **Not on Home tab** → switch to Home (so the user always lands on
///      the "root" of the app before the exit prompt).
///   4. **On Home, first press** → show "Press back again to exit".
///   5. **On Home, second press within [_kDoubleTapWindow]** → background
///      the app via [SystemNavigator.pop].
///
/// Routes pushed on the root navigator (`/details`, `/player`, `/all-media`,
/// etc.) sit *above* this shell, so their own pop happens first and never
/// reaches this PopScope.
class ShellScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;

  const ShellScaffold({super.key, required this.shell});

  @override
  ConsumerState<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends ConsumerState<ShellScaffold> {
  /// Index of the Home tab — the "root" of the app. Back falls back to here
  /// from any other tab before arming the exit prompt.
  static const int _homeBranchIndex = 0;

  /// Index of the tab that owns the search controller (Explore).
  static const int _exploreBranchIndex = 1;

  /// Window in which a second back press is treated as "confirm exit".
  static const Duration _kDoubleTapWindow = Duration(seconds: 2);

  DateTime? _lastBackPress;

  Future<void> _handleSystemBack() async {
    // 1. Soft keyboard is up AND a text field actually owns the focus →
    //    dismiss it first. With `canPop: false` we've overridden the
    //    framework's default first-back-dismisses-IME, so we have to
    //    recreate it here.
    //
    //    Both checks matter: viewInsets alone has a race during the
    //    keyboard's exit animation (it's still > 0 for ~150 ms after the
    //    user has already dismissed it via tap/scroll), which would make
    //    the next back press feel like a no-op. Combining with primaryFocus
    //    means we only short-circuit when there's something to actually
    //    unfocus.
    final primaryFocus = FocusManager.instance.primaryFocus;
    final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;
    if (keyboardUp && primaryFocus != null && primaryFocus.hasFocus) {
      primaryFocus.unfocus();
      return;
    }

    // 2. If a search is active on Explore, cancel it.
    final isSearching = ref.read(isSearchActiveProvider);
    if (isSearching && widget.shell.currentIndex == _exploreBranchIndex) {
      ref.read(searchClearSignalProvider.notifier).requestClear();
      return;
    }

    // 3. Not on Home → switch to Home. Reset the exit-hint timer so the
    //    user always gets a fresh "press back again" prompt on Home,
    //    regardless of any stale timestamp from before they pressed back.
    if (widget.shell.currentIndex != _homeBranchIndex) {
      _lastBackPress = null;
      widget.shell.goBranch(_homeBranchIndex);
      return;
    }

    // 4. On Home: arm the double-tap-to-exit pattern.
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last == null || now.difference(last) > _kDoubleTapWindow) {
      _lastBackPress = now;
      _showExitHint();
      return;
    }

    // 5. Second back within the window: actually leave. SystemNavigator.pop
    //    backgrounds the app on Android (matching standard launcher
    //    behaviour) and is a no-op on desktop.
    await SystemNavigator.pop();
  }

  void _showExitHint() {
    // Sit above the floating nav bar so the message isn't covered by it.
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Press back again to exit'),
          duration: _kDoubleTapWindow,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.navBarHorizontal,
            0,
            AppSpacing.navBarHorizontal,
            // Floating nav bar height (~64) + its bottom inset, with a small
            // gap so the snackbar visually sits above it.
            AppSpacing.navBarBottom + 80,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Hide the nav bar only when search is active *and* the user is on the
    // tab that owns the search. Gating on the tab here lets us drop the
    // discover screen's old `deactivate()` reset of the provider, which was
    // the source of a stale-state bug where the back button would jump
    // tabs instead of clearing search after a round-trip through Home.
    final isSearching = ref.watch(isSearchActiveProvider) &&
        widget.shell.currentIndex == 1;
    final isDesktop =
        MediaQuery.of(context).size.width >= 800; // Desktop breakpoint

    final scaffold = isDesktop
        ? Scaffold(
            backgroundColor: AppColors.backgroundDark,
            body: DesktopWindowFrame(
              child: Row(
                children: [
                  DesktopSideNav(
                    currentIndex: widget.shell.currentIndex,
                    onTap: (index) => widget.shell.goBranch(
                      index,
                      initialLocation: index == widget.shell.currentIndex,
                    ),
                  ),
                  // Divider for visual separation
                  Container(
                    width: 1,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  Expanded(child: widget.shell),
                ],
              ),
            ),
          )
        : Scaffold(
            backgroundColor: AppColors.backgroundDark,
            extendBody: true,
            extendBodyBehindAppBar: true,
            body: Stack(
              children: [
                // Current tab's full-screen content
                widget.shell,

                // Nav bar: Positioned must be a direct Stack child.
                // All animation widgets live INSIDE the Positioned.
                Positioned(
                  bottom: AppSpacing.navBarBottom,
                  left: AppSpacing.navBarHorizontal,
                  right: AppSpacing.navBarHorizontal,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOutCubic,
                    offset:
                        isSearching ? const Offset(0, 2.0) : Offset.zero,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: isSearching ? 0.0 : 1.0,
                      child: IgnorePointer(
                        ignoring: isSearching,
                        child: GlassBottomNav(
                          currentIndex: widget.shell.currentIndex,
                          onTap: (index) => widget.shell.goBranch(
                            index,
                            initialLocation:
                                index == widget.shell.currentIndex,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: scaffold,
    );
  }
}
