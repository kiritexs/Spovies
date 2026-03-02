import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/env.dart';
import '../../data/datasources/remote/tmdb_api.dart';
import '../../data/repositories/media_repository_impl.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/repositories/media_repository.dart';

// ─── Infrastructure Providers ───────────────────────────────────────────

/// Configured Dio instance with TMDB auth.
final dioProvider = Provider<Dio>((ref) {
  final token = Env.tmdbApiKey; // This is actually your Read Access Token

  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.tmdbBaseUrl,
      headers: {'Authorization': 'Bearer $token', 'accept': 'application/json'},
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
    ),
  );

  dio.interceptors.add(
    LogInterceptor(
      requestHeader: true,
      responseHeader: true,
      requestBody: false,
      error: true,
    ),
  );

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
