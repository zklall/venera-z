import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app_update.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/app_dio.dart' show AppDio;

ReleaseAsset apk(String name) => ReleaseAsset(
  name: name,
  url: 'https://github.com/zklall/venera-prime/releases/download/v3/$name',
  size: 4,
);
LatestRelease release(List<ReleaseAsset> assets) =>
    LatestRelease(version: '3.0', title: '', body: '', url: '', assets: assets);

void main() {
  test(
    'select APK by ABI preference with universal fallback, never incompatible split',
    () {
      final assets = [
        apk('venera-arm64-v8a.apk'),
        apk('venera-x86_64.apk'),
        apk('venera-armeabi-v7a.apk'),
        apk('venera.apk'),
      ];
      expect(
        release(assets).androidAsset(['arm64-v8a', 'armeabi-v7a'])!.name,
        'venera-arm64-v8a.apk',
      );
      expect(
        release(assets).androidAsset(['x86_64', 'x86'])!.name,
        'venera-x86_64.apk',
      );
      expect(release(assets).androidAsset(['mips'])!.name, 'venera.apk');
      expect(release(assets.take(3).toList()).androidAsset(['mips']), isNull);
    },
  );

  test(
    'parse release assets, reject foreign download URLs and ignore malformed data',
    () {
      final parsed = LatestRelease.fromJson({
        'tag_name': 'v3.0.0+300',
        'name': '',
        'assets': [
          {
            'name': 'venera.apk',
            'browser_download_url': apk('venera.apk').url,
            'size': 4,
          },
          {
            'name': 'other.apk',
            'browser_download_url': 'https://example.com/app.apk',
            'size': 4,
          },
          {
            'name': 'upstream.apk',
            'browser_download_url':
                'https://github.com/venera-app/venera-prime/releases/download/v3/upstream.apk',
            'size': 4,
          },
          {'name': 'broken.apk'},
        ],
      });
      expect(parsed.version, '3.0.0');
      expect(parsed.assets.single.name, 'venera.apk');
      expect(
        parsed.url,
        'https://github.com/zklall/venera-prime/releases/latest',
      );
    },
  );

  test('fetches the fork release feed and accepts its APK', () async {
    final adapter = _ReleaseFeedAdapter(200, {
      'tag_name': 'v3.0.0',
      'assets': [
        {
          'name': 'venera-arm64-v8a.apk',
          'browser_download_url': apk('venera-arm64-v8a.apk').url,
          'size': 4,
        },
      ],
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final latest = await fetchLatestAppRelease(dio: dio);
    expect(
      adapter.request!.uri.toString(),
      'https://api.github.com/repos/zklall/venera-prime/releases/latest',
    );
    expect(latest!.version, '3.0.0');
    expect(latest.androidAsset(['arm64-v8a'])!.name, 'venera-arm64-v8a.apk');
    dio.close();
  });

  test('a fork with no published release is not a network failure', () async {
    final dio = Dio()
      ..httpClientAdapter = _ReleaseFeedAdapter(404, {'message': 'Not Found'});
    expect(await fetchLatestAppRelease(dio: dio), isNull);
    dio.close();
  });

  test('release server and malformed feed errors are preserved', () async {
    final dio = Dio()..httpClientAdapter = _ReleaseFeedAdapter(503, {});
    await expectLater(
      fetchLatestAppRelease(dio: dio),
      throwsA(isA<DioException>()),
    );
    dio.httpClientAdapter = _ReleaseFeedAdapter(200, {});
    await expectLater(fetchLatestAppRelease(dio: dio), throwsFormatException);
    dio.close();
  });

  test(
    'stable version comparison handles differing lengths and build metadata',
    () {
      expect(isNewerAppVersion('2.4.10', '2.4.9'), isTrue);
      expect(isNewerAppVersion('2.5', '2.4.6'), isTrue);
      expect(isNewerAppVersion('2.4.6.1', '2.4.6'), isTrue);
      expect(isNewerAppVersion('2.4.6+246', '2.4.6'), isFalse);
      expect(isNewerAppVersion('2.4', '2.4.0'), isFalse);
      expect(isNewerAppVersion('3.0.0-beta', '2.4.6'), isFalse);
      expect(isNewerAppVersion('invalid', '2.4.6'), isFalse);
    },
  );

  group('download verification', () {
    late HttpServer server;
    late Directory dir;
    final bytes = [1, 2, 3, 4];
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('update-test-');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        if (request.uri.path == '/partial.apk') {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('content-range', 'bytes 0-3/9');
        }
        request.response.add(bytes);
        request.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    Dio localDio() => AppDio()
      ..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => HttpOverrides.runWithHttpOverrides(
          () => HttpClient(),
          _RealHttpOverrides(),
        ),
      );
    ReleaseAsset asset({int size = 4, String? digest}) => ReleaseAsset(
      name: 'venera.apk',
      url: 'http://127.0.0.1:${server.port}/venera.apk',
      size: size,
      digest: digest,
    );

    test(
      'verified download becomes installable and partial file is removed',
      () async {
        final progress = <int>[];
        final downloaded = await AppUpdateDownloader(dio: localDio()).download(
          asset(digest: 'sha256:${sha256.convert(bytes)}'),
          dir,
          cancelToken: CancelToken(),
          onProgress: (received, total) => progress.add(received),
        );
        expect(await downloaded.readAsBytes(), bytes);
        expect(progress.last, bytes.length);
        expect(await File('${downloaded.path}.part').exists(), isFalse);
      },
    );
    test('size or digest mismatch never leaves an installable file', () async {
      for (final bad in [asset(size: 9), asset(digest: 'sha256:${'0' * 64}')]) {
        await expectLater(
          AppUpdateDownloader(
            dio: localDio(),
          ).download(bad, dir, cancelToken: CancelToken()),
          throwsFormatException,
        );
        expect(dir.listSync(), isEmpty);
      }
    });
    test(
      'incomplete responses report byte counts without signed URLs',
      () async {
        Log.clear();
        await expectLater(
          AppUpdateDownloader(dio: localDio()).download(
            ReleaseAsset(
              name: 'venera.apk',
              url: 'http://127.0.0.1:${server.port}/partial.apk?sig=private',
              size: 9,
            ),
            dir,
            cancelToken: CancelToken(),
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('expected 9 bytes, received 4 bytes'),
            ),
          ),
        );
        final diagnostic = Log.logs.last.content;
        expect(diagnostic, contains('expected=9, actual=4, received=4'));
        expect(diagnostic, contains('status=206'));
        expect(diagnostic, contains('content-range=bytes 0-3/9'));
        expect(diagnostic, isNot(contains('private')));
        expect(diagnostic, isNot(contains('127.0.0.1')));
        expect(dir.listSync(), isEmpty);
        Log.clear();
      },
    );
    test('cancelled downloads clean up partial files', () async {
      final cancel = CancelToken()..cancel();
      await expectLater(
        AppUpdateDownloader(
          dio: localDio(),
        ).download(asset(), dir, cancelToken: cancel),
        throwsA(isA<DioException>()),
      );
      expect(dir.listSync(), isEmpty);
    });
    test('cancellation during transfer removes partial files', () async {
      final cancel = CancelToken();
      await expectLater(
        AppUpdateDownloader(dio: localDio()).download(
          asset(),
          dir,
          cancelToken: cancel,
          onProgress: (_, _) => cancel.cancel(),
        ),
        throwsA(isA<DioException>()),
      );
      expect(dir.listSync(), isEmpty);
    });
    test(
      'invalid filenames cannot escape or replace the update directory',
      () async {
        for (final name in [
          '',
          '/',
          '.',
          '..',
          '../bad.apk',
          r'..\bad.apk',
          'notes.txt',
        ]) {
          await expectLater(
            AppUpdateDownloader(dio: localDio()).download(
              ReleaseAsset(name: name, url: asset().url, size: 4),
              dir,
              cancelToken: CancelToken(),
            ),
            throwsFormatException,
          );
          expect(dir.listSync(), isEmpty);
          expect(File('${dir.path}.part').existsSync(), isFalse);
        }
      },
    );
  });

  testWidgets(
    'Android updater passes device ABIs and APK path over native channel',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('venera/method_channel'),
        (call) async {
          calls.add(call);
          return call.method == 'getSupportedAbis'
              ? ['arm64-v8a', 'armeabi-v7a']
              : false;
        },
      );
      expect(await AndroidAppUpdater.supportedAbis(), [
        'arm64-v8a',
        'armeabi-v7a',
      ]);
      expect(
        await AndroidAppUpdater.install(File('/cache/updates/venera.apk')),
        isFalse,
      );
      expect(calls.last.arguments, {'path': '/cache/updates/venera.apk'});
    },
  );
}

class _RealHttpOverrides extends HttpOverrides {}

class _ReleaseFeedAdapter implements HttpClientAdapter {
  _ReleaseFeedAdapter(this.statusCode, this.data);

  final int statusCode;
  final Map<String, dynamic> data;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
