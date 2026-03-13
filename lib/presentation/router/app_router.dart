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
    GoRoute(
      path: '/details',
      parentNavigatorKey: _rootKey,
      builder: (context, state) {
        final media = state.extra;
        if (media is! MediaItem) return const _RouteErrorScreen('/details');
        return DetailsScreen(media: media);
      },
    ),

    GoRoute(
      path: '/player',
      parentNavigatorKey: _rootKey,
      builder: (context, state) {
        final args = state.extra;
        if (args is! PlayerArgs) return const _RouteErrorScreen('/player');
        return WebViewPlayerScreen(
          url: args.url,
          media: args.media,
          pluginName: args.pluginName,
          resumeTimeSeconds: args.resumeTimeSeconds,
        );
      },
    ),

    GoRoute(
      path: '/all-media',
      parentNavigatorKey: _rootKey,
      builder: (context, state) {
        final args = state.extra;
        if (args is! AllMediaArgs) return const _RouteErrorScreen('/all-media');
        return AllMediaScreen(args: args);
      },
    ),

    // Settings sub-pages — pushed over the shell so the nav bar is hidden
    GoRoute(
      path: '/plugins',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const PluginManagementScreen(),
    ),

    GoRoute(
      path: '/licenses',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => Theme(
        data: ThemeData.dark(),
        child: const LicensePage(
          applicationName: 'Spovies',
          applicationVersion: '1.0.0',
        ),
      ),
    ),
  ],
);

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
    this.resumeTimeSeconds = 0,
    this.season,
    this.episode,
  });
}
