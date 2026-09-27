@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/error_observer.dart';
import 'support/journal.dart';
import 'support/probe_job.dart';

void main() {
  test('a value returned after cancellation goes to the disposer', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<String>((ctx) async {
        final resource = await ctx.join(() async {
          await delay(10);
          return 'db';
        });
        ctx.onDiscard(() => closed.add(resource));
        // The child keeps the job alive past the return.
        ctx
            .run(
              Job.deferred<void>(
                key: 'child',
                (ctx) => ctx.wait(() => delay(100)),
              ),
            )
            .ignore();
        return resource;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 30));
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(closed, ['db']);
    });
  });

  test('the disposer runs after the children and before the outcome', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<String>((ctx) async {
        ctx.onDiscard(() => order.add('disposer'));
        // Not started by hand: `run` starts it, and the cascade would
        // otherwise reach an already running child. Uncancellable, so
        // the cascade does not cut its wait short before it writes its
        // line.
        ctx
            .run(
              Job.deferred<void>(
                key: 'child',
                cancellable: false,
                (ctx) async {
                  await ctx.wait(() => delay(50));
                  order.add('child');
                },
              ),
            )
            .ignore();
        return 'db';
      });
      job.done.then((_) => order.add('done')).ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['child', 'disposer', 'done']);
    });
  });

  test('an error of the disposer goes to the observer, then the zone', () {
    final journal = JobJournal();
    final zone = <Object>[];
    late final Job<String> job;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          job = Job<String>(
            key: 'job',
            observer: journal,
            (ctx) async {
              ctx.onDiscard(() => throw StateError('close failed'));
              ctx
                  .run(
                    Job.deferred<void>(
                      key: 'child',
                      (ctx) => ctx.wait(() => delay(100)),
                    ),
                  )
                  .ignore();
              return 'db';
            },
          );
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => zone.add(error),
    );
    // Outside the guarded zone: an `expect` that fails inside it lands in
    // the handler and is counted as a zone error instead of failing.
    expect(job.outcome, isA<Cancelled>());
    expect(
      journal.take(),
      contains('[job] error Bad state: close failed'),
    );
    expect(
      zone.map((error) => '$error'),
      ['Bad state: close failed'],
      reason: 'an observer that only watches answers for nothing',
    );
  });

  test('without an observer the disposer error goes to the zone', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<String>((ctx) async {
            ctx.onDiscard(() => throw StateError('close failed'));
            ctx
                .run(
                  Job.deferred<void>((ctx) => ctx.wait(() => delay(100))),
                )
                .ignore();
            return 'db';
          });
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
          expect(job.outcome, isA<Cancelled>());
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught.map((error) => '$error').toList(), [
      'Bad state: close failed',
    ]);
  });
  test('a value that arrives during the cleanup is released before the end',
      () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        // Walked away from: the cancellation ends the wait, and the value
        // turns up later, while the engine is still unwinding the stack.
        // `ignore`, not `unawaited`: a `wait` left behind still completes
        // with the job's cancellation, and nobody is there to catch it.
        ctx.wait<String>(
          () => delay(50).then((_) => 'db'),
          discard: (value) async {
            order.add('discard starts');
            await delay(100);
            order.add('discard ends');
          },
        ).ignore();
        ctx.onDispose(() async {
          order.add('dispose starts');
          await delay(50);
          order.add('dispose ends');
        });
        await ctx.wait(() => delay(200));
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 10));
      job
        ..cancel().ignore()
        ..done.then((_) => order.add('done')).ignore();
      async.flushTimers();
      expect(order, [
        'dispose starts',
        'dispose ends',
        'discard starts',
        'discard ends',
        'done',
      ]);
    });
  });

  test('a value arriving after the body does not finish the wait twice', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final action = Completer<String>();
      final child = Completer<void>();
      final disposed = <String>[];
      final job = Job<void>(
        observer: ErrorObserver(errors),
        (ctx) async {
          // Walked away from: the body ends while the action is still in
          // flight, so the value comes back to a job whose body is gone.
          ctx.wait<String>(() => action.future, dispose: disposed.add).ignore();
          // And a child, so the job is still running when it does. Without
          // one the job would be over by then, and the window this test is
          // about would not exist.
          ctx
              .run(Job.deferred<void>((ctx) => ctx.join(() => child.future)))
              .ignore();
        },
      );
      async.flushMicrotasks();
      action.complete('v');
      // Into the microtask the registration of the late value costs: the
      // wait is finished by the cancellation there, and the value lands a
      // microtask later on a future that is already done.
      scheduleMicrotask(() => job.cancel().ignore());
      child.complete();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(
        disposed,
        ['v'],
        reason: 'the value did not reach the body, so it is cleaned up',
      );
      expect(
        errors,
        isEmpty,
        reason: 'and the observer hears nothing: a second completion of an '
            'internal future is not news of the job',
      );
    });
  });

  test('a value taken after the job was ended by hand is released', () {
    fakeAsync((async) {
      final released = <String>[];
      Object? caught;
      final action = Completer<String>();
      final job = ProbeJob<void>(key: 'job', (ctx) async {
        try {
          await ctx.wait<String>(() => action.future, dispose: released.add);
        } on Object catch (error) {
          caught = error;
        }
      })
        ..launch();
      async.flushMicrotasks();
      // An engine of a domain ending the job by hand, while the body is
      // still inside a call that has a resource coming.
      job.drop(const Done<void>(null));
      action.complete('db');
      async.flushTimers();
      expect(
        released,
        ['db'],
        reason: 'there is no stack to register on any more, so the value is '
            'released on the spot instead of being left to nobody',
      );
      expect(
        caught,
        isA<StateError>(),
        reason: 'and the body hears about the job, not about a registration '
            'it never made',
      );
      expect('$caught', contains('has already finished'));
    });
  });

  test('an action failing after the body walked away is not swallowed', () {
    final errors = <Object>[];
    final zone = <Object>[];
    late final Job<String> job;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          job = Job<String>(
            observer: ErrorObserver(errors),
            (ctx) => ctx.wait<String>(() async {
              await delay(50);
              throw StateError('the action failed late');
            }).timeout(
              const Duration(milliseconds: 10),
              onTimeout: () => 'fallback',
            ),
          );
          async.flushTimers();
        });
      },
      (error, stackTrace) => zone.add(error),
    );
    // Outside the guarded zone: an `expect` that fails inside it lands in
    // the handler and is counted as a zone error instead of failing.
    expect(job.outcome.toString(), 'Done(fallback)');
    expect(
      errors.map((error) => '$error').toList(),
      ['Bad state: the action failed late'],
      reason: 'the wrapper the body walked away through swallows what it '
          'is handed, and an error is never lost silently',
    );
    expect(
      zone.map((error) => '$error').toList(),
      ['Bad state: the action failed late'],
      reason: 'an observer that only watches answers for nothing',
    );
  });

  test('a wait made in the work still reports once, and only once', () {
    fakeAsync((async) {
      // Answering: this counts the announcements; where the error goes
      // after them is `unattended_test.dart`'s business.
      final journal = JobJournal(answers: true);
      Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() async {
          await ctx.wait<void>(() async {
            await delay(50);
            throw StateError('late');
          });
        });
        // The body ends here; the fork plays on, and the job is over long
        // before the action fails. The work is still holding that future,
        // so the fork is what announces -- announcing from the kernel as
        // well would say one error twice.
      }).ignore();
      async.flushTimers();
      expect(
        journal.take().where((line) => line.contains('error')).toList(),
        ['[j] error Bad state: late'],
      );
    });
  });

  group('a value unattended work takes after the body ended', () {
    // The work waits for the value, so it is the receiver: it gets the
    // value on the terms the call asked for, and a job that is over hands
    // it nothing closed -- it releases the value and says why.
    final members = <String,
        Future<_Resource> Function(
      JobContext ctx,
      Future<_Resource> Function() open, {
      void Function(_Resource)? dispose,
      void Function(_Resource)? discard,
    })>{
      'join': (ctx, open, {dispose, discard}) =>
          ctx.join(open, dispose: dispose, discard: discard),
      'wait': (ctx, open, {dispose, discard}) =>
          ctx.wait(open, dispose: dispose, discard: discard),
    };

    /// The body hands `take` to unattended work and returns, or gives
    /// itself up with [givesUp]; `open` brings the value back [opensIn] ms
    /// later and `make` right away, and a child keeps the job alive for
    /// [childFor] ms. With [cancelAt] the job is cancelled from outside
    /// that many ms in. What the work saw, and whether the resource ended
    /// up closed.
    List<String> scenario(
      Future<_Resource> Function(
        JobContext ctx,
        Future<_Resource> Function() open,
        _Resource Function() make,
      ) take, {
      int opensIn = 10,
      int childFor = 0,
      int? cancelAt,
      bool givesUp = false,
    }) {
      final seen = <String>[];
      fakeAsync((async) {
        _Resource? made;
        final job = Job<void>((ctx) async {
          if (childFor > 0) {
            ctx.run(Job.deferred<void>((_) => delay(childFor))).ignore();
          }
          ctx.unattended(() async {
            try {
              final resource = await take(
                ctx,
                () async {
                  await delay(opensIn);
                  return made = _Resource();
                },
                () => made = _Resource(),
              );
              seen.add('got it, closed: ${resource.closed}');
            } on Cancelled {
              seen.add('cancelled');
            } on Object catch (error) {
              seen.add('$error');
            }
          });
          if (givesUp) {
            throw const Cancelled('gave up');
          }
        });
        if (cancelAt != null) {
          async.elapse(Duration(milliseconds: cancelAt));
          job.cancel().ignore();
        }
        async.flushTimers();
        seen.add('in the end closed: ${made?.closed}');
      });
      return seen;
    }

    void close(_Resource resource) => resource.closed = true;

    const refused = 'Bad state: Job() has already finished, '
        'cannot take the value of a call it made';

    for (final MapEntry(key: member, value: call) in members.entries) {
      for (final discard in [false, true]) {
        final kind = discard ? 'discard' : 'dispose';
        test('$member with $kind, on a job that is over', () {
          expect(
            scenario(
              opensIn: 20,
              (ctx, open, _) => call(
                ctx,
                open,
                dispose: discard ? null : close,
                discard: discard ? close : null,
              ),
            ),
            [
              refused,
              'in the end closed: true',
            ],
          );
        });
      }
      test('$member with dispose, on a job still waiting for a child', () {
        expect(
          scenario(
            childFor: 30,
            (ctx, open, _) => call(ctx, open, dispose: close),
          ),
          ['got it, closed: false', 'in the end closed: true'],
        );
      });
      test('$member with discard, on a job still waiting for a child', () {
        expect(
          scenario(
            childFor: 30,
            (ctx, open, _) => call(ctx, open, discard: close),
          ),
          ['got it, closed: false', 'in the end closed: false'],
          reason: 'the job ended Done: the work is the receiver',
        );
      });
      test('$member, the job cancelled while the call runs', () {
        expect(
          scenario(
            opensIn: 20,
            childFor: 40,
            cancelAt: 10,
            (ctx, open, _) => call(ctx, open, discard: close),
          ),
          ['cancelled', 'in the end closed: true'],
        );
      });
      test('$member, the body gave itself up', () {
        expect(
          scenario(
            childFor: 40,
            givesUp: true,
            (ctx, open, _) => call(ctx, open, discard: close),
          ),
          ['cancelled', 'in the end closed: true'],
          reason: 'the mark ran no callbacks, and the work still gets it',
        );
      });
    }
    test('wait with a value at hand, on a job still waiting for a child', () {
      expect(
        scenario(
          childFor: 30,
          (ctx, open, make) async {
            await delay(10);
            return ctx.wait(make, discard: close);
          },
        ),
        ['got it, closed: false', 'in the end closed: false'],
        reason: 'the job ended Done: the work is the receiver',
      );
    });
  });
}

final class _Resource {
  bool closed = false;
}
