@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/cancellation_page.dart' as page;
import 'support/cancellation_stubs.dart';
import 'support/delay.dart';
import 'support/page_code.dart';

/// The first attempts of `doc/cancellation.md`, and what each one costs.
///
/// Every section of the page opens with the version habit or the names of
/// the API lead to and
/// shows what that version prints. The page has no bench: its code stands
/// verbatim in `support/cancellation_page.dart`, each block in a region of
/// its own, and the tests below run it; the variants next to them hold what
/// the code of the page does not show. The tests at the end hold the page to
/// these files: the lines it quotes to the lines its code prints, every
/// block of its code to the region in its place, the durations its prose
/// names to the stubs, and every block to a fence these checks read.

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
    'outcome: Cancelled(manual)',
  ],
  [
    'cancel',
    'version written',
    'ready flag written',
    'outcome: Cancelled(manual)',
  ],
  [
    'cancel',
    'version written',
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
    'step 1',
    'step 2',
    'migration stopped',
    'onError: DatabaseStopped',
    'database closed',
    'outcome: Cancelled(manual)',
  ],
  [
    'step 1',
    'step 2',
    'migration stopped',
    'onError: DatabaseStopped',
    'database closed',
    'outcome: Cancelled(timeout)',
  ],
  [
    'outcome: Done(page without a thumbnail)',
  ],
];

/// When the user cancels in the sections on the migration: the page's
/// "15 ms in".
const cancelMs = 15;

/// When the user cancels in "Letting time pass": the page's "500 ms in",
/// halfway through the second between two reads.
const pauseCancelMs = 500;

/// Runs the job [start] makes, cancels it [pauseCancelMs] in, and returns
/// how many ms after the cancellation the job ended and for how many more
/// a timer of it was still pending.
({int endedAfter, int timerLeftFor}) waiting(Job<Object?> Function() start) {
  freshRun();
  late final int endedAfter;
  late final int timerLeftFor;
  fakeAsync((async) {
    Duration? ended;
    final job = start()..ignore();
    unawaited(job.done.then((_) => ended = async.elapsed));
    async.elapse(const Duration(milliseconds: pauseCancelMs));
    unawaited(job.cancel());
    async.flushMicrotasks();
    while (ended == null) {
      async.elapse(const Duration(milliseconds: 1));
    }
    endedAfter = ended!.inMilliseconds - pauseCancelMs;
    final finishedAt = async.elapsed;
    while (async.pendingTimers.isNotEmpty) {
      async.elapse(const Duration(milliseconds: 1));
    }
    timerLeftFor = (async.elapsed - finishedAt).inMilliseconds;
  });
  return (endedAfter: endedAfter, timerLeftFor: timerLeftFor);
}

/// Runs the job [start] makes on a migration that fails before its first
/// step, and returns for how many ms after the end of the job a timer was
/// still pending, and what reached the zone.
({int timerLeftFor, List<String> zone}) failingUnderALimit(
  Job<Object?> Function() start,
) {
  freshRun();
  stage.migrationFails = true;
  var timerLeftFor = -1;
  final zone = <String>[];
  runZonedGuarded(
    () => fakeAsync((async) {
      final job = start();
      async.flushMicrotasks();
      while (!job.isFinished) {
        async.elapse(const Duration(milliseconds: 1));
      }
      final finishedAt = async.elapsed;
      while (async.pendingTimers.isNotEmpty) {
        async.elapse(const Duration(milliseconds: 1));
      }
      timerLeftFor = (async.elapsed - finishedAt).inMilliseconds;
    }),
    (error, stackTrace) => zone.add('$error'),
  );
  return (timerLeftFor: timerLeftFor, zone: zone);
}

/// Starts a run on fresh stubs; the stage stays as the test has set it.
void freshRun() {
  printed.clear();
  database = Database();
  device = Device();
}

/// Runs [body] as a job with the page's observer, cancels it [cancelAt] ms
/// in, and returns what was printed. An error that reaches the zone is
/// printed as `zone:`.
List<String> play<T>(
  Future<T> Function(JobContext ctx) body, {
  int? cancelAt,
  bool observed = true,
}) =>
    watch(
      () => Job<T>(body, observer: observed ? printing : null),
      cancelAt: cancelAt,
    );

/// Runs the job [start] makes, cancels it [cancelAt] ms in, and returns what
/// was printed. An error that reaches the zone is printed as `zone:`.
List<String> watch(Job<Object?> Function() start, {int? cancelAt}) {
  freshRun();
  runZonedGuarded(
    () => fakeAsync((async) {
      final job = start();
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
  setUp(() {
    stage = Stage();
    freshRun();
  });

  group('The opening example', () {
    test('uncancelled, it runs to its end', () {
      expect(watch(page.opening), [
        'rows read',
        'step 1',
        'step 2',
        'step 3',
        'version written',
        'ready flag written',
        'rows used',
        'outcome: Done(null)',
      ]);
    });

    test('the wait ends at once, and the read goes on', () {
      expect(watch(page.opening, cancelAt: 5), [
        'cancel',
        'outcome: Cancelled(manual)',
        'rows read',
      ]);
    });

    test('the join waits for the migration to stop at the token', () {
      expect(watch(page.opening, cancelAt: 15), [
        'rows read',
        'cancel',
        'step 1',
        'migration stopped',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('the section writes both, and check throws after it', () {
      expect(watch(page.opening, cancelAt: 45), [
        'rows read',
        'step 1',
        'step 2',
        'step 3',
        'cancel',
        'version written',
        'ready flag written',
        'outcome: Cancelled(manual)',
      ]);
    });
  });

  group('Stopping the operation', () {
    test('abandonable closes the database under a running migration', () {
      expect(watch(page.waitForTheMigration, cancelAt: cancelMs), quoted[0]);
    });

    test('join closes it after the migration has run to its end', () {
      expect(watch(page.joinTheMigration, cancelAt: cancelMs), quoted[1]);
    });

    test('a token through onCancel stops it, and join waits for that', () {
      expect(watch(page.stopTheMigration, cancelAt: cancelMs), quoted[2]);
    });

    test('without an observer the stopped migration reaches no zone', () {
      final lines = play(
        (ctx) async {
          final stop = CancelToken();
          ctx.onCancel(stop.cancel);

          await ctx.join(() => database.migrate(stop));
        },
        cancelAt: cancelMs,
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

    // The page names both parameters, so each test runs with either one.
    for (final kind in ['dispose', 'discard']) {
      test(
          'a late value of abandonable is released at once while the body '
          'still runs ($kind)', () {
        fakeAsync((async) {
          final seen = <String>[];
          String at() => '${async.elapsed.inMilliseconds} ms';
          void cleanup(String value) => seen.add('${at()}: $kind $value');
          final job = Job<void>((ctx) async {
            try {
              await ctx.abandonable(
                () async {
                  await delay(20);
                  return 'connection';
                },
                dispose: kind == 'dispose' ? cleanup : null,
                discard: kind == 'discard' ? cleanup : null,
              );
            } on Cancelled {
              await delay(40);
              seen.add('${at()}: the body ends');
              rethrow;
            }
          });
          unawaited(
            job.done.then((outcome) => seen.add('${at()}: finished $outcome')),
          );
          async.elapse(const Duration(milliseconds: 5));
          unawaited(job.cancel());
          async.flushTimers();

          expect(seen, [
            '20 ms: $kind connection',
            '45 ms: the body ends',
            '45 ms: finished Cancelled(manual)',
          ]);
        });
      });

      test(
          'a late value of abandonable is released at once while a child still '
          'runs, and the job waits for it ($kind)', () {
        fakeAsync((async) {
          final seen = <String>[];
          String at() => '${async.elapsed.inMilliseconds} ms';
          Future<void> cleanup(String value) async {
            seen.add('${at()}: $kind $value');
            await delay(40);
            seen.add('${at()}: $kind done');
          }

          final job = Job<void>((ctx) async {
            final child = Job.deferred<void>(
              (ctx) async {
                await delay(50);
                seen.add('${at()}: the child ends');
              },
              cancellable: false,
            );
            ctx.run(child).ignore();
            await ctx.abandonable(
              () async {
                await delay(20);
                return 'connection';
              },
              dispose: kind == 'dispose' ? cleanup : null,
              discard: kind == 'discard' ? cleanup : null,
            );
          });
          unawaited(
            job.done.then((outcome) => seen.add('${at()}: finished $outcome')),
          );
          async.elapse(const Duration(milliseconds: 5));
          unawaited(job.cancel());
          async.flushTimers();

          expect(seen, [
            '20 ms: $kind connection',
            '50 ms: the child ends',
            '60 ms: $kind done',
            '60 ms: finished Cancelled(manual)',
          ]);
        });
      });

      test(
          'a late value of abandonable joins the stack while the job finishes '
          '($kind)', () {
        fakeAsync((async) {
          final seen = <String>[];
          void cleanup(String value) =>
              seen.add('${async.elapsed.inMilliseconds} ms: $kind $value');
          final job = Job<void>((ctx) async {
            ctx.onDispose(() async {
              await delay(30);
              seen.add('${async.elapsed.inMilliseconds} ms: slow disposer');
            });
            await ctx.abandonable(
              () async {
                await delay(20);
                return 'connection';
              },
              dispose: kind == 'dispose' ? cleanup : null,
              discard: kind == 'discard' ? cleanup : null,
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
            '35 ms: $kind connection',
            '35 ms: finished Cancelled(manual)',
          ]);
        });
      });

      test(
          'a late value of abandonable runs alone once the job has finished '
          '($kind)', () {
        fakeAsync((async) {
          final seen = <String>[];
          void cleanup(String value) =>
              seen.add('${async.elapsed.inMilliseconds} ms: $kind $value');
          final job = Job<void>((ctx) async {
            await ctx.abandonable(
              () async {
                await delay(20);
                return 'connection';
              },
              dispose: kind == 'dispose' ? cleanup : null,
              discard: kind == 'discard' ? cleanup : null,
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
            '20 ms: $kind connection',
          ]);
        });
      });

      test('join awaits the $kind of its value before it throws', () {
        fakeAsync((async) {
          final seen = <String>[];
          Future<void> cleanup(String value) async {
            await delay(5);
            seen.add('${async.elapsed.inMilliseconds} ms: $kind $value');
          }

          final job = Job<void>((ctx) async {
            try {
              await ctx.join(
                () async {
                  await delay(20);
                  return 'connection';
                },
                dispose: kind == 'dispose' ? cleanup : null,
                discard: kind == 'discard' ? cleanup : null,
              );
            } on Cancelled {
              seen.add('${async.elapsed.inMilliseconds} ms: join threw');
              rethrow;
            }
          });
          async.elapse(const Duration(milliseconds: 5));
          unawaited(job.cancel());
          async.flushTimers();

          expect(seen, ['25 ms: $kind connection', '25 ms: join threw']);
        });
      });
    }
  });

  group('A token through onCancel: a stop that takes time', () {
    test('an async onCancel callback fails into the zone', () {
      stage.stopFails = true;
      final lines = play(
        (ctx) async {
          ctx.onCancel(() async {
            await device.stop();
          });
          await ctx.abandonable(() => delay(50));
        },
        cancelAt: 5,
      );

      expect(lines, [
        'cancel',
        'outcome: Cancelled(manual)',
        'zone: Bad state: device did not stop',
      ]);
    });

    test('an async onCancel callback fails before its first await the same',
        () async {
      // Real time and three zones: which one hears it is the claim.
      final zones = <String>[];
      late Job<void> job;
      runZonedGuarded(
        () => job = Job<void>(
          (ctx) async {
            ctx.onCancel(() async {
              throw StateError('device did not stop');
            });
            await ctx.abandonable(() => delay(50));
          },
          observer: printing,
        )..ignore(),
        (error, stackTrace) => zones.add('creation: $error'),
      );
      await delay(5);
      printed.clear();
      runZonedGuarded(
        () => job.cancel().ignore(),
        (error, stackTrace) => zones.add('cancel: $error'),
      );
      await job.done;
      await delay(5);

      expect(zones, ['cancel: Bad state: device did not stop']);
      expect(printed, isEmpty, reason: 'onError hears nothing');
    });

    test('a synchronous throw of onCancel reaches onError, then the zone', () {
      final lines = play(
        (ctx) async {
          ctx.onCancel(() => throw StateError('device did not stop'));
          await ctx.abandonable(() => delay(50));
        },
        cancelAt: 5,
      );

      expect(lines, [
        'cancel',
        'onError: Bad state: device did not stop',
        'zone: Bad state: device did not stop',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('the job does not wait for the stop it handed to unattended', () {
      expect(watch(page.stopTheDevice, cancelAt: 5), [
        'cancel',
        'device released',
        'outcome: Cancelled(manual)',
        'device stopped',
      ]);
    });

    test('a failed stop through unattended reaches onError, then the zone', () {
      stage.stopFails = true;
      expect(watch(page.stopTheDevice, cancelAt: 5), [
        'cancel',
        'device released',
        'outcome: Cancelled(manual)',
        'onError: Bad state: device did not stop',
        'zone: Bad state: device did not stop',
      ]);
    });

    test(
        'the zone that hears a failed stop is the one the job was created '
        'in, not the one of cancel()', () {
      stage.stopFails = true;
      fakeAsync((async) {
        late Job<void> job;
        runZonedGuarded(
          () => job = page.stopTheDevice(),
          (error, stackTrace) => say('the zone of the job: $error'),
        );
        async.elapse(const Duration(milliseconds: 5));
        runZonedGuarded(
          () => job.cancel().ignore(),
          (error, stackTrace) => say('the zone of cancel(): $error'),
        );
        async.flushTimers();
      });

      expect(printed, [
        'device released',
        'onError: Bad state: device did not stop',
        'the zone of the job: Bad state: device did not stop',
      ]);
    });

    test('a join around the operation the stop interrupts waits for it', () {
      expect(watch(page.waitForTheDevice, cancelAt: 5), [
        'cancel',
        'device stopped',
        'device released',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('a join around an operation that ends first waits for nothing more',
        () {
      final lines = play(
        (ctx) async {
          // The stop interrupts the playback at once and takes 10 ms more.
          final interrupted = Completer<void>();
          ctx
            ..onDispose(() => say('device released'))
            ..onCancel(
              () => ctx.unattended(() async {
                interrupted.complete();
                await delay(10);
                say('device stopped');
              }),
            );
          await ctx.join(() => interrupted.future);
        },
        cancelAt: 5,
      );

      expect(lines, [
        'cancel',
        'device released',
        'outcome: Cancelled(manual)',
        'device stopped',
      ]);
    });
  });

  group('A step that must finish', () {
    test('two joins lose the flag between them', () {
      expect(watch(page.twoJoins, cancelAt: 5), quoted[3]);
    });

    test('one join around the step makes both writes', () {
      expect(watch(page.oneJoinForTheStep, cancelAt: 5), quoted[4]);
    });

    test('one join keeps neither the token nor a checkpoint out', () {
      final withToken = play(
        (ctx) async {
          final stop = CancelToken();
          ctx.onCancel(stop.cancel);

          await ctx.join(() async {
            await database.writeVersion();
            if (stop.cancelled) {
              throw const DatabaseStopped();
            }
            await database.writeReadyFlag();
          });
        },
        cancelAt: 5,
      );
      final withCheckpoint = play(
        (ctx) async {
          await ctx.join(() async {
            await database.writeVersion();
            ctx.check();
            await database.writeReadyFlag();
          });
        },
        cancelAt: 5,
      );

      expect(withToken, isNot(contains('ready flag written')));
      expect(withCheckpoint, isNot(contains('ready flag written')));
    });
  });

  group('A step that runs a child', () {
    test('one join around the step loses the flag: run starts no child', () {
      expect(watch(page.oneJoinWithAChild, cancelAt: 5), quoted[5]);
      expect(
        database.flagJobs.single.outcome,
        isA<Cancelled>().having((c) => c.started, 'started', isFalse),
        reason: 'run throws instead of starting the child',
      );
    });

    test('uncancellable writes both, the child included', () {
      expect(watch(page.holdTheCancellationBack, cancelAt: 5), quoted[6]);
    });

    test('a held cancellation reaches no child until the section ends', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<void>((ctx) async {
          final child = Job.deferred<void>((ctx) async {
            ctx.onCancel(
              () => seen.add('${async.elapsed.inMilliseconds} ms: child'),
            );
            await ctx.abandonable(() => delay(100));
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
          await ctx.abandonable(() => delay(2));
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

    test(
        'a body that goes on past an unawaited section and gives itself up '
        'is cancelled at once', () {
      fakeAsync((async) {
        final seen = <String>[];
        var open = false;
        final job = Job<void>((ctx) async {
          ctx.onCancel(() => seen.add('onCancel, the section open: $open'));
          ctx.uncancellable(() async {
            open = true;
            try {
              await ctx.abandonable(() => delay(20));
            } on Cancelled catch (error) {
              seen.add('the wait in the section threw $error');
            } finally {
              open = false;
            }
          }).ignore();
          await delay(5);
          throw const Cancelled('gave up');
        });
        async.flushTimers();

        expect(seen, [
          'onCancel, the section open: true',
          'the wait in the section threw Cancelled(handler: gave up)',
        ]);
        expect(job.outcome, isA<Cancelled>());
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

    test('a deferred cancellable: false job cancelled before start is over',
        () {
      fakeAsync((async) {
        var ran = false;
        final job = Job.deferred<void>(
          (ctx) async => ran = true,
          cancellable: false,
        );
        var back = false;
        job.cancel().then((_) => back = true).ignore();
        async.flushTimers();
        expect(
          job.outcome,
          isA<Cancelled>().having((c) => c.started, 'started', isFalse),
        );
        expect(back, isTrue, reason: 'cancel() has nothing left to wait for');
        expect(job.start, throwsStateError);
        async.flushTimers();
        expect(ran, isFalse);
      });
    });

    test('Job(body) starts on the next microtask: a later cancel is refused',
        () {
      fakeAsync((async) {
        final job = Job<int>(
          (ctx) async {
            await ctx.join(() => delay(20));
            return 42;
          },
          cancellable: false,
        );
        expect(job.isRunning, isFalse, reason: 'created, not started yet');
        async.flushMicrotasks();
        expect(job.isRunning, isTrue);
        unawaited(job.cancel());
        async.flushTimers();
        expect(job.outcome, isA<Done<int>>());
      });
    });
  });

  group('Catching errors of the operation', () {
    test('a clause for Cancelled logs the stopped migration as a failure', () {
      expect(watch(page.catchCancelledFirst, cancelAt: cancelMs), quoted[7]);
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
          await ctx.join(() async {
            await database.writeVersion();
            await database.writeReadyFlag();
          });
        },
        cancelAt: cancelMs,
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
        cancelAt: cancelMs,
      );

      expect(lines, contains('log: migration failed: Cancelled(manual)'));
    });

    test('check in the catch lets the cancellation through', () {
      expect(watch(page.askTheJob, cancelAt: cancelMs), quoted[8]);
    });

    test('a failure of its own is logged, and the body goes on', () {
      stage.migrationFails = true;
      expect(watch(page.askTheJob), [
        'log: migration failed: FormatException: bad schema',
        'version written',
        'ready flag written',
        'outcome: Done(null)',
      ]);
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
            // ignore: cascade_invocations -- the form of Asking the job
            ctx.log('migration failed: $error');
          }
        },
        cancelAt: cancelMs,
      );

      expect(lines, quoted[8]);
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

    test('the clause of Asking the job logs a cancelled child as a failure',
        () {
      stage.thumbnail = Thumbnail.isCancelled;
      final lines = play((ctx) async {
        final thumbnail = Job.deferred<String>(renderThumbnail);
        try {
          return 'page with ${await ctx.run(thumbnail)}';
        } on Exception catch (error) {
          ctx.check();
          // ignore: cascade_invocations -- the form of Asking the job
          ctx.log('thumbnail failed: $error');
          return 'page without a thumbnail';
        }
      });

      expect(lines, [
        'log: thumbnail failed: Cancelled(manual)',
        'outcome: Done(page without a thumbnail)',
      ]);
    });

    for (final fails in [false, true]) {
      test(
          'a test of the type tells a cancelled child from a failed one '
          '(fails: $fails)', () {
        stage.thumbnail = fails ? Thumbnail.fails : Thumbnail.isCancelled;
        expect(watch(page.pageWithAThumbnail), [
          if (fails) ...[
            'onError: FormatException: bad image',
            'log: thumbnail failed: FormatException: bad image',
          ],
          'outcome: Done(page without a thumbnail)',
        ]);
      });
    }

    test('an operation waiting for a cancelled job passes check', () {
      final lines = play((ctx) async {
        final other = Job<String>((ctx) async {
          await ctx.abandonable(() => delay(20));
          return 'rows';
        });
        Timer(const Duration(milliseconds: 5), other.cancel);
        try {
          return await ctx.join(() async => 'read ${await other.value}');
        } on Exception catch (error) {
          ctx.check();
          if (error is! Cancelled) ctx.log('read failed: $error');
          return 'nothing read';
        }
      });

      expect(lines, ['outcome: Done(nothing read)']);
    });

    for (final (form, outcome) in [
      ('rethrow', 'Cancelled(handler: child null: Cancelled(manual))'),
      ('check', 'Done(page without a thumbnail)'),
    ]) {
      test('an optional child cancelled on its own, with $form', () {
        fakeAsync((async) {
          final job = Job<String>((ctx) async {
            final thumbnail = Job.deferred<String>((ctx) async {
              await ctx.abandonable(() => delay(20));
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

          expect('${job.outcome}', outcome);
        });
      });
    }
  });

  test('accepting reaches the children at once and decides the outcome', () {
    fakeAsync((async) {
      final seen = <String>[];
      final job = Job<int>((ctx) async {
        ctx.onCancel(() => seen.add('job onCancel'));
        final child = Job.deferred<void>((ctx) async {
          ctx.onCancel(() => seen.add('child onCancel'));
          await ctx.abandonable(() => delay(50));
        });
        ctx.run(child).ignore();
        await delay(20);
        seen.add('body returns');
        return 42;
      });
      async.elapse(const Duration(milliseconds: 5));
      unawaited(job.cancel());
      seen.add('cancel() returned, isCancelled: ${job.isCancelled}');
      async.flushTimers();

      expect(seen, [
        'child onCancel',
        'job onCancel',
        'cancel() returned, isCancelled: true',
        'body returns',
      ]);
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('a body that gives itself up runs its onCancel, after the children', () {
    fakeAsync((async) {
      final seen = <String>[];
      final threw = Job<void>((ctx) async {
        ctx.onCancel(() => seen.add('threw: onCancel'));
        await ctx.abandonable(() => delay(5));
        throw const Cancelled('why');
      })
        ..ignore();
      late Job<void> left;
      final threwWithChild = Job<void>((ctx) async {
        ctx.onCancel(() => seen.add('with child: onCancel'));
        left = Job.deferred<void>((ctx) async {
          ctx.onCancel(() => seen.add('with child: the child onCancel'));
          await ctx.abandonable(() => delay(50));
        });
        ctx.run(left).ignore();
        await ctx.abandonable(() => delay(10));
        throw const Cancelled('why');
      })
        ..ignore();
      final letOut = Job<void>((ctx) async {
        ctx.onCancel(() => seen.add('let out: onCancel'));
        final child =
            Job.deferred<void>((ctx) => ctx.abandonable(() => delay(20)));
        Timer(const Duration(milliseconds: 15), child.cancel);
        await ctx.run(child);
      })
        ..ignore();
      async.flushTimers();

      expect(seen, [
        'threw: onCancel',
        'with child: the child onCancel',
        'with child: onCancel',
        'let out: onCancel',
      ]);
      expect(threw.outcome, isA<Cancelled>());
      expect(letOut.outcome, isA<Cancelled>());
      expect(threwWithChild.outcome, isA<Cancelled>());
      expect(
        left.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<ParentCancelReason>(),
        ),
        reason: 'the cancellation still passes to the children',
      );
    });
  });

  test('after the cancellation, the waiting members throw and the rest work',
      () {
    fakeAsync((async) {
      final seen = <String>[];
      final branch = Job.deferred<int>((ctx) async => 1);
      final job = Job<void>((ctx) async {
        try {
          await ctx.abandonable(() => delay(50));
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
          await probe('abandonable', () => ctx.abandonable(() => 1));
          await probe('join', () => ctx.join(() => 1));
          await probe('uncancellable', () => ctx.uncancellable(() => 1));
          await probe('run', () => ctx.run(Job.deferred((ctx) async => 1)));
          await probe('runAll', () => ctx.runAll<int>([]));
          await probe('runAll of a job', () => ctx.runAll<int>([branch]));
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
        'abandonable throws',
        'join throws',
        'uncancellable throws',
        'run throws',
        'runAll throws',
        'runAll of a job throws',
        'each throws',
        'onCancel throws',
        'onDispose works',
        'onDiscard works',
        'disown works',
        'unattended works',
      ]);
      expect(
        branch.outcome,
        isA<Cancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          isA<ParentCancelReason>(),
        ),
        reason: 'the group started nothing and cancelled its branch',
      );
    });
  });

  group('Letting time pass', () {
    String row(String how, ({int endedAfter, int timerLeftFor}) measured) {
      final ended = measured.endedAfter == 0
          ? 'at once'
          : '${measured.endedAfter} ms after the cancellation';
      final timer = measured.timerLeftFor == 0
          ? 'none'
          : 'for ${measured.timerLeftFor} ms more';
      return '| $how | $ended | $timer |';
    }

    final lines = File('doc/cancellation.md').readAsLinesSync();

    test('a plain delay is sat out to its end', () {
      final measured = waiting(page.plainDelay);
      expect(measured, (endedAfter: 510, timerLeftFor: 0));
      expect(lines, contains(row('`await Future.delayed(...)`', measured)));
    });

    test('a delay under abandonable ends at once and leaves its timer', () {
      final measured = waiting(page.delayUnderAbandonable);
      expect(measured, (endedAfter: 0, timerLeftFor: 510));
      expect(
        lines,
        contains(row('`ctx.abandonable(() => Future.delayed(...))`', measured)),
      );
    });

    test('a pause ends at once and takes its timer along', () {
      final measured = waiting(page.pauseOfTheJob);
      expect(measured, (endedAfter: 0, timerLeftFor: 0));
      expect(lines, contains(row('`ctx.pause(...)`', measured)));
    });

    test('uncancelled, all three read once a second', () {
      for (final start in [
        page.plainDelay,
        page.delayUnderAbandonable,
        page.pauseOfTheJob,
      ]) {
        freshRun();
        fakeAsync((async) {
          final job = start()..ignore();
          async.elapse(const Duration(milliseconds: 2500));
          expect(printed.where((line) => line == 'rows used'), hasLength(3));
          unawaited(job.cancel());
          async.flushTimers();
        });
      }
    });
  });

  group('A deadline', () {
    String row(String how, ({int timerLeftFor, List<String> zone}) measured) {
      final timer = measured.timerLeftFor == 0
          ? 'none'
          : 'for ${measured.timerLeftFor} ms more';
      final zone =
          measured.zone.isEmpty ? 'reaches no zone' : 'reaches the zone';
      return '| $how | $timer | $zone |';
    }

    final text = File('doc/cancellation.md').readAsStringSync();
    final lines = text.split('\n');

    /// What the prose of the page quotes after [before], up to the closing
    /// backtick.
    String quotedAfter(String before) => RegExp(
          '${before.replaceAll(' ', r'\s+')}\\s+`([^`]+)`',
        ).firstMatch(text)!.group(1)!;

    test('a timer cancels the job still running, as the user does', () {
      expect(watch(page.timerOnTheJob), quoted[9]);
    });

    test('the timer does nothing to a job that has already finished', () {
      fakeAsync((async) {
        final quick = Job<int>((ctx) async => 1);
        Timer(page.limit, quick.cancel);
        async.flushTimers();

        expect('${quick.outcome}', 'Done(1)');
      });

      stage.migrationFails = true;
      expect(watch(page.timerOnTheJob), [
        'onError: FormatException: bad schema',
        'database closed',
        'outcome: Failed(FormatException: bad schema)',
      ]);
    });

    test('the timer lives until the limit, and the failure reaches the zone',
        () {
      final measured = failingUnderALimit(page.timerOnTheJob);
      expect(measured.timerLeftFor, page.limit.inMilliseconds);
      expect(measured.zone, ['FormatException: bad schema']);
      expect(lines, contains(row('`Timer(limit, job.cancel)`', measured)));
    });

    test('cancelling the timer when the job ends observes the outcome', () {
      final measured = failingUnderALimit(page.timerCancelledAtTheEnd);
      expect(measured.timerLeftFor, 0);
      expect(measured.zone, isEmpty);
      expect(
        lines,
        contains(row('`job.done.whenComplete(timer.cancel)`', measured)),
      );
      expect(printed, contains('onError: FormatException: bad schema'));
    });

    test('without an observer, nobody hears that failure', () {
      final measured = failingUnderALimit(() {
        final job = Job<Database>((ctx) async {
          final database = await ctx.join(Database.open);
          await ctx.join(() => database.migrate(CancelToken()));
          return database;
        });
        final timer = Timer(page.limit, job.cancel);
        job.done.whenComplete(timer.cancel).ignore();
        return job;
      });
      expect(measured.zone, isEmpty);
      expect(printed, isEmpty);
    });

    test('with a timer cancelled at the end, a running job is still cancelled',
        () {
      expect(watch(page.timerCancelledAtTheEnd), quoted[9]);
    });

    test('a deadline of the job stops it the same way, with its own reason',
        () {
      expect(watch(page.deadlineOfTheJob), quoted[10]);
    });

    test('a deadline leaves no timer and lets the failure reach the zone', () {
      final measured = failingUnderALimit(page.deadlineOfTheJob);
      expect(measured.timerLeftFor, 0);
      expect(measured.zone, ['FormatException: bad schema']);
      expect(lines, contains(row('`timeout: limit`', measured)));
    });

    test('the deadline is counted from the start of the body', () {
      fakeAsync((async) {
        final job = Job.deferred<void>(
          timeout: page.limit,
          (ctx) => ctx.pause(const Duration(milliseconds: 10)),
        );
        async.elapse(const Duration(milliseconds: 50));
        job.start();
        async.flushTimers();

        expect('${job.outcome}', 'Done(null)');
      });
    });

    test('the timer is gone the moment the job ends', () {
      fakeAsync((async) {
        final job = Job<int>(timeout: const Duration(hours: 1), (ctx) async {
          await ctx.pause(const Duration(milliseconds: 10));
          return 1;
        });
        async.elapse(const Duration(milliseconds: 5));
        expect(async.pendingTimers, hasLength(2));
        async.elapse(const Duration(milliseconds: 5));

        expect('${job.outcome}', 'Done(1)');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a running job holds its timer until it ends', () {
      fakeAsync((async) {
        final job = page.deadlineOfTheJob()..ignore();
        async.elapse(const Duration(milliseconds: 5));

        expect(job.isFinished, isFalse);
        expect(async.pendingTimers, isNotEmpty);
        unawaited(job.cancel());
        async.flushTimers();
      });
    });

    test('an uncancellable section holds the deadline until it closes', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<void>(timeout: page.limit, (ctx) async {
          await ctx.uncancellable(() => delay(30));
          seen.add('section closed');
          ctx.check();
          seen.add('after the section');
        });
        async.flushTimers();

        expect(seen, ['section closed']);
        expect('${job.outcome}', 'Cancelled(timeout)');
      });
    });

    test('a job cancelled already keeps its own reason', () {
      fakeAsync((async) {
        final job = page.deadlineOfTheJob()..ignore();
        async.elapse(const Duration(milliseconds: 5));
        unawaited(job.cancel());
        async.flushTimers();

        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('the children hear the deadline as the cause of their cancellation',
        () {
      fakeAsync((async) {
        final child = Job.deferred<void>((ctx) => ctx.pause(page.limit * 2));
        final job = Job<void>(timeout: page.limit, (ctx) => ctx.run(child));
        async.flushTimers();

        expect('${job.outcome}', 'Cancelled(timeout)');
        final reason = (child.outcome! as Cancelled).reason;
        expect(
          reason,
          isA<ParentCancelReason>().having(
            (reason) => reason.cause?.reason,
            'cause',
            isA<TimeoutCancelReason>().having(
              (reason) => reason.timeout,
              'timeout',
              page.limit,
            ),
          ),
        );
      });
    });

    test('the deadline does not reach the cleanup stack', () {
      fakeAsync((async) {
        final seen = <String>[];
        final job = Job<String>(timeout: page.limit, (ctx) async {
          ctx.onDispose(() async {
            await delay(30);
            seen.add('cleaned up');
          });
          return 'done';
        });
        async.flushTimers();

        expect(seen, ['cleaned up']);
        expect('${job.outcome}', 'Done(done)');
      });
    });

    test('a deadline that is not positive, or not refusable, throws', () {
      for (final timeout in [Duration.zero, const Duration(milliseconds: -1)]) {
        expect(
          () => Job<void>(timeout: timeout, (ctx) async {}),
          throwsArgumentError,
        );
      }
      expect(
        () => Job<void>(
          timeout: page.limit,
          cancellable: false,
          (ctx) async {},
        ),
        throwsArgumentError,
      );
    });

    test('a step with a deadline goes out without its thumbnail', () {
      expect(watch(page.thumbnailWithADeadline), quoted[11]);
    });

    test('the clause rethrows the cancellation of the job', () {
      expect(watch(page.thumbnailWithADeadline, cancelAt: 5), [
        'cancel',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('a request a section holds past the body goes with the timer', () {
      late final String outcome;
      fakeAsync((async) {
        final job = Job<int>(
          timeout: const Duration(milliseconds: 10),
          (ctx) async {
            ctx.onDispose(() => delay(200));
            unawaited(ctx.uncancellable(() => delay(100)));
            await ctx.run(Job.deferred((ctx) => delay(50)));
            return 1;
          },
        );
        async.flushTimers();
        outcome = '${job.outcome}';
      });

      expect(outcome, 'Done(1)');
      expect(
        text.replaceAll(RegExp(r'\s+'), ' '),
        contains('If the body and the children it waits for are over while '
            'the section still holds the request, the request goes with the '
            'timer, and the job ends with what the body returned.'),
      );
    });

    test('the clause rethrows a thumbnail somebody else cancelled', () {
      stage.thumbnail = Thumbnail.isCancelled;
      expect(watch(page.thumbnailWithADeadline), [
        'outcome: Cancelled(handler: child thumbnail: Cancelled(manual))',
      ]);
    });

    for (final key in ['thumbnail', null]) {
      test('let out, the deadline of the child ends the parent (key: $key)',
          () {
        late final String outcome;
        fakeAsync((async) {
          final job = Job<String>((ctx) async {
            final thumbnail = Job.deferred<String>(
              renderThumbnail,
              key: key,
              timeout: const Duration(milliseconds: 15),
            );
            return 'page with ${await ctx.run(thumbnail)}';
          });
          async.flushTimers();
          outcome = '${job.outcome}';
        });

        expect(
          outcome,
          'Cancelled(handler: child $key: Cancelled(timeout))',
        );
        if (key == null) {
          expect(quotedAfter('a child without one prints as'), 'child null');
        } else {
          expect(quotedAfter('deadline ends the parent'), outcome);
        }
      });
    }
  });

  group('The page', () {
    test('quotes what its code prints', () {
      final text = File('doc/cancellation.md').readAsStringSync();
      final blocks = RegExp(r'```text\n(.*?)\n```', dotAll: true)
          .allMatches(text)
          .map((match) => match.group(1)!.split('\n'))
          .toList();

      expect(blocks, quoted);
    });

    test('names the durations its code takes', () {
      final text = File('doc/cancellation.md').readAsStringSync();
      final steps = [
        for (final match
            in RegExp(r'three\s+steps\s+of\s+(\d+)\s+ms').allMatches(text))
          match.group(1),
      ];
      final cancels = [
        for (final match in RegExp(r'(\d+)\s+ms\s+in\b').allMatches(text))
          match.group(1),
      ];

      final limits = [
        for (final match in RegExp(r'is\s+given\s+(\d+)\s+ms').allMatches(text))
          match.group(1),
        for (final match
            in RegExp(r'takes\s+longer\s+than\s+(\d+)\s+ms').allMatches(text))
          match.group(1),
      ];
      final renders = [
        for (final match
            in RegExp(r'`renderThumbnail`\s+takes\s+(\d+)').allMatches(text))
          match.group(1),
      ];

      expect(steps, ['$stepMs']);
      expect(limits, ['${page.limit.inMilliseconds}', '15']);
      expect(renders, ['20']);
      expect(cancels, ['$cancelMs', '$cancelMs', '$pauseCancelMs']);
    });

    test('holds every block of its code in the region in its place', () {
      expect(
        codeOutOfPlace(
          'doc/cancellation.md',
          'test/support/cancellation_page.dart',
        ),
        isEmpty,
      );
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/cancellation.md'), isEmpty);
    });
  });
}
