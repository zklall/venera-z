import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/utils/data_sync.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/reader/reader.dart';
import 'package:venera/utils/translations.dart';
import 'reader_page_margin_test.dart' as fixture;

class _NoDataSync extends Fake implements DataSync {
  @override
  void onDataChanged() {}

  @override
  Future<Res<bool>> uploadData({bool force = false}) async => const Res(true);
}

Future<void> closeReader(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  await fixture.settle(tester);
  // The widget fixture uses a fake clock while settings use real filesystem
  // writes. Drain the serialized save queue before reusing the next fixture.
  var saved = false;
  final flush = appdata.saveData(false).then((_) => saved = true);
  for (var attempt = 0; !saved && attempt < 25; attempt++) {
    await fixture.settle(tester);
  }
  expect(
    saved,
    isTrue,
    reason: 'reader settings finish saving before teardown',
  );
  await flush;
}

void main() {
  late DataSync? previousSync;
  setUp(() {
    previousSync = DataSync.instance;
    DataSync.instance = _NoDataSync();
  });
  tearDown(() => DataSync.instance = previousSync);

  testWidgets(
    'pages 12 and 13 can be selected across old groups, saved, reopened and reset',
    (tester) async {
      dynamic state = await fixture.openReader(
        tester,
        'galleryRightToLeft',
        imageCount: 19,
        initialPage: 12,
        imageSizes: {
          for (var image = 1; image <= 19; image++) image: const Size(90, 128),
        },
      );
      appdata.settings['readerTwoPageSpread'] = true;
      state.update();
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.page), (10, 12));
      expect(state.imageLayout.range(state.page + 1), (12, 14));
      await tester.tapAt(const Offset(500, 300));
      await fixture.settle(tester);
      await tester.tap(find.byKey(const Key('reader-spread-options')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('Choose two pages for a spread'.tl),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      await fixture.settle(tester);
      final candidate = find.byKey(const Key('reader-spread-pair-12'));
      await tester.ensureVisible(candidate);
      await tester.tap(candidate);
      await tester.pumpAndSettle();
      // Preview selection alone must never change or persist the reader layout.
      expect(state.imageLayout.range(state.page), (10, 12));
      expect(appdata.settings['readerSpreadOverrides'], isEmpty);
      await tester.ensureVisible(
        find.byKey(const Key('reader-spread-pair-confirm')),
      );
      await tester.tap(find.byKey(const Key('reader-spread-pair-confirm')));
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.page), (11, 13));
      expect(state.joinedSpreadPairs, {11});
      expect((appdata.settings['readerSpreadOverrides'] as Map).values.single, {
        '11': 'pair',
      });
      Finder image(int n) => find.byKey(ValueKey('reader-spread-image-$n'));
      expect(
        tester.getRect(image(13)).right,
        closeTo(tester.getRect(image(12)).left, .1),
      );
      state.toNextPage();
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.page), (13, 15));
      state.toPrevPage();
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.page), (11, 13));
      appdata.settings['readerTwoPageSpread'] = false;
      state.update();
      await fixture.settle(tester);
      expect(state.page, 12);
      appdata.settings['readerTwoPageSpread'] = true;
      state.update();
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.page), (11, 13));
      final root = tester.widget<MaterialApp>(find.byType(MaterialApp));
      await closeReader(tester);
      await tester.pumpWidget(root);
      await fixture.settle(tester);
      state = tester.state(find.byType(Reader));
      expect(state.joinedSpreadPairs, {11});
      expect(state.imageLayout.range(state.page), (11, 13));
      final indices = <int>[
        for (var page = 1; page <= state.maxPage; page++)
          for (
            var i = state.imageLayout.range(page).$1;
            i < state.imageLayout.range(page).$2;
            i++
          )
            i,
      ];
      expect(indices, List.generate(19, (i) => i));
      state.setSpreadOverride(null);
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.imageLayout.pageForImage(12)), (
        10,
        12,
      ));
      expect(state.imageLayout.range(state.imageLayout.pageForImage(13)), (
        12,
        14,
      ));
      expect(appdata.settings['readerSpreadOverrides'], isEmpty);
      expect(tester.takeException(), isNull);
      await closeReader(tester);
    },
  );

  testWidgets(
    'pair selection can be cancelled and also works from a single last page',
    (tester) async {
      final dynamic state = await fixture.openReader(
        tester,
        'galleryRightToLeft',
        imageCount: 19,
        initialPage: 13,
      );
      appdata.settings['readerTwoPageSpread'] = true;
      state.update();
      await fixture.settle(tester);
      await tester.tapAt(const Offset(500, 300));
      await fixture.settle(tester);
      Future<void> openPicker() async {
        await tester.tap(find.byKey(const Key('reader-spread-options')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.ancestor(
            of: find.text('Choose two pages for a spread'.tl),
            matching: find.byType(CheckedPopupMenuItem<String>),
          ),
        );
        await fixture.settle(tester);
      }

      await openPicker();
      await tester.tap(find.byKey(const Key('reader-spread-pair-12')));
      await tester.pumpAndSettle();
      final left = find.byKey(const Key('reader-spread-preview-13'));
      final right = find.byKey(const Key('reader-spread-preview-12'));
      expect(
        tester.getRect(left).right,
        closeTo(tester.getRect(right).left, .1),
      );
      await tester.tap(find.byTooltip('Close'.tl));
      await tester.pumpAndSettle();
      expect(state.imageLayout.range(state.page), (12, 14));
      expect(appdata.settings['readerSpreadOverrides'], isEmpty);
      state.toPage(state.maxPage, animate: false);
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.page), (18, 19));
      await openPicker();
      expect(find.byKey(const Key('reader-spread-pair-18')), findsOneWidget);
      expect(find.byKey(const Key('reader-spread-pair-19')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('reader-spread-pair-confirm')),
      );
      await tester.tap(find.byKey(const Key('reader-spread-pair-confirm')));
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.page), (17, 19));
      expect(state.joinedSpreadPairs, {17});
      expect(tester.takeException(), isNull);
      await closeReader(tester);
    },
  );

  testWidgets(
    're-pairing replaces overlapping pairs and clears temporary shifts',
    (tester) async {
      final dynamic state = await fixture.openReader(
        tester,
        'galleryLeftToRight',
      );
      appdata.settings['readerTwoPageSpread'] = true;
      state.update();
      await fixture.settle(tester);
      state.setSpreadOverride('alignedPair', firstImage: 11);
      await fixture.settle(tester);
      state.setSpreadOverride('pair', firstImage: 13);
      await fixture.settle(tester);
      expect(state.joinedSpreadPairs, {10, 12});
      state.shiftImage(1);
      state.setSpreadOverride('pair', firstImage: 12);
      await fixture.settle(tester);
      expect(state.joinedSpreadPairs, {11});
      expect(state.alignedSpreadPairs, isEmpty);
      expect(state.imageGroupingAnchor, isNull);
      expect(state.imageGroupingOffset, 0);
      expect(state.imageLayout.range(state.page), (11, 13));
      state.setSpreadOverride('pair', firstImage: 30);
      state.setSpreadOverride('pair', firstImage: 0);
      expect(state.joinedSpreadPairs, {11});
      expect(tester.takeException(), isNull);
      await closeReader(tester);
    },
  );

  testWidgets(
    'Komiic spread keeps image 93 left and image 92 right independent of navigation',
    (tester) async {
      // The screenshots show screen 46 = images 91/92, screen 47 = 93/94.
      // The intended pair is 92/93; both are 980x1411 in a 193-image volume.
      final dynamic state = await fixture.openReader(
        tester,
        'galleryLeftToRight',
        imageCount: 193,
        initialPage: 92,
        useDefaultSpreadCover: true,
        useDefaultSpreadPageOrder: true,
        imageSizes: {92: const Size(980, 1411), 93: const Size(980, 1411)},
      );
      appdata.settings['readerTwoPageSpread'] = true;
      state.update();
      await fixture.settle(tester);

      expect(state.imageLayout.range(1), (0, 1));
      expect(state.imageLayout.range(state.page), (91, 93));
      expect(state.maxPage, 97);
      Finder image(int n) => find.byKey(ValueKey('reader-spread-image-$n'));
      final first = tester.getRect(image(92));
      final second = tester.getRect(image(93));
      expect(second.right, closeTo(first.left, 1));
      expect(first.height, closeTo(second.height, 1));

      state.mode = ReaderMode.galleryRightToLeft;
      state.update();
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.page), (91, 93));
      expect(
        tester.getRect(image(93)).right,
        closeTo(tester.getRect(image(92)).left, 1),
      );

      // Page order is a book preference; changing it leaves the current pair
      // and the navigation direction intact.
      final previousOrder = appdata.settings['readerSpreadRightToLeft'];
      addTearDown(() {
        appdata.settings['readerSpreadRightToLeft'] = previousOrder;
      });
      appdata.settings['readerSpreadRightToLeft'] = false;
      state.update();
      await fixture.settle(tester);
      expect(state.mode, ReaderMode.galleryRightToLeft);
      expect(state.imageLayout.range(state.page), (91, 93));
      expect(
        tester.getRect(image(92)).right,
        closeTo(tester.getRect(image(93)).left, 1),
      );
      appdata.settings['readerSpreadRightToLeft'] = previousOrder;
      state.update();
      await fixture.settle(tester);

      appdata.settings['readerTwoPageSpread'] = false;
      state.update();
      await fixture.settle(tester);
      expect(state.page, 92);
      appdata.settings['readerTwoPageSpread'] = true;
      state.update();
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.page), (91, 93));
      expect(
        tester.getRect(image(93)).right,
        closeTo(tester.getRect(image(92)).left, 1),
      );
      expect(appdata.settings['showSingleImageOnFirstPage'], isFalse);
      expect(tester.takeException(), isNull);
      await closeReader(tester);
    },
  );

  testWidgets(
    'book spreads align uneven pages, isolate wide images and retain progress',
    (tester) async {
      final dynamic state = await fixture.openReader(
        tester,
        'galleryLeftToRight',
        imageSizes: {
          9: const Size(300, 600),
          10: const Size(510, 600),
          11: const Size(1200, 600),
        },
      );
      appdata.settings['readerTwoPageSpread'] = true;
      state.update();
      await fixture.settle(tester);
      Finder image(int n) => find.byKey(ValueKey('reader-spread-image-$n'));
      final left = tester.getRect(image(9));
      final right = tester.getRect(image(10));
      expect(left.height, closeTo(right.height, 1));
      expect(left.top, closeTo(right.top, 1));
      expect(left.right, closeTo(right.left, 1));
      expect(left.width / left.height, closeTo(.5, .01));
      expect(right.width / right.height, closeTo(.85, .01));

      state.toPage(state.imageLayout.pageForImage(11), animate: false);
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.page), (10, 11));
      expect(tester.getSize(image(11)).width, greaterThan(right.width));
      tester.view.physicalSize = const Size(600, 1000);
      await fixture.settle(tester);
      expect(state.imageLayout.range(state.page), (10, 11));
      appdata.settings['readerTwoPageSpread'] = false;
      state.update();
      await fixture.settle(tester);
      expect(state.page, 11);
      expect(tester.takeException(), isNull);
      await closeReader(tester);
    },
  );

  testWidgets('manual cross-page marking persists and can be reset', (
    tester,
  ) async {
    dynamic state = await fixture.openReader(tester, 'galleryLeftToRight');
    appdata.settings['readerTwoPageSpread'] = true;
    state.update();
    await fixture.settle(tester);
    state.setSpreadOverride('pair');
    await fixture.settle(tester);
    final saved = appdata.settings['readerSpreadOverrides'] as Map;
    expect(saved.values.single, {'8': 'pair'});
    final root = tester.widget<MaterialApp>(find.byType(MaterialApp));
    await closeReader(tester);
    await tester.pumpWidget(root);
    await fixture.settle(tester);
    state = tester.state(find.byType(Reader));
    expect(state.joinedSpreadPairs, {8});
    state.shiftImage(1);
    await fixture.settle(tester);
    expect(state.imageLayout.range(state.page), (8, 10));
    state.setSpreadOverride(null);
    await fixture.settle(tester);
    expect(appdata.settings['readerSpreadOverrides'], isEmpty);
    expect(tester.takeException(), isNull);
    await closeReader(tester);
  });

  testWidgets('seam correction locks its pair, persists and can be disabled', (
    tester,
  ) async {
    dynamic state = await fixture.openReader(tester, 'galleryLeftToRight');
    appdata.settings['readerTwoPageSpread'] = true;
    state.update();
    await fixture.settle(tester);
    state.setSpreadOverride('alignedPair');
    await fixture.settle(tester);
    expect(state.alignedSpreadPairs, {8});
    expect(state.joinedSpreadPairs, {8});
    expect((appdata.settings['readerSpreadOverrides'] as Map).values.single, {
      '8': 'alignedPair',
    });
    final root = tester.widget<MaterialApp>(find.byType(MaterialApp));
    await closeReader(tester);
    await tester.pumpWidget(root);
    await fixture.settle(tester);
    state = tester.state(find.byType(Reader));
    expect(state.alignedSpreadPairs, {8});
    state.setSpreadOverride('pair');
    await fixture.settle(tester);
    expect(state.alignedSpreadPairs, isEmpty);
    expect(state.joinedSpreadPairs, {8});
    expect(state.imageLayout.range(state.page), (8, 10));
    expect(tester.takeException(), isNull);
    await closeReader(tester);
  });

  testWidgets('reset removes a forced-page override inside a regrouped pair', (
    tester,
  ) async {
    final dynamic state = await fixture.openReader(
      tester,
      'galleryLeftToRight',
      imageSizes: {10: const Size(1200, 600)},
    );
    appdata.settings['readerTwoPageSpread'] = true;
    state.update();
    await fixture.settle(tester);
    state.toPage(state.imageLayout.pageForImage(10), animate: false);
    await fixture.settle(tester);
    expect(state.imageLayout.range(state.page), (9, 10));
    state.setSpreadOverride('page');
    await fixture.settle(tester);
    expect(state.imageLayout.range(state.page), (8, 10));
    state.setSpreadOverride(null);
    await fixture.settle(tester);
    expect(state.imageLayout.range(state.imageLayout.pageForImage(10)), (
      9,
      10,
    ));
    expect(appdata.settings['readerSpreadOverrides'], isEmpty);
    expect(tester.takeException(), isNull);
    await closeReader(tester);
  });

  testWidgets(
    'double tap focuses the selected page and returns to the spread',
    (tester) async {
      final dynamic state = await fixture.openReader(
        tester,
        'galleryRightToLeft',
      );
      appdata.settings['readerTwoPageSpread'] = true;
      state.update();
      await fixture.settle(tester);
      final gallery = tester.widget<PhotoViewGallery>(
        find.byType(PhotoViewGallery),
      );
      final options = gallery.builder!(
        tester.element(find.byType(PhotoViewGallery)),
        state.page as int,
      );
      final controller = options.controller!;
      final initial = controller.getInitialScale!.call()!;
      final target = tester
          .getRect(find.byKey(const ValueKey('reader-spread-image-9')))
          .center;
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(target);
      await fixture.settle(tester);
      expect(controller.scale, greaterThan(initial * 1.2));
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(target);
      await fixture.settle(tester);
      expect(controller.scale, closeTo(initial, .01));
      expect(tester.takeException(), isNull);
      await closeReader(tester);
    },
  );
}
