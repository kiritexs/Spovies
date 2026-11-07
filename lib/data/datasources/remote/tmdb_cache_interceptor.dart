import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../local/hive_service.dart';

/// Dio interceptor that caches GET responses in Hive with configurable TTL.
///
/// - On request: check cache, return cached response if fresh
/// - On response: store response in cache
/// - On a network or server error: return stale cache as a fallback
///   (offline support)
///
/// [prune] runs at startup so the box doesn't grow forever.
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

  /// How long an expired entry is kept as an offline fallback.
  static const Duration staleWindow = Duration(days: 7);

  /// Most entries kept after [prune]. Each is one TMDB response.
  static const int maxEntries = 500;

  Box<Map> get _box => HiveService.tmdbCacheBox;

  /// Drop entries that expired more than [staleWindow] ago (or are
  /// malformed), then keep only the [maxEntries] that expire last.
  static Future<void> prune(Box<Map> box, {DateTime? now}) async {
    final cutoff =
        (now ?? DateTime.now()).millisecondsSinceEpoch -
        staleWindow.inMilliseconds;
    final drop = <dynamic>[];
    final kept = <({dynamic key, int expiresAt})>[];
    for (final key in box.keys) {
      final expiresAt = box.get(key)?['expiresAt'];
      if (expiresAt is! int || expiresAt < cutoff) {
        drop.add(key);
      } else {
        kept.add((key: key, expiresAt: expiresAt));
      }
    }
    if (kept.length > maxEntries) {
      kept.sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
      drop.addAll(kept.skip(maxEntries).map((e) => e.key));
    }
    if (drop.isNotEmpty) await box.deleteAll(drop);
  }

  /// Decode a cached body, or `null` (and evict it) if it is corrupt.
  dynamic _decode(String key, Map cached) {
    final body = cached['body'];
    if (body is String) {
      try {
        return jsonDecode(body);
      } on FormatException {
        // fall through
      }
    }
    unawaited(_box.delete(key));
    return null;
  }

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

      final data = now < expiresAt ? _decode(key, cached) : null;
      if (data != null) {
        // Cache hit — return cached response
        if (kDebugMode) {
          debugPrint('[Cache] HIT: ${options.uri.path}');
        }
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

      unawaited(
        _box.put(key, {
          'body': jsonEncode(response.data),
          'expiresAt': expiresAt,
        }),
      );
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // On a network or server error, try to serve stale cache. A 4xx is a
    // real answer (bad id, bad token), so it is passed through.
    final status = err.response?.statusCode;
    final offlineOrServer = status == null || status >= 500;
    if (err.requestOptions.method == 'GET' &&
        offlineOrServer &&
        err.type != DioExceptionType.cancel) {
      final key = _cacheKey(err.requestOptions);
      final cached = _box.get(key);
      final data = cached == null ? null : _decode(key, cached);

      if (data != null) {
        if (kDebugMode) {
          debugPrint('[Cache] STALE fallback: ${err.requestOptions.uri.path}');
        }
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
