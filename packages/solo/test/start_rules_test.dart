@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

void addTyped(TestSolo solo) {
  solo
    ..run<Initial, void>(key: 'test1', (ctx) async {})
    ..run<Preparing, void>(key: 'test2', (ctx) async {})
    ..run<Working, void>(key: 'test3', (ctx) async {});
}

void main() {
  test('only the job whose W matches Initial runs', () {
    runSolo((solo, journal, async) {
      addTyped(solo);
      async.flushMicrotasks();
      expect(journal.take(), [
        '[test1] started',
        '[test1] finished Done(null)',
        '[test2] dropped Cancelled(rules: is not Preparing)',
        '[test3] dropped Cancelled(rules: is not Working)',
      ]);
    });
  });

  test('only the job whose W matches Preparing runs', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      addTyped(solo);
      async.flushMicrotasks();
      expect(journal.take(), [
        '[test1] dropped Cancelled(rules: is not Initial)',
        '[test2] started',
        '[test2] finished Done(null)',
        '[test3] dropped Cancelled(rules: is not Working)',
      ]);
    });
  });

  test('a job whose W is the base type runs in any state', () {
    runSolo(initialState: const Disposed(), (solo, journal, async) {
      solo.run<TestState, void>(key: 'any', (ctx) async {});
      async.flushMicrotasks();
      expect(journal.take(), ['[any] started', '[any] finished Done(null)']);
    });
  });

  test('canStart false drops the job before start', () {
    runSolo((solo, journal, async) {
      final job = solo.run<Initial, void>(
        key: 'guarded',
        canStart: (state) => false,
        (ctx) async {},
      );
      async.flushMicrotasks();
      expect(journal.take(), ['[guarded] dropped Cancelled(rules: canStart)']);
      final outcome = job.outcome! as Cancelled;
      expect(outcome.started, isFalse);
      expect(job.isCancelled, isTrue);
      expect(job.isFinished, isTrue);
      expect(job.isQueued, isFalse);
    });
  });

  test('keepWhile false at start drops the job before start', () {
    runSolo(initialState: const Preparing(progress: 100),
        (solo, journal, async) {
      solo.run<Preparing, void>(
        key: 'kept',
        keepWhile: (state) => state.progress < 100,
        (ctx) async {},
      );
      async.flushMicrotasks();
      expect(journal.take(), ['[kept] dropped Cancelled(rules: keepWhile)']);
    });
  });

  test('the type is checked before canStart', () {
    runSolo((solo, journal, async) {
      var called = false;
      solo.run<Working, void>(
        key: 'typed',
        canStart: (state) {
          called = true;
          return true;
        },
        (ctx) async {},
      );
      async.flushMicrotasks();
      expect(
        journal.take(),
        ['[typed] dropped Cancelled(rules: is not Working)'],
      );
      expect(called, isFalse);
    });
  });

  test('a dropped job is reported to onFinish with no onStart', () {
    runSolo((solo, journal, async) {
      final job = solo.run<Working, void>(key: 'x', (ctx) async {});
      Outcome<void>? outcome;
      job.done.then((o) => outcome = o);
      async.flushMicrotasks();
      expect(outcome, isA<Cancelled>());
      expect(journal.take(), ['[x] dropped Cancelled(rules: is not Working)']);
    });
  });
}
