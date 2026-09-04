@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

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
          await ctx.run(test3).done;
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
          final child = ctx.run(test2);
          childAtRun = (
            level: child.level,
            isChild: child.isChild,
            isRunning: child.isRunning,
          );
          await child.done;
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
        final child = ctx.run(
          solo.job<Working, void>(key: 'child', (childCtx) async {
            childBodyRan = true;
          }),
        );
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

  test('await value of a child dropped at run reports the child', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        final child = solo.job<Working, void>(key: 'child', (ctx) async {});
        await ctx.run(child).value;
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
        ctx.run(child);
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
          await ctx.run(grandchild).done;
          ctx.check();
        });
        await ctx.run(child).done;
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
        unawaited(ctx.job.whenCancelled.then((_) => marked.add('parent')));
        final child = solo.job<TestState, void>(key: 'child', (ctx) async {
          unawaited(ctx.job.whenCancelled.then((_) => marked.add('child')));
          final grandchild = solo.job<TestState, void>(
            key: 'grandchild',
            (ctx) async {
              unawaited(
                ctx.job.whenCancelled.then((_) => marked.add('grandchild')),
              );
              await delay(100);
              ctx.check();
            },
          );
          await ctx.run(grandchild).done;
          ctx.check();
        });
        await ctx.run(child).done;
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

  test('await child.value propagates the child cancellation as handler', () {
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
        await ctx.run(child).value;
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
        final child = ctx.run(
          solo.job<Preparing, void>(
            key: 'child',
            keepWhile: (state) => state.progress < 50,
            (ctx) async {
              await delay(100);
              ctx.check();
            },
          ),
        );
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

  test('a failed child reports onError and fails the parent via value', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        final child = solo.job<TestState, void>(key: 'child', (ctx) async {
          throw StateError('boom');
        });
        await ctx.run(child).value;
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
          await ctx.run(child).done;
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
        await ctx.run(child).done;
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
        final a = ctx.run(
          solo.job<Working, void>(
            key: 'a',
            keepWhile: (state) => state.b == 0,
            (ctx) async {
              await delay(100);
              ctx.emit(ctx.state.copyWith(a: 1));
            },
          ),
        );
        final jobB = solo.job<Working, void>(key: 'b', (ctx) async {
          await delay(50);
          ctx.emit(ctx.state.copyWith(b: 1));
        });
        final b = ctx.run(jobB);
        await Future.wait([a.done, b.done]);
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
        await ctx
            .run(
              solo.job<TestState, void>(
                key: 'child',
                cancellable: false,
                (ctx) async {
                  await delay(100);
                  ctx.emit(const Preparing());
                },
              ),
            )
            .done;
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

  test('run of a used job, after finish, or when cancelled', () {
    runSolo((solo, journal, async) {
      late JobContext<TestState, TestState> leaked;
      final used = solo.job<TestState, void>(key: 'used', (ctx) async {});
      Object? secondRunError;
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        leaked = ctx;
        ctx.run(used);
        try {
          ctx.run(used);
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
        ctx.run(orphan);
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.elapse(const Duration(milliseconds: 50));
      expect(orphan.outcome, isA<Cancelled>());
      expect((orphan.outcome! as Cancelled).reason, CancelReason.parent);
      expect((orphan.outcome! as Cancelled).started, isFalse);
      expect(orphan.level, 1);
      expect(orphan.isChild, isTrue);
      expect(journal.lines.last, '[cancelled] finished Cancelled(manual)');
    });
  });
}
