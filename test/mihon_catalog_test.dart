import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/mihon_catalog.dart';
import 'package:venera/foundation/app_error.dart';
import 'package:venera/foundation/comic_source/source_catalog.dart';

List<int> vi(int n) {
  final out = <int>[];
  do {
    out.add((n & 127) | (n > 127 ? 128 : 0));
    n >>= 7;
  } while (n > 0);
  return out;
}

List<int> msg(int field, List<int> bytes) => [
  ...vi(field * 8 + 2),
  ...vi(bytes.length),
  ...bytes,
];
List<int> text(int field, String value) => msg(field, utf8.encode(value));
final extension = [
  ...text(1, 'Example'),
  ...text(2, 'eu.example.manga'),
  ...msg(3, text(1, 'apk/example.apk')),
  ...text(6, '1.6.3'),
  ...msg(8, [...text(2, 'Example 中文'), ...text(3, 'zh')]),
];
final index = msg(101, msg(1, extension));

class CatalogAdapter implements HttpClientAdapter {
  CatalogAdapter(this.responses);
  final Map<String, (int, List<int>)> responses;
  final requests = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    final path = options.uri.path;
    requests.add(path);
    final (status, data) = responses[path] ?? (404, utf8.encode('{}'));
    return ResponseBody.fromBytes(data, status);
  }

  @override
  void close({bool force = false}) {}
}

Dio client(CatalogAdapter adapter) => Dio()..httpClientAdapter = adapter;
void main() {
  test('native HTTP and DNS errors use readable classifications', () {
    expect(
      AppErrorInfo.statusCode(
        'eu.kanade.tachiyomi.network.HttpException: HTTP error 402',
      ),
      402,
    );
    expect(
      AppErrorInfo.from(
        'java.net.UnknownHostException: unable to resolve host',
      ).canAutoRetry,
      isTrue,
    );
    expect(
      AppErrorInfo.from(
        'java.lang.NoClassDefFoundError: missing source dependency',
      ).titleKey,
      'Extension is incompatible',
    );
  });
  test('old Mihon list resolves APK location and rejects unsafe filenames', () {
    final result = MihonCatalog.parseEntries([
      {
        'name': 'Example',
        'pkg': 'eu.example.manga',
        'version': '1.4.1',
        'lang': 'zh',
        'apk': 'source.apk',
      },
      {'name': 'Traversal', 'pkg': 'eu.example.bad', 'apk': '../app.apk'},
      {
        'name': 'Foreign scheme',
        'pkg': 'eu.example.bad2',
        'resources': {'apkUrl': 'file:///app.apk'},
      },
    ], Uri.parse('https://example.org/repo/index.min.json'));
    expect(result.single.apkUrl, 'https://example.org/repo/apk/source.apk');
    expect(result.single.languages, ['zh']);
  });
  test(
    'old user URL follows modern metadata and gzip protobuf rather than upgrade placeholders',
    () async {
      final adapter = CatalogAdapter({
        '/repo/repo.json': (
          200,
          utf8.encode(jsonEncode({'index_v2': 'index.pb'})),
        ),
        '/repo/index.pb': (200, gzip.encode(index)),
      });
      final values = await MihonCatalog.load(
        'https://example.org/repo/index.min.json',
        dio: client(adapter),
      );
      expect(values.single.package, 'eu.example.manga');
      expect(values.single.apkUrl, 'https://example.org/repo/apk/example.apk');
      expect(values.single.languages, ['zh']);
      expect(adapter.requests, ['/repo/repo.json', '/repo/index.pb']);
    },
  );
  test(
    'legacy repository without metadata still reads index.min.json',
    () async {
      final adapter = CatalogAdapter({
        '/repo/index.min.json': (
          200,
          utf8.encode(
            jsonEncode([
              {
                'name': 'Legacy',
                'pkg': 'eu.example.legacy',
                'version': '1.4.1',
                'lang': 'en',
                'apk': 'legacy.apk',
              },
            ]),
          ),
        ),
      });
      expect(
        (await MihonCatalog.load(
          'https://example.org/repo/',
          dio: client(adapter),
        )).single.name,
        'Legacy',
      );
    },
  );
  test('linked extension list protobuf is supported', () async {
    final adapter = CatalogAdapter({
      '/index.pb': (200, text(102, 'list.pb')),
      '/list.pb': (200, msg(1, extension)),
    });
    expect(
      (await MihonCatalog.load(
        'https://example.org/index.pb',
        dio: client(adapter),
      )).single.version,
      '1.6.3',
    );
  });
  test(
    'JSON v2 and cyclical links are handled without unbounded recursion',
    () async {
      final adapter = CatalogAdapter({
        '/index.json': (
          200,
          utf8.encode(
            jsonEncode({
              'extensionList': {
                'extensions': [
                  {
                    'name': 'V2',
                    'packageName': 'eu.example.v2',
                    'versionName': '1.6.1',
                    'resources': {'apkUrl': 'https://example.org/app.apk'},
                    'sources': [
                      {'name': 'V2', 'language': 'ja'},
                    ],
                  },
                ],
              },
            }),
          ),
        ),
      });
      expect(
        (await MihonCatalog.load(
          'https://example.org/index.json',
          dio: client(adapter),
        )).single.languages,
        ['ja'],
      );
      final cycle = CatalogAdapter({
        '/repo.json': (200, utf8.encode('{"index_v2":"repo.json"}')),
      });
      await expectLater(
        MihonCatalog.load('https://example.org/repo.json', dio: client(cycle)),
        throwsFormatException,
      );
      expect(cycle.requests.length, lessThanOrEqualTo(5));
    },
  );
  test('malformed binary fields fail cleanly', () {
    for (final bytes in [
      [0],
      [10, 10, 1],
      [15],
      [128],
      [138, 6, 255],
    ]) {
      expect(() => MihonCatalog.decodeIndex(bytes), throwsFormatException);
    }
  });
  test(
    'regular Venera catalogs remain JS entries through the shared loader',
    () async {
      final adapter = CatalogAdapter({
        '/index.json': (
          200,
          utf8.encode(
            '[{"name":"JS","key":"js","fileName":"source.js","version":"1.0.0"}]',
          ),
        ),
      });
      final result = await fetchCompatibleSourceCatalog(
        'https://example.org/index.json',
        dio: client(adapter),
      );
      expect(result.single['fileName'], 'source.js');
      expect(result.single['_format'], isNull);
    },
  );
}
