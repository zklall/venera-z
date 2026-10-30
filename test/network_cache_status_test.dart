import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/network/cache.dart';

class _Responses implements HttpClientAdapter {
  _Responses(this.initialStatus);
  final int initialStatus;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    calls++;
    return ResponseBody.fromString(
      calls == 1
          ? '{"message":"refused","results":{}}'
          : '{"results":{"comic":{"name":"OK"}}}',
      calls == 1 ? initialStatus : 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final code in [210, 206, 302, 401, 402, 429, 503]) {
    test(
      'does not disguise or cache HTTP $code as a successful comic',
      () async {
        final cache = NetworkCacheManager()..clear();
        final adapter = _Responses(code);
        final dio = Dio(BaseOptions(validateStatus: (_) => true))
          ..httpClientAdapter = adapter
          ..interceptors.add(cache);
        try {
          final first = await dio.get('https://fixture.invalid/comic');
          expect(first.statusCode, code);
          final second = await dio.get('https://fixture.invalid/comic');
          expect(second.statusCode, 200);
          expect(second.data['results']['comic']['name'], 'OK');
          final third = await dio.get('https://fixture.invalid/comic');
          expect(third.data, second.data);
          expect(adapter.calls, 2);
        } finally {
          dio.close();
          cache.clear();
        }
      },
    );
  }
}
