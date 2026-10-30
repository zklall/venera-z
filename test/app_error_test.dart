import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/res.dart';
import 'support/test_translations.dart';

class _LoadFixture extends StatefulWidget {
  const _LoadFixture(this.failure, this.called, {this.throwInstead = false});
  final String failure;
  final VoidCallback called;
  final bool throwInstead;
  @override
  State<_LoadFixture> createState() => _LoadFixtureState();
}

class _LoadFixtureState extends LoadingState<_LoadFixture, String> {
  @override
  Future<Res<String>> loadData() async {
    widget.called();
    if (widget.throwInstead) throw StateError(widget.failure);
    return Res.error(widget.failure);
  }

  @override
  Widget buildContent(BuildContext context, String data) => Text(data);
}

void main() {
  setUpAll(ensureTestTranslations);
  setUp(() => appdata.settings['language'] = 'en-US');
  test(
    'HTTP failures provide recovery advice without inventing site policy',
    () {
      for (final code in [210, 401, 402, 403, 404, 429, 500, 503]) {
        final typed = AppErrorInfo.from(
          DioException(
            requestOptions: RequestOptions(path: '/comic'),
            response: Response(
              requestOptions: RequestOptions(path: '/comic'),
              statusCode: code,
            ),
          ),
        );
        final string = AppErrorInfo.from('Invalid Status Code: $code');
        expect(typed.title, string.title);
        expect(typed.message, isNot(contains('$code')));
        expect(typed.canAutoRetry, isFalse);
      }
      expect(
        AppErrorInfo.from('Invalid status code: 210').message,
        isNot(contains('40')),
      );
      expect(
        AppErrorInfo.from('Invalid status code: 402').message,
        isNot(contains('pay')),
      );
      expect(
        AppErrorInfo.from('SocketException: failed host lookup').canAutoRetry,
        isTrue,
      );
      expect(
        AppErrorInfo.from('https://example.org/book/402').title,
        'Operation could not be completed',
      );
    },
  );
  test(
    'local file, source and sync errors have distinct actionable messages',
    () {
      expect(
        AppErrorInfo.from('FileSystemException: No space left on device').title,
        'Not enough storage',
      );
      expect(
        AppErrorInfo.from('FileSystemException: Permission denied').title,
        'Cannot access this folder',
      );
      expect(
        AppErrorInfo.from(
          'TypeError: cannot read property name of undefined',
        ).title,
        'The source could not read the website data',
      );
      expect(
        AppErrorInfo.from('key(Komiic) already exists').message,
        contains('Switch source library'),
      );
      expect(
        AppErrorInfo.from('Invalid WebDAV configuration').message,
        contains('WebDAV'),
      );
      expect(
        AppErrorInfo.from('FormatException: Update checksum mismatch').message,
        contains('APK'),
      );
      expect(
        AppErrorInfo.from('PlatformException(secret internal stack)').message,
        isNot(contains('secret')),
      );
    },
  );
  testWidgets('raw error is hidden until diagnostic details are expanded', (
    tester,
  ) async {
    const raw =
        'TypeError: cannot read property name of undefined\nat loadInfo (CopyManga:717:35)';
    var retries = 0;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkError(
          message: raw,
          withAppbar: false,
          retry: () => retries++,
        ),
      ),
    );
    expect(find.text(raw), findsNothing);
    expect(
      find.text('The source could not read the website data'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    await tester.tap(find.text('Diagnostic details'));
    await tester.pumpAndSettle();
    expect(find.text(raw), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'verification keeps a working Verify entry instead of generic Retry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkError(
            message: 'CloudflareException: https://example.test/chapter',
            withAppbar: false,
            retry: () {},
          ),
        ),
      );
      expect(find.text('Verify'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('https://'), findsNothing);
    },
  );
  testWidgets(
    'unexpected thrown failure exits loading and keeps diagnostics hidden',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: _LoadFixture(
            'internal diagnostic',
            () => calls++,
            throwInstead: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Operation could not be completed'), findsOneWidget);
      expect(find.textContaining('internal diagnostic'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'large text can scroll to recovery and diagnostics on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
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
          home: NetworkError(
            message: 'Invalid status code: 402',
            withAppbar: false,
            retry: () {},
          ),
        ),
      );
      await tester.ensureVisible(find.text('Retry'));
      await tester.ensureVisible(find.text('Diagnostic details'));
      await tester.tap(find.text('Diagnostic details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Export logs'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('disposing during a network retry stops further requests', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: _LoadFixture(
          'SocketException: failed host lookup',
          () => calls++,
        ),
      ),
    );
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
  for (final error in [
    'Invalid status code: 210',
    'Invalid Status Code: 402',
    'CloudflareException: https://example.test',
    'Login expired',
    'TypeError: cannot read property name of undefined',
  ]) {
    testWidgets('does not rapidly retry $error', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(home: _LoadFixture(error, () => calls++)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
