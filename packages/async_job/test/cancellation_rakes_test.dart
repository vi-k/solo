@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

/// The first attempts of `doc/cancellation.md`, and what each one costs.
///
/// Every section of the page opens with the version the names lead to and
/// shows what that version prints. The page has no bench, so the code is
/// repeated here as it stands there, and the last test holds the lines the
/// page quotes to the lines these tests print: a quote that drifts from its
/// code turns this file red, not only a broken engine.

/// What each `text` block of the page says, in the order of the page.
const quoted = [
  [
    'step 1',
    'cancel',
    'database closed',
    'outcome: Cancelled(manual)',
    'step 2 on a closed database',
    'step 3 on a closed database',
  ],
  [
    'step 1',
    'cancel',
    'step 2',
    'step 3',
    'database closed',
    'outcome: Cancelled(manual)',
  ],
  [
    'step 1',
    'cancel',
    'step 2',
    'migration stopped',
    'onError: DatabaseStopped',
    'database closed',
    'outcome: Cancelled(manual)',
  ],
  [
    'cancel',
    'version written',
    'marking stopped',
    'onError: DatabaseStopped',
    'outcome: Cancelled(manual)',
  ],
  [
    'cancel',
    'version written',
    'ready flag written',
    'outcome: Cancelled(manual)',
  ],
  [
    'step 1',
    'cancel',
    'step 2',
    'migration stopped',
    'log: migration failed: DatabaseStopped',
    'outcome: Cancelled(manual)',
  ],
  [
    'step 1',
    'cancel',
    'step 2',
    'migration stopped',
    'outcome: Cancelled(manual)',
  ],
  [
    'outcome: Done(null)',
    'zone: Bad state: analytics offline',
  ],
  [
    'outcome: Done(null)',
    'onError: Bad state: analytics offline',
  ],
];

/// What the database, the observer and the code around the job print.
final printed = <String>[];

void say(String line) => printed.add(line);

/// The stop signal of the database client, the kind `onCancel` is for.
final class CancelToken {
  bool cancelled = false;

  void cancel() => cancelled = true;
}

/// How the database client stops when its token is cancelled.
final class DatabaseStopped implements Exception {
  const DatabaseStopped();

  @override
  String toString() => 'DatabaseStopped';
}

final class Database {
  bool closed = false;

  static Future<Database> open() async => Database();

  /// Three steps, 10 ms each; the token is read before every one.
  Future<void> migrate(CancelToken stop) async {
    for (var step = 1; step <= 3; step++) {
      if (stop.cancelled) {
        say('migration stopped');
        throw const DatabaseStopped();
      }
      await delay(10);
      say(closed ? 'step $step on a closed database' : 'step $step');
    }
  }

  /// Two writes, 10 ms each; the token is read between them.
  Future<void> markReady(CancelToken stop) async {
    await delay(10);
    say('version written');
    if (stop.cancelled) {
      say('marking stopped');
      throw const DatabaseStopped();
    }
    await delay(10);
    say('ready flag written');
  }

  Future<void> close() async {
    closed = true;
    say('database closed');
  }
}

final class Analytics {
  Future<void> send(String event) async {
    await delay(10);
    throw StateError('analytics offline');
  }
}

final class Device {
  Future<void> stop() async {
    await delay(10);
    throw StateError('device did not stop');
  }
}

/// The observer of the page's jobs: it prints what reaches it.
final class PrintingObserver extends JobObserver {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      say('onError: $error');

  @override
  void onLog(Job<Object?> job, Object? message) => say('log: $message');
}

/// The database of the sections that do not open one.
Database database = Database();
final analytics = Analytics();
final device = Device();

/// Runs [body] as a job with the page's observer, cancels it [cancelAt] ms
/// in, and returns what was printed. An error that reaches the zone is
/// printed as `zone:`.
List<String> play<T>(
  Future<T> Function(JobContext ctx) body, {
  int? cancelAt,
  JobObserver? observer,
  bool observed = true,
}) {
  printed.clear();
  database = Database();
  runZonedGuarded(
    () => fakeAsync((async) {
      final job = Job<T>(
        body,
        observer: observed ? observer ?? PrintingObserver() : null,
      );
      unawaited(job.done.then((outcome) => say('outcome: $outcome')));
      if (cancelAt != null) {
        async.elapse(Duration(milliseconds: cancelAt));
        say('cancel');
        unawaited(job.cancel());
      }
      async.flushTimers();
    }),
    (error, stackTrace) => say('zone: $error'),
  );
  return printed.toList();
}

void main() {
  group('Stopping the operation', () {
    test('wait closes the database under a running migration', () {
      final lines = play(
        (ctx) async {
          final database = await ctx.join(
            Database.open,
            discard: (database) => database.close(),
          );
          final stop = CancelToken();

          await ctx.wait(() => database.migrate(stop));

          return database;
        },
        cancelAt: 15,
      );

      expect(lines, quoted[0]);
    });

    test('join closes it after the migration has run to its end', () {
      final lines = play(
        (ctx) async {
          final database = await ctx.join(
            Database.open,
            discard: (database) => database.close(),
          );
          final stop = CancelToken();

          await ctx.join(() => database.migrate(stop));

          return database;
        },
        cancelAt: 15,
      );

      expect(lines, quoted[1]);
    });

    test('a token through onCancel stops it, and join waits for that', () {
      final lines = play(
        (ctx) async {
          final database = await ctx.join(
            Database.open,
            discard: (database) => database.close(),
          );
          final stop = CancelToken();
          ctx.onCancel(stop.cancel);

          await ctx.join(() => database.migrate(stop));

          return database;
        },
        cancelAt: 15,
      );

      expect(lines, quoted[2]);
    });

    test('without an observer the stopped migration reaches no zone', () {
      final lines = play(
        (ctx) async {
          final stop = CancelToken();
          ctx.onCancel(stop.cancel);

          await ctx.join(() => database.migrate(stop));
        },
        cancelAt: 15,
        observed: false,
      );

      expect(lines, [
        'step 1',
        'cancel',
        'step 2',
        'migration stopped',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('onCancel runs inside cancel(), before the body goes on', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<void>((ctx) async {
          ctx.onCancel(() => seen.add('onCancel'));
          await ctx.join(() => delay(20));
          seen.add('body');
        });
        async.elapse(const Duration(milliseconds: 5));
        unawaited(job.cancel());
        seen.add('cancel() called');
        async.flushTimers();

        expect(seen, ['onCancel', 'cancel() called']);
      });
    });

    test('a late value of wait joins the stack while the job finishes', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<void>((ctx) async {
          ctx.onDispose(() async {
            await delay(30);
            seen.add('${async.elapsed.inMilliseconds} ms: slow disposer');
          });
          await ctx.wait(
            () async {
              await delay(20);
              return 'connection';
            },
            discard: (value) =>
                seen.add('${async.elapsed.inMilliseconds} ms: discard $value'),
          );
        });
        unawaited(
          job.done.then(
            (outcome) => seen
                .add('${async.elapsed.inMilliseconds} ms: finished $outcome'),
          ),
        );
        async.elapse(const Duration(milliseconds: 5));
        unawaited(job.cancel());
        async.flushTimers();

        expect(seen, [
          '35 ms: slow disposer',
          '35 ms: discard connection',
          '35 ms: finished Cancelled(manual)',
        ]);
      });
    });

    test('a late value of wait runs alone once the job has finished', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<void>((ctx) async {
          await ctx.wait(
            () async {
              await delay(20);
              return 'connection';
            },
            discard: (value) =>
                seen.add('${async.elapsed.inMilliseconds} ms: discard $value'),
          );
        });
        unawaited(
          job.done.then(
            (outcome) => seen
                .add('${async.elapsed.inMilliseconds} ms: finished $outcome'),
          ),
        );
        async.elapse(const Duration(milliseconds: 5));
        unawaited(job.cancel());
        async.flushTimers();

        expect(seen, [
          '5 ms: finished Cancelled(manual)',
          '20 ms: discard connection',
        ]);
      });
    });

    test('join awaits the cleanup of its value before it throws', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<void>((ctx) async {
          try {
            await ctx.join(
              () async {
                await delay(20);
                return 'connection';
              },
              dispose: (value) async {
                await delay(5);
                seen.add('${async.elapsed.inMilliseconds} ms: dispose $value');
              },
            );
          } on Cancelled {
            seen.add('${async.elapsed.inMilliseconds} ms: join threw');
            rethrow;
          }
        });
        async.elapse(const Duration(milliseconds: 5));
        unawaited(job.cancel());
        async.flushTimers();

        expect(seen, ['25 ms: dispose connection', '25 ms: join threw']);
      });
    });
  });

  group('A step that must finish', () {
    test('join lets the token stop the step halfway', () {
      final lines = play(
        (ctx) async {
          final stop = CancelToken();
          ctx.onCancel(stop.cancel);

          await ctx.join(() => database.markReady(stop));
        },
        cancelAt: 5,
      );

      expect(lines, quoted[3]);
    });

    test('uncancellable holds the cancellation until the step is over', () {
      final lines = play(
        (ctx) async {
          final stop = CancelToken();
          ctx.onCancel(stop.cancel);

          await ctx.uncancellable(() => database.markReady(stop));
        },
        cancelAt: 5,
      );

      expect(lines, quoted[4]);
    });

    test('a held cancellation reaches no child until the section ends', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<void>((ctx) async {
          final child = Job.deferred<void>((ctx) async {
            ctx.onCancel(
              () => seen.add('${async.elapsed.inMilliseconds} ms: child'),
            );
            await ctx.wait(() => delay(100));
          });
          final running = ctx.run(child);
          await ctx.uncancellable(() => delay(20));
          seen.add('${async.elapsed.inMilliseconds} ms: after the section');
          await running;
        });
        async.elapse(const Duration(milliseconds: 5));
        unawaited(job.cancel());
        async.flushTimers();

        expect(seen, ['20 ms: child', '20 ms: after the section']);
        expect(job.outcome, isA<Cancelled>());
      });
    });

    test('the body after the section runs up to the next checkpoint', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<int>((ctx) async {
          await ctx.uncancellable(() => delay(20));
          seen.add('after the section');
          ctx.check();
          seen.add('after check');
          return 42;
        });
        async.elapse(const Duration(milliseconds: 5));
        unawaited(job.cancel());
        async.flushTimers();

        expect(seen, ['after the section']);
        expect(job.outcome, isA<Cancelled>());
      });
    });

    test('an unawaited section loses the cancellation to a Done', () {
      fakeAsync((async) {
        final job = Job<void>((ctx) async {
          unawaited(ctx.uncancellable(() => delay(20)));
          await ctx.wait(() => delay(2));
        });
        async.elapse(const Duration(milliseconds: 1));
        var returned = false;
        unawaited(job.cancel().then((_) => returned = true));
        async.elapse(const Duration(milliseconds: 1));

        expect(returned, isTrue);
        expect(job.outcome, isA<Done<void>>());
        async.flushTimers();
      });
    });

    test('cancellable: false refuses a started job, not a created one', () {
      fakeAsync((async) {
        final started = Job<int>(
          (ctx) async {
            await ctx.join(() => delay(20));
            ctx.check();
            return 42;
          },
          cancellable: false,
        );
        final created = Job<int>((ctx) async => 42, cancellable: false);
        unawaited(created.cancel());
        async.elapse(const Duration(milliseconds: 5));
        unawaited(started.cancel());
        async.flushTimers();

        expect(started.outcome, isA<Done<int>>());
        expect(
          created.outcome,
          isA<Cancelled>().having((c) => c.started, 'started', isFalse),
        );
      });
    });
  });

  group('Catching errors of the operation', () {
    test('a clause for Cancelled logs the stopped migration as a failure', () {
      final lines = play(
        (ctx) async {
          final stop = CancelToken();
          ctx.onCancel(stop.cancel);

          try {
            await ctx.join(() => database.migrate(stop));
          } on Cancelled {
            rethrow;
          } on Exception catch (error) {
            ctx.log('migration failed: $error');
          }
          await ctx.uncancellable(() => database.markReady(stop));
        },
        cancelAt: 15,
      );

      expect(lines, quoted[5]);
    });

    test('without the token the clause for Cancelled holds', () {
      final lines = play(
        (ctx) async {
          final stop = CancelToken();

          try {
            await ctx.join(() => database.migrate(stop));
          } on Cancelled {
            rethrow;
          } on Exception catch (error) {
            ctx.log('migration failed: $error');
          }
          await ctx.uncancellable(() => database.markReady(stop));
        },
        cancelAt: 15,
      );

      expect(lines, [
        'step 1',
        'cancel',
        'step 2',
        'step 3',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('on Exception alone takes the Cancelled of join', () {
      final lines = play(
        (ctx) async {
          final stop = CancelToken();

          try {
            await ctx.join(() => database.migrate(stop));
          } on Exception catch (error) {
            ctx.log('migration failed: $error');
          }
        },
        cancelAt: 15,
      );

      expect(lines, contains('log: migration failed: Cancelled(manual)'));
    });

    test('check in the catch lets the cancellation through', () {
      final lines = play(
        (ctx) async {
          final stop = CancelToken();
          ctx.onCancel(stop.cancel);

          try {
            await ctx.join(() => database.migrate(stop));
          } on Exception catch (error) {
            ctx.check();
            // ignore: cascade_invocations -- the page's code as it stands
            ctx.log('migration failed: $error');
          }
          await ctx.uncancellable(() => database.markReady(stop));
        },
        cancelAt: 15,
      );

      expect(lines, quoted[6]);
    });

    test('check in an on Object catch does the same', () {
      final lines = play(
        (ctx) async {
          final stop = CancelToken();
          ctx.onCancel(stop.cancel);

          try {
            await ctx.join(() => database.migrate(stop));
          } on Object catch (error) {
            ctx.check();
            // ignore: cascade_invocations -- the page's code as it stands
            ctx.log('migration failed: $error');
          }
        },
        cancelAt: 15,
      );

      expect(lines, quoted[6]);
    });

    test('a failure of its own is logged, and the body goes on', () {
      final lines = play((ctx) async {
        final stop = CancelToken();
        ctx.onCancel(stop.cancel);

        try {
          await ctx.join(() => throw const FormatException('bad schema'));
        } on Exception catch (error) {
          ctx.check();
          // ignore: cascade_invocations -- the page's code as it stands
          ctx.log('migration failed: $error');
        }
        await ctx.uncancellable(() => database.markReady(stop));
      });

      expect(lines, [
        'log: migration failed: FormatException: bad schema',
        'version written',
        'ready flag written',
        'outcome: Done(null)',
      ]);
    });

    test('a caught Cancelled of the job does not undo it', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<int>((ctx) async {
          try {
            await ctx.join(() => delay(20));
          } on Cancelled {
            seen.add('caught');
          }
          seen.add('after the catch');
          return 42;
        });
        async.elapse(const Duration(milliseconds: 5));
        unawaited(job.cancel());
        async.flushTimers();

        expect(seen, ['caught', 'after the catch']);
        expect(job.outcome, isA<Cancelled>());
      });
    });

    for (final (form, outcome) in [
      ('rethrow', 'Cancelled(handler: child null: Cancelled(manual))'),
      ('check', 'Done(page without a thumbnail)'),
    ]) {
      test('an optional child cancelled on its own, with $form', () {
        fakeAsync((async) {
          final page = Job<String>((ctx) async {
            final thumbnail = Job.deferred<String>((ctx) async {
              await ctx.wait(() => delay(20));
              return 'thumbnail';
            });
            Timer(const Duration(milliseconds: 5), thumbnail.cancel);
            try {
              return 'page with ${await ctx.run(thumbnail)}';
            } on Cancelled {
              if (form == 'rethrow') rethrow;
              ctx.check();
              return 'page without a thumbnail';
            }
          });
          async.flushTimers();

          expect('${page.outcome}', outcome);
        });
      });
    }
  });

  group('Work the job does not wait for', () {
    test('unawaited sends the failure past the observer to the zone', () {
      final lines = play((ctx) async {
        unawaited(analytics.send('migrated'));
      });

      expect(lines, quoted[7]);
    });

    test('unattended hands it to the observer, after the job is over', () {
      final lines = play((ctx) async {
        ctx.unattended(() => analytics.send('migrated'));
      });

      expect(lines, quoted[8]);
    });

    test('without an observer unattended goes to the creation zone', () {
      final lines = play(
        (ctx) async {
          ctx.unattended(() => analytics.send('migrated'));
        },
        observed: false,
      );

      expect(lines, quoted[7]);
    });

    test('an async onCancel callback fails into the zone', () {
      final lines = play(
        (ctx) async {
          ctx.onCancel(() async {
            await device.stop();
          });
          await ctx.wait(() => delay(50));
        },
        cancelAt: 5,
      );

      expect(lines, [
        'cancel',
        'outcome: Cancelled(manual)',
        'zone: Bad state: device did not stop',
      ]);
    });

    test('a synchronous throw of onCancel reaches onError', () {
      final lines = play(
        (ctx) async {
          ctx.onCancel(() => throw StateError('device did not stop'));
          await ctx.wait(() => delay(50));
        },
        cancelAt: 5,
      );

      expect(lines, [
        'cancel',
        'onError: Bad state: device did not stop',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('an asynchronous stop through unattended reaches onError', () {
      final lines = play(
        (ctx) async {
          ctx.onCancel(() => ctx.unattended(device.stop));
          await ctx.wait(() => delay(50));
        },
        cancelAt: 5,
      );

      expect(lines, [
        'cancel',
        'outcome: Cancelled(manual)',
        'onError: Bad state: device did not stop',
      ]);
    });

    test('a future made outside never comes back in there', () {
      final lines = play((ctx) async {
        final sending = analytics.send('migrated');
        ctx.unattended(() async {
          try {
            await sending;
          } on Object catch (error) {
            say('caught: $error');
          }
        });
      });

      expect(lines, [
        'outcome: Done(null)',
        'zone: Bad state: analytics offline',
      ]);
    });

    test('a future made in there hangs the job that awaits it', () {
      final lines = play((ctx) async {
        late Future<void> sending;
        ctx.unattended(() {
          sending = analytics.send('migrated');
        });
        try {
          await ctx.wait(() => sending);
        } on Object catch (error) {
          say('caught: $error');
        }
      });

      expect(lines, ['onError: Bad state: analytics offline']);
    });
  });

  test('after the cancellation, the waiting members throw and the rest work',
      () {
    fakeAsync((async) {
      final seen = <String>[];
      final job = Job<void>((ctx) async {
        try {
          await ctx.wait(() => delay(50));
        } on Cancelled {
          Future<void> probe(
            String name,
            FutureOr<Object?> Function() call,
          ) async {
            try {
              await call();
              seen.add('$name works');
            } on Cancelled {
              seen.add('$name throws');
            }
          }

          await probe('check', ctx.check);
          await probe('wait', () => ctx.wait(() => 1));
          await probe('join', () => ctx.join(() => 1));
          await probe('uncancellable', () => ctx.uncancellable(() => 1));
          await probe('run', () => ctx.run(Job.deferred((ctx) async => 1)));
          await probe(
            'each',
            () => ctx.each<int>(const Stream.empty(), (ctx, _) async {}),
          );
          await probe('onCancel', () => ctx.onCancel(() {}));
          await probe('onDispose', () => ctx.onDispose(() {}));
          await probe('onDiscard', () => ctx.onDiscard(() {}));
          await probe('disown', () => ctx.disown(Object()));
          await probe('unattended', () => ctx.unattended(() {}));
          rethrow;
        }
      });
      async.elapse(const Duration(milliseconds: 5));
      unawaited(job.cancel());
      async.flushTimers();

      expect(seen, [
        'check throws',
        'wait throws',
        'join throws',
        'uncancellable throws',
        'run throws',
        'each throws',
        'onCancel throws',
        'onDispose works',
        'onDiscard works',
        'disown works',
        'unattended works',
      ]);
    });
  });

  test('the page quotes what these tests print', () {
    final page = File('doc/cancellation.md').readAsStringSync();
    final blocks = RegExp(r'```text\n(.*?)\n```', dotAll: true)
        .allMatches(page)
        .map((match) => match.group(1)!.split('\n'))
        .toList();

    expect(blocks, quoted);
  });
}
