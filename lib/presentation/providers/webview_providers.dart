import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Shared [WebViewEnvironment] for Windows to prevent process bloat.
/// All WebView instances will share the same renderer and utility processes.
final webViewEnvironmentProvider = FutureProvider<WebViewEnvironment?>((
  ref,
) async {
  if (kIsWeb || !Platform.isWindows) return null;

  try {
    final supportDir = await getApplicationSupportDirectory();
    final userDataFolder = '${supportDir.path}\\Spovies_WebView2';

    if (kDebugMode) {
      debugPrint('Initializing shared WebViewEnvironment at: $userDataFolder');
    }

    return await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(userDataFolder: userDataFolder),
    );
  } catch (e) {
    if (kDebugMode) debugPrint('WebViewEnvironment.create error: $e');
    // Rethrow so the player shows its error view with Retry (which
    // invalidates this provider). Returning null used to fall back to
    // WebView2's default data folder, which may not be writable.
    rethrow;
  }
});
