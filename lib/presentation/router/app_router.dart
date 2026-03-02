import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/media_item.dart';
import '../screens/details/details_screen.dart';
import '../screens/explore/all_media_screen.dart';
import '../screens/explore/discover_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/player/webview_player_screen.dart';
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
        final media = state.extra as MediaItem;
        return DetailsScreen(media: media);
      },
    ),

    GoRoute(
      path: '/player',
      parentNavigatorKey: _rootKey,
      builder: (context, state) {
        final args = state.extra as PlayerArgs;
        return WebViewPlayerScreen(
          url: args.url,
          media: args.media,
          pluginName: args.pluginName,
        );
      },
    ),

    GoRoute(
      path: '/all-media',
      parentNavigatorKey: _rootKey,
      builder: (context, state) {
        final args = state.extra as AllMediaArgs;
        return AllMediaScreen(args: args);
      },
    ),
  ],
);

// ─── Player Args ──────────────────────────────────────────────────────────────

/// Passed as `extra` when pushing to `/player`.
class PlayerArgs {
  final String url;
  final MediaItem media;
  final String pluginName;

  const PlayerArgs({
    required this.url,
    required this.media,
    required this.pluginName,
  });
}
