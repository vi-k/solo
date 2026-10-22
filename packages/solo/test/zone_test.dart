@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/test_solo.dart';
import 'support/test_state.dart';

void main() {
  test('a homeless error with no observer reaches the zone', () {
    final caught = <String>[];
    fakeAsync((async) {
      final solo = TestSolo();
      _inZone(caught, () {
        solo.enqueue<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('abandoned boom');
          });
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, ['Bad state: abandoned boom']);
  });

  test("the body's failure does not reach the zone twice", () {
    final caught = <String>[];
    Outcome<void>? outcome;
    fakeAsync((async) {
      final solo = TestSolo();
      _inZone(caught, () {
        final job = solo.enqueue<TestState, void>(
          key: 'j',
          (ctx) async => throw StateError('body boom'),
        );
        Future<void> watch() async => outcome = await job.done;
        unawaited(watch());
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(outcome, isA<Failed>());
    expect(caught, isEmpty);
  });

  test('a global observer leaves the default route alone', () {
    final caught = <String>[];
    Solo.observer = _Silent();
    try {
      fakeAsync((async) {
        final solo = TestSolo();
        _inZone(caught, () {
          solo.enqueue<TestState, void>(key: 'j', (ctx) async {
            ctx.unattended(() async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              throw StateError('abandoned boom');
            });
          });
        });
        async.flushTimers();
        solo.close();
        async.flushTimers();
      });
    } finally {
      Solo.observer = null;
    }
    expect(
      caught,
      ['Bad state: abandoned boom'],
      reason: 'watching is not answering',
    );
  });

  test('an error handler takes the default route over', () {
    final caught = <String>[];
    final answered = <String>[];
    Solo.unansweredHandler =
        (solo, job, error, stackTrace) => answered.add('${job.key}: $error');
    try {
      fakeAsync((async) {
        final solo = TestSolo();
        _inZone(caught, () {
          solo.enqueue<TestState, void>(key: 'j', (ctx) async {
            ctx.unattended(() async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              throw StateError('abandoned boom');
            });
          });
        });
        async.flushTimers();
        solo.close();
        async.flushTimers();
      });
    } finally {
      Solo.unansweredHandler = null;
    }
    expect(answered, ['j: Bad state: abandoned boom']);
    expect(caught, isEmpty, reason: 'the handler answered for it');
  });

  test('an error handler that throws reaches the zone after the error', () {
    final caught = <String>[];
    Solo.unansweredHandler =
        (solo, job, error, stackTrace) => throw StateError('handler boom');
    try {
      fakeAsync((async) {
        final solo = TestSolo();
        _inZone(caught, () {
          solo.enqueue<TestState, void>(key: 'j', (ctx) async {
            ctx.unattended(() async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              throw StateError('abandoned boom');
            });
          });
        });
        async.flushTimers();
        solo.close();
        async.flushTimers();
      });
    } finally {
      Solo.unansweredHandler = null;
    }
    expect(
      caught,
      ['Bad state: abandoned boom', 'Bad state: handler boom'],
      reason: 'a broken channel does not take the error it was handed',
    );
  });

  test('a handler that throws a cancellation leaves the error alone', () {
    final caught = <String>[];
    Solo.unansweredHandler =
        (solo, job, error, stackTrace) => throw const Cancelled('handler');
    try {
      fakeAsync((async) {
        final solo = TestSolo();
        _inZone(caught, () {
          solo.enqueue<TestState, void>(key: 'j', (ctx) async {
            ctx.unattended(() async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              throw StateError('abandoned boom');
            });
          });
        });
        async.flushTimers();
        solo.close();
        async.flushTimers();
      });
    } finally {
      Solo.unansweredHandler = null;
    }
    expect(caught, ['Bad state: abandoned boom']);
  });

  test(
      'a handler that throws: the error to the zone of the job, its own to '
      'the current one', () {
    final created = <String>[];
    final current = <String>[];
    Solo.unansweredHandler =
        (solo, job, error, stackTrace) => throw StateError('handler boom');
    try {
      fakeAsync((async) {
        final solo = TestSolo();
        late final Job<void> job;
        _inZone(created, () {
          job = solo.enqueue<TestState, void>(key: 'j', (ctx) async {
            ctx.onCancel(() => throw StateError('onCancel'));
            await ctx.abandonable(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
          });
        });
        async.elapse(const Duration(milliseconds: 10));
        _inZone(current, () => unawaited(job.cancel()));
        async.flushTimers();
        solo.close();
        async.flushTimers();
      });
    } finally {
      Solo.unansweredHandler = null;
    }
    expect(created, ['Bad state: onCancel']);
    expect(current, ['Bad state: handler boom']);
  });

  test('a handler that throws the error back hands it to the zone once', () {
    expect(
      _answeredBy(
        (solo, job, error, stackTrace) =>
            Error.throwWithStackTrace(error, stackTrace),
      ),
      ['Bad state: abandoned boom'],
    );
  });

  test('a handler that throws only cancellations leaves the error alone', () {
    expect(
      _answeredBy(
        (solo, job, error, stackTrace) =>
            throw ParallelWaitError<List<Object?>, List<AsyncError?>>(
          [null, null],
          [
            AsyncError(const Cancelled('a'), StackTrace.empty),
            AsyncError(const Cancelled('b'), StackTrace.empty),
          ],
        ),
      ),
      ['Bad state: abandoned boom'],
    );
  });

  test(
      'an override of onUnanswered that throws reaches the zone after the '
      'error', () {
    final caught = <String>[];
    final solo = _Broken();
    fakeAsync((async) {
      _inZone(caught, () {
        solo.enqueue<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('abandoned boom');
          });
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, ['Bad state: abandoned boom', 'Bad state: override boom']);
  });

  test('an override of onUnanswered keeps the error out of the zone', () {
    final caught = <String>[];
    final solo = _Quiet();
    fakeAsync((async) {
      _inZone(caught, () {
        solo.enqueue<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('abandoned boom');
          });
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, isEmpty);
    expect(solo.errors, ['Bad state: abandoned boom']);
  });

  test('an override of onError alone leaves the route in place', () {
    final caught = <String>[];
    final solo = _Noting();
    fakeAsync((async) {
      _inZone(caught, () {
        solo.enqueue<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('abandoned boom');
          });
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(solo.errors, ['Bad state: abandoned boom'], reason: 'it notes');
    expect(
      caught,
      ['Bad state: abandoned boom'],
      reason: 'and answers for nothing, so the zone still hears',
    );
  });

  test('an override calling super still hands it to the zone', () {
    final caught = <String>[];
    final solo = _Loud();
    fakeAsync((async) {
      _inZone(caught, () {
        solo.enqueue<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('abandoned boom');
          });
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, ['Bad state: abandoned boom']);
    expect(solo.errors, ['Bad state: abandoned boom']);
  });

  test('a rule that throws reaches the zone', () {
    final caught = <String>[];
    fakeAsync((async) {
      final solo = TestSolo();
      _inZone(caught, () {
        solo.enqueue<TestState, void>(
          key: 'j',
          keepWhile: (state) {
            if (state is Working) {
              throw StateError('rule boom');
            }
            return true;
          },
          (ctx) async {
            await ctx.abandonable(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
          },
        );
      });
      async.elapse(const Duration(milliseconds: 5));
      solo.externalSetState(const Working());
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, ['Bad state: rule boom']);
  });

  test('a reentrant notification does not lose the outer error', () {
    final caught = <String>[];
    final solo = _Reentrant();
    fakeAsync((async) {
      _inZone(caught, () {
        solo
          ..enqueue<TestState, void>(key: 'j', (ctx) async {
            ctx.unattended(() async {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              throw StateError('outer boom');
            });
          })
          ..enqueue<TestState, void>(
            key: 'k',
            keepWhile: (state) {
              if (state is Working) {
                throw StateError('inner boom');
              }
              return true;
            },
            (ctx) async {
              await ctx.abandonable(
                () => Future<void>.delayed(const Duration(milliseconds: 100)),
              );
            },
          );
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, ['Bad state: inner boom', 'Bad state: outer boom']);
  });

  test('a disposer that throws reaches the zone', () {
    final caught = <String>[];
    fakeAsync((async) {
      final solo = TestSolo();
      _inZone(caught, () {
        solo.enqueue<TestState, void>(key: 'j', (ctx) async {
          ctx.onDispose(() => throw StateError('cleanup boom'));
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    // The commonest case of the widened route, and the one the README
    // paragraph about disposers had to be rewritten for.
    expect(caught, ['Bad state: cleanup boom']);
  });

  test('a cancellation never reaches the zone', () {
    final caught = <String>[];
    final solo = _Loud();
    fakeAsync((async) {
      _inZone(caught, () {
        solo
          ..enqueue<TestState, void>(key: 'j', (ctx) async {
            ctx.unattended(() => throw const Cancelled('mine'));
          })
          ..enqueue<TestState, void>(
            key: 'k',
            keepWhile: (state) => state is! Working,
            (ctx) async {
              ctx.unattended(() async {
                await Future<void>.delayed(const Duration(milliseconds: 30));
                // The job is over and the state has left the rule: the
                // leaked context builds a fresh `Cancelled(rules)` and
                // hands it to the hook.
                ctx.state;
              });
            },
          );
      });
      async.elapse(const Duration(milliseconds: 10));
      solo.set(const Working());
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    // Both reached the hook; neither reached the zone. Without the
    // `error is! Cancelled` guard the zone would hold them too.
    expect(solo.errors, [
      'Cancelled(handler: mine)',
      'Cancelled(rules: keepWhile)',
    ]);
    expect(caught, isEmpty);
  });

  test('a job run inside unattended work of another controller is its own', () {
    // The queue starts the job at once, inside the work, and the job would
    // start in the work's zone: a bare error in its body and a throwing
    // `onStart` reached the controller whose job started the work. It
    // starts in the zone the work was started from, and both land there.
    final caught = <String>[];
    final a = _Loud();
    final b = _StartThrows();
    fakeAsync((async) {
      _inZone(caught, () {
        a.enqueue<TestState, void>(key: 'a', (ctx) async {
          ctx.unattended(() {
            b.enqueue<TestState, void>(key: 'b', (ctx) async {
              unawaited(Future<void>.error(StateError('leak')));
            });
          });
          await ctx.abandonable(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        });
      });
      async.flushTimers();
      a.close();
      b.close();
      async.flushTimers();
    });
    expect(a.errors, isEmpty);
    expect(b.errors, isEmpty);
    expect(caught, ['Bad state: onStart of b', 'Bad state: leak']);
  });

  group('a body runs in the zone its job was made in', () {
    // The queue starts a job from whatever woke it: the call that queued
    // a job just before it, the end of the job before, a window's timer.
    // The body ran in that zone, another call's as a rule, with its timers,
    // its values and its error handler.
    test('queued right after a job of another zone', () {
      final seen = <String>[];
      fakeAsync((async) {
        final solo = TestSolo();
        for (final name in ['A', 'B']) {
          runZoned(
            () => solo.enqueue<TestState, void>(
              key: name,
              (ctx) async => seen.add('$name:${Zone.current[#name]}'),
            ),
            zoneValues: {#name: name},
          );
        }
        async.flushMicrotasks();
        solo.close();
        async.flushMicrotasks();
      });
      expect(seen, ['A:A', 'B:B']);
    });

    test('queued behind a job of another zone', () {
      final seen = <String>[];
      fakeAsync((async) {
        final solo = TestSolo();
        final gate = Completer<void>();
        runZoned(
          () => solo.enqueue<TestState, void>(key: 'A', (ctx) async {
            await gate.future;
            seen.add('A:${Zone.current[#name]}');
          }),
          zoneValues: {#name: 'A'},
        );
        async.flushMicrotasks();
        runZoned(
          () => solo.enqueue<TestState, void>(
            key: 'B',
            (ctx) async => seen.add('B:${Zone.current[#name]}'),
          ),
          zoneValues: {#name: 'B'},
        );
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
        solo.close();
        async.flushMicrotasks();
      });
      expect(seen, ['A:A', 'B:B']);
    });

    test('a group sealed by a window another zone restarted', () {
      final seen = <String>[];
      fakeAsync((async) {
        final solo = TestSolo();
        final events = solo.collect<TestState, String, void>(
          (ctx, names) async => seen.add('$names:${Zone.current[#name]}'),
          timing: AccumulationTiming.debounce(
            const Duration(milliseconds: 200),
          ),
        );
        for (final name in ['A', 'B']) {
          runZoned(() => events.add(name), zoneValues: {#name: name});
        }
        async.elapse(const Duration(milliseconds: 200));
        solo.close();
        async.flushMicrotasks();
      });
      expect(seen, ['[A, B]:A']);
    });

    test('a group a throttle window let through', () {
      final seen = <String>[];
      fakeAsync((async) {
        final solo = TestSolo();
        final events = solo.collect<TestState, String, void>(
          (ctx, names) async => seen.add('$names:${Zone.current[#name]}'),
          timing: AccumulationTiming.throttle(
            const Duration(milliseconds: 200),
          ),
        );
        runZoned(() => events.add('A'), zoneValues: {#name: 'A'});
        async.flushMicrotasks();
        for (final name in ['B', 'C']) {
          runZoned(() => events.add(name), zoneValues: {#name: name});
        }
        async.elapse(const Duration(milliseconds: 500));
        solo.close();
        async.flushMicrotasks();
      });
      expect(seen, ['[A]:A', '[B, C]:B']);
    });

    test('made in one zone and queued from another', () {
      final seen = <String>[];
      fakeAsync((async) {
        final solo = TestSolo();
        final job = runZoned(
          () => solo.job<TestState, void>(
            (ctx) async => seen.add('${Zone.current[#name]}'),
          ),
          zoneValues: {#name: 'made'},
        );
        runZoned(() => solo.enqueueJob(job), zoneValues: {#name: 'queued'});
        async.flushMicrotasks();
        solo.close();
        async.flushMicrotasks();
      });
      expect(seen, ['made']);
    });

    test('made in one zone and queued from another: its failure', () {
      final caught = <String, List<String>>{'made': [], 'queued': []};
      fakeAsync((async) {
        final solo = TestSolo();
        late final SoloJob<void> job;
        runZonedGuarded(
          () => job = solo.job<TestState, void>(
            (ctx) async => throw StateError('nobody read it'),
          ),
          (error, stackTrace) => caught['made']!.add('$error'),
        );
        runZonedGuarded(
          () => solo.enqueueJob(job),
          (error, stackTrace) => caught['queued']!.add('$error'),
        );
        async.flushMicrotasks();
        solo.close();
        async.flushMicrotasks();
      });
      expect(caught, {
        'made': ['Bad state: nobody read it'],
        'queued': isEmpty,
      });
    });

    test('the onStart hooks of a job run in its zone', () {
      final caught = <String, List<String>>{'A': [], 'B': []};
      fakeAsync((async) {
        final solo = _StartNames();
        for (final name in ['A', 'B']) {
          runZonedGuarded(
            () => solo.enqueue<TestState, void>(key: name, (ctx) async {}),
            (error, stackTrace) => caught[name]!.add('$error'),
          );
        }
        async.flushMicrotasks();
        solo.close();
        async.flushMicrotasks();
      });
      expect(caught, {
        'A': ['Bad state: onStart of A'],
        'B': ['Bad state: onStart of B'],
      });
    });

    test('a failure of a future of its own zone reaches the body', () {
      // An error does not cross into another error zone. Started from the
      // zone of the job before, the body below never heard of the failure,
      // the zone of B took it as unhandled, and the job never ended.
      final caught = <String, List<String>>{'A': [], 'B': []};
      Outcome<int>? outcome;
      fakeAsync((async) {
        final solo = TestSolo();
        final gate = Completer<void>();
        late final Completer<int> fetch;
        runZonedGuarded(
          () => solo.enqueue<TestState, void>(key: 'A', (ctx) => gate.future),
          (error, stackTrace) => caught['A']!.add('$error'),
        );
        runZonedGuarded(
          () {
            fetch = Completer<int>();
            solo
                .enqueue<TestState, int>(
                  key: 'B',
                  (ctx) => fetch.future,
                )
                .done
                .then((done) => outcome = done);
          },
          (error, stackTrace) => caught['B']!.add('$error'),
        );
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
        fetch.completeError(StateError('offline'));
        async.flushMicrotasks();
        solo.close();
        async.flushMicrotasks();
      });
      expect('$outcome', startsWith('Failed(Bad state: offline'));
      expect(caught, {'A': isEmpty, 'B': isEmpty});
    });
  });

  group('a failure a cancellation covered', () {
    // Whoever reads the outcome gets the cancellation — `ctx.run`, a reader
    // of `value`, a body waiting for a child of `each` — and the controller
    // answers for the failure itself.
    test('in a child of run reaches onUnanswered of the controller', () {
      final caught = <String>[];
      final solo = _Quiet();
      fakeAsync((async) => _coveredChild(solo, async, caught));
      expect(solo.errors, ['Bad state: child failed first']);
      expect(caught, isEmpty, reason: 'the override answered for it');
    });

    test('in a child of run reaches the error handler behind it', () {
      final caught = <String>[];
      final answered = <String>[];
      Solo.unansweredHandler =
          (solo, job, error, stackTrace) => answered.add('${job.key}: $error');
      try {
        fakeAsync((async) => _coveredChild(TestSolo(), async, caught));
      } finally {
        Solo.unansweredHandler = null;
      }
      expect(answered, ['child: Bad state: child failed first']);
      expect(caught, isEmpty, reason: 'the handler answered for it');
    });

    test('in a child of run: the parent catches Cancelled, not the failure',
        () {
      final caught = <String>[];
      final thrown = <String>[];
      fakeAsync(
        (async) => _coveredChild(TestSolo(), async, caught, thrown: thrown),
      );
      expect(thrown, ['Cancelled']);
      expect(caught, ['Bad state: child failed first']);
    });

    test('in a child of run reaches the zone with neither', () {
      final caught = <String>[];
      fakeAsync((async) => _coveredChild(TestSolo(), async, caught));
      expect(caught, ['Bad state: child failed first']);
    });

    test('in a child of run that ignoreFailure was called on is only told', () {
      final caught = <String>[];
      final answered = <String>[];
      final solo = _Loud();
      Solo.unansweredHandler =
          (solo, job, error, stackTrace) => answered.add('${job.key}: $error');
      try {
        fakeAsync((async) => _coveredChild(solo, async, caught, ignored: true));
      } finally {
        Solo.unansweredHandler = null;
      }
      expect(solo.errors, ['Bad state: child failed first']);
      expect(answered, isEmpty, reason: 'nobody answers for it');
      expect(caught, isEmpty);
    });

    for (final named in [false, true]) {
      test(
          named
              ? 'a step the state stopped while a section held a stop, named '
                  'a cancellation error, is only told'
              : 'a step the state stopped while a section held a stop reaches '
                  'the zone', () {
        // The section holds the parent's cancellation. The state leaves the
        // child's working type inside it, and the rule cancels the child at
        // once: `onCancel` stops the step, and the body fails with that
        // stop. The child ends `Cancelled`, and the failure of its body goes
        // to the answer like any other, unless the app named it.
        if (named) {
          Job.isCancellationError = (error) => error is _Stopped;
        }
        final caught = <String>[];
        final solo = _Loud();
        late final SoloJob<int> child;
        try {
          fakeAsync((async) {
            late final Job<void> parent;
            _inZone(caught, () {
              parent =
                  solo.enqueue<TestState, void>(key: 'parent', (ctx) async {
                await ctx.run(
                  child = solo.job<Initial, int>(key: 'child', (ctx) async {
                    final stopped = Completer<void>();
                    ctx.onCancel(
                      () => stopped.completeError(const _Stopped()),
                    );
                    await ctx.uncancellable<void>(() => stopped.future);
                    return 1;
                  }),
                );
              });
            });
            async.elapse(const Duration(milliseconds: 5));
            parent.cancel().ignore();
            async.elapse(const Duration(milliseconds: 5));
            solo.set(const Preparing());
            async.flushTimers();
            solo.close();
            async.flushTimers();
          });
        } finally {
          Job.isCancellationError = null;
        }
        expect('${child.outcome}', 'Cancelled(rules: is not Initial)');
        expect(solo.errors, ['stopped']);
        expect(caught, named ? isEmpty : ['stopped']);
      });
    }

    for (final read in [false, true]) {
      test(
          read
              ? 'in a root whose value is awaited reaches the error handler'
              : 'in a root nobody reads reaches the error handler', () {
        final caught = <String>[];
        final answered = <String>[];
        final readers = <String>[];
        Solo.unansweredHandler = (solo, job, error, stackTrace) =>
            answered.add('${job.key}: $error');
        try {
          fakeAsync(
            (async) => _coveredRoot(
              TestSolo(),
              async,
              caught,
              read: read ? readers : null,
            ),
          );
        } finally {
          Solo.unansweredHandler = null;
        }
        expect(answered, ['root: Bad state: root failed first']);
        expect(caught, isEmpty, reason: 'the handler answered for it');
        expect(readers, read ? ['Cancelled(manual)'] : isEmpty);
      });
    }

    test('in a child of each whose value is awaited reaches the error handler',
        () {
      final caught = <String>[];
      final answered = <String>[];
      Solo.unansweredHandler =
          (solo, job, error, stackTrace) => answered.add('$error');
      try {
        fakeAsync((async) => _coveredEach(TestSolo(), async, caught));
      } finally {
        Solo.unansweredHandler = null;
      }
      expect(answered, ['Bad state: each failed first']);
      expect(caught, isEmpty, reason: 'the handler answered for it');
    });
  });

  test('the filter of cancellation errors is left as it was found', () {
    expect(Job.isCancellationError, isNull);
  });
}

/// A root whose body fails 5 ms in while a child of its own still runs, and
/// is cancelled 10 ms in; with [read], the value is awaited and what it
/// throws lands there.
void _coveredRoot(
  OpenSolo<TestState> solo,
  FakeAsync async,
  List<String> caught, {
  List<String>? read,
}) {
  late final Job<void> root;
  _inZone(caught, () {
    root = solo.enqueue<TestState, void>(key: 'root', (ctx) async {
      ctx
          .run(
            solo.job<TestState, void>(
              key: 'child',
              (ctx) => ctx.abandonable(
                () => Future<void>.delayed(const Duration(milliseconds: 50)),
              ),
            ),
          )
          .ignore();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      throw StateError('root failed first');
    });
    if (read != null) {
      unawaited(
        root.value.then<void>(
          (_) {},
          onError: (Object error) => read.add('$error'),
        ),
      );
    }
  });
  async.elapse(const Duration(milliseconds: 10));
  root.cancel().ignore();
  async.flushTimers();
  solo.close();
  async.flushTimers();
}

/// A parent that awaits the value of a child of `each`, cancelled 10 ms in,
/// while that child waits for a child of its own after its callback failed.
void _coveredEach(
  OpenSolo<TestState> solo,
  FakeAsync async,
  List<String> caught,
) {
  late final Job<void> parent;
  _inZone(caught, () {
    parent = solo.enqueue<TestState, void>(key: 'parent', (ctx) async {
      await ctx.each(Stream<int>.fromIterable([1]), (child, event) {
        child
            .run(
              solo.job<TestState, void>(
                key: 'grandchild',
                (ctx) => ctx.abandonable(
                  () => Future<void>.delayed(const Duration(milliseconds: 50)),
                ),
              ),
            )
            .ignore();
        throw StateError('each failed first');
      }).value;
    });
  });
  async.elapse(const Duration(milliseconds: 10));
  parent.cancel().ignore();
  async.flushTimers();
  solo.close();
  async.flushTimers();
}

/// A parent that runs a child through `ctx.run` and is cancelled 10 ms
/// in, while the child waits for a child of its own after its body failed
/// 5 ms in.
void _coveredChild(
  OpenSolo<TestState> solo,
  FakeAsync async,
  List<String> caught, {
  bool ignored = false,
  List<String>? thrown,
}) {
  late final Job<void> parent;
  _inZone(caught, () {
    parent = solo.enqueue<TestState, void>(key: 'parent', (ctx) async {
      final child = solo.job<TestState, int>(key: 'child', (ctx) async {
        ctx
            .run(
              solo.job<TestState, void>(
                key: 'grandchild',
                (ctx) => ctx.abandonable(
                  () => Future<void>.delayed(const Duration(milliseconds: 50)),
                ),
              ),
            )
            .ignore();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        throw StateError('child failed first');
      });
      if (ignored) {
        child.ignoreFailure();
      }
      try {
        await ctx.run(child);
      } on Object catch (error) {
        thrown?.add(error is Cancelled ? 'Cancelled' : '$error');
        rethrow;
      }
    });
  });
  async.elapse(const Duration(milliseconds: 10));
  parent.cancel().ignore();
  async.flushTimers();
  solo.close();
  async.flushTimers();
}

final class _Silent extends SoloObserver {}

final class _Quiet extends Solo<TestState> with OpenSolo<TestState> {
  final errors = <String>[];

  _Quiet() : super(const Initial());

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add('$error');
}

/// What reaches the zone when [handler] answers for a failure of work
/// handed to `ctx.unattended`.
List<String> _answeredBy(SoloUnansweredHandler handler) {
  final caught = <String>[];
  Solo.unansweredHandler = handler;
  try {
    fakeAsync((async) {
      final solo = TestSolo();
      _inZone(caught, () {
        solo.enqueue<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('abandoned boom');
          });
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
  } finally {
    Solo.unansweredHandler = null;
  }
  return caught;
}

/// Answers by throwing, the way a reporter that is down does.
final class _Broken extends Solo<TestState> with OpenSolo<TestState> {
  _Broken() : super(const Initial());

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      throw StateError('override boom');
}

/// Notes every error and answers for none: the route stands as it is.
final class _Noting extends Solo<TestState> with OpenSolo<TestState> {
  final errors = <String>[];

  _Noting() : super(const Initial());

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add('$error');
}

/// What the step of a child throws once its cancellation stops it.
final class _Stopped implements Exception {
  const _Stopped();

  @override
  String toString() => 'stopped';
}

final class _Loud extends Solo<TestState> with OpenSolo<TestState> {
  final errors = <String>[];

  _Loud() : super(const Initial());

  void set(TestState state) => externalSetState(state);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    errors.add('$error');
    super.onError(job, error, stackTrace);
  }
}

/// Throws from `onStart`, naming the job by its key.
final class _StartNames extends Solo<TestState> with OpenSolo<TestState> {
  _StartNames() : super(const Initial());

  @override
  void onStart(Job<Object?> job) => throw StateError('onStart of ${job.key}');
}

final class _StartThrows extends Solo<TestState> with OpenSolo<TestState> {
  final errors = <String>[];

  _StartThrows() : super(const Initial());

  @override
  void onStart(Job<Object?> job) => throw StateError('onStart of b');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    errors.add('$error');
    super.onError(job, error, stackTrace);
  }
}

final class _Reentrant extends Solo<TestState> with OpenSolo<TestState> {
  bool _nested = false;

  _Reentrant() : super(const Initial());

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (!_nested) {
      _nested = true;
      externalSetState(const Working());
    }
    super.onError(job, error, stackTrace);
  }
}

void _inZone(List<String> errors, void Function() body) {
  Zone.current
      .fork(
        specification: ZoneSpecification(
          handleUncaughtError: (self, parent, zone, error, stackTrace) =>
              errors.add('$error'),
        ),
      )
      .run<void>(body);
}
