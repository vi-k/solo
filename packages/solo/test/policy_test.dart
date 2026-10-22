@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

SoloJob<void> droppable(TestSolo solo, int n) => solo.enqueue<Special, void>(
      key: 'droppable',
      describe: () => '$n',
      policy: Policy.droppable,
      (ctx) async {
        await delay(100);
        final count = ctx.state.droppableCount + 1;
        ctx.emit(ctx.state.copyWith(droppableCount: count));
      },
    );

SoloJob<void> restartable(TestSolo solo, int n) => solo.enqueue<Special, void>(
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

SoloJob<void> replaceable(TestSolo solo, int n) => solo.enqueue<Special, void>(
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
        '[droppable: 2] dropped Cancelled(duplicate)',
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
        '[droppable: 2] dropped Cancelled(duplicate)',
        'state: Special(droppable: 1)',
        '[droppable: 1] finished Done(null)',
      ]);
    });
  });

  test('a duplicate ends with a reason of its own, not a manual cancel', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      final first = droppable(solo, 1);
      final mine = solo.job<Special, void>(key: 'droppable', (ctx) async {});
      final taken = solo.enqueueJob(mine, policy: Policy.droppable);
      expect(identical(taken, first), isTrue);
      expect(
        mine.outcome,
        isA<Cancelled>()
            .having((c) => c.reason, 'reason', isA<DuplicateCancelReason>())
            // One of the engine's own reasons, beside `rules` and `closed`.
            .having((c) => c.reason, 'reason', isA<SoloCancelReason>())
            .having((c) => c.reason.name, 'name', 'duplicate')
            .having((c) => c.description, 'description', isNull)
            .having((c) => c.started, 'started', isFalse),
      );

      // The cancel from outside is the one that stays manual.
      unawaited(first.cancel());
      async.flushTimers();
      expect(
        first.outcome,
        isA<Cancelled>()
            .having((c) => c.reason, 'reason', isA<ManualCancelReason>()),
      );
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
        '[replace: 2] dropped Cancelled(replaced)',
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
        '[restartable: 1] dropped Cancelled(replaced)',
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
        '[restartable: 1] finished Cancelled(replaced)',
        '[restartable: 2] started',
        'state: Special(restartable: 2)',
        'state: Special(restartable: 3)',
        '[restartable: 2] finished Done(null)',
      ]);
    });
  });

  test('droppable does not hand back the cancelled current job', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      final first = droppable(solo, 1);
      async.elapse(const Duration(milliseconds: 50));
      solo.cancelAll();
      // `_current` stays filled for the whole unwinding, and the job in it
      // will never do the work: the caller of the second `droppable` would
      // get a handle that ends `Cancelled` for a request just made.
      expect(first.isCancelled, isTrue);
      expect(first.isFinished, isFalse);

      final second = droppable(solo, 2);
      expect(identical(first, second), isFalse);
      expect(
        solo.lastJobWhere((job) => identical(job, first)),
        isNull,
        reason: 'the same rule answers a subclass',
      );

      async.flushTimers();
      expect(first.outcome, isA<Cancelled>());
      expect(second.outcome, isA<Done<void>>());
      expect(journal.take(), [
        '[droppable: 1] started',
        '[droppable: 1] finished Cancelled(manual)',
        '[droppable: 2] started',
        'state: Special(droppable: 1)',
        '[droppable: 2] finished Done(null)',
      ]);
    });
  });

  test('droppable does not hand back the job a handler is finishing', () {
    runSolo(initialState: const Special(), (solo, journal, async) {
      SoloJob<void>? second;
      // The outcome is set before the state handlers run, and the job is
      // let go of only after them: in here it is finished and still
      // current. A retry from a handler is a new request, not this one
      // handed back with its failure already in it.
      final first = solo.enqueue<Special, void>(
        key: 'droppable',
        describe: () => '1',
        policy: Policy.droppable,
        ifFailed: (state, error, stackTrace) {
          second = droppable(solo, 2);

          return state;
        },
        (ctx) async {
          await delay(50);
          throw StateError('boom');
        },
      );
      // Nobody is waiting for a job that exists to fail, and an
      // unobserved failure reaches the zone of the test.
      first.value.then<void>((_) {}, onError: (Object _) {});
      async.flushTimers();

      expect(first.outcome, isA<Failed>());
      expect(identical(first, second), isFalse);
      expect(second!.outcome, isA<Done<void>>());
    });
  });

  test('droppable refuses a key held by another result type', () {
    runSolo((solo, journal, async) {
      final first = solo.enqueue<TestState, int>(
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
        () => solo.enqueue<TestState, String>(
          key: 'shared',
          policy: Policy.droppable,
          (ctx) async => 'x',
        ),
        throwsA(
          isA<ArgumentError>()
              .having(
                (error) => error.message,
                'message',
                // Both types, or the reader learns nothing about the job
                // already holding the key.
                'key shared is held by a job of result type int, not String',
              )
              .having(
                (error) => '$error',
                'text',
                // The job by its key, not by the class of the engine.
                endsWith('not String: "Job(shared)"'),
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
      final first = solo.enqueue<TestState, int>(
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
        () => solo.enqueueJob(refused, policy: Policy.droppable),
        throwsArgumentError,
      );
      expect(
        journal.lines,
        isEmpty,
        reason: 'the refused job is not buried on the way out',
      );

      // And it is untouched: the same handle still goes into the queue.
      expect(refused.outcome, isNull);
      expect(identical(solo.enqueueJob(refused), refused), isTrue);

      async.flushTimers();
      expect(first.outcome, isA<Done<int>>());
      expect(refused.outcome, isA<Done<void>>());
    });
  });

  test('droppable refuses a key held by a job of a narrower type', () {
    runSolo((solo, journal, async) {
      solo.enqueue<TestState, String>(
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
        () => solo.enqueue<TestState, Object>(
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
      final held = solo.enqueue<TestState, String>(
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
      final answer =
          solo.enqueueJob<Object>(incoming, policy: Policy.droppable);

      expect(identical(answer, held), isTrue);
      async.flushTimers();
      expect(held.outcome, isA<Done<String>>());
    });
  });

  test('droppable compares result types, not the whole job', () {
    runSolo((solo, journal, async) {
      final held = solo.enqueue<TestState, void>(
        key: 'shared',
        policy: Policy.droppable,
        (ctx) async => delay(100),
      );
      async.flushMicrotasks();

      // A different working state under the same key, and the same result
      // type: one operation, so the second call gets the first job.
      final answer = solo.enqueue<Initial, void>(
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
          () => solo.enqueue<TestState, void>(policy: policy, (ctx) async {}),
          throwsArgumentError,
          reason: '$policy',
        );
      }
      expect(journal.lines, isEmpty);
    });
  });

  test('Policy has four values in spec order', () {
    expect(Policy.values, [
      Policy.sequential,
      Policy.droppable,
      Policy.replace,
      Policy.restart,
    ]);
  });

  test('droppable does not see a child running under the same key', () {
    runSolo((solo, journal, async) {
      final child = solo.job<TestState, void>(
        key: 'shared',
        (ctx) => pause(ctx, 100),
      );
      solo.enqueue<TestState, void>(key: 'parent', (ctx) => ctx.run(child));
      async.flushMicrotasks();
      expect(child.isRunning, isTrue);

      // The parent holds the queue, so the new root job waits there
      // rather than being handed the child.
      final root = solo.enqueue<TestState, void>(
        key: 'shared',
        policy: Policy.droppable,
        (ctx) async {},
      );
      expect(identical(root, child), isFalse);
      async.flushTimers();
      expect(root.outcome, isA<Done<void>>());
    });
  });

  group('a job whose start rules are being asked counts as queued', () {
    // Off the queue, not started, and not yet the current job: a rule of
    // it is the caller's code, and a call of the same key from in there
    // must find it, the way `pending` and `cancelAll` do.
    test('a droppable call from its rule gets it back', () {
      runSolo((solo, journal, async) {
        SoloJob<void>? fromRule;
        Job<Object?>? lastFromRule;
        late final SoloJob<void> first;
        first = solo.job<TestState, void>(
          key: 'k',
          describe: () => 'first',
          canStart: (state) {
            lastFromRule = solo.lastJobWhere((job) => job.key == 'k');
            fromRule = solo.enqueueJob(
              solo.job<TestState, void>(
                key: 'k',
                describe: () => 'second',
                (ctx) async {},
              ),
              policy: Policy.droppable,
            );
            return true;
          },
          (ctx) async {},
        );
        solo.enqueueJob(first, policy: Policy.droppable);
        async.flushTimers();
        expect(lastFromRule, same(first));
        expect(fromRule, same(first));
        expect(journal.take(), [
          '[k: second] dropped Cancelled(duplicate)',
          '[k: first] started',
          '[k: first] finished Done(null)',
        ]);
      });
    });

    for (final policy in [Policy.replace, Policy.restart]) {
      test('${policy.name} from its rule removes it before it starts', () {
        runSolo((solo, journal, async) {
          late final SoloJob<void> first;
          first = solo.job<TestState, void>(
            key: 'k',
            describe: () => 'first',
            canStart: (state) {
              solo.enqueueJob(
                solo.job<TestState, void>(
                  key: 'k',
                  describe: () => 'second',
                  (ctx) async {},
                ),
                policy: policy,
              );
              return true;
            },
            (ctx) async {},
          );
          solo.enqueueJob(first, policy: policy);
          async.flushTimers();
          expect(journal.take(), [
            '[k: first] dropped Cancelled(replaced)',
            '[k: second] started',
            '[k: second] finished Done(null)',
          ]);
        });
      });
    }

    test('a call of another key leaves it be', () {
      runSolo((solo, journal, async) {
        late final SoloJob<void> first;
        first = solo.job<TestState, void>(
          key: 'a',
          canStart: (state) {
            solo.enqueueJob(
              solo.job<TestState, void>(key: 'b', (ctx) async {}),
              policy: Policy.replace,
            );
            return true;
          },
          (ctx) async {},
        );
        solo.enqueueJob(first, policy: Policy.replace);
        async.flushTimers();
        expect(journal.take(), [
          '[a] started',
          '[a] finished Done(null)',
          '[b] started',
          '[b] finished Done(null)',
        ]);
      });
    });

    test('it stands ahead of what its rule has queued', () {
      runSolo((solo, journal, async) {
        SoloJob<void>? fromRule;
        late final SoloJob<void> queued;
        late final SoloJob<void> first;
        first = solo.job<TestState, void>(
          key: 'k',
          describe: () => 'first',
          canStart: (state) {
            queued = solo.enqueueJob(
              solo.job<TestState, void>(
                key: 'k',
                describe: () => 'queued',
                (ctx) async {},
              ),
            );
            fromRule = solo.enqueueJob(
              solo.job<TestState, void>(
                key: 'k',
                describe: () => 'third',
                (ctx) async {},
              ),
              policy: Policy.droppable,
            );
            return true;
          },
          (ctx) async {},
        );
        solo.enqueueJob(first, policy: Policy.droppable);
        async.flushTimers();
        // The queue is searched from its tail: the job the rule queued is
        // the last one of the key, and the one being started comes first.
        expect(fromRule, same(queued));
        expect(journal.take(), [
          '[k: third] dropped Cancelled(duplicate)',
          '[k: first] started',
          '[k: first] finished Done(null)',
          '[k: queued] started',
          '[k: queued] finished Done(null)',
        ]);
      });
    });

    test('one created cancellable: false refuses the removal', () {
      runSolo((solo, journal, async) {
        late final SoloJob<void> first;
        first = solo.job<TestState, void>(
          key: 'k',
          describe: () => 'first',
          cancellable: false,
          canStart: (state) {
            solo.enqueueJob(
              solo.job<TestState, void>(
                key: 'k',
                describe: () => 'second',
                (ctx) async {},
              ),
              policy: Policy.replace,
            );
            return true;
          },
          (ctx) async {},
        );
        solo.enqueueJob(first, policy: Policy.replace);
        async.flushTimers();
        expect(journal.take(), [
          '[k: first] started',
          '[k: first] finished Done(null)',
          '[k: second] started',
          '[k: second] finished Done(null)',
        ]);
      });
    });
  });

  // Cancelling a replaced job runs its code synchronously, inside the
  // `enqueueJob` that replaces it, and that code may ask for the same key
  // again. The job asked for last is the one that has to run last.
  group('a job queued from the code of a job it replaces', () {
    for (final policy in [Policy.replace, Policy.restart]) {
      for (final hook in ['onFinish', 'whenCancelled']) {
        for (final running in [
          false,
          if (policy == Policy.restart) true,
        ]) {
          final where = running ? 'running' : 'queued';
          // The `onFinish` of a running job comes after `enqueueJob` has
          // returned, so that variant never reaches the reentrant path; it
          // holds what was right before the order changed.
          test('${policy.name}, from $hook of a $where job, runs last', () {
            fakeAsync((async) {
              final solo =
                  _Rerequesting(policy, fromOnFinish: hook == 'onFinish');
              final a = solo.request('A');
              if (running) async.flushMicrotasks();
              if (hook == 'whenCancelled') {
                a.whenCancelled((_) => solo.request('C'));
              }
              final b = solo.request('B');
              async.flushTimers();
              expect(solo.requested, ['A', 'B', 'C']);
              expect(solo.started, [if (running) 'A', 'C']);
              expect(solo.currentState, 'C');
              expect(
                b.outcome,
                isA<Cancelled>().having(
                  (cancelled) => cancelled.reason,
                  'reason',
                  isA<ReplacedCancelReason>(),
                ),
              );
              unawaited(solo.close());
              async.flushTimers();
            });
          });
        }
      }
    }

    test('restart taken back by that code leaves the running job alone', () {
      fakeAsync((async) {
        final solo = _Rerequesting(Policy.restart, fromOnFinish: false);
        final a = solo.request('A');
        async.flushMicrotasks();
        solo
            .enqueue<String, void>(key: 'search', (ctx) async => ctx.emit('Q'))
            .whenCancelled((_) => solo.queue.clear());
        final b = solo.request('B');
        async.flushTimers();
        expect(
          b.outcome,
          isA<Cancelled>().having(
            (cancelled) => cancelled.reason,
            'reason',
            isA<ManualCancelReason>(),
          ),
        );
        expect(a.outcome, isA<Done<void>>());
        expect(solo.started, ['A']);
        expect(solo.currentState, 'A');
        unawaited(solo.close());
        async.flushTimers();
      });
    });
  });
}

final class _Rerequesting extends Solo<String> with OpenSolo<String> {
  final Policy policy;
  final bool fromOnFinish;
  final requested = <String>[];
  final started = <String>[];

  _Rerequesting(this.policy, {required this.fromOnFinish}) : super('');

  SoloJob<void> request(String value) {
    requested.add(value);
    return enqueue<String, void>(
      key: 'search',
      policy: policy,
      (ctx) async {
        started.add(value);
        if (value == 'A') await ctx.abandonable(() => delay(100));
        ctx.emit(value);
      },
    );
  }

  @override
  void onFinish(Job<Object?> job) {
    super.onFinish(job);
    if (fromOnFinish && requested.length == 2 && job.outcome is Cancelled) {
      request('C');
    }
  }
}
