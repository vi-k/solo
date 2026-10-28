@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

void addTyped(TestSolo solo) {
  solo
    ..enqueue<Initial, void>(key: 'test1', (ctx) async {})
    ..enqueue<Preparing, void>(key: 'test2', (ctx) async {})
    ..enqueue<Working, void>(key: 'test3', (ctx) async {});
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
      solo.enqueue<TestState, void>(key: 'any', (ctx) async {});
      async.flushMicrotasks();
      expect(journal.take(), ['[any] started', '[any] finished Done(null)']);
    });
  });

  test('canStart false drops the job before start', () {
    runSolo((solo, journal, async) {
      final job = solo.enqueue<Initial, void>(
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

  test('a job taken from the queue is no longer queued in canStart', () {
    runSolo((solo, journal, async) {
      bool? queuedInCanStart;
      late final SoloJob<void> job;
      job = solo.job<TestState, void>(
        key: 'job',
        canStart: (state) {
          queuedInCanStart = job.isQueued;
          return true;
        },
        (ctx) => delay(10),
      );
      solo.enqueueJob(job);
      expect(job.isQueued, isTrue, reason: 'queued until the pump runs');
      async.flushTimers();
      expect(queuedInCanStart, isFalse);
    });
  });

  test('keepWhile false at start drops the job before start', () {
    runSolo(initialState: const Preparing(progress: 100), (
      solo,
      journal,
      async,
    ) {
      solo.enqueue<Preparing, void>(
        key: 'kept',
        keepWhile: (state) => state.progress < 100,
        (ctx) async {},
      );
      async.flushMicrotasks();
      expect(journal.take(), ['[kept] dropped Cancelled(rules: keepWhile)']);
    });
  });

  test('a state canStart writes is held to W and keepWhile', () {
    runSolo((solo, journal, async) {
      var asked = 0;
      var ran = false;
      solo.enqueue<Initial, void>(
        key: 'moved',
        canStart: (state) {
          asked++;
          solo.externalSetState(const Preparing());
          return true;
        },
        (ctx) async => ran = true,
      );
      solo.enqueue<Preparing, void>(
        key: 'kept',
        canStart: (state) {
          asked++;
          solo.externalSetState(const Preparing(progress: 100));
          return true;
        },
        keepWhile: (state) => state.progress < 100,
        (ctx) async => ran = true,
      );
      async.flushMicrotasks();
      expect(journal.take(), [
        'state: Preparing(progress: 0)',
        '[moved] dropped Cancelled(rules: is not Initial)',
        'state: Preparing(progress: 100)',
        '[kept] dropped Cancelled(rules: keepWhile)',
      ]);
      expect(ran, isFalse);
      expect(asked, 2, reason: 'canStart is asked once a job');
    });
  });

  // A change asks every running job's `keepWhile` again, so a rule that
  // writes the state asks itself again, and one that writes every time it
  // is asked never comes back. The write throws instead, and the rule
  // throws with it, as any rule that throws.
  const refused =
      'Bad state: Cannot set the state of TestSolo while a '
      'keepWhile is answering; a rule answers about the state, it does not '
      'change it';

  test('a keepWhile that writes the state at the start is refused', () {
    runSolo((solo, journal, async) {
      final ran = <String>[];
      final root = solo.job<Initial, void>(
        key: 'root',
        keepWhile: (state) {
          solo.externalSetState(const Preparing());
          return true;
        },
        (ctx) async => ran.add('root'),
      )..ignoreFailure();
      solo.enqueueJob(root);
      async.flushTimers();
      solo.enqueue<TestState, void>(key: 'parent', (ctx) async {
        final child = solo.job<Initial, void>(
          key: 'child',
          keepWhile: (state) {
            solo.externalSetState(const Preparing(progress: 1));
            return true;
          },
          (childCtx) async => ran.add('child'),
        )..ignoreFailure();
        ctx.run(child).ignore();
        await child.done;
      }).ignoreFailure();
      async.flushTimers();
      expect(journal.take(), [
        '[root] error $refused',
        '[root] finished Failed($refused)',
        '[parent] started',
        '> [child] error $refused',
        '> [child] finished Failed($refused)',
        // A start rule of a child that throws is handed to the parent's
        // body, by `run` itself.
        '[parent] error $refused',
        '[parent] finished Failed($refused)',
      ]);
      expect(ran, isEmpty);
      expect(solo.currentState, const Initial());
    });
  });

  test('a keepWhile that writes on every change is refused once a change', () {
    runSolo((solo, journal, async) {
      var armed = false;
      var written = 0;
      solo.enqueue<TestState, void>(
        key: 'restless',
        keepWhile: (state) {
          if (armed) {
            solo.externalSetState(Preparing(progress: ++written));
          }
          return true;
        },
        (ctx) => pause(ctx, 100),
      );
      async.flushMicrotasks();
      armed = true;
      solo.externalSetState(const Preparing());
      async.flushTimers();
      expect(journal.take(), [
        '[restless] started',
        'state: Preparing(progress: 0)',
        '[restless] error $refused',
        '[restless] unanswered $refused',
        '[restless] finished Done(null)',
      ]);
      expect(written, 1, reason: 'one attempt, and no state from it');
      expect(solo.currentState, const Preparing());
    });
  });

  test('a keepWhile that writes the state from a read fails the read', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      Object? caught;
      var armed = false;
      solo.enqueue<Preparing, void>(
        key: 'reader',
        keepWhile: (state) {
          if (armed) {
            armed = false;
            solo.externalSetState(const Preparing(progress: 7));
          }
          return true;
        },
        (ctx) async {
          armed = true;
          try {
            ctx.state;
          } on Object catch (error) {
            caught = error;
          }
        },
      );
      async.flushTimers();
      expect(caught, isStateError);
      expect(solo.currentState, const Preparing());
    });
  });

  test('the type is checked before canStart', () {
    runSolo((solo, journal, async) {
      var called = false;
      solo.enqueue<Working, void>(
        key: 'typed',
        canStart: (state) {
          called = true;
          return true;
        },
        (ctx) async {},
      );
      async.flushMicrotasks();
      expect(journal.take(), [
        '[typed] dropped Cancelled(rules: is not Working)',
      ]);
      expect(called, isFalse);
    });
  });

  test('a dropped job is reported to onFinish with no onStart', () {
    runSolo((solo, journal, async) {
      final job = solo.enqueue<Working, void>(key: 'x', (ctx) async {});
      Outcome<void>? outcome;
      job.done.then((o) => outcome = o);
      async.flushMicrotasks();
      expect(outcome, isA<Cancelled>());
      expect(journal.take(), ['[x] dropped Cancelled(rules: is not Working)']);
    });
  });
  test('a start rule that throws does not stall the queue', () {
    runSolo((solo, journal, async) {
      // The rule is the caller's code: it may throw the way any code does,
      // and the job it was asked about is already out of the queue.
      final first = solo.job<Initial, void>(
        key: 'first',
        canStart: (state) => throw StateError('rule boom'),
        (ctx) async {},
      )..ignoreFailure();
      final next = solo.job<Initial, void>(key: 'next', (ctx) async {});
      solo
        ..enqueueJob(first)
        ..enqueueJob(next);
      async.flushTimers();
      expect(first.outcome, isA<Failed>());
      expect(next.outcome, isA<Done<void>>());
      expect(journal.take(), [
        '[first] error Bad state: rule boom',
        '[first] finished Failed(Bad state: rule boom)',
        '[next] started',
        '[next] finished Done(null)',
      ]);
    });
  });

  // The job is over by the time the rule throws, so there is no outcome to
  // carry the error; the observer still hears it, once.
  for (final how in ['close', 'cancel', 'cancelAll']) {
    test('a start rule that calls $how and then throws is heard', () {
      runSolo((solo, journal, async) {
        late SoloJob<void> job;
        job = solo.job<Initial, void>(
          key: 'x',
          canStart: (state) {
            switch (how) {
              case 'close':
                solo.close();
              case 'cancel':
                job.cancel().ignore();
              case 'cancelAll':
                solo.cancelAll();
            }
            throw StateError('rule boom');
          },
          (ctx) async {},
        );
        solo.enqueueJob(job);
        async.flushTimers();
        expect(job.outcome, isA<Cancelled>());
        expect(
          journal.take().where(
            (line) => line == '[x] error Bad state: rule boom',
          ),
          hasLength(1),
        );
      });
    });
  }

  test('a keep rule that throws does not stop the reevaluation', () {
    runSolo((solo, journal, async) {
      // It holds at the state the job started in and throws at the next
      // one: the throw happens in the reevaluation, not in the pump.
      final thrower = solo.job<TestState, void>(
        key: 'thrower',
        keepWhile: (state) =>
            state is Preparing ? throw StateError('keep boom') : true,
        (ctx) async => pause(ctx, 100),
      );
      final other = solo.job<TestState, void>(
        key: 'other',
        keepWhile: (state) => state is! Preparing,
        (ctx) async => pause(ctx, 100),
      );
      solo
        ..enqueueJob(thrower)
        ..enqueueJob(other);
      async.elapse(const Duration(milliseconds: 10));
      solo.externalSetState(const Preparing());
      async.flushTimers();
      expect(journal.take().where((line) => line.contains('error')).toList(), [
        '[thrower] error Bad state: keep boom',
      ]);
      expect(
        other.outcome,
        isA<Cancelled>(),
        reason: 'the job behind the thrower was still looked at',
      );
    });
  });
  test('cancelAll from a start rule reaches the job the pump holds', () {
    runSolo((solo, journal, async) {
      // The window between the queue and the start: the job is in the
      // pump's hands, in no list of the controller, and about to run.
      final held = solo.job<Initial, void>(
        key: 'held',
        canStart: (state) {
          solo.cancelAll().ignore();

          return true;
        },
        (ctx) async {},
      );
      final next = solo.job<Initial, void>(key: 'next', (ctx) async {});
      solo
        ..enqueueJob(held)
        ..enqueueJob(next);
      async.flushTimers();
      expect(held.outcome, isA<Cancelled>());
      expect(
        (held.outcome! as Cancelled).started,
        isFalse,
        reason: 'it was stopped before it ran a line',
      );
      expect(next.outcome, isA<Cancelled>());
      expect(
        journal.take().where((line) => line.contains('started')),
        isEmpty,
        reason: 'the cancelled everything included what was about to start',
      );
    });
  });

  test('a cancellable: false job the pump holds turns cancelAll down', () {
    runSolo((solo, journal, async) {
      // Queued work until it is launched, so the refusal a queued one
      // makes is the refusal this one makes.
      final stubborn = solo.job<Initial, void>(
        key: 'stubborn',
        cancellable: false,
        canStart: (state) {
          solo.cancelAll().ignore();

          return true;
        },
        (ctx) async {},
      );
      solo.enqueueJob(stubborn);
      async.flushTimers();
      expect(stubborn.outcome, isA<Done<void>>());
      expect(journal.take(), [
        '[stubborn] started',
        '[stubborn] finished Done(null)',
      ]);
    });
  });

  test('a job put back from a hook is refused, and the queue goes on', () {
    // The first thing anyone writes in a retry hook. The job the hook sees is
    // out of the queue, not started and not yet finished, and `enqueueJob` used
    // to read that state as "never added".
    Object? refused;
    Solo.observer = _Retrier((solo, job) {
      try {
        (solo as TestSolo).enqueueJob(job);
      } on Object catch (error) {
        refused = error;
      }
    });
    addTearDown(() => Solo.observer = null);
    fakeAsync((async) {
      final solo = TestSolo();
      var asked = 0;
      final first = solo.job<Initial, void>(
        key: 'first',
        // Throws once, the way a transient fault does: the retry the hook
        // asks for would then get through.
        canStart: (state) =>
            ++asked == 1 ? throw StateError('rule boom') : true,
        (ctx) async {},
      )..ignoreFailure();
      final second = solo.job<Initial, void>(key: 'second', (ctx) async {});
      solo
        ..enqueueJob(first)
        ..enqueueJob(second);
      async.flushTimers();
      expect(refused, isA<StateError>());
      expect(first.outcome, isA<Failed>());
      expect(
        second.outcome,
        isA<Done<void>>(),
        reason: 'the queue did not stall behind the job the hook put back',
      );
      expect(solo.current, isNull);
      solo.close();
      async.flushTimers();
    });
  });
  test('a child whose own rule puts it in the queue is refused', () {
    runSolo((solo, journal, async) {
      // The child's rule runs while the parent is adopting it: the handle
      // is taken, but nothing had said so yet.
      Object? refused;
      late SoloJob<void> child;
      child = solo.job<Initial, void>(
        key: 'child',
        canStart: (state) {
          try {
            solo.enqueueJob(child);
          } on Object catch (error) {
            refused = error;
          }

          return true;
        },
        (ctx) async {},
      );
      solo.enqueue<Initial, void>(key: 'parent', (ctx) async {
        ctx.run(child).ignore();
        await pause(ctx, 10);
      });
      async.flushTimers();
      expect(refused, isA<StateError>());
      expect(child.isQueued, isFalse);
      expect(solo.current, isNull);
      expect(child.outcome, isA<Done<void>>());
    });
  });

  test('a child whose own rule runs it again is refused', () {
    runSolo((solo, journal, async) {
      // The second adoption comes while the first one asks the child's
      // rule: the handle is taken, and a second start would run the child
      // with nobody waiting for it.
      Object? refused;
      var released = 0;
      var reentered = false;
      final trace = <String>[];
      late SoloJob<void> child;
      solo.enqueue<Initial, void>(key: 'parent', (ctx) async {
        child = solo.job<Initial, void>(
          key: 'child',
          canStart: (state) {
            if (!reentered) {
              reentered = true;
              try {
                ctx.run(child).ignore();
              } on Object catch (error) {
                refused = error;
              }
            }
            return true;
          },
          (childCtx) async {
            trace.add('child started');
            childCtx.onDispose(() => released++);
            await pause(childCtx, 10);
            trace.add('child returned');
          },
        );
        await ctx.run(child);
        trace.add('parent past the child');
      });
      solo.enqueue<Initial, void>(
        key: 'next',
        (ctx) async => trace.add('next started'),
      );
      async.flushTimers();
      expect(refused, isA<StateError>());
      expect(trace, [
        'child started',
        'child returned',
        'parent past the child',
        'next started',
      ]);
      expect(released, 1);
      expect(child.outcome, isA<Done<void>>());
    });
  });

  test('a rule that closes the controller does not let the job start', () {
    runSolo((solo, journal, async) {
      final job = solo.job<Initial, void>(
        key: 'closer',
        canStart: (state) {
          solo.close();

          return true;
        },
        (ctx) async {},
      );
      solo.enqueueJob(job);
      async.flushTimers();
      expect(
        job.outcome,
        isA<Cancelled>(),
        reason: 'the controller closed while the rule was being asked',
      );
      expect(
        journal.take().where((line) => line.contains('started')).toList(),
        isEmpty,
      );
    });
  });

  test('a job put back from a policy hook is refused', () {
    runSolo((solo, journal, async) {
      // `replace` drops the job that was queued, and its finish hook runs
      // while the incoming one is on its way into the queue.
      Object? refused;
      var once = true;
      late SoloJob<void> incoming;
      Solo.observer = _Retrier((solo, job) {
        if (once && job.key == 'old') {
          once = false;
          try {
            (solo as TestSolo).enqueueJob(incoming);
          } on Object catch (error) {
            refused = error;
          }
        }
      }, alsoOnFinish: true);
      solo
        ..enqueue<Initial, void>(key: 'blocker', (ctx) async => pause(ctx, 50))
        ..enqueueJob(solo.job<Initial, void>(key: 'old', (ctx) async {}));
      incoming = solo.job<Initial, void>(key: 'old', (ctx) async {});
      solo.enqueueJob(incoming, policy: Policy.replace);
      async.flushTimers();
      expect(refused, isA<StateError>());
      expect(solo.queue.length, 0);
      expect(solo.current, isNull);
    });
  });

  test('a start rule that gives its own job up lets the queue move on', () {
    runSolo((solo, journal, async) {
      late final SoloJob<void> first;
      first = solo.enqueue<TestState, void>(
        key: 'first',
        canStart: (state) {
          first.cancel().ignore();
          return true;
        },
        (ctx) async {},
      );
      final second = solo.enqueue<TestState, void>(
        key: 'second',
        (ctx) async {},
      );
      async.flushTimers();
      expect(first.outcome, isA<Cancelled>());
      expect(second.outcome, isA<Done<void>>(), reason: 'the queue moved on');
      expect(solo.current, isNull);
      expect(journal.take(), contains('[second] started'));
    });
  });

  for (final answer in [true, false]) {
    test('a child whose own start rule gives it up and says $answer '
        'reaches its parent as its cancellation', () {
      runSolo((solo, journal, async) {
        var ran = false;
        late final SoloJob<void> child;
        child = solo.job<TestState, void>(
          key: 'child',
          canStart: (state) {
            child.cancel().ignore();
            return answer;
          },
          (ctx) async => ran = true,
        );
        Object? caught;
        final parent = solo.enqueue<TestState, void>(key: 'parent', (
          ctx,
        ) async {
          try {
            await ctx.run(child);
          } on Object catch (error) {
            caught = error;
          }
        });
        async.flushTimers();
        expect(ran, isFalse);
        expect(
          child.outcome,
          isA<Cancelled>().having(
            (cancelled) => cancelled.reason,
            'reason',
            isA<ManualCancelReason>(),
          ),
        );
        expect(caught, same(child.outcome), reason: 'not a StateError');
        expect(parent.outcome, isA<Done<void>>());
      });
    });
  }

  test('a keepWhile that gives the job up stops the next action', () {
    runSolo((solo, journal, async) {
      var started = 0;
      var armed = false;
      late final SoloJob<void> job;
      job = solo.enqueue<TestState, void>(
        key: 'job',
        keepWhile: (state) {
          if (armed) {
            armed = false;
            job.cancel().ignore();
          }
          return true;
        },
        (ctx) async {
          armed = true;
          await ctx.abandonable(() async => started++);
        },
      );
      async.flushTimers();
      expect(started, 0, reason: 'the checkpoint threw before the action');
      expect(job.outcome, isA<Cancelled>());
    });
  });
}

/// Runs [_onError] from the observer's error hook.
final class _Retrier extends SoloObserver {
  final void Function(Solo<Object> solo, Job<Object?> job) _onError;
  final bool alsoOnFinish;

  _Retrier(this._onError, {this.alsoOnFinish = false});

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    if (alsoOnFinish) {
      _onError(solo, job);
    }
  }

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => _onError(solo, job);
}
