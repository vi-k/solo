@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

void main() {
  test('onDispose runs on every outcome', () {
    for (final scenario in ['done', 'failed', 'cancelled']) {
      fakeAsync((async) {
        final order = <String>[];
        final job = Job<int>((ctx) async {
          ctx.onDispose(() => order.add('disposed'));
          await ctx.wait(() => delay(10));
          if (scenario == 'failed') {
            throw StateError('boom');
          }
          return 1;
        })
          ..ignore();
        // Five milliseconds so the body starts and registers: a job
        // cancelled before that never runs its body at all.
        async.elapse(const Duration(milliseconds: 5));
        if (scenario == 'cancelled') {
          job.cancel().ignore();
        }
        async.flushTimers();
        expect(order, ['disposed'], reason: 'scenario: $scenario');
      });
    }
  });

  test('onDiscard is silent on Done and runs on the other two', () {
    for (final scenario in ['done', 'failed', 'cancelled']) {
      fakeAsync((async) {
        final order = <String>[];
        final job = Job<int>((ctx) async {
          ctx.onDiscard(() => order.add('discarded'));
          await ctx.wait(() => delay(10));
          if (scenario == 'failed') {
            throw StateError('boom');
          }
          return 1;
        })
          ..ignore();
        async.elapse(const Duration(milliseconds: 5));
        if (scenario == 'cancelled') {
          job.cancel().ignore();
        }
        async.flushTimers();
        expect(
          order,
          scenario == 'done' ? <String>[] : ['discarded'],
          reason: 'scenario: $scenario',
        );
      });
    }
  });

  test('the stack unwinds last in, first out', () {
    fakeAsync((async) {
      final order = <String>[];
      Job<void>((ctx) async {
        ctx
          ..onDispose(() => order.add('first'))
          ..onDiscard(() => order.add('second'))
          ..onDispose(() => order.add('third'));
        await ctx.wait(() => delay(10));
        throw StateError('boom');
      }).ignore();
      async.flushTimers();
      expect(order, ['third', 'second', 'first']);
    });
  });

  test('children run before the cleanup, and the outcome waits for it', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        ctx
          ..onDispose(() async {
            order.add('cleanup starts');
            await delay(50);
            order.add('cleanup ends');
          })
          ..run(
            Job.deferred<void>(
              key: 'child',
              (ctx) async {
                await ctx.wait(() => delay(30));
                order.add('child');
              },
            ),
          );
      });
      job.done.then((_) => order.add('finished')).ignore();
      async.flushTimers();
      expect(order, [
        'child',
        'cleanup starts',
        'cleanup ends',
        'finished',
      ]);
    });
  });

  test('an unregistered cleanup does not run, and dropping twice is safe', () {
    fakeAsync((async) {
      final order = <String>[];
      Job<void>((ctx) async {
        ctx.onDispose(() => order.add('kept'));
        final dropTwice = ctx.onDispose(() => order.add('dropped'))..call();
        dropTwice();
        await ctx.wait(() => delay(10));
      }).ignore();
      async.flushTimers();
      expect(order, ['kept']);
    });
  });

  test('a cleanup may register another one', () {
    fakeAsync((async) {
      final order = <String>[];
      Job<void>((ctx) async {
        ctx.onDispose(() {
          order.add('outer');
          ctx.onDispose(() => order.add('nested'));
        });
      }).ignore();
      async.flushTimers();
      expect(order, ['outer', 'nested']);
    });
  });

  test('an error of a cleanup goes to the observer and the rest still runs',
      () {
    fakeAsync((async) {
      final errors = <Object>[];
      final order = <String>[];
      final job = Job<int>(
        observer: _CollectingObserver(errors),
        (ctx) async {
          ctx
            ..onDispose(() => order.add('below'))
            ..onDispose(() => throw StateError('cleanup failed'));
          return 7;
        },
      );
      async.flushTimers();
      expect(order, ['below']);
      expect(errors.single, isA<StateError>());
      expect(job.outcome, isA<Done<int>>());
    });
  });

  test('a cancellation arriving during the cleanup still discards', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<int>((ctx) async {
        // The order of the two registrations is the point of this test:
        // the `discard` sits above the slow `dispose`, so it is taken off
        // first, skipped while the outcome is `Done`, and only the second
        // pass can bring it back.
        ctx
          ..onDispose(() async {
            order.add('slow starts');
            await delay(100);
            order.add('slow ends');
          })
          ..onDiscard(() => order.add('discarded'));
        return 7;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 50));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['slow starts', 'slow ends', 'discarded']);
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('registering stays open on a job already cancelled', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        try {
          await ctx.wait(() => delay(50));
        } on Cancelled {
          // The body is unwinding: registering a cleanup here has to work,
          // or the trap this whole mechanism removes is back.
          ctx.onDispose(() => order.add('registered while cancelled'));
          rethrow;
        }
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['registered while cancelled']);
    });
  });

  test('registering on a job that has finished is a StateError', () {
    fakeAsync((async) {
      late JobContext leaked;
      Job<void>((ctx) async => leaked = ctx).ignore();
      async.flushTimers();
      expect(() => leaked.onDispose(() {}), throwsStateError);
    });
  });
  test('isCancelled tells the truth inside a cleanup', () {
    fakeAsync((async) {
      final seen = <bool>[];
      Job<void>((ctx) async {
        ctx.onDispose(() => seen.add(ctx.job.isCancelled));
        await ctx.wait(() => delay(10));
        // The body throws the cancellation itself: nothing marked the job,
        // and until now `isCancelled` lied about it during the cleanup.
        throw Cancelled.by(
          reason: CancelReason.manual,
          started: true,
          stackTrace: StackTrace.current,
        );
      }).ignore();
      async.flushTimers();
      expect(seen, [true]);
    });
  });

  test('whenCancelled closes before the cleanup ends', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        ctx.onDispose(() async {
          order.add('cleanup starts');
          await delay(50);
          order.add('cleanup ends');
        });
        await ctx.wait(() => delay(10));
        throw Cancelled.by(
          reason: CancelReason.manual,
          started: true,
          stackTrace: StackTrace.current,
        );
      })
        ..ignore();
      job.whenCancelled.then((_) => order.add('whenCancelled')).ignore();
      async.flushTimers();
      // The listener of `whenCancelled` runs as a microtask, so its line
      // lands inside the asynchronous disposer rather than before it; what
      // matters is that it no longer waits for `finish`.
      expect(order, ['cleanup starts', 'whenCancelled', 'cleanup ends']);
    });
  });

  test('a wait the body walked away from gets no error of its own', () {
    fakeAsync((async) {
      final errors = <Object>[];
      Job<void>(
        observer: _CollectingObserver(errors),
        (ctx) async {
          // The body walks away from its own wait and throws the
          // cancellation itself: filling `_pendingCancel` must not run the
          // callbacks of the race.
          unawaited(ctx.wait(() => delay(50)));
          await ctx.wait(() => delay(10));
          throw Cancelled.by(
            reason: CancelReason.manual,
            started: true,
            stackTrace: StackTrace.current,
          );
        },
      ).ignore();
      async.flushTimers();
      expect(errors, isEmpty);
    });
  });

  test('cancelling a parent that waits for children still cascades', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        ctx.run(
          Job.deferred<void>(
            key: 'child',
            (ctx) async {
              ctx.onCancel(() => order.add('child cancelled'));
              await ctx.wait(() => delay(100));
            },
          ),
        );
        await ctx.wait(() => delay(10));
        // The body ended with a cancellation of its own while the children
        // are still running: an outside `cancel()` has to reach the child.
        throw Cancelled.by(
          reason: CancelReason.manual,
          started: true,
          stackTrace: StackTrace.current,
        );
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 30));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['child cancelled']);
    });
  });

  test('a section the body walked away from holds the cancellation', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<int>((ctx) async {
        ctx.onDiscard(() => order.add('discarded'));
        // A mistake of the body: the section was never awaited, so its
        // depth stays above zero. The engine does not fix that — this test
        // pins that the held cancellation never reaches the cleanup and
        // `Done` goes to whoever cancelled.
        unawaited(ctx.uncancellable(() => delay(100)));
        await ctx.wait(() => delay(10));
        return 1;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 20));
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      expect(order, isEmpty);
    });
  });
}

class _CollectingObserver extends JobObserver {
  _CollectingObserver(this.errors);

  final List<Object> errors;

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add(error);
}
