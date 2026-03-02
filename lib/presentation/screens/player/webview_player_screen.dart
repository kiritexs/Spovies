import 'dart:collection';

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

// ─── JavaScript injected at document-end (once, guarded by flag) ─────────────

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

// ─── CSS injected at document-start to disable text selection globally ────────

const _kNoSelectCss = '''
(function() {
  var s = document.createElement('style');
  s.textContent = '* { -webkit-user-select: none !important; '
    + 'user-select: none !important; '
    + '-webkit-touch-callout: none !important; } '
    + 'video, canvas, img { pointer-events: auto !important; }';
  (document.head || document.documentElement).appendChild(s);
})();
''';

/// Full-screen WebView player screen.
///
/// Features:
/// - Landscape orientation lock + immersive mode
/// - Non-selectable text (CSS UserScript at document start)
/// - Deduped postMessage → EventBridge (JS guarded by flag)
/// - Linear progress bar during load
/// - Swipe-down to dismiss
/// - Error state with retry
/// - Progress tracking → WatchHistory
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

  // Swipe-to-dismiss tracking
  double _dragStart = 0;
  static const _kDismissThreshold = 120.0;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _eventBridge = EventBridge(onProgressUpdate: _onProgressUpdate);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    super.dispose();
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

  // ─── WebView Settings ────────────────────────────────────────────────────

  InAppWebViewSettings get _settings => InAppWebViewSettings(
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    javaScriptEnabled: true,
    domStorageEnabled: true,
    supportZoom: false,
    transparentBackground: false,
    cacheEnabled: true,
    disableContextMenu: true,
    // Improve touch responsiveness
    useOnLoadResource: false,
  );

  List<UserScript> get _userScripts => [
    // Disable text selection at document start (before content paints)
    UserScript(
      source: _kNoSelectCss,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    // Bridge listener at document end (DOM ready)
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
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await _saveProgressOnExit();
          if (mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onVerticalDragStart: (d) => _dragStart = d.globalPosition.dy,
          onVerticalDragEnd: (d) {
            final delta = d.globalPosition.dy - _dragStart;
            if (delta > _kDismissThreshold) _dismiss();
          },
          child: Stack(
            children: [
              _hasError ? _buildErrorState() : _buildWebView(),
              _buildProgressBar(),
              _buildCloseButton(),
              if (_loadProgress < 100 && !_hasError) _buildLoadingOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── WebView ─────────────────────────────────────────────────────────────

  Widget _buildWebView() {
    return InAppWebView(
      preventGestureDelay: true,
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
        setState(() {
          _loadProgress = progress;
          if (progress > 0) _hasError = false;
        });
      },
      onReceivedError: (controller, request, error) {
        // Only show error for main frame failures
        if (request.isForMainFrame ?? false) {
          setState(() {
            _hasError = true;
            _errorMsg = error.description;
          });
        }
      },
      onConsoleMessage: (controller, message) {
        if (kDebugMode) {
          debugPrint('WebView: ${message.message}');
        }
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

  // ─── Loading Overlay (initial) ────────────────────────────────────────────

  Widget _buildLoadingOverlay() {
    if (_loadProgress > 15) return const SizedBox.shrink();
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Failed to load player',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
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
              padding: EdgeInsets.all(8),
              child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _dismiss() async {
    await _saveProgressOnExit();
    if (mounted) Navigator.pop(context);
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _loadProgress = 0;
    });
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.url)));
  }

  Future<void> _saveProgressOnExit() async {
    // Final progress save is already throttled by EventBridge;
    // nothing extra needed here. Left as hook for future use.
  }
}
