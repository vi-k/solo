@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('a branch a rule turns away ends without a body, and is the outcome',
      () {
    runSolo((solo, journal, async) {
      var refusedBodyRan = false;
      final bodies = <String>[];
      Object? thrown;
      Outcome<void>? refusedOutcome;
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        // The state is `Initial`, so the rule of the second branch turns
        // it away: it ends without ever entering its body, and the other
        // two still start.
        final refused = solo.job<Working, void>(key: 'b', (ctx) async {
          refusedBodyRan = true;
        });
        try {
          await ctx.runAll(<Job<void>>[
            solo.job<TestState, void>(key: 'a', (ctx) async {
              bodies.add('a');
              await pause(ctx, 50);
            }),
            refused,
            solo.job<TestState, void>(key: 'c', (ctx) async {
              bodies.add('c');
              await pause(ctx, 50);
            }),
          ]);
        } on Object catch (error) {
          thrown = error;
        }
        refusedOutcome = refused.outcome;
      });
      async.flushTimers();
      expect(refusedBodyRan, isFalse);
      expect(bodies, ['a', 'c'], reason: 'the other branches still start');
      expect(
        refusedOutcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<RulesCancelReason>(),
        ),
      );
      expect(thrown, same(refusedOutcome));
    });
  });

  test('a rule that throws ends the branch and the observer hears it', () {
    runSolo((solo, journal, async) {
      Object? thrown;
      late SoloJob<void> started;
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        started = solo.job<TestState, void>(key: 'a', (ctx) async {
          await pause(ctx, 50);
        });
        try {
          await ctx.runAll(<Job<void>>[
            started,
            solo.job<TestState, void>(
              key: 'b',
              canStart: (state) => throw StateError('rule boom'),
              (ctx) async {},
            ),
          ]);
        } on Object catch (error) {
          thrown = error;
        }
      });
      async.flushTimers();
      expect(thrown, isA<StateError>());
      expect(
        started.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<SiblingCancelReason>(),
        ),
        reason: 'whatever started is stopped and waited for',
      );
      expect(
        journal.take(),
        containsAllInOrder(['> [b] error Bad state: rule boom']),
        reason: 'the domain announces it, unlike the bare core',
      );
    });
  });

  test('a failure the group did not throw reaches the handler of the engine',
      () {
    runSolo((solo, journal, async) {
      final answered = <Object>[];
      Solo.errorHandler = (solo, job, error, stackTrace) => answered.add(error);
      final chosen = StateError('chosen');
      final other = StateError('other');
      Object? thrown;
      solo.run<TestState, void>(key: 'parent', (ctx) async {
        try {
          await ctx.runAll(<Job<void>>[
            solo.job<TestState, void>(key: 'a', (ctx) async => throw chosen),
            solo.job<TestState, void>(
              key: 'b',
              cancellable: false,
              (ctx) async {
                await pause(ctx, 50);
                throw other;
              },
            ),
          ]);
        } on Object catch (error) {
          thrown = error;
        }
      });
      async.flushTimers();
      expect(thrown, same(chosen));
      expect(
        answered,
        [same(other)],
        reason: 'the one nobody received, and it alone',
      );
      expect(
        journal
            .take()
            .where((line) => line.contains('error Bad state: other'))
            .toList(),
        ['> [b] error Bad state: other'],
        reason: 'the branch tells the observer once; the group never does',
      );
    });
  });
}
