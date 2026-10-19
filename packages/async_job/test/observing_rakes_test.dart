// `doc/observing.md` and `doc/testing.md` run here. The code of the pages
// stands verbatim in `support/observing_page.dart`, their first attempts in
// `support/observing_first_attempts.dart`, and what that code takes for
// granted in `support/observing_stubs.dart`. Every block of the pages runs in
// a test below, every quote is compared with what its block prints, and every
// piece of code on the pages has to be a run of lines of those files: a piece
// or a quote that drifts turns this file red. The rules the page states in
// prose and in its table are held with code of the tests' own where the page
// shows none.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/observing_first_attempts.dart' as first;
import 'support/observing_page.dart';
import 'support/observing_stubs.dart';
import 'support/page_code.dart';

/// The fake time of the running [play].
late FakeAsync time;

int get now => time.elapsed.inMilliseconds;

/// Starts a job under fake time and returns what was printed.
///
/// The code around the job prints the outcome as `outcome:` unless
/// [outcomeObserved] is false, and cancels at [cancelAt] ms, printing
/// `cancel` and then how long `cancel()` took. An error that reaches the zone
/// is printed as `zone:`.
List<String> play(
  Job<Object?> Function() start, {
  int? cancelAt,
  bool outcomeObserved = true,
}) {
  final printed = <String>[];
  runZonedGuarded(
    () => fakeAsync((async) {
      time = async;
      final job = start();
      if (outcomeObserved) {
        unawaited(job.done.then((outcome) => print('outcome: $outcome')));
      }
      if (cancelAt != null) {
        async.elapse(Duration(milliseconds: cancelAt));
        print('cancel');
        final calledAt = now;
        unawaited(
          job.cancel().then(
                (_) => print('cancel() returned after ${now - calledAt} ms'),
              ),
        );
      }
      async.flushTimers();
    }),
    (error, stackTrace) => printed.add('zone: $error'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}

/// The lines of [play] that the page quotes: `cancel()` timing is not one.
List<String> quotable(List<String> lines) => [
      for (final line in lines)
        if (!line.startsWith('cancel()')) line,
    ];

/// The job of the first attempt in "Where errors go", with [observer].
Job<void> migratingObserved(JobObserver observer) => Job<void>(
      observer: observer,
      (ctx) async {
        final stop = CancelToken();
        ctx.onCancel(stop.cancel);

        await ctx.join(() => database.migrate(stop));
      },
    );

/// What [run] returns with the filter of the page set as `main` sets it;
/// the field is put back after it.
List<String> withTheStopNamed(List<String> Function() run) {
  nameTheStop();
  try {
    return run();
  } finally {
    Job.isCancellationError = null;
  }
}

/// What [run] returns with the debug channel of the page switched on as
/// `main` switches it: its lines go where the job prints. The field is put
/// back after it.
List<String> debugged(List<String> Function() run) {
  debugToTheConsole();
  try {
    return quotable(run());
  } finally {
    Job.debug = null;
  }
}

/// The `text` blocks of the page, line by line, in the order of the page.
List<List<String>> pageQuotes() => [
      for (final block in RegExp(r'```text\n(.*?)\n```', dotAll: true)
          .allMatches(File('doc/observing.md').readAsStringSync()))
        block.group(1)!.split('\n'),
    ];

/// An observer that hears through `onError` and answers in `onUnanswered`,
/// and with [passedOn] hands each error on to `super` as well.
final class Answerer extends JobObserver with JobAnswerer {
  final bool passedOn;

  Answerer({this.passedOn = false});

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onError: $error');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    print('onUnanswered: $error');
    if (passedOn) {
      super.onUnanswered(job, error, stackTrace);
    }
  }
}

/// Every hook, for the rules the page states about them.
final class Hooks extends JobObserver {
  final String name;

  Hooks([this.name = '']);

  @override
  void onStart(Job<Object?> job) => print('${name}onStart $job');

  @override
  void onFinish(Job<Object?> job) => print('${name}onFinish $job');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('${name}onError: $error');

  @override
  void onLog(Job<Object?> job, Object? message) =>
      print('${name}onLog: $message');
}

/// A hook that throws, next to two that do not.
final class ThrowingStart extends JobObserver {
  @override
  void onStart(Job<Object?> job) => throw StateError('onStart failed');

  @override
  void onLog(Job<Object?> job, Object? message) => print('onLog: $message');

  @override
  void onFinish(Job<Object?> job) => print('onFinish $job');
}

/// A hook that throws when the job ends.
final class ThrowingFinish extends JobObserver {
  @override
  void onFinish(Job<Object?> job) => throw StateError('onFinish failed');
}

/// A hook that throws a cancellation, which goes nowhere.
final class ThrowingCancellation extends JobObserver {
  @override
  void onStart(Job<Object?> job) => throw const Cancelled('from onStart');

  @override
  void onFinish(Job<Object?> job) => print('onFinish $job');
}

/// A hook that cancels its job the way anybody else would.
final class CallingCancel extends JobObserver {
  @override
  void onStart(Job<Object?> job) => job.cancel().ignore();

  @override
  void onFinish(Job<Object?> job) => print('onFinish $job');
}

/// A class the app already has, which an observer extends.
class Tally {
  int count = 0;
}

/// Extends [Tally] and mixes in the observer and the answer.
final class TallyingAnswerer extends Tally with JobObserver, JobAnswerer {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    count++;
    print('onError: $error');
  }

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onUnanswered: $error');
}

/// An observer that keeps what `ctx.log` handed it.
final class Keeping extends JobObserver {
  final messages = <Object?>[];

  @override
  void onLog(Job<Object?> job, Object? message) => messages.add(message);
}

/// `SlowCancellations` of the page on fake time. A `Stopwatch` does not move
/// with fake time, so this one reads the fake clock, and the numbers the page
/// states come out exact.
final class FakeTimeCancellations extends JobObserver {
  final _acceptedAt = Expando<int>('cancellation');

  @override
  void onStart(Job<Object?> job) =>
      job.whenCancelled((_) => _acceptedAt[job] = now);

  @override
  void onFinish(Job<Object?> job) {
    final acceptedAt = _acceptedAt[job];
    if (acceptedAt != null) {
      print('$job ran ${now - acceptedAt} ms past its cancellation');
    }
  }
}

/// An observer whose `onError` throws.
final class Throwing extends JobObserver {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      throw StateError('reporter down');
}

/// `Both` of the page with any two observers in its place: `onError` handed
/// on by hand, unwrapped, the way the page writes it.
final class HandedOn extends JobObserver with JobAnswerer {
  final JobObserver first;
  final JobObserver second;

  HandedOn(this.first, this.second);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    first.onError(job, error, stackTrace);
    second.onError(job, error, stackTrace);
  }

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onUnanswered: $error');
}

/// The error of the log section; it counts how often it is put into words.
final class MigrationFailed implements Exception {
  int formatted = 0;

  @override
  String toString() {
    formatted++;
    return 'MigrationFailed';
  }
}

/// A key that cannot be put into words.
final class BrokenKey {
  @override
  String toString() => throw StateError('key failed');
}

/// A reason of a cancellation that cannot be put into words.
final class BrokenReason extends CancelReason {
  const BrokenReason();

  @override
  String get name => throw StateError('name failed');
}

/// A step that cannot be rolled back: it fails at 20 ms.
Future<void> pay() async {
  await delay(20);
  throw StateError('payment failed');
}

/// A body that fails at 10 ms.
Job<void> failing({JobObserver? observer}) => Job<void>(
      key: 'save',
      observer: observer,
      (ctx) async {
        await delay(10);
        throw StateError('disk full');
      },
    );

void main() {
  group('The code of the page', () {
    setUp(() => stage = Stage());

    test('every quote on the page is what its code prints', () {
      stage.databaseLocked = true;
      final prints = [
        play(loading, outcomeObserved: false),
        quotable(play(first.migrating, cancelAt: 10)),
        withTheStopNamed(() => quotable(play(first.migrating, cancelAt: 10))),
        quotable(play(openingReported, cancelAt: 10)),
        debugged(() => play(first.migrating, cancelAt: 10)),
        play(first.sendingUnawaited),
        play(() => sendingHandedOver(Reporter())),
        play(saving),
        play(first.sendingWithBoth),
        play(sendingToTheList),
      ];
      expect(
        pageQuotes(),
        prints,
        reason: 'each quote under the code that prints it',
      );
    });

    test('the page has no fence the checks do not read', () {
      expect(strayFences('doc/observing.md'), isEmpty);
    });

    // Each version under its own file: a line of an answer turned into the
    // line of a first attempt would still be found among all of them.
    const page = 'test/support/observing_page.dart';
    const firstAttempts = 'test/support/observing_first_attempts.dart';
    const holders = {
      '## Observer': page,
      '### Timing a cancellation': page,
      '### The first attempt': firstAttempts,
      '### Formatting left to the observer': page,
      '### Errors of a cancellation': page,
      '### An observer': page,
      '### The debug channel': page,
      '### Limits of the filter': page,
      '### Work handed to the job': page,
      '## Answering for errors': page,
      '### Several failures in one error': page,
      '## Several observers': page,
      '### Observers in one list': page,
    };
    for (final MapEntry(key: heading, value: holder) in holders.entries) {
      test('the code under "$heading" is a run of lines of $holder', () {
        expect(
          codeMissingFrom('doc/observing.md', holder, under: heading),
          isEmpty,
        );
      });
    }

    test('every piece of code on the page is a run of lines of these files',
        () {
      expect(
        codeMissingFrom('doc/observing.md', page, alsoIn: [firstAttempts]),
        isEmpty,
      );
    });
  });

  group('Observer', () {
    test('onFinish runs for a job cancelled before it started', () {
      final lines = play(
        () => Job.deferred<void>(
          key: 'early',
          observer: Hooks(),
          (ctx) async {},
        ),
        cancelAt: 0,
      );

      expect(quotable(lines), [
        'cancel',
        'onFinish Job(early)',
        'outcome: Cancelled(manual)',
      ]);
    });

    test('children inherit the observer unless they have their own', () {
      final lines = play(
        () => Job<void>(
          key: 'parent',
          observer: Hooks('parent '),
          (ctx) async {
            await ctx.run(Job.deferred<void>(key: 'a', (ctx) async {}));
            await ctx.run(
              Job.deferred<void>(
                key: 'b',
                observer: Hooks('own '),
                (ctx) async {},
              ),
            );
          },
        ),
        outcomeObserved: false,
      );

      expect(lines, [
        'parent onStart Job(parent)',
        'parent onStart Job(a)',
        'parent onFinish Job(a)',
        'own onStart Job(b)',
        'own onFinish Job(b)',
        'parent onFinish Job(parent)',
      ]);
    });

    test('a class that extends another mixes in the observer and the answer',
        () {
      final observer = TallyingAnswerer();
      final lines = play(
        () => Job<void>(
          observer: observer,
          (ctx) async {
            ctx.onDispose(() => throw StateError('cleanup'));
          },
        ),
      );

      expect(lines, [
        'onError: Bad state: cleanup',
        'onUnanswered: Bad state: cleanup',
        'outcome: Done(null)',
      ]);
      expect(observer.count, 1);
    });

    test('a hook that throws changes nothing else', () {
      final lines = play(
        () => Job<int>(
          key: 'hooked',
          observer: ThrowingStart(),
          (ctx) async {
            ctx.log('logged');
            return 1;
          },
        ),
      );

      expect(lines, [
        'zone: Bad state: onStart failed',
        'onLog: logged',
        'onFinish Job(hooked)',
        'outcome: Done(1)',
      ]);
    });

    test('a Cancelled a hook throws cancels nothing; cancel() does', () {
      final thrown = play(
        () => Job<int>(
          key: 'thrown',
          observer: ThrowingCancellation(),
          (ctx) => ctx.abandonable(load),
        ),
      );
      final called = play(
        () => Job<int>(
          key: 'called',
          observer: CallingCancel(),
          (ctx) => ctx.abandonable(load),
        ),
      );

      expect(thrown, ['onFinish Job(thrown)', 'outcome: Done(3)']);
      expect(called, ['onFinish Job(called)', 'outcome: Cancelled(manual)']);
    });

    test("a hook's error goes to the zone that calls it", () {
      // Created in one zone and cancelled before start from another: the
      // hook runs in the canceller's.
      final caught = <String>[];
      fakeAsync((async) {
        late DeferredJob<void> job;
        runZonedGuarded(
          () => job = Job.deferred<void>(
            observer: ThrowingFinish(),
            (ctx) async {},
          ),
          (error, stackTrace) => caught.add('creation: $error'),
        );
        runZonedGuarded(
          () => job.cancel().ignore(),
          (error, stackTrace) => caught.add('canceller: $error'),
        );
        async.flushTimers();
      });

      expect(caught, ['canceller: Bad state: onFinish failed']);
    });

    test('the four string representations', () {
      Job<void> job({Object? key, String Function()? describe}) =>
          Job<void>(key: key, describe: describe, (ctx) async {});

      fakeAsync((async) {
        expect(job(key: 'load').toString(), 'Job(load)');
        expect(job(key: 'load', describe: () => '').toString(), 'Job(load)');
        expect(
          job(key: 'load', describe: () => 'user 7').toString(),
          'Job(load: user 7)',
        );
        expect(job(describe: () => 'user 7').toString(), 'Job(user 7)');
        expect(job().toString(), 'Job()');
        async.flushTimers();
      });
    });

    test('a key or describe that throws is printed as a mark', () {
      Job<void> job({Object? key, String Function()? describe}) =>
          Job<void>(key: key, describe: describe, (ctx) async {});
      String brokenDescribe() => throw StateError('describe failed');

      fakeAsync((async) {
        expect(
          job(key: 'load', describe: brokenDescribe).toString(),
          'Job(load: <describe threw StateError>)',
        );
        expect(
          job(describe: brokenDescribe).toString(),
          'Job(<describe threw StateError>)',
        );
        expect(job(key: BrokenKey()).toString(), 'Job(<key threw StateError>)');
        async.flushTimers();
      });
    });

    test("a name that throws leaves the core's own error in place", () {
      const mark = '<describe threw StateError>';
      String brokenDescribe() => throw StateError('describe failed');
      final errors = <Object>[];
      fakeAsync((async) {
        final twice = Job.deferred<void>(
          key: 'twice',
          describe: brokenDescribe,
          (ctx) async {},
        )..start();
        try {
          twice.start();
        } on Object catch (error) {
          errors.add(error);
        }

        final finished = Job.deferred<void>(
          key: 'finished',
          describe: brokenDescribe,
          (ctx) async {},
        )..start();
        async.flushMicrotasks();
        final parent = Job<void>((ctx) async {
          try {
            await ctx.run(finished);
          } on Object catch (error) {
            errors.add(error);
          }
        });

        final lost = Job<void>(
          key: 'lost',
          describe: brokenDescribe,
          (ctx) async => Job.deferred<void>((ctx) async {}),
        )..ignoreFailure();
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
        errors.add((lost.outcome! as Failed).error);
      });

      expect(errors.map((error) => '$error'), [
        'Bad state: Job(twice: $mark) is already running',
        'Bad state: Job(finished: $mark) has already finished',
        startsWith(
          'Invalid argument(s): Job(lost: $mark) '
          'returned Job(), a deferred job that never started',
        ),
      ]);
    });
  });

  group('Timing a cancellation', () {
    List<String> timed(Future<void> Function(JobContext ctx) body) => play(
          () => Job<void>(
            key: 'slow',
            observer: FakeTimeCancellations(),
            body,
          ),
          cancelAt: 10,
          outcomeObserved: false,
        );

    test('a bare await shows the rest of the wait', () {
      final lines = timed((ctx) async {
        await delay(300);
        ctx.check();
      });

      expect(lines, [
        'cancel',
        'Job(slow) ran 290 ms past its cancellation',
        'cancel() returned after 290 ms',
      ]);
    });

    test('the same call through ctx.abandonable shows 0 ms', () {
      final lines = timed((ctx) => ctx.abandonable(() => delay(300)));

      expect(lines, [
        'cancel',
        'Job(slow) ran 0 ms past its cancellation',
        'cancel() returned after 0 ms',
      ]);
    });

    test('children and cleanup are in the count', () {
      final lines = timed((ctx) async {
        ctx.onDispose(() => delay(50));
        await ctx.run(Job.deferred<void>(key: 'child', (ctx) => delay(100)));
      });

      expect(lines, [
        'cancel',
        'Job(child) ran 90 ms past its cancellation',
        'Job(slow) ran 140 ms past its cancellation',
        'cancel() returned after 140 ms',
      ]);
    });

    test('a held cancellation counts from the end of the section', () {
      final lines = timed((ctx) async {
        await ctx.uncancellable(() => delay(100));
        await ctx.abandonable(() => delay(300));
      });

      expect(lines, [
        'cancel',
        'Job(slow) ran 0 ms past its cancellation',
        'cancel() returned after 90 ms',
      ]);
    });

    test('a body that cancels itself counts from its throw', () {
      // The body throws at 10 ms, the child it cannot cancel runs to 110 ms,
      // and the cleanup takes 50 ms more: the child and the cleanup are both
      // in the count, as for a cancellation from outside.
      final lines = play(
        () => Job<void>(
          key: 'self',
          observer: FakeTimeCancellations(),
          (ctx) async {
            ctx
              ..onDispose(() => delay(50))
              ..run(
                Job.deferred<void>(cancellable: false, (ctx) => delay(110)),
              ).ignore();
            await delay(10);
            throw const Cancelled.by(
              reason: ManualCancelReason(),
            );
          },
        ),
        outcomeObserved: false,
      );

      expect(lines, ['Job(self) ran 150 ms past its cancellation']);
    });

    test("a child's cancellation let out counts the same way", () {
      final lines = play(
        () {
          final child = Job.deferred<void>(
            key: 'child',
            (ctx) => ctx.abandonable(() => delay(50)),
          );
          unawaited(
            Future<void>.delayed(
              const Duration(milliseconds: 10),
              () => child.cancel().ignore(),
            ),
          );
          return Job<void>(
            key: 'parent',
            observer: FakeTimeCancellations(),
            (ctx) async {
              ctx
                  .run(
                    Job.deferred<void>(
                      cancellable: false,
                      (ctx) => delay(110),
                    ),
                  )
                  .ignore();
              await ctx.run(child);
            },
          );
        },
        outcomeObserved: false,
      );

      expect(lines, [
        'Job(child) ran 0 ms past its cancellation',
        'Job(parent) ran 100 ms past its cancellation',
      ]);
    });
  });

  group('Timing a cancellation with the Stopwatch of the page', () {
    // `SlowCancellations` as the page writes it, in real time: the numbers
    // above are exact on fake time, and here the code of the page shows the
    // same, give or take what a shared machine adds.
    Future<List<String>> timed(
      Future<void> Function(JobContext ctx) body, {
      int? cancelAt,
    }) async {
      final lines = <String>[];
      await runZoned(
        () async {
          final job = Job<void>(
            key: 'slow',
            observer: SlowCancellations(),
            body,
          );
          if (cancelAt != null) {
            await delay(cancelAt);
            final watch = Stopwatch()..start();
            await job.cancel();
            lines.add(
              'cancel() returned after ${watch.elapsedMilliseconds} ms',
            );
          }
          await job.done;
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ),
      );
      return lines;
    }

    int ms(String line) =>
        int.parse(RegExp(r'(\d+) ms').firstMatch(line)!.group(1)!);

    test(
      'a bare await adds the rest of the wait',
      () async {
        final lines = await timed(
          (ctx) async {
            await delay(300);
            ctx.check();
          },
          cancelAt: 10,
        );

        expect(lines.first, startsWith('Job(slow) ran '));
        expect(ms(lines.first), greaterThanOrEqualTo(250));
      },
      retry: 2,
    );

    test(
      'the same call through ctx.abandonable shows next to nothing',
      () async {
        final lines = await timed(
          (ctx) => ctx.abandonable(() => delay(300)),
          cancelAt: 10,
        );

        expect(ms(lines.first), lessThan(50));
      },
      retry: 2,
    );

    test(
      'a held cancellation counts from the end of the section',
      () async {
        final lines = await timed(
          (ctx) async {
            await ctx.uncancellable(() => delay(100));
            await ctx.abandonable(() => delay(300));
          },
          cancelAt: 10,
        );

        expect(ms(lines.first), lessThan(50));
        expect(ms(lines.last), greaterThanOrEqualTo(80));
      },
      retry: 2,
    );

    test(
      'a body that cancels itself counts its child and cleanup',
      () async {
        final lines = await timed((ctx) async {
          ctx
            ..onDispose(() => delay(50))
            ..run(
              Job.deferred<void>(cancellable: false, (ctx) => delay(110)),
            ).ignore();
          await delay(10);
          throw const Cancelled('gave up');
        });

        expect(ms(lines.single), greaterThanOrEqualTo(140));
      },
      retry: 2,
    );
  });

  group('A message for the log', () {
    setUp(() => stage = Stage());

    test('the first attempt builds the string without an observer', () {
      final error = MigrationFailed();
      stage.migrationError = error;
      play(first.migrationLoggedAsAString);

      expect(error.formatted, 1);
    });

    test('the callback is not called without an observer', () {
      final error = MigrationFailed();
      stage.migrationError = error;
      play(migration);

      expect(error.formatted, 0);
    });

    test('Log calls the callback and prints what it returns', () {
      final error = MigrationFailed();
      stage.migrationError = error;
      final lines = play(
        () => migration(observer: Log()),
        outcomeObserved: false,
      );

      expect(lines, [
        'Job(migrate): migration failed: MigrationFailed',
        'Job(migrate): Done(null)',
      ]);
      expect(error.formatted, 1);
    });

    test('ctx.log hands the callback over as it is', () {
      final error = MigrationFailed();
      stage.migrationError = error;
      final observer = Keeping();
      play(() => migration(observer: observer));

      expect(observer.messages, [isA<String Function()>()]);
      expect(error.formatted, 0);
    });

    test('the error alone is put into words by the observer', () {
      final unheard = MigrationFailed();
      play(() => Job<void>((ctx) async => ctx.log(unheard)));
      expect(unheard.formatted, 0);

      final heard = MigrationFailed();
      final lines = play(
        () => Job<void>(
          key: 'migrate',
          observer: Log(),
          (ctx) async => ctx.log(heard),
        ),
        outcomeObserved: false,
      );
      expect(lines.first, 'Job(migrate): MigrationFailed');
      expect(heard.formatted, 1);
    });
  });

  group('Where errors go', () {
    setUp(() => stage = Stage()..databaseLocked = true);

    test('the first attempt: each cancellation reaches the zone', () {
      expect(
        quotable(play(first.migrating, cancelAt: 10, outcomeObserved: false)),
        ['cancel', 'zone: DatabaseStopped'],
        reason: 'the outcome is not what sends it there',
      );
      expect(
        quotable(
          play(() => migratingObserved(Reporter()), cancelAt: 10),
        ),
        [
          'cancel',
          'onError: DatabaseStopped',
          'zone: DatabaseStopped',
          'outcome: Cancelled(manual)',
        ],
        reason: 'an observer that only watches moves nothing',
      );
      expect(
        play(first.migrating),
        ['outcome: Done(null)'],
        reason: 'uncancelled, the migration runs to its end',
      );
    });

    test('the filter keeps the stop at onError and asks nobody to answer', () {
      expect(
        withTheStopNamed(
          () => quotable(
            play(
              () => migratingObserved(Answerer(passedOn: true)),
              cancelAt: 10,
            ),
          ),
        ),
        ['cancel', 'onError: DatabaseStopped', 'outcome: Cancelled(manual)'],
      );
      expect(
        withTheStopNamed(
          () => quotable(
            play(first.migrating, cancelAt: 10, outcomeObserved: false),
          ),
        ),
        ['cancel'],
      );
    });

    test('the filter is not asked about a job nobody cancelled', () {
      // Somebody else has cancelled the token: the job goes on, and its body
      // fails with the stop.
      Job<void> stoppedByAnother() => Job<void>((ctx) async {
            final stop = CancelToken()..cancel();
            await ctx.join(() => database.migrate(stop));
          });

      expect(
        withTheStopNamed(() => play(stoppedByAnother, outcomeObserved: false)),
        ['zone: DatabaseStopped'],
      );
      expect(
        withTheStopNamed(() => play(stoppedByAnother)),
        ['outcome: Failed(DatabaseStopped)'],
      );
    });

    test('the filter does not name the failed open', () {
      expect(
        withTheStopNamed(() => quotable(play(openingReported, cancelAt: 10))),
        [
          'cancel',
          'onError: Bad state: database locked',
          'zone: Bad state: database locked',
          'outcome: Cancelled(manual)',
        ],
      );
    });

    test('the chained filter names its own error and the one before it', () {
      Job.isCancellationError = (error) => error is DatabaseException;
      try {
        nameTheStopAfter();
        final filter = Job.isCancellationError!;
        expect(filter(const DatabaseStopped()), isTrue);
        expect(filter(const DatabaseException()), isTrue);
        expect(filter(StateError('database locked')), isFalse);
      } finally {
        Job.isCancellationError = null;
      }
      try {
        nameTheStopAfter();
        final filter = Job.isCancellationError!;
        expect(filter(const DatabaseStopped()), isTrue);
        expect(filter(const DatabaseException()), isFalse);
      } finally {
        Job.isCancellationError = null;
      }
    });

    test('a filter that throws: the zone hears it, and the failure goes on',
        () {
      Job.isCancellationError = (error) => throw StateError('filter failed');
      try {
        expect(
          quotable(
            play(() => migratingObserved(Answerer()), cancelAt: 10),
          ),
          [
            'cancel',
            'onError: DatabaseStopped',
            'zone: Bad state: filter failed',
            'onUnanswered: DatabaseStopped',
            'outcome: Cancelled(manual)',
          ],
        );
      } finally {
        Job.isCancellationError = null;
      }
    });

    test('the filter does not see what Dart hands to the zone itself', () {
      Job<void> leaving() => Job<void>((ctx) async {
            final stop = CancelToken();
            ctx.onCancel(stop.cancel);
            unawaited(ctx.join(() => database.migrate(stop)));
            await ctx.abandonable(() => delay(50));
          });
      Job<void> stoppingLater() => Job<void>((ctx) async {
            // ignore: avoid_types_on_closure_parameters
            ctx.onCancel(() async {
              await delay(5);
              throw const DatabaseStopped();
            });
            await ctx.abandonable(() => delay(50));
          });

      for (final start in [leaving, stoppingLater]) {
        expect(
          withTheStopNamed(() => quotable(play(start, cancelAt: 10))),
          contains('zone: DatabaseStopped'),
        );
      }
    });

    test('a body that wraps its own cancellation: the zone, unless named', () {
      Job<void> wrapping({bool checksFirst = false}) => Job<void>((ctx) async {
            try {
              await ctx.abandonable(() => delay(30));
              // ignore: avoid_catches_without_on_clauses
            } catch (error) {
              if (checksFirst) {
                ctx.check();
              }
              throw AppException(error);
            }
          });

      expect(
        withTheStopNamed(() => quotable(play(wrapping, cancelAt: 10))),
        [
          'cancel',
          'zone: AppException(Cancelled(manual))',
          'outcome: Cancelled(manual)',
        ],
        reason: 'the filter of the stop does not name the wrapper',
      );
      nameTheWrapper();
      try {
        expect(
          quotable(play(wrapping, cancelAt: 10)),
          ['cancel', 'outcome: Cancelled(manual)'],
        );
      } finally {
        Job.isCancellationError = null;
      }
      expect(
        quotable(play(() => wrapping(checksFirst: true), cancelAt: 10)),
        ['cancel', 'outcome: Cancelled(manual)'],
        reason: 'the cancellation itself goes out',
      );
    });

    test('a catch that asks the job first loses a failure after the cancel',
        () {
      Job<void> opening({required bool checksFirst}) =>
          Job<void>(observer: Reporter(), (ctx) async {
            try {
              await ctx.join(Database.open);
              // ignore: avoid_catches_without_on_clauses
            } catch (error) {
              if (checksFirst) ctx.check();
              throw AppException(error);
            }
          });

      expect(
        quotable(play(() => opening(checksFirst: false), cancelAt: 10)),
        [
          'cancel',
          'onError: AppException(Bad state: database locked)',
          'zone: AppException(Bad state: database locked)',
          'outcome: Cancelled(manual)',
        ],
        reason: 'the open fails after the cancellation',
      );
      expect(
        quotable(play(() => opening(checksFirst: true), cancelAt: 10)),
        ['cancel', 'outcome: Cancelled(manual)'],
        reason: 'the open failed after the cancellation, and nobody heard it',
      );
    });

    // The two things of `ctx.runAll` the page names: the group learns of an
    // error of a cancellation from the body, and a branch nobody cancelled
    // fails with it.
    test('a branch cancelled from outside fails the group with its stop', () {
      CancelReason? reason;
      final lines = withTheStopNamed(
        () => quotable(
          play(() {
            final stopped = Job.deferred<void>((ctx) async {
              final stop = CancelToken();
              ctx.onCancel(stop.cancel);
              await ctx.join(() => database.migrate(stop));
            });
            unawaited(delay(10).then((_) => stopped.cancel()));
            return Job<void>((ctx) async {
              await ctx.runAll([
                stopped,
                Job.deferred<void>((ctx) => ctx.abandonable(() => delay(50)))
                  ..whenCancelled((cancelled) => reason = cancelled.reason),
              ]);
            });
          }),
        ),
      );

      expect(lines, ['outcome: Cancelled(handler: Job(): Cancelled(manual))']);
      expect(
        reason,
        isA<SiblingCancelReason>()
            .having((reason) => reason.cause, 'cause', isA<DatabaseStopped>()),
      );
    });

    test('a branch nobody cancelled throws its stop in place of a cancellation',
        () {
      Job<void> group() {
        final cancelled = Job.deferred<void>(
          (ctx) => ctx.abandonable(() => delay(50)),
        );
        unawaited(delay(10).then((_) => cancelled.cancel()));
        return Job<void>((ctx) async {
          await ctx.runAll([
            // Somebody else has cancelled its token, and the branch does not
            // take the stop the group asks for.
            Job.deferred<void>(cancellable: false, (ctx) async {
              final stop = CancelToken()..cancel();
              await ctx.join(() => database.migrate(stop));
            }),
            cancelled,
          ]);
        });
      }

      expect(
        withTheStopNamed(() => play(group)),
        ['outcome: Failed(DatabaseStopped)'],
      );
      expect(
        withTheStopNamed(() => play(group, outcomeObserved: false)),
        ['zone: DatabaseStopped'],
      );
    });

    test('the hooks do not observe the outcome, not even Log reading it', () {
      expect(
        play(() => failing(observer: Log()), outcomeObserved: false),
        [
          'Job(save): Failed(Bad state: disk full)',
          'zone: Bad state: disk full',
        ],
      );
    });

    test('done, value, then and ignoreFailure() observe the outcome', () {
      // A continuation takes the failure on, so it is ignored in its turn.
      final ways = <String, void Function(Job<void> job)>{
        'done': (job) => job.done.ignore(),
        'value': (job) => job.value.ignore(),
        'then': (job) => job.then<void>((ctx, _) async {}).ignoreFailure(),
        'ignoreFailure()': (job) => job.ignoreFailure(),
      };
      for (final MapEntry(key: way, value: observe) in ways.entries) {
        final lines = play(
          () {
            final job = failing();
            observe(job);
            return job;
          },
          outcomeObserved: false,
        );
        expect(lines, isEmpty, reason: way);
      }
      expect(
        play(failing, outcomeObserved: false),
        ['zone: Bad state: disk full'],
        reason: 'nothing observes it',
      );
    });

    test('a failure the job ends with: onError, and the zone if unobserved',
        () {
      expect(
        play(() => failing(observer: Reporter()), outcomeObserved: false),
        ['onError: Bad state: disk full', 'zone: Bad state: disk full'],
      );
      expect(
        play(() => failing(observer: Reporter())),
        [
          'onError: Bad state: disk full',
          'outcome: Failed(Bad state: disk full)',
        ],
      );
      expect(
        play(failing, outcomeObserved: false),
        ['zone: Bad state: disk full'],
      );
      expect(play(failing), ['outcome: Failed(Bad state: disk full)']);
    });

    Job<void> failingBeforeCancel({JobObserver? observer}) => Job<void>(
          observer: observer,
          (ctx) async {
            ctx
                .run(
                  Job.deferred<void>(
                    (ctx) => ctx.abandonable(() => delay(50)),
                  ),
                )
                .ignore();
            await delay(10);
            throw StateError('disk full');
          },
        );

    test('a cancellation after the failure: answered, whoever reads it', () {
      expect(
        quotable(
          play(
            () => failingBeforeCancel(observer: Answerer(passedOn: true)),
            cancelAt: 20,
            outcomeObserved: false,
          ),
        ),
        [
          'onError: Bad state: disk full',
          'cancel',
          'onUnanswered: Bad state: disk full',
          'zone: Bad state: disk full',
        ],
      );
      expect(
        quotable(
          play(
            () => failingBeforeCancel(observer: Answerer(passedOn: true)),
            cancelAt: 20,
          ),
        ),
        [
          'onError: Bad state: disk full',
          'cancel',
          'onUnanswered: Bad state: disk full',
          'zone: Bad state: disk full',
          'outcome: Cancelled(manual)',
        ],
        reason: 'the reader gets the cancellation, and the failure is answered '
            'all the same',
      );
      expect(
        quotable(
          play(failingBeforeCancel, cancelAt: 20, outcomeObserved: false),
        ),
        ['cancel', 'zone: Bad state: disk full'],
      );
      expect(
        quotable(play(failingBeforeCancel, cancelAt: 20)),
        ['cancel', 'zone: Bad state: disk full', 'outcome: Cancelled(manual)'],
      );
    });

    Job<void> failingBeforeCleanup({JobObserver? observer}) => Job<void>(
          observer: observer,
          (ctx) async {
            ctx.onDispose(() => delay(50));
            await delay(10);
            throw StateError('disk full');
          },
        );

    test('a cancellation while the cleanup runs: answered, whoever reads it',
        () {
      expect(
        quotable(
          play(
            () => failingBeforeCleanup(observer: Answerer(passedOn: true)),
            cancelAt: 20,
            outcomeObserved: false,
          ),
        ),
        [
          'onError: Bad state: disk full',
          'cancel',
          'onUnanswered: Bad state: disk full',
          'zone: Bad state: disk full',
        ],
      );
      expect(
        quotable(
          play(
            () => failingBeforeCleanup(observer: Answerer(passedOn: true)),
            cancelAt: 20,
          ),
        ),
        [
          'onError: Bad state: disk full',
          'cancel',
          'onUnanswered: Bad state: disk full',
          'zone: Bad state: disk full',
          'outcome: Cancelled(manual)',
        ],
        reason: 'the reader gets the cancellation, and the failure is answered '
            'all the same',
      );
      expect(
        quotable(
          play(failingBeforeCleanup, cancelAt: 20, outcomeObserved: false),
        ),
        ['cancel', 'zone: Bad state: disk full'],
      );
      expect(
        quotable(play(failingBeforeCleanup, cancelAt: 20)),
        ['cancel', 'zone: Bad state: disk full', 'outcome: Cancelled(manual)'],
      );
    });

    Job<void> childFailingBeforeCancel({JobObserver? observer}) => Job<void>(
          observer: observer,
          (ctx) async {
            await ctx.run(
              Job.deferred<void>((ctx) async {
                ctx
                    .run(
                      Job.deferred<void>(
                        (ctx) => ctx.abandonable(() => delay(50)),
                      ),
                    )
                    .ignore();
                await delay(10);
                throw StateError('disk full');
              }),
            );
          },
        );

    test('a child of run the same way: onError, then the zone', () {
      // The parent read the child's outcome, and the outcome carries the
      // cancellation: the failure is answered for, not dropped.
      expect(
        quotable(
          play(
            () => childFailingBeforeCancel(observer: Reporter()),
            cancelAt: 20,
          ),
        ),
        [
          'onError: Bad state: disk full',
          'cancel',
          'zone: Bad state: disk full',
          'outcome: Cancelled(manual)',
        ],
      );
      expect(
        quotable(play(childFailingBeforeCancel, cancelAt: 20)),
        ['cancel', 'zone: Bad state: disk full', 'outcome: Cancelled(manual)'],
      );
    });

    test('the envelope of .wait of a cancelled job: each failure goes on', () {
      // The open of the child fails at 20 ms, the cancellation comes at 30 ms,
      // and the future the body awaits on its own fails at 40 ms.
      Job<void> waiting({JobObserver? observer}) => Job<void>(
            observer: observer,
            (ctx) => [
              ctx.run(Job.deferred<void>((ctx) => ctx.join(Database.open))),
              delay(40).then<void>((_) => throw StateError('disk full')),
            ].wait,
          );

      expect(
        quotable(play(() => waiting(observer: Reporter()), cancelAt: 30)),
        [
          'onError: Bad state: database locked',
          'cancel',
          'onError: Bad state: database locked',
          'onError: Bad state: disk full',
          'zone: Bad state: database locked',
          'zone: Bad state: disk full',
          'outcome: Cancelled(manual)',
        ],
        reason: 'the child hears its own failure at 20 ms, the parent each '
            'error of the envelope',
      );
      expect(
        quotable(play(waiting, cancelAt: 30)),
        [
          'cancel',
          'zone: Bad state: database locked',
          'zone: Bad state: disk full',
          'outcome: Cancelled(manual)',
        ],
      );
    });

    Job<void> failingAfterCancel({JobObserver? observer}) => Job<void>(
          observer: observer,
          (ctx) async {
            try {
              await ctx.abandonable(() => delay(20));
            } on Cancelled {
              throw StateError('cleanup step failed');
            }
          },
        );

    test('a failure after the cancellation: onError, then the answer', () {
      expect(
        quotable(
          play(
            () => failingAfterCancel(observer: Reporter()),
            cancelAt: 10,
            outcomeObserved: false,
          ),
        ),
        [
          'cancel',
          'onError: Bad state: cleanup step failed',
          'zone: Bad state: cleanup step failed',
        ],
      );
      expect(
        quotable(
          play(
            () => failingAfterCancel(observer: Answerer()),
            cancelAt: 10,
            outcomeObserved: false,
          ),
        ),
        [
          'cancel',
          'onError: Bad state: cleanup step failed',
          'onUnanswered: Bad state: cleanup step failed',
        ],
      );
      expect(
        quotable(
          play(failingAfterCancel, cancelAt: 10, outcomeObserved: false),
        ),
        ['cancel', 'zone: Bad state: cleanup step failed'],
      );
    });

    test('a step of uncancellable or behind join: onError, then the answer',
        () {
      final ways = <String, Job<void> Function({JobObserver? observer})>{
        'uncancellable': ({observer}) =>
            Job<void>(observer: observer, (ctx) => ctx.uncancellable(pay)),
        'join': ({observer}) =>
            Job<void>(observer: observer, (ctx) => ctx.join(pay)),
      };
      for (final MapEntry(key: way, value: held) in ways.entries) {
        expect(
          quotable(play(() => held(observer: Reporter()), cancelAt: 10)),
          [
            'cancel',
            'onError: Bad state: payment failed',
            'zone: Bad state: payment failed',
            'outcome: Cancelled(manual)',
          ],
          reason: way,
        );
        expect(
          quotable(play(() => held(observer: Answerer()), cancelAt: 10)),
          [
            'cancel',
            'onError: Bad state: payment failed',
            'onUnanswered: Bad state: payment failed',
            'outcome: Cancelled(manual)',
          ],
          reason: way,
        );
        expect(
          quotable(play(held, cancelAt: 10)),
          [
            'cancel',
            'zone: Bad state: payment failed',
            'outcome: Cancelled(manual)',
          ],
          reason: way,
        );
      }
    });

    Job<void> failingOutside({JobObserver? observer}) => Job<void>(
          observer: observer,
          (ctx) async {
            ctx
              ..onDispose(() => throw StateError('cleanup'))
              ..onCancel(() => throw StateError('onCancel'))
              ..unattended(() async {
                await delay(5);
                throw StateError('unattended');
              });
            await ctx.abandonable(() async {
              await delay(30);
              throw StateError('late wait');
            });
          },
        )
          ..whenCancelled((_) => throw StateError('whenCancelled'))
          ..whenFinished((_) => throw StateError('whenFinished'));

    test('errors outside the body: onError, then the zone', () {
      const errors = [
        'Bad state: unattended',
        'Bad state: onCancel',
        'Bad state: whenCancelled',
        'Bad state: cleanup',
        'Bad state: whenFinished',
        'Bad state: late wait',
      ];
      List<String> starting(List<String> lines, String prefix) => [
            for (final line in lines)
              if (line.startsWith(prefix)) line,
          ];

      final heard = play(
        () => failingOutside(observer: Reporter()),
        cancelAt: 10,
        outcomeObserved: false,
      );
      expect(
        starting(heard, 'onError'),
        [for (final error in errors) 'onError: $error'],
      );
      expect(
        starting(heard, 'zone'),
        [for (final error in errors) 'zone: $error'],
        reason: 'an observer written to watch changes nowhere an error goes',
      );

      final answered = play(
        () => failingOutside(observer: Answering()),
        cancelAt: 10,
        outcomeObserved: false,
      );
      expect(
        starting(answered, 'onUnanswered'),
        [for (final error in errors) 'onUnanswered: $error'],
      );
      expect(
        starting(answered, 'zone'),
        isEmpty,
        reason: 'the errors stop where the observer answers',
      );

      final passedOn = play(
        () => failingOutside(observer: Answerer(passedOn: true)),
        cancelAt: 10,
        outcomeObserved: false,
      );
      expect(
        starting(passedOn, 'zone'),
        [for (final error in errors) 'zone: $error'],
        reason: 'super sends each one on to the zone as well',
      );

      final unheard = play(
        failingOutside,
        cancelAt: 10,
        outcomeObserved: false,
      );
      expect(
        starting(unheard, 'zone'),
        [for (final error in errors) 'zone: $error'],
      );
    });

    List<String> childNamed({
      required Object key,
      String Function()? describe,
      CancelReason reason = const ManualCancelReason(),
      JobObserver? observer,
      bool outcomeObserved = false,
    }) =>
        play(
          () {
            final child = Job.deferred<void>(
              key: key,
              describe: describe,
              (ctx) => ctx.abandonable(() => delay(50)),
            );
            unawaited(
              Future<void>.delayed(
                const Duration(milliseconds: 10),
                () => child.cancel(reason: reason),
              ),
            );
            return Job<void>(observer: observer, (ctx) => ctx.run(child));
          },
          outcomeObserved: outcomeObserved,
        );

    test(
        "a child's key, describe or Cancelled that fails to name the child: "
        'onError, then the zone', () {
      expect(
        childNamed(key: BrokenKey(), observer: Reporter()),
        ['onError: Bad state: key failed', 'zone: Bad state: key failed'],
      );
      expect(childNamed(key: BrokenKey()), ['zone: Bad state: key failed']);
      expect(
        childNamed(
          key: 'child',
          reason: const BrokenReason(),
          observer: Reporter(),
        ),
        ['onError: Bad state: name failed', 'zone: Bad state: name failed'],
      );
      expect(
        childNamed(
          key: 'child',
          describe: () => throw StateError('describe failed'),
          observer: Reporter(),
        ),
        [
          'onError: Bad state: describe failed',
          'zone: Bad state: describe failed',
        ],
      );
    });

    test('a child that fails to describe itself is named with a mark', () {
      const named = 'Job(child: <describe threw StateError>)';
      expect(
        childNamed(
          key: 'child',
          describe: () => throw StateError('describe failed'),
          outcomeObserved: true,
        ),
        [
          'zone: Bad state: describe failed',
          'outcome: Cancelled(handler: $named: Cancelled(manual))',
        ],
      );
    });

    test('a cancellation that fails to name itself falls back on words', () {
      expect(
        childNamed(
          key: 'child',
          reason: const BrokenReason(),
          outcomeObserved: true,
        ),
        [
          'zone: Bad state: name failed',
          'outcome: Cancelled(handler: child cancellation)',
        ],
      );
    });

    Job<void> cancelledOutside({JobObserver? observer}) => Job<void>(
          observer: observer,
          (ctx) async {
            ctx.onDispose(
              () => throw const Cancelled.by(
                reason: ManualCancelReason(),
              ),
            );
          },
        );

    test('a Cancelled thrown outside the body: onError or nobody', () {
      expect(
        play(() => cancelledOutside(observer: Reporter())),
        ['onError: Cancelled(manual)', 'outcome: Done(null)'],
        reason: 'the default body of onUnanswered drops a cancellation',
      );
      expect(
        play(() => cancelledOutside(observer: Answerer())),
        ['onError: Cancelled(manual)', 'outcome: Done(null)'],
        reason: 'an override is not asked about it either',
      );
      expect(play(cancelledOutside), ['outcome: Done(null)']);
    });

    test("the job's own cancellation out of work left behind: nobody", () {
      // Both checkpoints run after the job accepted the cancellation: one in
      // work of unattended, one in the action `abandonable` let go of.
      Job<void> checking({JobObserver? observer}) => Job<void>(
            observer: observer,
            (ctx) async {
              ctx.unattended(() async {
                await delay(20);
                ctx.check();
              });
              await ctx.abandonable(() async {
                await delay(20);
                ctx.check();
              });
            },
          );

      expect(
        quotable(play(() => checking(observer: Answerer()), cancelAt: 10)),
        ['cancel', 'outcome: Cancelled(manual)'],
      );
      expect(
        quotable(play(checking, cancelAt: 10)),
        ['cancel', 'outcome: Cancelled(manual)'],
      );
    });

    test('the same cancellation thrown by a callback: onError', () {
      Job<void> rethrowing({JobObserver? observer}) => Job<void>(
            observer: observer,
            (ctx) => ctx.abandonable(() => delay(50)),
          )..whenCancelled((cancelled) => throw cancelled);

      expect(
        quotable(play(() => rethrowing(observer: Answerer()), cancelAt: 10)),
        ['cancel', 'onError: Cancelled(manual)', 'outcome: Cancelled(manual)'],
      );
    });

    test('a join the body did not await: the zone, past the observer', () {
      Job<void> leaving({JobObserver? observer}) => Job<void>(
            observer: observer,
            (ctx) async {
              unawaited(
                ctx.join(() async {
                  await delay(20);
                  throw StateError('late join');
                }),
              );
            },
          );

      expect(
        play(() => leaving(observer: Answerer())),
        ['outcome: Done(null)', 'zone: Bad state: late join'],
      );
      expect(
        play(leaving),
        ['outcome: Done(null)', 'zone: Bad state: late join'],
      );
    });

    test('any call the body did not await: the zone, cancellation included',
        () {
      Job<void> walkingOn(
        JobObserver? observer,
        Future<void> Function(JobContext ctx) call,
      ) =>
          Job<void>(observer: observer, (ctx) async {
            unawaited(call(ctx));
            await delay(50);
          });

      expect(
        quotable(
          play(
            () => walkingOn(
              Answerer(),
              (ctx) => ctx.abandonable(() => delay(30)),
            ),
            cancelAt: 10,
          ),
        ),
        ['cancel', 'zone: Cancelled(manual)', 'outcome: Cancelled(manual)'],
      );
      for (final call in <Future<void> Function(JobContext ctx)>[
        (ctx) => ctx.abandonable(pay),
        (ctx) => ctx.uncancellable(pay),
      ]) {
        expect(
          play(() => walkingOn(Answerer(), call)),
          ['zone: Bad state: payment failed', 'outcome: Done(null)'],
        );
      }
    });

    test('a wait left behind by a body that ended: an abandoned action', () {
      Job<void> leaving({JobObserver? observer}) => Job<void>(
            observer: observer,
            (ctx) async => unawaited(ctx.abandonable(pay)),
          );

      expect(play(() => leaving(observer: Answerer())), [
        'outcome: Done(null)',
        'onError: Bad state: payment failed',
        'onUnanswered: Bad state: payment failed',
      ]);
      expect(
        play(leaving),
        ['outcome: Done(null)', 'zone: Bad state: payment failed'],
      );
    });

    test("a wait left behind, the job's cancellation after the body: nobody",
        () {
      // The table holds `abandonable` to the zone only until the body ends. A
      // body that cancels itself ends as the job accepts its cancellation, and
      // one from outside may arrive while the job waits for a child.
      expect(
        play(
          () => Job<void>(observer: Answerer(), (ctx) async {
            unawaited(ctx.abandonable(() => delay(30)));
            await delay(10);
            throw const Cancelled('gave up');
          }),
        ),
        ['outcome: Cancelled(handler: gave up)'],
      );
      expect(
        quotable(
          play(
            () => Job<void>(observer: Answerer(), (ctx) async {
              ctx
                  .run(
                    Job.deferred<void>(
                      (ctx) => ctx.abandonable(() => delay(50)),
                    ),
                  )
                  .ignore();
              unawaited(ctx.abandonable(() => delay(30)));
            }),
            cancelAt: 10,
          ),
        ),
        ['cancel', 'outcome: Cancelled(manual)'],
      );
    });

    test('a call the body did not await: the zone the body runs in', () {
      // Created in one zone and started from another: the error goes to
      // the starter's, where the body runs.
      final caught = <String>[];
      fakeAsync((async) {
        late DeferredJob<void> job;
        runZonedGuarded(
          () => job = Job.deferred<void>((ctx) async {
            unawaited(ctx.join(pay));
            await delay(50);
          }),
          (error, stackTrace) => caught.add('creation: $error'),
        );
        runZonedGuarded(
          job.start,
          (error, stackTrace) => caught.add('starter: $error'),
        );
        async.flushTimers();
      });

      expect(caught, ['starter: Bad state: payment failed']);
    });

    // A branch of `ctx.runAll` that fails on its own after the group has
    // thrown the first failure: its body told the observer where it was
    // caught, and what the group did not throw is nobody's outcome.
    Job<void> branchNotThrown({
      JobObserver? observer,
      bool secondIgnored = false,
    }) =>
        Job<void>(
          observer: observer,
          (ctx) async {
            final second = Job.deferred<int>(cancellable: false, (ctx) async {
              await ctx.abandonable(() => delay(20));
              throw StateError('second');
            });
            if (secondIgnored) {
              second.ignoreFailure();
            }
            try {
              await ctx.runAll([
                Job.deferred<int>((ctx) async {
                  await ctx.abandonable(() => delay(10));
                  throw StateError('first');
                }),
                second,
              ]);
            } on Object catch (_) {
              // The group throws the first one, and only that one.
            }
          },
        );

    test('a branch failure the group did not throw: onError, then the zone',
        () {
      expect(
        play(() => branchNotThrown(observer: Reporter())),
        [
          'onError: Bad state: first',
          'onError: Bad state: second',
          'zone: Bad state: second',
          'outcome: Done(null)',
        ],
      );
      expect(
        play(branchNotThrown),
        ['zone: Bad state: second', 'outcome: Done(null)'],
      );
    });

    test('ignoreFailure closes the second way for a failure no outcome carries',
        () {
      expect(
        quotable(
          play(
            () => failingBeforeCancel(observer: Answerer(passedOn: true))
              ..ignoreFailure(),
            cancelAt: 20,
            outcomeObserved: false,
          ),
        ),
        ['onError: Bad state: disk full', 'cancel'],
      );
      expect(
        play(
          () => branchNotThrown(
            observer: Answerer(passedOn: true),
            secondIgnored: true,
          ),
        ),
        [
          'onError: Bad state: first',
          'onError: Bad state: second',
          'outcome: Done(null)',
        ],
      );
    });

    // The line the page quotes after [lead], in the original and in the
    // translation.
    void quotes(Map<String, String> lead, String line) {
      for (final MapEntry(key: page, value: pattern) in lead.entries) {
        if (!File(page).existsSync()) {
          continue;
        }
        expect(
          RegExp('$pattern`([^`]+)`')
              .firstMatch(File(page).readAsStringSync())!
              .group(1),
          line,
          reason: page,
        );
      }
    }

    test('the debug channel prints the error of the first attempt', () {
      final lines = debugged(
        () => play(first.migrating, cancelAt: 10, outcomeObserved: false),
      );

      expect(lines, [
        'Job() started',
        'cancel',
        'cancel Job(): Cancelled(manual)',
        'Job() error: DatabaseStopped',
        'Job() finished: Cancelled(manual)',
        'Job() error nobody answered for: DatabaseStopped',
        'Job() error went to the zone: DatabaseStopped',
        'zone: DatabaseStopped',
      ]);
    });

    test('with the filter it says why the error went no further', () {
      final lines = withTheStopNamed(
        () => debugged(
          () => play(first.migrating, cancelAt: 10, outcomeObserved: false),
        ),
      );

      expect(lines, [
        'Job() started',
        'cancel',
        'cancel Job(): Cancelled(manual)',
        'Job() error: DatabaseStopped',
        'Job() finished: Cancelled(manual)',
        'Job() kept a cancellation error out of the answer: DatabaseStopped',
      ]);
      quotes(
        {
          'doc/observing.md': r'give\s+way\s+to\s+one:\s+',
          '../../docs/ru/async_job/observing.md':
              r'канал\s+печатает\s+одну:\s+',
        },
        lines.last,
      );
    });

    test('it prints what the observer hears, whether there is one or not', () {
      expect(
        debugged(
          () => play(
            first.migrating,
            cancelAt: 10,
            outcomeObserved: false,
          ),
        ).where((line) => line.contains(' error: ')),
        ['Job() error: DatabaseStopped'],
      );
      expect(
        debugged(
          () => play(openingReported, cancelAt: 10, outcomeObserved: false),
        ).where(
          (line) => line.contains(' error: ') || line.startsWith('onError:'),
        ),
        [
          'Job() error: Bad state: database locked',
          'onError: Bad state: database locked',
        ],
      );
    });

    test('a ParallelWaitError takes one line, and onError hears each failure',
        () {
      final lines = debugged(
        () => play(
          () => Job<void>(observer: Reporter(), (ctx) async {
            await [
              ctx.join<void>(() async {
                await delay(20);
                throw StateError('a');
              }),
              ctx.join<void>(() async {
                await delay(30);
                throw StateError('b');
              }),
            ].wait;
          }),
          cancelAt: 10,
          outcomeObserved: false,
        ),
      );

      expect(
        lines.where(
          (line) => line.contains(' error: ') || line.startsWith('onError:'),
        ),
        [
          startsWith('Job() error: ParallelWaitError'),
          'onError: Bad state: a',
          'onError: Bad state: b',
        ],
      );
    });

    test('and says so when an error goes on to the zone', () {
      // The second row of the table, then the first: each line of the zone
      // has the channel's word about it right before it.
      for (final lines in [
        debugged(() => play(openingReported, cancelAt: 10)),
        debugged(() => play(failing, outcomeObserved: false)),
      ]) {
        final zone = lines.indexWhere((line) => line.startsWith('zone:'));
        expect(zone, isNot(-1));
        expect(lines[zone - 1], contains('went to the zone'), reason: '$lines');
      }
    });
  });

  group('Work the job does not wait for', () {
    test('without an observer the work goes straight to the zone', () {
      expect(
        play(() => sendingHandedOver(null)),
        ['outcome: Done(null)', 'zone: Bad state: analytics offline'],
      );
    });

    test('the job neither waits for the work nor cancels it', () {
      final lines = play(
        () => Job<void>((ctx) async {
          ctx.unattended(() async {
            await delay(50);
            print('the work ends at $now ms');
          });
          await ctx.abandonable(() => delay(100));
        }),
        cancelAt: 10,
      );

      expect(quotable(lines), [
        'cancel',
        'outcome: Cancelled(manual)',
        'the work ends at 50 ms',
      ]);
    });

    Job<void> sending(FutureOr<void> Function(JobContext ctx) send) =>
        Job<void>(observer: Reporter(), (ctx) async => send(ctx));

    test('a future made outside never comes back in there', () {
      final lines = play(
        () => sending((ctx) {
          final sending = analytics.send('loaded');
          ctx.unattended(() async {
            try {
              await sending;
            } on Object catch (error) {
              print('caught: $error');
            }
          });
        }),
      );

      expect(lines, [
        'outcome: Done(null)',
        'zone: Bad state: analytics offline',
      ]);
    });

    test('a future made in there hangs the job that awaits it', () {
      final lines = play(
        () => sending((ctx) async {
          late Future<void> sending;
          ctx.unattended(() {
            sending = analytics.send('loaded');
          });
          try {
            await ctx.abandonable(() => sending);
          } on Object catch (error) {
            print('caught: $error');
          }
        }),
      );

      expect(lines, [
        'onError: Bad state: analytics offline',
        'zone: Bad state: analytics offline',
      ]);
    });

    test('a job started inside the callback is outside the boundary', () {
      // Started inside the work of another job: the body runs in the zone
      // that work was started from, not in the work's, and the observer of
      // the other job hears nothing.
      final caught = <String>[];
      final printed = <String>[];
      runZoned(
        () => fakeAsync((async) {
          late DeferredJob<void> job;
          runZonedGuarded(
            () => job = Job.deferred<void>((ctx) async {
              unawaited(ctx.join(pay));
              await delay(50);
            }),
            (error, stackTrace) => caught.add('creation: $error'),
          );
          runZonedGuarded(
            () => Job<void>(observer: Answerer(), (ctx) async {
              ctx.unattended(job.start);
              await ctx.abandonable(() => delay(1));
            }),
            (error, stackTrace) => caught.add('work started from: $error'),
          );
          async.flushTimers();
        }),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      expect(caught, ['work started from: Bad state: payment failed']);
      expect(printed, isEmpty);
    });
  });

  group('Answering for errors', () {
    test('each failure of an envelope is asked about on its own', () {
      expect(play(saving), [
        'outcome: Done(null)',
        'onUnanswered: DatabaseException',
        'zone: Bad state: analytics offline',
      ]);
      Job<void> leaving({JobObserver? observer}) =>
          Job<void>(observer: observer, (ctx) async {
            ctx.unattended(() => [saveDraft(), sendAnalytics()].wait);
          });
      expect(
        play(leaving),
        [
          'outcome: Done(null)',
          'zone: DatabaseException',
          'zone: Bad state: analytics offline',
        ],
        reason: 'without an observer the zone hears them one at a time too',
      );
      expect(
        play(() => leaving(observer: Reporter())),
        [
          'outcome: Done(null)',
          'onError: DatabaseException',
          'onError: Bad state: analytics offline',
          'zone: DatabaseException',
          'zone: Bad state: analytics offline',
        ],
        reason: 'onError hears them one at a time as well',
      );
    });

    test('the outcome keeps the envelope, and Job.visitErrors walks it', () {
      late Job<void> job;
      final printed = play(
        () {
          job = Job<void>(observer: Reporter(), (ctx) async {
            await [saveDraft(), sendAnalytics()].wait;
          });
          unawaited(readingTheOutcome(job));
          return job;
        },
        outcomeObserved: false,
      );

      expect(printed, [
        'onError: DatabaseException',
        'onError: Bad state: analytics offline',
        'failed: DatabaseException',
        'failed: Bad state: analytics offline',
      ]);
      expect(
        (job.outcome! as Failed).error,
        isA<ParallelWaitError<Object?, Object?>>(),
      );
    });

    test('nobody is asked about a cancellation, alone or in an envelope', () {
      Job<void> leaving(JobObserver observer) =>
          Job<void>(observer: observer, (ctx) async {
            ctx
              ..unattended(() async {
                await [
                  Future<void>.error(const Cancelled('a'), StackTrace.empty),
                  Future<void>.error(const Cancelled('b'), StackTrace.empty),
                ].wait;
              })
              ..unattended(() async {
                await [
                  Future<void>.value(),
                  Future<void>.error(const Cancelled('c'), StackTrace.empty),
                ].wait;
              });
          });

      expect(play(() => leaving(DatabaseErrors())), ['outcome: Done(null)']);
      expect(play(() => leaving(Answering())), ['outcome: Done(null)']);
    });

    test('an error that comes alone is asked about as it is', () {
      Job<void> leaving(Future<void> Function() work) =>
          Job<void>(observer: DatabaseErrors(), (ctx) async {
            ctx.unattended(work);
          });

      expect(
        play(() => leaving(saveDraft)),
        ['outcome: Done(null)', 'onUnanswered: DatabaseException'],
      );
      expect(
        play(() => leaving(sendAnalytics)),
        ['outcome: Done(null)', 'zone: Bad state: analytics offline'],
      );
      expect(
        play(() => leaving(() async => throw const Cancelled('alone'))),
        ['outcome: Done(null)'],
        reason: 'nobody is asked about a Cancelled that comes alone',
      );
    });

    test('the override answers for a child of a child, the zone for the app',
        () {
      // The observer is the root's; the child and the child's child
      // inherit it.
      Job<void> tree(JobObserver observer) => Job<void>(
            observer: observer,
            (ctx) => ctx.run(
              Job.deferred<void>(
                (ctx) => ctx.run(
                  Job.deferred<void>((ctx) async {
                    ctx
                        .run(
                          Job.deferred<void>(
                            (ctx) => ctx.abandonable(() => delay(50)),
                          ),
                        )
                        .ignore();
                    await delay(10);
                    throw StateError('disk full');
                  }),
                ),
              ),
            ),
          );

      expect(quotable(play(() => tree(Answering()), cancelAt: 20)), [
        'cancel',
        'onUnanswered: Bad state: disk full',
        'outcome: Cancelled(manual)',
      ]);
      expect(quotable(play(() => tree(Reporter()), cancelAt: 20)), [
        'onError: Bad state: disk full',
        'cancel',
        'zone: Bad state: disk full',
        'outcome: Cancelled(manual)',
      ]);
    });
  });

  group('Several observers', () {
    Job<void> sending(JobObserver observer) => Job<void>(
          observer: observer,
          (ctx) async {
            ctx.unattended(() => analytics.send('loaded'));
          },
        );

    test('a call that throws switches off the next, unless it is wrapped', () {
      expect(play(() => sending(HandedOn(Throwing(), Reporter()))), [
        'outcome: Done(null)',
        'zone: Bad state: reporter down',
        'onUnanswered: Bad state: analytics offline',
      ]);
      expect(
        play(
          () => sending(
            JobObserver.all([Throwing(), Reporter(), Crashes()]),
          ),
        ),
        [
          'outcome: Done(null)',
          'zone: Bad state: reporter down',
          'onError: Bad state: analytics offline',
          'onUnanswered: Bad state: analytics offline',
        ],
      );
    });

    test('with nobody answering, the zone, as for one that does not', () {
      expect(
        play(() => sending(JobObserver.all([Reporter(), Reporter()]))),
        [
          'outcome: Done(null)',
          'onError: Bad state: analytics offline',
          'onError: Bad state: analytics offline',
          'zone: Bad state: analytics offline',
        ],
      );
    });

    test('two that answer, or one twice, and it throws', () {
      final reporter = Reporter();
      expect(
        () => JobObserver.all([Crashes(), Crashes()]),
        throwsArgumentError,
      );
      expect(
        () => JobObserver.all([reporter, reporter]),
        throwsArgumentError,
      );
    });

    test('inside the list of another, it answers when one inside it does', () {
      expect(
        play(
          () => sending(
            JobObserver.all([
              Reporter(),
              JobObserver.all([Crashes()]),
            ]),
          ),
        ),
        [
          'outcome: Done(null)',
          'onError: Bad state: analytics offline',
          'onUnanswered: Bad state: analytics offline',
        ],
      );
    });
  });

  group('Testing', () {
    setUp(() => stage = Stage());

    const testingPage = 'doc/testing.md';
    const page = 'test/support/observing_page.dart';
    const firstAttempts = 'test/support/observing_first_attempts.dart';

    test('the page has no fence the checks do not read', () {
      expect(strayFences(testingPage), isEmpty);
    });

    const holders = {
      '### The first attempt': firstAttempts,
      '### Time moved by the test': page,
    };
    for (final MapEntry(key: heading, value: holder) in holders.entries) {
      test('the code under "$heading" is a run of lines of $holder', () {
        expect(codeMissingFrom(testingPage, holder, under: heading), isEmpty);
      });
    }

    test('every piece of code on the page is a run of lines of these files',
        () {
      expect(
        codeMissingFrom(testingPage, page, alsoIn: [firstAttempts]),
        isEmpty,
      );
    });

    group('the first attempt, as the page writes it,', () {
      first.cancelledOpenAwaited(test, expect);
    });

    test('the first attempt runs neither of its checks', () async {
      final checked = <Object?>[];
      first.cancelledOpenAwaited(
        (description, body) => body(),
        (actual, matcher) => checked.add(actual),
      );
      await pumpEventQueue();

      expect(checked, isEmpty);
    });

    test('written as an arrow, the test waits for what never completes', () {
      final waited = fakeAsync((async) async {
        final job = Job<Database>((ctx) => ctx.join(Database.open));

        async.elapse(const Duration(milliseconds: 10));
        await job.cancel();
      });

      expect(waited, doesNotComplete);
    });

    group('time moved by the test, as the page writes it,', () {
      timeMovedByTheTest(test, expect);
    });

    test('time moved by the test runs both of its checks', () {
      final checked = <Object?>[];
      timeMovedByTheTest(
        (description, body) => body(),
        (actual, matcher) {
          checked.add(actual);
          expect(actual, matcher);
        },
      );

      expect(checked, [isA<Cancelled>(), 1]);
    });

    test('flushMicrotasks is enough to start a job', () {
      fakeAsync((async) {
        var started = false;
        Job<void>((ctx) async => started = true);

        expect(started, isFalse);
        async.flushMicrotasks();
        expect(started, isTrue);
      });
    });
  });

  // Last: the tests of a file share the isolate, and a filter left behind
  // would silence the failures of every test after it.
  test('the filter of cancellation errors is left as it was found', () {
    expect(Job.isCancellationError, isNull);
  });
}
