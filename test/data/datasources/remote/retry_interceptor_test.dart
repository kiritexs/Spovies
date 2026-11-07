// RetryInterceptor retries network failures and 5xx up to maxRetries,
// and never retries a 4xx or a cancelled request.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spovies/data/datasources/remote/retry_interceptor.dart';

/// Answers with the queued results in order; the last one repeats.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  final List<Object> script;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final next = script[calls < script.length ? calls : script.length - 1];
    calls++;
    if (next is Exception) throw next;
    return ResponseBody.fromString(
      jsonEncode({'ok': next}),
      next as int,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  (Dio, _ScriptedAdapter) client(List<Object> script) {
    final adapter = _ScriptedAdapter(script);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;
    dio.interceptors.add(
      RetryInterceptor(dio: dio, initialDelay: Duration.zero),
    );
    return (dio, adapter);
  }

  test('recovers from a dropped connection', () async {
    final (dio, adapter) = client([const SocketException('reset'), 200]);

    final res = await dio.get<dynamic>('/x');

    expect(res.statusCode, 200);
    expect(adapter.calls, 2);
  });

  test('retries a 5xx three times, then gives up', () async {
    final (dio, adapter) = client([503]);

    await expectLater(
      dio.get<dynamic>('/x'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          503,
        ),
      ),
    );
    expect(adapter.calls, 4); // first try + 3 retries
  });

  test('does not retry a 4xx', () async {
    final (dio, adapter) = client([404]);

    await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
  });

  test('does not retry a cancelled request', () async {
    final (dio, adapter) = client([200]);
    final token = CancelToken()..cancel();

    await expectLater(
      dio.get<dynamic>('/x', cancelToken: token),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(adapter.calls, 0);
  });
}
