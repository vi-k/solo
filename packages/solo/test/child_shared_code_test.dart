// `ctx.child` in `solo` from code that holds only a `JobContext`: the
// case it was made for. Kept apart from `child_factory_test.dart`, which
// reaches `SoloContext.child` and would not compile without it.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// Code that knows nothing of `solo`: a step of [milliseconds] with
/// a deadline of [limit].
Future<int> loadWithin(JobContext ctx, int milliseconds, Duration limit) =>
    ctx.run(
      ctx.child(
        key: 'step',
        timeout: limit,
        (ctx) async {
          await ctx.abandonable(() => delay(milliseconds));
          return 1;
        },
      ),
    );

/// Code that knows nothing of `solo`: a pause that [wake] cuts short.
/// Returns whether it was woken.
Future<bool> napOrWake(JobContext ctx, Duration nap, Future<void> wake) async {
  final child = ctx.child<void>((ctx) => ctx.pause(nap));
  unawaited(wake.then((_) => child.cancel().ignore()));
  try {
    await ctx.run(child);
    return false;
  } on Cancelled {
    // The job's own cancellation goes on up.
    ctx.check();
    return true;
  }
}

Matcher cancelledBy<T>() => isA<Cancelled>().having(
      (cancelled) => cancelled.reason,
      'reason',
      isA<T>(),
    );

void main() {
  group('code on JobContext inside a job of the controller', () {
    test('runs its child', () {
      runSolo((solo, journal, async) {
        final job = solo.enqueue<TestState, int>(
          key: 'job',
          (ctx) => loadWithin(ctx, 10, ms(100)),
        );
        async.flushTimers();
        expect(job.outcome, isA<Done<int>>());
        expect(journal.take(), [
          '[job] started',
          '> [step] started',
          '> [step] finished Done(1)',
          '[job] finished Done(1)',
        ]);
      });
    });

    test('gets the deadline of its step as Cancelled(timeout)', () {
      runSolo((solo, journal, async) {
        Object? caught;
        solo.enqueue<TestState, void>((ctx) async {
          try {
            await loadWithin(ctx, 50, ms(10));
          } on Cancelled catch (cancelled) {
            caught = cancelled;
          }
        });
        async.elapse(ms(9));
        expect(caught, isNull, reason: 'the deadline is 10 ms');
        async.elapse(ms(1));
        expect(caught, cancelledBy<TimeoutCancelReason>());
        final reason = (caught! as Cancelled).reason as TimeoutCancelReason;
        expect(reason.timeout, ms(10));
      });
    });
  });

  group('a deadline of a child of the controller', () {
    test('caught, it leaves the parent Done and the queue going', () {
      runSolo((solo, journal, async) {
        final cancelledParents = <Cancelled>[];
        final parent = solo.enqueue<TestState, int>(
          ifCancelled: (state, cancelled) {
            cancelledParents.add(cancelled);
            return state;
          },
          (ctx) async {
            try {
              return await loadWithin(ctx, 50, ms(10));
            } on Cancelled {
              return 0;
            }
          },
        );
        final next = solo.enqueue<TestState, void>((ctx) async {});
        async.flushTimers();
        expect(parent.outcome, isA<Done<int>>());
        expect(cancelledParents, isEmpty);
        expect(next.outcome, isA<Done<void>>());
      });
    });

    test('let out, it reaches ifCancelled of the parent', () {
      runSolo((solo, journal, async) {
        final cancelledParents = <Cancelled>[];
        final parent = solo.enqueue<TestState, int>(
          ifCancelled: (state, cancelled) {
            cancelledParents.add(cancelled);
            return state;
          },
          (ctx) => loadWithin(ctx, 50, ms(10)),
        )..ignoreFailure();
        final next = solo.enqueue<TestState, void>((ctx) async {});
        async.flushTimers();
        expect(parent.outcome, cancelledBy<HandlerCancelReason>());
        expect(cancelledParents, [cancelledBy<HandlerCancelReason>()]);
        expect(next.outcome, isA<Done<void>>());
      });
    });
  });

  group('a pause the code on JobContext wakes by cancelling its child', () {
    test('wakes early', () {
      runSolo((solo, journal, async) {
        final wake = Completer<void>();
        final job = solo.enqueue<TestState, bool>(
          (ctx) => napOrWake(ctx, const Duration(seconds: 5), wake.future),
        );
        async.elapse(ms(100));
        wake.complete();
        async.flushMicrotasks();
        expect((job.outcome! as Done<bool>).value, isTrue);
        expect(async.elapsed, ms(100));
      });
    });

    test('lets a cancellation of the parent through', () {
      runSolo((solo, journal, async) {
        final job = solo.enqueue<TestState, bool>(
          (ctx) => napOrWake(
            ctx,
            const Duration(seconds: 5),
            Completer<void>().future,
          ),
        )..ignoreFailure();
        async.elapse(ms(100));
        job.cancel().ignore();
        async.flushMicrotasks();
        expect(job.outcome, cancelledBy<ManualCancelReason>());
      });
    });
  });
}
