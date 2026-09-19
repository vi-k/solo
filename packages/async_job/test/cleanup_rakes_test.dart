@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:test/test.dart';

import 'support/error_observer.dart';

/// The first attempts of `doc/cleanup.md`, and what each one costs.
///
/// Three sections of the page open with the version the vocabulary of the
/// API leads to and say what that version does instead of what it was
/// meant to do. Nothing else guards those statements: the page has no
/// bench, so an owner or an order quoted there rots silently. Every claim
/// the page makes about who closes the resource, and when, is pinned here
/// next to the version it then shows.

final class Database {
  final String name;
  final List<String> trace;
  int closes = 0;

  Database(this.name, this.trace);

  bool get closed => closes > 0;

  Future<void> migrate() async => trace.add('$name migrated');

  Future<void> failingMigrate() async {
    trace.add('$name migration failed');
    throw StateError('migration');
  }

  Future<void> close() async {
    closes += 1;
    trace.add('$name closed');
  }
}

final class Lock {
  final List<String> trace;
  bool released = false;

  Lock(this.trace);

  Future<void> release() async {
    released = true;
    trace.add('lock released');
  }
}

/// A step the test lets through when it wants to.
final class Gate {
  final _open = Completer<void>();

  Future<void> wait() => _open.future;

  Future<void> release() async {
    _open.complete();
    await pump();
  }
}

void main() {
  late List<String> trace;

  Future<Database> open([String name = 'db']) async {
    trace.add('$name opened');
    return Database(name, trace);
  }

  Future<Lock> acquire() async {
    trace.add('lock acquired');
    return Lock(trace);
  }

  setUp(() => trace = <String>[]);

  tearDown(() => JobBase.debug = null);

  group('Choosing the callback', () {
    test('discard leaves a lock the body keeps held', () async {
      late Lock lock;
      final job = Job<Database>(key: 'work', (ctx) async {
        lock = await ctx.join(acquire, discard: (lock) => lock.release());
        return ctx.join(open);
      })
        ..ignore();
      final db = await job.value;

      expect(job.outcome, isA<Done<Database>>());
      expect(lock.released, isFalse);
      expect(db.closed, isFalse);
    });

    test('dispose releases it on the successful path too', () async {
      late Lock lock;
      final job = Job<Database>(key: 'work', (ctx) async {
        lock = await ctx.join(acquire, dispose: (lock) => lock.release());
        return ctx.join(open, discard: (db) => db.close());
      })
        ..ignore();
      final db = await job.value;

      expect(lock.released, isTrue);
      expect(db.closed, isFalse);
    });

    test('a cancelled job releases both', () async {
      final gate = Gate();
      late Lock lock;
      late Database db;
      final job = Job<Database>(key: 'work', (ctx) async {
        lock = await ctx.join(acquire, dispose: (lock) => lock.release());
        db = await ctx.join(open, discard: (db) => db.close());
        await ctx.join(gate.wait);
        return db;
      })
        ..ignore();
      await pump();
      job.cancel().ignore();
      await gate.release();
      await job.done;

      expect(job.outcome, isA<Cancelled>());
      expect(lock.released, isTrue);
      expect(db.closed, isTrue);
    });
  });

  group('A resource that travels', () {
    DeferredJob<Database> connect({Gate? gate, bool cancellable = true}) =>
        Job.deferred<Database>(
          key: 'connect',
          cancellable: cancellable,
          (ctx) async {
            final db = await ctx.wait(open, discard: (db) => db.close());
            if (gate != null) {
              await ctx.join(gate.wait);
            }
            return db;
          },
        );

    test('the child that handed its value over closes nothing', () async {
      final ready = Job<Database>(key: 'ready', (ctx) async {
        final db = await ctx.run(connect());
        await ctx.join(db.failingMigrate);
        return db;
      })
        ..ignore();
      await ready.done;

      expect(ready.outcome, isA<Failed>());
      expect(trace, isNot(contains('db closed')));
    });

    test('the registration under run is never reached', () async {
      final gate = Gate();
      final ready = Job<Database>(key: 'ready', (ctx) async {
        final db = await ctx.run(connect(gate: gate, cancellable: false));
        ctx.onDiscard(db.close);
        trace.add('parent registered the database');
        return db;
      })
        ..ignore();
      await pump();
      ready.cancel().ignore();
      await gate.release();
      await ready.done;

      expect(ready.outcome, isA<Cancelled>());
      expect(trace, isNot(contains('parent registered the database')));
      expect(trace, isNot(contains('db closed')));
    });

    test('the registration handed to run closes it', () async {
      final gate = Gate();
      final ready = Job<Database>(key: 'ready', (ctx) async {
        final db = await ctx.run(
          connect(gate: gate, cancellable: false),
          discard: (db) => db.close(),
        );
        trace.add('parent registered the database');
        return db;
      })
        ..ignore();
      await pump();
      ready.cancel().ignore();
      await gate.release();
      await ready.done;

      expect(ready.outcome, isA<Cancelled>());
      expect(trace, contains('db closed'));
    });

    test('a hand-over that succeeds leaves the database open', () async {
      final ready = Job<Database>(key: 'ready', (ctx) async {
        final db = await ctx.run(connect(), discard: (db) => db.close());
        await ctx.join(db.migrate);
        return db;
      })
        ..ignore();
      final db = await ready.value;

      expect(db.closed, isFalse);
      expect(trace, contains('db migrated'));
    });

    test('the debug channel names the dropped registration', () async {
      final said = <String>[];
      JobBase.debug = said.add;
      final parent = Job<void>(key: 'parent', (ctx) async {
        await ctx.run(connect());
      })
        ..ignore();
      await parent.done;

      expect(
        said,
        contains('Job(connect) handed its value over: '
            '1 conditional cleanup dropped'),
      );
    });
  });

  group('Registering without a call', () {
    test('the unregister call under the action is not reached', () async {
      final gate = Gate();
      final cursor = Database('cursor', trace);
      final job = Job<void>(key: 'read', (ctx) async {
        final removeDisposer = ctx.onDispose(cursor.close);
        await ctx.join(() async {
          await gate.wait();
          await cursor.close();
        });
        removeDisposer();
      })
        ..ignore();
      await pump();
      job.cancel().ignore();
      await gate.release();
      await job.done;

      expect(cursor.closes, 2);
    });

    test('unregistering inside the action closes it once', () async {
      final gate = Gate();
      final cursor = Database('cursor', trace);
      final job = Job<void>(key: 'read', (ctx) async {
        final removeDisposer = ctx.onDispose(cursor.close);
        await ctx.join(() async {
          await gate.wait();
          await cursor.close();
          removeDisposer();
        });
      })
        ..ignore();
      await pump();
      job.cancel().ignore();
      await gate.release();
      await job.done;

      expect(cursor.closes, 1);
    });

    test('the unregister function is safe twice and after cleanup', () async {
      late void Function() removeDisposer;
      final job = Job<void>(key: 'twice', (ctx) async {
        removeDisposer = ctx.onDispose(() async => trace.add('disposer ran'));
        removeDisposer();
        removeDisposer();
      })
        ..ignore();
      await job.done;
      removeDisposer();

      expect(job.outcome, isA<Done<void>>());
      expect(trace, isEmpty);
    });

    test('disown looks the value up by identity', () async {
      final answers = <bool>[];
      final job = Job<void>(key: 'disown', (ctx) async {
        final db = await ctx.join(open, dispose: (db) => db.close());
        answers
          ..add(ctx.disown(Database('db', trace)))
          ..add(ctx.disown(db))
          ..add(ctx.disown(db));
      })
        ..ignore();
      await job.done;

      expect(answers, <bool>[false, true, false]);
      expect(trace, isNot(contains('db closed')));
    });
  });

  group('Cleanup order and late results', () {
    test('cleanup waits for the children', () async {
      final gate = Gate();
      final job = Job<void>(key: 'parent', (ctx) async {
        ctx.onDispose(() async => trace.add('parent cleanup'));
        unawaited(
          ctx
              .run(
                Job.deferred<void>(key: 'child', (child) async {
                  await child.join(gate.wait);
                  trace.add('child finished');
                }),
              )
              .onError((_, __) {}),
        );
        await pump();
      })
        ..ignore();
      await pump();
      await gate.release();
      await job.done;

      expect(
        trace,
        containsAllInOrder(<String>['child finished', 'parent cleanup']),
      );
    });

    test('callbacks run in reverse order and each is awaited', () async {
      final job = Job<void>(key: 'order', (ctx) async {
        ctx
          ..onDispose(() async {
            await pump();
            trace.add('first');
          })
          ..onDispose(() async => trace.add('second'));
      })
        ..ignore();
      await job.done;

      expect(trace, <String>['second', 'first']);
    });

    test('an error in one callback leaves the rest running', () async {
      final errors = <Object>[];
      final job = Job<void>(
        key: 'boom',
        observer: ErrorObserver(errors),
        (ctx) async {
          ctx
            ..onDispose(() async => trace.add('under it'))
            ..onDispose(() async => throw StateError('cleanup failed'));
        },
      )..ignore();
      await job.done;

      expect(errors, <Matcher>[isStateError]);
      expect(trace, <String>['under it']);
      expect(job.outcome, isA<Done<void>>());
    });

    test('a cancellation into the unwinding stops no callback', () async {
      final gate = Gate();
      final job = Job<void>(key: 'unwind', (ctx) async {
        ctx
          ..onDispose(() async => trace.add('under it'))
          ..onDispose(() async {
            trace.add('waiting');
            await gate.wait();
            trace.add('released');
          });
      })
        ..ignore();
      await pump();
      // It lands while the first callback is awaiting its resource.
      job.cancel().ignore();
      await gate.release();
      await job.done;

      expect(trace, <String>['waiting', 'released', 'under it']);
    });

    test('waiting methods throw StateError inside a callback', () async {
      final caught = <Object>[];
      final job = Job<void>(key: 'late', (ctx) async {
        ctx.onDispose(() async {
          try {
            await ctx.join(() async => 1);
          } on Object catch (error) {
            caught.add(error);
          }
        });
      })
        ..ignore();
      await job.done;

      expect(caught, <Matcher>[isStateError]);
    });

    test('cancellation after the return closes what was returned', () async {
      final gate = Gate();
      late Database db;
      final job = Job<Database>(key: 'open', (ctx) async {
        db = await ctx.join(open, discard: (db) => db.close());
        unawaited(
          ctx
              .run(
                Job.deferred<void>(
                  key: 'child',
                  (child) => child.join(gate.wait),
                ),
              )
              .onError((_, __) {}),
        );
        await pump();
        return db;
      })
        ..ignore();
      unawaited(job.value.onError((_, __) => Database('none', trace)));
      await pump();
      await pump();
      job.cancel().ignore();
      await gate.release();
      await job.done;

      expect(job.outcome, isA<Cancelled>());
      expect(db.closed, isTrue);
    });

    test('the second pass runs the discard after the later callbacks',
        () async {
      final gate = Gate();
      final job = Job<Database>(key: 'order', (ctx) async {
        ctx
          ..onDispose(() async => trace.add('disposer A'))
          ..onDispose(() async {
            trace.add('disposer B waits');
            await gate.wait();
            trace.add('disposer B done');
          });
        return ctx.join(open, discard: (db) => db.close());
      })
        ..ignore();
      unawaited(job.value.onError((_, __) => Database('none', trace)));
      await pump();
      await pump();
      job.cancel().ignore();
      await pump();
      await gate.release();
      await job.done;

      expect(
        trace,
        containsAllInOrder(<String>[
          'disposer B done',
          'disposer A',
          'db closed',
        ]),
      );
    });

    test('a branch whose group handed the values over keeps its value',
        () async {
      final job = Job<void>(key: 'group', (ctx) async {
        final values = await ctx.runAll(<Job<Database>>[
          Job.deferred<Database>(
            key: 'left',
            (branch) =>
                branch.wait(() => open('left'), discard: (db) => db.close()),
          ),
          Job.deferred<Database>(
            key: 'right',
            (branch) =>
                branch.wait(() => open('right'), discard: (db) => db.close()),
          ),
        ]);
        trace.add('group handed over ${values.length} values');
      })
        ..ignore();
      await job.done;

      expect(job.outcome, isA<Done<void>>());
      expect(trace, contains('group handed over 2 values'));
      expect(trace, isNot(contains('left closed')));
      expect(trace, isNot(contains('right closed')));
    });

    test('a branch whose group never decided closes what it took', () async {
      final gate = Gate();
      final job = Job<void>(key: 'group', (ctx) async {
        await ctx.runAll(<Job<Database>>[
          Job.deferred<Database>(key: 'left', (branch) async {
            final db = await branch.wait(
              () => open('left'),
              discard: (db) => db.close(),
            );
            await branch.join(gate.wait);
            return db;
          }),
          Job.deferred<Database>(
            key: 'right',
            (branch) =>
                branch.wait(() => open('right'), discard: (db) => db.close()),
          ),
        ]);
      })
        ..ignore();
      await pump();
      job.cancel().ignore();
      await gate.release();
      await job.done;

      expect(job.outcome, isA<Cancelled>());
      expect(trace, contains('left closed'));
      expect(trace, contains('right closed'));
    });

    test('a value abandoned by wait is released after the job ended', () async {
      final gate = Gate();
      final job = Job<void>(key: 'abandon', (ctx) async {
        await ctx.wait(
          () async {
            await gate.wait();
            return open('late');
          },
          dispose: (db) => db.close(),
        );
      })
        ..ignore();
      await pump();
      job.cancel().ignore();
      await job.done;
      trace.add('job ended ${job.outcome}');
      await gate.release();
      await pump();

      expect(
        trace,
        containsAllInOrder(<String>[
          'job ended Cancelled(manual)',
          'late opened',
          'late closed',
        ]),
      );
    });

    test('a plain await registers what a cancellation could not interrupt',
        () async {
      final gate = Gate();
      late Database db;
      final job = Job<Database>(key: 'open', (ctx) async {
        await gate.wait();
        db = await open();
        ctx.onDiscard(db.close);
        return db;
      })
        ..ignore();
      unawaited(job.value.onError((_, __) => Database('none', trace)));
      await pump();
      job.cancel().ignore();
      await gate.release();
      await job.done;

      expect(job.outcome, isA<Cancelled>());
      expect(db.closed, isTrue);
    });
  });
}

Future<void> pump() => Future<void>.delayed(Duration.zero);
