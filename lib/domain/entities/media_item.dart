import 'media_metadata.dart';
import 'media_type.dart';

/// Core domain entity representing a movie or TV show.
class MediaItem {
  final String id;
  final int tmdbId;
  final MediaType type;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final MediaMetadata metadata;

  const MediaItem({
    required this.id,
    required this.tmdbId,
    required this.type,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.metadata = const MediaMetadata(),
  });

  MediaItem copyWith({
    String? id,
    int? tmdbId,
    MediaType? type,
    String? title,
    String? overview,
    String? posterPath,
    String? backdropPath,
    String? releaseDate,
    MediaMetadata? metadata,
  }) {
    return MediaItem(
      id: id ?? this.id,
      tmdbId: tmdbId ?? this.tmdbId,
      type: type ?? this.type,
      title: title ?? this.title,
      overview: overview ?? this.overview,
      posterPath: posterPath ?? this.posterPath,
      backdropPath: backdropPath ?? this.backdropPath,
      releaseDate: releaseDate ?? this.releaseDate,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Year extracted from releaseDate.
  String? get year {
    if (releaseDate == null || releaseDate!.length < 4) return null;
    return releaseDate!.substring(0, 4);
  }
}
