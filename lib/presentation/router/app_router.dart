import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/media_item.dart';
import '../screens/details/details_screen.dart';
import '../screens/explore/all_media_screen.dart';
import '../screens/explore/discover_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/player/webview_player_screen.dart';
import '../screens/settings/plugin_management_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/watchlist/watchlist_screen.dart';
import 'shell_scaffold.dart';

// ─── Navigator Keys ───────────────────────────────────────────────────────────
// The root key is used by full-screen routes (/details, /player) so they push
// over the shell and the nav bar disappears automatically.

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _homeKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _exploreKey = GlobalKey<NavigatorState>(debugLabel: 'explore');
final _browseKey = GlobalKey<NavigatorState>(debugLabel: 'browse');
final _profileKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

// ─── Router ───────────────────────────────────────────────────────────────────

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/home',
  debugLogDiagnostics: false,
  routes: [
    // ── Shell (tab bar always visible) ────────────────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => ShellScaffold(shell: shell),
      branches: [
        // Tab 0 — Home
        StatefulShellBranch(
          navigatorKey: _homeKey,
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),

        // Tab 1 — Explore (Discovery)
        StatefulShellBranch(
          navigatorKey: _exploreKey,
          routes: [
            GoRoute(
              path: '/explore',
              builder: (context, state) => const DiscoverScreen(),
            ),
          ],
        ),

        // Tab 2 — Browse (Watchlist)
        StatefulShellBranch(
          navigatorKey: _browseKey,
          routes: [
            GoRoute(
              path: '/browse',
              builder: (context, state) => const WatchlistScreen(),
            ),
          ],
        ),

        // Tab 3 — Profile (Settings)
        StatefulShellBranch(
          navigatorKey: _profileKey,
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),

    // ── Full-screen routes (push over shell, no nav bar) ──────────────────
    //
    // Every route below is wrapped in [_PopToHomeOnSystemBack] so the
    // Android system back gesture (and the in-app `Navigator.maybePop` it
    // triggers) takes the user directly to /home instead of popping one
    // level back to whatever tab they came from. Without this wrapper the
    // user would see inconsistent behaviour: when they enter /details
    // from the Home tab, system back lands on Home → shell PopScope fires
    // → "press back again to exit". When they enter /details from
    // Explore, system back lands on Explore → shell PopScope still fires
    // BUT only switches the branch to Home (step 3 in `_handleSystemBack`)
    // and never reaches the exit prompt on that first press. The result
    // was the "sometimes the prompt appears, sometimes it doesn't" bug.
    //
    // The wrapper keeps in-app `context.pop()` calls (e.g. the player's
    // × button → `_dismiss`) working as before — they go through
    // `Navigator.pop`, which the wrapper's `canPop: false` does NOT
    // intercept (those are explicit pops on the route stack, not pops
    // initiated by the system). Only system-back / Navigator.maybePop is
    // redirected here.
    GoRoute(
      path: '/details',
      parentNavigatorKey: _rootKey,
      builder: (context, state) {
        final media = state.extra;
        if (media is! MediaItem) return const _RouteErrorScreen('/details');
        return _PopToHomeOnSystemBack(child: DetailsScreen(media: media));
      },
    ),

    GoRoute(
      path: '/player',
      parentNavigatorKey: _rootKey,
      builder: (context, state) {
        final args = state.extra;
        if (args is! PlayerArgs) return const _RouteErrorScreen('/player');
        // Player owns its own PopScope (window-manager + cleanup
        // ordering). Do NOT wrap it again here — the inner PopScope wins
        // and the outer wrapper would never fire. Player's PopScope
        // already redirects system back through `_backToHome`.
        return WebViewPlayerScreen(
          url: args.url,
          media: args.media,
          pluginName: args.pluginName,
          pluginId: args.pluginId,
          resumeTimeSeconds: args.resumeTimeSeconds,
          season: args.season,
          episode: args.episode,
        );
      },
    ),

    GoRoute(
      path: '/all-media',
      parentNavigatorKey: _rootKey,
      builder: (context, state) {
        final args = state.extra;
        if (args is! AllMediaArgs) return const _RouteErrorScreen('/all-media');
        return _PopToHomeOnSystemBack(child: AllMediaScreen(args: args));
      },
    ),

    // Settings sub-pages — pushed over the shell so the nav bar is hidden
    GoRoute(
      path: '/plugins',
      parentNavigatorKey: _rootKey,
      builder: (context, state) =>
          const _PopToHomeOnSystemBack(child: PluginManagementScreen()),
    ),

    GoRoute(
      path: '/licenses',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => _PopToHomeOnSystemBack(
        child: Theme(
          data: ThemeData.dark(),
          child: const LicensePage(
            applicationName: 'Spovies',
            applicationVersion: '1.0.0',
          ),
        ),
      ),
    ),
  ],
);

// ─── PopScope wrapper: system back → /home ────────────────────────────────────

/// Wraps a full-screen route so the Android system back gesture takes
/// the user to /home instead of popping one level back to the previous
/// tab. See the comment above the routes for the full rationale.
class _PopToHomeOnSystemBack extends StatelessWidget {
  final Widget child;
  const _PopToHomeOnSystemBack({required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // `.go()` resets the navigator stack to /home: the current pushed
        // route is removed and the shell's Home branch becomes the live
        // page. The shell's own PopScope then handles the next system
        // back press (exit prompt + double-tap-to-exit).
        context.go('/home');
      },
      child: child,
    );
  }
}

// ─── Route Error Screen ───────────────────────────────────────────────────────
//
// Shown when a route is reached with the wrong (or missing) `extra` argument,
// e.g. via a deep link or after GoRouter's state restoration discards extras.

class _RouteErrorScreen extends StatelessWidget {
  final String routeName;
  const _RouteErrorScreen(this.routeName);

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      debugPrint(
        'Router: navigated to "$routeName" with invalid or null extra',
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Go Back',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Player Args ──────────────────────────────────────────────────────────────

/// Passed as `extra` when pushing to `/player`.
class PlayerArgs {
  final String url;
  final MediaItem media;
  final String pluginName;

  /// Plugin ID for saving as [UserProgress.lastPluginId] when progress is saved.
  final String? pluginId;

  /// If > 0, the player will attempt to seek the <video> element to this
  /// position (in seconds) once playback starts.
  final double resumeTimeSeconds;

  /// For TV episodes — used as the authoritative Hive key source so that
  /// the universal JS tracker (which never sends season/episode) still
  /// saves progress under the correct per-episode key.
  final int? season;
  final int? episode;

  const PlayerArgs({
    required this.url,
    required this.media,
    required this.pluginName,
    this.pluginId,
    this.resumeTimeSeconds = 0,
    this.season,
    this.episode,
  });
}
