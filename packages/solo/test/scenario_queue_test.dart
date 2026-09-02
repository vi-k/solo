@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

/// A short job that only bumps its counter: the "other events" of the 1.x
/// scenarios.
Job<void> noop(TestSolo solo, int n) => solo.run<Special, void>(
      key: 'noop',
      describe: () => '$n',
      (ctx) async {
        await Future<void>(() {});
        ctx.emit(ctx.state.copyWith(noopCount: ctx.state.noopCount + 1));
      },
    );

/// A 100 ms job with no policy at all: the queue alone orders it.
Job<void> sequential(TestSolo solo, int n) => solo.run<Special, void>(
      key: 'sequential',
      describe: () => '$n',
      (ctx) async {
        await delay(100);
        ctx.emit(
          ctx.state.copyWith(sequentialCount: ctx.state.sequentialCount + 1),
        );
      },
    );

/// `Policy.droppable` written out by hand: look the job up, and cancel the
/// new one before it reaches the queue. The caller always gets the job that
/// stays, so this one fixture covers both 1.x droppable groups.
Job<void> droppableByQueue(TestSolo solo, int n) {
  final existing = solo.lastJobWhere((job) => job.key == 'droppable');
  final job = solo.job<Special, void>(
    key: 'droppable',
    describe: () => '$n',
    (ctx) async {
      await delay(100);
      ctx.emit(
        ctx.state.copyWith(droppableCount: ctx.state.droppableCount + 1),
      );
    },
  );
  if (existing != null) {
    job.cancel();
    return existing as Job<void>;
  }
  return solo.add(job);
}

/// `Policy.restart` written out by hand: drop the queued namesakes, cancel
/// the running one without waiting for it, then queue the new job.
Job<void> restartableByQueue(TestSolo solo, int n) {
  solo.queue.removeWhere((job) => job.key == 'restartable');
  final current = solo.current;
  if (current != null && current.key == 'restartable') {
    current.cancel();
  }
  return solo.add(
    solo.job<Special, void>(
      key: 'restartable',
      describe: () => '$n',
      (ctx) async {
        ctx.emit(
          ctx.state.copyWith(restartableCount: ctx.state.restartableCount + 1),
        );
        await delay(100);
        ctx.emit(
          ctx.state.copyWith(restartableCount: ctx.state.restartableCount + 1),
        );
      },
    ),
  );
}

void main() {
  test('sequential jobs run one after another', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      sequential(solo, 1);
      sequential(solo, 2);
      async.flushTimers();
      expect((solo.state as Special).sequentialCount, 2);
      expect(journal.take(), [
        '[sequential: 1] started',
        'state: Special(sequential: 1)',
        '[sequential: 1] finished Done(null)',
        '[sequential: 2] started',
        'state: Special(sequential: 2)',
        '[sequential: 2] finished Done(null)',
      ]);
    });
  });

  test('sequential jobs interleave with noops in queue order', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      noop(solo, 1);
      sequential(solo, 1);
      noop(solo, 2);
      sequential(solo, 2);
      noop(solo, 3);
      async.flushTimers();
      expect((solo.state as Special).sequentialCount, 2);
      expect(journal.take(), [
        '[noop: 1] started',
        'state: Special(noop: 1)',
        '[noop: 1] finished Done(null)',
        '[sequential: 1] started',
        'state: Special(noop: 1, sequential: 1)',
        '[sequential: 1] finished Done(null)',
        '[noop: 2] started',
        'state: Special(noop: 2, sequential: 1)',
        '[noop: 2] finished Done(null)',
        '[sequential: 2] started',
        'state: Special(noop: 2, sequential: 2)',
        '[sequential: 2] finished Done(null)',
        '[noop: 3] started',
        'state: Special(noop: 3, sequential: 2)',
        '[noop: 3] finished Done(null)',
      ]);
    });
  });

  test('a sequential job added mid-flight waits its turn', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      sequential(solo, 1);
      async.elapse(const Duration(milliseconds: 50));
      sequential(solo, 2);
      async.flushTimers();
      expect((solo.state as Special).sequentialCount, 2);
      expect(journal.take(), [
        '[sequential: 1] started',
        'state: Special(sequential: 1)',
        '[sequential: 1] finished Done(null)',
        '[sequential: 2] started',
        'state: Special(sequential: 2)',
        '[sequential: 2] finished Done(null)',
      ]);
    });
  });

  test('a sequential job added mid-flight queues behind the noop', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      noop(solo, 1);
      sequential(solo, 1);
      noop(solo, 2);
      async.elapse(const Duration(milliseconds: 50));
      sequential(solo, 2);
      noop(solo, 3);
      async.flushTimers();
      expect((solo.state as Special).sequentialCount, 2);
      expect(journal.take(), [
        '[noop: 1] started',
        'state: Special(noop: 1)',
        '[noop: 1] finished Done(null)',
        '[sequential: 1] started',
        'state: Special(noop: 1, sequential: 1)',
        '[sequential: 1] finished Done(null)',
        '[noop: 2] started',
        'state: Special(noop: 2, sequential: 1)',
        '[noop: 2] finished Done(null)',
        '[sequential: 2] started',
        'state: Special(noop: 2, sequential: 2)',
        '[sequential: 2] finished Done(null)',
        '[noop: 3] started',
        'state: Special(noop: 3, sequential: 2)',
        '[noop: 3] finished Done(null)',
      ]);
    });
  });

  test('a sequential job added after a long pause runs at once', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      sequential(solo, 1);
      async.elapse(const Duration(milliseconds: 150));
      sequential(solo, 2);
      async.flushTimers();
      expect((solo.state as Special).sequentialCount, 2);
      expect(journal.take(), [
        '[sequential: 1] started',
        'state: Special(sequential: 1)',
        '[sequential: 1] finished Done(null)',
        '[sequential: 2] started',
        'state: Special(sequential: 2)',
        '[sequential: 2] finished Done(null)',
      ]);
    });
  });

  test('sequential jobs added after a long pause keep queue order', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      noop(solo, 1);
      sequential(solo, 1);
      noop(solo, 2);
      async.elapse(const Duration(milliseconds: 150));
      sequential(solo, 2);
      noop(solo, 3);
      async.flushTimers();
      expect((solo.state as Special).sequentialCount, 2);
      expect(journal.take(), [
        '[noop: 1] started',
        'state: Special(noop: 1)',
        '[noop: 1] finished Done(null)',
        '[sequential: 1] started',
        'state: Special(noop: 1, sequential: 1)',
        '[sequential: 1] finished Done(null)',
        '[noop: 2] started',
        'state: Special(noop: 2, sequential: 1)',
        '[noop: 2] finished Done(null)',
        '[sequential: 2] started',
        'state: Special(noop: 2, sequential: 2)',
        '[sequential: 2] finished Done(null)',
        '[noop: 3] started',
        'state: Special(noop: 3, sequential: 2)',
        '[noop: 3] finished Done(null)',
      ]);
    });
  });

  test('droppable by queue returns the queued job and drops the copy', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      final first = droppableByQueue(solo, 1);
      final second = droppableByQueue(solo, 2);
      expect(identical(first, second), isTrue);
      async.flushTimers();
      expect((solo.state as Special).droppableCount, 1);
      expect(journal.take(), [
        '[droppable: 2] dropped Cancelled(manual)',
        '[droppable: 1] started',
        'state: Special(droppable: 1)',
        '[droppable: 1] finished Done(null)',
      ]);
    });
  });

  test('droppable by queue drops the copy, noops keep their order', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      noop(solo, 1);
      final first = droppableByQueue(solo, 1);
      noop(solo, 2);
      final second = droppableByQueue(solo, 2);
      noop(solo, 3);
      expect(identical(first, second), isTrue);
      async.flushTimers();
      expect((solo.state as Special).droppableCount, 1);
      expect(journal.take(), [
        '[droppable: 2] dropped Cancelled(manual)',
        '[noop: 1] started',
        'state: Special(noop: 1)',
        '[noop: 1] finished Done(null)',
        '[droppable: 1] started',
        'state: Special(noop: 1, droppable: 1)',
        '[droppable: 1] finished Done(null)',
        '[noop: 2] started',
        'state: Special(noop: 2, droppable: 1)',
        '[noop: 2] finished Done(null)',
        '[noop: 3] started',
        'state: Special(noop: 3, droppable: 1)',
        '[noop: 3] finished Done(null)',
      ]);
    });
  });

  test('droppable by queue finds the running job too', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      final first = droppableByQueue(solo, 1);
      async.elapse(const Duration(milliseconds: 50));
      final second = droppableByQueue(solo, 2);
      expect(identical(first, second), isTrue);
      async.flushTimers();
      expect((solo.state as Special).droppableCount, 1);
      expect(journal.take(), [
        '[droppable: 1] started',
        '[droppable: 2] dropped Cancelled(manual)',
        'state: Special(droppable: 1)',
        '[droppable: 1] finished Done(null)',
      ]);
    });
  });

  test('droppable by queue finds the job running between noops', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      noop(solo, 1);
      final first = droppableByQueue(solo, 1);
      noop(solo, 2);
      async.elapse(const Duration(milliseconds: 50));
      final second = droppableByQueue(solo, 2);
      noop(solo, 3);
      expect(identical(first, second), isTrue);
      async.flushTimers();
      expect((solo.state as Special).droppableCount, 1);
      expect(journal.take(), [
        '[noop: 1] started',
        'state: Special(noop: 1)',
        '[noop: 1] finished Done(null)',
        '[droppable: 1] started',
        '[droppable: 2] dropped Cancelled(manual)',
        'state: Special(noop: 1, droppable: 1)',
        '[droppable: 1] finished Done(null)',
        '[noop: 2] started',
        'state: Special(noop: 2, droppable: 1)',
        '[noop: 2] finished Done(null)',
        '[noop: 3] started',
        'state: Special(noop: 3, droppable: 1)',
        '[noop: 3] finished Done(null)',
      ]);
    });
  });

  test('droppable by queue after a long pause runs both', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      final first = droppableByQueue(solo, 1);
      async.elapse(const Duration(milliseconds: 150));
      final second = droppableByQueue(solo, 2);
      expect(identical(first, second), isFalse);
      async.flushTimers();
      expect((solo.state as Special).droppableCount, 2);
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

  test('droppable by queue after a long pause runs both with noops', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      noop(solo, 1);
      final first = droppableByQueue(solo, 1);
      noop(solo, 2);
      async.elapse(const Duration(milliseconds: 150));
      final second = droppableByQueue(solo, 2);
      noop(solo, 3);
      expect(identical(first, second), isFalse);
      async.flushTimers();
      expect((solo.state as Special).droppableCount, 2);
      expect(journal.take(), [
        '[noop: 1] started',
        'state: Special(noop: 1)',
        '[noop: 1] finished Done(null)',
        '[droppable: 1] started',
        'state: Special(noop: 1, droppable: 1)',
        '[droppable: 1] finished Done(null)',
        '[noop: 2] started',
        'state: Special(noop: 2, droppable: 1)',
        '[noop: 2] finished Done(null)',
        '[droppable: 2] started',
        'state: Special(noop: 2, droppable: 2)',
        '[droppable: 2] finished Done(null)',
        '[noop: 3] started',
        'state: Special(noop: 3, droppable: 2)',
        '[noop: 3] finished Done(null)',
      ]);
    });
  });

  test('restart by queue drops the queued job with the key', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      restartableByQueue(solo, 1);
      restartableByQueue(solo, 2);
      async.flushTimers();
      expect((solo.state as Special).restartableCount, 2);
      expect(journal.take(), [
        '[restartable: 1] dropped Cancelled(manual)',
        '[restartable: 2] started',
        'state: Special(restartable: 1)',
        'state: Special(restartable: 2)',
        '[restartable: 2] finished Done(null)',
      ]);
    });
  });

  test('restart by queue drops the queued job, noops keep going', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      noop(solo, 1);
      restartableByQueue(solo, 1);
      noop(solo, 2);
      restartableByQueue(solo, 2);
      noop(solo, 3);
      async.flushTimers();
      expect((solo.state as Special).restartableCount, 2);
      expect(journal.take(), [
        '[restartable: 1] dropped Cancelled(manual)',
        '[noop: 1] started',
        'state: Special(noop: 1)',
        '[noop: 1] finished Done(null)',
        '[noop: 2] started',
        'state: Special(noop: 2)',
        '[noop: 2] finished Done(null)',
        '[restartable: 2] started',
        'state: Special(noop: 2, restartable: 1)',
        'state: Special(noop: 2, restartable: 2)',
        '[restartable: 2] finished Done(null)',
        '[noop: 3] started',
        'state: Special(noop: 3, restartable: 2)',
        '[noop: 3] finished Done(null)',
      ]);
    });
  });

  test('restart by queue cancels the running job without waiting', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      restartableByQueue(solo, 1);
      async.elapse(const Duration(milliseconds: 50));
      final second = restartableByQueue(solo, 2);
      expect(second.isQueued, isTrue);
      expect(solo.current!.isCancelled, isTrue);
      async.flushTimers();
      expect((solo.state as Special).restartableCount, 3);
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

  test('restart by queue cancels the running job between noops', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      noop(solo, 1);
      restartableByQueue(solo, 1);
      noop(solo, 2);
      async.elapse(const Duration(milliseconds: 50));
      restartableByQueue(solo, 2);
      noop(solo, 3);
      async.flushTimers();
      expect((solo.state as Special).restartableCount, 3);
      expect(journal.take(), [
        '[noop: 1] started',
        'state: Special(noop: 1)',
        '[noop: 1] finished Done(null)',
        '[restartable: 1] started',
        'state: Special(noop: 1, restartable: 1)',
        '[restartable: 1] finished Cancelled(manual)',
        '[noop: 2] started',
        'state: Special(noop: 2, restartable: 1)',
        '[noop: 2] finished Done(null)',
        '[restartable: 2] started',
        'state: Special(noop: 2, restartable: 2)',
        'state: Special(noop: 2, restartable: 3)',
        '[restartable: 2] finished Done(null)',
        '[noop: 3] started',
        'state: Special(noop: 3, restartable: 3)',
        '[noop: 3] finished Done(null)',
      ]);
    });
  });

  test('restart by queue after a long pause runs both to the end', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      restartableByQueue(solo, 1);
      async.elapse(const Duration(milliseconds: 150));
      restartableByQueue(solo, 2);
      async.flushTimers();
      expect((solo.state as Special).restartableCount, 4);
      expect(journal.take(), [
        '[restartable: 1] started',
        'state: Special(restartable: 1)',
        'state: Special(restartable: 2)',
        '[restartable: 1] finished Done(null)',
        '[restartable: 2] started',
        'state: Special(restartable: 3)',
        'state: Special(restartable: 4)',
        '[restartable: 2] finished Done(null)',
      ]);
    });
  });

  test('restart by queue after a long pause runs both with noops', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      noop(solo, 1);
      restartableByQueue(solo, 1);
      noop(solo, 2);
      async.elapse(const Duration(milliseconds: 150));
      restartableByQueue(solo, 2);
      noop(solo, 3);
      async.flushTimers();
      expect((solo.state as Special).restartableCount, 4);
      expect(journal.take(), [
        '[noop: 1] started',
        'state: Special(noop: 1)',
        '[noop: 1] finished Done(null)',
        '[restartable: 1] started',
        'state: Special(noop: 1, restartable: 1)',
        'state: Special(noop: 1, restartable: 2)',
        '[restartable: 1] finished Done(null)',
        '[noop: 2] started',
        'state: Special(noop: 2, restartable: 2)',
        '[noop: 2] finished Done(null)',
        '[restartable: 2] started',
        'state: Special(noop: 2, restartable: 3)',
        'state: Special(noop: 2, restartable: 4)',
        '[restartable: 2] finished Done(null)',
        '[noop: 3] started',
        'state: Special(noop: 3, restartable: 4)',
        '[noop: 3] finished Done(null)',
      ]);
    });
  });
}
