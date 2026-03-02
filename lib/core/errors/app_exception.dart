/// Base exception hierarchy for Spovies.
///
/// Every exception carries a user-friendly [message] suitable for display.
sealed class AppException implements Exception {
  final String message;
  final Object? cause;

  const AppException(this.message, {this.cause});

  @override
  String toString() => '$runtimeType: $message';
}

/// Network-related failures (timeout, no connectivity, server error).
class NetworkException extends AppException {
  final int? statusCode;

  const NetworkException(super.message, {this.statusCode, super.cause});

  bool get isTimeout => statusCode == null && message.contains('timeout');
  bool get isServerError => statusCode != null && statusCode! >= 500;
}

/// Local cache read/write failures.
class CacheException extends AppException {
  const CacheException(super.message, {super.cause});
}

/// Data parsing or validation failures.
class ParseException extends AppException {
  const ParseException(super.message, {super.cause});
}
