import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Safely casts a JSON value to int?.
/// Returns null if the value is not a number (e.g. `false` sent by plugins
/// for movie season/episode fields).
int? _toIntOrNull(dynamic v) {
  if (v == null || v is bool) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}

/// Parsed event from a plugin's WebView postMessage.
class PlayerEvent {
  final String eventType; // timeupdate, play, pause, ended, seeked
  final double currentTime;
  final double duration;
  final double progress; // percentage
  final String mediaId;
  final String mediaType;
  final int? season;
  final int? episode;

  const PlayerEvent({
    required this.eventType,
    required this.currentTime,
    required this.duration,
    required this.progress,
    required this.mediaId,
    required this.mediaType,
    this.season,
    this.episode,
  });

  /// Parse from the plugin's postMessage JSON payload.
  ///
  /// Expected format (from Provider A docs):
  /// ```json
  /// {
  ///   "type": "PLAYER_EVENT",
  ///   "data": {
  ///     "event": "timeupdate",
  ///     "currentTime": 120.5,
  ///     "duration": 7200,
  ///     "progress": 1.6,
  ///     "id": "299534",
  ///     "mediaType": "movie",
  ///     "season": 1,
  ///     "episode": 8
  ///   }
  /// }
  /// ```
  static PlayerEvent? tryParse(String rawMessage) {
    try {
      final json = jsonDecode(rawMessage) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type != 'PLAYER_EVENT') return null;

      final data = json['data'] as Map<String, dynamic>;

      return PlayerEvent(
        eventType: data['event'] as String? ?? 'unknown',
        currentTime: (data['currentTime'] as num?)?.toDouble() ?? 0,
        duration: (data['duration'] as num?)?.toDouble() ?? 0,
        progress: (data['progress'] as num?)?.toDouble() ?? 0,
        mediaId: data['id']?.toString() ?? '',
        mediaType: data['mediaType'] as String? ?? 'movie',
        season: _toIntOrNull(data['season']),
        episode: _toIntOrNull(data['episode']),
      );
    } catch (e) {
      debugPrint('EventBridge: Failed to parse postMessage: $e');
      return null;
    }
  }
}

/// Manages postMessage event parsing and throttled progress updates.
class EventBridge {
  final String? allowedOrigin;
  final List<String> allowedEventTypes;
  final void Function(PlayerEvent event) onProgressUpdate;

  DateTime? _lastWrite;
  static const _throttleDuration = Duration(seconds: 5);

  EventBridge({
    this.allowedOrigin,
    this.allowedEventTypes = const ['PLAYER_EVENT'],
    required this.onProgressUpdate,
  });

  /// Handle a raw postMessage string from the WebView.
  void handleMessage(String rawMessage) {
    final event = PlayerEvent.tryParse(rawMessage);
    if (event == null) return;

    // Only 'ended' and 'pause' skip the throttle — they are the only events
    // where an immediate save is critical (user stopped or finished watching).
    //
    // 'seeked' is intentionally throttled: scrubbing fires it dozens of times
    // per second, and writing on every one causes unnecessary Hive I/O with
    // no UX benefit (the final resting currentTime is already captured by the
    // next throttled timeupdate or by a subsequent pause/ended).
    //
    // 'play' is also throttled — it carries the same time value as the
    // preceding timeupdate and adds nothing.
    if (event.eventType == 'ended' || event.eventType == 'pause') {
      onProgressUpdate(event);
      return;
    }

    // Throttle everything else (timeupdate, seeked, play) to 1 write per 5 s.
    final now = DateTime.now();
    if (_lastWrite == null ||
        now.difference(_lastWrite!) >= _throttleDuration) {
      _lastWrite = now;
      onProgressUpdate(event);
    }
  }
}
