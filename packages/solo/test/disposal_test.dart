@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('reading the state from a disposer is a StateError, not a flip', () {
    runSolo((solo, journal, async) {
      final errors = <Object>[];
      final job = solo.run<Initial, int>(
        key: 'load',
        (ctx) async {
          ctx.onDispose(() {
            // Without the ban this read would check the rules against the
            // state the body itself emitted, and turn the outcome into
            // `Cancelled(rules)`.
            try {
              ctx.state;
            } on Object catch (error) {
              errors.add(error);
            }
          });
          await pause(ctx, 10);
          ctx.emit(const Working(a: 7));
          return 7;
        },
      );
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      expect(errors.single, isA<StateError>());
      expect('${errors.single}', contains('is disposing'));
    });
  });

  test('emit from a disposer is a StateError the observer sees', () {
    runSolo((solo, journal, async) {
      final job = solo.run<Initial, int>(
        key: 'load',
        (ctx) async {
          ctx.onDispose(() => ctx.emit(const Working(a: 1)));
          return 7;
        },
      );
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      // The observer is installed by `runSolo`. Without one an error of a
      // disposer reaches nobody in `solo`, and this test would be green on
      // silence.
      expect(
        journal.lines.where((line) => line.contains('error Bad state')),
        hasLength(1),
      );
    });
  });

  test('check, disown and emit hand the value over in one go', () {
    fakeAsync((async) {
      final solo = _ReentrantSolo();
      final closed = <String>[];
      final job = solo.run<Initial, void>(
        key: 'load',
        (ctx) async {
          final db = await ctx.join(() async => 'db', discard: closed.add);
          // The hook replaces the state from inside `onChange`, so `emit`
          // throws after the write — but the disown is already behind us.
          ctx
            ..check()
            ..disown(db)
            ..emit(Working(a: db.length));
        },
      )..ignore();
      async.flushTimers();
      expect(closed, isEmpty, reason: 'the database went into the state');
      expect(job.outcome, isA<Cancelled>(), reason: 'the hook cancelled it');
      solo.close();
      async.flushTimers();
    });
  });

  test('join inside an uncancellable section breaks the pair', () {
    runSolo((solo, journal, async) {
      final rolled = <String>[];
      final job = solo.run<Initial, void>(
        key: 'load',
        (ctx) async {
          final tx = await ctx.join(() async => 'tx', dispose: rolled.add);
          await ctx.uncancellable(() async {
            // Not how it should be written, and this test documents why:
            // inside a section `join` throws after its step on a
            // cancellation by the rules, and the disown never happens.
            await ctx.join(() => delay(10));
            ctx.disown(tx);
          });
        },
      )..ignore();
      async.elapse(const Duration(milliseconds: 5));
      solo.externalSetState(const Working(a: 1));
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(rolled, ['tx'], reason: 'the disown never happened');
    });
  });

  test('a state change during the cleanup no longer cancels by rules', () {
    runSolo((solo, journal, async) {
      final closed = <String>[];
      final job = solo.run<Initial, int>(
        key: 'load',
        (ctx) async {
          final db = await ctx.join(() async => 'db', discard: closed.add);
          ctx
            ..onDispose(() async => delay(50))
            // The form from the README: the working type is `Initial`, the
            // last state is outside it, and the value goes to the caller.
            ..emit(const Working(a: 7));
          return db.length;
        },
      );
      // While the disposer sleeps, the outside world sets a state: the
      // rules of the job no longer hold, but the body is gone and there is
      // nothing left for them to guard.
      async.elapse(const Duration(milliseconds: 10));
      solo.externalSetState(const Working(a: 4));
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      expect(closed, isEmpty, reason: 'the value went to the caller');
    });
  });

  test('restart waits for the cleanup of the job it replaces', () {
    runSolo((solo, journal, async) {
      final order = <String>[];
      solo.run<Initial, void>(
        key: 'load',
        policy: Policy.restart,
        (ctx) async {
          ctx.onDispose(() async {
            order.add('cleanup starts');
            await delay(50);
            order.add('cleanup ends');
          });
          await pause(ctx, 10);
        },
      ).ignore();
      async.elapse(const Duration(milliseconds: 5));
      // The next job of the same queue starts only after `finish`, and
      // that waits for the cleanup.
      solo
          .run<Initial, void>(
            key: 'load',
            policy: Policy.restart,
            (ctx) async => order.add('second starts'),
          )
          .ignore();
      async.flushTimers();
      expect(order, ['cleanup starts', 'cleanup ends', 'second starts']);
    });
  });

  test('reads after the job has finished are still legal', () {
    runSolo((solo, journal, async) {
      late SoloContext<TestState, Initial> leaked;
      solo
          .run<Initial, void>(
            key: 'load',
            (ctx) async => leaked = ctx,
          )
          .ignore();
      async.flushTimers();
      expect(() => leaked.state, returnsNormally);
      expect(leaked.check, returnsNormally);
    });
  });
}

/// A controller whose hook replaces the state from inside `onChange`.
final class _ReentrantSolo extends Solo<TestState> {
  _ReentrantSolo() : super(const Initial());

  @override
  void onChange(TestState previous, TestState current) {
    if (current is Working) {
      externalSetState(const Disposed());
    }
  }
}
