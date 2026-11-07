import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/host_utils.dart';
import 'data/datasources/local/hive_service.dart';
import 'data/datasources/remote/tmdb_cache_interceptor.dart';
import 'presentation/router/app_router.dart';
import 'presentation/screens/player/player_scripts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Init local persistence, the bundled Public Suffix List, and the
  // player's injected JS in parallel. All three must be ready before
  // any UI loads:
  //   • Hive — every repository depends on it
  //   • PSL — backs the player's cross-domain navigation guard and the
  //     ad blocklist's eTLD+1 lookup
  //   • PlayerScripts — the WebView player constructs its UserScript
  //     list synchronously and throws if scripts aren't loaded
  await Future.wait([
    HiveService.init(),
    HostUtils.init(),
    PlayerScripts.load(),
  ]);
  // The bundled font's licence, shown on the Licenses page.
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Spline Sans'], ofl);
  });
  // Not awaited: trimming old TMDB responses must not delay startup.
  unawaited(TmdbCacheInterceptor.prune(HiveService.tmdbCacheBox));

  // Desktop Specific Initialization
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(960, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // Use custom title bar
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  // Mobile Specific Initialization
  else if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0A0A0C),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  runApp(
    ProviderScope(
      // Riverpod retries failed providers up to 10 times by default. Dio's
      // RetryInterceptor already retries network and 5xx errors, so a
      // second layer only delays the error screen (minutes when offline).
      // Retry buttons invalidate the provider instead.
      retry: (_, _) => null,
      child: const SpoviesApp(),
    ),
  );
}

// Enable Mouse dragging for Desktop Web/Windows
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse, // Ensures mouse users can drag horizontal lists
  };
}

/// Root app widget.
///
/// Now a plain `StatelessWidget` — all the back-handling and tab state
/// lives inside [MainScaffold] (driven by `currentTabProvider`). This
/// file used to register a global `BackButtonInterceptor`, a custom
/// `RootBackButtonDispatcher`, and various per-tab handlers, all of
/// which were replaced by the single `PopScope(canPop:false)` at the
/// root of [MainScaffold]. See the doc-comment on that class for why.
class SpoviesApp extends StatelessWidget {
  const SpoviesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Spovies',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      scrollBehavior: AppScrollBehavior(),
    );
  }
}
