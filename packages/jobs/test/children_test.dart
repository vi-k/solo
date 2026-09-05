@Timeout(Duration(seconds: 5))
library;

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
      final parent = Job<void>((ctx) async {
        child = ctx.run(
          Job.deferred<void>(
            key: 'child',
            cancellable: false,
            (ctx) => ctx.wait(() => delay(50)),
          ),
        );
        await ctx.wait(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      async.flushTimers();
      expect(child.outcome, isA<Done<void>>());
      expect(async.elapsed.inMilliseconds, greaterThanOrEqualTo(50));
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
}

/// A handle that implements [Job] without being a job of this core.
final class _ForeignJob implements Job<void> {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
