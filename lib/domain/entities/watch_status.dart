import 'package:flutter/material.dart';

/// User's list status for a media item (or per episode for TV).
enum WatchStatus {
  watching,
  completed,
  dropped,
  onHold,
  planToWatch;

  String get value => switch (this) {
    WatchStatus.watching => 'watching',
    WatchStatus.completed => 'completed',
    WatchStatus.dropped => 'dropped',
    WatchStatus.onHold => 'on_hold',
    WatchStatus.planToWatch => 'plan_to_watch',
  };

  static WatchStatus fromString(String? value) => switch (value) {
    'watching' => WatchStatus.watching,
    'completed' => WatchStatus.completed,
    'dropped' => WatchStatus.dropped,
    'on_hold' => WatchStatus.onHold,
    'plan_to_watch' => WatchStatus.planToWatch,
    _ => WatchStatus.planToWatch,
  };

  String get displayName => switch (this) {
    WatchStatus.watching => 'Watching',
    WatchStatus.completed => 'Completed',
    WatchStatus.dropped => 'Dropped',
    WatchStatus.onHold => 'On Hold',
    WatchStatus.planToWatch => 'Plan to Watch',
  };

  IconData get icon => switch (this) {
    WatchStatus.watching => Icons.visibility_rounded,
    WatchStatus.completed => Icons.check_circle_rounded,
    WatchStatus.dropped => Icons.delete_sweep_rounded,
    WatchStatus.onHold => Icons.pause_circle_rounded,
    WatchStatus.planToWatch => Icons.bookmark_add_rounded,
  };
}

/// A single status entry: media-level (movie or show) or episode-level (TV).
class MediaStatus {
  final String mediaId;
  final String mediaType;
  final WatchStatus status;
  final int? season;
  final int? episode;
  final DateTime updatedAt;

  const MediaStatus({
    required this.mediaId,
    required this.mediaType,
    required this.status,
    this.season,
    this.episode,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'mediaId': mediaId,
    'mediaType': mediaType,
    'status': status.value,
    'season': season,
    'episode': episode,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory MediaStatus.fromMap(Map<dynamic, dynamic> map) {
    return MediaStatus(
      mediaId: (map['mediaId']?.toString()) ?? '',
      mediaType: (map['mediaType'] as String?) ?? 'movie',
      status: WatchStatus.fromString(map['status'] as String?),
      season: _toIntOrNull(map['season']),
      episode: _toIntOrNull(map['episode']),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

int? _toIntOrNull(dynamic v) {
  if (v == null || v is bool) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}
