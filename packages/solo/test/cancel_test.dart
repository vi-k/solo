@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('cancel of a queued job drops it at once', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'first', (ctx) async => delay(100));
      final second = solo.run<TestState, void>(key: 'second', (ctx) async {});
      async.flushMicrotasks();
      var cancelDone = false;
      second.cancel().then((_) => cancelDone = true);
      async.flushMicrotasks();
      expect(cancelDone, isTrue);
      expect(journal.take(), [
        '[first] started',
        '[second] dropped Cancelled(manual)',
      ]);
    });
  });

  test('whenCancelled completes for a job dropped from the queue', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'first', (ctx) async => delay(100));
      final second = solo.run<TestState, void>(key: 'second', (ctx) async {});
      async.flushMicrotasks();
      var cancelled = false;
      second.whenCancelled.then((_) => cancelled = true);
      second.cancel();
      async.flushMicrotasks();
      expect(cancelled, isTrue);
      expect(journal.take(), [
        '[first] started',
        '[second] dropped Cancelled(manual)',
      ]);
    });
  });

  test('cancel of a running job fixes the outcome and waits for the body', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, int>(key: 'job', (ctx) async {
        await delay(100);
        ctx.check();
        return 1;
      });
      async.elapse(const Duration(milliseconds: 50));
      var cancelDone = false;
      job.cancel().then((_) => cancelDone = true);
      async.flushMicrotasks();
      expect(job.isCancelled, isTrue);
      expect(job.isRunning, isTrue);
      expect(cancelDone, isFalse, reason: 'cancel waits for the body');

      async.elapse(const Duration(milliseconds: 50));
      expect(cancelDone, isTrue);
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('a value returned after cancellation does not change the outcome', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, int>(key: 'job', (ctx) async {
        await delay(100);
        return 42;
      });
      async.elapse(const Duration(milliseconds: 50));
      job.cancel();
      async.elapse(const Duration(milliseconds: 50));
      expect(job.outcome, isA<Cancelled>());
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('an error thrown after cancellation goes to onError only', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        await delay(100);
        throw StateError('late');
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[job] started',
        '[job] error Bad state: late',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('a body throwing Cancelled cancels itself as handler', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        throw const Cancelled('no photo');
      });
      async.flushMicrotasks();
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(handler: no photo)',
      ]);
      final outcome = job.outcome! as Cancelled;
      expect(outcome.started, isTrue);
      expect(outcome.stackTrace, isNotNull);
    });
  });

  test('Cancelled thrown after the mark keeps the marked outcome', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        await delay(100);
        throw const Cancelled('mine');
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('cancel does not cancel a running cancellable: false job', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(
        key: 'stubborn',
        cancellable: false,
        (ctx) async {
          await delay(100);
          ctx.emit(const Working());
        },
      );
      async.elapse(const Duration(milliseconds: 50));
      var cancelDone = false;
      job.cancel().then((_) => cancelDone = true);
      async.flushMicrotasks();
      expect(job.isCancelled, isFalse);
      expect(cancelDone, isFalse);
      async.elapse(const Duration(milliseconds: 50));
      expect(cancelDone, isTrue);
      expect(journal.take(), [
        '[stubborn] started',
        'state: Working(a: 0, b: 0)',
        '[stubborn] finished Done(null)',
      ]);
    });
  });

  test('rules cancel a cancellable: false job anyway', () {
    runSolo((solo, journal, async) {
      solo.run<NotDisposed, void>(
        key: 'stubborn',
        cancellable: false,
        (ctx) async {
          await delay(100);
          ctx.check();
        },
      );
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Disposed());
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[stubborn] started',
        'state: Disposed()',
        '[stubborn] finished Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('cancel before add drops the job and add then throws', () {
    runSolo((solo, journal, async) {
      final job = solo.job<TestState, void>(key: 'early', (ctx) async {})
        ..cancel();
      expect(journal.take(), ['[early] dropped Cancelled(manual)']);
      expect(() => solo.add(job), throwsStateError);
    });
  });

  test('value throws Cancelled, done does not', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await delay(100);
        ctx.check();
      });
      Object? error;
      Outcome<void>? outcome;
      job.value.then(
        (_) {},
        onError: (Object e) {
          error = e;
        },
      );
      job.done.then((o) => outcome = o);
      async.elapse(const Duration(milliseconds: 50));
      job.cancel();
      async.elapse(const Duration(milliseconds: 50));
      expect(identical(error, job.outcome), isTrue);
      expect(identical(outcome, job.outcome), isTrue);
    });
  });

  test('a second cancel and a cancel after finish are no-ops', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await delay(100);
        ctx.check();
      });
      async.elapse(const Duration(milliseconds: 50));
      job
        ..cancel()
        ..cancel();
      async.elapse(const Duration(milliseconds: 50));
      var done = false;
      job.cancel().then((_) => done = true);
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('the manual stack trace points at cancel', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await delay(100);
        ctx.check();
      });
      async.elapse(const Duration(milliseconds: 50));
      job.cancel();
      async.elapse(const Duration(milliseconds: 50));
      final trace = (job.outcome! as Cancelled).stackTrace.toString();
      expect(trace, contains('cancel'));
    });
  });
}
