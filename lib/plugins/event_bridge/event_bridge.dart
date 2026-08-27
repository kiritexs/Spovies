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

/// Gates the `data['type']` fallback added for Provider B. Without the
/// restriction, a plugin sending an arbitrary `type` could poison
/// `UserProgress.mediaType` and bypass the Continue-Watching filters.
const _kValidMediaTypes = {'movie', 'tv', 'anime'};

String? _validMediaType(dynamic v) {
  if (v is! String) return null;
  return _kValidMediaTypes.contains(v) ? v : null;
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

  /// Parse a plugin's postMessage payload.
  ///
  /// Three shapes are supported — standard `PLAYER_EVENT`, the flat
  /// Provider D format, and the Provider C native format. Field
  /// mappings per provider are in `docs/architecture/PLUGINS.md`.
  static PlayerEvent? tryParse(String rawMessage) {
    try {
      final decoded = jsonDecode(rawMessage);
      final json =
          decoded is List &&
              decoded.isNotEmpty &&
              decoded.first is Map<String, dynamic>
          ? decoded.first as Map<String, dynamic>
          : decoded is Map<String, dynamic>
          ? decoded
          : null;
      if (json == null) return null;

      final eventValue = json['event'];

      // 1) Standard PLAYER_EVENT (Provider A, Provider C, Provider B).
      //    Provider C omits "progress" — compute it from currentTime/duration.
      //    Provider B renames currentTime → timestamp and mediaType → type,
      //    hence the fallbacks below.
      final type = json['type'] as String?;
      if (type == 'PLAYER_EVENT') {
        final data = json['data'] as Map<String, dynamic>?;
        if (data == null) return null;
        final currentTime =
            (data['currentTime'] as num?)?.toDouble() ??
            (data['timestamp'] as num?)?.toDouble() ??
            0;
        final duration = (data['duration'] as num?)?.toDouble() ?? 0;
        var progress = (data['progress'] as num?)?.toDouble();
        if (progress == null || (progress == 0 && duration > 0)) {
          progress = duration > 0 ? (currentTime / duration) * 100 : 0;
        }
        return PlayerEvent(
          eventType: data['event'] as String? ?? 'unknown',
          currentTime: currentTime,
          duration: duration,
          progress: progress,
          mediaId: data['id']?.toString() ?? '',
          mediaType:
              data['mediaType'] as String? ??
              _validMediaType(data['type']) ??
              'movie',
          season: _toIntOrNull(data['season']),
          episode: _toIntOrNull(data['episode']),
        );
      }

      // 2) Provider D format: {"channel":"example-channel","event":"time","time":...,"duration":...,"percent":...}
      final channel = json['channel'];
      if (channel != null && eventValue != null) {
        final event = eventValue;
        final currentTime = (json['time'] as num?)?.toDouble();
        final duration = (json['duration'] as num?)?.toDouble();
        final percent =
            (json['percent'] as num?)?.toDouble() ??
            (json['progress'] as num?)?.toDouble();
        if (currentTime != null &&
            duration != null &&
            duration > 0 &&
            percent != null) {
          return PlayerEvent(
            eventType: event == 'time' ? 'timeupdate' : event.toString(),
            currentTime: currentTime,
            duration: duration,
            progress: percent,
            mediaId: '',
            mediaType: '',
            season: null,
            episode: null,
          );
        }
      }

      // 3) Provider C native: no "type" or "channel"; time in "time" or "data".
      final durationVal = (json['duration'] as num?)?.toDouble();
      final timeVal =
          (json['time'] as num?)?.toDouble() ??
          (json['data'] as num?)?.toDouble();
      if (eventValue != null &&
          durationVal != null &&
          durationVal > 0 &&
          timeVal != null) {
        final eventStr = eventValue.toString();
        if (eventStr == 'time' ||
            eventStr == 'pause' ||
            eventStr == 'userpause' ||
            eventStr == 'paused') {
          final progressPct = (timeVal / durationVal) * 100;
          return PlayerEvent(
            eventType: eventStr == 'time' ? 'timeupdate' : 'pause',
            currentTime: timeVal,
            duration: durationVal,
            progress: progressPct,
            mediaId: '',
            mediaType: '',
            season: null,
            episode: null,
          );
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        // Only log if it's not a known non-JSON message from external scripts
        if (!rawMessage.startsWith('__ym') &&
            !rawMessage.startsWith('adscore')) {
          debugPrint('EventBridge: Failed to parse postMessage: $e');
        }
      }
      return null;
    }
  }
}

/// Manages postMessage event parsing and throttled progress updates.
class EventBridge {
  final void Function(PlayerEvent event) onProgressUpdate;

  DateTime? _lastWrite;
  static const _throttleDuration = Duration(seconds: 5);

  EventBridge({required this.onProgressUpdate});

  /// Handle a raw postMessage string from the WebView.
  void handleMessage(String rawMessage) {
    final event = PlayerEvent.tryParse(rawMessage);
    if (event == null) return;

    // Only 'ended' and 'pause' skip the throttle. 'seeked' fires dozens of
    // times per second while scrubbing and 'play' repeats the preceding
    // timeupdate — see PLUGINS.md § Throttling.
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
