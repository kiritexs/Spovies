import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/media_item.dart';
import '../screens/details/details_screen.dart';
import '../screens/explore/all_media_screen.dart';
import '../screens/player/webview_player_screen.dart';
import '../screens/settings/plugin_management_screen.dart';
import 'main_scaffold.dart';

// ─── Navigator Keys ───────────────────────────────────────────────────────────
//
// Only one navigator now — the root. Full-screen routes (/details, /player,
// /all-media, /plugins, /licenses) all push onto this navigator via
// `parentNavigatorKey: _rootKey`, which means they overlay [MainScaffold]
// and hide its bottom nav automatically.

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

// ─── Router ───────────────────────────────────────────────────────────────────
//
// Massively simpler than the prior `StatefulShellRoute.indexedStack` setup.
// Tab state lives in `currentTabProvider` (Riverpod), driven by
// [MainScaffold]'s `IndexedStack` — no branch navigators, no per-branch
// keys, no back-button dispatcher.
//
// System-back is handled by [MainScaffold]'s single root `PopScope`. See
// the long doc-comment at the top of that file for the full ladder.

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/',
  debugLogDiagnostics: false,
  routes: [
    // ── Main app (4-tab IndexedStack) ─────────────────────────────────────
    GoRoute(
      path: '/',
      builder: (context, state) => const MainScaffold(),
    ),

    // ── Full-screen routes pushed above the tab scaffold ──────────────────
    //
    // Each uses `parentNavigatorKey: _rootKey` so it stacks above
    // MainScaffold (hiding its nav bar). On back, the framework pops
    // this route normally and reveals MainScaffold with whichever tab
    // was active.
    //
    // The player keeps its own `PopScope` for window-manager cleanup.
    // The other routes just pop normally.
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
        return AllMediaScreen(args: args);
      },
    ),

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
