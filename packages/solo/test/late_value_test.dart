@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('a value returned after cancellation goes to the disposer', () {
    runSolo((solo, journal, async) {
      final closed = <String>[];
      final job = solo.run<TestState, String>(
        key: 'open',
        (ctx) async {
          final resource = await ctx.join(() async {
            await delay(10);
            return 'db';
          });
          ctx
            ..onDiscard(() => closed.add(resource))
            // The child keeps the job alive past the return: without it
            // the body ends at 10 ms and no late value can exist.
            ..run(
              solo.job<TestState, void>(
                key: 'child',
                (ctx) => pause(ctx, 100),
              ),
            ).ignore();
          return resource;
        },
      );
      async.elapse(const Duration(milliseconds: 30));
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(
        closed,
        ['db'],
        reason: 'the outcome is the cancellation, the value still gets '
            'released',
      );
    });
  });

  test('close waits for the disposer of a cancelled job', () {
    runSolo((solo, journal, async) {
      final closed = <String>[];
      solo.run<TestState, String>(
        key: 'open',
        (ctx) async {
          final resource = await ctx.join(() async {
            await delay(10);
            return 'db';
          });
          ctx
            ..onDiscard(() async {
              await delay(50);
              closed.add(resource);
            })
            ..run(
              solo.job<TestState, void>(
                key: 'child',
                (ctx) => pause(ctx, 100),
              ),
            ).ignore();
          return resource;
        },
      );
      async.elapse(const Duration(milliseconds: 30));
      var closedAt = Duration.zero;
      solo.close().then((_) => closedAt = async.elapsed).ignore();
      async.flushTimers();
      expect(closed, ['db']);
      expect(closedAt.inMilliseconds, greaterThanOrEqualTo(80));
    });
  });

  test('an error of the disposer goes to onError, the cancel stands', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, String>(
        key: 'open',
        (ctx) async {
          final resource = await ctx.join(() async {
            await delay(10);
            return 'db';
          });
          ctx
            ..onDiscard(() => throw StateError('close failed'))
            ..run(
              solo.job<TestState, void>(
                key: 'child',
                (ctx) => pause(ctx, 100),
              ),
            ).ignore();
          return resource;
        },
      );
      async.elapse(const Duration(milliseconds: 30));
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(
        journal.take(),
        contains('[open] error Bad state: close failed'),
      );
    });
  });
}
