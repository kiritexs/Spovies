import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Shared [WebViewEnvironment] for Windows to prevent process bloat.
/// All WebView instances will share the same renderer and utility processes.
final webViewEnvironmentProvider = FutureProvider<WebViewEnvironment?>((ref) async {
  if (kIsWeb || !Platform.isWindows) return null;
  
  try {
    final supportDir = await getApplicationSupportDirectory();
    final userDataFolder = '${supportDir.path}\\Spovies_WebView2';
    
    if (kDebugMode) {
      debugPrint('Initializing shared WebViewEnvironment at: $userDataFolder');
    }
    
    return await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: userDataFolder,
      ),
    );
  } catch (e) {
    debugPrint('WebViewEnvironment.create error: $e');
    // If initialization fails, we return null and the WebView will 
    // fall back to default behavior (or error UI in the screen).
    return null;
  }
});
