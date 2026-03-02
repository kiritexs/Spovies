import 'dart:convert';

import 'package:flutter/foundation.dart';

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
        season: data['season'] as int?,
        episode: data['episode'] as int?,
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

    // For critical events (pause, ended, seeked), always save
    if (event.eventType != 'timeupdate') {
      onProgressUpdate(event);
      return;
    }

    // Throttle timeupdate events to 1 write per 5 seconds
    final now = DateTime.now();
    if (_lastWrite == null ||
        now.difference(_lastWrite!) >= _throttleDuration) {
      _lastWrite = now;
      onProgressUpdate(event);
    }
  }
}
