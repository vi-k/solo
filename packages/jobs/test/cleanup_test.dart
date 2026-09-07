@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

void main() {
  test('onDispose runs on every outcome', () {
    for (final scenario in ['done', 'failed', 'cancelled']) {
      fakeAsync((async) {
        final order = <String>[];
        final job = Job<int>((ctx) async {
          ctx.onDispose(() => order.add('disposed'));
          await ctx.wait(() => delay(10));
          if (scenario == 'failed') {
            throw StateError('boom');
          }
          return 1;
        })
          ..ignore();
        // Five milliseconds so the body starts and registers: a job
        // cancelled before that never runs its body at all.
        async.elapse(const Duration(milliseconds: 5));
        if (scenario == 'cancelled') {
          job.cancel().ignore();
        }
        async.flushTimers();
        expect(order, ['disposed'], reason: 'scenario: $scenario');
      });
    }
  });

  test('onDiscard is silent on Done and runs on the other two', () {
    for (final scenario in ['done', 'failed', 'cancelled']) {
      fakeAsync((async) {
        final order = <String>[];
        final job = Job<int>((ctx) async {
          ctx.onDiscard(() => order.add('discarded'));
          await ctx.wait(() => delay(10));
          if (scenario == 'failed') {
            throw StateError('boom');
          }
          return 1;
        })
          ..ignore();
        async.elapse(const Duration(milliseconds: 5));
        if (scenario == 'cancelled') {
          job.cancel().ignore();
        }
        async.flushTimers();
        expect(
          order,
          scenario == 'done' ? <String>[] : ['discarded'],
          reason: 'scenario: $scenario',
        );
      });
    }
  });

  test('the stack unwinds last in, first out', () {
    fakeAsync((async) {
      final order = <String>[];
      Job<void>((ctx) async {
        ctx
          ..onDispose(() => order.add('first'))
          ..onDiscard(() => order.add('second'))
          ..onDispose(() => order.add('third'));
        await ctx.wait(() => delay(10));
        throw StateError('boom');
      }).ignore();
      async.flushTimers();
      expect(order, ['third', 'second', 'first']);
    });
  });

  test('children run before the cleanup, and the outcome waits for it', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        ctx
          ..onDispose(() async {
            order.add('cleanup starts');
            await delay(50);
            order.add('cleanup ends');
          })
          ..run(
            Job.deferred<void>(
              key: 'child',
              (ctx) async {
                await ctx.wait(() => delay(30));
                order.add('child');
              },
            ),
          );
      });
      job.done.then((_) => order.add('finished')).ignore();
      async.flushTimers();
      expect(order, [
        'child',
        'cleanup starts',
        'cleanup ends',
        'finished',
      ]);
    });
  });

  test('an unregistered cleanup does not run, and dropping twice is safe', () {
    fakeAsync((async) {
      final order = <String>[];
      Job<void>((ctx) async {
        ctx.onDispose(() => order.add('kept'));
        final dropTwice = ctx.onDispose(() => order.add('dropped'))..call();
        dropTwice();
        await ctx.wait(() => delay(10));
      }).ignore();
      async.flushTimers();
      expect(order, ['kept']);
    });
  });

  test('a cleanup may register another one', () {
    fakeAsync((async) {
      final order = <String>[];
      Job<void>((ctx) async {
        ctx.onDispose(() {
          order.add('outer');
          ctx.onDispose(() => order.add('nested'));
        });
      }).ignore();
      async.flushTimers();
      expect(order, ['outer', 'nested']);
    });
  });

  test('an error of a cleanup goes to the observer and the rest still runs',
      () {
    fakeAsync((async) {
      final errors = <Object>[];
      final order = <String>[];
      final job = Job<int>(
        observer: _CollectingObserver(errors),
        (ctx) async {
          ctx
            ..onDispose(() => order.add('below'))
            ..onDispose(() => throw StateError('cleanup failed'));
          return 7;
        },
      );
      async.flushTimers();
      expect(order, ['below']);
      expect(errors.single, isA<StateError>());
      expect(job.outcome, isA<Done<int>>());
    });
  });

  test('a cancellation arriving during the cleanup still discards', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<int>((ctx) async {
        // The order of the two registrations is the point of this test:
        // the `discard` sits above the slow `dispose`, so it is taken off
        // first, skipped while the outcome is `Done`, and only the second
        // pass can bring it back.
        ctx
          ..onDispose(() async {
            order.add('slow starts');
            await delay(100);
            order.add('slow ends');
          })
          ..onDiscard(() => order.add('discarded'));
        return 7;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 50));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['slow starts', 'slow ends', 'discarded']);
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('registering stays open on a job already cancelled', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        try {
          await ctx.wait(() => delay(50));
        } on Cancelled {
          // The body is unwinding: registering a cleanup here has to work,
          // or the trap this whole mechanism removes is back.
          ctx.onDispose(() => order.add('registered while cancelled'));
          rethrow;
        }
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['registered while cancelled']);
    });
  });

  test('registering on a job that has finished is a StateError', () {
    fakeAsync((async) {
      late JobContext leaked;
      Job<void>((ctx) async => leaked = ctx).ignore();
      async.flushTimers();
      expect(() => leaked.onDispose(() {}), throwsStateError);
    });
  });
}

class _CollectingObserver extends JobObserver {
  _CollectingObserver(this.errors);

  final List<Object> errors;

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add(error);
}
