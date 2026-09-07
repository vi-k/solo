@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';
import 'support/probe_job.dart';

void main() {
  test('a child runs inside the parent, one level deeper', () {
    fakeAsync((async) {
      ({int level, bool isChild, bool isRunning})? atRun;
      final parent = Job<void>((ctx) async {
        final child = ctx.run(
          Job.deferred<void>(key: 'child', (ctx) => ctx.wait(() => delay(10))),
        );
        atRun = (
          level: child.level,
          isChild: child.isChild,
          isRunning: child.isRunning,
        );
        await child.done;
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
          ctx.run(
            Job.deferred<void>(
              key: 'child',
              (ctx) => ctx.wait(() => delay(50)),
            ),
          );
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
            ctx.run(
              Job.deferred<void>(
                key: 'child$i',
                (ctx) => ctx.wait(() => delay(100)),
              ),
            );
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
        child = ctx.run(
          Job.deferred<void>(
            key: 'child',
            cancellable: false,
            (ctx) async {
              await ctx.wait(() => delay(50));
              childEndedAt = async.elapsed;
            },
          ),
        );
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

  test('a child cancellation seen through value marks the parent', () {
    fakeAsync((async) {
      final parent = Job<void>((ctx) async {
        final child = ctx.run(
          Job.deferred<void>(key: 'child', (ctx) => ctx.wait(() => delay(50))),
        );
        child.cancel().ignore();
        await child.value;
      });
      async.flushTimers();
      final outcome = parent.outcome! as Cancelled;
      expect(outcome.reason, CancelReason.handler);
      expect(outcome.description, 'child child: Cancelled(manual)');
    });
  });

  test('a child without a key still shows in the parent outcome', () {
    fakeAsync((async) {
      final parent = Job<void>((ctx) async {
        final child = ctx.run(
          Job.deferred<void>((ctx) => ctx.wait(() => delay(50))),
        );
        child.cancel().ignore();
        await child.value;
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
          await ctx
              .run(
                Job.deferred<void>(
                  key: 'child$i',
                  (ctx) => ctx.wait(() => delay(10)),
                ),
              )
              .done;
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
          ctx.run(child);
        } on Object catch (error) {
          thrown = error;
        }
      });
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      async.flushTimers();
      expect(thrown, isA<Cancelled>());
      expect((child.outcome! as Cancelled).reason, CancelReason.parent);
      expect((child.outcome! as Cancelled).started, isFalse);
    });
  });

  test('an implementation of Job that is not of this core is refused', () {
    fakeAsync((async) {
      Object? thrown;
      Job<void>((ctx) async {
        try {
          ctx.run(_ForeignJob());
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
          await ctx
              .run(
                Job.deferred<void>(
                  key: 'child',
                  observer: childJournal,
                  (ctx) async {},
                ),
              )
              .done;
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
          ctx.run(
            Job.deferred<void>(key: 'child', (ctx) async {
              ctx.run(
                Job.deferred<void>(
                  key: 'grandchild',
                  (ctx) => ctx.wait(() => delay(100)),
                ),
              );
              await ctx.wait(() => delay(100));
            }),
          );
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
          ctx.run(child);
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
          handle = ctx.run(child);
        },
      )..launch();
      async.flushMicrotasks();
      expect(identical(handle, child), isTrue, reason: 'the same handle');
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
          ctx.run(UnstartableJob<void>(key: 'child'));
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
          ctx.run(Job.deferred<void>(key: 'child', (child) async {}));
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
        child = ctx.run(
          Job.deferred<void>(key: 'child', (c) => c.wait(() => delay(100))),
        );
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
        child = ctx.run(
          Job.deferred<void>(key: 'child', (c) => c.wait(() => delay(100))),
        );
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
        ctx.run(
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
        );
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
      late Job<void> child;
      final parent = ThrowingRulesJob<int>((ctx) async {
        // An auto-starting job: left half-adopted it would start itself
        // on its own microtask, under a parent that waits for nothing.
        child = Job<void>(key: 'ghost', (c) async {
          log.add('ghost started');
          await c.wait(() => delay(50));
        });
        try {
          ctx.run(child);
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
    });
  });
}

/// A handle that implements [Job] without being a job of this core.
final class _ForeignJob implements Job<void> {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
