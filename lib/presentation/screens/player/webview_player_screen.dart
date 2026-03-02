import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/user_progress.dart';
import '../../../plugins/event_bridge/event_bridge.dart';
import '../../providers/watch_history_providers.dart';

/// Full-screen WebView player screen.
///
/// Opens a plugin's resolved URL in an in-app WebView with:
/// - Landscape orientation lock
/// - Glass close button overlay
/// - Progress tracking via EventBridge
class WebViewPlayerScreen extends ConsumerStatefulWidget {
  final String url;
  final MediaItem media;
  final String pluginName;

  const WebViewPlayerScreen({
    super.key,
    required this.url,
    required this.media,
    required this.pluginName,
  });

  @override
  ConsumerState<WebViewPlayerScreen> createState() =>
      _WebViewPlayerScreenState();
}

class _WebViewPlayerScreenState extends ConsumerState<WebViewPlayerScreen> {
  // ignore: unused_field
  InAppWebViewController? _controller;
  late final EventBridge _eventBridge;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    // Lock to landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Hide system UI for immersive
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Set up event bridge for progress tracking
    _eventBridge = EventBridge(onProgressUpdate: _onProgressUpdate);
  }

  @override
  void dispose() {
    // Restore portrait orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );

    super.dispose();
  }

  void _onProgressUpdate(PlayerEvent event) {
    if (event.duration <= 0) return;

    final progress = UserProgress(
      mediaId: widget.media.tmdbId.toString(),
      mediaType: widget.media.type.name,
      title: widget.media.title,
      posterPath: widget.media.posterPath,
      percentage: event.progress,
      currentTime: event.currentTime,
      duration: event.duration,
      season: event.season,
      episode: event.episode,
      lastPlayedDate: DateTime.now(),
    );

    ref.read(watchHistoryRepositoryProvider).saveProgress(progress);
    // Invalidate continue watching so it refreshes when we go back
    ref.invalidate(continueWatchingProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ─── WebView ──────────────────────────────────────────
          InAppWebView(
            preventGestureDelay: true,
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptEnabled: true,
              domStorageEnabled: true,
              supportZoom: false,
              // Opaque background reduces GPU compositing overhead (avoids alpha blending)
              transparentBackground: false,
              cacheEnabled: true,
              disableContextMenu: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;

              // Listen for postMessage events from the player
              controller.addJavaScriptHandler(
                handlerName: 'spoviesEventBridge',
                callback: (args) {
                  if (args.isNotEmpty) {
                    _eventBridge.handleMessage(args[0].toString());
                  }
                },
              );
            },
            onLoadStart: (controller, url) {
              setState(() => _isLoading = true);
            },
            onLoadStop: (controller, url) {
              setState(() => _isLoading = false);

              // Inject a script to forward postMessage events to Flutter
              controller.evaluateJavascript(
                source: '''
                window.addEventListener('message', function(event) {
                  if (typeof event.data === 'string') {
                    window.flutter_inappwebview.callHandler('spoviesEventBridge', event.data);
                  } else if (typeof event.data === 'object') {
                    window.flutter_inappwebview.callHandler('spoviesEventBridge', JSON.stringify(event.data));
                  }
                });
              ''',
              );
            },
            onConsoleMessage: (controller, message) {
              if (kDebugMode) {
                debugPrint('WebView Console: ${message.message}');
              }
            },
          ),

          // ─── Loading indicator ─────────────────────────────────
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),

          // ─── Close Button (simple opaque — avoids BackdropFilter GPU cost) ─
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
              child: IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close Player',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
