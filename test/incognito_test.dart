import 'dart:io';
import 'package:venera/utils/data_sync.dart';
import 'package:venera/foundation/res.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/incognito_setting.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/reading_statistics.dart';
import 'support/test_translations.dart';

class _Sync extends Fake implements DataSync {
  int uploads = 0;
  @override
  Future<Res<bool>> uploadData({bool force = false}) async {
    uploads++;
    return const Res(true);
  }
}

const comic = Comic(
  'Saved comic',
  'cover',
  'saved',
  'author',
  [],
  '',
  'local',
  null,
  null,
);
History item(String id, int page) => History.fromMap({
  'id': id,
  'title': 'Saved comic',
  'subtitle': '',
  'cover': 'cover',
  'type': 0,
  'ep': 1,
  'page': page,
  'time': DateTime.now().millisecondsSinceEpoch,
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  DataSync? previousSync;
  late _Sync sync;
  final histories = HistoryManager();
  final statistics = ReadingStatisticsManager();
  setUpAll(ensureTestTranslations);
  setUp(() async {
    previousSync = DataSync.instance;
    sync = _Sync();
    DataSync.instance = sync;
    directory = await Directory.systemTemp.createTemp('venera-incognito-');
    App.dataPath = directory.path;
    appdata.settings['webdav'] = [];
    appdata.settings['incognitoMode'] = false;
    appdata.settings['recordReadingStatistics'] = true;
    appdata.settings['language'] = 'zh-CN';
    appdata.searchHistory = ['existing'];
    histories.close();
    statistics.close();
    await histories.init();
    await statistics.init();
  });
  tearDown(() async {
    await appdata.saveData(false);
    histories.close();
    statistics.close();
    appdata.settings['incognitoMode'] = false;
    await directory.delete(recursive: true);
    DataSync.instance = previousSync;
  });
  test(
    'no new search, history, progress or statistics; resumes after disabling',
    () async {
      histories.addHistory(item('saved', 3));
      final now = DateTime.now();
      void record() => statistics.recordSession(
        comic: comic,
        startedAt: now,
        endedAt: now.add(const Duration(seconds: 10)),
      );
      record();
      appdata.settings['incognitoMode'] = true;
      appdata.addSearchHistory('private query');
      histories.addHistory(item('saved', 9));
      await histories.addHistoryAsync(item('private', 1));
      record();
      expect(appdata.searchHistory, ['existing']);
      expect(sync.uploads, 0);
      expect(histories.length, 1);
      expect(histories.find('saved', ComicType.local)!.page, 3);
      expect(histories.find('private', ComicType.local), isNull);
      expect(statistics.totalDuration(), 10);
      // Verify the original progress is unchanged on disk as well as in memory.
      histories.close();
      await histories.init();
      expect(histories.find('saved', ComicType.local)!.page, 3);
      appdata.settings['incognitoMode'] = false;
      appdata.addSearchHistory('normal query');
      histories.addHistory(item('saved', 5));
      record();
      expect(appdata.searchHistory, ['normal query', 'existing']);
      expect(histories.find('saved', ComicType.local)!.page, 5);
      expect(statistics.totalDuration(), 20);
    },
  );
  test('remote settings cannot turn off device incognito', () {
    appdata.settings['incognitoMode'] = true;
    appdata.syncData({
      'settings': {'incognitoMode': false},
    }, persist: false);
    expect(appdata.isIncognito, isTrue);
  });
  testWidgets(
    'switch shows simplified Chinese, updates immediately and persists',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IncognitoSetting())),
      );
      expect(find.text('无痕模式'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch));
        await appdata.saveData(false);
      });
      await tester.pump();
      expect(appdata.isIncognito, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(File('${directory.path}/appdata.json').existsSync(), isTrue);
      appdata.settings['incognitoMode'] = false;
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    },
  );
}
