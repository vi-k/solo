@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/journal.dart';
import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('log lines carry the job level', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        ctx.log('hello');
        final child = solo.job<TestState, void>(key: 'child', (ctx) async {
          ctx.log(42);
        });
        await ctx.run(child).done;
      });
      async.flushTimers();
      expect(journal.take(), [
        '[parent] started',
        '[parent] log hello',
        '> [child] started',
        '> [child] log 42',
        '> [child] finished Done(null)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  test('the observer runs before each instance hook, super or not', () {
    fakeAsync((async) {
      final journal = JournalObserver();
      SoloBase.observer = journal;
      final solo = _Hooked(journal.lines);
      try {
        solo.run<TestState, void>(key: 'job', (ctx) async {
          ctx
            ..emit(const Preparing())
            ..log('x');
          throw StateError('boom');
        }).ignore();
        async.flushMicrotasks();
        expect(journal.take(), [
          '[job] started',
          'hook: start job',
          'state: Preparing(progress: 0)',
          'hook: change Preparing(progress: 0)',
          '[job] log x',
          'hook: log x',
          '[job] error Bad state: boom',
          'hook: error Bad state: boom',
          '[job] finished Failed(Bad state: boom)',
          'hook: finish job',
        ]);
      } finally {
        solo.close();
        async.flushTimers();
        SoloBase.observer = null;
      }
    });
  });

  test('a throwing onFinish hook still completes done', () {
    final journal = JournalObserver();
    final errors = <String>[];
    Outcome<void>? outcome;
    var closed = false;
    // The hook's error becomes an unhandled zone error; the zone keeps it
    // out of the test output and lets the assertions below name it.
    runZonedGuarded(
      () {
        fakeAsync((async) {
          SoloBase.observer = journal;
          final solo = _ThrowingFinish();
          try {
            solo
                .run<TestState, void>(key: 'job', (ctx) async {})
                .done
                .then((value) => outcome = value);
            async.flushMicrotasks();
            solo.close().then((_) => closed = true);
            async.flushTimers();
          } finally {
            SoloBase.observer = null;
          }
        });
      },
      (error, stackTrace) => errors.add('$error'),
    );
    expect(outcome, isA<Done<void>>());
    expect(closed, isTrue);
    expect(journal.take(), [
      '[job] started',
      '[job] finished Done(null)',
      'closed',
    ]);
    expect(errors, ['Bad state: onFinish']);
  });

  test('a throwing onClose observer still completes close', () {
    final errors = <String>[];
    var closed = false;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          SoloBase.observer = _ThrowingClose();
          final solo = Solo<TestState>(const Initial());
          try {
            solo.close().then((_) => closed = true);
            async.flushTimers();
          } finally {
            SoloBase.observer = null;
          }
        });
      },
      (error, stackTrace) => errors.add('$error'),
    );
    expect(closed, isTrue);
    expect(errors, ['Bad state: onClose']);
  });

  test('a throwing onFinish does not stall the queue', () {
    final journal = JournalObserver();
    final errors = <String>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          SoloBase.observer = journal;
          final solo = _ThrowingFinish();
          try {
            solo
              ..run<TestState, void>(key: 'first', (ctx) async {})
              ..run<TestState, void>(key: 'second', (ctx) async {});
            async.flushTimers();
          } finally {
            solo.close();
            async.flushTimers();
            SoloBase.observer = null;
          }
        });
      },
      (error, stackTrace) => errors.add('$error'),
    );
    expect(journal.take(), [
      '[first] started',
      '[first] finished Done(null)',
      '[second] started',
      '[second] finished Done(null)',
      'closed',
    ]);
    expect(errors, ['Bad state: onFinish', 'Bad state: onFinish']);
  });

  test('a throwing onFinish does not cut the drain of close', () {
    final journal = JournalObserver();
    final errors = <String>[];
    final outcomes = <Outcome<void>>[];
    var closed = false;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          SoloBase.observer = journal;
          final solo = _ThrowingFinish();
          try {
            // No pump between the adds and `close`: all three wait in the
            // queue and are dropped by the drain, one hook throw each.
            for (final key in ['a', 'b', 'c']) {
              solo
                  .run<TestState, void>(key: key, (ctx) async {})
                  .done
                  .then(outcomes.add);
            }
            solo.close().then((_) => closed = true);
            async.flushTimers();
          } finally {
            SoloBase.observer = null;
          }
        });
      },
      (error, stackTrace) => errors.add('$error'),
    );
    expect(closed, isTrue);
    expect(outcomes, hasLength(3));
    expect(journal.take(), [
      '[a] dropped Cancelled(closed)',
      '[b] dropped Cancelled(closed)',
      '[c] dropped Cancelled(closed)',
      'closed',
    ]);
    expect(errors, List.filled(3, 'Bad state: onFinish'));
  });

  test('a throwing onStart at ctx.run leaves the parent alone', () {
    final journal = JournalObserver();
    final errors = <String>[];
    Outcome<void>? parentOutcome;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          SoloBase.observer = journal;
          final solo = _ThrowingStart();
          try {
            solo
                .run<TestState, void>(key: 'parent', (ctx) async {
                  final child = solo.job<TestState, void>(
                    key: 'child',
                    (childCtx) async {},
                  );
                  await ctx.run(child).done;
                })
                .done
                .then((value) => parentOutcome = value);
            async.flushTimers();
          } finally {
            solo.close();
            async.flushTimers();
            SoloBase.observer = null;
          }
        });
      },
      (error, stackTrace) => errors.add('$error'),
    );
    expect(parentOutcome, isA<Done<void>>());
    expect(journal.take(), [
      '[parent] started',
      '> [child] started',
      '> [child] finished Done(null)',
      '[parent] finished Done(null)',
      'closed',
    ]);
    expect(errors, ['Bad state: onStart', 'Bad state: onStart']);
  });

  test('a throwing onChange still publishes and re-evaluates the rules', () {
    final errors = <String>[];
    final seen = <TestState>[];
    Outcome<void>? outcome;
    Duration? finishedAt;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final solo = _ThrowingChange();
          try {
            solo.stream.listen(seen.add);
            solo
                .run<Initial, void>(key: 'job', (ctx) async {
                  await pause(ctx, 100);
                })
                .done
                .then((value) {
                  outcome = value;
                  finishedAt = async.elapsed;
                });
            async.flushMicrotasks();
            solo.externalSetState(const Preparing());
            async.flushTimers();
          } finally {
            solo.close();
            async.flushTimers();
          }
        });
      },
      (error, stackTrace) => errors.add('$error'),
    );
    expect(seen, [const Preparing()], reason: 'publish ran after the hook');
    expect(outcome, isA<Cancelled>());
    expect(finishedAt, Duration.zero, reason: 'the rules were re-evaluated');
    expect(errors, ['Bad state: onChange']);
  });

  test('a throwing observer does not switch off the instance hook', () {
    final lines = <String>[];
    final errors = <String>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          SoloBase.observer = _ThrowingObserver();
          final solo = _Hooked(lines);
          try {
            solo.run<TestState, void>(key: 'job', (ctx) async {});
            async.flushTimers();
          } finally {
            solo.close();
            async.flushTimers();
            SoloBase.observer = null;
          }
        });
      },
      (error, stackTrace) => errors.add('$error'),
    );
    expect(lines, ['hook: start job', 'hook: finish job']);
    expect(errors, [
      'Bad state: observer onStart',
      'Bad state: observer onFinish',
    ]);
  });

  test('SoloBase.debug receives engine traces', () {
    final traces = <String>[];
    SoloBase.debug = traces.add;
    try {
      runSolo((solo, journal, async) {
        solo.run<TestState, void>(key: 'job', (ctx) async {
          ctx.emit(const Preparing());
        });
        async.flushMicrotasks();
      });
    } finally {
      SoloBase.debug = null;
    }
    expect(traces, contains('add Job(job)'));
    expect(traces, contains('Job(job) started'));
    expect(traces, contains('state: Preparing(progress: 0)'));
    expect(traces, contains('Job(job) finished: Done(null)'));
  });
}

/// Throws from the instance hook the engine calls while finishing a job.
final class _ThrowingFinish extends Solo<TestState> {
  _ThrowingFinish() : super(const Initial());

  @override
  void onFinish(Job<Object?> job) => throw StateError('onFinish');
}

/// Throws from the instance hook the engine calls before a job body.
final class _ThrowingStart extends Solo<TestState> {
  _ThrowingStart() : super(const Initial());

  @override
  void onStart(Job<Object?> job) => throw StateError('onStart');
}

/// Throws from the instance hook the engine calls on a state change.
final class _ThrowingChange extends Solo<TestState> {
  _ThrowingChange() : super(const Initial());

  @override
  void externalSetState(TestState state) => super.externalSetState(state);

  @override
  void onChange(TestState previous, TestState current) =>
      throw StateError('onChange');
}

/// Throws from the observer hooks around a job body.
final class _ThrowingObserver extends SoloObserver {
  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      throw StateError('observer onStart');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      throw StateError('observer onFinish');
}

/// Throws from the observer hook the engine calls while closing.
final class _ThrowingClose extends SoloObserver {
  @override
  void onClose(SoloBase<Object> solo) => throw StateError('onClose');
}

final class _Hooked extends Solo<TestState> {
  final List<String> lines;

  _Hooked(this.lines) : super(const Initial());

  @override
  void onStart(Job<Object?> job) => lines.add('hook: start ${job.key}');

  @override
  void onFinish(Job<Object?> job) => lines.add('hook: finish ${job.key}');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      lines.add('hook: error $error');

  @override
  void onLog(Job<Object?> job, String message) =>
      lines.add('hook: log $message');

  @override
  void onChange(TestState previous, TestState current) =>
      lines.add('hook: change $current');
}
