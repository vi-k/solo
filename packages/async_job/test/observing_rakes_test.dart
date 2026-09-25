@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

/// The first attempts of `doc/observing.md`, and what each one costs.
///
/// A section of the page opens with the version the names lead to and shows
/// what that version does. The page has no bench, so the code is repeated
/// here as it stands there, together with the rules the page states in
/// prose and in its table, and the last test holds the lines the page
/// quotes to the lines these tests print.

/// What each `text` block of the page says, in the order of the page.
const quoted = [
  [
    'Job(load): Done(3)',
  ],
  [
    'cancel',
    'outcome: Cancelled(manual)',
  ],
  [
    'cancel',
    'onError: Bad state: database locked',
    'outcome: Cancelled(manual)',
  ],
  [
    'outcome: Done(null)',
    'zone: Bad state: analytics offline',
  ],
  [
    'outcome: Done(null)',
    'onError: Bad state: analytics offline',
    'zone: Bad state: analytics offline',
  ],
];

/// What the observers and the code around the job print.
final printed = <String>[];

void say(String line) => printed.add(line);

/// The fake time of the running [play].
late FakeAsync time;

int get now => time.elapsed.inMilliseconds;

/// The observer of the page's first section.
final class Log extends JobObserver {
  @override
  void onFinish(Job<Object?> job) => say('$job: ${job.outcome}');

  @override
  void onLog(Job<Object?> job, Object? message) {
    final data = message is Object? Function() ? message() : message;
    say('$job: $data');
  }
}

/// The observer of the page's section on where errors go.
final class Reporter extends JobObserver {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      say('onError: $error');
}

/// An observer that answers for the errors no outcome carries, the way the
/// page overrides `onUnanswered`, and, with [passedOn], hands each one on
/// to `super` as well.
final class Answering extends JobObserver {
  final bool passedOn;

  Answering({this.passedOn = false});

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      say('onError: $error');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    say('onUnanswered: $error');
    if (passedOn) {
      super.onUnanswered(job, error, stackTrace);
    }
  }
}

/// Every hook, for the rules the page states about them.
final class Hooks extends JobObserver {
  Hooks([this.name = '']);

  final String name;

  @override
  void onStart(Job<Object?> job) => say('${name}onStart $job');

  @override
  void onFinish(Job<Object?> job) => say('${name}onFinish $job');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      say('${name}onError: $error');

  @override
  void onLog(Job<Object?> job, Object? message) =>
      say('${name}onLog: $message');
}

/// A hook that throws, next to two that do not.
final class ThrowingStart extends JobObserver {
  @override
  void onStart(Job<Object?> job) => throw StateError('onStart failed');

  @override
  void onLog(Job<Object?> job, Object? message) => say('onLog: $message');

  @override
  void onFinish(Job<Object?> job) => say('onFinish $job');
}

/// An observer that keeps what `ctx.log` handed it.
final class Keeping extends JobObserver {
  final messages = <Object?>[];

  @override
  void onLog(Job<Object?> job, Object? message) => messages.add(message);
}

/// The observer the page describes for timing a cancellation.
final class SlowCancellations extends JobObserver {
  final _acceptedAt = Expando<int>('cancellation');

  @override
  void onStart(Job<Object?> job) =>
      job.whenCancelled((_) => _acceptedAt[job] = now);

  @override
  void onFinish(Job<Object?> job) {
    final acceptedAt = _acceptedAt[job];
    if (acceptedAt != null) {
      say('$job ran ${now - acceptedAt} ms past its cancellation');
    }
  }
}

Future<int> load() async {
  await delay(10);
  return 3;
}

/// Opens in 20 ms, or fails then when [locked].
final class Database {
  static bool locked = false;

  static Future<Database> open() async {
    await delay(20);
    if (locked) {
      throw StateError('database locked');
    }
    return Database();
  }

  Future<void> close() async {}
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

/// How the migration of the cancellation page stops at its token.
final class DatabaseStopped implements Exception {
  const DatabaseStopped();

  @override
  String toString() => 'DatabaseStopped';
}

final class Analytics {
  Future<void> send(String event) async {
    await delay(10);
    throw StateError('analytics offline');
  }
}

final analytics = Analytics();

/// A key that cannot be put into words.
final class BrokenKey {
  @override
  String toString() => throw StateError('key failed');
}

/// Starts a job under fake time and returns what was printed.
///
/// The code around the job prints the outcome as `outcome:` unless
/// [outcomeObserved] is false, and cancels at [cancelAt] ms, printing
/// `cancel`. An error that reaches the zone is printed as `zone:`.
List<String> play(
  Job<Object?> Function() start, {
  int? cancelAt,
  bool outcomeObserved = true,
}) {
  printed.clear();
  runZonedGuarded(
    () => fakeAsync((async) {
      time = async;
      final job = start();
      if (outcomeObserved) {
        unawaited(job.done.then((outcome) => say('outcome: $outcome')));
      }
      if (cancelAt != null) {
        async.elapse(Duration(milliseconds: cancelAt));
        say('cancel');
        final calledAt = now;
        unawaited(
          job.cancel().then(
                (_) => say('cancel() returned after ${now - calledAt} ms'),
              ),
        );
      }
      async.flushTimers();
    }),
    (error, stackTrace) => say('zone: $error'),
  );
  return printed.toList();
}

/// The lines of [play] that the page quotes: `cancel()` timing is not one.
List<String> quotable(List<String> lines) => [
      for (final line in lines)
        if (!line.startsWith('cancel()')) line,
    ];

void main() {
  group('Observer', () {
    test('the page prints how the job ended', () {
      final lines = play(
        () => Job<int>(
          key: 'load',
          observer: Log(),
          (ctx) => ctx.wait(load),
        ),
        outcomeObserved: false,
      );

      expect(lines, quoted[0]);
    });

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

    test('the four string representations', () {
      Job<void> job({Object? key, String Function()? describe}) =>
          Job<void>(key: key, describe: describe, (ctx) async {});

      fakeAsync((async) {
        expect(job(key: 'load').toString(), 'Job(load)');
        expect(
          job(key: 'load', describe: () => 'user 7').toString(),
          'Job(load: user 7)',
        );
        expect(job(describe: () => 'user 7').toString(), 'Job(user 7)');
        expect(job().toString(), 'Job()');
        async.flushTimers();
      });
    });
  });

  group('Timing a cancellation', () {
    List<String> timed(Future<void> Function(JobContext ctx) body) => play(
          () => Job<void>(
            key: 'slow',
            observer: SlowCancellations(),
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

    test('the same call through ctx.wait shows 0 ms', () {
      final lines = timed((ctx) => ctx.wait(() => delay(300)));

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
        await ctx.wait(() => delay(300));
      });

      expect(lines, [
        'cancel',
        'Job(slow) ran 0 ms past its cancellation',
        'cancel() returned after 90 ms',
      ]);
    });
  });

  group('A message for the log', () {
    test('a string is built without an observer', () {
      final error = MigrationFailed();
      play(
        () => Job<void>(
          key: 'migrate',
          (ctx) async => ctx.log('migration failed: $error'),
        ),
      );

      expect(error.formatted, 1);
    });

    test('a callback is not called without an observer', () {
      final error = MigrationFailed();
      play(
        () => Job<void>(
          key: 'migrate',
          (ctx) async => ctx.log(() => 'migration failed: $error'),
        ),
      );

      expect(error.formatted, 0);
    });

    test('Log calls the callback and prints what it returns', () {
      final error = MigrationFailed();
      final lines = play(
        () => Job<void>(
          key: 'migrate',
          observer: Log(),
          (ctx) async => ctx.log(() => 'migration failed: $error'),
        ),
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
      final observer = Keeping();
      play(
        () => Job<void>(
          key: 'migrate',
          observer: observer,
          (ctx) async => ctx.log(() => 'migration failed: $error'),
        ),
      );

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
    setUp(() => Database.locked = true);
    tearDown(() => Database.locked = false);

    Job<Database> open({JobObserver? observer}) => Job<Database>(
          observer: observer,
          (ctx) => ctx.join(
            Database.open,
            discard: (database) => database.close(),
          ),
        );

    test('without an observer the failed open reaches nobody', () {
      final lines = play(open, cancelAt: 10);

      expect(quotable(lines), quoted[1]);
    });

    test('the observer hears it', () {
      final lines = play(() => open(observer: Reporter()), cancelAt: 10);

      expect(quotable(lines), quoted[2]);
    });

    test('nobody hears it even when the outcome is left unobserved', () {
      final lines = play(open, cancelAt: 10, outcomeObserved: false);

      expect(quotable(lines), ['cancel']);
    });

    // The stop the page names: the operation stops at the job's token and
    // throws its own error, the way the migration of the cancellation page
    // does.
    Job<void> stoppedAtToken({JobObserver? observer}) => Job<void>(
          observer: observer,
          (ctx) async {
            var stopped = false;
            ctx.onCancel(() => stopped = true);
            await ctx.join(() async {
              await delay(20);
              if (stopped) {
                throw const DatabaseStopped();
              }
            });
          },
        );

    test('a stop at the token goes the same way: onError or nobody', () {
      expect(
        quotable(
          play(
            () => stoppedAtToken(observer: Reporter()),
            cancelAt: 10,
            outcomeObserved: false,
          ),
        ),
        ['cancel', 'onError: DatabaseStopped'],
      );
      expect(
        quotable(play(stoppedAtToken, cancelAt: 10, outcomeObserved: false)),
        ['cancel'],
      );
    });

    Job<void> failing({JobObserver? observer}) => Job<void>(
          observer: observer,
          (ctx) async {
            await delay(10);
            throw StateError('disk full');
          },
        );

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
                .run(Job.deferred<void>((ctx) => ctx.wait(() => delay(50))))
                .ignore();
            await delay(10);
            throw StateError('disk full');
          },
        );

    test('a cancellation after the failure: the same as the failure', () {
      expect(
        quotable(
          play(
            () => failingBeforeCancel(observer: Reporter()),
            cancelAt: 20,
            outcomeObserved: false,
          ),
        ),
        [
          'onError: Bad state: disk full',
          'cancel',
          'zone: Bad state: disk full',
        ],
      );
      expect(
        quotable(
          play(
            () => failingBeforeCancel(observer: Reporter()),
            cancelAt: 20,
          ),
        ),
        [
          'onError: Bad state: disk full',
          'cancel',
          'outcome: Cancelled(manual)',
        ],
      );
      expect(
        quotable(
          play(failingBeforeCancel, cancelAt: 20, outcomeObserved: false),
        ),
        ['cancel', 'zone: Bad state: disk full'],
      );
    });

    Job<void> failingAfterCancel({JobObserver? observer}) => Job<void>(
          observer: observer,
          (ctx) async {
            try {
              await ctx.wait(() => delay(20));
            } on Cancelled {
              throw StateError('cleanup step failed');
            }
          },
        );

    test('a failure after the cancellation: onError or nobody', () {
      expect(
        quotable(
          play(
            () => failingAfterCancel(observer: Reporter()),
            cancelAt: 10,
            outcomeObserved: false,
          ),
        ),
        ['cancel', 'onError: Bad state: cleanup step failed'],
      );
      expect(
        quotable(
          play(failingAfterCancel, cancelAt: 10, outcomeObserved: false),
        ),
        ['cancel'],
      );
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
            await ctx.wait(() async {
              await delay(30);
              throw StateError('late wait');
            });
          },
        )..whenCancelled((_) => throw StateError('whenCancelled'));

    test('errors outside the body: onError, then the zone', () {
      const errors = [
        'Bad state: unattended',
        'Bad state: onCancel',
        'Bad state: whenCancelled',
        'Bad state: cleanup',
        'Bad state: late wait',
      ];

      final heard = play(
        () => failingOutside(observer: Reporter()),
        cancelAt: 10,
        outcomeObserved: false,
      );
      expect(
        [
          for (final line in heard)
            if (line.startsWith('onError')) line,
        ],
        [for (final error in errors) 'onError: $error'],
      );
      expect(
        [
          for (final line in heard)
            if (line.startsWith('zone')) line,
        ],
        [for (final error in errors) 'zone: $error'],
        reason: 'an observer written to watch changes nowhere an error goes',
      );

      final answered = play(
        () => failingOutside(observer: Answering()),
        cancelAt: 10,
        outcomeObserved: false,
      );
      expect(
        [
          for (final line in answered)
            if (line.startsWith('onUnanswered')) line,
        ],
        [for (final error in errors) 'onUnanswered: $error'],
      );
      expect(
        answered.where((line) => line.startsWith('zone')),
        isEmpty,
        reason: 'an override of onUnanswered is where they stop',
      );

      final passedOn = play(
        () => failingOutside(observer: Answering(passedOn: true)),
        cancelAt: 10,
        outcomeObserved: false,
      );
      expect(
        [
          for (final line in passedOn)
            if (line.startsWith('zone')) line,
        ],
        [for (final error in errors) 'zone: $error'],
        reason: 'super sends each one on to the zone as well',
      );

      final unheard = play(
        failingOutside,
        cancelAt: 10,
        outcomeObserved: false,
      );
      expect(
        [
          for (final line in unheard)
            if (line.startsWith('zone')) line,
        ],
        [for (final error in errors) 'zone: $error'],
      );
    });

    List<String> childDescribed({JobObserver? observer}) => play(
          () {
            final child = Job.deferred<void>(
              key: BrokenKey(),
              (ctx) => ctx.wait(() => delay(50)),
            );
            unawaited(
              Future<void>.delayed(
                const Duration(milliseconds: 10),
                child.cancel,
              ),
            );
            return Job<void>(observer: observer, (ctx) => ctx.run(child));
          },
          outcomeObserved: false,
        );

    test(
        "a child's cancellation description that fails: onError, then the "
        'zone', () {
      expect(
        childDescribed(observer: Reporter()),
        ['onError: Bad state: key failed', 'zone: Bad state: key failed'],
      );
      expect(childDescribed(), ['zone: Bad state: key failed']);
    });

    Job<void> cancelledOutside({JobObserver? observer}) => Job<void>(
          observer: observer,
          (ctx) async {
            ctx.onDispose(
              () => throw const Cancelled.by(
                reason: ManualCancelReason(),
                started: true,
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
        play(() => cancelledOutside(observer: Answering())),
        [
          'onError: Cancelled(manual)',
          'onUnanswered: Cancelled(manual)',
          'outcome: Done(null)',
        ],
        reason: 'an override is asked about it all the same',
      );
      expect(play(cancelledOutside), ['outcome: Done(null)']);
    });
    // A branch of `ctx.runAll` that fails on its own after the group has
    // thrown the first failure: its body told the observer where it was
    // caught, and what the group did not throw is nobody's outcome.
    Job<void> branchNotThrown({JobObserver? observer}) => Job<void>(
          observer: observer,
          (ctx) async {
            try {
              await ctx.runAll([
                Job.deferred<int>((ctx) async {
                  await ctx.wait(() => delay(10));
                  throw StateError('first');
                }),
                Job.deferred<int>(cancellable: false, (ctx) async {
                  await ctx.wait(() => delay(20));
                  throw StateError('second');
                }),
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
  });

  group('Work the job does not wait for', () {
    Job<void> sending(
      FutureOr<void> Function(JobContext ctx) send, {
      bool reported = true,
    }) =>
        Job<void>(
          observer: reported ? Reporter() : null,
          (ctx) async => send(ctx),
        );

    test('unawaited sends the failure past the observer to the zone', () {
      final lines = play(
        () => sending((ctx) {
          unawaited(analytics.send('loaded'));
        }),
      );

      expect(lines, quoted[3]);
    });

    test('unattended hands it to the observer, after the job is over', () {
      final lines = play(
        () => sending((ctx) {
          ctx.unattended(() => analytics.send('loaded'));
        }),
      );

      expect(lines, quoted[4]);
    });

    test('without an observer unattended goes to the creation zone', () {
      final lines = play(
        () => sending(
          (ctx) {
            ctx.unattended(() => analytics.send('loaded'));
          },
          reported: false,
        ),
      );

      expect(lines, quoted[3]);
    });

    test('a future made outside never comes back in there', () {
      final lines = play(
        () => sending((ctx) {
          final sending = analytics.send('loaded');
          ctx.unattended(() async {
            try {
              await sending;
            } on Object catch (error) {
              say('caught: $error');
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
            await ctx.wait(() => sending);
          } on Object catch (error) {
            say('caught: $error');
          }
        }),
      );

      expect(lines, [
        'onError: Bad state: analytics offline',
        'zone: Bad state: analytics offline',
      ]);
    });
  });

  group('Testing', () {
    test('awaiting cancel() inside fakeAsync checks nothing', () {
      var checked = false;

      expect(
        () => fakeAsync((async) async {
          var closed = 0;
          final job = Job<Database>(
            (ctx) => ctx.join(
              Database.open,
              discard: (db) {
                closed++;
                return db.close();
              },
            ),
          );

          async.elapse(const Duration(milliseconds: 10));
          await job.cancel();

          checked = true;
          expect(closed, 0); // wrong, and never run
        }),
        returnsNormally,
      );
      expect(checked, isFalse);
    });

    test('written as an arrow, the test waits for what never completes', () {
      final waited = fakeAsync((async) async {
        final job = Job<Database>((ctx) => ctx.join(Database.open));

        async.elapse(const Duration(milliseconds: 10));
        await job.cancel();
      });

      expect(waited, doesNotComplete);
    });

    test('a cancelled open still closes what it opened', () {
      fakeAsync((async) {
        var closed = 0;
        final job = Job<Database>(
          (ctx) => ctx.join(
            Database.open,
            discard: (db) {
              closed++;
              return db.close();
            },
          ),
        );

        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore(); // nothing awaits inside `fakeAsync`
        async.flushTimers();

        expect(job.outcome, isA<Cancelled>());
        expect(closed, 1); // what the test is named for
      });
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

  test('the page quotes what these tests print', () {
    final page = File('doc/observing.md').readAsStringSync();
    final blocks = RegExp(r'```text\n(.*?)\n```', dotAll: true)
        .allMatches(page)
        .map((match) => match.group(1)!.split('\n'))
        .toList();

    expect(blocks, quoted);
  });
}
