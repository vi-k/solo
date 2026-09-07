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
      solo.add(job);
      expect(job.isQueued, isTrue, reason: 'queued until the pump runs');
      async.flushTimers();
      expect(queuedInCanStart, isFalse);
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
  test('a start rule that throws does not stall the queue', () {
    runSolo((solo, journal, async) {
      // The rule is the caller's code: it may throw the way any code does,
      // and the job it was asked about is already out of the queue.
      final first = solo.job<Initial, void>(
        key: 'first',
        canStart: (state) => throw StateError('rule boom'),
        (ctx) async {},
      )..ignore();
      final next = solo.job<Initial, void>(key: 'next', (ctx) async {});
      solo
        ..add(first)
        ..add(next);
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
        ..add(thrower)
        ..add(other);
      async.elapse(const Duration(milliseconds: 10));
      solo.externalSetState(const Preparing());
      async.flushTimers();
      expect(
        journal.take().where((line) => line.contains('error')).toList(),
        ['[thrower] error Bad state: keep boom'],
      );
      expect(
        other.outcome,
        isA<Cancelled>(),
        reason: 'the job behind the thrower was still looked at',
      );
    });
  });
  test('a job put back from a hook is refused, and the queue goes on', () {
    // The first thing anyone writes in a retry hook. The job the hook sees
    // is out of the queue, not started and not yet finished, and `add`
    // used to read that state as "never added".
    Object? refused;
    SoloBase.observer = _Retrier((solo, job) {
      try {
        solo.add(job);
      } on Object catch (error) {
        refused = error;
      }
    });
    addTearDown(() => SoloBase.observer = null);
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
      )..ignore();
      final second = solo.job<Initial, void>(key: 'second', (ctx) async {});
      solo
        ..add(first)
        ..add(second);
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
            solo.add(child);
          } on Object catch (error) {
            refused = error;
          }

          return true;
        },
        (ctx) async {},
      );
      solo.run<Initial, void>(key: 'parent', (ctx) async {
        ctx.run(child);
        await pause(ctx, 10);
      });
      async.flushTimers();
      expect(refused, isA<StateError>());
      expect(child.isQueued, isFalse);
      expect(solo.current, isNull);
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
      solo.add(job);
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
      SoloBase.observer = _Retrier(
        (solo, job) {
          if (once && job.key == 'old') {
            once = false;
            try {
              solo.add(incoming);
            } on Object catch (error) {
              refused = error;
            }
          }
        },
        alsoOnFinish: true,
      );
      solo
        ..run<Initial, void>(key: 'blocker', (ctx) async => pause(ctx, 50))
        ..add(
          solo.job<Initial, void>(key: 'old', (ctx) async {}),
        );
      incoming = solo.job<Initial, void>(key: 'old', (ctx) async {});
      solo.add(incoming, policy: Policy.replace);
      async.flushTimers();
      expect(refused, isA<StateError>());
      expect(solo.queue.length, 0);
      expect(solo.current, isNull);
    });
  });
}

/// Runs [_onError] from the observer's error hook.
final class _Retrier extends SoloObserver {
  final void Function(SoloBase<Object> solo, Job<Object?> job) _onError;
  final bool alsoOnFinish;

  _Retrier(this._onError, {this.alsoOnFinish = false});

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) {
    if (alsoOnFinish) {
      _onError(solo, job);
    }
  }

  @override
  void onError(
    SoloBase<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      _onError(solo, job);
}
