import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/mihon_source.dart';
import 'support/test_translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureTestTranslations);
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MihonSource.channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'search':
            case 'popular':
              return {
                'comics': [
                  {
                    'id': '/book/1',
                    'title': 'Book',
                    'cover': 'https://example.com/cover.jpg',
                    'tags': ['Adventure'],
                  },
                ],
                'hasNext': call.arguments['page'] == 1,
              };
            case 'details':
              return {
                'comicId': '/book/1',
                'title': 'Book',
                'cover': 'https://example.com/cover.jpg',
                'tags': {
                  'author': ['A'],
                },
                'chapters': {'/ep/1': 'Chapter 1', '/ep/2': 'Chapter 2'},
              };
            case 'pages':
              return 2;
            case 'image':
              return Uint8List.fromList([1, 2, 3]);
            case 'settings':
              return null;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MihonSource.channel, null),
  );
  MihonSource source() => MihonSource({
    'id': '1234567890123456789',
    'name': 'Sample',
    'lang': 'zh',
    'package': 'eu.example.source',
    'version': '1.6.1',
    'configurable': true,
  });
  test(
    'search, details and chapter order use native source identity without loss',
    () async {
      final s = source();
      final found = await s.searchPageData!.loadPage!('keyword', 1, []);
      expect(found.error, isFalse);
      expect(found.data.single.sourceKey, s.key);
      expect(found.subData, 2);
      final last = await s.searchPageData!.loadPage!('keyword', 2, []);
      expect(last.subData, 2);
      final details = await s.loadComicInfo!('/book/1');
      expect(details.data.sourceKey, s.key);
      expect(details.data.chapters!.ids, ['/ep/1', '/ep/2']);
      expect(calls.first.arguments['id'], '1234567890123456789');
    },
  );
  test(
    'native page handles preserve chapter and image position across reader reload',
    () async {
      final s = source();
      final pages = await s.loadComicPages!('/book/1', '/ep/2?token=a');
      expect(pages.data, hasLength(2));
      final decoded = jsonDecode(
        utf8.decode(
          base64Url.decode(pages.data.last.substring('mihon:'.length)),
        ),
      );
      expect(decoded, {'chapter': '/ep/2?token=a', 'index': 1});
      expect(await s.image(pages.data.last), [1, 2, 3]);
      expect(calls.last.arguments['chapter'], '/ep/2?token=a');
      expect(calls.last.arguments['index'], 1);
      expect(await s.image('https://example.com/cover.jpg', thumbnail: true), [
        1,
        2,
        3,
      ]);
      expect(calls.last.arguments['cover'], 'https://example.com/cover.jpg');
    },
  );
  test(
    'source settings call native preferences rather than JavaScript',
    () async {
      final setting = source().getSettingsDynamic()!.values.single;
      await setting['callback']([]);
      expect(calls.single.method, 'settings');
    },
  );
  test(
    'native failures preserve readable HTTP status and verification URL',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MihonSource.channel,
            (_) async => throw PlatformException(
              code: 'mihon_error',
              message: 'CloudflareException: https://example.com/',
            ),
          );
      final result = await source().loadComicInfo!('/book/1');
      expect(result.error, isTrue);
      expect(result.errorMessage, 'CloudflareException: https://example.com/');
    },
  );
}
