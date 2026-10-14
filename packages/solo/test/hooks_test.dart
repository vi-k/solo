@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/journal.dart';
import 'support/plain_solo.dart';
import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

void main() {
  test('log lines carry the job level', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        ctx.log('hello');
        final child = solo.job<TestState, void>(key: 'child', (ctx) async {
          ctx.log(42);
        });
        await ctx.run(child);
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
      Solo.observer = journal;
      final solo = _Hooked(journal.lines);
      try {
        solo.run<TestState, void>(key: 'job', (ctx) async {
          ctx
            ..emit(const Preparing())
            ..log('x');
          throw StateError('boom');
        }).ignoreFailure();
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
        Solo.observer = null;
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
          Solo.observer = journal;
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
            Solo.observer = null;
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
          Solo.observer = _ThrowingClose();
          final solo = PlainSolo<TestState>(const Initial());
          try {
            solo.close().then((_) => closed = true);
            async.flushTimers();
          } finally {
            Solo.observer = null;
          }
        });
      },
      (error, stackTrace) => errors.add('$error'),
    );
    expect(closed, isTrue);
    expect(errors, ['Bad state: onClose']);
  });

  test('onClose comes once, after the observer and after the last job', () {
    fakeAsync((async) {
      final journal = JournalObserver();
      Solo.observer = journal;
      final solo = _Closing(journal.lines);
      try {
        solo.run<TestState, void>(key: 'job', (ctx) async {
          await ctx.abandonable(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
        });
        async.flushMicrotasks();
        solo
          ..close(mode: SoloCloseMode.drain)
          ..close(mode: SoloCloseMode.drain);
        async.flushTimers();
        solo.close();
        async.flushTimers();

        expect(
          journal.take(),
          [
            '[job] started',
            '[job] finished Done(null)',
            'closed',
            'hook: close, finished false',
          ],
          reason: 'the drain ran its job first, and three calls are one close',
        );
      } finally {
        Solo.observer = null;
      }
    });
  });

  test('a close from inside onClose is the same close', () {
    fakeAsync((async) {
      final lines = <String>[];
      final solo = _Closing(lines, closeAgain: true);
      final closing = solo.close();
      async.flushTimers();

      expect(lines, ['hook: close, finished false']);
      expect(identical(solo.again, closing), isTrue);
    });
  });

  test('a state written from onClose is the state the controller keeps', () {
    fakeAsync((async) {
      final lines = <String>[];
      final solo = _Closing(lines, writeOnClose: const Preparing());
      final heard = <String>[];
      solo.addListener(() => heard.add('${solo.currentState}'));
      solo.close();
      async.flushTimers();

      expect(solo.isFinished, isTrue);
      expect(solo.currentState, const Preparing());
      expect(
        heard,
        ['Preparing(progress: 0)'],
        reason: 'the listeners are still there when the hook runs',
      );
    });
  });

  test('a throwing onClose hook still completes close', () {
    final errors = <String>[];
    var closed = false;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final solo = _ThrowingCloseHook();
          solo.close().then((_) => closed = true);
          async.flushTimers();
          expect(solo.isFinished, isTrue);
        });
      },
      (error, stackTrace) => errors.add('$error'),
    );
    expect(closed, isTrue);
    expect(errors, ['Bad state: onClose hook']);
  });

  test('a throwing onFinish does not stall the queue', () {
    final journal = JournalObserver();
    final errors = <String>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Solo.observer = journal;
          final solo = _ThrowingFinish();
          try {
            solo
              ..run<TestState, void>(key: 'first', (ctx) async {})
              ..run<TestState, void>(key: 'second', (ctx) async {});
            async.flushTimers();
          } finally {
            solo.close();
            async.flushTimers();
            Solo.observer = null;
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
          Solo.observer = journal;
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
            Solo.observer = null;
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
          Solo.observer = journal;
          final solo = _ThrowingStart();
          try {
            solo
                .run<TestState, void>(key: 'parent', (ctx) async {
                  final child = solo.job<TestState, void>(
                    key: 'child',
                    (childCtx) async {},
                  );
                  await ctx.run(child);
                })
                .done
                .then((value) => parentOutcome = value);
            async.flushTimers();
          } finally {
            solo.close();
            async.flushTimers();
            Solo.observer = null;
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
          Solo.observer = _ThrowingObserver();
          final solo = _Hooked(lines);
          try {
            solo.run<TestState, void>(key: 'job', (ctx) async {});
            async.flushTimers();
          } finally {
            solo.close();
            async.flushTimers();
            Solo.observer = null;
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

  test('a Cancelled a hook throws stays out of the zone', () {
    final lines = <String>[];
    final errors = <String>[];
    late Job<void> job;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final solo = _LazyLog(lines);
          job = solo.run<TestState, void>(key: 'job', (ctx) async {
            await delay(100);
            // The line is built where the hook reads it, and the job has
            // been cancelled by then: reading the state throws.
            ctx.log(() => 'state ${ctx.state}');
          });
          async.flushMicrotasks();
          job.cancel().ignore();
          async.flushTimers();
          solo.close();
          async.flushTimers();
        });
      },
      (error, stackTrace) => errors.add('$error'),
    );
    expect(lines, ['hook: log'], reason: 'the hook was called');
    expect(errors, isEmpty);
    expect('${job.outcome}', 'Cancelled(manual)');
  });

  test('a hook error is a cancellation only when all of it is', () {
    List<String> zoneOf(Object Function() thrown) {
      final errors = <String>[];
      runZonedGuarded(
        () {
          fakeAsync((async) {
            final solo = _ThrowingAtStart(thrown)
              ..run<TestState, void>(key: 'job', (ctx) async {});
            async.flushTimers();
            solo.close();
            async.flushTimers();
          });
        },
        (error, stackTrace) => errors.add('${error.runtimeType}'),
      );
      return errors;
    }

    AsyncError cancelled() =>
        AsyncError(const Cancelled('branch'), StackTrace.empty);
    AsyncError failed() => AsyncError(StateError('branch'), StackTrace.empty);

    expect(zoneOf(() => const Cancelled('hook')), isEmpty);
    expect(
      zoneOf(
        () => ParallelWaitError<List<Object?>, List<AsyncError?>>(
          const [null, null],
          [cancelled(), cancelled()],
        ),
      ),
      isEmpty,
      reason: 'nothing but cancellations inside',
    );
    expect(
      zoneOf(
        () => ParallelWaitError<List<Object?>, List<AsyncError?>>(
          const [null, null],
          [cancelled(), failed()],
        ),
      ),
      [startsWith('ParallelWaitError')],
      reason: 'one failure inside, and the error goes whole',
    );
    expect(zoneOf(() => StateError('hook')), ['StateError']);
  });

  test('the observer sees start, log, error and finish in order', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(
        key: 'job',
        (ctx) async {
          ctx.log('hello');
          throw StateError('boom');
        },
      ).ignoreFailure();
      async.flushTimers();
      expect(journal.take(), [
        '[job] started',
        '[job] log hello',
        '[job] error Bad state: boom',
        '[job] finished Failed(Bad state: boom)',
      ]);
    });
  });

  test('the two debug channels each print their own side', () {
    final engine = <String>[];
    final jobs = <String>[];
    Solo.debug = engine.add;
    Job.debug = jobs.add;
    try {
      runSolo((solo, journal, async) {
        solo.run<TestState, void>(key: 'job', (ctx) async {
          ctx.emit(const Preparing());
        });
        async.flushMicrotasks();
      });
    } finally {
      Solo.debug = null;
      Job.debug = null;
    }
    // The queue, the state and the closing belong to the controller.
    expect(engine, contains('add Job(job)'));
    expect(engine, contains('state: Preparing(progress: 0)'));
    expect(engine, isNot(contains('Job(job) started')));
    // The life of a job belongs to the core.
    expect(jobs, contains('Job(job) started'));
    expect(jobs, contains('Job(job) finished: Done(null)'));
    expect(jobs, isNot(contains('add Job(job)')));
  });

  test('a job added while another runs says when it starts', () {
    final engine = <String>[];
    Solo.debug = engine.add;
    try {
      runSolo((solo, journal, async) {
        solo.run<TestState, void>(key: 'outer', (ctx) async {
          // Not awaited: awaited, it would wait for good.
          solo.run<TestState, void>(key: 'inner', (ctx) async {});
          ctx.onDispose(() {
            solo.run<TestState, void>(key: 'cleanup', (ctx) async {});
          });
        });
        async.flushMicrotasks();
      });
    } finally {
      Solo.debug = null;
    }
    expect(engine, contains('add Job(outer)'));
    expect(
      engine,
      contains(
        'add Job(inner) while Job(outer) is running: '
        'it starts after Job(outer) ends',
      ),
    );
    expect(
      engine,
      contains(
        'add Job(cleanup) while Job(outer) is running: '
        'it starts after Job(outer) ends',
      ),
      reason: 'past the body, the job still holds the queue',
    );
  });

  test('a job a child adds names the root job it waits for', () {
    final engine = <String>[];
    Solo.debug = engine.add;
    try {
      runSolo((solo, journal, async) {
        solo.run<TestState, void>(key: 'root', (ctx) async {
          await ctx.run(
            solo.job<TestState, void>(key: 'child', (child) async {
              solo.run<TestState, void>(key: 'fromChild', (ctx) async {});
            }),
          );
        });
        async.flushMicrotasks();
      });
    } finally {
      Solo.debug = null;
    }
    // The child runs too, but the queue waits for the root job, and the
    // root job is what the line names.
    expect(
      engine,
      contains(
        'add Job(fromChild) while Job(root) is running: '
        'it starts after Job(root) ends',
      ),
    );
  });

  test('a describe that throws is a mark on Solo.debug, and no more', () {
    final engine = <String>[];
    final zone = <Object>[];
    Solo.debug = engine.add;
    try {
      runZonedGuarded(
        () => fakeAsync((async) {
          PlainSolo<TestState>(const Initial()).run<TestState, void>(
            key: 'job',
            describe: () => throw StateError('describe'),
            (ctx) async {},
          );
          async.flushMicrotasks();
        }),
        (error, stackTrace) => zone.add(error),
      );
    } finally {
      Solo.debug = null;
    }
    expect(engine, contains('add Job(job: <describe threw StateError>)'));
    expect(zone, isEmpty);
  });
}

/// Throws from the instance hook the engine calls while finishing a job.
final class _ThrowingFinish extends Solo<TestState> with OpenSolo<TestState> {
  _ThrowingFinish() : super(const Initial());

  @override
  void onFinish(Job<Object?> job) => throw StateError('onFinish');
}

/// Throws from the instance hook the engine calls before a job body.
final class _ThrowingStart extends Solo<TestState> with OpenSolo<TestState> {
  _ThrowingStart() : super(const Initial());

  @override
  void onStart(Job<Object?> job) => throw StateError('onStart');
}

/// Throws from the instance hook the engine calls on a state change.
final class _ThrowingChange extends Solo<TestState>
    with SoloStream, OpenSolo<TestState> {
  _ThrowingChange() : super(const Initial());

  @override
  void onChange(SoloTransition<TestState> transition) =>
      throw StateError('onChange');
}

/// Throws from the observer hooks around a job body.
final class _ThrowingObserver extends SoloObserver {
  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      throw StateError('observer onStart');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      throw StateError('observer onFinish');
}

/// Throws from the instance hook the engine calls while closing.
final class _ThrowingCloseHook extends Solo<TestState> {
  _ThrowingCloseHook() : super(const Initial());

  @override
  void onClose() => throw StateError('onClose hook');
}

/// Writes down its `onClose`, and can close again or write the state
/// from inside it.
final class _Closing extends Solo<TestState> with OpenSolo<TestState> {
  final List<String> lines;
  final bool closeAgain;
  final TestState? writeOnClose;
  Future<void>? again;

  _Closing(this.lines, {this.closeAgain = false, this.writeOnClose})
      : super(const Initial());

  @override
  void onClose() {
    lines.add('hook: close, finished $isFinished');
    if (closeAgain) {
      again = close();
    }
    final state = writeOnClose;
    if (state != null) {
      externalSetState(state);
    }
  }
}

/// Builds a lazy log line in the hook, as the page about errors does.
final class _LazyLog extends Solo<TestState> with OpenSolo<TestState> {
  final List<String> lines;

  _LazyLog(this.lines) : super(const Initial());

  @override
  void onLog(Job<Object?> job, Object? message) {
    lines.add('hook: log');
    final line = message is Object? Function() ? message() : message;
    lines.add('hook: $line');
  }
}

/// Throws what [thrown] makes from the instance hook the engine calls before
/// a job body.
final class _ThrowingAtStart extends Solo<TestState> with OpenSolo<TestState> {
  final Object Function() thrown;

  _ThrowingAtStart(this.thrown) : super(const Initial());

  @override
  void onStart(Job<Object?> job) =>
      Error.throwWithStackTrace(thrown(), StackTrace.current);
}

/// Throws from the observer hook the engine calls while closing.
final class _ThrowingClose extends SoloObserver {
  @override
  void onClose(Solo<Object> solo) => throw StateError('onClose');
}

final class _Hooked extends Solo<TestState> with OpenSolo<TestState> {
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
  void onLog(Job<Object?> job, Object? message) =>
      lines.add('hook: log $message');

  @override
  void onChange(SoloTransition<TestState> transition) =>
      lines.add('hook: change ${transition.current}');
}
