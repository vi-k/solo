@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
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
          await ctx.run(Job.deferred<void>(key: 'child', (ctx) async {})).done;
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
      final job = Job<void>((ctx) async {
        ctx.log('nobody listens');
        await ctx.wait(() => delay(10));
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
    });
  });
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
  void onLog(Job<Object?> job, String message) => throw StateError('onLog');
}
