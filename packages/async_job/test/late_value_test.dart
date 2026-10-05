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
                (ctx) => ctx.abandonable(() => delay(100)),
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
                  await ctx.abandonable(() => delay(50));
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
                      (ctx) => ctx.abandonable(() => delay(100)),
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
                  Job.deferred<void>(
                    (ctx) => ctx.abandonable(() => delay(100)),
                  ),
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
        // Walked away from: the cancellation ends the wait, and the value turns
        // up later, while the engine is still unwinding the stack. `ignore`,
        // not `unawaited`: an `abandonable` call left behind still completes
        // with the job's cancellation, and nobody is there to catch it.
        ctx.abandonable<String>(
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
        await ctx.abandonable(() => delay(200));
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
          ctx
              .abandonable<String>(() => action.future, dispose: disposed.add)
              .ignore();
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
          await ctx.abandonable<String>(
            () => action.future,
            dispose: released.add,
          );
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
            (ctx) => ctx.abandonable<String>(() async {
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
          await ctx.abandonable<void>(() async {
            await delay(50);
            throw StateError('late');
          });
        });
        // The body ends here; the fork plays on, and the job is over long
        // before the action fails. The work is still holding that future,
        // so the fork is what announces -- announcing from the core as
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
      'abandonable': (ctx, open, {dispose, discard}) =>
          ctx.abandonable(open, dispose: dispose, discard: discard),
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
          reason: 'the callbacks run for a body that gives itself up too',
        );
      });
    }
    for (final givesUp in [true, false]) {
      final how = givesUp ? 'the body gave itself up' : 'cancelled outside';
      test('abandonable, the job ended by hand in the cascade, $how', () {
        // A callback of the child reaches the engine, and it ends the parent
        // by hand: the mark is on, and the callbacks that would have told
        // this race are gone with `finish`.
        final seen = <String>[];
        fakeAsync((async) {
          _Resource? made;
          late final ProbeJob<void> parent;
          parent = ProbeJob<void>((ctx) async {
            ctx.run(
              Job.deferred<void>((ctx) async {
                ctx.onCancel(() => parent.drop(const Cancelled('by hand')));
                await ctx.abandonable(() => delay(50));
              }),
            ).ignore();
            ctx.unattended(() async {
              try {
                final resource = await ctx.abandonable(
                  () async {
                    await delay(20);
                    return made = _Resource();
                  },
                  discard: close,
                );
                seen.add('got it, closed: ${resource.closed}');
              } on Cancelled {
                seen.add('cancelled');
              } on Object catch (error) {
                seen.add('$error');
              }
            });
            await delay(5);
            if (givesUp) {
              throw const Cancelled('gave up');
            }
            await delay(100);
          })
            ..ignore()
            ..launch();
          if (!givesUp) {
            async.elapse(const Duration(milliseconds: 5));
            parent.cancel().ignore();
          }
          async.flushTimers();
          seen.add('in the end closed: ${made?.closed}');
        });
        expect(seen, ['cancelled', 'in the end closed: true']);
      });
    }
    test('abandonable, a raw callback before it threw, the body gave itself up',
        () {
      // The pass over the callbacks stops at the throw, and the race of the
      // call never hears the cancellation from it.
      final seen = <String>[];
      final errors = <String>[];
      runZonedGuarded(
        () => fakeAsync((async) {
          _Resource? made;
          ProbeJob<void>((ctx) async {
            (ctx as ProbeContext).onCancelRaw(() => throw StateError('boom'));
            ctx.unattended(() async {
              try {
                final resource = await ctx.abandonable(
                  () async {
                    await delay(20);
                    return made = _Resource();
                  },
                  discard: close,
                );
                seen.add('got it, closed: ${resource.closed}');
              } on Cancelled {
                seen.add('cancelled');
              }
            });
            await delay(5);
            throw const Cancelled('gave up');
          })
            ..ignore()
            ..launch();
          async.flushTimers();
          seen.add('in the end closed: ${made?.closed}');
        }),
        (error, stackTrace) => errors.add('$error'),
      );
      expect(seen, ['cancelled', 'in the end closed: true']);
      expect(errors, ['Bad state: boom']);
    });
    test('abandonable with a value at hand, on a job still waiting for a child',
        () {
      expect(
        scenario(
          childFor: 30,
          (ctx, open, make) async {
            await delay(10);
            return ctx.abandonable(make, discard: close);
          },
        ),
        ['got it, closed: false', 'in the end closed: false'],
        reason: 'the job ended Done: the work is the receiver',
      );
    });
  });

  group('a value that reached nobody is released before the unwinding', () {
    // One slot, and a queue for it: the first to ask gets it, the rest wait
    // in turn.
    ({List<String> log, Future<_Slot> Function(String) take}) slot() {
      final log = <String>[];
      final slot = _Slot(log);
      return (log: log, take: slot.take);
    }

    /// Holds the slot until 20 ms, so that `a` queues for it first and the
    /// child of `a` after it.
    void holdUntil20(Future<_Slot> Function(String) take) {
      Job<void>((ctx) async {
        final held = await ctx.join(() => take('x'));
        await ctx.abandonable(() => delay(20));
        held.give('x');
      }).ignore();
    }

    for (final how in ['plain child', 'runAll branch']) {
      test('a child that waits for it gets it, $how', () {
        fakeAsync((async) {
          final (:log, :take) = slot();
          holdUntil20(take);
          final a = Job.deferred<int>(key: 'a', (ctx) async {
            // Asks a millisecond later, so the slot comes to `a` first, and
            // holds on through the cancellation of `a`.
            ctx.run(
              Job.deferred<void>((ctx) async {
                await ctx.abandonable(() => delay(1));
                await ctx.uncancellable(() async {
                  (await take('child')).give('child');
                });
              }),
            ).ignore();
            await ctx.abandonable(() => take('a'), dispose: (s) => s.give('a'));
            return 0;
          });
          final parent = Job<void>((ctx) async {
            if (how == 'runAll branch') {
              await ctx.runAll([
                a,
                Job.deferred<int>((ctx) async => 2),
              ]);
            } else {
              await ctx.run(a);
            }
          })
            ..ignore();
          async.elapse(const Duration(milliseconds: 5));
          a.cancel().ignore();
          async.flushTimers();
          expect(
            log,
            [
              'x takes',
              'a waits',
              'child waits',
              'x gives',
              'a takes',
              'a gives',
              'child takes',
              'child gives',
            ],
            reason: 'the slot came to `a` after its wait was abandoned: `a` '
                'waits for its child, the child for the slot, and kept for '
                'the unwinding the slot would wait for `a`',
          );
          expect(a.outcome, isA<Cancelled>());
          expect(parent.outcome, isA<Cancelled>());
        });
      });
    }

    for (final how in ['by itself', 'by its parent']) {
      test('a branch between the passes gets it out, cancelled $how', () {
        fakeAsync((async) {
          final (:log, :take) = slot();
          holdUntil20(take);
          final a = Job.deferred<int>(key: 'a', (ctx) async {
            ctx
                .abandonable(() => take('a'), dispose: (s) => s.give('a'))
                .ignore();
            return 1;
          });
          // Its cleanup keeps the group at the second barrier, `a` with it.
          final b = Job.deferred<int>(key: 'b', (ctx) async {
            ctx.onDispose(() async {
              (await take('b cleanup')).give('b cleanup');
            });
            await ctx.abandonable(() => delay(1));
            return 2;
          });
          final group = Job<List<int>>((ctx) => ctx.runAll([a, b]))..ignore();
          async.elapse(const Duration(milliseconds: 10));
          if (how == 'by itself') {
            a.cancel().ignore();
          } else {
            group.cancel().ignore();
          }
          async.flushTimers();
          expect(
            log,
            [
              'x takes',
              'a waits',
              'b cleanup waits',
              'x gives',
              'a takes',
              'a gives',
              'b cleanup takes',
              'b cleanup gives',
            ],
            reason: 'the slot came to `a` at the second barrier, where no '
                'callback runs: held for the second pass, it would wait for '
                'the barrier, the barrier for `b`, and `b` for the slot',
          );
          expect(a.outcome, isA<Cancelled>());
          expect(group.outcome, isA<Cancelled>());
        });
      });
    }

    test('and the job still ends only after the release', () {
      fakeAsync((async) {
        final seen = <String>[];
        void at(String what) =>
            seen.add('${async.elapsed.inMilliseconds} ms: $what');
        final job = Job<void>((ctx) async {
          ctx
              .run(
                Job.deferred<void>(
                  (ctx) => ctx.uncancellable(() => delay(30)),
                ),
              )
              .ignore();
          await ctx.abandonable(
            () => delay(10).then((_) => 'db'),
            dispose: (db) async {
              at('release starts');
              await delay(40);
              at('release ends');
            },
          );
        });
        job.done.then((_) => at('done')).ignore();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        expect(seen, [
          '10 ms: release starts',
          '50 ms: release ends',
          '50 ms: done',
        ]);
      });
    });

    test('while the body is still running too', () {
      fakeAsync((async) {
        final seen = <String>[];
        void at(String what) =>
            seen.add('${async.elapsed.inMilliseconds} ms: $what');
        final job = Job<void>((ctx) async {
          try {
            await ctx.abandonable(
              () => delay(20).then((_) => 'db'),
              // Outlives the body: the job waits for it all the same.
              dispose: (db) async {
                at('release starts');
                await delay(50);
                at('release ends');
              },
            );
          } on Cancelled {
            // A body finishing its own business after the cancellation:
            // the value is not coming to it either way.
            await Future<void>.delayed(const Duration(milliseconds: 30));
            at('body ends');
            rethrow;
          }
        });
        job.done.then((_) => at('done')).ignore();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        expect(seen, [
          '20 ms: release starts',
          '35 ms: body ends',
          '70 ms: release ends',
          '70 ms: done',
        ]);
      });
    });

    test('a branch unwinding its stack takes it in turn', () {
      fakeAsync((async) {
        final order = <String>[];
        void at(String what) =>
            order.add('${async.elapsed.inMilliseconds} ms: $what');
        final a = Job.deferred<void>((ctx) async {
          ctx.abandonable<String>(
            () => delay(50).then((_) => 'db'),
            discard: (value) async {
              at('discard starts');
              await delay(100);
              at('discard ends');
            },
          ).ignore();
          ctx.onDispose(() async {
            at('dispose starts');
            await delay(50);
            at('dispose ends');
          });
          await ctx.abandonable(() => delay(200));
        });
        Job<void>(
          (ctx) => ctx.runAll([a, Job.deferred<void>((ctx) async {})]),
        ).ignore();
        async.elapse(const Duration(milliseconds: 10));
        a.cancel().ignore();
        async.flushTimers();
        expect(
          order,
          [
            '10 ms: dispose starts',
            '60 ms: dispose ends',
            '60 ms: discard starts',
            '160 ms: discard ends',
          ],
          reason: 'the value came while the stack was unwinding, and the '
              'callbacks of the stack do not overlap',
        );
      });
    });

    for (final how in ['throws', 'fails later']) {
      test('an error of the release reaches the observer once: $how', () {
        final errors = <Object>[];
        final zone = <Object>[];
        late final Job<void> job;
        runZonedGuarded(
          () {
            fakeAsync((async) {
              job = Job<void>(
                observer: ErrorObserver(errors),
                (ctx) async {
                  ctx
                      .run(
                        Job.deferred<void>(
                          (ctx) => ctx.uncancellable(() => delay(30)),
                        ),
                      )
                      .ignore();
                  await ctx.abandonable(
                    () => delay(10).then((_) => 'db'),
                    dispose: (db) => how == 'throws'
                        ? throw StateError('close failed')
                        : delay(5)
                            .then((_) => throw StateError('close failed')),
                  );
                },
              )..ignore();
              async.elapse(const Duration(milliseconds: 5));
              job.cancel().ignore();
              async.flushTimers();
            });
          },
          (error, stackTrace) => zone.add(error),
        );
        // Outside the guarded zone: an `expect` that fails inside it lands in
        // the handler and is counted as a zone error instead of failing.
        expect(job.outcome, isA<Cancelled>());
        expect(errors.map((error) => '$error'), ['Bad state: close failed']);
        expect(zone.map((error) => '$error'), ['Bad state: close failed']);
      });
    }

    test('a release that ends the job by hand is no error', () {
      final errors = <Object>[];
      final zone = <Object>[];
      late final ProbeJob<void> job;
      runZonedGuarded(
        () {
          fakeAsync((async) {
            job = ProbeJob<void>(
              observer: ErrorObserver.answering(errors),
              (ctx) async {
                ctx
                    .run(
                      Job.deferred<void>(
                        (ctx) => ctx.uncancellable(() => delay(30)),
                      ),
                    )
                    .ignore();
                await ctx.abandonable(
                  () => delay(10).then((_) => 'db'),
                  dispose: (db) => job.drop(const Cancelled('by hand')),
                );
              },
            )
              ..launch()
              ..ignore();
            async.elapse(const Duration(milliseconds: 5));
            job.cancel().ignore();
            async.flushTimers();
          });
        },
        (error, stackTrace) => zone.add(error),
      );
      expect(job.outcome, isA<Cancelled>());
      expect(
        [...errors, ...zone],
        isEmpty,
        reason: 'the wait for the release is on the stack before the release '
            'starts, not after the disposer has finished the job',
      );
    });

    test('a branch the group has taken, cancelled while it unwinds', () {
      fakeAsync((async) {
        final released = <String>[];
        final a = Job.deferred<int>(key: 'a', (ctx) async {
          ctx
              .abandonable(
                () => delay(100).then((_) => 'db'),
                dispose: (db) =>
                    released.add('${async.elapsed.inMilliseconds} ms: $db'),
              )
              .ignore();
          // Lands at the second barrier and keeps `a` in its second pass
          // from 70 ms to 170: the value comes while `a` unwinds.
          Timer(const Duration(milliseconds: 50), () {
            ctx.onDispose(() => delay(100));
          });
          return 1;
        });
        // Keeps the group at its second barrier until 70 ms, so that the
        // group has taken the value of `a` by the time `a` is cancelled.
        final b = Job.deferred<int>(key: 'b', (ctx) async {
          ctx.onDispose(() => delay(70));
          return 2;
        });
        final group = Job<List<int>>((ctx) => ctx.runAll([a, b]))..ignore();
        async.elapse(const Duration(milliseconds: 80));
        a.cancel().ignore();
        async.flushTimers();
        expect(group.outcome, isA<Done<List<int>>>());
        expect(
          released,
          ['170 ms: db'],
          reason: 'the value came to a wait the cancellation had ended: it '
              'reaches nobody, and the group taking the value of the branch '
              'does not pass over its release; it came in the second pass, '
              'so it waits for the callback running there',
        );
      });
    });

    test('disown still finds what the body registered by the same value', () {
      fakeAsync((async) {
        final released = <String>[];
        final token = Object();
        late bool disowned;
        final job = Job<void>((ctx) async {
          final mine = await ctx.join(
            () => token,
            dispose: (_) => released.add('by the body'),
          );
          try {
            await ctx.abandonable(
              () => delay(10).then((_) => token),
              // Slow, so that it is still under way when the body disowns.
              dispose: (_) async {
                await delay(50);
                released.add('late');
              },
            );
          } on Cancelled {
            // Past the arrival of the late one, and before the unwinding.
            await Future<void>.delayed(const Duration(milliseconds: 20));
            disowned = ctx.disown(mine);
            rethrow;
          }
        })
          ..ignore();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();
        expect(disowned, isTrue);
        expect(
          released,
          ['late'],
          reason: 'the release of the late value is no registration of the '
              'value: disown takes back the one the body made',
        );
      });
    });
  });

  group('a value that came to a future the body handed on', () {
    for (final how in ['abandonable', 'join', 'run']) {
      test('reaches its holder open, $how', () {
        fakeAsync((async) {
          final log = <String>[];
          Job<void>((ctx) async {
            Future<_Resource> open() => delay(10).then((_) => _Resource());
            void close(_Resource resource) {
              resource.closed = true;
              log.add('closed');
            }

            final resource = switch (how) {
              'abandonable' => ctx.abandonable(open, dispose: close),
              'join' => ctx.join(open, dispose: close),
              _ => ctx.run(
                  Job.deferred<_Resource>((ctx) => open()),
                  dispose: close,
                ),
            };
            ctx.run(
              Job.deferred<void>((ctx) async {
                final taken = await resource;
                await ctx.abandonable(() => delay(5));
                log.add('used, closed: ${taken.closed}');
              }),
            ).ignore();
          }).ignore();
          async.flushTimers();
          expect(
            log,
            ['used, closed: false', 'closed'],
            reason: 'the body walked away, but the child holds the future: '
                'the value reaches it, and the parent closes it after its '
                'children, on the stack',
          );
        });
      });
    }
  });
}

/// A slot for one holder at a time, handed to the next in the queue.
final class _Slot {
  _Slot(this._log);

  final List<String> _log;
  String? _holder;
  final _queue = <(String, Completer<void>)>[];

  Future<_Slot> take(String who) {
    if (_holder == null) {
      _holder = who;
      _log.add('$who takes');
      return Future.value(this);
    }
    _log.add('$who waits');
    final turn = Completer<void>();
    _queue.add((who, turn));
    return turn.future.then((_) => this);
  }

  void give(String who) {
    _log.add('$who gives');
    _holder = null;
    if (_queue.isNotEmpty) {
      final (next, turn) = _queue.removeAt(0);
      _holder = next;
      _log.add('$next takes');
      turn.complete();
    }
  }
}

final class _Resource {
  bool closed = false;
}
