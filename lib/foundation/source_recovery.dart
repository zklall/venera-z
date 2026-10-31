import 'dart:async';

import 'app_error.dart';

/// Shares device resets across concurrent requests, but retries each request once.
class SourceRecovery {
  SourceRecovery({DateTime Function()? now}) : _now = now ?? DateTime.now;
  static final instance = SourceRecovery();
  final DateTime Function() _now;
  final _pending = <String, Future<bool>>{};
  final _successful = <String, bool>{};
  final _lastReset = <String, DateTime>{};

  DateTime? generation(String key) => _lastReset[key];

  static bool isDeviceRestriction(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('cloudflare') || text.contains('login expired')) {
      return false;
    }
    return AppErrorInfo.statusCode(error) == 402 ||
        text.contains('设备风控') ||
        text.contains('device blocked');
  }

  Future<bool> recover(
    String key,
    Object error,
    Future<bool> Function() reset, {
    DateTime? startedWith,
  }) {
    if (!isDeviceRestriction(error)) return Future.value(false);
    final pending = _pending[key];
    if (pending != null) return pending;
    final last = _lastReset[key];
    if (last != null && last != startedWith) {
      return Future.value(_successful[key] == true);
    }
    // New failures during the cooldown do not trigger another reset.
    if (last != null && _now().difference(last) < const Duration(minutes: 1)) {
      return Future.value(false);
    }
    final task = Future<bool>.sync(reset).then((value) {
      _successful[key] = value;
      return value;
    }, onError: (Object _, StackTrace __) => false);
    _successful[key] = false;
    _lastReset[key] = _now();
    _pending[key] = task;
    return task.whenComplete(() => _pending.remove(key));
  }

  Future<T> run<T>(
    String key,
    Future<T> Function() request,
    Future<bool> Function() reset,
  ) async {
    final startedWith = generation(key);
    try {
      return await request();
    } catch (error) {
      if (!await recover(key, error, reset, startedWith: startedWith)) rethrow;
      return request();
    }
  }
}
