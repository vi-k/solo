@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';
import 'support/probe_job.dart';

void main() {
  test('a child runs inside the parent, one level deeper', () {
    fakeAsync((async) {
      ({int level, bool isChild, bool isRunning})? atRun;
      final parent = Job<void>((ctx) async {
        final child = Job.deferred<void>(
          key: 'child',
          (ctx) => ctx.wait(() => delay(10)),
        );
        final result = ctx.run(child);
        atRun = (
          level: child.level,
          isChild: child.isChild,
          isRunning: child.isRunning,
        );
        await result;
      });
      async.flushTimers();
      expect(atRun, (level: 1, isChild: true, isRunning: true));
      expect(parent.outcome, isA<Done<void>>());
    });
  });

  test('the parent finishes after its children', () {
    fakeAsync((async) {
      final journal = JobJournal();
      Job<void>(
        key: 'parent',
        observer: journal,
        (ctx) async {
          // Not awaited: the parent still waits for the child before it
          // can finish.
          ctx
              .run(
                Job.deferred<void>(
                  key: 'child',
                  (ctx) => ctx.wait(() => delay(50)),
                ),
              )
              .ignore();
        },
      ).ignore();
      async.flushTimers();
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        '> [child] finished Done(null)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  test('cancelling a parent cascades to its children, last one first', () {
    fakeAsync((async) {
      final journal = JobJournal();
      final parent = Job<void>(
        key: 'parent',
        observer: journal,
        (ctx) async {
          for (var i = 0; i < 2; i++) {
            ctx
                .run(
                  Job.deferred<void>(
                    key: 'child$i',
                    (ctx) => ctx.wait(() => delay(100)),
                  ),
                )
                .ignore();
          }
          await ctx.wait(() => delay(100));
        },
      );
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      async.flushTimers();
      final lines = journal.take();
      expect(
        lines.where((line) => line.contains('finished Cancelled')).toList(),
        [
          '> [child1] finished Cancelled(parent)',
          '> [child0] finished Cancelled(parent)',
          '[parent] finished Cancelled(manual)',
        ],
      );
    });
  });

  test('a child that is not cancellable refuses the cascade', () {
    fakeAsync((async) {
      late final Job<void> child;
      var childEndedAt = Duration.zero;
      final parent = Job<void>((ctx) async {
        child = Job.deferred<void>(
          key: 'child',
          cancellable: false,
          (ctx) async {
            await ctx.wait(() => delay(50));
            childEndedAt = async.elapsed;
          },
        );
        ctx.run(child).ignore();
        await ctx.wait(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      async.flushTimers();
      expect(child.outcome, isA<Done<void>>());
      expect(
        childEndedAt.inMilliseconds,
        50,
        reason: 'it ran its own course, cascade or no cascade',
      );
    });
  });

  test('run waits for a refusing child then checks parent cancellation', () {
    fakeAsync((async) {
      final gate = Completer<int>();
      final log = <String>[];
      int? valueReadSeparately;
      final child = Job.deferred<int>(
        (ctx) => ctx.wait(() => gate.future),
        cancellable: false,
      );
      final parent = Job<void>((ctx) async {
        await ctx.run(child);
        log.add('continued');
      });
      child.value.then((value) => valueReadSeparately = value).ignore();
      async.flushMicrotasks();

      parent.cancel().ignore();
      async.flushMicrotasks();

      expect(child.outcome, isNull);
      expect(parent.outcome, isNull);
      expect(log, isEmpty);

      gate.complete(3);
      async.flushMicrotasks();

      expect(
        child.outcome,
        isA<Done<int>>().having((it) => it.value, 'value', 3),
      );
      expect(parent.outcome, isA<Cancelled>());
      expect(log, isEmpty);
      expect(valueReadSeparately, 3);
    });
  });

  test('run waits while the child holds cancellation', () {
    fakeAsync((async) {
      final gate = Completer<int>();
      final log = <String>[];
      final child = Job.deferred<int>(
        (ctx) => ctx.uncancellable(() => gate.future),
      );
      final parent = Job<void>((ctx) async {
        await ctx.run(child);
        log.add('continued');
      });
      async.flushMicrotasks();

      parent.cancel().ignore();
      async.flushMicrotasks();

      expect(child.outcome, isNull);
      expect(parent.outcome, isNull);
      expect(log, isEmpty);

      gate.complete(9);
      async.flushMicrotasks();

      expect(child.outcome, isA<Cancelled>());
      expect(parent.outcome, isA<Cancelled>());
      expect(log, isEmpty);
    });
  });

  test('run waits when child onStart cancels the parent', () {
    fakeAsync((async) {
      final gate = Completer<int>();
      final log = <String>[];
      late final Job<void> parent;
      final child = Job.deferred<int>(
        (ctx) => ctx.wait(() => gate.future),
        observer: _OnStartObserver(() => parent.cancel().ignore()),
        cancellable: false,
      );
      parent = Job<void>((ctx) async {
        await ctx.run(child);
        log.add('continued');
      });
      async.flushMicrotasks();

      expect(child.outcome, isNull);
      expect(parent.outcome, isNull);
      expect(log, isEmpty);

      gate.complete(11);
      async.flushMicrotasks();

      expect(child.outcome, isA<Done<int>>());
      expect(parent.outcome, isA<Cancelled>());
      expect(log, isEmpty);
    });
  });

  test('run waits for the child children and cleanup before returning', () {
    fakeAsync((async) {
      final order = <String>[];
      final child = Job.deferred<int>((ctx) async {
        ctx.onDispose(() async {
          await delay(10);
          order.add('cleanup');
        });
        ctx.run(
          Job.deferred<void>((grandchild) async {
            await grandchild.wait(() => delay(20));
            order.add('grandchild');
          }),
        ).ignore();
        return 7;
      });
      final parent = Job<void>((ctx) async {
        final value = await ctx.run(child);
        order.add('run returned $value');
      });

      async.flushTimers();

      expect(parent.outcome, isA<Done<void>>());
      expect(order, ['grandchild', 'cleanup', 'run returned 7']);
    });
  });

  test('run preserves a child error and its stack trace', () {
    fakeAsync((async) {
      final error = StateError('child failed');
      final stackTrace = StackTrace.fromString('child stack');
      Object? caught;
      StackTrace? caughtStackTrace;
      final child = Job.deferred<void>((ctx) async {
        Error.throwWithStackTrace(error, stackTrace);
      });
      final parent = Job<void>((ctx) async {
        try {
          await ctx.run(child);
        } on Object catch (thrown, thrownStackTrace) {
          caught = thrown;
          caughtStackTrace = thrownStackTrace;
        }
      });

      async.flushMicrotasks();

      expect(caught, same(error));
      expect(caughtStackTrace, same(stackTrace));
      expect((child.outcome! as Failed).stackTrace, same(stackTrace));
      expect(parent.outcome, isA<Done<void>>());
    });
  });

  test('an ignored run returns a late value after the parent body ends', () {
    fakeAsync((async) {
      final gate = Completer<int>();
      int? runValue;
      int? childValue;
      final child = Job.deferred<int>(
        (ctx) => ctx.wait(() => gate.future),
        cancellable: false,
      );
      final parent = Job<void>((ctx) async {
        ctx.run(child).then((value) => runValue = value).ignore();
        child.value.then((value) => childValue = value).ignore();
      });
      async.flushMicrotasks();

      parent.cancel().ignore();
      async.flushMicrotasks();
      expect(parent.outcome, isNull);

      gate.complete(13);
      async.flushMicrotasks();

      expect(runValue, 13);
      expect(childValue, 13);
      expect(child.outcome, isA<Done<int>>());
      expect(parent.outcome, isA<Cancelled>());
    });
  });

  test('a child cancellation seen through run marks the parent', () {
    fakeAsync((async) {
      final parent = Job<void>((ctx) async {
        final child = Job.deferred<void>(
          key: 'child',
          (ctx) => ctx.wait(() => delay(50)),
        );
        final result = ctx.run(child);
        child.cancel().ignore();
        await result;
      });
      async.flushTimers();
      final outcome = parent.outcome! as Cancelled;
      expect(outcome.reason, isA<HandlerCancelReason>());
      expect(outcome.description, 'child child: Cancelled(manual)');
    });
  });

  test('a child without a key still shows in the parent outcome', () {
    fakeAsync((async) {
      final parent = Job<void>((ctx) async {
        final child = Job.deferred<void>((ctx) => ctx.wait(() => delay(50)));
        final result = ctx.run(child);
        child.cancel().ignore();
        await result;
      });
      async.flushTimers();
      expect(
        parent.outcome.toString(),
        'Cancelled(handler: child null: Cancelled(manual))',
      );
    });
  });

  test('a finished child leaves the waiting list', () {
    fakeAsync((async) {
      late final ProbeJob<void> parent;
      final counts = <int>[];
      parent = ProbeJob<void>((ctx) async {
        for (var i = 0; i < 3; i++) {
          await ctx.run(
            Job.deferred<void>(
              key: 'child$i',
              (ctx) => ctx.wait(() => delay(10)),
            ),
          );
          counts.add(parent.childCount);
        }
      })
        ..launch();
      async.flushTimers();
      expect(parent.outcome, isA<Done<void>>());
      expect(counts, [0, 0, 0]);
    });
  });

  test('run on a finished context throws StateError', () {
    fakeAsync((async) {
      late final JobContext leaked;
      final job = Job<void>((ctx) async {
        leaked = ctx;
      });
      async.flushMicrotasks();
      expect(job.isFinished, isTrue);
      expect(
        () => leaked.run(Job.deferred<void>((ctx) async {})),
        throwsStateError,
      );
    });
  });

  test('run under a cancelled parent drops the child and throws', () {
    fakeAsync((async) {
      // Deferred, so it can be made before the parent without starting.
      final child = Job.deferred<void>(key: 'child', (ctx) async {});
      Object? thrown;
      final parent = Job<void>((ctx) async {
        try {
          await ctx.wait(() => delay(50));
        } on Cancelled {
          // The wait gives up first; the body walks on to `run` anyway.
        }
        try {
          ctx.run(child).ignore();
        } on Object catch (error) {
          thrown = error;
        }
      });
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      async.flushTimers();
      expect(thrown, isA<Cancelled>());
      expect((child.outcome! as Cancelled).reason, isA<ParentCancelReason>());
      expect((child.outcome! as Cancelled).started, isFalse);
    });
  });

  test('an implementation of Job that is not of this core is refused', () {
    fakeAsync((async) {
      Object? thrown;
      Job<void>((ctx) async {
        try {
          ctx.run(_ForeignJob()).ignore();
        } on Object catch (error) {
          thrown = error;
        }
      });
      async.flushMicrotasks();
      expect(thrown, isA<ArgumentError>());
    });
  });

  test('a child given an observer of its own keeps it', () {
    fakeAsync((async) {
      final parentJournal = JobJournal();
      final childJournal = JobJournal();
      Job<void>(
        key: 'parent',
        observer: parentJournal,
        (ctx) async {
          await ctx.run(
            Job.deferred<void>(
              key: 'child',
              observer: childJournal,
              (ctx) async {},
            ),
          );
        },
      ).ignore();
      async.flushMicrotasks();
      expect(
        parentJournal.take(),
        ['[parent] started', '[parent] finished Done(null)'],
        reason: 'the child never reported to the parent observer',
      );
      expect(childJournal.take(), [
        '> [child] started',
        '> [child] finished Done(null)',
      ]);
    });
  });

  test('the cascade goes all the way down, deepest first', () {
    fakeAsync((async) {
      final journal = JobJournal();
      final root = Job<void>(
        key: 'root',
        observer: journal,
        (ctx) async {
          ctx
              .run(
                Job.deferred<void>(key: 'child', (ctx) async {
                  ctx
                      .run(
                        Job.deferred<void>(
                          key: 'grandchild',
                          (ctx) => ctx.wait(() => delay(100)),
                        ),
                      )
                      .ignore();
                  await ctx.wait(() => delay(100));
                }),
              )
              .ignore();
          await ctx.wait(() => delay(100));
        },
      );
      async.elapse(const Duration(milliseconds: 10));
      root.cancel().ignore();
      async.flushTimers();
      expect(
        journal.take().where((line) => line.contains('Cancelled')).toList(),
        [
          '>> [grandchild] finished Cancelled(parent)',
          '> [child] finished Cancelled(parent)',
          '[root] finished Cancelled(manual)',
        ],
      );
    });
  });

  test('a child that refuses its parent is left as it was', () {
    fakeAsync((async) {
      final child = UnadoptableJob<void>(key: 'child', (ctx) async {});
      Object? thrown;
      final parent = Job<void>((ctx) async {
        try {
          ctx.run(child).ignore();
        } on Object catch (error) {
          thrown = error;
        }
      })
        ..ignore();
      async.flushMicrotasks();
      expect(thrown, isA<ArgumentError>());
      expect(child.statusNow, JobStatus.created);
      expect(child.level, 0, reason: 'the level is set after the adoption');
      expect(child.isChild, isFalse);
      expect(child.outcome, isNull);
      // The parent reached its end, so the refused child never joined its
      // waiting list — and the child is free to run later, on its own.
      expect(parent.outcome, isA<Done<void>>());
      child.launch();
      async.flushMicrotasks();
      expect(child.outcome, isA<Done<void>>());
    });
  });

  test('a child the parent turns away finishes without ever starting', () {
    fakeAsync((async) {
      final journal = JobJournal();
      late final Job<void> handle;
      final child = Job.deferred<void>(key: 'child', (ctx) async {});
      final parent = RefusingParentJob<void>(
        key: 'parent',
        observer: journal,
        (ctx) async {
          handle = child;
          ctx.run(child).ignore();
        },
      )..launch();
      async.flushMicrotasks();
      expect(identical(handle, child), isTrue, reason: 'the original handle');
      expect(child.level, 1, reason: 'adopted before it was turned away');
      expect((child.outcome! as Cancelled).description, 'not now');
      expect(parent.outcome, isA<Done<void>>());
      expect(
        journal.take(),
        [
          '[parent] started',
          '> [child] dropped Cancelled(rules: not now)',
          '[parent] finished Done(null)',
        ],
        reason: 'finished without a started of its own',
      );
    });
  });
  test('a child whose start throws does not hang the parent', () {
    fakeAsync((async) {
      Object? caught;
      final parent = Job<int>((ctx) async {
        try {
          ctx.run(UnstartableJob<void>(key: 'child')).ignore();
        } on Object catch (error) {
          caught = error;
        }
        return 7;
      });
      async.elapse(const Duration(milliseconds: 10));
      expect(caught, isA<StateError>());
      expect(parent.outcome, isA<Done<int>>());
    });
  });

  test('a start rule that throws does not hang the parent', () {
    fakeAsync((async) {
      Object? caught;
      final parent = ThrowingRulesJob<int>((ctx) async {
        try {
          ctx.run(Job.deferred<void>(key: 'child', (child) async {})).ignore();
        } on Object catch (error) {
          caught = error;
        }
        return 7;
      })
        ..launch();
      async.elapse(const Duration(milliseconds: 10));
      expect(caught, isA<StateError>());
      expect(parent.outcome, isA<Done<int>>());
    });
  });

  test('a child started after the body has ended is refused', () {
    fakeAsync((async) {
      Object? thrown;
      final parent = Job<void>((ctx) async {
        scheduleMicrotask(() {
          scheduleMicrotask(() {
            try {
              ctx.run(Job.deferred<void>(key: 'late', (child) async {}));
            } on Object catch (error) {
              thrown = error;
            }
          });
        });
      });
      async.elapse(const Duration(milliseconds: 10));
      expect(
        thrown,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('has ended its body'),
        ),
        reason: 'the window of the body, not the one after the outcome',
      );
      expect(parent.outcome, isA<Done<void>>());
    });
  });

  test('a body that cancels itself cancels its children', () {
    fakeAsync((async) {
      late Job<void> child;
      final parent = Job<void>((ctx) async {
        child = Job.deferred<void>(
          key: 'child',
          (c) => c.wait(() => delay(100)),
        );
        ctx.run(child).ignore();
        await ctx.wait(() => delay(10));
        throw const Cancelled('enough');
      });
      async.elapse(const Duration(milliseconds: 20));
      expect(child.outcome, isA<Cancelled>());
      expect(parent.outcome, isA<Cancelled>());
    });
  });

  test('a body that fails leaves its children alone', () {
    fakeAsync((async) {
      late Job<void> child;
      final parent = Job<void>((ctx) async {
        child = Job.deferred<void>(
          key: 'child',
          (c) => c.wait(() => delay(100)),
        );
        ctx.run(child).ignore();
        await ctx.wait(() => delay(10));
        throw StateError('boom');
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 20));
      expect(child.outcome, isNull);
      async.elapse(const Duration(milliseconds: 200));
      expect(child.outcome, isA<Done<void>>());
      expect(parent.outcome, isA<Failed>());
    });
  });
  test('the waiting list a subclass sees cannot be changed by hand', () {
    fakeAsync((async) {
      final job = ProbeJob<void>((ctx) async {})..launch();
      expect(() => job.childrenList.add(job), throwsUnsupportedError);
    });
  });
  test(
      'a child started from a cancel callback of a self-cancelled body is '
      'refused', () {
    fakeAsync((async) {
      // The same window as the cascade of an outside cancellation, on the
      // path the body opens by giving itself up.
      Object? thrown;
      final parent = Job<void>((ctx) async {
        ctx
            .run(
              Job.deferred<void>(key: 'child', (child) async {
                child.onCancel(() {
                  try {
                    ctx.run(
                      Job.deferred<void>(
                        key: 'late',
                        (late) => late.wait(() => delay(50)),
                      ),
                    );
                  } on Object catch (error) {
                    thrown = error;
                  }
                });
                await child.wait(() => delay(100));
              }),
            )
            .ignore();
        await ctx.wait(() => delay(10));
        throw const Cancelled('enough');
      })
        ..ignore();
      async.flushTimers();
      expect(thrown, isA<StateError>());
      expect(parent.outcome, isA<Cancelled>());
    });
  });

  test('a child a throwing rule turned away never runs', () {
    fakeAsync((async) {
      final log = <String>[];
      final journal = JobJournal();
      late Job<void> child;
      final parent = ThrowingRulesJob<int>(observer: journal, (ctx) async {
        // Left half-adopted it would be a job nobody starts and nobody
        // waits for: the rule turns it away, and it is dropped instead.
        child = Job.deferred<void>(key: 'ghost', (c) async {
          log.add('ghost started');
          await c.wait(() => delay(50));
        });
        try {
          ctx.run(child).ignore();
        } on Object catch (error) {
          log.add('run threw ${error.runtimeType}');
        }

        return 7;
      })
        ..launch();
      async.flushTimers();
      expect(log, ['run threw StateError']);
      expect(child.outcome, isA<Failed>());
      expect(parent.outcome, isA<Done<int>>());
      // The one place a `Failed` does not call `onError`, and the reason
      // is that the very same error went to the body by the throw above:
      // announced once, where somebody can do something about it. The
      // parent swallowed it here, as a `try/catch` of its own would.
      expect(
        journal.take(),
        [
          '[null] started',
          '> [ghost] finished Failed(Bad state: rule failed)',
          '[null] finished Done(7)',
        ],
      );
    });
  });

  test(
      'a rule that cancels the parent while saying yes still refuses the '
      'child', () {
    Outcome<void>? parentOutcome;
    Outcome<void>? childOutcome;
    Object? thrown;
    fakeAsync((async) {
      final parent = SelfCancellingRulesJob<void>((ctx) async {
        final child = Job.deferred<void>(
          key: 'child',
          (c) => c.wait(() => delay(1000)),
        );
        try {
          ctx.run(child).ignore();
        } on Object catch (error) {
          thrown = error;
        }
        child.done.then((outcome) => childOutcome = outcome).ignore();
        await ctx.wait(() => delay(50));
      })
        ..launch();
      parent.done.then((outcome) => parentOutcome = outcome).ignore();
      async.elapse(const Duration(milliseconds: 100));
    });
    expect(
      thrown,
      isA<Cancelled>(),
      reason: 'the mark reaches the body as a throw, as it does before the '
          'rule is asked at all',
    );
    expect(childOutcome, isA<Cancelled>());
    expect(
      parentOutcome,
      isA<Cancelled>(),
      reason: 'and the parent ends on its own cancellation, not after the '
          'child it never waited for',
    );
  });
  test('a child leaves the waiting list by identity, not by ==', () {
    // A job of a domain is free to compare itself by its key, and then two
    // children of one queue are equal and still two jobs. Whoever takes a
    // child off the list has to name the one that ended.
    fakeAsync((async) {
      // The twins run side by side; the fast one ends first, the slow one
      // holds its cleanup open. The parent must not walk away from it.
      final tail = Completer<void>();
      var parentCleaned = false;
      final slow = KeyedJob<int>(key: 'twin', (ctx) async {
        ctx.onDispose(() => tail.future);
        return 1;
      });
      final fast = KeyedJob<int>(key: 'twin', (ctx) async => 2);
      final parent = ProbeJob<void>((ctx) async {
        ctx.onDispose(() => parentCleaned = true);
        ctx.run(slow).ignore();
        await ctx.run(fast);
      })
        ..launch();
      async.elapse(const Duration(milliseconds: 50));
      expect(fast.isFinished, isTrue);
      expect(slow.isFinished, isFalse, reason: 'its cleanup still holds');
      expect(
        parent.childrenList,
        [same(slow)],
        reason: 'the fast twin left, the slow one stayed',
      );
      expect(
        parent.isFinished,
        isFalse,
        reason: 'the parent waits for the child that is still running',
      );
      expect(parentCleaned, isFalse, reason: 'and has not unwound yet');
      tail.complete();
      async.elapse(const Duration(milliseconds: 10));
      expect(parent.isFinished, isTrue);
      expect(parentCleaned, isTrue);
    });
    fakeAsync((async) {
      // The same twins, one step earlier: a rule of a domain throws over
      // the second handle. That one never joined the list, so the one on
      // it must stay.
      Object? refusal;
      final live = KeyedJob<int>(key: 'twin', (ctx) async {
        await ctx.wait(() => delay(100));
        return 1;
      });
      final parent = _SwitchableRulesJob<void>((ctx) async {
        ctx.run(live).ignore();
        ctx.refuseNextChild = true;
        try {
          ctx.run(KeyedJob<int>(key: 'twin', (ctx) async => 2)).ignore();
        } on Object catch (error) {
          refusal = error;
        }
      })
        ..launch();
      async.elapse(const Duration(milliseconds: 20));
      expect(refusal, isA<StateError>());
      expect(parent.childrenList, [same(live)]);
      expect(
        parent.isFinished,
        isFalse,
        reason: 'the refused handle did not take the live child with it',
      );
      parent.cancel().ignore();
      async.elapse(const Duration(milliseconds: 20));
      expect(
        live.outcome,
        isA<Cancelled>(),
        reason: 'and the cascade still reaches the child on the list',
      );
      expect(parent.isFinished, isTrue);
    });
    fakeAsync((async) {
      // The same refusal one step later: the handle is on the list
      // already, and its own context is what throws.
      Object? refusal;
      final live = KeyedJob<int>(key: 'twin', (ctx) async {
        await ctx.wait(() => delay(100));
        return 1;
      });
      final parent = ProbeJob<void>((ctx) async {
        ctx.run(live).ignore();
        try {
          ctx.run(UnstartableKeyedJob<int>(key: 'twin')).ignore();
        } on Object catch (error) {
          refusal = error;
        }
      })
        ..launch();
      async.elapse(const Duration(milliseconds: 20));
      expect(refusal, isA<StateError>());
      expect(parent.childrenList, [same(live)]);
      expect(
        parent.isFinished,
        isFalse,
        reason: 'the handle taken off the list is the one that was refused',
      );
      parent.cancel().ignore();
      async.elapse(const Duration(milliseconds: 20));
      expect(live.outcome, isA<Cancelled>());
      expect(parent.isFinished, isTrue);
    });
  });
}

/// A handle that implements [Job] without being a job of this core.
final class _ForeignJob implements Job<void> {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _OnStartObserver extends JobObserver {
  final void Function() _onStart;

  _OnStartObserver(this._onStart);

  @override
  void onStart(Job<Object?> job) => _onStart();
}

/// A parent whose rule throws when the body tells it to.
///
/// Stands in for a rule of a domain — `canStart` in `solo` — that lets one
/// child in and throws over the next.
final class _SwitchableRulesJob<T> extends JobBase<T> {
  final Future<T> Function(_SwitchableRulesContext ctx) _body;

  _SwitchableRulesJob(this._body);

  /// The waiting list itself, as a subclass of the core sees it.
  List<JobBase<Object?>> get childrenList => children;

  /// Starts the body the way an engine of a domain would.
  void launch() => start();

  @override
  JobContextBase createContext() => _SwitchableRulesContext(this);

  @override
  Future<T> execute(covariant _SwitchableRulesContext ctx) => _body(ctx);
}

/// The context of [_SwitchableRulesJob].
final class _SwitchableRulesContext extends JobContextBase {
  _SwitchableRulesContext(super.owner);

  /// Turned on by the body between two children.
  bool refuseNextChild = false;

  @override
  Cancelled? beforeChildStart(JobBase<Object?> child) {
    if (refuseNextChild) {
      throw StateError('rule failed');
    }
    return null;
  }
}
