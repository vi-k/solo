@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';

void main() {
  test('the observer sees start, log, error and finish in order', () {
    fakeAsync((async) {
      final journal = JobJournal();
      Job<void>(
        key: 'job',
        observer: journal,
        (ctx) async {
          ctx.log('hello');
          throw StateError('boom');
        },
      ).ignore();
      async.flushMicrotasks();
      expect(journal.take(), [
        '[job] started',
        '[job] log hello',
        '[job] error Bad state: boom',
        '[job] finished Failed(Bad state: boom)',
      ]);
    });
  });

  test('a child without an observer inherits the parent one', () {
    fakeAsync((async) {
      final journal = JobJournal();
      Job<void>(
        key: 'parent',
        observer: journal,
        (ctx) async {
          await ctx.run(Job.deferred<void>(key: 'child', (ctx) async {}));
        },
      ).ignore();
      async.flushMicrotasks();
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        '> [child] finished Done(null)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  test('a hook that throws changes nothing', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<int>(
            key: 'job',
            observer: _ThrowingObserver(),
            (ctx) async => 42,
          );
          async.flushMicrotasks();
          expect(job.outcome, isA<Done<int>>());
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      ['Bad state: onStart', 'Bad state: onFinish'],
      reason: 'each hook is isolated on its own',
    );
  });

  test('log without an observer is a no-op', () {
    fakeAsync((async) {
      var conversions = 0;
      final job = Job<void>((ctx) async {
        ctx
          ..log('nobody listens')
          ..log(_Counted(() => conversions++))
          // Nothing makes a line out of it, so a `toString` of the
          // caller's that throws cannot end a job that only asked to log.
          ..log(_Unspeakable());
        await ctx.wait(() => delay(10));
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
      expect(conversions, 0, reason: 'nobody to hand the message to');
    });
  });

  test('the message reaches the observer as it was given', () {
    fakeAsync((async) {
      var conversions = 0;
      final heard = _Messages();
      final message = _Counted(() => conversions++);
      Job<void>(observer: heard, (ctx) async => ctx.log(message));
      async.flushMicrotasks();
      expect(heard.seen, hasLength(1));
      expect(identical(heard.seen.single, message), isTrue);
      expect(conversions, 0, reason: 'the line is the listener to make');
      expect('${heard.seen.single}', 'counted');
      expect(conversions, 1, reason: 'and it made one');
    });
  });
}

/// Keeps the messages as they came, without a word about them.
final class _Messages extends JobObserver {
  final seen = <Object?>[];

  @override
  void onLog(Job<Object?> job, Object? message) => seen.add(message);
}

/// Throws from every hook the engine calls.
final class _ThrowingObserver implements JobObserver {
  @override
  void onStart(Job<Object?> job) => throw StateError('onStart');

  @override
  void onFinish(Job<Object?> job) => throw StateError('onFinish');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      throw StateError('onError');

  @override
  void onLog(Job<Object?> job, Object? message) => throw StateError('onLog');
}

/// Counts every turn into a string, so a message nobody hears is visible.
class _Counted {
  _Counted(this._seen);

  final void Function() _seen;

  @override
  String toString() {
    _seen();
    return 'counted';
  }
}

/// A message that fails the moment somebody turns it into a string.
class _Unspeakable {
  @override
  String toString() => throw StateError('message conversion');
}
