import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// In-memory cache of the player's injected JS, loaded once from
/// `assets/js/` at app startup.
///
/// Putting the scripts in real `.js` files (instead of inline Dart string
/// constants) buys us:
///   • syntax highlighting + ESLint / JSHint tooling on the source files
///   • diff readability — JS changes don't move Dart line numbers
///   • the ability to run a real JS test harness against each script
///
/// Lifecycle:
///   1. `main()` awaits `PlayerScripts.load()` alongside `HiveService.init()`
///      and `HostUtils.init()`. By the time `runApp` runs, all scripts are
///      cached.
///   2. The player screen reads them through `PlayerScripts.instance`.
///      Accessing `.instance` before `load()` throws `StateError` — fail
///      loudly rather than silently inject empty scripts.
class PlayerScripts {
  PlayerScripts._({
    required this.bridge,
    required this.isAd,
    required this.adGuard,
    required this.consoleKiller,
    required this.adRemoval,
    required this.suppressFullscreen,
    required this.iosInlineVideo,
    required this.brandHide,
    required this.noSelectCss,
    required this.userActivity,
    required String videoProgressTemplate,
  }) : _videoProgressTemplate = videoProgressTemplate;

  static PlayerScripts? _cached;

  /// The placeholder substituted in `player_video_progress.js`. Kept in
  /// sync with the literal token inside that file.
  static const String _resumeTargetToken = '__SPOVIES_RESUME_TARGET__';

  /// Pre-load every script. Safe to call more than once — only the first
  /// call hits `rootBundle`.
  static Future<void> load() async {
    if (_cached != null) return;
    Future<String> read(String name) =>
        rootBundle.loadString('assets/js/$name');
    final results = await Future.wait([
      read('player_bridge.js'),
      read('player_is_ad.js'),
      read('player_adguard.js'),
      read('player_console_killer.js'),
      read('player_ad_removal.js'),
      read('player_suppress_fullscreen.js'),
      read('player_ios_inline_video.js'),
      read('player_brand_hide.js'),
      read('player_no_select_css.js'),
      read('player_user_activity.js'),
      read('player_video_progress.js'),
    ]);
    _cached = PlayerScripts._(
      bridge: results[0],
      isAd: results[1],
      adGuard: results[2],
      consoleKiller: results[3],
      adRemoval: results[4],
      suppressFullscreen: results[5],
      iosInlineVideo: results[6],
      brandHide: results[7],
      noSelectCss: results[8],
      userActivity: results[9],
      videoProgressTemplate: results[10],
    );
    if (kDebugMode) {
      debugPrint('PlayerScripts: loaded ${results.length} scripts from '
          'assets/js/');
    }
  }

  static PlayerScripts get instance {
    final c = _cached;
    if (c == null) {
      throw StateError(
        'PlayerScripts.load() must be awaited in main() before any '
        'player screen is constructed.',
      );
    }
    return c;
  }

  final String bridge;
  final String isAd;
  final String adGuard;
  final String consoleKiller;
  final String adRemoval;
  final String suppressFullscreen;
  final String iosInlineVideo;
  final String brandHide;
  final String noSelectCss;
  final String userActivity;
  final String _videoProgressTemplate;

  /// Returns the video-progress script with the runtime resume target
  /// substituted into the placeholder.
  ///
  /// `resumeTime` is sanitised before substitution: `NaN`, `Infinity`, and
  /// negative values all collapse to `0`. Dart's `double.toString()` emits
  /// `'NaN'` / `'Infinity'` literally for those values, and both are valid
  /// JS identifiers — without this sanitisation the resulting JS line
  /// `var RESUME_TARGET = NaN;` would parse fine, every
  /// `RESUME_TARGET >= video.duration` check would silently evaluate
  /// false, and auto-resume would break with no error visible on either
  /// side.
  String videoProgress(double resumeTime) {
    final safe = (resumeTime.isFinite && resumeTime >= 0) ? resumeTime : 0.0;
    return _videoProgressTemplate.replaceAll(
      _resumeTargetToken,
      safe.toString(),
    );
  }
}
