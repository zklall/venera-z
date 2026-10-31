import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/pages/reader/reader.dart';
import 'support/test_translations.dart';

class RestrictedImage extends ImageProvider<RestrictedImage> {
  const RestrictedImage();
  @override
  Future<RestrictedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    RestrictedImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Future.error('Invalid Status Code: 402'));
}

void main() {
  testWidgets(
    'reader keeps raw image failure collapsed and uses simplified Chinese',
    (tester) async {
      await ensureTestTranslations();
      appdata.settings['language'] = 'zh-CN';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: ComicImage(image: const RestrictedImage())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('网站限制了内容访问'), findsOneWidget);
      expect(find.text('Invalid Status Code: 402'), findsNothing);
      await tester.tap(find.text('诊断详情'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid Status Code: 402'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
