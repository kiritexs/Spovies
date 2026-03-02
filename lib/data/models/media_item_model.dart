import '../../domain/entities/cast_member.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_metadata.dart';
import '../../domain/entities/media_type.dart';

/// Data model for TMDB API responses → [MediaItem] entity conversion.
class MediaItemModel {
  final MediaItem entity;

  MediaItemModel._(this.entity);

  /// Parse a movie/TV item from TMDB list endpoints (trending, top_rated, search).
  factory MediaItemModel.fromTmdbJson(Map<String, dynamic> json) {
    final mediaType = MediaType.fromString(json['media_type'] as String?);
    final title = (json['title'] ?? json['name'] ?? '') as String;
    final releaseDate =
        (json['release_date'] ?? json['first_air_date']) as String?;
    final genreIds =
        (json['genre_ids'] as List<dynamic>?)?.map((e) => e as int).toList() ??
        [];

    return MediaItemModel._(
      MediaItem(
        id: json['id'].toString(),
        tmdbId: json['id'] as int,
        type: mediaType,
        title: title,
        overview: json['overview'] as String?,
        posterPath: json['poster_path'] as String?,
        backdropPath: json['backdrop_path'] as String?,
        releaseDate: releaseDate,
        metadata: MediaMetadata(
          rating: (json['vote_average'] as num?)?.toDouble(),
          voteCount: json['vote_count'] as int?,
          genreIds: genreIds,
        ),
      ),
    );
  }

  /// Parse from TMDB movie detail endpoint (includes appended data).
  factory MediaItemModel.fromTmdbDetailJson(Map<String, dynamic> json) {
    final genres =
        (json['genres'] as List<dynamic>?)
            ?.map((g) => g['name'] as String)
            .toList() ??
        [];

    // Extract trailer key (YouTube, type=Trailer)
    String? trailerKey;
    final videos = json['videos']?['results'] as List<dynamic>?;
    if (videos != null && videos.isNotEmpty) {
      final trailer = videos.firstWhere(
        (v) => v['type'] == 'Trailer' && v['site'] == 'YouTube',
        orElse: () => videos.first,
      );
      trailerKey = trailer['key'] as String?;
    }

    // Extract certification (US)
    String? certification;
    final releaseDates = json['release_dates']?['results'] as List<dynamic>?;
    if (releaseDates != null) {
      final us = releaseDates.firstWhere(
        (r) => r['iso_3166_1'] == 'US',
        orElse: () => <String, dynamic>{},
      );
      final usReleases = us['release_dates'] as List<dynamic>?;
      if (usReleases != null && usReleases.isNotEmpty) {
        certification = usReleases.first['certification'] as String?;
        if (certification != null && certification.isEmpty) {
          certification = null;
        }
      }
    }

    // Extract cast (top 20)
    final castList = <CastMember>[];
    final credits = json['credits']?['cast'] as List<dynamic>?;
    if (credits != null) {
      for (final c in credits.take(20)) {
        castList.add(
          CastMember(
            id: c['id'] as int,
            name: c['name'] as String? ?? '',
            character: c['character'] as String?,
            profilePath: c['profile_path'] as String?,
          ),
        );
      }
    }

    final type = json['name'] != null ? MediaType.tv : MediaType.movie;

    return MediaItemModel._(
      MediaItem(
        id: json['id'].toString(),
        tmdbId: json['id'] as int,
        type: type,
        title: (json['title'] ?? json['name'] ?? '') as String,
        overview: json['overview'] as String?,
        posterPath: json['poster_path'] as String?,
        backdropPath: json['backdrop_path'] as String?,
        releaseDate:
            (json['release_date'] ?? json['first_air_date']) as String?,
        metadata: MediaMetadata(
          imdbId: json['imdb_id'] as String?,
          runtime: json['runtime'] as int?,
          genres: genres,
          genreIds:
              (json['genres'] as List<dynamic>?)
                  ?.map((g) => g['id'] as int)
                  .toList() ??
              [],
          rating: (json['vote_average'] as num?)?.toDouble(),
          voteCount: json['vote_count'] as int?,
          trailerKey: trailerKey,
          certification: certification,
          cast: castList,
        ),
      ),
    );
  }

  /// Convert model → entity.
  MediaItem toEntity() => entity;
}
