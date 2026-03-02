import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

// ─── Bridge JS — injected at document-end, guarded by flag ───────────────────

const _kBridgeJs = '''
(function() {
  if (window.__spoviesBridgeInit) return;
  window.__spoviesBridgeInit = true;
  window.addEventListener('message', function(e) {
    var d = (typeof e.data === 'string') ? e.data : JSON.stringify(e.data);
    if (d && window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('spoviesEventBridge', d);
    }
  });
})();
''';

// ─── CSS — injected at document-start ────────────────────────────────────────
// Disables text selection & long-press callouts globally.
// Does NOT touch pointer-events so scrollable lists remain fully interactive.

const _kNoSelectCss = '''
(function() {
  var s = document.createElement('style');
  s.textContent = [
    '* {',
    '  -webkit-user-select: none !important;',
    '  user-select: none !important;',
    '  -webkit-touch-callout: none !important;',
    '}',
  ].join('');
  (document.head || document.documentElement).appendChild(s);
})();
''';

/// Full-screen WebView player.
///
/// Design decisions:
/// - **No full-body GestureDetector** — the previous swipe-to-dismiss
///   wrapper was claiming all vertical drags in Flutter's gesture arena
///   before the WebView could receive them, breaking internal list scrolling.
///   Dismiss is handled by the × button and the Android back button only.
/// - **`gestureRecognizers`** — explicitly transfers vertical drag, horizontal
///   drag, and scale gesture ownership to the WebView so Flutter widgets
///   above it never compete.
/// - **`gestureNavigationEnabled: false`** — disables iOS WebView's built-in
///   swipe-to-navigate-back, which would otherwise conflict with content
///   that needs horizontal swiping (e.g. carousels, tab bars inside the player).
/// - **Landscape lock** — `SystemChrome.setPreferredOrientations` is called
///   in `initState`; `dispose` fully restores portrait + system UI.
///   The iOS `Info.plist` already declares both landscape orientations so the
///   lock works identically on iOS and Android.
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
  InAppWebViewController? _controller;
  late final EventBridge _eventBridge;

  int _loadProgress = 0;
  bool _hasError = false;
  String _errorMsg = '';

  // ─── Gesture recognizers — transferred to the WebView ────────────────────
  // Giving explicit ownership of these gestures to the WebView prevents the
  // Flutter widget tree from competing, which is the root cause of scroll
  // breakage in embedded lists.
  static final _webViewGestures =
      <Factory<OneSequenceGestureRecognizer>>{
        Factory<VerticalDragGestureRecognizer>(
          VerticalDragGestureRecognizer.new,
        ),
        Factory<HorizontalDragGestureRecognizer>(
          HorizontalDragGestureRecognizer.new,
        ),
        Factory<ScaleGestureRecognizer>(ScaleGestureRecognizer.new),
        Factory<LongPressGestureRecognizer>(LongPressGestureRecognizer.new),
      };

  @override
  void initState() {
    super.initState();
    _lockLandscape();
    _eventBridge = EventBridge(onProgressUpdate: _onProgressUpdate);
  }

  @override
  void dispose() {
    _restorePortrait();
    super.dispose();
  }

  // ─── Orientation ─────────────────────────────────────────────────────────

  void _lockLandscape() {
    // Works on Android and iOS (Info.plist already allows landscape).
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Immersive mode: hides nav bar + status bar for full viewport.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restorePortrait() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  // ─── Progress Tracking ───────────────────────────────────────────────────

  void _onProgressUpdate(PlayerEvent event) {
    if (event.duration <= 0) return;
    final progress = UserProgress(
      mediaId: widget.media.tmdbId.toString(),
      mediaType: widget.media.type.name,
      title: widget.media.title,
      posterPath: widget.media.posterPath,
      percentage: event.progress * 100,
      currentTime: event.currentTime,
      duration: event.duration,
      season: event.season,
      episode: event.episode,
      lastPlayedDate: DateTime.now(),
    );
    ref.read(watchHistoryRepositoryProvider).saveProgress(progress);
    ref.invalidate(continueWatchingProvider);
  }

  // ─── Settings ────────────────────────────────────────────────────────────

  InAppWebViewSettings get _settings => InAppWebViewSettings(
    // Playback
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    allowsPictureInPictureMediaPlayback: true,

    // JavaScript & Storage
    javaScriptEnabled: true,
    domStorageEnabled: true,
    cacheEnabled: true,

    // Scroll & touch
    // NOTE: do NOT set isScrollEnabled: false — lists inside the player
    // depend on the WebView's native scroll.
    supportZoom: false,
    disableContextMenu: true,

    // iOS: disable swipe-back/forward navigation so it doesn't intercept
    // horizontal swipes inside the player UI (e.g. carousels, tab bars).
    allowsBackForwardNavigationGestures: false,

    // Rendering
    transparentBackground: false,

    // Reduce unnecessary resource tracking
    useOnLoadResource: false,
  );

  List<UserScript> get _userScripts => [
    UserScript(
      source: _kNoSelectCss,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    UserScript(
      source: _kBridgeJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
    ),
  ];

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // No GestureDetector wrapper — touch events go directly to WebView.
        body: Stack(
          children: [
            _hasError ? _buildErrorState() : _buildWebView(),
            _buildLoadingOverlay(),
            _buildProgressBar(),
            _buildCloseButton(),
          ],
        ),
      ),
    );
  }

  // ─── WebView ─────────────────────────────────────────────────────────────

  Widget _buildWebView() {
    return InAppWebView(
      preventGestureDelay: true,
      gestureRecognizers: _webViewGestures,
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
      initialSettings: _settings,
      initialUserScripts: UnmodifiableListView(_userScripts),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'spoviesEventBridge',
          callback: (args) {
            if (args.isNotEmpty) {
              _eventBridge.handleMessage(args[0].toString());
            }
          },
        );
      },
      onProgressChanged: (controller, progress) {
        if (!mounted) return;
        setState(() {
          _loadProgress = progress;
          if (progress > 0 && _hasError) _hasError = false;
        });
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) {
          if (!mounted) return;
          setState(() {
            _hasError = true;
            _errorMsg = error.description;
          });
        }
      },
      onConsoleMessage: (controller, message) {
        if (kDebugMode) debugPrint('WebView: ${message.message}');
      },
    );
  }

  // ─── Progress Bar ─────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    if (_loadProgress >= 100 || _hasError) return const SizedBox.shrink();
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: LinearProgressIndicator(
        value: _loadProgress / 100,
        backgroundColor: Colors.white12,
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
        minHeight: 2,
      ),
    );
  }

  // ─── Initial Loading Overlay ──────────────────────────────────────────────

  Widget _buildLoadingOverlay() {
    // Only shown during the very first load (progress ≤ 15%).
    if (_hasError || _loadProgress > 15) return const SizedBox.shrink();
    return Container(
      color: Colors.black,
      child: const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      ),
    );
  }

  // ─── Error State ─────────────────────────────────────────────────────────

  Widget _buildErrorState() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Colors.white38,
                size: 56,
              ),
              const SizedBox(height: 16),
              const Text(
                'Failed to load player',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMsg,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Close Button ─────────────────────────────────────────────────────────

  Widget _buildCloseButton() {
    return Positioned(
      top: 12,
      right: 16,
      child: SafeArea(
        child: Material(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
            onTap: _dismiss,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  void _dismiss() {
    if (mounted) Navigator.pop(context);
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _loadProgress = 0;
    });
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.url)));
  }
}
