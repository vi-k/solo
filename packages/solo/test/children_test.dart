@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/foreign_job.dart';
import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('children run inside the parent, nested by level', () {
    runSolo((solo, journal, async) {
      final test3 = solo.job<Preparing, void>(key: 'test3', (ctx) async {
        await delay(100);
        ctx.emit(ctx.state.copyWith(progress: 100));
      });
      final test2 = solo.job<PreparingAndWorking, void>(
        key: 'test2',
        canStart: (state) => state is Preparing,
        (ctx) async {
          await delay(100);
          ctx.emit(ctx.stateAs<Preparing>().copyWith(progress: 50));
          await ctx.run(test3);
          ctx.emit(const Working());
        },
      );
      // Read inside the body, asserted outside: a failing `expect` in a job
      // body ends the job as `Failed` instead of failing the test.
      ({int level, bool isChild, bool isRunning})? childAtRun;
      final test1 = solo.run<NotDisposed, void>(
        key: 'test1',
        canStart: (state) => state is Initial,
        (ctx) async {
          await delay(100);
          ctx.emit(const Preparing());
          final waitForChild = ctx.run(test2);
          childAtRun = (
            level: test2.level,
            isChild: test2.isChild,
            isRunning: test2.isRunning,
          );
          await waitForChild;
          await delay(100);
          ctx.emit(ctx.stateAs<Working>().copyWith(a: 1, b: 1));
          ctx.emit(const Disposed());
        },
      );
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(
        childAtRun,
        (level: 1, isChild: true, isRunning: true),
        reason: 'the child starts synchronously, one level deeper',
      );
      expect(test3.level, 2);
      expect(test1.level, 0);
      expect(journal.take(), [
        '[test1] started',
        'state: Preparing(progress: 0)',
        '> [test2] started',
        'state: Preparing(progress: 50)',
        '>> [test3] started',
        'state: Preparing(progress: 100)',
        '>> [test3] finished Done(null)',
        'state: Working(a: 0, b: 0)',
        '> [test2] finished Done(null)',
        'state: Working(a: 1, b: 1)',
        'state: Disposed()',
        '[test1] finished Done(null)',
      ]);
    });
  });

  test('a child failing canStart is a finished handle, parent goes on', () {
    runSolo((solo, journal, async) {
      var childBodyRan = false;
      bool? childFinishedAtRun;
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        final child = solo.job<Working, void>(key: 'child', (childCtx) async {
          childBodyRan = true;
        });
        ctx.run(child).ignore();
        childFinishedAtRun = child.isFinished;
        await child.done;
        ctx.emit(const Preparing());
      });
      async.flushTimers();
      expect(childBodyRan, isFalse);
      expect(childFinishedAtRun, isTrue, reason: 'rejected at run');
      expect(journal.take(), [
        '[parent] started',
        '> [child] dropped Cancelled(rules: is not Working)',
        'state: Preparing(progress: 0)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  test('await run of a child dropped at start reports the child', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        final child = solo.job<Working, void>(key: 'child', (ctx) async {});
        await ctx.run(child);
      });
      async.flushTimers();
      const parentOutcome = '[parent] finished Cancelled(handler: child '
          'child: Cancelled(rules: is not Working))';
      expect(journal.take(), [
        '[parent] started',
        '> [child] dropped Cancelled(rules: is not Working)',
        parentOutcome,
      ]);
    });
  });

  test('the parent finishes only after an un-awaited child', () {
    runSolo((solo, journal, async) {
      final parent = solo.run<TestState, void>(key: 'parent', (ctx) async {
        final child = solo.job<TestState, void>(key: 'child', (ctx) async {
          await delay(100);
          ctx.emit(const Preparing());
        });
        ctx.run(child).ignore();
      });
      async.elapse(const Duration(milliseconds: 50));
      expect(parent.isRunning, isTrue);
      expect(journal.take(), ['[parent] started', '> [child] started']);
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        'state: Preparing(progress: 0)',
        '> [child] finished Done(null)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  test('cancelling the parent cascades to children, deepest first', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        final child = solo.job<TestState, void>(key: 'child', (ctx) async {
          final grandchild = solo.job<TestState, void>(
            key: 'grandchild',
            (ctx) async {
              await delay(100);
              ctx.check();
            },
          );
          ctx.run(grandchild).ignore();
          await grandchild.done;
          ctx.check();
        });
        ctx.run(child).ignore();
        await child.done;
        ctx.check();
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        '>> [grandchild] started',
        '>> [grandchild] finished Cancelled(parent)',
        '> [child] finished Cancelled(parent)',
        '[parent] finished Cancelled(manual)',
      ]);
    });
  });

  test('cancelling the parent marks children before itself', () {
    runSolo((solo, journal, async) {
      // Registered parent first, deepest child last: the recorded order can
      // only come from the order in which the marks were set.
      final marked = <String>[];
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        ctx.job.whenCancelled((_) => marked.add('parent'));
        final child = solo.job<TestState, void>(key: 'child', (ctx) async {
          ctx.job.whenCancelled((_) => marked.add('child'));
          final grandchild = solo.job<TestState, void>(
            key: 'grandchild',
            (ctx) async {
              ctx.job.whenCancelled((_) => marked.add('grandchild'));
              await delay(100);
              ctx.check();
            },
          );
          ctx.run(grandchild).ignore();
          await grandchild.done;
          ctx.check();
        });
        ctx.run(child).ignore();
        await child.done;
        ctx.check();
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.flushMicrotasks();
      expect(marked, ['grandchild', 'child', 'parent']);
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        '>> [grandchild] started',
        '>> [grandchild] finished Cancelled(parent)',
        '> [child] finished Cancelled(parent)',
        '[parent] finished Cancelled(manual)',
      ]);
    });
  });

  test('await run propagates the child cancellation as handler', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      solo.run<Preparing, void>(key: 'parent', (ctx) async {
        final child = solo.job<Preparing, void>(
          key: 'child',
          keepWhile: (state) => state.progress < 50,
          (ctx) async {
            await delay(100);
            ctx.check();
          },
        );
        await ctx.run(child);
        ctx.emit(const Working());
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Preparing(progress: 50));
      async.elapse(const Duration(milliseconds: 50));
      const parentOutcome = '[parent] finished Cancelled(handler: child '
          'child: Cancelled(rules: keepWhile))';
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        'state: Preparing(progress: 50)',
        '> [child] finished Cancelled(rules: keepWhile)',
        parentOutcome,
      ]);
    });
  });

  test('await child.done lets the parent continue after cancellation', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      solo.run<PreparingAndWorking, void>(key: 'parent', (ctx) async {
        final child = solo.job<Preparing, void>(
          key: 'child',
          keepWhile: (state) => state.progress < 50,
          (ctx) async {
            await delay(100);
            ctx.check();
          },
        );
        ctx.run(child).ignore();
        await child.done;
        ctx.emit(const Working());
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Preparing(progress: 50));
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        'state: Preparing(progress: 50)',
        '> [child] finished Cancelled(rules: keepWhile)',
        'state: Working(a: 0, b: 0)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  test('a failed child reports onError and fails the parent via run', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        final child = solo.job<TestState, void>(key: 'child', (ctx) async {
          throw StateError('boom');
        });
        await ctx.run(child);
      })
          // The journal below is the whole assertion; keep the parent's
          // failure out of the zone.
          .ignore();
      async.flushTimers();
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        '> [child] error Bad state: boom',
        '> [child] finished Failed(Bad state: boom)',
        '[parent] error Bad state: boom',
        '[parent] finished Failed(Bad state: boom)',
      ]);
    });
  });

  test("a child's emit re-evaluates the parent's rules", () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      solo.run<Preparing, void>(
        key: 'parent',
        keepWhile: (state) => state.progress != 50,
        (ctx) async {
          await delay(100);
          final child = solo.job<Preparing, void>(key: 'child', (ctx) async {
            ctx
              ..emit(const Preparing(progress: 25))
              ..emit(const Preparing(progress: 50))
              ..emit(const Preparing(progress: 75));
          });
          ctx.run(child).ignore();
          await child.done;
          ctx.emit(const Preparing(progress: 100));
        },
      );
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 100));
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        'state: Preparing(progress: 25)',
        'state: Preparing(progress: 50)',
        '> [child] finished Cancelled(parent)',
        '[parent] finished Cancelled(rules: keepWhile)',
      ]);
    });
  });

  test("a child's emit outside the parent's W cancels the parent", () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      solo.run<Preparing, void>(key: 'parent', (ctx) async {
        final child = solo.job<PreparingAndWorking, void>(
          key: 'child',
          (ctx) async {
            ctx.emit(const Working());
            await delay(10);
            ctx.check();
          },
        );
        ctx.run(child).ignore();
        await child.done;
        ctx.check();
      });
      async.flushTimers();
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        'state: Working(a: 0, b: 0)',
        '> [child] finished Cancelled(parent)',
        '[parent] finished Cancelled(rules: is not Preparing)',
      ]);
    });
  });

  test('parallel children each re-evaluate the other', () {
    runSolo(initialState: const Working(), (solo, journal, async) {
      solo.run<Working, void>(key: 'parent', (ctx) async {
        final jobA = solo.job<Working, void>(
          key: 'a',
          keepWhile: (state) => state.b == 0,
          (ctx) async {
            await delay(100);
            ctx.emit(ctx.state.copyWith(a: 1));
          },
        );
        ctx.run(jobA).ignore();
        final jobB = solo.job<Working, void>(key: 'b', (ctx) async {
          await delay(50);
          ctx.emit(ctx.state.copyWith(b: 1));
        });
        ctx.run(jobB).ignore();
        await Future.wait([jobA.done, jobB.done]);
      });
      async.flushTimers();
      expect(journal.take(), [
        '[parent] started',
        '> [a] started',
        '> [b] started',
        'state: Working(a: 0, b: 1)',
        '> [b] finished Done(null)',
        '> [a] finished Cancelled(rules: keepWhile)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  test('a cancellable: false child finishes and the parent waits', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        final child = solo.job<TestState, void>(
          key: 'child',
          cancellable: false,
          (ctx) async {
            await delay(100);
            ctx.emit(const Preparing());
          },
        );
        ctx.run(child).ignore();
        await child.done;
        ctx.check();
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        'state: Preparing(progress: 0)',
        '> [child] finished Done(null)',
        '[parent] finished Cancelled(manual)',
      ]);
    });
  });

  test('run reevaluates parent rules after a successful child', () {
    runSolo((solo, journal, async) {
      var continued = false;
      final child = solo.job<TestState, int>(
        key: 'child',
        (ctx) async => 7,
      );
      final parent = solo.run<Initial, void>(key: 'parent', (ctx) async {
        ctx.emit(const Working());
        await ctx.run(child);
        continued = true;
      });

      async.flushMicrotasks();
      expect(child.outcome, isA<Done<int>>());
      expect(continued, isFalse);
      expect(parent.outcome, isA<Cancelled>());
      expect((parent.outcome! as Cancelled).reason, isA<RulesCancelReason>());
      expect(journal.take(), [
        '[parent] started',
        'state: Working(a: 0, b: 0)',
        '> [child] started',
        '> [child] finished Done(7)',
        '[parent] finished Cancelled(rules: is not Initial)',
      ]);
    });
  });

  test('run checks parent rules after a successful child cleanup', () {
    runSolo((solo, journal, async) {
      final order = <String>[];
      int? childValue;
      final child = solo.job<TestState, int>(
        key: 'child',
        cancellable: false,
        (ctx) async {
          ctx.onDispose(() async {
            order.add('cleanup starts');
            await delay(50);
            order.add('cleanup ends');
          });
          await delay(50);
          order.add('child body ends');
          return 7;
        },
      );
      child.value.then((value) => childValue = value).ignore();
      final parent = solo.run<Initial, void>(key: 'parent', (ctx) async {
        await ctx.run(child);
        order.add('parent continued');
      });
      final next = solo.run<TestState, void>(key: 'next', (ctx) async {
        order.add('next starts');
      });

      async.elapse(const Duration(milliseconds: 10));
      solo.externalSetState(const Working());
      async.elapse(const Duration(milliseconds: 40));
      expect(child.outcome, isNull, reason: 'cleanup is still running');
      expect(next.outcome, isNull, reason: 'the parent still owns the slot');

      async.elapse(const Duration(milliseconds: 50));
      expect(child.outcome, isA<Done<int>>());
      expect(childValue, 7, reason: 'the original handle keeps the value');
      expect(parent.outcome, isA<Cancelled>());
      expect((parent.outcome! as Cancelled).reason, isA<RulesCancelReason>());
      expect(next.outcome, isA<Done<void>>());
      expect(order, [
        'child body ends',
        'cleanup starts',
        'cleanup ends',
        'next starts',
      ]);
    });
  });

  test('run of a used job, after finish, or when cancelled', () {
    runSolo((solo, journal, async) {
      late SoloContext<TestState, TestState> leaked;
      final used = solo.job<TestState, void>(key: 'used', (ctx) async {});
      Object? secondRunError;
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        leaked = ctx;
        ctx.run(used).ignore();
        try {
          ctx.run(used).ignore();
        } on Object catch (error) {
          secondRunError = error;
        }
      });
      async.flushTimers();
      expect(secondRunError, isStateError, reason: 'the job is already used');
      expect(
        () => leaked.run(solo.job<TestState, void>((ctx) async {})),
        throwsStateError,
      );

      final orphan = solo.job<TestState, void>(key: 'orphan', (ctx) async {});
      solo.run<TestState, void>(key: 'cancelled', (ctx) async {
        await delay(100);
        ctx.run(orphan).ignore();
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.elapse(const Duration(milliseconds: 50));
      expect(orphan.outcome, isA<Cancelled>());
      expect((orphan.outcome! as Cancelled).reason, isA<ParentCancelReason>());
      expect((orphan.outcome! as Cancelled).started, isFalse);
      expect(orphan.level, 1);
      expect(orphan.isChild, isTrue);
      expect(journal.lines.last, '[cancelled] finished Cancelled(manual)');
    });
  });

  test('a queued job cannot be run as a child', () {
    runSolo((solo, journal, async) {
      final queued = solo.run<TestState, void>(key: 'queued', (ctx) async {});
      Object? thrown;
      solo.add(
        solo.job<TestState, void>(
          key: 'parent',
          (ctx) async {
            try {
              ctx.run(queued).ignore();
            } on Object catch (error) {
              thrown = error;
            }
          },
        ),
        first: true,
      );
      async.flushTimers();
      expect(thrown, isA<StateError>());
      expect(queued.outcome, isA<Done<void>>(), reason: 'ran once, by queue');
    });
  });

  test('a solo job is not adopted by a context of the core', () {
    runSolo((solo, journal, async) {
      final child = solo.job<TestState, void>(key: 'child', (ctx) async {});
      Object? thrown;
      ForeignJob<void>((ctx) async {
        try {
          ctx.run(child).ignore();
        } on Object catch (error) {
          thrown = error;
        }
      }).launch();
      async.flushTimers();
      expect(thrown, isA<ArgumentError>());
      expect(child.outcome, isNull, reason: 'never started, never dropped');
    });
  });

  test('solo refuses a job of the core as a child', () {
    runSolo((solo, journal, async) {
      var foreignRan = false;
      final parent = solo.run<TestState, void>(
        key: 'parent',
        (ctx) async {
          ctx.run(ForeignJob<void>((_) async => foreignRan = true)).ignore();
        },
      )..ignore();
      async.flushTimers();
      expect(foreignRan, isFalse);
      expect(parent.outcome, isA<Failed>());
      expect((parent.outcome! as Failed).error, isA<ArgumentError>());
    });
  });

  test('the waiting list of a parent shrinks as children finish', () {
    fakeAsync((async) {
      // The list of children is protected; the double of the core reads it,
      // and being a subclass is all it takes.
      late final ForeignJob<void> parent;
      final counts = <int>[];
      parent = ForeignJob<void>((ctx) async {
        for (var i = 0; i < 3; i++) {
          await ctx.run(
            ForeignJob<void>(
              key: 'child$i',
              (ctx) async {
                await ctx.wait(() => delay(10));
              },
            ),
          );
          counts.add(parent.childCount);
        }
      })
        ..launch();
      async.flushTimers();
      expect(parent.outcome, isA<Done<void>>());
      expect(counts, [0, 0, 0], reason: 'each child leaves as it finishes');
    });
  });

  test('a child without a key still shows in the parent outcome', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      final parent = solo.run<Preparing, void>(
        key: 'parent',
        (ctx) async {
          await ctx.run(solo.job<Working, void>((ctx) async {}));
        },
      );
      async.flushTimers();
      expect(
        parent.outcome.toString(),
        'Cancelled(handler: child null: Cancelled(rules: is not Working))',
      );
    });
  });

  test('a start rule of a child that throws reaches the observer', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        try {
          ctx
              .run(
                solo.job<TestState, void>(
                  key: 'child',
                  canStart: (state) => throw StateError('rule boom'),
                  (childCtx) async {},
                ),
              )
              .ignore();
        } on Object catch (_) {
          // The parent handles it and ends `Done`; the failure of the
          // child still has to be heard.
        }
      });
      async.flushTimers();
      expect(
        journal.take(),
        containsAllInOrder([
          '> [child] error Bad state: rule boom',
          '> [child] finished Failed(Bad state: rule boom)',
        ]),
      );
    });
  });
}
