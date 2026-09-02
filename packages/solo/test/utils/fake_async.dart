import 'package:fake_async/fake_async.dart';

import 'duration_utils.dart';

class FutureResult<T> {
  var _isDone = false;
  T? _result;
  Object? _error;
  late final StackTrace _stackTrace;

  bool get isDone => _isDone;

  bool get isFailed => _error != null;

  T get result {
    if (!_isDone) {
      throw StateError('No result');
    }

    if (_error != null) {
      Error.throwWithStackTrace(_error!, _stackTrace);
    }

    return _result as T;
  }

  dynamic get resultOrError =>
      _isDone ? _error ?? _result : StateError('No result');

  void setResult(T value) {
    _result = value;
    _isDone = true;
  }

  void setError(Object error, StackTrace stackTrace) {
    _error = error;
    _stackTrace = stackTrace;
    _isDone = true;
  }
}

extension FakeAsyncExtension on FakeAsync {
  bool flushNextTimer({bool Function(FakeTimer timer)? test}) {
    flushMicrotasks();

    if (pendingTimers.isEmpty) {
      return false;
    }

    try {
      final timer = pendingTimers[0];
      final flush = test == null || test(timer);

      if (!flush) {
        return false;
      }

      flushTimers(
        flushPeriodicTimers: false,
        timeout: timer.duration,
      );

      // ignore: avoid_catching_errors
    } on StateError catch (e, s) {
      if (!e.message.startsWith('Exceeded timeout ')) {
        Error.throwWithStackTrace(e, s);
      }
    }

    return true;
  }

  /// Обработать текущий event-loop (таймеры с длительностью 0).
  int handleEventLoop() {
    flushMicrotasks();

    var count = 0;

    // Во время обработки таймеров их количество может увеличиваться, поэтому
    // фиксируем их количество.
    for (final timer in pendingTimers) {
      if (!timer.duration.isZero) {
        break;
      }

      count++;
    }

    for (var i = 0; i < count; i++) {
      flushNextTimer();
    }

    return count;
  }

  void printPendingTimers() {
    print(pendingTimers.map((e) => e.duration).toList());
  }

  void _handleFuture<T>(
    Future<T> future,
    FutureResult<T> result,
  ) {
    Future(() async {
      try {
        result.setResult(await future);
      } on Object catch (e, s) {
        result.setError(e, s);
      }
    });
  }

  void _waitFutureResult<T>(FutureResult<T> result) {
    while (!result.isDone) {
      if (!flushNextTimer()) {
        throw StateError('No timers');
      }
    }
  }

  /// Запустить фьючу. Результат будет возвращён внутри FutureResult.
  FutureResult<T> startFuture<T>(Future<T> future) {
    final result = FutureResult<T>();

    _handleFuture<T>(future, result);

    return result;
  }

  T waitFutureResult<T>(
    Future<T> future, [
    Duration? duration,
  ]) {
    final result = FutureResult<T>();

    _handleFuture<T>(future, result);

    if (duration == null) {
      _waitFutureResult<T>(result);
    } else {
      elapse(duration);
    }

    return result.result;
  }

  dynamic waitFuture<T>(
    Future<T> future, [
    Duration? duration,
  ]) {
    final result = FutureResult<T>();

    _handleFuture<T>(future, result);

    if (duration == null) {
      _waitFutureResult<T>(result);
    } else {
      elapse(duration);
    }

    return result.resultOrError;
  }
}
