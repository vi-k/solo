// The blocks of the README, run as they are written there, what its prose
// says about them and about its neighbours in Dart, and the example it
// points to.
//
// It is a showcase, so it is the one page a reader is most likely to copy
// and the one a reader is most likely to check under a debugger. Its
// first Quick start used to prove nothing: `cancel` stood next to the
// constructor, the body never started, and the promised line --
// `Cancelled(manual)` -- printed while the database was never opened and
// never closed. The example printed that one path, while its comments
// described the others.
//
// What the page quotes is read from the page: the output in the comments
// of its blocks, the output of the example and the outcome of a job
// cancelled before its start, from the README and its translation alike,
// the number of runs of the example and the dependency of the package. A
// literal kept here would follow the code, and the page would go on
// promising what the code no longer does. The table of the context is read
// from the page too: every member of `JobContext` stands in it, and what it
// says of a cancellation is run here.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../example/example.dart' as example;
import '../example/quick_start.dart' as quick_start;
import 'support/delay.dart';
import 'support/page_code.dart';

/// The `Database` of the blocks, with a journal instead of a disk.
final class Database {
  static final events = <String>[];

  /// What [open] fails with once its time has passed; nothing by default.
  static StateError? openError;

  /// What [readAll] fails with once its time has passed; nothing by default.
  static StateError? readError;

  /// Whether [migrate] stops at its token by throwing [DatabaseStopped], as
  /// many clients do, rather than by returning.
  static bool stopThrows = false;

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
    if (readError case final error?) {
      throw error;
    }
    events.add('read');
    return const ['row'];
  }

  Future<void> migrate(CancelToken stop) async {
    for (var step = 1; step <= 3; step++) {
      if (stop.cancelled) {
        events.add('migration stopped');
        if (stopThrows) {
          throw const DatabaseStopped();
        }
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

  ChildJob<void> readyFlag() => Job.deferred(
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

/// How a client that stops by throwing stops at its token.
final class DatabaseStopped implements Exception {
  const DatabaseStopped();

  @override
  String toString() => 'DatabaseStopped';
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
// written there, with nothing more, in the order of the page; the flag is
// declared as the block declares it.

// README: begin
// ignore: type_annotate_public_apis
var cancelled = false;

Future<void> load() async {
  final db = await Database.open();
  try {
    if (cancelled) return;
    final rows = await db.readAll();
    if (cancelled) return;
    use(rows);
  } finally {
    await db.close();
  }
}
// README: end

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

/// The fuller example of the README, as it is written there.
Future<void> fullerExample() async {
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

/// The outputs [page] quotes: the Quick start's, then the example's.
List<String> quotedOutputs(String page) {
  final outputs = [
    for (final match
        in RegExp(r'```text\n(.*?)\n```', dotAll: true).allMatches(read(page)))
      match.group(1)!,
  ];
  expect(outputs, hasLength(2), reason: page);
  return outputs;
}

/// The members of `JobContext`, in the order of its source, the deprecated
/// ones left out: a name kept for one release is not one to teach.
List<String> contextMembers() {
  final body = RegExp(
    r'abstract interface class JobContext \{\n(.*?)\n\}',
    dotAll: true,
  ).firstMatch(read('lib/src/job_context.dart'))!.group(1)!;
  final members = <String>[];
  var deprecated = false;
  for (final line in body.split('\n')) {
    // A declaration stands at two spaces; its parameters and its
    // documentation do not count.
    if (!line.startsWith('  ') || line.startsWith('   ')) {
      continue;
    }
    final code = line.substring(2);
    if (code.startsWith('//')) {
      continue;
    }
    if (code.startsWith('@Deprecated')) {
      deprecated = true;
      continue;
    }
    final name = RegExp(r'get (\w+);').firstMatch(code)?.group(1) ??
        RegExp(r' (\w+)(?:<[^(]*>)?\(')
            .allMatches(code)
            .map((match) => match.group(1)!)
            .where((name) => name != 'Function')
            .firstOrNull;
    if (name == null) {
      // What closes the parameters of a declaration names nothing; any
      // other line that names nothing is a declaration this reading missed,
      // and a member missed here would be missing from the table unseen.
      if (code.startsWith(')') || code.startsWith('}')) {
        continue;
      }
      throw StateError('no member read from "$line"');
    }
    if (!deprecated) {
      members.add(name);
    }
    deprecated = false;
  }
  return members;
}

/// The rows of the table of the context on [page]: the member and its cells.
///
/// A member with two rows throws: in a map the second would hide the first.
Map<String, List<String>> contextTable(String page) {
  final rows = <String, List<String>>{};
  for (final match
      in RegExp(r'^\| `ctx\.(\w+)[^`]*` \|(.*)\|$', multiLine: true)
          .allMatches(read(page))) {
    final member = match.group(1)!;
    if (rows.containsKey(member)) {
      throw StateError('two rows for $member on $page');
    }
    rows[member] = [
      for (final cell in match.group(2)!.split('|')) cell.trim(),
    ];
  }
  return rows;
}

/// What [call] does on a job that has accepted a cancellation: `throws` and
/// the cancellation, or `works`.
String onCancelledJob(FutureOr<Object?> Function(JobContext ctx) call) {
  final heard = <String>[];
  fakeAsync((async) {
    final job = Job<void>((ctx) async {
      try {
        await ctx.join(() => delay(10));
      } on Cancelled {
        try {
          await call(ctx);
          heard.add('works');
        } on Cancelled catch (cancelled) {
          heard.add('throws $cancelled');
        }
      }
    });
    async.elapse(const Duration(milliseconds: 5));
    job.cancel().ignore();
    async.flushTimers();
  });
  return heard.single;
}

/// What happens when the job is cancelled at 10 ms while [body] runs: what
/// [body] says, what it returns, and the [Cancelled] the body throws, each
/// with the time. The job is created [cancellable] or not.
List<String> cancelledWhile(
  Future<Object?> Function(JobContext ctx, void Function(String) say) body, {
  bool cancellable = true,
}) {
  final heard = <String>[];
  fakeAsync((async) {
    void say(String what) =>
        heard.add('$what at ${async.elapsed.inMilliseconds}');
    final job = Job<void>(cancellable: cancellable, (ctx) async {
      try {
        say('returned ${await body(ctx, say)}');
        ctx.check();
      } on Cancelled catch (cancelled) {
        say('threw $cancelled');
        rethrow;
      }
    });
    async.elapse(const Duration(milliseconds: 10));
    say('cancel');
    job.cancel().ignore();
    async.flushTimers();
  });
  return heard;
}

void main() {
  setUp(() {
    Database.events.clear();
    Database.openError = null;
    Database.readError = null;
    Database.stopThrows = false;
    cancelled = false;
  });
  tearDown(() => Job.isCancellationError = null);

  group('the flag "Why" starts from', () {
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

    test('and when the read fails', () {
      Database.readError = StateError('read failed');
      final zone = zoneErrorsOf((async) => unawaited(load()));

      expect(Database.events, ['opened', 'closed']);
      expect(zone, ['Bad state: read failed']);
    });

    test('and returns the same whether cancelled or not', () {
      for (final cancelAt in [null, 10, 50]) {
        Database.events.clear();
        cancelled = false;
        fakeAsync((async) {
          var returned = false;
          load().then((_) => returned = true);
          if (cancelAt != null) {
            async.elapse(Duration(milliseconds: cancelAt));
            cancelled = true;
          }
          async.flushTimers();

          expect(returned, isTrue, reason: 'cancelled at $cancelAt');
          expect(Database.events.last, 'closed');
        });
      }
    });
  });

  test('the Quick start earns every line of it', () {
    // The block runs in `example/quick_start.dart`, which the README names,
    // with a database that prints when it opens and when it closes.
    final printed = <String>[];
    Duration? closedAt;
    fakeAsync((async) {
      runZoned(
        () => unawaited(quick_start.main()),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            printed.add(line);
            if (line == 'database closed') {
              closedAt = async.elapsed;
            }
          },
        ),
      );
      async.flushTimers();
    });

    expect(
      printed,
      isNot(contains(startsWith('read '))),
      reason: 'the value never reached the body: the cancellation came first',
    );
    expect(
      closedAt,
      const Duration(milliseconds: 120),
      reason: 'the body was entered and the database opened; `join` waited '
          'for the read it had already asked for, and the registration '
          'closed the database on the way out',
    );
    for (final page in readmes) {
      expect(
        printed.last,
        quotedAfter(page, 'print(job.outcome);'),
        reason: page,
      );
      expect(printed.join('\n'), quotedOutputs(page).first, reason: page);
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

      // The outcome the README promises for it. This is what the first
      // Quick start used to show, and why the wait in it is not decoration.
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

    // Hearing is not observing: the failure is still nobody's, and it goes
    // where any error nobody answered for goes — to the answer of an
    // observer that answers, or to the zone.
    test('nor does the observer of the job, and one that answers takes it', () {
      for (final observer in [Listening(), Answering()]) {
        final zone = zoneErrorsOf((async) {
          Job<void>(
            observer: observer,
            (ctx) async => throw StateError('read failed'),
          );
        });

        final answering = observer is Answering;
        final kind = answering ? 'answering' : 'listening';
        expect(
          observer.heard,
          [
            'onError: Bad state: read failed',
            if (answering) 'onUnanswered: Bad state: read failed',
          ],
          reason: kind,
        );
        expect(
          zone,
          [if (!answering) 'Bad state: read failed'],
          reason: kind,
        );
      }
    });

    test('accessing done or value, or calling ignoreFailure(), observes it',
        () {
      final ways = <String, void Function(Job<void> job)>{
        'done': (job) => job.done.ignore(),
        'value': (job) => job.value.ignore(),
        'ignoreFailure()': (job) => job.ignoreFailure(),
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
        'an open that fails after the cancellation is answered for: the '
        'observer hears it, and then the zone, unless the observer answers',
        () {
      final heard = {
        null: (zone: ['Bad state: database locked'], heard: null),
        Listening(): (
          zone: ['Bad state: database locked'],
          heard: ['onError: Bad state: database locked'],
        ),
        Answering(): (
          zone: <String>[],
          heard: [
            'onError: Bad state: database locked',
            'onUnanswered: Bad state: database locked',
          ],
        ),
      };
      for (final MapEntry(key: observer, value: expected) in heard.entries) {
        Database.openError = StateError('database locked');
        Outcome<Database>? ended;
        Object? thrown;
        final zone = zoneErrorsOf((async) {
          final job = Job<Database>(observer: observer, (ctx) async {
            try {
              return await ctx.join(
                Database.open,
                discard: (db) => db.close(),
              );
            } catch (error) {
              thrown = error;
              rethrow;
            }
          });
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
          ended = job.outcome;
        });

        // `join` throws the open's own error, not `Cancelled`.
        expect('$thrown', 'Bad state: database locked');
        expect('$ended', 'Cancelled(manual)');
        expect(zone, expected.zone);
        expect(observer?.heard, expected.heard);
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
          ..ignoreFailure();
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

  group('the fuller example', () {
    test('as the README writes it, closes the database', () {
      final printed = printedBy(fullerExample);

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
          // Not the fuller example's own lines, so that the check of the
          // README finds those in `fullerExample` alone.
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

    test(
        'a client that stops by throwing sends the stop to the zone on every '
        'cancellation, unless the app names it', () {
      Database.stopThrows = true;
      for (final named in [false, true]) {
        Job.isCancellationError =
            named ? (error) => error is DatabaseStopped : null;
        final heard = Listening();
        Outcome<Database>? ended;
        final zone = zoneErrorsOf((async) {
          // Not the fuller example's own lines, as above; the steps after the
          // migration are left out, since the cancellation comes during it.
          final job = Job<Database>(observer: heard, (ctx) async {
            final database =
                await ctx.join(Database.open, discard: (db) => db.close());
            final token = CancelToken();
            ctx.onCancel(token.cancel);
            await ctx.join(() => database.migrate(token));
            return database;
          });
          // The database opens in 20 ms, and a step takes 10.
          async.elapse(const Duration(milliseconds: 25));
          job.cancel().ignore();
          async.flushTimers();
          ended = job.outcome;
        });

        expect('$ended', 'Cancelled(manual)');
        expect(
          Database.events,
          ['opened', 'migration stopped', 'closed'],
          reason: 'named: $named',
        );
        expect(
          heard.heard,
          ['onError: DatabaseStopped'],
          reason: 'named: $named',
        );
        expect(zone, named ? isEmpty : ['DatabaseStopped']);
        Database.events.clear();
      }
    });

    test(
        'the fuller example names that filter and the page that takes it apart',
        () {
      for (final page in readmes) {
        final item = RegExp(
          r'- \*\*`ctx\.join\(\(\) => database\.migrate\(stop\)\)`\*\*(.*?)\n- ',
          dotAll: true,
        ).firstMatch(read(page))!.group(1)!;
        expect(item, contains('`Job.isCancellationError`'), reason: page);
        // The anchor is the page's own; `tool/check_links.py` holds it.
        expect(item, contains('errors.md#'), reason: page);
      }
    });

    test('without the section a cancellation comes between the two', () {
      fakeAsync((async) {
        Object? thrown;
        ChildJob<void>? flag;
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

  test('the example prints what the README quotes', () {
    final printed = printedBy(example.main);
    for (final page in readmes) {
      expect(printed.join('\n'), quotedOutputs(page).last, reason: page);
    }

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

  group('the context at a glance', () {
    test('names every member of the context, and nothing else', () {
      for (final page in readmes) {
        expect(
          contextTable(page).keys.toList()..sort(),
          contextMembers()..sort(),
          reason: page,
        );
      }
    });

    test('says which of them throw once the job is cancelled', () {
      final calls = <String, FutureOr<Object?> Function(JobContext ctx)>{
        'check': (ctx) => ctx.check(),
        'join': (ctx) => ctx.join(() => 1),
        'abandonable': (ctx) => ctx.abandonable(() => 1),
        'uncancellable': (ctx) => ctx.uncancellable(() => 1),
        'pause': (ctx) => ctx.pause(),
        'run': (ctx) => ctx.run(Job.deferred<int>((ctx) async => 1)),
        'start': (ctx) => ctx.start(Job.deferred<int>((ctx) async => 1)),
        'runAll': (ctx) => ctx.runAll([Job.deferred<int>((ctx) async => 1)]),
        'each': (ctx) => ctx.each(Stream.value(1), (ctx, event) {}),
        'onCancel': (ctx) => ctx.onCancel(() {}),
        'onDispose': (ctx) => ctx.onDispose(() {}),
        'onDiscard': (ctx) => ctx.onDiscard(() {}),
        'disown': (ctx) => ctx.disown(Object()),
        'unattended': (ctx) => ctx.unattended(() {}),
        'log': (ctx) => ctx.log('message'),
        'job': (ctx) => ctx.job,
        'heldCancellation': (ctx) => ctx.heldCancellation,
      };
      const said = {
        'Throws `Cancelled`': 'throws Cancelled(manual)',
        'Works as usual': 'works',
        'Бросает `Cancelled`': 'throws Cancelled(manual)',
        'Работает как обычно': 'works',
      };
      expect(calls.keys.toList()..sort(), contextMembers()..sort());
      for (final page in readmes) {
        for (final MapEntry(key: member, value: cells)
            in contextTable(page).entries) {
          expect(
            onCancelledJob(calls[member]!),
            said[cells[1]],
            reason: '$member on $page',
          );
        }
      }
    });

    // What a cancellation that comes while a member runs does to it, and
    // for one member what it does. The cell is read here next to the run
    // that holds it: a cell rewritten turns this red until the run says the
    // same. The translation says it in words of its own, and its cell is
    // held to them.
    const translated = {
      'Waits, then throws': 'Ждёт, потом бросает',
      'Throws at once': 'Бросает сразу',
      'Holds it until the step ends': 'Держит её до конца шага',
      'Ends and throws': 'Прерывается и бросает',
      'Passes it on, waits, throws': 'Передаёт её, ждёт, бросает',
      'Passes it on': 'Передаёт её',
      'Not cancelled': 'Не отменяется',
    };
    String cell(String member, {int column = 2}) {
      final original = contextTable('README.md')[member]![column];
      if (readmes.contains('README.ru.md')) {
        expect(
          contextTable('README.ru.md')[member]![column],
          translated[original],
          reason: '$member in the translation',
        );
      }
      return original;
    }

    test('join waits for the action to end, then throws', () {
      expect(cell('join'), 'Waits, then throws');
      expect(
        cancelledWhile(
          (ctx, say) => ctx.join<void>(() async {
            await delay(100);
            say('action ended');
          }),
        ),
        [
          'cancel at 10',
          'action ended at 100',
          'threw Cancelled(manual) at 100',
        ],
      );
    });

    test('abandonable throws at once, and the action runs on', () {
      expect(cell('abandonable'), 'Throws at once');
      expect(
        cancelledWhile(
          (ctx, say) => ctx.abandonable<void>(() async {
            await delay(100);
            say('action ended');
          }),
        ),
        [
          'cancel at 10',
          'threw Cancelled(manual) at 10',
          'action ended at 100',
        ],
      );
    });

    test('uncancellable holds it until the step ends', () {
      expect(cell('uncancellable'), 'Holds it until the step ends');
      expect(
        cancelledWhile(
          (ctx, say) => ctx.uncancellable(() async {
            await delay(100);
            say('step ended');
            return 'the step';
          }),
        ),
        [
          'cancel at 10',
          'step ended at 100',
          'returned the step at 100',
          'threw Cancelled(manual) at 100',
        ],
      );
    });

    test('pause ends and throws', () {
      expect(cell('pause'), 'Ends and throws');
      expect(
        cancelledWhile(
          (ctx, say) => ctx.pause(const Duration(milliseconds: 100)),
        ),
        ['cancel at 10', 'threw Cancelled(manual) at 10'],
      );
    });

    test('run passes the cancellation to the child and waits for it', () {
      expect(cell('run'), 'Passes it on, waits, throws');
      expect(
        cancelledWhile((ctx, say) {
          final child = Job.deferred<int>((ctx) async {
            await ctx.join(() => delay(100));
            return 1;
          });
          unawaited(child.done.then((outcome) => say('child $outcome')));
          return ctx.run(child);
        }),
        [
          'cancel at 10',
          'child Cancelled(parent) at 100',
          'threw Cancelled(parent) at 100',
        ],
      );
    });

    test('runAll passes it to the children and waits for them', () {
      expect(cell('runAll'), 'Passes it on, waits, throws');
      expect(
        cancelledWhile((ctx, say) {
          ChildJob<int> child(String name, int ms) {
            final child = Job.deferred<int>((ctx) async {
              await ctx.join(() => delay(ms));
              return ms;
            });
            unawaited(child.done.then((outcome) => say('$name $outcome')));
            return child;
          }

          return ctx.runAll([child('a', 100), child('b', 50)]);
        }),
        [
          'cancel at 10',
          'b Cancelled(parent) at 50',
          'a Cancelled(parent) at 100',
          'threw Cancelled(parent) at 100',
        ],
      );
    });

    test('each passes it to the child', () {
      expect(cell('each'), 'Passes it on');
      expect(
        cancelledWhile((ctx, say) async {
          final child = ctx.each(StreamController<int>().stream, (ctx, _) {});
          unawaited(child.done.then((outcome) => say('child $outcome')));
          await ctx.pause(const Duration(milliseconds: 100));
          return null;
        }),
        [
          'cancel at 10',
          'threw Cancelled(manual) at 10',
          'child Cancelled(parent) at 10',
        ],
      );
    });

    test('start passes it to the child', () {
      expect(cell('start'), 'Passes it on');
      expect(
        cancelledWhile((ctx, say) async {
          final child = Job.deferred<void>(
            (ctx) => ctx.pause(const Duration(milliseconds: 100)),
          );
          ctx.start(child);
          unawaited(child.done.then((outcome) => say('child $outcome')));
          await ctx.pause(const Duration(milliseconds: 100));
          return null;
        }),
        [
          'cancel at 10',
          'threw Cancelled(manual) at 10',
          'child Cancelled(parent) at 10',
        ],
      );
    });

    test('unattended work is not cancelled', () {
      expect(cell('unattended'), 'Not cancelled');
      expect(
        cancelledWhile((ctx, say) async {
          ctx.unattended(() async {
            await delay(100);
            say('work ended');
          });
          await ctx.pause(const Duration(milliseconds: 100));
          return null;
        }),
        [
          'cancel at 10',
          'threw Cancelled(manual) at 10',
          'work ended at 100',
        ],
      );
    });

    test('the notes say what the cells of check and each leave out', () {
      // The cells name the member; the line under the table says the rest.
      final said = {
        'README.md': [
          '`ctx.check()` is the checkpoint for a place where there is no call '
              'to wrap.',
          '`ctx.each` hands the events of the stream to its callback one at a '
              'time.',
        ],
        'README.ru.md': [
          '`ctx.check()` — контрольная точка для места, где нечего обернуть.',
          '`ctx.each` отдаёт события стрима колбэку по одному.',
        ],
      };
      for (final page in readmes) {
        final text = read(page).replaceAll(RegExp(r'\s+'), ' ');
        for (final line in said[page]!) {
          expect(text, contains(line), reason: page);
        }
      }
    });

    test('the errors of unattended work go to onError, then to the answer', () {
      // Said under the table, in a line of its own on each page.
      final said = {
        'README.md': 'The errors of the work of `ctx.unattended` go to '
            '`onError`, then are answered for.',
        'README.ru.md':
            'Ошибки работы `ctx.unattended` идут в `onError`, затем к ответу.',
      };
      for (final page in readmes) {
        expect(
          read(page).replaceAll(RegExp(r'\s+'), ' '),
          contains(said[page]),
          reason: page,
        );
      }
      // Who hears the error: the observer, if there is one, and the zone or
      // the answerer, the same as for an error of cleanup.
      List<String> heardOf(
        Listening? observer,
        void Function(JobContext ctx) fail,
      ) {
        final zone = zoneErrorsOf(
          (async) => Job<void>(observer: observer, (ctx) async => fail(ctx)),
        );
        return [...?observer?.heard, for (final error in zone) 'zone: $error'];
      }

      final ways = <Listening? Function(), List<String>>{
        () => null: ['zone: Bad state: lost'],
        Listening.new: ['onError: Bad state: lost', 'zone: Bad state: lost'],
        Answering.new: [
          'onError: Bad state: lost',
          'onUnanswered: Bad state: lost',
        ],
      };
      for (final MapEntry(key: observer, value: way) in ways.entries) {
        expect(
          heardOf(
            observer(),
            (ctx) => ctx.unattended(() => throw StateError('lost')),
          ),
          way,
        );
        expect(
          heardOf(
            observer(),
            (ctx) => ctx.onDispose(() => throw StateError('lost')),
          ),
          way,
        );
      }
    });

    test('in a section and in a job that refuses, the members go on', () {
      Future<Object?> members(JobContext ctx, void Function(String) say) async {
        await ctx.join(() => delay(20));
        say('join returned');
        await ctx.abandonable(() => delay(20));
        say('abandonable returned');
        await ctx.pause(const Duration(milliseconds: 20));
        say('pause ended');
        final value = await ctx.run(
          Job.deferred<int>((ctx) async {
            await ctx.join(() => delay(20));
            return 1;
          }),
        );
        say('run returned $value');
        return 'the step';
      }

      const ran = [
        'cancel at 10',
        'join returned at 20',
        'abandonable returned at 40',
        'pause ended at 60',
        'run returned 1 at 80',
        'returned the step at 80',
      ];
      expect(
        cancelledWhile(
          (ctx, say) => ctx.uncancellable(() => members(ctx, say)),
        ),
        [...ran, 'threw Cancelled(manual) at 80'],
      );
      expect(cancelledWhile(members, cancellable: false), ran);
    });

    test('the members that do not run on leave the cell empty', () {
      for (final page in readmes) {
        expect(
          [
            for (final MapEntry(key: member, value: cells)
                in contextTable(page).entries)
              if (cells[2].isEmpty) member,
          ],
          [
            'check',
            'onCancel',
            'onDispose',
            'onDiscard',
            'disown',
            'log',
            'job',
            'heldCancellation',
          ],
          reason: page,
        );
      }
    });
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
      codeMissingFrom(
        'README.md',
        'test/readme_recipe_test.dart',
        alsoIn: ['example/quick_start.dart'],
      ),
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

    // The Quick start is the first block, and its copy is the program of
    // `example/quick_start.dart`.
    const marks = r'// README: begin\n(.*?)\n\s*// README: end';
    expect(
      [
        ...blocks(marks, 'example/quick_start.dart'),
        ...blocks(marks, 'test/readme_recipe_test.dart'),
      ],
      blocks(r'```dart\n(.*?)\n```', 'README.md'),
    );
  });

  test('the example runs the job of the fuller example as the README writes it',
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
