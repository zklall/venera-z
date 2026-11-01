import 'dart:convert';
import 'package:venera/network/app_dio.dart';
import 'mihon_catalog.dart';

Future<List<Map<String, dynamic>>> fetchCompatibleSourceCatalog(
  String address, {
  Dio? dio,
}) async {
  List<Map<String, dynamic>> extensions(List<MihonExtension> values) => [
    for (final e in values)
      {
        '_format': 'mihon',
        'name': e.name,
        'key': e.package,
        'version': e.version,
        'url': e.apkUrl,
      },
  ];
  if (isExtensionRepository(address)) {
    return extensions(await MihonCatalog.load(address, dio: dio));
  }
  final response = await (dio ?? AppDio()).get<String>(
    address,
    options: Options(
      headers: {'cache-time': 'no'},
      responseType: ResponseType.plain,
    ),
  );
  if (response.statusCode != 200 || response.data == null) {
    throw StateError('HTTP ${response.statusCode}');
  }
  final raw = jsonDecode(response.data!);
  if (raw is Map ||
      raw is List &&
          raw.whereType<Map>().any(
            (e) => e.containsKey('pkg') || e.containsKey('packageName'),
          )) {
    return extensions(await MihonCatalog.load(address, dio: dio));
  }
  if (raw is! List) throw const FormatException('Invalid source catalog');
  return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
}
