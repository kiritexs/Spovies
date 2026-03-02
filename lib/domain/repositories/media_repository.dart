import '../../domain/entities/media_item.dart';

/// Abstract repository interface for media data.
abstract class MediaRepository {
  /// Trending movies for the week.
  Future<List<MediaItem>> getTrendingMovies();

  /// Top rated movies.
  Future<List<MediaItem>> getTopRatedMovies({int page = 1});

  /// Genre id → name mapping.
  Future<Map<int, String>> getGenreMap();

  /// Movie details with appended data (credits, videos, etc.).
  Future<MediaItem> getMovieDetails(int id);

  /// TV show details with seasons + cast.
  Future<MediaItem> getTvDetails(int id);

  /// Multi-search across movies + TV.
  Future<List<MediaItem>> search(String query);
}
