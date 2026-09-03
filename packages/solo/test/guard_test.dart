@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('guard stops waiting when the job is cancelled', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.guard(() => delay(100));
        ctx.emit(const Preparing());
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.flushMicrotasks();
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(manual)',
      ]);
      expect(async.elapsed, const Duration(milliseconds: 50));
    });
  });

  test('guard stops waiting when the action cancels the job itself', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.guard(() {
          solo.current!.cancel();
          return delay(100);
        });
        ctx.emit(const Preparing());
      });
      async.flushMicrotasks();
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(manual)',
      ]);
      expect(async.elapsed, Duration.zero);
    });
  });

  test('guard stops waiting when the action drops the job by a rule', () {
    runSolo((solo, journal, async) {
      solo.run<NotDisposed, void>(key: 'job', (ctx) async {
        await ctx.guard(() {
          solo.externalSetState(const Disposed());
          return delay(100);
        });
        ctx.check();
      });
      async.flushMicrotasks();
      expect(journal.take(), [
        '[job] started',
        'state: Disposed()',
        '[job] finished Cancelled(rules: is not NotDisposed)',
      ]);
      expect(async.elapsed, Duration.zero);
    });
  });

  test('guard does not start the action when already cancelled', () {
    runSolo((solo, journal, async) {
      var started = false;
      solo.run<TestState, void>(key: 'job', (ctx) async {
        await delay(100);
        await ctx.guard(() {
          started = true;
          return delay(10);
        });
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.elapse(const Duration(milliseconds: 50));
      expect(started, isFalse);
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('a late error of the abandoned future goes to onError', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.guard(() async {
          await delay(100);
          throw StateError('late');
        });
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.flushMicrotasks();
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(manual)',
      ]);
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), ['[job] error Bad state: late']);
    });
  });

  test('a late value of the abandoned future is ignored', () {
    runSolo((solo, journal, async) {
      var resumed = false;
      solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.guard(() async {
          await delay(100);
          return 1;
        });
        resumed = true;
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.elapse(const Duration(milliseconds: 100));
      expect(resumed, isFalse);
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('guard passes values and errors through', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, int>(key: 'job', (ctx) async {
        final sync = await ctx.guard(() => 1);
        final later = await ctx.guard(() async {
          await delay(10);
          return 2;
        });
        return sync + later;
      });
      solo.run<TestState, void>(key: 'bad', (ctx) async {
        await ctx.guard(() => throw StateError('boom'));
      }).ignore();
      async.flushTimers();
      expect((job.outcome! as Done<int>).value, 3);
      expect(journal.take(), [
        '[job] started',
        '[job] finished Done(3)',
        '[bad] started',
        '[bad] error Bad state: boom',
        '[bad] finished Failed(Bad state: boom)',
      ]);
    });
  });

  test('guard checks the rules before starting', () {
    runSolo((solo, journal, async) {
      solo.run<Initial, void>(key: 'job', (ctx) async {
        ctx.emit(const Preparing());
        await ctx.guard(() => delay(10));
      });
      async.flushTimers();
      expect(journal.take(), [
        '[job] started',
        'state: Preparing(progress: 0)',
        '[job] finished Cancelled(rules: is not Initial)',
      ]);
    });
  });

  test('a timeout is a guard around Future.timeout', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.guard(
          () => delay(100).timeout(const Duration(milliseconds: 10)),
        );
      }).ignore();
      async.flushTimers();
      const errorLine = '[job] error TimeoutException after '
          '0:00:00.010000: Future not completed';
      const finishedLine = '[job] finished Failed(TimeoutException after '
          '0:00:00.010000: Future not completed)';
      expect(journal.take(), [
        '[job] started',
        errorLine,
        finishedLine,
      ]);
    });
  });
}
