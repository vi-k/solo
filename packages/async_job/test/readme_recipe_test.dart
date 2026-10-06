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
//
// What the page quotes is read from the page: the output in the comments
// of its blocks and the outcome of a job cancelled before its start, from
// the README and its translation alike, the number of runs of the example
// and the dependency of the package. A literal kept here would follow the
// code, and the page would go on promising what the code no longer does.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../example/example.dart' as example;
import 'support/delay.dart';
import 'support/page_code.dart';

/// The `Database` of the blocks, with a journal instead of a disk.
final class Database {
  static final events = <String>[];

  /// What [open] fails with once its time has passed; nothing by default.
  static StateError? openError;

  Database._();

  static Future<Database> open() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (openError case final error?) {
      throw error;
    }
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

/// Hears what reaches the observer of a job, and answers for nothing.
final class Listening with JobObserver {
  final heard = <String>[];

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('onError: $error');
}

/// Hears it as well, and answers for what has nowhere else to go.
final class Answering extends Listening with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('onUnanswered: $error');
}

// The blocks of the README stand between these marks, each as it is
// written there, with nothing more; the flag is declared as the block
// declares it.
// README: begin
// ignore: type_annotate_public_apis
var cancelled = false;

Future<void> load() async {
  final db = await Database.open();
  if (cancelled) {
    await db.close();
    return;
  }
  final rows = await db.readAll();
  if (cancelled) {
    await db.close();
    return;
  }
  use(rows);
  await db.close();
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

/// The operation of the README that catches a late database, as it is
/// written there.
CancelableOperation<Database> lateOpenCaught() {
  // README: begin
  final open = Database.open();
  final operation = CancelableOperation.fromFuture(
    open,
    // cancel() stops the waiting; this closes the database once it opens.
    onCancel: () async => (await open).close(),
  );
  // README: end
  return operation;
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

/// What reaches the zone while [body] runs on fake time, every timer fired.
///
/// The zone catches whatever is thrown inside, a failed `expect` included,
/// so the checks stand outside: [body] only collects.
List<String> zoneErrorsOf(void Function(FakeAsync async) body) {
  final zone = <String>[];
  runZonedGuarded(
    () => fakeAsync((async) {
      body(async);
      async.flushTimers();
    }),
    (error, stackTrace) => zone.add('$error'),
  );
  return zone;
}

/// The README and its translation: the output and the outcomes they quote
/// are the same in both.
///
/// The translation is read where it is. `.pubignore` keeps it out of the
/// archive, and the `floor` job runs this file on the archive, where the
/// README is read alone. In the tree a missing translation fails
/// `tool/check_translations.py`.
final readmes = [
  'README.md',
  if (File('README.ru.md').existsSync()) 'README.ru.md',
];

String read(String file) => File(file).readAsStringSync();

/// The output a block of [page] quotes in the comment that closes the line
/// starting with [code].
String quotedAfter(String page, String code) {
  final line = RegExp(r'```dart\n(.*?)\n```', dotAll: true)
      .allMatches(read(page))
      .expand((block) => block.group(1)!.split('\n'))
      .map((line) => line.trim())
      .singleWhere((line) => line.startsWith(code));
  return line.substring(line.indexOf('// ') + 3);
}

void main() {
  setUp(() {
    Database.events.clear();
    Database.openError = null;
    cancelled = false;
  });

  group('the flag the README starts from', () {
    test('closes the database at the check after the open', () {
      fakeAsync((async) {
        unawaited(load());
        async.elapse(const Duration(milliseconds: 10));
        cancelled = true;
        async.flushTimers();

        expect(Database.events, ['opened', 'closed']);
      });
    });

    test('and at the check after the read', () {
      fakeAsync((async) {
        unawaited(load());
        async.elapse(const Duration(milliseconds: 50));
        cancelled = true;
        async.flushTimers();

        expect(Database.events, ['opened', 'read', 'closed']);
      });
    });

    test('and once more at the end when nobody sets the flag', () {
      fakeAsync((async) {
        unawaited(load());
        async.flushTimers();

        expect(Database.events, ['opened', 'read', 'used 1', 'closed']);
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
    for (final page in readmes) {
      expect(
        printed,
        [quotedAfter(page, 'print(job.outcome);')],
        reason: page,
      );
    }
  });

  test('cancelled next to its constructor the same job does none of it', () {
    fakeAsync((async) {
      final job = Job<void>((ctx) async {
        final db = await ctx.join(Database.open, dispose: (db) => db.close());
        use(await ctx.join(db.readAll));
      });
      job.cancel().ignore();
      async.flushTimers();

      // The outcome the README promises for it. This is what the Quick start
      // used to show, and why the wait in it is not decoration.
      final outcome = job.outcome! as Cancelled;
      for (final page in readmes) {
        final promised = RegExp(
          r'`(Cancelled\(\w+\))`\s+(?:with|с)\s+`started: (\w+)`',
        ).firstMatch(read(page))!;
        expect('$outcome', promised.group(1), reason: page);
        expect('${outcome.started}', promised.group(2), reason: page);
      }
      expect(Database.events, isEmpty);
    });
  });

  group('what reaches the zone', () {
    test('awaiting cancel() and reading outcome do not observe a failure', () {
      final reads = <String>[];
      final zone = zoneErrorsOf((async) {
        // `cancellable: false` refuses the cancellation, so `cancel()` is
        // called and awaited while the job still runs, and the failure
        // comes after both.
        final job = Job<void>(cancellable: false, (ctx) async {
          await ctx.join(() => delay(20));
          throw StateError('read failed');
        });
        Future<void> cancelAndRead() async {
          await delay(10);
          final cancelling = job.cancel();
          reads.add('${job.outcome}');
          await cancelling;
          reads.add('${job.outcome}');
        }

        unawaited(cancelAndRead());
      });

      expect(reads, ['null', 'Failed(Bad state: read failed)']);
      expect(zone, ['Bad state: read failed']);
    });

    test('nor does the observer of the job, answering or not', () {
      for (final observer in [Listening(), Answering()]) {
        final zone = zoneErrorsOf((async) {
          Job<void>(
            observer: observer,
            (ctx) async => throw StateError('read failed'),
          );
        });

        final kind = observer is Answering ? 'answering' : 'listening';
        expect(
          observer.heard,
          ['onError: Bad state: read failed'],
          reason: kind,
        );
        expect(zone, ['Bad state: read failed'], reason: kind);
      }
    });

    test('accessing done or value, or calling ignore(), observes it', () {
      final ways = <String, void Function(Job<void> job)>{
        'done': (job) => job.done.ignore(),
        'value': (job) => job.value.ignore(),
        'ignore()': (job) => job.ignore(),
      };
      for (final MapEntry(key: way, value: observe) in ways.entries) {
        final zone = zoneErrorsOf((async) {
          observe(Job<void>((ctx) async => throw StateError('read failed')));
        });

        expect(zone, isEmpty, reason: way);
      }
    });

    test(
        'a cleanup error goes to the zone, outcome observed or not, unless '
        'the observer answers for it', () {
      for (final observer in [null, Listening(), Answering()]) {
        final zone = zoneErrorsOf((async) {
          Job<void>(observer: observer, (ctx) async {
            ctx.onDispose(() => throw StateError('close failed'));
          }).done.ignore();
        });

        switch (observer) {
          case null:
            expect(zone, ['Bad state: close failed']);
          case Answering():
            expect(observer.heard, [
              'onError: Bad state: close failed',
              'onUnanswered: Bad state: close failed',
            ]);
            expect(zone, isEmpty);
          case Listening():
            expect(observer.heard, ['onError: Bad state: close failed']);
            expect(zone, ['Bad state: close failed']);
        }
      }
    });

    test(
        'an open that fails after the cancellation reaches the observer '
        'alone, and nobody without one', () {
      for (final observer in [null, Listening(), Answering()]) {
        Database.openError = StateError('database locked');
        Outcome<Database>? ended;
        final zone = zoneErrorsOf((async) {
          final job = Job<Database>(
            observer: observer,
            (ctx) => ctx.join(Database.open, discard: (db) => db.close()),
          );
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
          ended = job.outcome;
        });

        expect('$ended', 'Cancelled(manual)');
        expect(zone, isEmpty);
        expect(
          observer?.heard,
          observer == null ? null : ['onError: Bad state: database locked'],
        );
      }
    });
  });

  group('the checkpoints', () {
    test('a running job accepts the request inside cancel() itself', () {
      for (final cancellable in [true, false]) {
        fakeAsync((async) {
          final trace = <String>[];
          final job = Job<void>(cancellable: cancellable, (ctx) async {
            ctx.onCancel(() => trace.add('onCancel'));
            for (final checkpoint in <Future<void> Function()>[
              () => ctx.abandonable(() => delay(50)),
              () async => ctx.check(),
            ]) {
              try {
                await checkpoint();
                trace.add('passed');
              } on Cancelled {
                trace.add('threw Cancelled');
              }
            }
          });
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          trace.add('cancel() returned');
          async.flushTimers();

          if (cancellable) {
            expect(trace, [
              'onCancel',
              'cancel() returned',
              'threw Cancelled',
              'threw Cancelled',
            ]);
            expect('${job.outcome}', 'Cancelled(manual)');
          } else {
            // Created with `cancellable: false`, it never accepts.
            expect(trace, ['cancel() returned', 'passed', 'passed']);
            expect('${job.outcome}', 'Done(null)');
          }
        });
      }
    });

    test(
        'inside an action passed to the context, and in cleanup, a direct '
        'await waits each step out', () {
      fakeAsync((async) {
        Future<void> step(String name) async {
          await delay(10);
          Database.events.add(name);
        }

        final job = Job<void>((ctx) async {
          ctx.onDispose(() async {
            await step('cleanup, first step');
            await step('cleanup, second step');
          });
          await ctx.join(() async {
            await step('first step');
            await step('second step');
          });
        });
        job.done.then((outcome) => Database.events.add('$outcome')).ignore();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushTimers();

        expect(Database.events, [
          'first step',
          'second step',
          'cleanup, first step',
          'cleanup, second step',
          'Cancelled(manual)',
        ]);
      });
    });

    test(
        'one join keeps a step of plain code whole, and not a step that '
        'takes the token', () {
      for (final takesToken in [false, true]) {
        fakeAsync((async) {
          final written = <String>[];
          final job = Job<void>((ctx) async {
            final token = CancelToken();
            ctx.onCancel(token.cancel);
            await ctx.join(() async {
              for (final part in ['version', 'flag']) {
                if (takesToken && token.cancelled) {
                  return;
                }
                await delay(10);
                written.add(part);
              }
            });
          });
          async.elapse(const Duration(milliseconds: 5));
          job.cancel().ignore();
          async.flushTimers();

          expect(
            written,
            takesToken ? ['version'] : ['version', 'flag'],
            reason: takesToken ? 'takes the token' : 'plain code',
          );
          expect('${job.outcome}', 'Cancelled(manual)');
        });
      }
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
        final operation = lateOpenCaught();
        async.elapse(const Duration(milliseconds: 10));
        operation.cancel().ignore();
        async.flushTimers();

        expect(Database.events, ['opened', 'closed']);
      });
    });

    test(
        'the same onCancel covers one wait: once the database is handed '
        'over, cancel() does nothing and the read runs on', () {
      fakeAsync((async) {
        final operation = lateOpenCaught();
        operation.value.then((db) async => use(await db.readAll())).ignore();
        async.elapse(const Duration(milliseconds: 50));
        operation.cancel().ignore();
        async.flushTimers();

        expect(operation.isCanceled, isFalse);
        expect(Database.events, ['opened', 'read', 'used 1']);
      });
    });

    test('a cancelled operation never completes its value', () {
      fakeAsync((async) {
        final operation = lateOpenCaught();
        var completed = false;
        operation.value.whenComplete(() => completed = true).ignore();
        async.elapse(const Duration(milliseconds: 10));
        operation.cancel().ignore();
        async.flushTimers();

        expect(operation.isCanceled, isTrue);
        expect(completed, isFalse);
      });
    });

    test(
        'the registration of ctx.join covers the rest of the job: an '
        'error after it closes the database too', () {
      fakeAsync((async) {
        final job = Job<void>((ctx) async {
          await ctx.join(Database.open, dispose: (db) => db.close());
          throw StateError('the read failed');
        })
          ..ignore();
        async.flushTimers();

        expect(Database.events, ['opened', 'closed']);
        expect(job.outcome, isA<Failed>());
      });
    });

    test(
        'ctx.join hands a database that opens after the cancellation to '
        'its dispose, and the job ends once the database is closed', () {
      fakeAsync((async) {
        final job = Job<void>((ctx) async {
          await ctx.join(Database.open, dispose: (db) => db.close());
        });
        async.elapse(const Duration(milliseconds: 10));
        job.cancel().then((_) => Database.events.add('job ended')).ignore();
        async.flushTimers();

        expect(Database.events, ['opened', 'closed', 'job ended']);
        expect(job.outcome.toString(), 'Cancelled(manual)');
      });
    });

    test(
        'ctx.abandonable stops the waiting as they do, and still hands that '
        'database to its dispose after the job has ended', () {
      fakeAsync((async) {
        final job = Job<void>((ctx) async {
          await ctx.abandonable(Database.open, dispose: (db) => db.close());
        });
        async.elapse(const Duration(milliseconds: 10));
        job.cancel().then((_) => Database.events.add('job ended')).ignore();
        async.flushTimers();

        expect(Database.events, ['job ended', 'opened', 'closed']);
        expect(job.outcome.toString(), 'Cancelled(manual)');
      });
    });

    test(
        'Job(body, timeout: limit) cancels a job still running once the '
        'limit has run out, and leaves no timer behind', () {
      for (final page in readmes) {
        expect(read(page), contains('`Job(body, timeout: limit)`'));
        expect(read(page), contains('`Cancelled(timeout)`'));
      }
      fakeAsync((async) {
        const limit = Duration(milliseconds: 30);
        final slow = Job<void>(timeout: limit, (ctx) async {
          final db = await ctx.join(Database.open, dispose: (db) => db.close());
          use(await ctx.join(db.readAll));
        });
        async.flushTimers();

        expect(slow.outcome.toString(), 'Cancelled(timeout)');
        expect(Database.events, ['opened', 'read', 'closed']);
      });
      fakeAsync((async) {
        final quick =
            Job<int>(timeout: const Duration(hours: 1), (ctx) async => 1);
        async.flushMicrotasks();

        expect(quick.outcome.toString(), 'Done(1)');
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('the Quick start', () {
    test('as the README writes it, closes the database', () {
      final printed = printedBy(quickStart);

      expect(Database.events, ['opened', 'closed']);
      for (final page in readmes) {
        expect(
          printed,
          [quotedAfter(page, 'final outcome = await job.done;')],
          reason: page,
        );
      }
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

    test('without the section a cancellation comes between the two', () {
      fakeAsync((async) {
        Object? thrown;
        Job<void>? flag;
        final job = Job<void>((ctx) async {
          final database =
              await ctx.join(Database.open, dispose: (db) => db.close());
          await ctx.join(() async {
            await database.writeVersion();
            flag = database.readyFlag();
            try {
              await ctx.run(flag!);
            } on Cancelled catch (error) {
              thrown = error;
              rethrow;
            }
          });
        });
        // The database opens in 20 ms, and the version takes 10.
        async.elapse(const Duration(milliseconds: 25));
        job.cancel().ignore();
        async.flushTimers();

        expect(Database.events, ['opened', 'version written', 'closed']);
        // `ctx.run` threw the job's own cancellation instead of starting
        // the child.
        expect('$thrown', 'Cancelled(manual)');
        expect((flag!.outcome! as Cancelled).started, isFalse);
        expect(job.outcome.toString(), 'Cancelled(manual)');
      });
    });
  });

  test('the example runs the job to its end and cancels it at each step', () {
    final printed = printedBy(example.main);
    expect(printed, [
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

    // The README counts the runs in a word, and each run opens with a
    // heading of its own.
    const numbers = {
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
    };
    final said = RegExp(r'runs the job\s+(\w+)\s+times')
        .firstMatch(read('README.md'))!
        .group(1);
    expect(printed.where((line) => line.endsWith(':')).length, numbers[said]);
  });

  group('what the README says of the package', () {
    test('it depends on the one package the README names', () {
      final named = RegExp(r'depends only on `(\w+)`')
          .firstMatch(read('README.md'))!
          .group(1);
      final pubspec = File('pubspec.yaml').readAsLinesSync();
      final dependencies = [
        for (final line in pubspec
            .skip(pubspec.indexOf('dependencies:') + 1)
            .takeWhile((line) => line.isEmpty || line.startsWith(' ')))
          if (RegExp(r'^  (\w+):').firstMatch(line) case final match?)
            match.group(1),
      ];

      expect(dependencies, [named]);
    });

    test(
        'the core imports dart:async, dart:collection and meta alone, so it '
        'is pure Dart and runs wherever Dart does', () {
      final imported = {
        for (final file
            in Directory('lib').listSync(recursive: true).whereType<File>())
          for (final match in RegExp(
            "^(?:import|export) '([^']+)'",
            multiLine: true,
          ).allMatches(file.readAsStringSync()))
            if (match.group(1)!.contains(':')) match.group(1)!.split('/').first,
      };

      expect(imported, {'dart:async', 'dart:collection', 'package:meta'});
    });

    test('the one block the checks do not run installs this package', () {
      final name = RegExp(r'^name: (\w+)$', multiLine: true)
          .firstMatch(read('pubspec.yaml'))!
          .group(1);
      for (final page in readmes) {
        expect(strayFences(page), ['```sh'], reason: page);
        expect(
          RegExp(r'```sh\n(.*?)\n```', dotAll: true)
              .firstMatch(read(page))!
              .group(1),
          'dart pub add $name',
          reason: page,
        );
      }
    });
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
