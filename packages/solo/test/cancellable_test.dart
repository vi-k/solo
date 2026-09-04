@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('an uncancellable step refuses cancel and the job finishes', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'pay', (ctx) async {
        await ctx.uncancellable(() => delay(100));
        ctx.emit(const Working());
      });
      async.elapse(const Duration(milliseconds: 50));
      var cancelDone = false;
      job.cancel().then((_) => cancelDone = true);
      async.flushMicrotasks();
      expect(job.isCancelled, isFalse, reason: 'the step is in flight');
      expect(cancelDone, isFalse, reason: 'cancel waits for the body');
      async.elapse(const Duration(milliseconds: 50));
      expect(cancelDone, isTrue);
      expect(job.outcome, isA<Done<void>>());
      expect(journal.take(), [
        '[pay] started',
        'state: Working(a: 0, b: 0)',
        '[pay] finished Done(null)',
      ]);
    });
  });

  test('cancel works again once the step is over', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'pay', (ctx) async {
        await ctx.uncancellable(() => delay(50));
        await delay(50);
        ctx.emit(const Working());
      });
      async.elapse(const Duration(milliseconds: 75));
      job.cancel();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(journal.take(), [
        '[pay] started',
        '[pay] finished Cancelled(manual)',
      ]);
    });
  });

  test('close waits for an uncancellable step instead of cancelling', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'pay', (ctx) async {
        await ctx.uncancellable(() => delay(100));
        ctx.emit(const Working());
      });
      async.elapse(const Duration(milliseconds: 50));
      var closed = false;
      solo.close().then((_) => closed = true);
      async.flushMicrotasks();
      expect(closed, isFalse, reason: 'close waits for the body');
      async.flushTimers();
      expect(closed, isTrue);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('the answer in force before the step is restored, not assumed', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(
        key: 'pay',
        cancellable: false,
        (ctx) async {
          await ctx.uncancellable(() => delay(50));
          // Still uncancellable: the job was created that way, and the
          // step restored what it found rather than opening the job up.
          await delay(50);
          ctx.emit(const Working());
        },
      );
      async.elapse(const Duration(milliseconds: 75));
      job.cancel();
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('the answer comes back even if the step throws', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'pay', (ctx) async {
        try {
          await ctx.uncancellable(() async {
            await delay(50);
            throw const FormatException('declined');
          });
        } on FormatException {
          // The payment failed; the job carries on and may be cancelled.
        }
        await delay(50);
        ctx.emit(const Working());
      });
      async.elapse(const Duration(milliseconds: 75));
      job.cancel();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('rules cancel a job inside an uncancellable step anyway', () {
    runSolo((solo, journal, async) {
      solo.run<NotDisposed, void>(key: 'pay', (ctx) async {
        await ctx.uncancellable(() => delay(100));
        ctx.check();
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Disposed());
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[pay] started',
        'state: Disposed()',
        '[pay] finished Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('an already cancelled job does not begin the step', () {
    runSolo((solo, journal, async) {
      var began = false;
      final job = solo.run<TestState, void>(key: 'pay', (ctx) async {
        await delay(100);
        await ctx.uncancellable(() async => began = true);
      });
      async.elapse(const Duration(milliseconds: 50));
      job.cancel();
      async.flushTimers();
      expect(began, isFalse, reason: 'nothing irreversible starts');
      expect(job.outcome, isA<Cancelled>());
    });
  });
}
