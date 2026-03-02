/// Type of media content.
enum MediaType {
  movie,
  tv;

  /// Parse from TMDB `media_type` string value.
  static MediaType fromString(String? value) => switch (value) {
    'movie' => MediaType.movie,
    'tv' => MediaType.tv,
    _ => MediaType.movie,
  };

  String get displayName => switch (this) {
    MediaType.movie => 'Movie',
    MediaType.tv => 'TV Show',
  };
}
