@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/error_observer.dart';
import 'support/probe_job.dart';

void main() {
  test('the members are closed during the cleanup of a Done job', () {
    fakeAsync((async) {
      final errors = <Object>[];
      Job<int>(
        observer: ErrorObserver(errors),
        (ctx) async {
          // The outcome is `Done`: nothing marked the job, so without a
          // check of the phase every one of these would go through — `run`
          // would start a child after the children were waited for.
          ctx
            ..onDispose(() => ctx.run(Job.deferred<void>((ctx) async {})))
            ..onDispose(() => ctx.wait(() => delay(1)))
            ..onDispose(() => ctx.join(() => delay(1)))
            ..onDispose(() => ctx.uncancellable(() => delay(1)))
            ..onDispose(() => ctx.onCancel(() {}))
            ..onDispose(ctx.check);
          return 1;
        },
      ).ignore();
      async.flushTimers();
      expect(errors, hasLength(6));
      expect(errors.every((error) => error is StateError), isTrue);
      expect(
        errors.every((error) => '$error'.contains('is disposing')),
        isTrue,
        reason: 'the message names the cleanup, not a finished job',
      );
    });
  });

  test('registration and log stay open during the cleanup', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final order = <String>[];
      Job<int>(
        observer: ErrorObserver(errors),
        (ctx) async {
          ctx.onDispose(() {
            ctx
              ..onDispose(() => order.add('nested'))
              ..log('cleaning up');
            order.add('outer');
          });
          return 1;
        },
      ).ignore();
      async.flushTimers();
      expect(order, ['outer', 'nested']);
      expect(errors, isEmpty);
    });
  });

  test('a Cancelled thrown by a cleanup is its own error', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final job = Job<void>(
        observer: ErrorObserver(errors),
        (ctx) async {
          ctx.onDispose(
            () => throw Cancelled.by(
              reason: CancelReason.manual,
              started: true,
              stackTrace: StackTrace.current,
            ),
          );
          await ctx.wait(() => delay(10));
        },
      )..ignore();
      async.elapse(const Duration(milliseconds: 5));
      job.cancel().ignore();
      async.flushTimers();
      // Nothing is swallowed by identity any more: a cancellation thrown
      // by a disposer is an error of the disposer.
      expect(errors.single, isA<Cancelled>());
    });
  });

  test('a cancellation from a child inside a cleanup is its own error', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final job = Job<int>(
        observer: ErrorObserver(errors),
        (ctx) async {
          final child = ctx.run(
            Job.deferred<void>(
              key: 'child',
              (ctx) => ctx.wait(() => delay(100)),
            ),
          );
          ctx.onDispose(() async {
            // The disposer chose to wait for someone else's outcome: the
            // cascade took the child down, and its cancellation is an
            // error of this disposer.
            await child.value;
          });
          await ctx.wait(() => delay(50));
          return 1;
        },
      )..ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(errors.single, isA<Cancelled>());
    });
  });

  test('check stays legal after the job has finished', () {
    fakeAsync((async) {
      late JobContext leaked;
      final job = Job<void>((ctx) async {
        leaked = ctx;
        // A cleanup of its own, so the job really goes through the phase
        // that closes the context: without one the flag is never raised,
        // and this test would say nothing about it being lowered again.
        ctx.onDispose(() {});
      })
        ..ignore();
      async.flushTimers();
      expect(job.isFinished, isTrue);
      expect(leaked.check, returnsNormally);
      leaked.log('still legal');
    });
  });

  test('check throws the cancellation an engine finished the job with', () {
    fakeAsync((async) {
      late JobContext captured;
      final job = ProbeJob<void>((ctx) async {
        captured = ctx;
        await ctx.wait(() => delay(100));
      })
        ..launch();
      async.elapse(const Duration(milliseconds: 10));
      job.drop(
        Cancelled.by(
          reason: CancelReason.manual,
          started: true,
          stackTrace: StackTrace.current,
        ),
      );
      async.elapse(const Duration(milliseconds: 200));
      expect(captured.check, throwsA(isA<Cancelled>()));
    });
  });
  test('the job is still running while the engine cleans up after it', () {
    fakeAsync((async) {
      final marks = <bool>[];
      final job = Job<int>((ctx) async {
        ctx.onDispose(() async {
          marks.add(ctx.job.isRunning);
          await delay(10);
        });

        return 1;
      });
      async.flushTimers();
      expect(marks, [true]);
      expect(job.isRunning, isFalse);
    });
  });
}
