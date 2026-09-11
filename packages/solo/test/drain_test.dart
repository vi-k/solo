@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

SoloJob<void> step(TestSolo solo, String name) => solo.run<TestState, void>(
      key: name,
      (ctx) async {
        await delay(50);
        ctx.emit(const Preparing());
      },
    );

void main() {
  test('a drain runs what was already queued', () {
    runSolo((solo, journal, async) {
      step(solo, 'one');
      step(solo, 'two');
      step(solo, 'three');
      async.flushMicrotasks();
      solo.close(mode: SoloCloseMode.drain).ignore();
      expect(solo.isClosed, isTrue);
      expect(solo.isDraining, isTrue);
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 150));
      expect(solo.isDraining, isFalse);
      expect(journal.take(), [
        '[one] started',
        'state: Preparing(progress: 0)',
        '[one] finished Done(null)',
        '[two] started',
        'state: Preparing(progress: 0)',
        '[two] finished Done(null)',
        '[three] started',
        'state: Preparing(progress: 0)',
        '[three] finished Done(null)',
        'closed',
      ]);
    });
  });

  test('a drain takes no new root job', () {
    runSolo((solo, journal, async) {
      step(solo, 'queued');
      async.flushMicrotasks();
      solo.close(mode: SoloCloseMode.drain).ignore();
      final refused = step(solo, 'late');
      async.flushTimers();
      expect(refused.outcome, isA<Cancelled>());
      expect(
        journal.take(),
        containsAllInOrder([
          '[late] dropped Cancelled(closed)',
          '[queued] finished Done(null)',
          'closed',
        ]),
      );
    });
  });

  test('a drained job keeps its children and its cleanup', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        ctx.onDispose(() => ctx.log('cleaned'));
        await ctx.run(
          solo.job<TestState, void>(
            key: 'child',
            (childCtx) => delay(30),
          ),
        );
      });
      async.flushMicrotasks();
      solo.close(mode: SoloCloseMode.drain).ignore();
      async.flushTimers();
      expect(journal.take(), [
        '[job] started',
        '> [child] started',
        '> [child] finished Done(null)',
        '[job] log cleaned',
        '[job] finished Done(null)',
        'closed',
      ]);
    });
  });

  test('an idle controller drains at once, on a microtask', () {
    runSolo((solo, journal, async) {
      var closed = false;
      solo.close(mode: SoloCloseMode.drain).then((_) => closed = true).ignore();
      expect(closed, isFalse, reason: 'onClose never arrives from inside');
      async.flushMicrotasks();
      expect(closed, isTrue);
      expect(journal.take(), ['closed']);
    });
  });

  test('a drain waits out an accumulation window', () {
    runSolo((solo, journal, async) {
      final metrics = solo.collect<TestState, int, void>(
        key: 'metrics',
        timing: AccumulationTiming.debounce(const Duration(milliseconds: 40)),
        (ctx, events) async => ctx.log('sent $events'),
      );
      metrics.add(1).ignore();
      metrics.add(2).ignore();
      async.elapse(const Duration(milliseconds: 10));
      solo.close(mode: SoloCloseMode.drain).ignore();
      async.flushTimers();
      expect(journal.take(), [
        '[metrics] started',
        '[metrics] log sent [1, 2]',
        '[metrics] finished Done(null)',
        'closed',
      ]);
    });
  });

  test('a plain close over a drain stops it where it is', () {
    runSolo((solo, journal, async) {
      step(solo, 'running');
      step(solo, 'queued');
      async.flushMicrotasks();
      solo.close(mode: SoloCloseMode.drain).ignore();
      async.elapse(const Duration(milliseconds: 10));
      solo.close().ignore();
      expect(solo.isDraining, isFalse);
      async.flushTimers();
      expect(journal.take(), [
        '[running] started',
        '[queued] dropped Cancelled(closed)',
        '[running] finished Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('a drain over a plain close changes nothing', () {
    runSolo((solo, journal, async) {
      step(solo, 'running');
      step(solo, 'queued');
      async.flushMicrotasks();
      solo.close().ignore();
      solo.close(mode: SoloCloseMode.drain).ignore();
      expect(solo.isDraining, isFalse);
      async.flushTimers();
      expect(journal.take(), [
        '[running] started',
        '[queued] dropped Cancelled(closed)',
        '[running] finished Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('repeated drains share one future and close once', () {
    runSolo((solo, journal, async) {
      step(solo, 'job');
      async.flushMicrotasks();
      final first = solo.close(mode: SoloCloseMode.drain)..ignore();
      final second = solo.close(mode: SoloCloseMode.drain)..ignore();
      expect(identical(first, second), isTrue);
      async.flushTimers();
      expect(journal.take().where((line) => line == 'closed'), hasLength(1));
    });
  });

  test('cancelAll ends a drain by emptying the queue', () {
    runSolo((solo, journal, async) {
      step(solo, 'running');
      step(solo, 'queued');
      async.flushMicrotasks();
      solo.close(mode: SoloCloseMode.drain).ignore();
      solo.cancelAll();
      async.flushTimers();
      expect(journal.take(), [
        '[running] started',
        '[queued] dropped Cancelled(manual)',
        '[running] finished Cancelled(manual)',
        'closed',
      ]);
    });
  });
}
