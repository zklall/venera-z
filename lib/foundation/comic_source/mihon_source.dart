import 'dart:convert';
import 'dart:io';
import 'package:venera/network/app_dio.dart';
import 'package:flutter/services.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/consts.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/proxy.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/utils/translations.dart';
import 'comic_source.dart';

class MihonSource extends ComicSource {
  static const channel = MethodChannel('venera/mihon');
  final String nativeId;
  final String packageName;

  static String? _configuration;
  static Future<void>? _configurationTask;
  static Future<void> _configure() async {
    if (!App.isAndroid) return;
    final proxy = await getProxy();
    final dns = appdata.settings['enableDnsOverrides'] == true
        ? appdata.settings['dnsOverrides']
        : <String, String>{};
    final signature = jsonEncode([proxy, dns]);
    if (_configuration == signature) return;
    if (_configurationTask != null) {
      await _configurationTask;
      if (_configuration == signature) return;
      return _configure();
    }
    final task = channel.invokeMethod<void>('configure', {
      'proxy': proxy,
      'dns': dns,
      'userAgent': webUA,
    });
    _configurationTask = task;
    try {
      await task;
      _configuration = signature;
    } finally {
      _configurationTask = null;
    }
  }

  static Future<T> _call<T>(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    await _configure();
    try {
      return (await channel.invokeMethod<T>(method, arguments))!;
    } on PlatformException catch (error, stack) {
      Log.error('Mihon', '${error.message}\n${error.details}');
      Error.throwWithStackTrace(error.message ?? error.code, stack);
    }
  }

  static Future<Map<String, dynamic>> installed() async {
    if (!App.isAndroid) return {'sources': [], 'failures': {}};
    await _configure();
    final result = await channel.invokeMapMethod<String, dynamic>('list');
    return result ?? {'sources': [], 'failures': {}};
  }

  static Future<List<MihonSource>> loadInstalledSources() async {
    final result = await installed();
    return [
      for (final source in (result['sources'] as List? ?? []).whereType<Map>())
        MihonSource(Map<String, dynamic>.from(source)),
    ];
  }

  static Future<Res<T>> _read<T>(Future<T> Function() read) async {
    try {
      return Res(await read());
    } catch (error) {
      return Res.error(
        error is PlatformException
            ? (error.message ?? error.code)
            : error.toString(),
      );
    }
  }

  static Future<Res<List<Comic>>> _comicPage(
    String id,
    String key,
    String method,
    int page, {
    String query = '',
    bool latest = false,
  }) async {
    try {
      final data = await _call<Map>(method, {
        'id': id,
        'page': page,
        'query': query,
        'latest': latest,
      });
      final comics = [
        for (final raw in (data['comics'] as List).whereType<Map>())
          Comic(
            raw['title'] as String,
            raw['cover'] as String,
            raw['id'] as String,
            raw['subtitle'] as String?,
            (raw['tags'] as List?)?.cast<String>(),
            raw['description'] as String? ?? '',
            key,
            null,
            null,
          ),
      ];
      return Res(comics, subData: data['hasNext'] == true ? page + 1 : page);
    } catch (error) {
      return Res.error(
        error is PlatformException
            ? (error.message ?? error.code)
            : error.toString(),
      );
    }
  }

  static Future<Res<ComicDetails>> _details(
    String id,
    String key,
    String url,
  ) => _read(() async {
    final data = await _call<Map>('details', {'id': id, 'url': url});
    return ComicDetails.fromJson({
      ...Map<String, dynamic>.from(data),
      'sourceKey': key,
    });
  });
  static Future<Res<List<String>>> _pages(
    String id,
    String? chapter,
  ) => _read(() async {
    final count = await _call<int>('pages', {'id': id, 'chapter': chapter});
    return [
      for (var i = 0; i < count; i++)
        'mihon:${base64Url.encode(utf8.encode(jsonEncode({'chapter': chapter, 'index': i})))}',
    ];
  });

  Future<Uint8List> image(String key, {bool thumbnail = false}) async {
    final arguments = thumbnail
        ? <String, dynamic>{'cover': key}
        : Map<String, dynamic>.from(
            jsonDecode(
                  utf8.decode(base64Url.decode(key.substring('mihon:'.length))),
                )
                as Map,
          );
    return _call<Uint8List>('image', {'id': nativeId, ...arguments});
  }

  Future<bool> updateFromUrl(String url, {bool Function()? canApply}) async {
    final directory = await Directory.systemTemp.createTemp('mihon-update-');
    try {
      final path = '${directory.path}/extension.apk';
      await AppDio().download(
        url,
        path,
        options: Options(headers: {'cache-time': 'no'}),
      );
      final metadata = await inspect(path);
      if (metadata['package'] != packageName) {
        throw const FormatException(
          'Extension package does not match the catalog',
        );
      }
      if (canApply?.call() == false) return false;
      await install(path);
      await ComicSourceManager().reload();
      return true;
    } finally {
      await directory.delete(recursive: true);
    }
  }

  static Future<void> uninstallPackage(String package) =>
      channel.invokeMethod<void>('uninstall', {'package': package});
  static Future<Map<String, dynamic>> inspect(String path) async =>
      Map<String, dynamic>.from(await _call<Map>('inspect', {'path': path}));
  static Future<void> install(String path) =>
      channel.invokeMethod<void>('install', {'path': path});

  @override
  Map<String, Map<String, dynamic>>? getSettingsDynamic() => settings;

  // Constructor is defined below with the same immutable source contract as JS.
  MihonSource(Map<String, dynamic> metadata)
    : nativeId = metadata['id'] as String,
      packageName = metadata['package'] as String,
      super(
        '${metadata['name']} (${metadata['lang']})', // name
        'mihon_${metadata['id']}', // key
        null, // account
        null, // categoryData
        null, // categoryComicsData
        null, // favoriteData
        [
          ExplorePageData(
            '${metadata['name']} · ${'Popular'.tl}',
            ExplorePageType.multiPageComicList,
            (page) => _comicPage(
              '${metadata['id']}',
              'mihon_${metadata['id']}',
              'popular',
              page,
            ),
            null,
            null,
            null,
          ),
        ], // explorePages
        SearchPageData(
          const [],
          (query, page, options) => _comicPage(
            '${metadata['id']}',
            'mihon_${metadata['id']}',
            'search',
            page,
            query: query,
          ),
          null,
        ), // searchPageData
        {
          if (metadata['configurable'] == true)
            'mihon': {
              'type': 'callback',
              'title': 'Source settings'.tl,
              'buttonText': 'Open'.tl,
              'callback': (List<dynamic> _) =>
                  channel.invokeMethod('settings', {'id': metadata['id']}),
            },
        }, // settings
        (url) => _details(
          '${metadata['id']}',
          'mihon_${metadata['id']}',
          url,
        ), // loadComicInfo
        null, // loadComicThumbnail
        (id, ep) => _pages('${metadata['id']}', ep), // loadComicPages
        null, // getImageLoadingConfig
        null, // getThumbnailLoadingConfig
        'mihon:${metadata['package']}', // filePath
        metadata['baseUrl'] as String? ?? '', // url
        metadata['version'] as String? ?? '', // version
        null, // commentsLoader
        null, // sendCommentFunc
        null, // chapterCommentsLoader
        null, // sendChapterCommentFunc
        null, // likeOrUnlikeComic
        null, // voteCommentFunc
        null, // likeCommentFunc
        null, // idMatcher
        null, // translations
        null, // handleClickTagEvent
        null, // onTagSuggestionSelected
        null, // linkHandler
        false, // enableTagsSuggestions
        false, // enableTagsTranslate
        null, // starRatingFunc
        null, // archiveDownloader
      );
}
