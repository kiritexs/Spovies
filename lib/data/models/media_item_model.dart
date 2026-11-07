import '../../domain/entities/cast_member.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_metadata.dart';
import '../../domain/entities/media_type.dart';

typedef _Json = Map<String, dynamic>;

/// [v] as a JSON object, or null if it isn't one.
_Json? _obj(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

/// [v] as a list of JSON objects (non-objects skipped), or empty.
List<_Json> _objs(Object? v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];

/// A YouTube video key: the trailer if there is one, else any YouTube
/// video, else null. Keys are opened as `youtube.com/watch?v=<key>`, so a
/// video hosted elsewhere (e.g. Vimeo) must never be picked.
String? _trailerKey(_Json json) {
  final youtube = _objs(
    _obj(json['videos'])?['results'],
  ).where((v) => v['site'] == 'YouTube').toList();
  if (youtube.isEmpty) return null;
  final trailer = youtube.firstWhere(
    (v) => v['type'] == 'Trailer',
    orElse: () => youtube.first,
  );
  return trailer['key'] as String?;
}

List<String> _genreNames(_Json json) => [
  for (final g in _objs(json['genres'])) g['name'] as String,
];

List<int> _genreIds(_Json json) => [
  for (final g in _objs(json['genres'])) g['id'] as int,
];

/// Data model for TMDB API responses → [MediaItem] entity conversion.
class MediaItemModel {
  final MediaItem entity;

  MediaItemModel._(this.entity);

  /// Parse a movie/TV item from TMDB list endpoints (trending, top_rated, search).
  ///
  /// [defaultType] is used when the JSON doesn't include a `media_type` field
  /// (e.g. `/tv/popular`, `/movie/top_rated`). Trending endpoints include it.
  factory MediaItemModel.fromTmdbJson(
    Map<String, dynamic> json, {
    MediaType? defaultType,
  }) {
    final mediaType = json['media_type'] != null
        ? MediaType.fromString(json['media_type'] as String?)
        : (defaultType ?? MediaType.movie);
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
    // Certification: the first US release's, empty treated as none.
    String? certification;
    final us = _objs(
      _obj(json['release_dates'])?['results'],
    ).where((r) => r['iso_3166_1'] == 'US').firstOrNull;
    final usReleases = _objs(us?['release_dates']);
    if (usReleases.isNotEmpty) {
      certification = usReleases.first['certification'] as String?;
      if (certification != null && certification.isEmpty) {
        certification = null;
      }
    }

    // Cast (top 20)
    final castList = [
      for (final c in _objs(_obj(json['credits'])?['cast']).take(20))
        CastMember(
          id: c['id'] as int,
          name: c['name'] as String? ?? '',
          character: c['character'] as String?,
          profilePath: c['profile_path'] as String?,
        ),
    ];

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
          genres: _genreNames(json),
          genreIds: _genreIds(json),
          rating: (json['vote_average'] as num?)?.toDouble(),
          voteCount: json['vote_count'] as int?,
          trailerKey: _trailerKey(json),
          certification: certification,
          cast: castList,
        ),
      ),
    );
  }

  /// Parse from TMDB TV detail endpoint.
  factory MediaItemModel.fromTmdbTvDetailJson(Map<String, dynamic> json) {
    // Seasons (skip specials, season 0)
    final seasonsList = <TvSeason>[];
    for (final s in _objs(json['seasons'])) {
      final number = s['season_number'] as int? ?? 0;
      if (number == 0) continue;
      seasonsList.add(
        TvSeason(
          seasonNumber: number,
          episodeCount: s['episode_count'] as int? ?? 0,
          name: s['name'] as String?,
          posterPath: s['poster_path'] as String?,
        ),
      );
    }

    // Cast from aggregate_credits (TV), falling back to credits. In
    // aggregate credits the character is on the first role.
    final aggregate = _obj(json['aggregate_credits'])?['cast'];
    final castSource = _objs(aggregate ?? _obj(json['credits'])?['cast']);
    final castList = [
      for (final c in castSource.take(20))
        CastMember(
          id: c['id'] as int,
          name: c['name'] as String? ?? '',
          character: _objs(c['roles']).isNotEmpty
              ? _objs(c['roles']).first['character'] as String?
              : c['character'] as String?,
          profilePath: c['profile_path'] as String?,
        ),
    ];

    return MediaItemModel._(
      MediaItem(
        id: json['id'].toString(),
        tmdbId: json['id'] as int,
        type: MediaType.tv,
        title: (json['name'] ?? json['title'] ?? '') as String,
        overview: json['overview'] as String?,
        posterPath: json['poster_path'] as String?,
        backdropPath: json['backdrop_path'] as String?,
        releaseDate: json['first_air_date'] as String?,
        metadata: MediaMetadata(
          imdbId: _obj(json['external_ids'])?['imdb_id'] as String?,
          genres: _genreNames(json),
          genreIds: _genreIds(json),
          rating: (json['vote_average'] as num?)?.toDouble(),
          voteCount: json['vote_count'] as int?,
          trailerKey: _trailerKey(json),
          cast: castList,
          seasons: seasonsList,
          numberOfSeasons: json['number_of_seasons'] as int?,
        ),
      ),
    );
  }

  /// Convert model → entity.
  MediaItem toEntity() => entity;
}
