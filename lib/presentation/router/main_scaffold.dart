import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../providers/search_providers.dart';
import '../providers/tab_provider.dart';
import '../screens/explore/discover_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/watchlist/watchlist_screen.dart';
import '../widgets/desktop_side_nav.dart';
import '../widgets/desktop_window_frame.dart';
import '../widgets/glass_bottom_nav.dart';

/// Top-level scaffold owning the four tabs and the global system-back
/// contract.
///
/// A single `PopScope(canPop:false)` here handles every back press while
/// no full-screen route is pushed. See `docs/architecture/NAVIGATION.md`
/// for the back-press ladder and why `StatefulShellRoute` was abandoned.
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  static const int _homeTabIndex = 0;
  static const int _exploreTabIndex = 1;
  static const Duration _kDoubleTapWindow = Duration(seconds: 2);

  /// `null` means the exit-prompt timer is not armed.
  DateTime? _lastBackPress;

  /// Built once and cached. The `ValueKey`s keep Flutter's reconciliation
  /// from recreating a tab's State on an ancestor rebuild.
  late final List<Widget> _tabs = const [
    _KeepAliveTab(key: ValueKey(0), child: HomeScreen()),
    _KeepAliveTab(key: ValueKey(1), child: DiscoverScreen()),
    _KeepAliveTab(key: ValueKey(2), child: WatchlistScreen()),
    _KeepAliveTab(key: ValueKey(3), child: SettingsScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(currentTabProvider);
    final isSearching =
        ref.watch(isSearchActiveProvider) && tab == _exploreTabIndex;
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    final body = IndexedStack(index: tab, children: _tabs);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_onBack());
      },
      // Desktop title bar on the tab shell only (a no-op on phones). It
      // wraps the narrow layout too, so a narrow window can still be moved
      // and closed. Pushed screens like Details draw edge to edge.
      child: DesktopWindowFrame(
        child: isDesktop
            ? _buildDesktopShell(body, tab)
            : _buildMobileShell(body, tab, isSearching),
      ),
    );
  }

  Widget _buildDesktopShell(Widget body, int tab) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Row(
        children: [
          DesktopSideNav(currentIndex: tab, onTap: _setTab),
          Container(width: 1, color: Colors.white.withValues(alpha: 0.05)),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildMobileShell(Widget body, int tab, bool isSearching) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          body,
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
                  child: GlassBottomNav(currentIndex: tab, onTap: _setTab),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _setTab(int i) {
    ref.read(currentTabProvider.notifier).state = i;
  }

  Future<void> _onBack() async {
    // 1. Keyboard.
    final focus = FocusManager.instance.primaryFocus;
    final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;
    if (keyboardUp && focus != null && focus.hasFocus) {
      focus.unfocus();
      return;
    }

    final tab = ref.read(currentTabProvider);

    // 2. Active search on Explore — clear it rather than leave the tab.
    if (tab == _exploreTabIndex && ref.read(isSearchActiveProvider)) {
      ref.read(searchClearSignalProvider.notifier).requestClear();
      return;
    }

    // 3. Not on Home — go there, re-arming the exit prompt.
    if (tab != _homeTabIndex) {
      _lastBackPress = null;
      _setTab(_homeTabIndex);
      return;
    }

    // 4. On Home, first back — arm the exit prompt.
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last == null || now.difference(last) > _kDoubleTapWindow) {
      _lastBackPress = now;
      _showExitHint();
      return;
    }

    // 5. Second back within the window.
    await SystemNavigator.pop();
  }

  void _showExitHint() {
    ScaffoldMessenger.of(context)
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
            AppSpacing.navBarBottom + 80,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
          ),
        ),
      );
  }
}

/// Keeps a tab subtree's State alive across ancestor rebuilds.
class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  const _KeepAliveTab({super.key, required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
