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
  };

  /// Create from Hive Map.
  factory UserProgress.fromMap(Map<dynamic, dynamic> map) {
    return UserProgress(
      mediaId: map['mediaId'] as String,
      mediaType: map['mediaType'] as String,
      title: map['title'] as String,
      posterPath: map['posterPath'] as String?,
      percentage: (map['percentage'] as num).toDouble(),
      currentTime: (map['currentTime'] as num).toDouble(),
      duration: (map['duration'] as num).toDouble(),
      season: map['season'] as int?,
      episode: map['episode'] as int?,
      lastPlayedDate: DateTime.parse(map['lastPlayedDate'] as String),
    );
  }
}
