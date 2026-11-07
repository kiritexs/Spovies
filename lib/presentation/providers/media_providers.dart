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

  // Dio runs onError in the order interceptors were added. Retry goes
  // first so a network or 5xx failure is retried (1s → 2s → 4s) before
  // the cache falls back to stale data; the other way round, any URL with
  // a recently expired entry got stale data on the first timeout and was
  // never retried.
  //
  // 1. Retry interceptor (no onRequest work; retries on error)
  dio.interceptors.add(RetryInterceptor(dio: dio));

  // 2. Cache interceptor (serves fresh entries without a request; serves
  //    stale data once retries are exhausted)
  dio.interceptors.add(TmdbCacheInterceptor());

  // 3. Logging (debug only)
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        // Headers carry the TMDB bearer token; keep it out of logs.
        requestHeader: false,
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

/// Top rated TV shows.
final topRatedTvProvider = FutureProvider<List<MediaItem>>((ref) async {
  final api = ref.watch(tmdbApiProvider);
  return (await api.getTopRatedTv()).map((m) => m.toEntity()).toList();
});

/// Discover movies by genre id.
final discoverMoviesByGenreProvider =
    FutureProvider.family<List<MediaItem>, int>((ref, genreId) async {
      final api = ref.watch(tmdbApiProvider);
      return (await api.discoverMoviesByGenre(
        genreId,
      )).map((m) => m.toEntity()).toList();
    });

/// Discover TV shows by genre id.
final discoverTvByGenreProvider = FutureProvider.family<List<MediaItem>, int>((
  ref,
  genreId,
) async {
  final api = ref.watch(tmdbApiProvider);
  return (await api.discoverTvByGenre(
    genreId,
  )).map((m) => m.toEntity()).toList();
});

/// Combined genre list (movies + TV, deduped) for Discovery genre chips.
final allGenresProvider = FutureProvider<List<({int id, String name})>>((
  ref,
) async {
  final api = ref.watch(tmdbApiProvider);
  final movie = await api.getMovieGenres();
  final tv = await api.getTvGenres();
  final seen = <int>{};
  final merged = <({int id, String name})>[];
  for (final g in [...movie, ...tv]) {
    if (seen.add(g.id)) merged.add((id: g.id, name: g.name));
  }
  return merged;
});
