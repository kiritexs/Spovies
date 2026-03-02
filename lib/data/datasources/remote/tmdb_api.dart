import 'package:dio/dio.dart';

import '../../models/media_item_model.dart';
import '../../models/genre_model.dart';

/// TMDB REST API client — handles all HTTP calls to themoviedb.org.
class TmdbApi {
  final Dio _dio;

  TmdbApi(this._dio);

  // ─── Trending ─────────────────────────────────────────────────────────

  /// Weekly trending movies (used for Hero + Trending row).
  Future<List<MediaItemModel>> getTrendingMovies({
    String window = 'week',
  }) async {
    final response = await _dio.get('/trending/movie/$window');
    final results = response.data['results'] as List;
    return results.map((json) => MediaItemModel.fromTmdbJson(json)).toList();
  }

  /// Weekly trending TV shows.
  Future<List<MediaItemModel>> getTrendingTv({String window = 'week'}) async {
    final response = await _dio.get('/trending/tv/$window');
    final results = response.data['results'] as List;
    return results.map((json) => MediaItemModel.fromTmdbJson(json)).toList();
  }

  // ─── Curated Lists ────────────────────────────────────────────────────

  /// Top rated movies.
  Future<List<MediaItemModel>> getTopRatedMovies({int page = 1}) async {
    final response = await _dio.get(
      '/movie/top_rated',
      queryParameters: {'page': page},
    );
    final results = response.data['results'] as List;
    return results.map((json) => MediaItemModel.fromTmdbJson(json)).toList();
  }

  /// Popular movies.
  Future<List<MediaItemModel>> getPopularMovies({int page = 1}) async {
    final response = await _dio.get(
      '/movie/popular',
      queryParameters: {'page': page},
    );
    final results = response.data['results'] as List;
    return results.map((json) => MediaItemModel.fromTmdbJson(json)).toList();
  }

  // ─── Details ──────────────────────────────────────────────────────────

  /// Movie details with appended credits, videos, images, release_dates.
  Future<MediaItemModel> getMovieDetails(int id) async {
    final response = await _dio.get(
      '/movie/$id',
      queryParameters: {
        'append_to_response': 'credits,videos,images,release_dates',
      },
    );
    return MediaItemModel.fromTmdbDetailJson(response.data);
  }

  // ─── Search ───────────────────────────────────────────────────────────

  /// Multi-search (movie + TV + person — filter in UI).
  Future<List<MediaItemModel>> search(String query, {int page = 1}) async {
    final response = await _dio.get(
      '/search/multi',
      queryParameters: {'query': query, 'page': page},
    );
    final results = response.data['results'] as List;
    return results
        .where((json) => (json['media_type'] as String?) != 'person')
        .map((json) => MediaItemModel.fromTmdbJson(json))
        .toList();
  }

  // ─── Config & Genres ──────────────────────────────────────────────────

  /// Movie genre list: id → name mapping.
  Future<List<GenreModel>> getMovieGenres() async {
    final response = await _dio.get('/genre/movie/list');
    final genres = response.data['genres'] as List;
    return genres.map((json) => GenreModel.fromJson(json)).toList();
  }

  /// TV genre list.
  Future<List<GenreModel>> getTvGenres() async {
    final response = await _dio.get('/genre/tv/list');
    final genres = response.data['genres'] as List;
    return genres.map((json) => GenreModel.fromJson(json)).toList();
  }
}
