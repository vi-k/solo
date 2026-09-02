@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

Job<void> droppable(TestSolo solo, int n) => solo.run<Special, void>(
      key: 'droppable',
      describe: () => '$n',
      policy: Policy.droppable,
      (ctx) async {
        await delay(100);
        final count = ctx.state.droppableCount + 1;
        ctx.emit(ctx.state.copyWith(droppableCount: count));
      },
    );

Job<void> restartable(TestSolo solo, int n) => solo.run<Special, void>(
      key: 'restartable',
      describe: () => '$n',
      policy: Policy.restart,
      (ctx) async {
        final before = ctx.state.restartableCount + 1;
        ctx.emit(ctx.state.copyWith(restartableCount: before));
        await delay(100);
        final after = ctx.state.restartableCount + 1;
        ctx.emit(ctx.state.copyWith(restartableCount: after));
      },
    );

Job<void> replaceable(TestSolo solo, int n) => solo.run<Special, void>(
      key: 'replace',
      describe: () => '$n',
      policy: Policy.replace,
      (ctx) async {
        await delay(100);
        final count = ctx.state.sequentialCount + 1;
        ctx.emit(ctx.state.copyWith(sequentialCount: count));
      },
    );

void main() {
  test('droppable returns the queued job and drops the duplicate', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      final first = droppable(solo, 1);
      final second = droppable(solo, 2);
      expect(identical(first, second), isTrue);
      async.flushTimers();
      expect(journal.take(), [
        '[droppable: 2] dropped Cancelled(manual: duplicate)',
        '[droppable: 1] started',
        'state: Special(droppable: 1)',
        '[droppable: 1] finished Done(null)',
      ]);
    });
  });

  test('droppable finds the running job too', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      final first = droppable(solo, 1);
      async.elapse(const Duration(milliseconds: 50));
      final second = droppable(solo, 2);
      expect(identical(first, second), isTrue);
      async.flushTimers();
      expect(journal.take(), [
        '[droppable: 1] started',
        '[droppable: 2] dropped Cancelled(manual: duplicate)',
        'state: Special(droppable: 1)',
        '[droppable: 1] finished Done(null)',
      ]);
    });
  });

  test('droppable after a pause runs both', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      droppable(solo, 1);
      async.elapse(const Duration(milliseconds: 150));
      droppable(solo, 2);
      async.flushTimers();
      expect(journal.take(), [
        '[droppable: 1] started',
        'state: Special(droppable: 1)',
        '[droppable: 1] finished Done(null)',
        '[droppable: 2] started',
        'state: Special(droppable: 2)',
        '[droppable: 2] finished Done(null)',
      ]);
    });
  });

  test('replace removes queued jobs with the key, keeps the running one', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      replaceable(solo, 1);
      async.elapse(const Duration(milliseconds: 50));
      replaceable(solo, 2);
      replaceable(solo, 3);
      async.flushTimers();
      expect(journal.take(), [
        '[replace: 1] started',
        '[replace: 2] dropped Cancelled(manual)',
        'state: Special(sequential: 1)',
        '[replace: 1] finished Done(null)',
        '[replace: 3] started',
        'state: Special(sequential: 2)',
        '[replace: 3] finished Done(null)',
      ]);
    });
  });

  test('restart drops the queued job with the key', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      restartable(solo, 1);
      restartable(solo, 2);
      async.flushTimers();
      expect(journal.take(), [
        '[restartable: 1] dropped Cancelled(manual)',
        '[restartable: 2] started',
        'state: Special(restartable: 1)',
        'state: Special(restartable: 2)',
        '[restartable: 2] finished Done(null)',
      ]);
    });
  });

  test('restart cancels the running job with the key without waiting', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      restartable(solo, 1);
      async.elapse(const Duration(milliseconds: 50));
      final second = restartable(solo, 2);
      expect(second.isQueued, isTrue);
      expect(solo.current!.isCancelled, isTrue);
      async.flushTimers();
      expect(journal.take(), [
        '[restartable: 1] started',
        'state: Special(restartable: 1)',
        '[restartable: 1] finished Cancelled(manual)',
        '[restartable: 2] started',
        'state: Special(restartable: 2)',
        'state: Special(restartable: 3)',
        '[restartable: 2] finished Done(null)',
      ]);
    });
  });

  test('a policy other than sequential requires a key', () {
    runSolo((solo, journal, async) {
      for (final policy in [Policy.droppable, Policy.replace, Policy.restart]) {
        expect(
          () => solo.run<TestState, void>(policy: policy, (ctx) async {}),
          throwsArgumentError,
          reason: '$policy',
        );
      }
      expect(journal.lines, isEmpty);
    });
  });
}
