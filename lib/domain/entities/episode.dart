/// A single TV show episode.
class Episode {
  final int seasonNumber;
  final int episodeNumber;
  final String name;
  final String? overview;
  final String? stillPath;
  final int? runtime;
  final String? airDate;

  const Episode({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.name,
    this.overview,
    this.stillPath,
    this.runtime,
    this.airDate,
  });

  /// Format runtime as "Xm" or "Xh Ym".
  String get formattedRuntime {
    if (runtime == null || runtime == 0) return '';
    final hours = runtime! ~/ 60;
    final minutes = runtime! % 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  String get label => 'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';
}

/// A TV season summary (for the season selector).
class TvSeason {
  final int seasonNumber;
  final String? name;
  final int episodeCount;
  final String? posterPath;

  const TvSeason({
    required this.seasonNumber,
    required this.episodeCount,
    this.name,
    this.posterPath,
  });
}
