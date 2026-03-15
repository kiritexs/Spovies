/// Represents the user's watch progress for a specific media item.
class UserProgress {
  final String mediaId;
  final String mediaType; // 'movie' or 'tv'
  final String title;
  final String? posterPath;
  final double percentage;
  final double currentTime; // seconds
  final double duration; // seconds
  final int? season;
  final int? episode;
  final DateTime lastPlayedDate;
  /// Plugin ID used when this progress was last saved (for "Continue" to reuse).
  final String? lastPluginId;

  const UserProgress({
    required this.mediaId,
    required this.mediaType,
    required this.title,
    this.posterPath,
    required this.percentage,
    required this.currentTime,
    required this.duration,
    this.season,
    this.episode,
    required this.lastPlayedDate,
    this.lastPluginId,
  });

  /// Remaining time in human-readable format.
  String get remainingTime {
    final remaining = duration - currentTime;
    if (remaining <= 0) return 'Finished';
    final mins = (remaining / 60).ceil();
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = mins % 60;
      return '${h}h ${m}m remaining';
    }
    return '${mins}m remaining';
  }

  /// Convert to Map for Hive storage.
  Map<String, dynamic> toMap() => {
    'mediaId': mediaId,
    'mediaType': mediaType,
    'title': title,
    'posterPath': posterPath,
    'percentage': percentage,
    'currentTime': currentTime,
    'duration': duration,
    'season': season,
    'episode': episode,
    'lastPlayedDate': lastPlayedDate.toIso8601String(),
    'lastPluginId': lastPluginId,
  };

  /// Create from Hive Map.
  ///
  /// All casts are null-safe so that old stored entries (written by a
  /// previous app version with a different schema) never crash the app.
  factory UserProgress.fromMap(Map<dynamic, dynamic> map) {
    return UserProgress(
      mediaId: (map['mediaId'] as String?) ?? '',
      mediaType: (map['mediaType'] as String?) ?? 'movie',
      title: (map['title'] as String?) ?? 'Unknown',
      posterPath: map['posterPath'] as String?,
      percentage: (map['percentage'] as num?)?.toDouble() ?? 0,
      currentTime: (map['currentTime'] as num?)?.toDouble() ?? 0,
      duration: (map['duration'] as num?)?.toDouble() ?? 0,
      season: map['season'] as int?,
      episode: map['episode'] as int?,
      lastPlayedDate: map['lastPlayedDate'] != null
          ? DateTime.tryParse(map['lastPlayedDate'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastPluginId: map['lastPluginId'] as String?,
    );
  }
}
