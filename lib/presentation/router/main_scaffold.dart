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

/// Top-level scaffold that owns the four tabs and the global system-back
/// contract.
///
/// Replaces the previous `StatefulShellRoute.indexedStack` + `ShellScaffold`
/// + `SpoviesBackButtonDispatcher` + `back_button_interceptor` stack.
/// Rationale, in one line: a single `PopScope(canPop:false)` on a route
/// that owns its tabs via plain `IndexedStack` is the canonical Flutter
/// pattern for this UX and is the only mechanism that doesn't get
/// pre-empted by `StatefulShellRoute`'s nested back-button-dispatcher
/// chain (Flutter issues #143172 / #153672 / #155441 / #170220, see
/// the workflow investigation in task #61).
///
/// ## Architecture
///
/// - `IndexedStack` keeps all four tab subtrees mounted at once. The
///   inactive ones are off-screen but their `State` lives — scroll
///   positions, controllers, Riverpod sub-tree state survive a switch.
///   `_KeepAliveTab` (`AutomaticKeepAliveClientMixin`) makes sure any
///   `PageStorageBucket`-style state inside also keeps.
/// - Active tab index lives in [currentTabProvider]. Bottom-nav /
///   side-nav widgets read+write it. Any other widget that wants to
///   switch tabs programmatically (e.g. the Home search button jumping
///   to Explore) writes to it directly — no `context.go()` hop needed.
/// - `PopScope(canPop:false)` at the root of this scaffold catches
///   every system-back press while no full-screen route is pushed on
///   top. When a full-screen route IS pushed (`/details`, `/player`,
///   `/all-media`, `/plugins`, `/licenses`), the framework's modal
///   route stack puts that route above this PopScope, so its own pop
///   logic runs first — exactly what we want.
///
/// ## Back-press ladder (in [_onBack])
///
/// 1. Keyboard up + focused field → unfocus.
/// 2. Tab is Explore AND search active → clear search instead of
///    leaving the tab.
/// 3. Tab is not Home → switch to Home (no exit prompt).
/// 4. Tab is Home, first press → arm a 2-second exit prompt
///    (snackbar).
/// 5. Tab is Home, second press within 2 s → `SystemNavigator.pop`.
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  /// Branch indices. Kept in sync with [GlassBottomNav] / [DesktopSideNav]
  /// label order.
  static const int _homeTabIndex = 0;
  static const int _exploreTabIndex = 1;

  /// Window in which a second back-press confirms exit.
  static const Duration _kDoubleTapWindow = Duration(seconds: 2);

  /// Timestamp of the last Home-tab back press. `null` means the
  /// exit-prompt timer is not armed.
  DateTime? _lastBackPress;

  /// Tab subtrees built ONCE and cached for the lifetime of this
  /// scaffold. Each carries an explicit `ValueKey` so Flutter's
  /// reconciliation can't confuse them with a freshly-built sibling
  /// when an ancestor rebuilds (e.g. when the player route on top
  /// triggers a SystemChrome orientation change that propagates a
  /// MediaQuery rebuild down through the whole tree). Without these
  /// keys, the Explore tab's `_DiscoverScreenState` was getting
  /// re-initialised after every player → details → back sequence,
  /// dropping its `_searchController` and the local "is searching"
  /// flag while the Riverpod `isSearchActiveProvider` survived —
  /// which produced an inconsistent state (Discovery content shown
  /// but bottom-nav still hidden).
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
      // `canPop:false` is what makes Android 13+ predictive-back deliver
      // the gesture to Dart instead of letting the OS finish the activity.
      // The framework calls our `onPopInvokedWithResult` for both legacy
      // and predictive-back paths — we then encode the full back-press
      // ladder in `_onBack`.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onBack();
      },
      child: isDesktop
          ? _buildDesktopShell(body, tab)
          : _buildMobileShell(body, tab, isSearching),
    );
  }

  Widget _buildDesktopShell(Widget body, int tab) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: DesktopWindowFrame(
        child: Row(
          children: [
            DesktopSideNav(
              currentIndex: tab,
              onTap: _setTab,
            ),
            Container(
              width: 1,
              color: Colors.white.withValues(alpha: 0.05),
            ),
            Expanded(child: body),
          ],
        ),
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
                  child: GlassBottomNav(
                    currentIndex: tab,
                    onTap: _setTab,
                  ),
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
    // 1. Keyboard always wins.
    final focus = FocusManager.instance.primaryFocus;
    final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;
    if (keyboardUp && focus != null && focus.hasFocus) {
      focus.unfocus();
      return;
    }

    final tab = ref.read(currentTabProvider);

    // 2. Active search on Explore → clear it instead of leaving the tab.
    if (tab == _exploreTabIndex && ref.read(isSearchActiveProvider)) {
      ref.read(searchClearSignalProvider.notifier).requestClear();
      return;
    }

    // 3. Not on Home → switch to Home. Reset the exit timer so the
    //    prompt always arms fresh when the user actually lands on Home.
    if (tab != _homeTabIndex) {
      _lastBackPress = null;
      _setTab(_homeTabIndex);
      return;
    }

    // 4. On Home, first back → arm exit prompt.
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last == null || now.difference(last) > _kDoubleTapWindow) {
      _lastBackPress = now;
      _showExitHint();
      return;
    }

    // 5. Second back within the window → leave the app.
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

/// Wraps a tab subtree in [AutomaticKeepAliveClientMixin] so an
/// ancestor rebuild (or a transient out-of-view scroll-into-view) can't
/// dispose its `State`. Combined with [IndexedStack] this gives every
/// tab the same lifecycle guarantees that `StatefulShellBranch`'s
/// nested Navigator provided.
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
