// `ctx.child` in `solo`: what a child made by a `SoloContext` gets. The
// code on `JobContext` it was made for is in `child_shared_code_test.dart`.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/compile_errors.dart';
import 'support/run_solo.dart';
import 'support/test_state.dart';

Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

Matcher cancelledBy<T>() => isA<Cancelled>().having(
  (cancelled) => cancelled.reason,
  'reason',
  isA<T>(),
);

void main() {
  test('the child gets a SoloContext with the state and emit', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      Object? seen;
      solo.enqueue<Preparing, void>((ctx) async {
        await ctx.run(
          ctx.child((child) async {
            seen = child;
            child.emit(child.state.copyWith(progress: 5));
          }),
        );
      });
      async.flushTimers();
      expect(seen, isA<SoloContext<TestState, Preparing>>());
      expect(solo.currentState, const Preparing(progress: 5));
    });
  });

  group('the rules of the job that made the child', () {
    test('hold after its body has ended, and turn the child away', () {
      runSolo(initialState: const Preparing(), (solo, journal, async) {
        late final SoloJob<void> child;
        solo.enqueue<Preparing, void>(
          key: 'maker',
          keepWhile: (state) => state.progress < 50,
          (ctx) async {
            child = ctx.child(key: 'child', (ctx) async {});
          },
        );
        async.flushTimers();
        solo.externalSetState(const Preparing(progress: 60));
        Object? thrown;
        final runner = solo.enqueue<TestState, void>(key: 'runner', (
          ctx,
        ) async {
          try {
            await ctx.run(child);
          } on Cancelled catch (cancelled) {
            thrown = cancelled;
          }
        });
        async.flushTimers();
        expect(child.outcome, cancelledBy<RulesCancelReason>());
        expect(thrown, same(child.outcome));
        expect(runner.outcome, isA<Done<void>>());
      });
    });

    test('cancel a child that runs under another job', () {
      runSolo(initialState: const Preparing(), (solo, journal, async) {
        late final SoloJob<void> child;
        solo.enqueue<Preparing, void>(
          keepWhile: (state) => state.progress < 50,
          (ctx) async {
            child = ctx.child((ctx) => ctx.abandonable(() => delay(100)));
          },
        );
        async.flushTimers();
        final runner = solo.enqueue<TestState, void>((ctx) => ctx.run(child))
          ..ignoreFailure();
        async.elapse(ms(10));
        expect(child.outcome, isNull, reason: 'the child is running');
        solo.externalSetState(const Preparing(progress: 60));
        async.flushTimers();
        expect(child.outcome, cancelledBy<RulesCancelReason>());
        expect(runner.outcome, cancelledBy<HandlerCancelReason>());
      });
    });

    test('keep the working type of the job that made the child', () {
      runSolo(initialState: const Preparing(), (solo, journal, async) {
        late final SoloJob<void> child;
        solo.enqueue<Preparing, void>((ctx) async {
          child = ctx.child((ctx) async {});
        });
        async.flushTimers();
        solo.externalSetState(const Working());
        // Another working type: the child is still the maker's.
        final runner = solo.enqueue<Working, void>((ctx) => ctx.run(child))
          ..ignoreFailure();
        async.flushTimers();
        expect(child.outcome, cancelledBy<RulesCancelReason>());
        expect(runner.outcome, cancelledBy<HandlerCancelReason>());
      });
    });

    test('leave canStart out and cancellable: false to the maker', () {
      runSolo(initialState: const Preparing(), (solo, journal, async) {
        late final SoloJob<int> child;
        late final SoloJob<int> held;
        solo.enqueue<Preparing, void>(
          canStart: (state) => state.progress == 0,
          cancellable: false,
          (ctx) async {
            child = ctx.child((ctx) async => 7);
            held = ctx.child((ctx) async {
              await ctx.abandonable(() => delay(50));
              return 8;
            });
          },
        );
        async.flushTimers();
        solo.externalSetState(const Preparing(progress: 10));
        int? value;
        solo.enqueue<TestState, void>((ctx) async {
          value = await ctx.run(child);
          ctx.start(held);
          held.cancel().ignore();
        });
        async.flushTimers();
        expect(value, 7, reason: 'canStart of the maker is not asked again');
        expect(held.outcome, cancelledBy<ManualCancelReason>());
      });
    });
  });

  test('child checks nothing: not the rules, nor the end of the job', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      final made = <String, SoloJob<void>>{};
      late final SoloContext<TestState, Preparing> leaked;
      solo.enqueue<Preparing, void>(keepWhile: (state) => state.progress < 50, (
        ctx,
      ) async {
        leaked = ctx;
        ctx
          ..unattended(() async {
            made['unattended'] = ctx.child((ctx) async {});
          })
          ..onDispose(() {
            made['cleanup'] = ctx.child((ctx) async {});
          });
      });
      async.flushTimers();
      solo.externalSetState(const Preparing(progress: 60));
      made['finished, its rules broken'] = leaked.child((ctx) async {});
      expect(made.keys, [
        'unattended',
        'cleanup',
        'finished, its rules broken',
      ]);
      for (final child in made.values) {
        expect(child.outcome, isNull);
      }
      // Another job runs them: the rules of the maker refuse at the start.
      solo.externalSetState(const Preparing(progress: 10));
      final ran = solo.enqueue<TestState, void>((ctx) async {
        await ctx.run(made['unattended']!);
        await ctx.run(made['cleanup']!);
      });
      async.flushTimers();
      expect(ran.outcome, isA<Done<void>>());
      solo.externalSetState(const Preparing(progress: 60));
      final refused = made['finished, its rules broken']!;
      solo.enqueue<TestState, void>((ctx) => ctx.run(refused)).ignoreFailure();
      async.flushTimers();
      expect(refused.outcome, cancelledBy<RulesCancelReason>());
    });
  });

  test('a timeout of zero or less throws from child, before run', () {
    runSolo((solo, journal, async) {
      final thrown = <Object>[];
      solo.enqueue<TestState, void>((ctx) async {
        for (final timeout in [Duration.zero, ms(-1)]) {
          try {
            ctx.child(timeout: timeout, (ctx) async {}).cancel().ignore();
          } on Object catch (error) {
            thrown.add(error);
          }
        }
      });
      async.flushTimers();
      expect(thrown, [isArgumentError, isArgumentError]);
    });
  });

  test('a child nobody started is left out of close, until cancelled', () {
    runSolo((solo, journal, async) {
      late final SoloJob<void> child;
      solo.enqueue<TestState, void>((ctx) async {
        child = ctx.child(timeout: ms(10), (ctx) async {});
      });
      async.flushTimers();
      expect(async.pendingTimers, isEmpty, reason: 'its deadline does not run');
      var closed = false;
      var done = false;
      solo.close().then((_) => closed = true).ignore();
      child.done.then((_) => done = true).ignore();
      async.flushTimers();
      expect(closed, isTrue);
      expect(done, isFalse);
      child.cancel().ignore();
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(child.outcome, cancelledBy<ManualCancelReason>());
    });
  });

  test('start and runAll take children of child', () {
    runSolo((solo, journal, async) {
      late final SoloJob<void> started;
      late final SoloJob<void> sibling;
      Object? thrown;
      solo.enqueue<TestState, void>((ctx) async {
        started = ctx.child((ctx) async {});
        ctx.start(started);
        sibling = ctx.child((ctx) => ctx.abandonable(() => delay(50)));
        try {
          await ctx.runAll<void>([
            ctx.child((ctx) async {
              await ctx.abandonable(() => delay(10));
              throw const FormatException('broken');
            }),
            sibling,
          ]);
        } on FormatException catch (error) {
          thrown = error;
        }
      });
      async.flushTimers();
      expect(started.outcome, isA<Done<void>>());
      expect('$thrown', 'FormatException: broken');
      expect(sibling.outcome, cancelledBy<SiblingCancelReason>());
    });
  });

  test(
    'a child made and dropped is a warning, through either context',
    () async {
      final warnings = await compileWarnings('''
import 'package:solo/solo.dart';

void shared(JobContext ctx) {
  ctx.child<void>((ctx) async {});
}

void ofSolo(SoloContext<Object, Object> ctx) {
  ctx.child<void>((ctx) async {});
}
''');
      expect(warnings, [
        startsWith('unused_result:'),
        startsWith('unused_result:'),
      ]);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
