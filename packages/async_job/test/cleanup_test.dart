@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:mirrors';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/error_observer.dart';

void _byDispose(JobContext ctx, void Function() run) => ctx.onDispose(run);

void _byDiscard(JobContext ctx, void Function() run) => ctx.onDiscard(run);

/// Runs a job that registers a cleanup through [register] and ends the way
/// [scenario] says, and gives back what the cleanup wrote.
List<String> _cleanupsOn(
  String scenario,
  void Function(JobContext ctx, void Function() run) register,
) =>
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<int>((ctx) async {
        register(ctx, () => order.add('cleaned'));
        await ctx.wait(() => delay(10));
        if (scenario == 'failed') {
          throw StateError('boom');
        }

        return 1;
      })
        ..ignore();
      // Five milliseconds so the body starts and registers: a job cancelled
      // before that never runs its body at all.
      async.elapse(const Duration(milliseconds: 5));
      if (scenario == 'cancelled') {
        job.cancel().ignore();
      }
      async.flushTimers();

      return order;
    });

/// Opens a resource the way a real one opens: not at once.
Future<String> _open() async {
  await delay(10);

  return 'db';
}

void main() {
  test('onDispose runs on Done', () {
    expect(_cleanupsOn('done', _byDispose), ['cleaned']);
  });

  test('onDispose runs on Failed', () {
    expect(_cleanupsOn('failed', _byDispose), ['cleaned']);
  });

  test('onDispose runs on Cancelled', () {
    expect(_cleanupsOn('cancelled', _byDispose), ['cleaned']);
  });

  test('onDiscard is silent on Done', () {
    expect(_cleanupsOn('done', _byDiscard), isEmpty);
  });

  test('onDiscard runs on Failed', () {
    expect(_cleanupsOn('failed', _byDiscard), ['cleaned']);
  });

  test('onDiscard runs on Cancelled', () {
    expect(_cleanupsOn('cancelled', _byDiscard), ['cleaned']);
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
        observer: ErrorObserver(errors),
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
  test('isCancelled tells the truth inside a cleanup', () {
    fakeAsync((async) {
      final seen = <bool>[];
      Job<void>((ctx) async {
        ctx.onDispose(() => seen.add(ctx.job.isCancelled));
        await ctx.wait(() => delay(10));
        // The body throws the cancellation itself: nothing marked the job,
        // and until now `isCancelled` lied about it during the cleanup.
        throw Cancelled.by(
          reason: CancelReason.manual,
          started: true,
          stackTrace: StackTrace.current,
        );
      }).ignore();
      async.flushTimers();
      expect(seen, [true]);
    });
  });

  test('whenCancelled closes before the cleanup ends', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        ctx.onDispose(() async {
          order.add('cleanup starts');
          await delay(50);
          order.add('cleanup ends');
        });
        await ctx.wait(() => delay(10));
        throw Cancelled.by(
          reason: CancelReason.manual,
          started: true,
          stackTrace: StackTrace.current,
        );
      })
        ..ignore();
      job.whenCancelled.then((_) => order.add('whenCancelled')).ignore();
      async.flushTimers();
      // The listener of `whenCancelled` runs as a microtask, so its line
      // lands inside the asynchronous disposer rather than before it; what
      // matters is that it no longer waits for `finish`.
      expect(order, ['cleanup starts', 'whenCancelled', 'cleanup ends']);
    });
  });

  test('a wait the body walked away from gets no error of its own', () {
    fakeAsync((async) {
      final errors = <Object>[];
      Job<void>(
        observer: ErrorObserver(errors),
        (ctx) async {
          // The body walks away from its own wait and throws the
          // cancellation itself: filling `_pendingCancel` must not run the
          // callbacks of the race.
          unawaited(ctx.wait(() => delay(50)));
          await ctx.wait(() => delay(10));
          throw Cancelled.by(
            reason: CancelReason.manual,
            started: true,
            stackTrace: StackTrace.current,
          );
        },
      ).ignore();
      async.flushTimers();
      expect(errors, isEmpty);
    });
  });

  test('cancelling a parent that waits for children still cascades', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        ctx.run(
          Job.deferred<void>(
            key: 'child',
            (ctx) async {
              ctx.onCancel(() => order.add('child cancelled'));
              await ctx.wait(() => delay(100));
            },
          ),
        );
        await ctx.wait(() => delay(10));
        // The body ended with a cancellation of its own while the children
        // are still running: an outside `cancel()` has to reach the child.
        throw Cancelled.by(
          reason: CancelReason.manual,
          started: true,
          stackTrace: StackTrace.current,
        );
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 30));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['child cancelled']);
    });
  });

  test('a section the body walked away from holds the cancellation', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<int>((ctx) async {
        ctx.onDiscard(() => order.add('discarded'));
        // A mistake of the body: the section was never awaited, so its
        // depth stays above zero. The engine does not fix that — this test
        // pins that the held cancellation never reaches the cleanup and
        // `Done` goes to whoever cancelled.
        unawaited(ctx.uncancellable(() => delay(100)));
        await ctx.wait(() => delay(10));
        return 1;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 20));
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      expect(order, isEmpty);
    });
  });
  test('join keeps the value and cleans it up at the end', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<String>((ctx) async {
        final db = await ctx.join(
          () async {
            await delay(10);
            return 'db';
          },
          discard: closed.add,
        );
        await ctx.wait(() => delay(10));
        return db;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 15));
      job.cancel().ignore();
      async.flushTimers();
      expect(closed, ['db'], reason: 'the value reached the body: the stack');
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('join cleans up on the spot when the cancellation beat the value', () {
    fakeAsync((async) {
      final closed = <String>[];
      final order = <String>[];
      final job = Job<void>((ctx) async {
        try {
          await ctx.join(
            () async {
              await delay(50);
              return 'db';
            },
            discard: (value) async {
              await delay(20);
              closed.add(value);
            },
          );
        } on Cancelled {
          order.add('body sees the cancellation');
          rethrow;
        }
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(closed, ['db']);
      expect(order, ['body sees the cancellation']);
    });
  });

  test('a value that arrives in the window of the children is cleaned up', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<int>((ctx) async {
        // The body walks away from its own call: the value arrives when
        // the body is gone, so it reached nobody and the outcome does not
        // matter.
        unawaited(
          ctx.join<String>(
            () async {
              await delay(50);
              return 'db';
            },
            discard: closed.add,
          ),
        );
        ctx.run(
          Job.deferred<void>(
            key: 'child',
            (ctx) => ctx.wait(() => delay(80)),
          ),
        );
        return 1;
      })
        ..ignore();
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      expect(closed, ['db'], reason: 'on Done as well');
    });
  });

  test('a value that arrives into the running cleanup is cleaned up too', () {
    fakeAsync((async) {
      final closed = <String>[];
      final errors = <Object>[];
      final job = Job<int>(
        observer: ErrorObserver(errors),
        (ctx) async {
          unawaited(
            ctx.join<String>(
              () async {
                await delay(50);
                return 'db';
              },
              discard: closed.add,
            ),
          );
          // No children: the value lands in the middle of a slow disposer
          // rather than in the window of the children.
          ctx.onDispose(() => delay(100));
          return 1;
        },
      )..ignore();
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      expect(closed, ['db']);
      expect(errors, isEmpty);
    });
  });

  test('a value that arrives after the job has finished is cleaned up', () {
    fakeAsync((async) {
      final closed = <String>[];
      Job<int>((ctx) async {
        unawaited(
          ctx.join<String>(
            () async {
              await delay(50);
              return 'joined';
            },
            discard: closed.add,
          ),
        );
        unawaited(
          ctx.wait<String>(
            () async {
              await delay(60);
              return 'waited';
            },
            discard: closed.add,
          ),
        );
        return 1;
      }).ignore();
      async.flushTimers();
      expect(closed, ['joined', 'waited'], reason: 'both of the family');
    });
  });

  test('an abandoned join is silent on the successful path', () {
    fakeAsync((async) {
      final errors = <Object>[];
      Job<int>(
        observer: ErrorObserver(errors),
        (ctx) async {
          unawaited(
            ctx.join<String>(
              () async {
                await delay(50);
                return 'db';
              },
              discard: (_) {},
            ),
          );
          ctx.run(
            Job.deferred<void>(
              key: 'child',
              (ctx) => ctx.wait(() => delay(80)),
            ),
          );
          return 1;
        },
      ).ignore();
      async.flushTimers();
      expect(errors, isEmpty, reason: 'no StateError, no cancellation');
    });
  });

  test('a call with no value of its own registers by the member', () {
    fakeAsync((async) {
      final released = <String>[];
      final job = Job<void>((ctx) async {
        // `join<void>` registers a cleanup with no address of its own:
        // `disown` cannot reach it, so unregistering goes by the member.
        await ctx.join<void>(
          () async => delay(1),
          dispose: (_) => released.add('by parameter'),
        );
        final drop = ctx.onDispose(() => released.add('by member'));
        await ctx.wait(() => delay(10));
        drop();
      })
        ..ignore();
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
      expect(released, ['by parameter']);
    });
  });

  test('a cancellation cannot slip between the value and the body', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<String>((ctx) async {
        final db = await ctx.wait(
          () async {
            await delay(10);
            return 'db';
          },
          discard: closed.add,
        );
        await ctx.wait(() => delay(10));
        return db;
      })
        ..ignore();
      // The cancellation lands exactly when the action returned its value:
      // the registration is synchronous, so the cleanup is not lost.
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(closed, ['db']);
    });
  });

  test('disown drops the top registration for that value', () {
    fakeAsync((async) {
      final closed = <String>[];
      final dropped = <bool>[];
      final job = Job<String>((ctx) async {
        final db = await ctx.join(() async => 'db', dispose: closed.add);
        dropped
          ..add(ctx.disown(db))
          ..add(ctx.disown(db))
          ..add(ctx.disown('someone else'));
        await ctx.wait(() => delay(10));

        return db;
      })
        ..ignore();
      async.flushTimers();
      expect(job.outcome, isA<Done<String>>());
      expect(dropped, [true, false, false], reason: 'one per call, then none');
      expect(closed, isEmpty);
    });
  });

  test('disown does not see a registration made by a member', () {
    fakeAsync((async) {
      final closed = <String>[];
      final dropped = <bool>[];
      final job = Job<void>((ctx) async {
        const db = 'db';
        ctx.onDispose(() => closed.add(db));
        dropped.add(ctx.disown(db));
      })
        ..ignore();
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
      expect(dropped, [false]);
      expect(closed, ['db'], reason: 'disown left the member alone');
    });
  });

  test('disown after the job has finished is a StateError', () {
    fakeAsync((async) {
      late JobContext leaked;
      Job<void>((ctx) async => leaked = ctx).ignore();
      async.flushTimers();
      expect(() => leaked.disown('anything'), throwsStateError);
    });
  });

  test('a parameter and a member on one value both run', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<String>((ctx) async {
        final db = await ctx.join(
          () async => 'db',
          discard: (value) => closed.add('by parameter'),
        );
        // Documented behaviour: two independent registrations, and the
        // member's own function drops only its own. Nobody should write
        // this — the test holds the line the dartdoc draws.
        ctx.onDiscard(() => closed.add('by member'))();
        await ctx.wait(() => delay(10));
        return db;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 5));
      job.cancel().ignore();
      async.flushTimers();
      expect(closed, ['by parameter']);
    });
  });

  test('passing both dispose and discard is an ArgumentError', () {
    fakeAsync((async) {
      final job = Job<void>((ctx) async {
        await ctx.join(
          () async => 'db',
          dispose: (_) {},
          discard: (_) {},
        );
      })
        ..ignore();
      async.flushTimers();
      expect(job.outcome, isA<Failed>());
      expect((job.outcome! as Failed).error, isA<ArgumentError>());
    });
  });
  test('the discards a cancellation brings back keep the stack order', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<int>((ctx) async {
        // The slow `dispose` sits at the bottom of the stack, so both
        // `discard` registrations come off first and are skipped while the
        // outcome is still `Done`. The cancellation arrives during the slow
        // one, and the second pass brings them back — in the order of the
        // stack, not of the registrations.
        ctx
          ..onDispose(() async {
            order.add('slow starts');
            await delay(100);
            order.add('slow ends');
          })
          ..onDiscard(() => order.add('below'))
          ..onDiscard(() => order.add('top'));
        return 7;
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.elapse(const Duration(milliseconds: 200));
      expect(order, ['slow starts', 'slow ends', 'top', 'below']);
    });
  });
  test('a discard of a call is silent when the value reaches the body', () {
    fakeAsync((async) {
      // The pattern of the Quick start: the call gives the body a resource
      // and the body hands it out. Nothing may close it on the way.
      final closed = <String>[];
      final job = Job<String>((ctx) async {
        final db = await ctx.join(_open, discard: closed.add);
        await ctx.wait(() => delay(10));

        return db;
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<String>>());
      expect(closed, isEmpty);
    });
  });

  test('a discard of a wait is silent when the value reaches the body', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<String>((ctx) async {
        final db = await ctx.wait(_open, discard: closed.add);
        await ctx.wait(() => delay(10));

        return db;
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<String>>());
      expect(closed, isEmpty);
    });
  });

  test('a synchronous value of wait goes on the stack as any other does', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<void>((ctx) async {
        await ctx.wait(() => 'file', dispose: closed.add);
        await ctx.wait(() => delay(10));
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
      expect(closed, ['file']);
    });
  });

  test('a synchronous value of wait is discarded on a cancellation', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<void>((ctx) async {
        await ctx.wait(() => 'file', discard: closed.add);
        await ctx.wait(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(closed, ['file']);
    });
  });

  test('disown drops the top of two registrations for one value', () {
    fakeAsync((async) {
      final closed = <String>[];
      final dropped = <bool>[];
      final job = Job<String>((ctx) async {
        final db = await ctx.join(_open, dispose: (_) => closed.add('below'));
        await ctx.join(() async => db, dispose: (_) => closed.add('top'));
        dropped.add(ctx.disown(db));
        await ctx.wait(() => delay(10));

        return db;
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<String>>());
      expect(dropped, [true]);
      expect(closed, ['below'], reason: 'the top one went, the one below ran');
    });
  });

  test('a registration the unwinding put off can still be taken back', () {
    final ran = <String>[];
    fakeAsync((async) {
      late void Function() unregister;
      Job<Object>((ctx) async {
        ctx.onDispose(() {
          // Runs below the put-off registration, on a `Done` a cancellation
          // is about to take away.
          unregister();
          ctx.job.cancel().ignore();
        });
        unregister = ctx.onDiscard(() => ran.add('discard ran'));
        return ran;
      }).ignore();
      async.flushTimers();
    });
    expect(
      ran,
      isEmpty,
      reason: 'taking a registration back works wherever the unwinding has '
          'put it',
    );
  });

  test('a value the unwinding put off can still be disowned', () {
    final ran = <String>[];
    final resource = Object();
    fakeAsync((async) {
      Job<Object>((ctx) async {
        ctx.onDispose(() {
          ran.add('disown: ${ctx.disown(resource)}');
          ctx.job.cancel().ignore();
        });
        return ctx.wait(
          () => resource,
          discard: (value) => ran.add('discard ran'),
        );
      }).ignore();
      async.flushTimers();
    });
    expect(
      ran,
      ['disown: true'],
      reason: 'the body handed the value on, and the registration the first '
          'pass put aside went with it',
    );
  });

  test('disown takes the newest registration, whichever list holds it', () {
    final resource = Object();
    final ran = <String>[];
    fakeAsync((async) {
      Job<void>((ctx) async {
        await ctx.wait(() => resource, discard: (_) => ran.add('bottom'));
        ctx.onDispose(() {
          ran.add('disown: ${ctx.disown(resource)}');
          ctx.job.cancel().ignore();
        });
        await ctx.wait(() => resource, discard: (_) => ran.add('top'));
      }).ignore();
      async.flushTimers();
    });
    expect(
      ran,
      ['disown: true', 'bottom'],
      reason: 'the top registration is the one the unwinding had already '
          'put aside, and the one below it is still owed',
    );
  });

  test('a successful job lets go of the registrations it never ran', () {
    late Job<Object> job;
    fakeAsync((async) {
      job = Job<Object>((ctx) async {
        final resource = Object();
        // Put off by the first pass on a `Done` and never run: the value
        // reached the caller, so there was nothing to discard.
        return ctx.wait(() => resource, discard: (value) {});
      })
        ..ignore();
      async.flushTimers();
    });
    expect(job.outcome, isA<Done<Object>>());
    expect(
      _putAside(job),
      isEmpty,
      reason: 'a registration nobody will run must not outlive the job in '
          'its handle: it holds its value and its closure',
    );
  });
}

/// The registrations the unwinding put aside, read through the mirror: the
/// list is private, and nothing public tells a finished job apart from one
/// still holding what it will never run.
List<Object?> _putAside(Job<Object?> job) {
  final mirror = reflect(job);
  for (ClassMirror? type = mirror.type; type != null; type = type.superclass) {
    for (final entry in type.declarations.entries) {
      if (MirrorSystem.getName(entry.key) == '_skipped') {
        return mirror.getField(entry.key).reflectee as List<Object?>;
      }
    }
  }
  throw StateError('no _skipped field on ${job.runtimeType}');
}
