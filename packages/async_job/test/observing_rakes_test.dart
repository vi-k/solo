// `doc/observing.md` and `doc/testing.md` run here, and `doc/errors.md` and
// `doc/error-rules.md` run in `errors_rakes_test.dart`. The code of the pages
// stands verbatim in `support/observing_page.dart`, their first attempts in
// `support/observing_first_attempts.dart`, and what that code takes for
// granted in `support/observing_stubs.dart`; what the two files of tests share
// is in `support/observing_rakes.dart`. Every block of the pages runs in a
// test below, every quote is compared with what its block prints, and every
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
import 'support/observing_rakes.dart';
import 'support/observing_stubs.dart';
import 'support/page_code.dart';

void main() {
  group('The code of the page', () {
    setUp(() => stage = Stage());

    test('every quote on the page is what its code prints', () {
      expect(
        pageQuotes('doc/observing.md'),
        [play(loading, outcomeObserved: false)],
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
        equals(
            'Bad state: Job(finished: $mark) has already finished; a job runs '
            'once, and a child needs a new Job.deferred'),
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
      '### The failure read by the test': page,
      '### By type and value': page,
      '## Settings between tests': page,
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

    /// The output block that follows the code of the test named
    /// [description] on the page, under its first attempt.
    List<String> quotedAfter(String description) {
      final text = File(testingPage).readAsStringSync();
      final match = RegExp(
        r"// The first attempt: [^\n]*\ntest\('"
        '${RegExp.escape(description)}'
        "'"
        r'.*?\n```\n\n```text\n(.*?)\n```',
        dotAll: true,
      ).firstMatch(text);
      return match!.group(1)!.split('\n');
    }

    test('the failure left unread: the check passes, the zone hears it', () {
      stage.databaseLocked = true;
      final zone = <String>[];
      final checked = <Object?>[];
      runZonedGuarded(
        () => first.failureLeftUnread(
          (description, body) => body(),
          (actual, matcher) {
            checked.add(actual);
            expect(actual, matcher);
          },
        ),
        (error, stackTrace) => zone.add('$error'),
      );

      expect(checked, [isA<Failed>()]);
      expect(zone, quotedAfter('a locked database fails the open'));
    });

    group('the failure read by the test, as the page writes it,', () {
      setUp(() => stage.databaseLocked = true);
      failureReadByTheTest(test, expect);
    });

    test('the outcome compared with an outcome: the failure the page quotes',
        () {
      expect(
        () => first.comparedWithAnOutcome(
          (description, body) => body(),
          expect,
        ),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message!.trim().split('\n'),
            'message',
            quotedAfter('the job loads three'),
          ),
        ),
      );
    });

    group('compared by type and value, as the page writes it,', () {
      comparedByTypeAndValue(test, expect);
    });

    group('the settings, as the page writes them,', () {
      settingsBetweenTests(setUp, addTearDown);

      test('are set inside the group', () {
        expect(Job.isCancellationError, isNotNull);
        expect(Job.isCancellationError!(const DatabaseStopped()), isTrue);
      });
    });

    test('and are put back after it', () {
      expect(Job.isCancellationError, isNull);
    });

    test('elapse moves a pause and a deadline; microtasks alone do not', () {
      fakeAsync((async) {
        final paused = Job<void>(
          (ctx) => ctx.pause(const Duration(milliseconds: 30)),
        );
        final limited = Job<void>(
          timeout: const Duration(milliseconds: 30),
          (ctx) => ctx.abandonable(() => Completer<void>().future),
        );
        async.flushMicrotasks();
        expect(paused.isFinished, isFalse);
        expect(limited.isFinished, isFalse);

        async.elapse(const Duration(milliseconds: 30));
        expect(paused.outcome, isA<Done<void>>());
        expect('${limited.outcome}', 'Cancelled(timeout)');
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

  // Last: the tests of a file share the isolate, and a filter left behind
  // would silence the failures of every test after it.
  test('the filter of cancellation errors is left as it was found', () {
    expect(Job.isCancellationError, isNull);
  });
}
