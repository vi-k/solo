// `ctx.child`: a child made through the context, for code that holds only
// a context.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/compile_errors.dart';
import 'support/delay.dart';
import 'support/journal.dart';

Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// A step that takes [milliseconds] and gives up on a cancellation.
Future<int> Function(JobContext ctx) step(int milliseconds, [int value = 1]) =>
    (ctx) async {
      await ctx.abandonable(() => delay(milliseconds));
      return value;
    };

void main() {
  test('a child made by the context runs and hands its value over', () {
    fakeAsync((async) {
      final journal = JobJournal();
      int? value;
      final parent = Job<void>(key: 'parent', observer: journal, (ctx) async {
        value = await ctx.run(
          ctx.child(step(10, 7), key: 'rows', describe: () => 'load'),
        );
      });
      async.flushTimers();
      expect(value, 7);
      expect(parent.outcome, isA<Done<void>>());
      expect(journal.take(), [
        '[parent] started',
        '> [rows: load] started',
        '> [rows: load] finished Done(7)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  group('the timeout of a child', () {
    test('caught, it leaves the parent uncancelled', () {
      fakeAsync((async) {
        Cancelled? caught;
        bool? parentCancelledThen;
        late final Job<String> parent;
        parent = Job<String>((ctx) async {
          try {
            await ctx.run(ctx.child(step(50), timeout: ms(10)));
          } on Cancelled catch (cancelled) {
            caught = cancelled;
            parentCancelledThen = parent.isCancelled;
          }
          return 'fallback';
        });
        async.flushTimers();
        expect(caught!.reason, isA<TimeoutCancelReason>());
        expect((caught!.reason as TimeoutCancelReason).timeout, ms(10));
        expect(parentCancelledThen, isFalse);
        expect(parent.value, completion('fallback'));
        async.flushMicrotasks();
      });
    });

    test('let out, it ends the parent as a handler cancellation', () {
      fakeAsync((async) {
        final parent = Job<int>(
          (ctx) => ctx.run(ctx.child(step(50), timeout: ms(10))),
        )..ignoreFailure();
        async.flushTimers();
        final reason = (parent.outcome! as Cancelled).reason;
        expect(reason, isA<HandlerCancelReason>());
        expect(
          (reason as HandlerCancelReason).cause!.reason,
          isA<TimeoutCancelReason>(),
        );
      });
    });
  });

  test('a timeout of zero or less throws from child, before run', () {
    fakeAsync((async) {
      final thrown = <Object>[];
      var reachedRun = false;
      Job<void>((ctx) async {
        for (final timeout in [Duration.zero, ms(-1)]) {
          try {
            final child = ctx.child(step(10), timeout: timeout);
            reachedRun = true;
            await ctx.run(child);
          } on Object catch (error) {
            thrown.add(error);
          }
        }
      });
      async.flushTimers();
      expect(thrown, [isArgumentError, isArgumentError]);
      expect(reachedRun, isFalse);
    });
  });

  group('a child nobody started', () {
    test('belongs to its holder: no deadline, no done, until cancelled', () {
      fakeAsync((async) {
        late final ChildJob<int> child;
        final maker = Job<void>((ctx) async {
          child = ctx.child(step(10), timeout: ms(10));
        });
        var done = false;
        async.flushMicrotasks();
        child.done.then((_) => done = true).ignore();
        async.elapse(const Duration(seconds: 1));
        expect(maker.outcome, isA<Done<void>>());
        expect(child.isRunning, isFalse);
        expect(child.outcome, isNull);
        expect(done, isFalse);

        child.cancel().ignore();
        async.flushMicrotasks();
        final outcome = child.outcome! as Cancelled;
        expect(outcome.reason, isA<ManualCancelReason>());
        expect(outcome.started, isFalse);
        expect(done, isTrue);
      });
    });

    test('is taken by start and by runAll', () {
      fakeAsync((async) {
        late final ChildJob<int> started;
        List<int>? all;
        Job<void>((ctx) async {
          started = ctx.child(step(10));
          ctx.start(started);
          all = await ctx.runAll([
            ctx.child(step(10, 2)),
            ctx.child(step(20, 3)),
          ]);
        });
        async.flushTimers();
        expect(started.outcome, isA<Done<int>>());
        expect(all, [2, 3]);
      });
    });
  });

  group('child makes a child wherever run refuses one', () {
    void expectRefused(Object? error, String message) => expect(
      error,
      isA<StateError>().having((e) => e.message, 'message', contains(message)),
    );

    test('in unattended work', () {
      fakeAsync((async) {
        ChildJob<int>? child;
        Object? thrown;
        Job<void>((ctx) async {
          ctx.unattended(() async {
            child = ctx.child(step(10));
            try {
              ctx.run(child!).ignore();
            } on Object catch (error) {
              thrown = error;
            }
          });
        });
        async.flushTimers();
        expect(child, isNotNull);
        expectRefused(thrown, 'inside unattended work');
        expect(child!.outcome, isNull);
        child!.cancel().ignore();
        async.flushMicrotasks();
      });
    });

    test('in cleanup', () {
      fakeAsync((async) {
        ChildJob<int>? child;
        Object? thrown;
        Job<void>((ctx) async {
          ctx.onDispose(() {
            child = ctx.child(step(10));
            try {
              ctx.run(child!).ignore();
            } on Object catch (error) {
              thrown = error;
            }
          });
        });
        async.flushTimers();
        expect(child, isNotNull);
        expectRefused(thrown, 'is cleaning up after its body');
        expect(child!.outcome, isNull);
        child!.cancel().ignore();
        async.flushMicrotasks();
      });
    });

    test('after the body has ended', () {
      fakeAsync((async) {
        ChildJob<int>? child;
        Object? thrown;
        Job<void>((ctx) async {
          ctx.start(ctx.child(step(50)));
          Timer(ms(10), () {
            child = ctx.child(step(10));
            try {
              ctx.run(child!).ignore();
            } on Object catch (error) {
              thrown = error;
            }
          });
        });
        async.flushTimers();
        expect(child, isNotNull);
        expectRefused(thrown, 'has ended its body');
        expect(child!.outcome, isNull);
        child!.cancel().ignore();
        async.flushMicrotasks();
      });
    });

    test('on a finished job', () {
      fakeAsync((async) {
        late final JobContext leaked;
        Job<void>((ctx) async {
          leaked = ctx;
        });
        async.flushMicrotasks();
        final child = leaked.child(step(10));
        expect(
          () => leaked.run(child),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('has already finished'),
            ),
          ),
        );
        expect(child.outcome, isNull);
        child.cancel().ignore();
        async.flushMicrotasks();
      });
    });

    test('and on a cancelled job run drops it with the parent', () {
      fakeAsync((async) {
        late final ChildJob<int> child;
        Object? thrown;
        final parent = Job<void>((ctx) async {
          try {
            await ctx.abandonable(() => delay(50));
          } on Cancelled {
            // The wait gives up first; the body walks on to `run` anyway.
          }
          child = ctx.child(step(10));
          try {
            ctx.run(child).ignore();
          } on Object catch (error) {
            thrown = error;
          }
        });
        async.elapse(ms(10));
        parent.cancel().ignore();
        async.flushTimers();
        expect(thrown, same(parent.outcome));
        final outcome = child.outcome! as Cancelled;
        expect(outcome.reason, isA<ParentCancelReason>());
        expect(outcome.started, isFalse);
      });
    });
  });

  group('a child handed to another job', () {
    test('runs there', () {
      fakeAsync((async) {
        final maker = JobJournal();
        final runner = JobJournal();
        late final ChildJob<int> child;
        Job<void>(key: 'maker', observer: maker, (ctx) async {
          child = ctx.child(key: 'child', step(10, 5));
        });
        async.flushMicrotasks();
        maker.take();
        int? value;
        final other = Job<void>(key: 'runner', observer: runner, (ctx) async {
          value = await ctx.run(child);
        });
        async.flushTimers();
        expect(value, 5);
        expect(other.outcome, isA<Done<void>>());
        expect(maker.take(), isEmpty);
        expect(runner.take(), [
          '[runner] started',
          '> [child] started',
          '> [child] finished Done(5)',
          '[runner] finished Done(null)',
        ]);
      });
    });

    test('has the job that started it for a parent', () {
      fakeAsync((async) {
        late final ChildJob<int> child;
        Job<void>((ctx) async {
          child = ctx.child(step(50));
        });
        async.flushMicrotasks();
        final other = Job<void>((ctx) => ctx.run(child))..ignoreFailure();
        async.elapse(ms(10));
        expect(child.isRunning, isTrue);
        other.cancel().ignore();
        async.flushTimers();
        final outcome = child.outcome! as Cancelled;
        expect(outcome.reason, isA<ParentCancelReason>());
        expect(
          (outcome.reason as ParentCancelReason).cause,
          same(other.outcome),
        );
      });
    });
  });

  test('inside uncancellable the parent is held and the deadline is not', () {
    fakeAsync((async) {
      late final ChildJob<int> child;
      final parent = Job<void>((ctx) async {
        await ctx.uncancellable(() async {
          child = ctx.child(step(50), timeout: ms(20));
          try {
            await ctx.run(child);
          } on Cancelled {
            // The deadline of the child: the section goes on to its end.
          }
        });
      });
      async.elapse(ms(5));
      parent.cancel().ignore();
      async.elapse(ms(10));
      expect(child.isRunning, isTrue, reason: 'the section holds the cascade');
      async.flushTimers();
      expect((child.outcome! as Cancelled).reason, isA<TimeoutCancelReason>());
      expect((parent.outcome! as Cancelled).reason, isA<ManualCancelReason>());
    });
  });

  test('a child dropped in the body of an engine is a warning', () async {
    // The context of an engine's body is typed with its own class, and an
    // override does not inherit `@useResult`: `JobContextBase` keeps it.
    final warnings = await compileWarnings('''
import 'package:async_job/engine.dart';

final class MyContext extends JobContextBase {
  MyContext(super.owner);
}

void ofEngine(MyContext ctx) {
  ctx.child<void>((ctx) async {});
}
''');
    expect(warnings, [startsWith('unused_result:')]);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
