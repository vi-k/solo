// The block the README opens with, run as it is written there, and the
// block of its Quick start.
//
// It is a showcase, so it is the one block a reader is most likely to copy
// and the one a reader is most likely to check under a debugger. It also
// used to prove nothing: `cancel` stood next to the constructor, the body
// never started, and the promised line -- `Cancelled(manual)` -- printed
// while the database was never opened and never closed.
@Timeout(Duration(seconds: 5))
library;

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

/// The `Database` of the block, with a journal instead of a disk.
final class Database {
  static final events = <String>[];

  Database._();

  static Future<Database> open() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    events.add('opened');
    return Database._();
  }

  Future<List<String>> readAll() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    events.add('read');
    return const ['row'];
  }

  Future<void> migrate(CancelToken stop) async {
    for (var step = 1; step <= 3; step++) {
      if (stop.cancelled) {
        events.add('migration stopped');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    events.add('migrated');
  }

  Future<void> writeVersion() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    events.add('version written');
  }

  Job<void> readyFlag() => Job.deferred(
        (ctx) => ctx.join(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          events.add('ready flag written');
        }),
      );

  Future<void> close() async => events.add('closed');
}

final class CancelToken {
  bool cancelled = false;

  void cancel() => cancelled = true;
}

/// The body of the Quick start, as the README writes it.
Job<Database> quickStart() => Job<Database>((ctx) async {
      final database = await ctx.join(
        Database.open,
        discard: (database) => database.close(),
      );

      final stop = CancelToken();
      ctx.onCancel(stop.cancel);

      await ctx.join(() => database.migrate(stop));
      await ctx.uncancellable(() async {
        await database.writeVersion();
        await ctx.run(database.readyFlag());
      });

      return database;
    });

void use(List<String> rows) => Database.events.add('used ${rows.length}');

void main() {
  setUp(Database.events.clear);

  test('the block the README opens with earns every line of it', () {
    fakeAsync((async) {
      final job = Job<void>((ctx) async {
        // Checked before the call and again before the value comes back,
        // and the database is closed whichever way the job ends.
        final db = await ctx.join(Database.open, dispose: (db) => db.close());
        use(await ctx.join(db.readAll));
      });

      // Somebody left the screen while the read was in flight.
      async.elapse(const Duration(milliseconds: 50));
      job.cancel().ignore();
      async.flushTimers();

      expect(
        Database.events,
        ['opened', 'read', 'closed'],
        reason: 'the body was entered and the database opened; `join` waited '
            'for the read it had already asked for, and the registration '
            'closed the database on the way out',
      );
      expect(
        Database.events,
        isNot(contains('used 1')),
        reason: 'and the value never reached the body: the cancellation came '
            'first',
      );
      expect(job.outcome.toString(), 'Cancelled(manual)');
    });
  });

  group('the Quick start', () {
    test('cancelled while the database opens, it closes the database', () {
      fakeAsync((async) {
        final job = quickStart();

        // Somebody changed their mind while the database was opening.
        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore();
        async.flushTimers();

        expect(Database.events, ['opened', 'closed']);
        expect(job.outcome.toString(), 'Cancelled(manual)');
      });
    });

    test('cancelled during the migration, the token stops it', () {
      fakeAsync((async) {
        final job = quickStart();
        async.elapse(const Duration(milliseconds: 35));
        job.cancel().ignore();
        async.flushTimers();

        expect(Database.events, ['opened', 'migration stopped', 'closed']);
        expect(job.outcome.toString(), 'Cancelled(manual)');
      });
    });

    test('cancelled while the version is written, the step ends whole', () {
      fakeAsync((async) {
        final job = quickStart();
        // Open 20 ms, migration 30 ms, then the version.
        async.elapse(const Duration(milliseconds: 55));
        job.cancel().ignore();
        async.flushTimers();

        expect(
          Database.events,
          [
            'opened',
            'migrated',
            'version written',
            'ready flag written',
            'closed',
          ],
          reason: 'the section holds the cancellation, so `ctx.run` starts '
              'the child that writes the flag',
        );
        expect(job.outcome.toString(), 'Cancelled(manual)');
      });
    });
  });

  test('cancelled next to its constructor the same job does none of it', () {
    fakeAsync((async) {
      final job = Job<void>((ctx) async {
        final db = await ctx.join(Database.open, dispose: (db) => db.close());
        use(await ctx.join(db.readAll));
      });
      job.cancel().ignore();
      async.flushTimers();

      // The same printed line, and nothing behind it. This is what the
      // block used to show, and why the wait above is not decoration.
      expect(job.outcome.toString(), 'Cancelled(manual)');
      expect(Database.events, isEmpty);
    });
  });
}
