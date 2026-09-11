@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('an idle controller holds nothing', () {
    runSolo((solo, journal, async) {
      expect(solo.pending, isNull);
    });
  });

  test('a running body says so, and nobody has asked it to stop', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) => pause(ctx, 100));
      async.flushMicrotasks();
      final pending = solo.pending!;
      expect(pending.phase, SoloPhase.body);
      expect(pending.job.key, 'job');
      expect(pending.cancellation, isNull);
      expect(pending.cancellationPending, isFalse);
      expect(pending.closing, isFalse);
      expect(pending.refusesCancellation, isFalse);
      expect('$pending', 'SoloPending([job] in its body)');
      async.flushTimers();
    });
  });

  test('a job that turns cancellation down is nothing pending', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(
        key: 'job',
        cancellable: false,
        (ctx) => pause(ctx, 100),
      );
      async.flushMicrotasks();
      solo.close();
      final pending = solo.pending!;
      expect(pending.closing, isTrue);
      expect(
        pending.cancellation,
        isNull,
        reason: 'close asked and this one turned it down',
      );
      expect(pending.cancellationPending, isFalse);
      expect(pending.refusesCancellation, isTrue);
      expect(
        '$pending',
        'SoloPending([job] in its body, closing, '
            'created cancellable: false)',
      );
      async.flushTimers();
    });
  });

  test('a held cancellation is named without being a guess', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(
        key: 'job',
        (ctx) => ctx.uncancellable(() => delay(100)),
      );
      async.flushMicrotasks();
      solo.cancelAll();
      final pending = solo.pending!;
      expect(pending.inUncancellableSection, isTrue);
      expect(
        pending.cancellation,
        isNull,
        reason: 'the job is not marked while the section holds it',
      );
      expect(pending.cancellationPending, isTrue);
      expect(
        '$pending',
        'SoloPending([job] in its body, holding a cancellation back)',
      );
      async.flushTimers();
    });
  });

  test('a body that ended with children waiting says how many', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        ctx
          ..each<int>(
            Stream<int>.periodic(const Duration(milliseconds: 20), (i) => i),
            (childCtx, event) async {},
          )
          ..each<int>(
            Stream<int>.periodic(const Duration(milliseconds: 30), (i) => i),
            (childCtx, event) async {},
          );
      });
      async.elapse(const Duration(milliseconds: 10));
      final pending = solo.pending!;
      expect(pending.phase, SoloPhase.children);
      expect(pending.children, 2);
      expect('$pending', 'SoloPending([job] waiting for 2 children)');
      solo.cancelAll();
      async.flushTimers();
    });
  });

  test('a cleanup that takes its time is named', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        ctx.onDispose(() => delay(100));
      });
      async.flushMicrotasks();
      final pending = solo.pending!;
      expect(pending.phase, SoloPhase.cleanup);
      expect('$pending', 'SoloPending([job] in its cleanup)');
      async.flushTimers();
    });
  });

  test('a body waiting on something the engine cannot see says so', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        // A bare await, past every checkpoint: this is the case the
        // engine has nothing to say about, and it must not pretend.
        await delay(100);
      });
      async.flushMicrotasks();
      expect(solo.pending!.phase, SoloPhase.body);
      async.flushTimers();
    });
  });
}
