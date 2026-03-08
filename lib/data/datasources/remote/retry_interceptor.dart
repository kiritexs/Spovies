import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Dio interceptor that retries failed requests with exponential backoff.
///
/// Retries on:
/// - Socket/timeout errors (no connectivity, DNS failure)
/// - Server errors (HTTP 500–599)
///
/// Does NOT retry on:
/// - Client errors (4xx) — these are definitive
/// - Cancellations
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Duration initialDelay;

  RetryInterceptor({
    required this.dio,
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
  });

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_shouldRetry(err)) {
      return handler.next(err);
    }

    final retryCount = err.requestOptions.extra['retryCount'] as int? ?? 0;
    if (retryCount >= maxRetries) {
      return handler.next(err);
    }

    final delay = initialDelay * (1 << retryCount); // 1s, 2s, 4s
    if (kDebugMode) {
      debugPrint(
        '[Retry] Attempt ${retryCount + 1}/$maxRetries '
        'for ${err.requestOptions.uri} after ${delay.inMilliseconds}ms',
      );
    }

    await Future<void>.delayed(delay);

    try {
      err.requestOptions.extra['retryCount'] = retryCount + 1;
      final response = await dio.fetch(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  bool _shouldRetry(DioException err) {
    // Don't retry cancellations
    if (err.type == DioExceptionType.cancel) return false;

    // Retry on connection/timeout errors
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }

    // Retry on socket exceptions (no network)
    if (err.error is SocketException) return true;

    // Retry on server errors (5xx)
    final statusCode = err.response?.statusCode;
    if (statusCode != null && statusCode >= 500) return true;

    return false;
  }
}
