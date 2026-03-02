import '../../domain/entities/media_item.dart';
import '../../domain/repositories/media_repository.dart';
import '../datasources/remote/tmdb_api.dart';

/// Concrete implementation of [MediaRepository] using TMDB API.
class MediaRepositoryImpl implements MediaRepository {
  final TmdbApi _api;

  MediaRepositoryImpl(this._api);

  @override
  Future<List<MediaItem>> getTrendingMovies() async {
    final models = await _api.getTrendingMovies();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<MediaItem>> getTopRatedMovies({int page = 1}) async {
    final models = await _api.getTopRatedMovies(page: page);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<Map<int, String>> getGenreMap() async {
    final movieGenres = await _api.getMovieGenres();
    final tvGenres = await _api.getTvGenres();
    final map = <int, String>{};
    for (final g in movieGenres) {
      map[g.id] = g.name;
    }
    for (final g in tvGenres) {
      map.putIfAbsent(g.id, () => g.name);
    }
    return map;
  }

  @override
  Future<MediaItem> getMovieDetails(int id) async {
    final model = await _api.getMovieDetails(id);
    return model.toEntity();
  }

  @override
  Future<List<MediaItem>> search(String query) async {
    final models = await _api.search(query);
    return models.map((m) => m.toEntity()).toList();
  }
}
