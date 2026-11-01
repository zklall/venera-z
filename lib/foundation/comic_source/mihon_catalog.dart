import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:venera/network/app_dio.dart';
import 'source_library.dart';

class MihonExtension {
  const MihonExtension({
    required this.name,
    required this.package,
    required this.version,
    required this.languages,
    required this.sources,
    required this.apkUrl,
  });
  final String name, package, version, apkUrl;
  final List<String> languages, sources;
}

bool isExtensionRepository(String address) {
  final uri = Uri.tryParse(address.trim());
  final name = uri?.pathSegments.lastOrNull ?? '';
  return name == 'repo.json' ||
      name == 'index.min.json' ||
      name.endsWith('.pb') ||
      name == 'repo';
}

class MihonCatalog {
  static const defaultUrl =
      'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json';
  static Future<List<MihonExtension>> load(String address, {Dio? dio}) async {
    final client = dio ?? AppDio();
    var input = Uri.parse(address.trim());
    if (!isHttpSourceUrl(input.toString())) {
      throw const FormatException('Invalid catalog URL');
    }
    final filename = input.pathSegments.lastOrNull ?? '';
    final isRoot = !filename.contains('.');
    final root = isRoot
        ? input.replace(path: '${input.path.replaceFirst(RegExp(r'/+$'), '')}/')
        : input.resolve('.');
    Future<List<MihonExtension>> read(
      Uri url,
      int depth, {
      bool listOnly = false,
    }) async {
      if (depth > 4 || !isHttpSourceUrl(url.toString())) {
        throw const FormatException('Invalid Mihon catalog link');
      }
      final response = await client.get<List<int>>(
        url.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'cache-time': 'no'},
        ),
      );
      if (response.statusCode != 200 || response.data == null) {
        throw StateError('HTTP ${response.statusCode}');
      }
      var bytes = response.data!;
      if (bytes.length >= 2 && bytes[0] == 31 && bytes[1] == 139) {
        bytes = gzip.decode(bytes);
      }
      if (bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('Mihon catalog is too large');
      }
      final first = bytes
          .skipWhile((b) => b == 32 || b == 10 || b == 13 || b == 9)
          .firstOrNull;
      List raw;
      if (first == 91 || first == 123) {
        final json = jsonDecode(utf8.decode(bytes));
        if (json is Map) {
          final next =
              json['index_v2'] ?? json['index_v1'] ?? json['extensionListUrl'];
          if (next is String) {
            return read(
              url.resolve(next),
              depth + 1,
              listOnly: json.containsKey('extensionListUrl'),
            );
          }
          final list = json['extensionList'];
          if (list is Map) {
            raw = list['extensions'] as List? ?? [];
          } else if (json['extensions'] is List) {
            raw = json['extensions'] as List;
          } else {
            throw const FormatException('Invalid Mihon catalog');
          }
        } else if (json is List) {
          raw = json;
        } else {
          throw const FormatException('Invalid Mihon catalog');
        }
      } else {
        final decoded = decodeIndex(bytes, listOnly: listOnly);
        if (decoded.url != null) {
          return read(url.resolve(decoded.url!), depth + 1, listOnly: true);
        }
        raw = decoded.entries;
      }
      return parseEntries(raw, url);
    }

    if (isRoot || filename == 'index.min.json') {
      try {
        return await read(root.resolve('repo.json'), 0);
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
      }
      input = isRoot ? root.resolve('index.min.json') : input;
    }
    return read(input, 0);
  }

  static List<MihonExtension> parseEntries(List raw, Uri base) {
    final result = <MihonExtension>[];
    for (final item in raw.whereType<Map>()) {
      final pkg = item['packageName'] ?? item['pkg'];
      if (pkg is! String ||
          !RegExp(r'^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$').hasMatch(pkg) ||
          item['name'] is! String) {
        continue;
      }
      final sources = (item['sources'] as List? ?? [])
          .whereType<Map>()
          .toList();
      final resources = item['resources'];
      final direct = resources is Map ? resources['apkUrl'] : null;
      final file = item['apk'];
      final uri = direct is String
          ? base.resolve(direct)
          : file is String && RegExp(r'^[\w.+-]+\.apk$').hasMatch(file)
          ? base.resolve('apk/$file')
          : null;
      if (uri == null ||
          !isHttpSourceUrl(uri.toString()) ||
          !uri.path.endsWith('.apk')) {
        continue;
      }
      result.add(
        MihonExtension(
          name: item['name'] as String,
          package: pkg,
          version: (item['versionName'] ?? item['version'] ?? '').toString(),
          languages: {
            if (item['lang'] is String) item['lang'] as String,
            for (final s in sources)
              if ((s['language'] ?? s['lang']) is String)
                (s['language'] ?? s['lang']) as String,
          }.toList(),
          sources: [
            for (final s in sources)
              if (s['name'] is String) s['name'] as String,
          ],
          apkUrl: uri.toString(),
        ),
      );
    }
    return result;
  }

  /// TachiyomiX index.proto; skips unknown fields for forward compatibility.
  static ({List<Map<String, dynamic>> entries, String? url}) decodeIndex(
    List<int> bytes, {
    bool listOnly = false,
  }) {
    final index = _Wire(bytes);
    final list = listOnly ? index : index.message(101);
    final next = listOnly ? null : index.string(102);
    if (list == null && next == null) {
      throw const FormatException('Invalid Mihon index');
    }
    return (
      url: next,
      entries: [
        for (final e in list?.messages(1) ?? <_Wire>[])
          {
            'name': e.string(1),
            'packageName': e.string(2),
            'versionName': e.string(6),
            'resources': {'apkUrl': e.message(3)?.string(1)},
            'sources': [
              for (final s in e.messages(8))
                {'name': s.string(2), 'language': s.string(3)},
            ],
          },
      ],
    );
  }
}

class _Wire {
  _Wire(List<int> bytes) {
    var offset = 0;
    int varint() {
      var value = 0;
      for (var shift = 0; shift < 70; shift += 7) {
        if (offset >= bytes.length) {
          throw const FormatException('Truncated Mihon index');
        }
        final byte = bytes[offset++];
        value |= (byte & 127) << shift;
        if (byte < 128) return value;
      }
      throw const FormatException('Invalid Mihon index integer');
    }

    while (offset < bytes.length) {
      final tag = varint();
      if (tag >> 3 == 0) {
        throw const FormatException('Invalid Mihon index field');
      }
      final wire = tag & 7;
      if (wire == 0) {
        varint();
        continue;
      }
      final length = switch (wire) {
        1 => 8,
        2 => varint(),
        5 => 4,
        _ => throw const FormatException('Invalid Mihon index field type'),
      };
      if (length < 0 || length > bytes.length - offset) {
        throw const FormatException('Truncated Mihon index');
      }
      if (wire == 2) {
        (_fields[tag >> 3] ??= []).add(
          Uint8List.fromList(bytes.sublist(offset, offset + length)),
        );
      }
      offset += length;
    }
  }
  final _fields = <int, List<Uint8List>>{};
  String? string(int n) =>
      _fields[n]?.isNotEmpty == true ? utf8.decode(_fields[n]!.last) : null;
  _Wire? message(int n) =>
      _fields[n]?.isNotEmpty == true ? _Wire(_fields[n]!.last) : null;
  List<_Wire> messages(int n) => [
    for (final b in _fields[n] ?? <Uint8List>[]) _Wire(b),
  ];
}
