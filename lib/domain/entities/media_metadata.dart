import 'cast_member.dart';

/// Nested metadata for a media item — ratings, genres, runtime, etc.
class MediaMetadata {
  final String? imdbId;
  final int? runtime;
  final List<String> genres;
  final List<int> genreIds;
  final double? rating;
  final int? voteCount;
  final String? trailerKey;
  final String? certification;
  final List<CastMember> cast;

  const MediaMetadata({
    this.imdbId,
    this.runtime,
    this.genres = const [],
    this.genreIds = const [],
    this.rating,
    this.voteCount,
    this.trailerKey,
    this.certification,
    this.cast = const [],
  });

  MediaMetadata copyWith({
    String? imdbId,
    int? runtime,
    List<String>? genres,
    List<int>? genreIds,
    double? rating,
    int? voteCount,
    String? trailerKey,
    String? certification,
    List<CastMember>? cast,
  }) {
    return MediaMetadata(
      imdbId: imdbId ?? this.imdbId,
      runtime: runtime ?? this.runtime,
      genres: genres ?? this.genres,
      genreIds: genreIds ?? this.genreIds,
      rating: rating ?? this.rating,
      voteCount: voteCount ?? this.voteCount,
      trailerKey: trailerKey ?? this.trailerKey,
      certification: certification ?? this.certification,
      cast: cast ?? this.cast,
    );
  }

  /// Format runtime as "Xh Ym".
  String get formattedRuntime {
    if (runtime == null || runtime == 0) return '';
    final hours = runtime! ~/ 60;
    final minutes = runtime! % 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }
}
