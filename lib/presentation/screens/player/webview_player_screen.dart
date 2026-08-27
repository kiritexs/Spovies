import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/host_utils.dart';
import '../../../core/utils/player_platform.dart';
import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/media_type.dart';
import '../../../domain/entities/user_progress.dart';
import '../../../plugins/event_bridge/event_bridge.dart';
import '../../../plugins/protocol/plugin_url_resolver.dart';
import '../../../plugins/protocol/trigger_hook.dart';
import '../../providers/plugin_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/watch_history_providers.dart';
import '../../providers/webview_providers.dart';
import '../../router/app_router.dart';
import '../../../data/services/remote_blocklist.dart';
import 'player_scripts.dart';
import 'web_view_player_config.dart';
import 'widgets/next_episode_overlay.dart';
import 'widgets/player_error_view.dart';
import 'widgets/player_window_actions.dart';

/// Full-screen WebView player.
///
/// Injected JS lives in `assets/js/`, loaded at startup by
/// `PlayerScripts.load()`; the `UserScript` list is assembled in
/// `web_view_player_config.dart`.
///
/// See `docs/architecture/PLAYER.md` for gesture ownership, orientation
/// handling, hijack recovery, and the rebuild-cost optimisations.
class WebViewPlayerScreen extends ConsumerStatefulWidget {
  final String url;
  final MediaItem media;
  final String pluginName;

  /// Plugin ID for saving as [UserProgress.lastPluginId] when progress is saved.
  final String? pluginId;

  /// If > 0, the player will attempt to seek the <video> to this position
  /// (in seconds) once the page finishes loading.
  final double resumeTimeSeconds;

  /// For TV episodes — used when the bridge event has null season/episode.
  final int? season;
  final int? episode;

  const WebViewPlayerScreen({
    super.key,
    required this.url,
    required this.media,
    required this.pluginName,
    this.pluginId,
    this.resumeTimeSeconds = 0,
    this.season,
    this.episode,
  });

  @override
  ConsumerState<WebViewPlayerScreen> createState() =>
      _WebViewPlayerScreenState();
}

class _WebViewPlayerScreenState extends ConsumerState<WebViewPlayerScreen>
    with WidgetsBindingObserver, WindowListener {
  /// A notifier, not `setState` — only the progress bar and initial-load
  /// overlay react. See PLAYER.md § Rebuild-cost optimisations.
  final ValueNotifier<double> _loadProgress = ValueNotifier<double>(0);

  bool _isNavigating = false;

  /// `true` while handing off to another `/player` route ("Play Next").
  /// `dispose()` skips `_restorePortrait` when set — see PLAYER.md
  /// § Episode handoff for the iOS rotation race this avoids.
  bool _navigatingToAnotherPlayer = false;

  EventBridge? _eventBridge;

  // Stored so imperative operations (reload, goBack, etc.) are possible.
  InAppWebViewController? _controller;

  bool _hasError = false;
  String _errorMsg = '';
  bool _isFullScreen = false;

  Timer? _controlsTimer;
  bool _showControls = true;

  /// Epoch ms of the last actual re-arm. Coalesces the per-frame pointer
  /// flood on Windows into one Timer cancel + recreate per window.
  int _lastControlsTimerResetMs = 0;
  static const int _kControlsTimerCoalesceMs = 500;

  bool _showNextEpisodeOverlay = false;
  bool _overlayActive = false; // Controls animation (slide/fade)
  bool _dismissedNextEpisodeOverlay = false;
  int? _lastNextEpisodeTriggered; // episode number to avoid repeat popups
  Timer? _overlayTimer;

  /// Gap between the iOS 16+ orientation relaxation call and the landscape
  /// lock. See PLAYER.md § The iOS two-step lock.
  static const Duration _kIosOrientationCommitDelay = Duration(
    milliseconds: 50,
  );

  /// Latches on the first completed main-frame load. Gates the cross-domain
  /// check — see PLAYER.md § Cross-domain main-frame guard.
  bool _initialLoadComplete = false;

  /// Registered domain of the original URL (`example.com` for
  /// `https://www.example.com/embed/123`). PSL-backed via [HostUtils] so
  /// multi-part TLDs work; computed once so each check is an O(1) compare.
  late final String _initialHostBase = HostUtils.registeredDomain(
    Uri.tryParse(widget.url)?.host ?? '',
  );

  /// Stable cache key for [nextEpisodeForProgressProvider], hoisted out of
  /// `build` to cut allocator pressure on the chrome rebuild path.
  late final UserProgress _nextEpisodeKey = UserProgress(
    mediaId: widget.media.tmdbId.toString(),
    mediaType: 'tv',
    title: widget.media.title,
    percentage: 100,
    currentTime: 0,
    duration: 0,
    season: widget.season,
    episode: widget.episode,
    lastPlayedDate: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Cached in `initState` so `dispose()` can invalidate providers without
  /// touching `ref` — Riverpod 3.x throws once the element starts
  /// unmounting. `listen: false` avoids registering a dependency that
  /// would fire `didChangeDependencies`.
  late final ProviderContainer _providerContainer;

  /// Latched at the top of [dispose]. WebView callbacks the native side can
  /// still fire during teardown check this — `mounted` only flips after
  /// `super.dispose()` returns, which is too late on Windows.
  bool _disposed = false;

  // LongPressGestureRecognizer is deliberately NOT transferred to the
  // WebView — it adds a ~500 ms gesture-arena delay before taps forward,
  // making buttons feel like they need a double click.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _providerContainer = ProviderScope.containerOf(context, listen: false);

    // Fail closed: the URI must parse, use http(s), and have a host.
    // `initialUrlRequest` bypasses `shouldOverrideUrlLoading` on Android,
    // and an empty host silently disables the cross-domain guard below.
    // Defence-in-depth — the install path validates this too.
    final initialUri = Uri.tryParse(widget.url);
    final initialScheme = initialUri?.scheme.toLowerCase() ?? '';
    final initialHost = initialUri?.host ?? '';
    if (initialUri == null ||
        (initialScheme != 'http' && initialScheme != 'https') ||
        initialHost.isEmpty) {
      _hasError = true;
      _errorMsg = 'Invalid stream URL';
      return;
    }

    // Delay the orientation lock until after the first frame on iOS to
    // prevent race conditions with the screen transition.
    if (PlayerPlatform.isIOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lockLandscape();
      });
    } else {
      _lockLandscape();
    }

    _eventBridge = EventBridge(onProgressUpdate: _onProgressUpdate);
    if (PlayerPlatform.isWindows) {
      // Keeps `_isFullScreen` in sync when the user toggles fullscreen
      // outside our own button (F11, title-bar double-click, OS shortcut).
      windowManager.addListener(this);
      _checkFullScreen();
    }
    _resetControlsTimer();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted && !_isFullScreen) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted && _isFullScreen) setState(() => _isFullScreen = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Plugins fire `pause` unreliably (HLS.js wrappers, custom MSE), so
    // flush Continue Watching ourselves when the OS backgrounds us.
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden) &&
        _progressDirty) {
      _providerContainer.invalidate(continueWatchingProvider);
      _providerContainer.invalidate(episodeProgressProvider);
      _progressDirty = false;
    }
  }

  void _resetControlsTimer() {
    if (!mounted) return;

    // Hot path — pointer moves fire every frame on desktop. Only setState
    // when something actually changes.
    final overlayShouldShow =
        _showNextEpisodeOverlay && !_dismissedNextEpisodeOverlay;
    final overlayNeedsUpdate = overlayShouldShow && !_overlayActive;

    if (!_showControls || overlayNeedsUpdate) {
      setState(() {
        _showControls = true;
        if (overlayNeedsUpdate) {
          _overlayActive = true;
          _startOverlayTimer();
        }
      });
    }

    // Coalesce Timer churn — re-arm at most once per window.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastControlsTimerResetMs < _kControlsTimerCoalesceMs) return;
    _lastControlsTimerResetMs = now;

    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _startOverlayTimer() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _overlayActive) {
        setState(() => _overlayActive = false);
      }
    });
  }

  Future<void> _checkFullScreen() async {
    final isFullscreen = await windowManager.isFullScreen();
    if (!mounted) return;
    // The WindowListener may have updated `_isFullScreen` during the await.
    // Only push state if it would actually change.
    if (_isFullScreen != isFullscreen) {
      setState(() => _isFullScreen = isFullscreen);
    }
  }

  @override
  void dispose() {
    // Latch FIRST so in-flight WebView callbacks short-circuit.
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (PlayerPlatform.isWindows) {
      windowManager.removeListener(this);
    }
    _controlsTimer?.cancel();
    _overlayTimer?.cancel();
    _cleanupWebView();
    // Break the retain cycle — the bridge captures `this`.
    _eventBridge = null;
    _loadProgress.dispose();
    // Flush progress written this session but never committed by a
    // pause/ended event.
    if (_progressDirty) {
      _providerContainer.invalidate(continueWatchingProvider);
      _providerContainer.invalidate(episodeProgressProvider);
    }
    if (!_navigatingToAnotherPlayer) {
      _restorePortrait();
    }
    super.dispose();
  }

  /// Centralized cleanup to ensure the WebView stops all background work.
  /// Called before navigation and during disposal.
  void _cleanupWebView() {
    final controller = _controller;
    if (controller != null) {
      // Drop the handler BEFORE nulling the controller — its closure
      // captures `this`, and on Windows the native controller can outlive
      // the platform view, leaking one State per playback.
      try {
        controller.removeJavaScriptHandler(handlerName: 'spoviesEventBridge');
      } catch (e) {
        // Throws on Windows during transitional WebView2 states. The
        // controller is about to be released anyway.
        if (kDebugMode) {
          debugPrint('Player: removeJavaScriptHandler failed: $e');
        }
      }
      // Windows is sensitive to imperative calls during disposal — let the
      // native platform view dispose itself.
      if (!PlayerPlatform.isWindows) {
        controller.stopLoading();
      }
      _controller = null;
    }
  }

  // ─── Hijack recovery (Windows/WebView2 only) ─────────────────────────────
  //
  // Handles the about:blank click-jacker and the SmartScreen takeover.
  // Rate-limited by a per-type cooldown plus a global sliding-window
  // circuit breaker. See `docs/architecture/PLAYER.md` § Hijack recovery.
  final Map<String, DateTime> _lastRecoveryByType = {};
  final List<DateTime> _recentRecoveries = [];
  static const Duration _kRecoveryCooldown = Duration(seconds: 2);
  static const int _kMaxRecoveriesPerWindow = 3;
  static const Duration _kRecoveryWindowDuration = Duration(seconds: 15);

  Future<void> _recoverFromHijack(
    InAppWebViewController controller,
    String reason, {
    required String type,
  }) async {
    final now = DateTime.now();
    final lastForType = _lastRecoveryByType[type];
    if (lastForType != null &&
        now.difference(lastForType) < _kRecoveryCooldown) {
      if (kDebugMode) {
        debugPrint('Player: $type recovery skipped (cooldown): $reason');
      }
      return;
    }

    // Sliding-window prune — drop entries older than the window.
    _recentRecoveries.removeWhere(
      (t) => now.difference(t) > _kRecoveryWindowDuration,
    );
    if (_recentRecoveries.length >= _kMaxRecoveriesPerWindow) {
      if (kDebugMode) {
        debugPrint(
          'Player: recovery circuit breaker tripped '
          '(${_recentRecoveries.length} attempts in '
          '${_kRecoveryWindowDuration.inSeconds}s) — showing error',
        );
      }
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMsg =
              'This source keeps redirecting or timing out.\n'
              'Try a different plugin or server.';
        });
      }
      return;
    }

    _recentRecoveries.add(now);
    _lastRecoveryByType[type] = now;
    if (kDebugMode) {
      debugPrint(
        'Player: hijack recovery '
        '(${_recentRecoveries.length}/$_kMaxRecoveriesPerWindow, '
        'type=$type) — $reason',
      );
    }

    // Native calls throw E_INVALIDARG on Windows during transitional
    // WebView2 states; don't let those leak as unhandled async errors.
    try {
      await controller.stopLoading();
      if (!mounted) return;
      // Prefer goBack() — WebView2's history still holds the embed page, so
      // server selection and video element state survive.
      final canGoBack = await controller.canGoBack();
      if (!mounted) return;
      if (canGoBack) {
        await controller.goBack();
      } else {
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(widget.url)),
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Player: recovery controller call failed: $e\n$st');
      }
      // Roll back the entry — a failed call must not burn breaker budget
      // without having actually attempted a recovery.
      if (_recentRecoveries.isNotEmpty && _recentRecoveries.last == now) {
        _recentRecoveries.removeLast();
      }
    }
  }

  // ─── Orientation ─────────────────────────────────────────────────────────

  Future<void> _lockLandscape() async {
    if (!PlayerPlatform.supportsOrientationLock) return;

    if (PlayerPlatform.isIOS) {
      // Relax the supported set first — iOS 16+ rejects a landscape-only
      // call with "None of the requested orientations are supported".
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);
      await Future.delayed(_kIosOrientationCommitDelay);
      // If the route was popped during the delay, the call below would
      // land on the parent screen and strand it in landscape.
      if (_disposed) return;
    }

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _restorePortrait() async {
    if (!PlayerPlatform.supportsOrientationLock) return;
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  // ─── Progress Tracking ───────────────────────────────────────────────────

  /// Whether anything was persisted this session, so lifecycle events know
  /// to invalidate Continue Watching once.
  bool _progressDirty = false;

  void _onProgressUpdate(PlayerEvent event) {
    if (!mounted) return;
    if (event.duration <= 0) return;

    final progress = UserProgress(
      mediaId: widget.media.tmdbId.toString(),
      mediaType: widget.media.type.name,
      title: widget.media.title,
      posterPath: widget.media.posterPath,
      percentage: event.progress,
      currentTime: event.currentTime,
      duration: event.duration,
      season: event.season ?? widget.season,
      episode: event.episode ?? widget.episode,
      lastPlayedDate: DateTime.now(),
      lastPluginId: widget.pluginId,
    );

    // Fire-and-forget, but handled — a Hive failure must not escape as an
    // unhandled async error.
    unawaited(
      ref
          .read(watchHistoryRepositoryProvider)
          .saveProgress(progress)
          .catchError((Object e, StackTrace st) {
            if (kDebugMode) debugPrint('saveProgress failed: $e');
          }),
    );
    _progressDirty = true;

    // Only on pause/ended — the throttled timeupdate fires every ~5 s and
    // would rebuild the home screen continuously. The write above still
    // happens on every update, so progress survives a crash.
    final isLifecycle =
        event.eventType == 'pause' || event.eventType == 'ended';
    if (isLifecycle) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(episodeProgressProvider);
      _progressDirty = false;
    }

    // Already normalised to 0–100 by PlayerEvent.tryParse.
    final currentEp = event.episode ?? widget.episode;
    final pct = event.progress;

    if (widget.media.type == MediaType.tv && pct >= 95.0) {
      if (!_showNextEpisodeOverlay &&
          !_dismissedNextEpisodeOverlay &&
          _lastNextEpisodeTriggered != currentEp) {
        setState(() {
          _showNextEpisodeOverlay = true;
          _overlayActive = true;
          _lastNextEpisodeTriggered = currentEp;
          _startOverlayTimer();
        });
      }
    } else {
      // Re-arm the overlay once the user scrubs back far enough. Neither
      // field is read in build, so plain assignment is correct.
      if (pct < 90.0) {
        _dismissedNextEpisodeOverlay = false;
        _lastNextEpisodeTriggered = null;
      }

      if (_showNextEpisodeOverlay && pct < 95.0) {
        _overlayTimer?.cancel();
        setState(() {
          _showNextEpisodeOverlay = false;
          _overlayActive = false;
        });
      }
    }
  }

  // ─── WebView config — see web_view_player_config.dart ───────────────────

  InAppWebViewSettings get _settings => WebViewPlayerConfig.buildSettings();

  List<UserScript> get _userScripts => WebViewPlayerConfig.buildUserScripts(
    scripts: PlayerScripts.instance,
    resumeTimeSeconds: widget.resumeTimeSeconds,
  );

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (PlayerPlatform.isWindows) {
      final envAsync = ref.watch(webViewEnvironmentProvider);
      content = envAsync.when(
        data: (env) {
          if (_hasError) return _buildErrorState();
          return _buildWebView(env);
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        // Render directly without mutating state during build — that would
        // trip a setState-in-build assertion or permanently latch
        // `_hasError`, stranding the screen if the provider recovers.
        error: (err, _) => _buildErrorState(
          overrideMessage: 'WebView initialization failed: $err',
          onRetry: () => ref.invalidate(webViewEnvironmentProvider),
        ),
      );
    } else {
      content = _hasError ? _buildErrorState() : _buildWebView();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Pops one level to whoever pushed us (usually /details).
        // `_dismiss` also does the window-manager cleanup.
        _dismiss();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // One Listener covers every pointer kind. A MouseRegion + Listener
        // pair would double-fire every mouse event on Windows.
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _resetControlsTimer(),
          onPointerMove: (_) => _resetControlsTimer(),
          onPointerHover: (_) => _resetControlsTimer(),
          child: Stack(
            children: [
              content,
              _buildLoadingOverlay(),
              _buildProgressBar(),
              _buildWindowActions(),
              _buildNextEpisodeOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── WebView ─────────────────────────────────────────────────────────────

  Widget _buildWebView([WebViewEnvironment? environment]) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.expand();
        }

        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            // Always allow system volume keys to bubble up.
            if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
                event.logicalKey == LogicalKeyboardKey.audioVolumeDown ||
                event.logicalKey == LogicalKeyboardKey.audioVolumeMute) {
              return KeyEventResult.ignored;
            }

            // Ignore modifiers — otherwise Flutter's key-state tracker
            // desyncs and asserts on "Alt Left".
            if (event.logicalKey == LogicalKeyboardKey.altLeft ||
                event.logicalKey == LogicalKeyboardKey.altRight ||
                event.logicalKey == LogicalKeyboardKey.controlLeft ||
                event.logicalKey == LogicalKeyboardKey.controlRight ||
                event.logicalKey == LogicalKeyboardKey.shiftLeft ||
                event.logicalKey == LogicalKeyboardKey.shiftRight) {
              return KeyEventResult.ignored;
            }

            // Windows needs .handled for everything else, or the WebView
            // trips framework assertions during layout. Elsewhere .ignored
            // keeps system and hardware keys working.
            return PlayerPlatform.isWindows
                ? KeyEventResult.handled
                : KeyEventResult.ignored;
          },
          child: InAppWebView(
            // Full URL, not hashCode — String hashCode collides, and a
            // collision reuses the previous WebView state for a new URL.
            key: ValueKey('spovies_player_${widget.url}'),
            webViewEnvironment: environment,
            preventGestureDelay: true,
            // Mobile hands drag + scale to the WebView so embedded list
            // scroll stays smooth; desktop wants no competition at all.
            gestureRecognizers: PlayerPlatform.isDesktop
                ? const <Factory<OneSequenceGestureRecognizer>>{}
                : <Factory<OneSequenceGestureRecognizer>>{
                    Factory<VerticalDragGestureRecognizer>(
                      VerticalDragGestureRecognizer.new,
                    ),
                    Factory<HorizontalDragGestureRecognizer>(
                      HorizontalDragGestureRecognizer.new,
                    ),
                    Factory<ScaleGestureRecognizer>(ScaleGestureRecognizer.new),
                  },
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: _settings,
            initialUserScripts: UnmodifiableListView(_userScripts),
            onWebViewCreated: (controller) {
              _controller = controller;
              controller.addJavaScriptHandler(
                handlerName: 'spoviesEventBridge',
                callback: (args) {
                  if (args.isEmpty || _disposed) return;
                  final rawMessage = args[0].toString();

                  // Parse once at the boundary. A substring check for
                  // `"type":"USER_ACTIVITY"` collides with payloads that
                  // mention it in a nested field, silently dropping real
                  // PLAYER_EVENTs.
                  Map<String, dynamic>? parsed;
                  try {
                    final decoded = jsonDecode(rawMessage);
                    if (decoded is Map<String, dynamic>) parsed = decoded;
                  } catch (_) {
                    // Non-JSON — EventBridge.handleMessage handles it.
                  }
                  if (parsed?['type'] == 'USER_ACTIVITY') {
                    _resetControlsTimer();
                    return;
                  }
                  if (mounted) _eventBridge?.handleMessage(rawMessage);
                },
              );
            },
            onProgressChanged: (controller, progress) {
              // `_disposed` before `mounted` — native callbacks can land
              // between `_loadProgress.dispose()` and `super.dispose()`.
              if (_disposed || !mounted) return;
              // Latch once; gates the cross-domain check below.
              if (progress >= 100) _initialLoadComplete = true;
              _loadProgress.value = progress.toDouble();
            },
            onUpdateVisitedHistory: (controller, url, isReload) async {
              // about:blank click-jacker recovery. This is the earliest
              // callback WebView2 fires for the hijack — and deliberately
              // NOT gated on `_initialLoadComplete`. See PLAYER.md
              // § about:blank click-jacker.
              if (!PlayerPlatform.isWindows) return;
              if (_disposed || !mounted) return;
              final urlStr = url?.toString() ?? '';
              if (urlStr == 'about:blank' || urlStr.startsWith('about:')) {
                await _recoverFromHijack(
                  controller,
                  'about:blank navigation',
                  type: 'about_blank',
                );
              }
            },
            onTitleChanged: (controller, title) async {
              // SmartScreen takeover recovery — the URL stays unchanged
              // but the title flips to a known marker. Windows-only:
              // elsewhere such a title is just a normal page.
              if (!PlayerPlatform.isWindows) return;
              if (_disposed || !mounted) return;
              final t = title ?? '';
              const smartScreenMarkers = [
                'SmartScreen',
                'Reported Unsafe',
                'Navigation Blocked',
                'reported as unsafe',
              ];
              final hit = smartScreenMarkers.any(t.contains);
              if (hit) {
                await _recoverFromHijack(
                  controller,
                  'SmartScreen: "$t"',
                  type: 'smartscreen',
                );
              }
            },
            onReceivedError: (controller, request, error) {
              final isMainFrame = request.isForMainFrame ?? false;
              if (isMainFrame && _loadProgress.value < 50 && mounted) {
                setState(() {
                  _hasError = true;
                  _errorMsg = error.description;
                });
              }
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              final isMainFrame = request.isForMainFrame ?? false;
              final statusCode = errorResponse.statusCode ?? 0;
              if (isMainFrame && statusCode >= 500 && mounted) {
                setState(() {
                  _hasError = true;
                  _errorMsg = 'Server error ($statusCode)';
                });
              }
            },
            onConsoleMessage: (controller, message) {
              if (kDebugMode) {
                final msg = message.message;
                // Still filter out the most common noise.
                if (msg == 'undefined' ||
                    msg.toLowerCase().contains('console.clear') ||
                    msg.startsWith('[object Object]') ||
                    msg.startsWith('Array')) {
                  return;
                }
                // Some Windows sites flood with Adscore bot-detection logs.
                if (PlayerPlatform.isWindows && msg.contains('Adscore')) return;

                debugPrint('WebView: $msg');
              }
            },
            onPermissionRequest: (controller, request) async {
              // DRM only. Camera, mic, geolocation, MIDI and the rest are
              // never needed by a video player. (Not a real enum, so the
              // set can't be `const`.)
              final allowedResources = <PermissionResourceType>{
                PermissionResourceType.PROTECTED_MEDIA_ID,
              };

              final isAllSafe = request.resources.every(
                allowedResources.contains,
              );

              if (isAllSafe) {
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                );
              }

              if (kDebugMode) {
                debugPrint(
                  'Blocked unauthorized permission request: ${request.resources}',
                );
              }
              return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.DENY,
              );
            },
            onCreateWindow: (controller, createWindowAction) async {
              // No popups. On Windows this triggers WebView2's
              // navigate-current-frame fallback, recovered in
              // `onUpdateVisitedHistory`. Do NOT try to pre-empt that here
              // — see PLAYER.md § A pre-empt attempt that backfired.
              return false;
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              // Can fire after `dispose()` on Windows — gate before the
              // `_providerContainer.read` below races its own teardown.
              if (_disposed) return NavigationActionPolicy.CANCEL;

              final urlRequest = navigationAction.request;
              final url = urlRequest.url?.toString() ?? '';
              if (url.isEmpty) return NavigationActionPolicy.ALLOW;

              final scheme = urlRequest.url?.scheme ?? '';
              // Main-frame `javascript:` runs in the document's origin —
              // the textbook DOM-XSS vector. Sub-frames legitimately use
              // `href="javascript:void(0)"` as a no-op, so allow it there.
              if (navigationAction.isForMainFrame && scheme == 'javascript') {
                return NavigationActionPolicy.CANCEL;
              }
              if (scheme.isNotEmpty &&
                  scheme != 'https' &&
                  scheme != 'http' &&
                  scheme != 'blob' &&
                  scheme != 'data' &&
                  scheme != 'about' &&
                  scheme != 'javascript') {
                return NavigationActionPolicy.CANCEL;
              }

              // Click-jacker guard. Sub-frames are left alone — some
              // players use a brief about:blank intermediate in iframes.
              if (navigationAction.isForMainFrame &&
                  _initialLoadComplete &&
                  (url == 'about:blank' || scheme == 'about')) {
                return NavigationActionPolicy.CANCEL;
              }

              final blocklist =
                  _providerContainer.read(adBlocklistProvider).value ??
                  _providerContainer.read(adBlocklistFallbackProvider);
              if (blocklist?.isBlocked(url) ?? false) {
                return NavigationActionPolicy.CANCEL;
              }

              // Cross-domain main-frame guard. Gated on
              // `_initialLoadComplete`, not live progress — a programmatic
              // `location.assign` fires this while progress is dropping
              // back to 0, so a progress check would let it through.
              if (navigationAction.isForMainFrame &&
                  _initialLoadComplete &&
                  _initialHostBase.isNotEmpty) {
                final newBase = HostUtils.registeredDomain(
                  urlRequest.url?.host ?? '',
                );
                if (newBase.isNotEmpty && newBase != _initialHostBase) {
                  return NavigationActionPolicy.CANCEL;
                }
              }
              return NavigationActionPolicy.ALLOW;
            },
            shouldInterceptRequest: PlayerPlatform.useNativeAdBlocking
                ? (controller, request) async {
                    // Queued native callbacks can land after dispose.
                    if (_disposed) return null;
                    final url = request.url.toString();
                    final blocklist =
                        _providerContainer.read(adBlocklistProvider).value ??
                        _providerContainer.read(adBlocklistFallbackProvider);
                    if (blocklist?.isBlocked(url) ?? false) {
                      return WebResourceResponse(
                        contentType: 'text/plain',
                        data: null,
                      );
                    }
                    return null;
                  }
                : null,
          ),
        );
      },
    );
  }

  // ─── Progress Bar ─────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    if (_hasError) return const SizedBox.shrink();
    // ValueListenableBuilder so only this rebuilds on progress change.
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<double>(
        valueListenable: _loadProgress,
        builder: (context, progress, _) {
          if (progress >= 100) return const SizedBox.shrink();
          return LinearProgressIndicator(
            value: progress / 100,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 2,
          );
        },
      ),
    );
  }

  // ─── Initial Loading Overlay ──────────────────────────────────────────────

  Widget _buildLoadingOverlay() {
    if (_hasError) return const SizedBox.shrink();
    // IgnorePointer so taps still reach the WebView while the spinner is
    // up — otherwise the play button feels laggy.
    return ValueListenableBuilder<double>(
      valueListenable: _loadProgress,
      builder: (context, progress, _) {
        if (progress > 15) return const SizedBox.shrink();
        return IgnorePointer(
          child: Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Error State ─────────────────────────────────────────────────────────

  /// [overrideMessage] / [onRetry] let transient errors render their own
  /// message without touching `_hasError`/`_errorMsg`, which belong to the
  /// in-WebView load lifecycle.
  Widget _buildErrorState({String? overrideMessage, VoidCallback? onRetry}) {
    return PlayerErrorView(
      message: overrideMessage ?? _errorMsg,
      onRetry: onRetry ?? _retry,
    );
  }

  // ─── Window Actions ───────────────────────────────────────────────────────

  Widget _buildNextEpisodeOverlay() {
    if (!_showNextEpisodeOverlay) return const SizedBox.shrink();
    return NextEpisodeOverlay(
      progressKey: _nextEpisodeKey,
      fallbackBackdropPath: widget.media.backdropPath,
      active: _overlayActive,
      onPlayNext: _playNextEpisode,
      onDismiss: () {
        // Clearing the flag short-circuits the next build. Leaving it set
        // would keep the overlay's provider subscription alive off-screen.
        _overlayTimer?.cancel();
        setState(() {
          _showNextEpisodeOverlay = false;
          _overlayActive = false;
          _dismissedNextEpisodeOverlay = true;
        });
      },
      onHoverEnter: () => _overlayTimer?.cancel(),
      onHoverExit: _startOverlayTimer,
    );
  }

  void _playNextEpisode(int nextSeason, int nextEpisode) {
    if (!mounted) return;

    final plugins =
        ref.read(pluginsForHookProvider(TriggerHook.mediaHeader)).value ?? [];
    final plugin = PluginUrlResolver.pickPlugin(
      plugins,
      savedId: widget.pluginId,
      preferredId: ref.read(preferredPluginProvider),
    );
    if (plugin == null) return;

    final nextUrl = PluginUrlResolver.resolve(
      plugin,
      widget.media,
      season: nextSeason,
      episode: nextEpisode,
    );

    if (_isNavigating) return;
    _isNavigating = true;
    // Suppress our own portrait restore — the next player re-locks
    // landscape in its initState and iOS honours whichever call lands last.
    _navigatingToAnotherPlayer = true;

    _cleanupWebView();

    Future.microtask(() {
      if (!mounted) {
        // The route disappeared before the microtask ran. Reset both flags
        // so we don't leave the (now detached) state stuck pretending it's
        // mid-navigation.
        _isNavigating = false;
        _navigatingToAnotherPlayer = false;
        return;
      }
      try {
        context.pushReplacement(
          '/player',
          extra: PlayerArgs(
            url: nextUrl,
            media: widget.media,
            pluginName: plugin.name,
            pluginId: plugin.pluginId,
            season: nextSeason,
            episode: nextEpisode,
          ),
        );
      } catch (e) {
        _isNavigating = false;
        _navigatingToAnotherPlayer = false;
        if (kDebugMode) debugPrint('_playNextEpisode push failed: $e');
      }
    });
  }

  Widget _buildWindowActions() {
    return PlayerWindowActions(
      showControls: _showControls,
      isFullScreen: _isFullScreen,
      onToggleFullScreen: _toggleFullScreen,
      onDismiss: _dismiss,
    );
  }

  Future<void> _toggleFullScreen() async {
    final isFull = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFull);
    // No setState — the WindowListener owns `_isFullScreen` and writing
    // here would clobber it with the pre-toggle value if the user changed
    // fullscreen externally during the awaits.
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _dismiss() async {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      if (PlayerPlatform.isWindows) {
        await windowManager.setFullScreen(false);
      }
      if (!mounted) {
        // Already tearing down; unwedge the flag in case of a re-entrant
        // call after a quick rebuild.
        _isNavigating = false;
        return;
      }
      context.pop();
    } catch (e) {
      // Unwedge on any failure so the user can try again.
      _isNavigating = false;
      if (kDebugMode) debugPrint('_dismiss failed: $e');
    }
  }

  void _retry() {
    // Reset EVERY page-load-lifecycle latch — including the breaker and
    // cooldowns, or a user who tripped the breaker can't escape it here.
    _loadProgress.value = 0;
    _recentRecoveries.clear();
    _lastRecoveryByType.clear();
    _initialLoadComplete = false;
    setState(() {
      _hasError = false;
      _errorMsg = '';
    });
    // Explicit reload — the `ValueKey` is bound to an unchanged
    // `widget.url`, so the WebView is reused and would otherwise keep
    // showing the failed page.
    unawaited(
      _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.url))),
    );
  }
}
