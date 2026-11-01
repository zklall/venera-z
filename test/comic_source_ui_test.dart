import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/pages/comic_source_page.dart';
import 'support/test_translations.dart';

class SourceFixture extends Fake implements ComicSource {
  int resets = 0;
  @override
  String get key => 'ui_fixture';
  @override
  String get name => 'Sample source';
  @override
  String get version => '1.0.0';
  @override
  String get filePath => '/unused/ui_fixture.js';
  @override
  AccountConfig? get account => null;
  @override
  Map<String, dynamic> data = {};
  @override
  Map<String, Map<String, dynamic>>? getSettingsDynamic() => {
    'clear_device_info': {
      'type': 'callback',
      'title': '清除设备信息',
      'buttonText': '清除',
      'callback': (List _) {
        resets++;
      },
    },
  };
  @override
  Future<void> saveData() async {}
  @override
  Map<String, Map<String, String>>? get translations => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureTestTranslations);
  late Directory directory;
  late SourceFixture source;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('source-ui-');
    App.dataPath = directory.path;
    appdata.settings['language'] = 'zh-CN';
    appdata.settings['incognitoMode'] = false;
    appdata.settings['incognitoOnlySources'] = <String>[];
    appdata.settings['liquidGlass'] = false;
    appdata.settings['comicSourceLibraries'] = [];
    appdata.settings['comicSourceProvenance'] = {};
    source = SourceFixture();
    ComicSourceManager().add(source);
  });
  tearDown(() async {
    ComicSourceManager().remove(source.key);
    appdata.settings['incognitoMode'] = false;
    appdata.settings['incognitoOnlySources'] = <String>[];
    await directory.delete(recursive: true);
  });
  test('source privacy setting can be restored and saved', () async {
    await ComicSourceManager().setIncognitoOnly(source.key, true);
    expect(ComicSource.visible(), isNot(contains(source)));
    expect(await File('${directory.path}/appdata.json').readAsString(), contains(source.key));
    appdata.syncData({'settings': {'incognitoOnlySources': <String>[]}}, persist: false);
    expect(ComicSource.visible(), isNot(contains(source)));
    await ComicSourceManager().setIncognitoOnly(source.key, false);
    expect(ComicSource.visible(), contains(source));
    final saved = await File('${directory.path}/appdata.json').readAsString();
    expect(saved, contains('incognitoOnlySources'));
  });
  testWidgets('source entry actions are named and settings expand on demand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: App.rootNavigatorKey,
        builder: (context, child) => OverlayWidget(child!),
        home: const ComicSourcePage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('从链接添加'), findsOneWidget);
    expect(find.text('导入文件'), findsOneWidget);
    expect(find.text('Mihon'), findsNothing);
    expect(find.text('清除设备信息'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('source-header-ui_fixture')));
    await tester.pumpAndSettle();
    expect(find.text('清除设备信息'), findsOneWidget);
    await tester.tap(find.text('清除'));
    await tester.pump();
    expect(source.resets, 1);
    expect(find.text('设备信息已清除'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byKey(const ValueKey('source-header-ui_fixture')));
    await tester.pumpAndSettle();
    expect(find.text('清除设备信息'), findsNothing);
  });
  testWidgets(
    'add from link opens an explicitly labeled input with add action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: App.rootNavigatorKey,
          home: const ComicSourcePage(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('从链接添加'));
      await tester.pumpAndSettle();
      expect(find.text('漫画源或仓库链接'), findsOneWidget);
      expect(find.text('添加'), findsOneWidget);
    },
  );
  testWidgets('source only appears while incognito is enabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appdata.settings['searchSources'] = <String>[source.key];
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: App.rootNavigatorKey,
        builder: (context, child) => OverlayWidget(child!),
        home: const ComicSourcePage(),
      ),
    );
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('source-header-ui_fixture'));
    expect(header, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: header,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('仅无痕模式显示'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(header, findsNothing);
    expect(ComicSource.all(), contains(source));
    expect(ComicSource.visible(), isNot(contains(source)));
    expect(appdata.settings['searchSources'], contains(source.key));
    appdata.settings['incognitoMode'] = true;
    await tester.pumpAndSettle();
    expect(header, findsOneWidget);
    appdata.settings['incognitoMode'] = false;
    await tester.pumpAndSettle();
    expect(header, findsNothing);
  });

}
