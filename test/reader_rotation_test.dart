import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/reader_rotation.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/reader_orientation.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/reader/reader.dart';
import 'package:venera/utils/data_sync.dart';
import 'package:venera/utils/translations.dart';

import 'reader_page_margin_test.dart' as fixture;
import 'support/test_translations.dart';

class _NoDataSync extends Fake implements DataSync {
  @override
  void onDataChanged() {}
  @override
  Future<Res<bool>> uploadData({bool force = false}) async => const Res(true);
}

void main() {
  DataSync? previousSync;
  Object? previousDefault;
  setUp(() {
    previousSync = DataSync.instance;
    DataSync.instance = _NoDataSync();
    previousDefault = appdata.settings[ReaderRotationPreference.settingKey];
    appdata.settings[ReaderRotationPreference.settingKey] = 'none';
  });
  tearDown(() {
    DataSync.instance = previousSync;
    appdata.settings[ReaderRotationPreference.settingKey] = previousDefault;
  });

  test('quarter turns rotate safe areas, keyboard and folding feature', () {
    const screen = Size(600, 800);
    const data = MediaQueryData(
      size: screen,
      padding: EdgeInsets.fromLTRB(1, 2, 3, 4),
      viewPadding: EdgeInsets.fromLTRB(5, 6, 7, 8),
      viewInsets: EdgeInsets.only(bottom: 250),
      systemGestureInsets: EdgeInsets.only(left: 12, right: 16),
      displayFeatures: [
        DisplayFeature(
          bounds: Rect.fromLTWH(298, 0, 4, 800),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureFlat,
        ),
      ],
    );
    final left = ReaderRotation.left.mediaQuery(data, screen);
    expect(left.size, const Size(800, 600));
    expect(left.padding, const EdgeInsets.fromLTRB(4, 1, 2, 3));
    expect(left.viewPadding, const EdgeInsets.fromLTRB(8, 5, 6, 7));
    expect(left.viewInsets, const EdgeInsets.only(left: 250));
    expect(
      left.systemGestureInsets,
      const EdgeInsets.only(top: 12, bottom: 16),
    );
    expect(
      left.displayFeatures.single.bounds,
      const Rect.fromLTWH(0, 298, 800, 4),
    );
    final right = ReaderRotation.right.mediaQuery(data, screen);
    expect(right.padding, const EdgeInsets.fromLTRB(2, 3, 4, 1));
    expect(right.viewInsets, const EdgeInsets.only(right: 250));
    expect(
      right.systemGestureInsets,
      const EdgeInsets.only(top: 16, bottom: 12),
    );
    expect(
      right.displayFeatures.single.bounds,
      const Rect.fromLTWH(0, 298, 800, 4),
    );
    expect(ReaderRotation.normal.mediaQuery(data, screen), data);
    expect(ReaderRotation.fromStorage('landscape'), isNull);
    expect(ReaderRotationPreference.initial, ReaderRotation.normal);
  });

  testWidgets(
    'spread options have one text column with and without checkmarks',
    (tester) async {
      final dynamic reader = await fixture.openReader(
        tester,
        'galleryLeftToRight',
      );
      appdata.settings['readerTwoPageSpread'] = true;
      reader.update();
      await fixture.settle(tester);
      await tester.tapAt(const Offset(500, 300));
      await fixture.settle(tester);
      Future<void> checkAlignment() async {
        await tester.tap(find.byKey(const Key('reader-spread-options')));
        await tester.pumpAndSettle();
        final labels = [
          'Choose two pages for a spread',
          'Align this spread seam',
          'Reset spread layout',
        ];
        final lefts = [
          for (final label in labels) tester.getTopLeft(find.text(label.tl)).dx,
        ];
        expect(lefts[0], closeTo(lefts[1], .1));
        expect(lefts[0], closeTo(lefts[2], .1));
      }

      await checkAlignment();
      await tester.tap(
        find.ancestor(
          of: find.text('Choose two pages for a spread'.tl),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      await fixture.settle(tester);
      await tester.ensureVisible(
        find.byKey(const Key('reader-spread-pair-confirm')),
      );
      await tester.tap(find.byKey(const Key('reader-spread-pair-confirm')));
      await fixture.settle(tester);
      await checkAlignment();
      expect(find.byIcon(Icons.done), findsOneWidget);
      await tester.tap(
        find.ancestor(
          of: find.text('Reset spread layout'.tl),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      await fixture.settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      await fixture.settle(tester);
    },
  );

  testWidgets(
    'rotation preserves the reader, transforms taps and pins only explicitly',
    (tester) async {
      final dynamic reader = await fixture.openReader(
        tester,
        'galleryLeftToRight',
      );
      final images = reader.images;
      final page = reader.page;
      final viewportSize = tester.getSize(find.byType(Reader));
      await tester.tapAt(const Offset(500, 300));
      await fixture.settle(tester);
      await tester.tap(find.byKey(const Key('reader-rotation-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderRotationPanel), findsOneWidget);
      expect(find.byKey(const Key('reader-rotation-inverted')), findsNothing);
      await tester.tap(find.byKey(const Key('reader-rotation-left')));
      await tester.pumpAndSettle();
      expect(reader.rotation.value, ReaderRotation.left);
      expect(reader.size, Size(viewportSize.height, viewportSize.width));
      expect(reader.isPortrait, isTrue);
      expect(reader.page, page);
      expect(identical(reader.images, images), isTrue);
      expect(ReaderRotationPreference.pinned, isNull);
      await tester.tap(find.byKey(const Key('reader-rotation-pin')));
      await fixture.settle(tester);
      expect(ReaderRotationPreference.pinned, ReaderRotation.left);
      for (var attempt = 0; attempt < 10; attempt++) {
        final exists = await tester.runAsync(
          () => File('${App.dataPath}/appdata.json').exists(),
        );
        if (exists == true) break;
        await fixture.settle(tester);
      }
      final saved = await tester.runAsync(
        () async => jsonDecode(
          await File('${App.dataPath}/appdata.json').readAsString(),
        ),
      );
      expect(saved['settings'][ReaderRotationPreference.settingKey], 'left');
      await tester.tap(find.text('Close'.tl));
      await tester.pumpAndSettle();
      final navigator = find
          .descendant(
            of: find.byType(ReaderRotationViewport),
            matching: find.byType(Navigator),
          )
          .first;
      final box = tester.renderObject<RenderBox>(navigator);
      await tester.tapAt(box.localToGlobal(const Offset(300, 500)));
      await fixture.settle(tester);
      // Logical right edge is the physical top edge after a left quarter turn.
      await tester.tapAt(box.localToGlobal(const Offset(530, 500)));
      await fixture.settle(tester);
      expect(reader.page, page + 1);
      // Flutter also transforms native drag hit tests into the new reading axes.
      await tester.dragFrom(
        box.localToGlobal(const Offset(450, 500)),
        const Offset(0, 500),
      );
      await fixture.settle(tester);
      expect(reader.page, page + 2);
      final widget = tester.widget<Reader>(find.byType(Reader));
      App.rootNavigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => widget),
      );
      await fixture.settle(tester);
      final dynamic reopened = tester.state(find.byType(Reader));
      expect(reopened.rotation.value, ReaderRotation.left);
      reopened.setRotation(ReaderRotation.right);
      await fixture.settle(tester);
      expect(ReaderRotationPreference.pinned, ReaderRotation.left);
      await tester.tapAt(const Offset(500, 300));
      await fixture.settle(tester);
      await tester.tap(find.byKey(const Key('reader-rotation-toggle')));
      await tester.pumpAndSettle();
      // Back dismisses the rotated panel first; the next back exits the reader.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderRotationPanel), findsNothing);
      expect(tester.state(find.byType(Reader)), same(reopened));
      await tester.binding.handlePopRoute();
      await fixture.settle(tester);
      expect(tester.state(find.byType(Reader)), same(reader));
      expect(reader.rotation.value, ReaderRotation.left);
      await tester.runAsync(() => ReaderRotationPreference.pin(null));
      expect(ReaderRotationPreference.initial, ReaderRotation.normal);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      await fixture.settle(tester);
    },
  );

  testWidgets(
    'direction panel remains usable on a short screen with large text',
    (tester) async {
      await ensureTestTranslations();
      tester.view.physicalSize = const Size(600, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ReaderRotationPanel(
              rotation: ReaderRotation.normal,
              pinned: null,
              onChanged: (_) {},
              onPinChanged: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('reader-rotation-pin')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
