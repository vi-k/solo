@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  const second = Duration(seconds: 1);

  test('a pause nobody interrupts', () {
    fakeAsync((async) {
      final log = <String>[];
      final job = Job<void>((ctx) async {
        log.add('before');
        await ctx.pause(second);
        log.add('after');
      });
      async.elapse(const Duration(milliseconds: 999));
      expect(log, ['before']);
      async.elapse(const Duration(milliseconds: 1));
      expect(log, ['before', 'after']);
      expect(job.outcome, isA<Done<void>>());
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a cancellation halfway through a pause', () {
    fakeAsync((async) {
      Object? thrown;
      final job = Job<void>((ctx) async {
        try {
          await ctx.pause(second);
        } on Object catch (error) {
          thrown = error;
          rethrow;
        }
      });
      async.elapse(const Duration(milliseconds: 500));
      job.cancel().ignore();
      async.flushMicrotasks();
      expect(thrown, isA<Cancelled>());
      expect(job.outcome, isA<Cancelled>(), reason: 'not half a second later');
      expect(async.pendingTimers, isEmpty, reason: 'the timer went with it');
    });
  });

  test('the same wait written with Future.delayed leaves its timer', () {
    fakeAsync((async) {
      final job = Job<void>(
        (ctx) => ctx.wait(() => Future<void>.delayed(second)),
      );
      async.elapse(const Duration(milliseconds: 500));
      job.cancel().ignore();
      async.flushMicrotasks();
      expect(job.outcome, isA<Cancelled>());
      expect(async.pendingTimers, hasLength(1));
      async.flushTimers();
    });
  });

  test('a pause in a job cancelled already', () {
    fakeAsync((async) {
      Object? thrown;
      int? timersInTheCall;
      final job = Job<void>((ctx) async {
        await ctx.uncancellable(() async {});
        ctx.job.cancel().ignore();
        try {
          final paused = ctx.pause(second);
          timersInTheCall = async.pendingTimers.length;
          await paused;
        } on Object catch (error) {
          thrown = error;
          rethrow;
        }
      });
      async.flushMicrotasks();
      expect(thrown, isA<Cancelled>());
      expect(job.outcome, isA<Cancelled>());
      expect(timersInTheCall, 0, reason: 'no timer was made');
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a pause without a duration', () {
    fakeAsync((async) {
      final log = <String>[];
      final job = Job<void>((ctx) async {
        await ctx.pause();
        log.add('after');
      });
      async.flushMicrotasks();
      expect(log, isEmpty, reason: 'a timer, not a microtask');
      async.elapse(Duration.zero);
      expect(log, ['after']);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('a cancellation during a pause inside uncancellable', () {
    fakeAsync((async) {
      final log = <String>[];
      final job = Job<void>((ctx) async {
        await ctx.uncancellable(() async {
          await ctx.pause(second);
          log.add('the step is whole');
        });
        ctx.check();
        log.add('never');
      });
      async.elapse(const Duration(milliseconds: 500));
      job.cancel().ignore();
      async.flushMicrotasks();
      expect(job.isFinished, isFalse);
      async.elapse(const Duration(milliseconds: 500));
      expect(log, ['the step is whole']);
      expect(job.outcome, isA<Cancelled>());
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a cancellation after a pause that ran its course', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final job = runZonedGuarded(
        () => Job<void>((ctx) async {
          await ctx.pause(second);
          await ctx.wait(() => Completer<void>().future);
        }),
        (error, _) => errors.add(error),
      )!;
      async.elapse(second);
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(errors, isEmpty);
    });
  });

  test('a pause in a disposer', () {
    fakeAsync((async) {
      Object? thrown;
      Job<void>((ctx) async {
        ctx.onDispose(() async {
          try {
            await ctx.pause(second);
          } on Object catch (error) {
            thrown = error;
          }
        });
      });
      async.flushTimers();
      expect(thrown, isA<StateError>());
      expect('$thrown', contains('cannot pause'));
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a pause the body walked away from, in a job that ends Done', () {
    fakeAsync((async) {
      final job = Job<void>((ctx) async {
        unawaited(ctx.pause(second));
      });
      async.flushMicrotasks();
      expect(job.outcome, isA<Done<void>>());
      expect(async.pendingTimers, hasLength(1), reason: 'it runs to its end');
      async.flushTimers();
    });
  });

  test('a negative duration', () {
    fakeAsync((async) {
      final job = Job<void>((ctx) => ctx.pause(const Duration(seconds: -1)));
      async.flushMicrotasks();
      expect(job.isFinished, isFalse);
      async.elapse(Duration.zero);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('a pause in a callback of onCancel', () {
    fakeAsync((async) {
      Object? thrown;
      final job = Job<void>((ctx) async {
        ctx.onCancel(() {
          ctx.pause(second).then<void>(
            (_) {},
            onError: (Object error) {
              thrown = error;
            },
          );
        });
        await ctx.wait(() => Completer<void>().future);
      });
      async.flushMicrotasks();
      job.cancel().ignore();
      async.flushMicrotasks();
      expect(thrown, isA<Cancelled>());
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a pause in unattended work, cancelled', () {
    fakeAsync((async) {
      final log = <String>[];
      final job = Job<void>((ctx) async {
        ctx.unattended(() async {
          try {
            await ctx.pause(second);
            log.add('elapsed');
          } on Cancelled {
            log.add('cancelled');
          }
        });
        await ctx.wait(() => Completer<void>().future);
      });
      async.elapse(const Duration(milliseconds: 500));
      job.cancel().ignore();
      async.flushTimers();
      expect(log, ['cancelled']);
      expect(job.outcome, isA<Cancelled>());
      expect(async.pendingTimers, isEmpty);
    });
  });
}
