import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/env.dart';
import '../../data/datasources/remote/retry_interceptor.dart';
import '../../data/datasources/remote/tmdb_api.dart';
import '../../data/datasources/remote/tmdb_cache_interceptor.dart';
import '../../data/repositories/media_repository_impl.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/repositories/media_repository.dart';

// ─── Infrastructure Providers ───────────────────────────────────────────

/// Configured Dio instance with TMDB auth, caching, and retry.
final dioProvider = Provider<Dio>((ref) {
  final token = Env.tmdbApiKey;

  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.tmdbBaseUrl,
      headers: {'Authorization': 'Bearer $token', 'accept': 'application/json'},
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
    ),
  );

  // 1. Cache interceptor (checks Hive before network, serves stale on error)
  dio.interceptors.add(TmdbCacheInterceptor());

  // 2. Retry interceptor (exponential backoff: 1s → 2s → 4s)
  dio.interceptors.add(RetryInterceptor(dio: dio));

  // 3. Logging (debug only)
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestHeader: true,
        responseHeader: true,
        requestBody: false,
        error: true,
      ),
    );
  }

  return dio;
});

/// TMDB API client.
final tmdbApiProvider = Provider<TmdbApi>((ref) {
  return TmdbApi(ref.watch(dioProvider));
});

/// Media repository.
final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepositoryImpl(ref.watch(tmdbApiProvider));
});

// ─── Data Providers ─────────────────────────────────────────────────────

/// Trending movies for the week (Hero + Trending row).
final trendingMoviesProvider = FutureProvider<List<MediaItem>>((ref) async {
  final repo = ref.watch(mediaRepositoryProvider);
  return repo.getTrendingMovies();
});

/// Top rated movies (Top Rated row).
final topRatedMoviesProvider = FutureProvider<List<MediaItem>>((ref) async {
  final repo = ref.watch(mediaRepositoryProvider);
  return repo.getTopRatedMovies();
});

/// Genre id → name map.
final genreMapProvider = FutureProvider<Map<int, String>>((ref) async {
  final repo = ref.watch(mediaRepositoryProvider);
  return repo.getGenreMap();
});

/// Trending TV shows for the week.
final trendingTvProvider = FutureProvider<List<MediaItem>>((ref) async {
  final api = ref.watch(tmdbApiProvider);
  return (await api.getTrendingTv()).map((m) => m.toEntity()).toList();
});

/// Popular TV shows.
final popularTvProvider = FutureProvider<List<MediaItem>>((ref) async {
  final api = ref.watch(tmdbApiProvider);
  return (await api.getPopularTv()).map((m) => m.toEntity()).toList();
});

/// Popular movies.
final popularMoviesProvider = FutureProvider<List<MediaItem>>((ref) async {
  final api = ref.watch(tmdbApiProvider);
  return (await api.getPopularMovies()).map((m) => m.toEntity()).toList();
});

/// Discover movies by genre id.
final discoverMoviesByGenreProvider =
    FutureProvider.family<List<MediaItem>, int>((ref, genreId) async {
      final api = ref.watch(tmdbApiProvider);
      return (await api.discoverMoviesByGenre(genreId))
          .map((m) => m.toEntity())
          .toList();
    });

/// Discover TV shows by genre id.
final discoverTvByGenreProvider =
    FutureProvider.family<List<MediaItem>, int>((ref, genreId) async {
      final api = ref.watch(tmdbApiProvider);
      return (await api.discoverTvByGenre(genreId))
          .map((m) => m.toEntity())
          .toList();
    });

/// Combined genre list (movies + TV, deduped) for Discovery genre chips.
final allGenresProvider = FutureProvider<List<({int id, String name})>>(
  (ref) async {
    final api = ref.watch(tmdbApiProvider);
    final movie = await api.getMovieGenres();
    final tv = await api.getTvGenres();
    final seen = <int>{};
    final merged = <({int id, String name})>[];
    for (final g in [...movie, ...tv]) {
      if (seen.add(g.id)) merged.add((id: g.id, name: g.name));
    }
    return merged;
  },
);
