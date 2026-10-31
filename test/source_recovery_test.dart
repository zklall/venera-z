import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/source_recovery.dart';
import 'package:venera/foundation/app_error.dart';

void main() {
  test('402 resets before rebuilding the request and retries once', () async {
    final recovery = SourceRecovery();
    var identity = 'old';
    final used = <String>[];
    final result = await recovery.run(
      'copy',
      () async {
        used.add(identity);
        if (identity == 'old') throw 'HTTP 402';
        return 'ok';
      },
      () async {
        identity = 'new';
        return true;
      },
    );
    expect(result, 'ok');
    expect(used, ['old', 'new']);
  });
  test('persistent restriction stops after one retry', () async {
    var requests = 0, resets = 0;
    await expectLater(
      SourceRecovery().run(
        'copy',
        () async {
          requests++;
          throw 'Invalid Status Code: 402';
        },
        () async {
          resets++;
          return true;
        },
      ),
      throwsA('Invalid Status Code: 402'),
    );
    expect(requests, 2);
    expect(resets, 1);
  });
  test('concurrent failures share reset, cooldown stops new resets', () async {
    final recovery = SourceRecovery();
    final gate = Completer<bool>();
    var resets = 0;
    Future<bool> reset() {
      resets++;
      return gate.future;
    }

    final a = recovery.recover('copy', '402', reset);
    final b = recovery.recover('copy', '402', reset);
    gate.complete(true);
    expect(await a, isTrue);
    expect(await b, isTrue);
    expect(resets, 1);
    expect(
      await recovery.recover(
        'copy',
        '402',
        reset,
        startedWith: recovery.generation('copy'),
      ),
      isFalse,
    );
    expect(resets, 1);
  });
  test('failed or absent action keeps original error', () async {
    for (final throws in [false, true]) {
      var calls = 0;
      await expectLater(
        SourceRecovery().run(
          'copy',
          () async {
            calls++;
            throw 'HTTP 402';
          },
          () async {
            if (throws) throw StateError('reset failed');
            return false;
          },
        ),
        throwsA('HTTP 402'),
      );
      expect(calls, 1);
    }
  });
  test(
    'does not clear for authentication, verification or rate limits',
    () async {
      for (final error in [
        'HTTP 401',
        'HTTP 403',
        'HTTP 429',
        'CloudflareException: HTTP 402',
        'Login expired',
      ]) {
        var resets = 0;
        expect(
          await SourceRecovery().recover('copy', error, () async {
            resets++;
            return true;
          }),
          isFalse,
        );
        expect(resets, 0);
      }
    },
  );
  test('status strings are readable errors, page numbers are not', () {
    for (final text in [
      '402',
      'HTTP 402',
      'status code 402',
      'statusCode:402',
    ]) {
      expect(
        AppErrorInfo.from(text).titleKey,
        'Access restricted by the website',
      );
      expect(AppErrorInfo.isTechnical(text), isTrue);
    }
    expect(AppErrorInfo.statusCode('https://example.com/book/402'), isNull);
  });
}
