// The deadline of a job of a controller: `timeout` on `job`, `run`,
// `collect` and `accumulate`.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// Far enough that no test reaches it.
const hour = Duration(hours: 1);

/// The text of the [ArgumentError] [action] throws.
String argumentErrorOf(void Function() action) {
  Object? thrown;
  try {
    action();
  } on Object catch (error) {
    thrown = error;
  }
  expect(thrown, isA<ArgumentError>());
  return '$thrown';
}

/// Adds an event from a frame of its own, so the trace of the deadline can
/// be told to lead here.
SoloJob<void> addAnEvent(SoloAccumulator<int, void> accumulator) =>
    accumulator.add(1);

void main() {
  group('a deadline no job may have', () {
    for (final (name, timeout, cancellable) in [
      ('zero', Duration.zero, true),
      ('negative', ms(-1), true),
      ('with cancellable: false', ms(10), false),
    ]) {
      test(name, () {
        runSolo((solo, journal, async) {
          final core = argumentErrorOf(
            () => Job.deferred<void>(
              cancellable: cancellable,
              timeout: timeout,
              (ctx) async {},
            ),
          );
          expect(
            argumentErrorOf(
              () => solo.job<TestState, void>(
                cancellable: cancellable,
                timeout: timeout,
                (ctx) async {},
              ),
            ),
            core,
          );
          expect(
            argumentErrorOf(
              () => solo.run<TestState, void>(
                cancellable: cancellable,
                timeout: timeout,
                (ctx) async {},
              ),
            ),
            core,
          );
          expect(solo.pending, isNull, reason: 'nothing was queued');
          // At the call, before any event: the jobs are made on `add`.
          expect(
            argumentErrorOf(
              () => solo.collect<TestState, int, void>(
                cancellable: cancellable,
                timeout: timeout,
                (ctx, events) async {},
              ),
            ),
            core,
          );
          expect(
            argumentErrorOf(
              () => solo.accumulate<TestState, int, void>(
                merge: (accumulated, incoming) => accumulated + incoming,
                cancellable: cancellable,
                timeout: timeout,
                (ctx, value) async {},
              ),
            ),
            core,
          );
        });
      });
    }
  });

  test('a job made by job and added', () {
    runSolo((solo, journal, async) {
      final job = solo.add(
        solo.job<TestState, void>(
          key: 'load',
          timeout: ms(10),
          (ctx) => pause(ctx, 50),
        ),
      );
      async.elapse(ms(100));
      expect('${job.outcome}', 'Cancelled(timeout)');
    });
  });

  test('the trace of a deadline of an accumulated job', () {
    runSolo((solo, journal, async) {
      final accumulator = solo.collect<TestState, int, void>(
        key: 'save',
        timeout: ms(10),
        (ctx, events) => pause(ctx, 50),
      );
      final job = addAnEvent(accumulator);
      async.elapse(ms(100));
      final outcome = job.outcome! as Cancelled;
      expect('$outcome', 'Cancelled(timeout)');
      expect('${outcome.stackTrace}', contains('addAnEvent'));
      expect('${outcome.stackTrace}', contains('_SoloAccumulator.add'));
    });
  });

  test('a deadline of an accumulated job running out', () {
    runSolo((solo, journal, async) {
      final accumulator = solo.accumulate<TestState, int, void>(
        key: 'sum',
        merge: (accumulated, incoming) => accumulated + incoming,
        timeout: ms(10),
        (ctx, value) => pause(ctx, 50),
      );
      final job = accumulator.add(1);
      async.elapse(ms(100));
      expect('${job.outcome}', 'Cancelled(timeout)');
    });
  });

  test('a job waiting in the queue longer than its deadline', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'first', (ctx) => pause(ctx, 50));
      final second = solo.run<TestState, int>(
        key: 'second',
        timeout: ms(20),
        (ctx) async {
          await pause(ctx, 15);
          return 2;
        },
      );
      async.elapse(ms(100));
      expect((second.outcome! as Done<int>).value, 2);
    });
  });

  test('an accumulated job waiting out its window', () {
    runSolo((solo, journal, async) {
      final accumulator = solo.collect<TestState, int, int>(
        key: 'save',
        timing: AccumulationTiming.debounce(ms(50)),
        timeout: ms(20),
        (ctx, events) async {
          await pause(ctx, 15);
          return events.length;
        },
      );
      final job = accumulator.add(1);
      async.elapse(ms(30));
      expect(identical(accumulator.add(2), job), isTrue);
      async.elapse(ms(200));
      expect((job.outcome! as Done<int>).value, 2);
    });
  });

  test('a deadline reaching onCancel, not onError', () {
    runSolo((solo, journal, async) {
      var errors = 0;
      final job = solo.run<TestState, void>(
        key: 'load',
        timeout: ms(10),
        onError: (state, error, stackTrace) {
          errors++;
          return state;
        },
        onCancel: (state, cancelled) => cancelled.reason is TimeoutCancelReason
            ? const Working(a: 1)
            : const Initial(),
        (ctx) => pause(ctx, 50),
      );
      async.elapse(ms(100));
      expect('${job.outcome}', 'Cancelled(timeout)');
      expect(errors, 0);
      expect(solo.currentState, const Working(a: 1));
      expect(journal.take(), [
        '[load] started',
        'state: ${const Working(a: 1)}',
        '[load] finished Cancelled(timeout)',
      ]);
    });
  });

  test('a deadline running out while the job waits for its children', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(
        key: 'load',
        timeout: ms(10),
        onCancel: (state, cancelled) => cancelled.reason is TimeoutCancelReason
            ? const Preparing(progress: 9)
            : state,
        (ctx) async {
          ctx
            ..emit(const Working(a: 1))
            ..run(
              solo.job<TestState, void>(
                key: 'child',
                (child) => pause(child, 50),
              ),
            ).ignore();
        },
      );
      async.elapse(ms(100));
      expect('${job.outcome}', 'Cancelled(timeout)');
      expect(solo.currentState, const Preparing(progress: 9));
    });
  });

  test('the queue after a deadline', () {
    runSolo((solo, journal, async) {
      final order = <String>[];
      solo.run<TestState, void>(key: 'slow', timeout: ms(10), (ctx) async {
        ctx.onDispose(() async {
          await delay(20);
          order.add('cleaned up');
        });
        await pause(ctx, 50);
      });
      final next = solo.run<TestState, int>(key: 'next', (ctx) async {
        order.add('next started');
        return 1;
      });
      async.elapse(ms(100));
      expect(order, ['cleaned up', 'next started']);
      expect((next.outcome! as Done<int>).value, 1);
    });
  });

  test('a droppable call over a live job with a deadline', () {
    runSolo((solo, journal, async) {
      final first = solo.run<TestState, int>(
        key: 'load',
        policy: Policy.droppable,
        timeout: ms(10),
        (ctx) async {
          await pause(ctx, 50);
          return 1;
        },
      );
      async.flushMicrotasks();
      final second = solo.run<TestState, int>(
        key: 'load',
        policy: Policy.droppable,
        timeout: hour,
        (ctx) async => 2,
      );
      expect(identical(second, first), isTrue);
      async.elapse(ms(100));
      expect('${first.outcome}', 'Cancelled(timeout)');
      expect(async.pendingTimers, isEmpty, reason: 'the hour went with it');
      final third = solo.run<TestState, int>(
        key: 'load',
        policy: Policy.droppable,
        timeout: ms(10),
        (ctx) async => 3,
      );
      expect(identical(third, first), isFalse);
      async.elapse(ms(100));
      expect((third.outcome! as Done<int>).value, 3);
    });
  });

  test('a restart over a job its deadline has cancelled', () {
    runSolo((solo, journal, async) {
      final first = solo.run<TestState, void>(
        key: 'load',
        timeout: ms(10),
        (ctx) => ctx.join(() => delay(50)),
      );
      async.elapse(ms(20));
      expect(first.isCancelled, isTrue);
      expect(first.isFinished, isFalse, reason: 'join plays out');
      final second = solo.run<TestState, void>(
        key: 'load',
        policy: Policy.restart,
        (ctx) async {},
      );
      async.elapse(ms(100));
      expect('${first.outcome}', 'Cancelled(timeout)');
      expect(second.outcome, isA<Done<void>>());
    });
  });

  test('cancelAll after a deadline', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(
        key: 'load',
        timeout: ms(10),
        (ctx) => ctx.join(() => delay(50)),
      );
      async.elapse(ms(20));
      solo.cancelAll().ignore();
      async.elapse(ms(100));
      expect('${job.outcome}', 'Cancelled(timeout)');
    });
  });

  test('close after a deadline', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(
        key: 'load',
        timeout: ms(10),
        (ctx) => ctx.join(() => delay(50)),
      );
      async.elapse(ms(20));
      solo.close().ignore();
      async.elapse(ms(100));
      expect('${job.outcome}', 'Cancelled(timeout)');
    });
  });

  test('close with jobs with deadlines running and queued', () {
    runSolo((solo, journal, async) {
      final gate = Completer<void>();
      final running = solo.run<TestState, void>(
        key: 'running',
        timeout: hour,
        (ctx) => ctx.abandonable(() => gate.future),
      );
      final queued = solo.run<TestState, void>(
        key: 'queued',
        timeout: hour,
        (ctx) async {},
      );
      async.flushMicrotasks();
      expect(async.pendingTimers, hasLength(1));
      solo.close().ignore();
      async.flushMicrotasks();
      expect('${running.outcome}', 'Cancelled(closed)');
      expect('${queued.outcome}', 'Cancelled(closed)');
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a drain past a job that hangs until its deadline', () {
    runSolo((solo, journal, async) {
      final hanging = solo.run<TestState, void>(
        key: 'hanging',
        timeout: ms(10),
        (ctx) => ctx.abandonable(() => Completer<void>().future),
      );
      final after = solo.run<TestState, int>(key: 'after', (ctx) async => 2);
      async.flushMicrotasks();
      var closed = false;
      solo.close(mode: SoloCloseMode.drain).then((_) => closed = true);
      async.elapse(ms(20));
      expect('${hanging.outcome}', 'Cancelled(timeout)');
      expect((after.outcome! as Done<int>).value, 2);
      expect(closed, isTrue);
    });
  });

  test('pending names a job its deadline has cancelled', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(
        key: 'job',
        timeout: ms(10),
        (ctx) => ctx.join(() => delay(50)),
      );
      async.elapse(ms(20));
      final pending = solo.pending! as SoloPendingJob;
      expect(pending.cancellation?.reason, isA<TimeoutCancelReason>());
      expect(
        '$pending',
        'SoloPending([job] in its body, cancelled by Cancelled(timeout))',
      );
      async.flushTimers();
    });
  });

  test('pending names a deadline a section holds', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(
        key: 'job',
        timeout: ms(10),
        (ctx) => ctx.uncancellable(() => delay(50)),
      );
      async.elapse(ms(20));
      final pending = solo.pending! as SoloPendingJob;
      expect(pending.cancellation, isNull);
      expect(pending.heldCancellation?.reason, isA<TimeoutCancelReason>());
      expect(
        '$pending',
        'SoloPending([job] in its body, holding Cancelled(timeout) back)',
      );
      async.flushTimers();
    });
  });
}
