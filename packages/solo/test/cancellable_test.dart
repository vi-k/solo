@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('a closed section refuses cancel and the job finishes', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'pay', (ctx) async {
        ctx.cancellable = false;
        await delay(100);
        ctx
          ..cancellable = true
          ..emit(const Working());
      });
      async.elapse(const Duration(milliseconds: 50));
      var cancelDone = false;
      job.cancel().then((_) => cancelDone = true);
      async.flushMicrotasks();
      expect(job.isCancelled, isFalse, reason: 'the section is closed');
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

  test('cancel works again once the section is reopened', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'pay', (ctx) async {
        ctx.cancellable = false;
        await delay(50);
        ctx.cancellable = true;
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

  test('close waits for a closed section instead of cancelling', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'pay', (ctx) async {
        ctx.cancellable = false;
        await delay(100);
        ctx
          ..cancellable = true
          ..emit(const Working());
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

  test('a job created uncancellable can open itself from the body', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(
        key: 'pay',
        cancellable: false,
        (ctx) async {
          await delay(50);
          ctx.cancellable = true;
          await delay(50);
          ctx.emit(const Working());
        },
      );
      async.elapse(const Duration(milliseconds: 75));
      job.cancel();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>(), reason: 'the body opened it');
      expect(journal.take(), [
        '[pay] started',
        '[pay] finished Cancelled(manual)',
      ]);
    });
  });

  test('rules cancel a job with a closed section anyway', () {
    runSolo((solo, journal, async) {
      solo.run<NotDisposed, void>(key: 'pay', (ctx) async {
        ctx.cancellable = false;
        await delay(100);
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

  test('setting it back is safe on a job the rules already cancelled', () {
    runSolo((solo, journal, async) {
      final job = solo.run<NotDisposed, void>(key: 'pay', (ctx) async {
        ctx.cancellable = false;
        try {
          await delay(100);
        } finally {
          ctx.cancellable = true;
        }
        ctx.check();
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>(), reason: 'not Failed');
    });
  });
}
