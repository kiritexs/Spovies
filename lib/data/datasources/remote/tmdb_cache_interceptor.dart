import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../local/hive_service.dart';

/// Dio interceptor that caches GET responses in Hive with configurable TTL.
///
/// - On request: check cache, return cached response if fresh
/// - On response: store response in cache
/// - On error: return stale cache as fallback (offline support)
class TmdbCacheInterceptor extends Interceptor {
  /// TTL rules by URL path pattern (first match wins).
  static final List<_CacheRule> _rules = [
    _CacheRule('/genre/', const Duration(hours: 24)),
    _CacheRule('/configuration', const Duration(hours: 24)),
    _CacheRule('/trending/', const Duration(minutes: 30)),
    _CacheRule('/movie/top_rated', const Duration(hours: 1)),
    _CacheRule('/movie/popular', const Duration(hours: 1)),
    _CacheRule('/search/', const Duration(minutes: 10)),
    // Details: 1 hour default
  ];

  static const Duration _defaultTtl = Duration(hours: 1);

  Box<Map> get _box => HiveService.tmdbCacheBox;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Only cache GET requests
    if (options.method != 'GET') {
      return handler.next(options);
    }

    final key = _cacheKey(options);
    final cached = _box.get(key);

    if (cached != null) {
      final expiresAt = cached['expiresAt'] as int? ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (now < expiresAt) {
        // Cache hit — return cached response
        if (kDebugMode) {
          print('[Cache] HIT: ${options.uri.path}');
        }
        final data = jsonDecode(cached['body'] as String);
        handler.resolve(
          Response(
            requestOptions: options,
            data: data,
            statusCode: 200,
            statusMessage: 'OK (cached)',
          ),
        );
        return;
      }
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.method == 'GET' && response.statusCode == 200) {
      final key = _cacheKey(response.requestOptions);
      final ttl = _ttlFor(response.requestOptions.uri.path);
      final expiresAt =
          DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds;

      _box.put(key, {
        'body': jsonEncode(response.data),
        'expiresAt': expiresAt,
      });
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // On network error, try to serve stale cache
    if (err.requestOptions.method == 'GET') {
      final key = _cacheKey(err.requestOptions);
      final cached = _box.get(key);

      if (cached != null) {
        if (kDebugMode) {
          print('[Cache] STALE fallback: ${err.requestOptions.uri.path}');
        }
        final data = jsonDecode(cached['body'] as String);
        handler.resolve(
          Response(
            requestOptions: err.requestOptions,
            data: data,
            statusCode: 200,
            statusMessage: 'OK (stale cache)',
          ),
        );
        return;
      }
    }

    handler.next(err);
  }

  /// Generate a unique cache key from the request URL + query parameters.
  String _cacheKey(RequestOptions options) {
    final uri = options.uri;
    return '${uri.path}?${uri.query}';
  }

  /// Find the TTL for a given path.
  Duration _ttlFor(String path) {
    for (final rule in _rules) {
      if (path.contains(rule.pattern)) return rule.ttl;
    }
    return _defaultTtl;
  }
}

class _CacheRule {
  final String pattern;
  final Duration ttl;
  const _CacheRule(this.pattern, this.ttl);
}
