// The blocks of the README, run as they are written there, what its prose
// says about them and about its neighbours in Dart, and the example it
// points to.
//
// It is a showcase, so it is the one page a reader is most likely to copy
// and the one a reader is most likely to check under a debugger. Its
// Quick start used to prove nothing: `cancel` stood next to the
// constructor, the body never started, and the promised line --
// `Cancelled(manual)` -- printed while the database was never opened and
// never closed. The example printed that one path, while its comments
// described the others.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../example/example.dart' as example;
import 'support/page_code.dart';

/// The `Database` of the blocks, with a journal instead of a disk.
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

void use(List<String> rows) => Database.events.add('used ${rows.length}');

// The blocks of the README stand between these marks, each as it is
// written there, with nothing more; the flag is declared as the block
// declares it.
// README: begin
// ignore: type_annotate_public_apis
var cancelled = false;

Future<void> load() async {
  final db = await Database.open();
  if (cancelled) {
    return; // the database stays open
  }
  final rows = await db.readAll();
  if (cancelled) {
    return; // and so does it here
  }
  use(rows);
}
// README: end

/// The job the README opens with, as it is written there.
Future<void> openingJob() async {
  // README: begin
  final job = Job<void>((ctx) async {
    // Checked before the call and again before the value comes back,
    // and the database is closed whichever way the job ends.
    final db = await ctx.join(Database.open, dispose: (db) => db.close());
    use(await ctx.join(db.readAll));
  });

  // Somebody left the screen while the read was in flight.
  await Future<void>.delayed(const Duration(milliseconds: 50));

  // Waits for the body, its children and its cleanup.
  await job.cancel();
  print(job.outcome); // Cancelled(manual)
  // README: end
}

/// The Quick start of the README, as it is written there.
Future<void> quickStart() async {
  // README: begin
  final job = Job<Database>((ctx) async {
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

  // Somebody changed their mind while the database was opening.
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await job.cancel();

  final outcome = await job.done; // Cancelled(manual)
  // README: end
  print(outcome);
}

/// What [run] prints, on fake time, once every timer has fired.
List<String> printedBy(Future<void> Function() run) {
  final lines = <String>[];
  fakeAsync((async) {
    runZoned(
      () => unawaited(run()),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ),
    );
    async.flushTimers();
  });
  return lines;
}

void main() {
  setUp(() {
    Database.events.clear();
    cancelled = false;
  });

  group('the flag the README starts from', () {
    test('leaves the database open when it is set during the open', () {
      fakeAsync((async) {
        unawaited(load());
        async.elapse(const Duration(milliseconds: 10));
        cancelled = true;
        async.flushTimers();

        expect(Database.events, ['opened']);
      });
    });

    test('and when it is set during the read', () {
      fakeAsync((async) {
        unawaited(load());
        async.elapse(const Duration(milliseconds: 50));
        cancelled = true;
        async.flushTimers();

        expect(Database.events, ['opened', 'read']);
      });
    });
  });

  test('the job the README opens with earns every line of it', () {
    final printed = printedBy(openingJob);

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
    expect(printed, ['Cancelled(manual)']);
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
      // Quick start used to show, and why the wait in it is not decoration.
      expect(job.outcome.toString(), 'Cancelled(manual)');
      expect(Database.events, isEmpty);
    });
  });

  group('what Dart already has', () {
    test('Future.timeout stops the waiting, and a late database stays open',
        () {
      fakeAsync((async) {
        Object? error;
        Database.open().timeout(const Duration(milliseconds: 10)).then<void>(
              (_) {},
              onError: (Object e) => error = e,
            );
        async.flushTimers();

        expect(error, isA<TimeoutException>());
        expect(Database.events, ['opened']);
      });
    });

    test(
        'CancelableOperation runs its onCancel, and a late database stays '
        'open', () {
      fakeAsync((async) {
        final operation = CancelableOperation.fromFuture(
          Database.open(),
          onCancel: () => Database.events.add('onCancel'),
        );
        Database? value;
        operation.value.then((database) => value = database).ignore();
        async.elapse(const Duration(milliseconds: 10));
        operation.cancel().ignore();
        async.flushTimers();

        expect(operation.isCanceled, isTrue);
        expect(value, isNull);
        expect(Database.events, ['onCancel', 'opened']);
      });
    });

    test('an onCancel written to catch the late database closes it', () {
      fakeAsync((async) {
        final open = Database.open();
        final operation = CancelableOperation.fromFuture(
          open,
          onCancel: () async => (await open).close(),
        );
        async.elapse(const Duration(milliseconds: 10));
        operation.cancel().ignore();
        async.flushTimers();

        expect(Database.events, ['opened', 'closed']);
      });
    });

    test(
        'ctx.join hands a database that opens after the cancellation to '
        'its dispose', () {
      fakeAsync((async) {
        final job = Job<void>((ctx) async {
          await ctx.join(Database.open, dispose: (db) => db.close());
        });
        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore();
        async.flushTimers();

        expect(Database.events, ['opened', 'closed']);
        expect(job.outcome.toString(), 'Cancelled(manual)');
      });
    });

    test(
        'Timer(limit, job.cancel) cancels a job still running and leaves a '
        'finished one be', () {
      fakeAsync((async) {
        const limit = Duration(milliseconds: 30);
        final slow = Job<void>((ctx) async {
          final db = await ctx.join(Database.open, dispose: (db) => db.close());
          use(await ctx.join(db.readAll));
        });
        Timer(limit, slow.cancel);
        final quick = Job<int>((ctx) async => 1);
        Timer(limit, quick.cancel);
        async.flushTimers();

        expect(slow.outcome.toString(), 'Cancelled(manual)');
        expect(Database.events, ['opened', 'read', 'closed']);
        expect(quick.outcome.toString(), 'Done(1)');
      });
    });

    test(
        'the timer lives until the limit, and stopping it through job.done '
        'keeps a failure from the zone', () {
      for (final throughDone in [false, true]) {
        final zone = <Object>[];
        var timers = -1;
        runZonedGuarded(
          () => fakeAsync((async) {
            final job = Job<int>((ctx) async => throw StateError('failed'));
            final timer = Timer(const Duration(seconds: 1), job.cancel);
            if (throughDone) {
              job.done.whenComplete(timer.cancel).ignore();
            }
            async.elapse(const Duration(milliseconds: 5));
            timers = async.pendingTimers.length;
            async.flushTimers();
          }),
          (error, stackTrace) => zone.add(error),
        );

        expect(timers, throughDone ? 0 : 1);
        expect(zone, throughDone ? isEmpty : [isA<StateError>()]);
      }
    });
  });

  group('the Quick start', () {
    test('as the README writes it, closes the database', () {
      final printed = printedBy(quickStart);

      expect(Database.events, ['opened', 'closed']);
      expect(printed, ['Cancelled(manual)']);
    });

    test(
        'a cancellation the section held lands as the section closes, and '
        'the body goes on to return', () {
      fakeAsync((async) {
        final job = Job<Database>((ctx) async {
          // Not the Quick start's own lines, so that the check of the
          // README finds those in `quickStart` alone.
          final database =
              await ctx.join(Database.open, discard: (db) => db.close());
          ctx.onCancel(() => Database.events.add('onCancel'));
          await ctx.uncancellable(() async {
            await database.writeVersion();
            await ctx.run(database.readyFlag());
          });
          Database.events.add('return database');
          return database;
        });
        // The database opens in 20 ms, and the version takes 10.
        async.elapse(const Duration(milliseconds: 25));
        job.cancel().ignore();
        async.flushTimers();

        expect(Database.events, [
          'opened',
          'version written',
          'ready flag written',
          'onCancel',
          'return database',
          'closed',
        ]);
        expect(job.outcome.toString(), 'Cancelled(manual)');
      });
    });

    test('a child made with Job(...) is refused by ctx.run', () {
      fakeAsync((async) {
        final job = Job<void>((ctx) => ctx.run(Job<void>((ctx) async {})))
          ..ignore();
        async.flushTimers();

        expect(
          job.outcome,
          isA<Failed>().having((f) => f.error, 'error', isA<ArgumentError>()),
        );
      });
    });
  });

  test('the example runs the job to its end and cancels it at each step', () {
    expect(printedBy(example.main), [
      'Nobody changes their mind:',
      'database opened',
      'migrated',
      'version written',
      'ready flag written',
      'Done(database)',
      'database closed',
      '\nSomebody changes their mind while the database opens:',
      'database opened',
      'database closed',
      'Cancelled(manual)',
      '\nWhile it migrates, the token stops the migration:',
      'database opened',
      'migration stopped',
      'database closed',
      'Cancelled(manual)',
      '\nWhile the version is written, the step ends whole:',
      'database opened',
      'migrated',
      'version written',
      'ready flag written',
      'database closed',
      'Cancelled(manual)',
    ]);
  });

  test('every block of the README runs in this file', () {
    expect(
      codeMissingFrom('README.md', 'test/readme_recipe_test.dart'),
      isEmpty,
    );
  });

  test('and each of them runs whole, with nothing more', () {
    // The check above finds each piece between blank lines on its own, so
    // a line dropped from the edge of a piece, or one added here between
    // two pieces, would pass it. Between the marks, each copy is its block
    // of the README and nothing else; an import stays at the top.
    List<String> code(Iterable<String> lines) => [
          for (final line in lines)
            if (line.trim().isNotEmpty &&
                !line.trim().startsWith('// ignore:') &&
                !line.startsWith('import '))
              line.trim(),
        ];
    List<List<String>> blocks(String pattern, String file) => [
          for (final match in RegExp(pattern, dotAll: true)
              .allMatches(File(file).readAsStringSync()))
            code(match.group(1)!.split('\n')),
        ];

    expect(
      blocks(
        r'// README: begin\n(.*?)\n\s*// README: end',
        'test/readme_recipe_test.dart',
      ),
      blocks(r'```dart\n(.*?)\n```', 'README.md'),
    );
  });

  test('the example runs the job of the Quick start as the README writes it',
      () {
    // Comments aside: the example explains the body in its own comments,
    // and the README in the list under the block.
    List<String> code(Iterable<String> lines) => [
          for (final line in lines)
            if (line.trim().isNotEmpty && !line.trim().startsWith('//'))
              line.trim(),
        ];

    final block = RegExp(r'```dart\n(.*?)\n```', dotAll: true)
        .allMatches(File('README.md').readAsStringSync())
        .map((match) => match.group(1)!)
        .singleWhere((block) => block.contains('Job<Database>'));
    final lines = block.split('\n');
    final start = lines.indexWhere((line) => line.contains('Job<Database>('));
    final body = code(lines.sublist(start, lines.indexOf('});', start) + 1));

    final source = code(File('example/example.dart').readAsLinesSync());
    final at = source.indexWhere(
      (line) => line.endsWith(body.first.replaceFirst('final job = ', '')),
    );
    expect(at, isNot(-1), reason: 'the example builds no such job');
    expect(source.sublist(at + 1, at + body.length), body.sublist(1));
  });
}
