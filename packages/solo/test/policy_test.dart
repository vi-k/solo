@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

SoloJob<void> droppable(TestSolo solo, int n) => solo.run<Special, void>(
      key: 'droppable',
      describe: () => '$n',
      policy: Policy.droppable,
      (ctx) async {
        await delay(100);
        final count = ctx.state.droppableCount + 1;
        ctx.emit(ctx.state.copyWith(droppableCount: count));
      },
    );

SoloJob<void> restartable(TestSolo solo, int n) => solo.run<Special, void>(
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

SoloJob<void> replaceable(TestSolo solo, int n) => solo.run<Special, void>(
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

  test('droppable refuses a key held by another result type', () {
    runSolo((solo, journal, async) {
      final first = solo.run<TestState, int>(
        key: 'shared',
        policy: Policy.droppable,
        (ctx) async {
          await delay(100);

          return 1;
        },
      );
      async.flushMicrotasks();
      journal.take();
      expect(
        () => solo.run<TestState, String>(
          key: 'shared',
          policy: Policy.droppable,
          (ctx) async => 'x',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            // Both types, or the reader learns nothing about the job
            // already holding the key.
            'key shared is held by a job of result type int, not String',
          ),
        ),
      );
      expect(
        journal.lines,
        isEmpty,
        reason: 'the refused job is not buried on the way out',
      );
      async.flushTimers();
      expect(first.outcome, isA<Done<int>>());
    });
  });

  test('droppable refuses a void job for a key held by another type', () {
    runSolo((solo, journal, async) {
      final first = solo.run<TestState, int>(
        key: 'shared',
        policy: Policy.droppable,
        (ctx) async {
          await delay(100);

          return 1;
        },
      );
      async.flushMicrotasks();
      journal.take();
      // `void` is a top type, so an `is SoloJob<void>` would say yes to
      // this `Job<int>` and hand it back as the answer to a save that
      // never ran. The jobs are compared with each other instead.
      final refused = solo.job<TestState, void>(key: 'shared', (ctx) async {});
      expect(
        () => solo.add(refused, policy: Policy.droppable),
        throwsArgumentError,
      );
      expect(
        journal.lines,
        isEmpty,
        reason: 'the refused job is not buried on the way out',
      );

      // And it is untouched: the same handle still goes into the queue.
      expect(refused.outcome, isNull);
      expect(identical(solo.add(refused), refused), isTrue);

      async.flushTimers();
      expect(first.outcome, isA<Done<int>>());
      expect(refused.outcome, isA<Done<void>>());
    });
  });

  test('droppable refuses a key held by a job of a narrower type', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, String>(
        key: 'shared',
        policy: Policy.droppable,
        (ctx) async {
          await delay(100);

          return 'x';
        },
      );
      async.flushMicrotasks();
      journal.take();
      // A `Job<String>` is a `SoloJob<Object>`, so handing it back would
      // type-check — and the work of this job would be lost all the same.
      expect(
        () => solo.run<TestState, Object>(
          key: 'shared',
          policy: Policy.droppable,
          (ctx) async => 1,
        ),
        throwsArgumentError,
      );
      expect(journal.lines, isEmpty);
    });
  });

  test("droppable looks at the two jobs, not at the call's type argument", () {
    runSolo((solo, journal, async) {
      final held = solo.run<TestState, String>(
        key: 'shared',
        policy: Policy.droppable,
        (ctx) async {
          await delay(100);

          return 'x';
        },
      );
      async.flushMicrotasks();

      // The call writes `Object`, both jobs are `Job<String>`: the type
      // argument here is whatever the call site felt like and decides
      // nothing.
      final incoming =
          solo.job<TestState, String>(key: 'shared', (ctx) async => 'y');
      final answer = solo.add<Object>(incoming, policy: Policy.droppable);

      expect(identical(answer, held), isTrue);
      async.flushTimers();
      expect(held.outcome, isA<Done<String>>());
    });
  });

  test('droppable compares result types, not the whole job', () {
    runSolo((solo, journal, async) {
      final held = solo.run<TestState, void>(
        key: 'shared',
        policy: Policy.droppable,
        (ctx) async => delay(100),
      );
      async.flushMicrotasks();

      // A different working state under the same key, and the same result
      // type: one operation, so the second call gets the first job.
      final answer = solo.run<Initial, void>(
        key: 'shared',
        policy: Policy.droppable,
        (ctx) async {},
      );

      expect(identical(answer, held), isTrue);
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
