@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import 'support/error_observer.dart';
import 'support/fake_time.dart';

/// The first attempts of `doc/cleanup.md`, and what each one costs.
///
/// Three sections of the page open with the version the vocabulary of the
/// API leads to and say what that version does instead of what it was
/// meant to do. Nothing else guards those statements: the page has no
/// bench, so an owner or an order quoted there rots silently. Every claim
/// the page makes about who closes the resource, and when, is pinned here
/// next to the version it then shows, and the last test holds the lines
/// the page quotes to the lines these tests print.

/// What each `text` block of the page says, in the order of the page.
const quoted = [
  ['Job(connect) handed its value over: 1 conditional cleanup dropped'],
];

final class Database {
  final String name;
  final List<String> trace;
  int closes = 0;

  Database(this.name, this.trace);

  /// `Database.open` of the page, for a fragment run as it stands there.
  static Future<Database> open() async => Database('db', <String>[]);

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

/// A value with an equality of its own: two built from one name are equal,
/// and only one of them is the value a call handed over.
@immutable
final class Address {
  final String name;

  const Address(this.name);

  @override
  bool operator ==(Object other) => other is Address && other.name == name;

  @override
  int get hashCode => name.hashCode;
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

  tearDown(() => Job.debug = null);

  group('Choosing the callback', () {
    fakeAsyncTest('discard leaves a lock the body keeps held', () async {
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

    fakeAsyncTest('dispose releases it on the successful path too', () async {
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

    fakeAsyncTest('a cancelled job releases both', () async {
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

    fakeAsyncTest('the child that handed its value over closes nothing',
        () async {
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

    fakeAsyncTest('the registration under run is never reached', () async {
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

    fakeAsyncTest('the registration handed to run closes it', () async {
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

    fakeAsyncTest('a hand-over that succeeds leaves the database open',
        () async {
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

    fakeAsyncTest('the debug channel names the hand-over of the page',
        () async {
      final said = <String>[];
      Job.debug = said.add;

      final connect = Job.deferred<Database>(
        key: 'connect',
        (ctx) => ctx.wait(Database.open, discard: (db) => db.close()),
      );

      final ready = Job.deferred<Database>((ctx) async {
        final database = await ctx.run(connect);
        // As the page writes it.
        // ignore: unnecessary_lambdas
        await ctx.join(() => database.migrate());

        return database;
      })
        ..start();
      await ready.done;

      expect(said.where((line) => line.contains('handed')), quoted[0]);
    });
  });

  group('Registering without a call', () {
    fakeAsyncTest('the unregister call under the action is not reached',
        () async {
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

    fakeAsyncTest('unregistering inside the action closes it once', () async {
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

    fakeAsyncTest('the unregister function is safe twice and after cleanup',
        () async {
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

    fakeAsyncTest('disown looks the value up by identity', () async {
      final answers = <bool>[];
      final job = Job<void>(key: 'disown', (ctx) async {
        final address = await ctx.join(
          () => const Address('db'),
          dispose: (address) => trace.add('${address.name} released'),
        );
        // Built at run time: a constant would be the very same one.
        final equal = Address(address.name);
        answers
          ..add(equal == address)
          ..add(ctx.disown(equal))
          ..add(ctx.disown(address))
          ..add(ctx.disown(address));
      })
        ..ignore();
      await job.done;

      expect(
        answers,
        <bool>[true, false, true, false],
        reason: 'an equal value is not the one the call handed over',
      );
      expect(trace, isEmpty);
    });

    fakeAsyncTest('a number is found by an equal one of its type', () async {
      final answers = <bool>[];
      final job = Job<void>(key: 'disown', (ctx) async {
        final port = await ctx.join(
          () => int.parse('8080'),
          dispose: (port) => trace.add('port $port released'),
        );
        answers
          ..add(ctx.disown(8080))
          ..add(ctx.disown(port));
      })
        ..ignore();
      await job.done;

      expect(
        answers,
        <bool>[true, false],
        reason: 'a number has no identity apart from its value, as the '
            'dartdoc of disown says',
      );
      expect(trace, isEmpty);
    });
  });

  group('Cleanup order and late results', () {
    fakeAsyncTest('cleanup waits for the children', () async {
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

    fakeAsyncTest('callbacks run in reverse order and each is awaited',
        () async {
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

    fakeAsyncTest('an error in one callback leaves the rest running', () async {
      final errors = <Object>[];
      final job = Job<void>(
        key: 'boom',
        // Answering: the order is the subject, not where the error goes
        // after the observer.
        observer: ErrorObserver.answering(errors),
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

    fakeAsyncTest('a cancellation into the unwinding stops no callback',
        () async {
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

    fakeAsyncTest('waiting methods throw StateError inside a callback',
        () async {
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

    fakeAsyncTest('cancellation after the return closes what was returned',
        () async {
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

    fakeAsyncTest(
        'the second pass runs the discard after the earlier callbacks',
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
        final db = await ctx.join(open, discard: (db) => db.close());
        ctx.onDispose(() async => trace.add('disposer D'));
        return db;
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
        <String>[
          'db opened',
          'disposer D',
          'disposer B waits',
          'disposer B done',
          'disposer A',
          'db closed',
        ],
        reason: 'strict reverse order would close the database before A '
            'and B, registered before the discard; the second pass closes it '
            'after them',
      );
    });

    fakeAsyncTest('a branch whose group handed the values over keeps its value',
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

    fakeAsyncTest('a branch whose group never decided closes what it took',
        () async {
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

    fakeAsyncTest('a value abandoned by wait is released after the job ended',
        () async {
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

    fakeAsyncTest(
        'a plain await registers what a cancellation could not interrupt',
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

  test('the page quotes what these tests print', () {
    final page = File('doc/cleanup.md').readAsStringSync();
    final blocks = RegExp(r'```text\n(.*?)\n```', dotAll: true)
        .allMatches(page)
        .map((match) => match.group(1)!.split('\n'))
        .toList();

    expect(blocks, quoted);
  });
}

Future<void> pump() => Future<void>.delayed(Duration.zero);
