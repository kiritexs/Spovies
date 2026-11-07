// TmdbCacheInterceptor: fresh hits skip the network, network and server
// errors fall back to stale data, 4xx answers are not masked, corrupt
// entries are evicted, and prune() keeps the box bounded.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:spovies/data/datasources/local/hive_service.dart';
import 'package:spovies/data/datasources/remote/tmdb_cache_interceptor.dart';

/// Answers each request with the next queued result: a status code with a
/// JSON body, or an exception to throw. Counts calls.
class _FakeAdapter implements HttpClientAdapter {
  final List<Object> queue = [];
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final next = queue.removeAt(0);
    if (next is Exception) throw next;
    final (code, body) = next as (int, Object);
    return ResponseBody.fromString(
      jsonEncode(body),
      code,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('spovies_cache_test_');
    Hive.init(tmpDir.path);
    HiveService.tmdbCacheBox = await Hive.openBox<Map<dynamic, dynamic>>(
      HiveService.tmdbCacheBoxName,
    );
  });

  tearDownAll(() async {
    await Hive.close();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  late Dio dio;
  late _FakeAdapter adapter;
  Box<Map<dynamic, dynamic>> box() => HiveService.tmdbCacheBox;

  setUp(() async {
    await box().clear();
    adapter = _FakeAdapter();
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(TmdbCacheInterceptor());
  });

  int inMs(Duration d) => DateTime.now().add(d).millisecondsSinceEpoch;

  test('stores a response and serves it from cache while fresh', () async {
    adapter.queue.add((200, {'id': 1}));

    final first = await dio.get<dynamic>('/movie/1');
    final second = await dio.get<dynamic>('/movie/1');

    expect(first.data, {'id': 1});
    expect(second.data, {'id': 1});
    expect(second.statusMessage, 'OK (cached)');
    expect(adapter.calls, 1);
  });

  test('serves stale data when the network fails', () async {
    await box().put('/movie/2?', {
      'body': jsonEncode({'id': 2}),
      'expiresAt': inMs(const Duration(hours: -2)),
    });
    adapter.queue.add(const SocketException('offline'));

    final res = await dio.get<dynamic>('/movie/2');

    expect(res.data, {'id': 2});
    expect(res.statusMessage, 'OK (stale cache)');
  });

  test('does not mask a 4xx with stale data', () async {
    await box().put('/movie/3?', {
      'body': jsonEncode({'id': 3}),
      'expiresAt': inMs(const Duration(hours: -2)),
    });
    adapter.queue.add((404, {'status_message': 'not found'}));

    await expectLater(
      dio.get<dynamic>('/movie/3'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          404,
        ),
      ),
    );
  });

  test('evicts a corrupt entry and goes to the network', () async {
    await box().put('/movie/4?', {
      'body': '{not json',
      'expiresAt': inMs(const Duration(hours: 1)),
    });
    adapter.queue.add((200, {'id': 4}));

    final res = await dio.get<dynamic>('/movie/4');

    expect(res.data, {'id': 4});
    expect(adapter.calls, 1);
  });

  group('prune', () {
    test('drops long-expired and malformed entries', () async {
      final now = DateTime(2026, 6, 1);
      int at(Duration d) => now.add(d).millisecondsSinceEpoch;
      await box().putAll({
        'fresh': {'body': '1', 'expiresAt': at(const Duration(hours: 1))},
        'recent-stale': {
          'body': '1',
          'expiresAt': at(const Duration(days: -1)),
        },
        'old': {'body': '1', 'expiresAt': at(const Duration(days: -30))},
        'malformed': {'body': '1'},
      });

      await TmdbCacheInterceptor.prune(box(), now: now);

      expect(box().keys, unorderedEquals(['fresh', 'recent-stale']));
    });

    test('keeps only the entries that expire last', () async {
      final now = DateTime(2026, 6, 1);
      final extra = 5;
      await box().putAll({
        for (var i = 0; i < TmdbCacheInterceptor.maxEntries + extra; i++)
          'k$i': {
            'body': '1',
            'expiresAt': now.add(Duration(minutes: i)).millisecondsSinceEpoch,
          },
      });

      await TmdbCacheInterceptor.prune(box(), now: now);

      expect(box().length, TmdbCacheInterceptor.maxEntries);
      for (var i = 0; i < extra; i++) {
        expect(box().containsKey('k$i'), isFalse);
      }
    });
  });
}
