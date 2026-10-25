// `doc/errors.md` and `doc/error-rules.md` run here. The code of the pages
// stands verbatim in `support/observing_page.dart`, their first attempts in
// `support/observing_first_attempts.dart`, and what that code takes for
// granted in `support/observing_stubs.dart`, which it shares with
// `doc/observing.md`; so does `support/observing_rakes.dart` with the tests
// of that page. Every block of the pages runs in a test below, every quote
// is compared with what its block prints, and every piece of code on the
// pages has to be a run of lines of those files: a piece or a quote that
// drifts turns this file red. The rules the pages state in prose and in
// their tables are held with code of the tests' own where the pages show
// none.
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
import 'support/probe_job.dart';

/// The pages this file runs: where an error goes, then its rules.
const pages = ['doc/errors.md', 'doc/error-rules.md'];

/// The pages, and their translation where it is.
///
/// The translation lives outside the package, and the `floor` job runs this
/// file on the archive, where the original is read alone. In the tree each
/// page of both has to be there.
final versions = {
  'original': pages,
  if (Directory('../../docs/ru').existsSync())
    'translation': [
      '../../docs/ru/async_job/errors.md',
      '../../docs/ru/async_job/error-rules.md',
    ],
};

/// The pages of [version] read together.
String readAll(String version) =>
    versions[version]!.map((page) => File(page).readAsStringSync()).join('\n');

void main() {
  group('The code of the page', () {
    setUp(() => stage = Stage());

    test('every quote on the pages is what its code prints', () {
      stage.databaseLocked = true;
      final prints = [
        quotable(play(first.migrating, cancelAt: 10)),
        withTheStopNamed(() => quotable(play(first.migrating, cancelAt: 10))),
        quotable(play(openingReported, cancelAt: 10)),
        play(first.sendingUnawaited),
        play(() => sendingHandedOver(Reporter())),
        play(first.sendingWithBoth),
        play(sendingToTheList),
        debugged(() => play(first.migrating, cancelAt: 10)),
        play(saving),
      ];
      expect(
        [for (final doc in pages) ...pageQuotes(doc)],
        prints,
        reason: 'each quote under the code that prints it, page by page',
      );
    });

    for (final doc in pages) {
      test('$doc has no fence the checks do not read', () {
        expect(strayFences(doc), isEmpty);
      });
    }

    // Each version under its own file: a line of an answer turned into the
    // line of a first attempt would still be found among all of them.
    const page = 'test/support/observing_page.dart';
    const firstAttempts = 'test/support/observing_first_attempts.dart';
    const holders = [
      ('doc/errors.md', '### The first attempt', firstAttempts),
      ('doc/errors.md', '### Errors of a cancellation', page),
      ('doc/errors.md', '### An observer', page),
      ('doc/error-rules.md', '## The debug channel', page),
      ('doc/error-rules.md', '### Limits of the filter', page),
      ('doc/errors.md', '### Work handed to the job', page),
      ('doc/errors.md', '## Answering for errors', page),
      ('doc/error-rules.md', '## Several failures in one error', page),
      ('doc/errors.md', '## Several observers', page),
      ('doc/errors.md', '### Observers in one list', page),
      ('doc/errors.md', '## Reporting each error once', page),
    ];
    for (final (doc, heading, holder) in holders) {
      test('the code under "$heading" on $doc is a run of lines of $holder',
          () {
        expect(codeMissingFrom(doc, holder, under: heading), isEmpty);
      });
    }

    for (final doc in pages) {
      test('every piece of code on $doc is a run of lines of these files', () {
        expect(
          codeMissingFrom(doc, page, alsoIn: [firstAttempts]),
          isEmpty,
        );
      });
    }
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
      Job<void> stoppedByAnother({JobObserver? observer}) => Job<void>(
            observer: observer,
            (ctx) async {
              final stop = CancelToken()..cancel();
              await ctx.join(() => database.migrate(stop));
            },
          );

      expect(
        withTheStopNamed(() => play(stoppedByAnother, outcomeObserved: false)),
        ['zone: DatabaseStopped'],
      );
      expect(
        withTheStopNamed(
          () => play(
            () => stoppedByAnother(observer: Answerer()),
            outcomeObserved: false,
          ),
        ),
        ['onError: DatabaseStopped', 'onUnanswered: DatabaseStopped'],
        reason: 'it goes on to the answer',
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
          // The job is cancelled when the body throws, so the filter is asked
          // there, before `onError` is told what the answer will be.
          [
            'cancel',
            'zone: Bad state: filter failed',
            'onError: DatabaseStopped',
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

    test('a failure the job ends with: onError, then the answer if unobserved',
        () {
      expect(
        play(() => failing(observer: Reporter()), outcomeObserved: false),
        ['onError: Bad state: disk full', 'zone: Bad state: disk full'],
      );
      expect(
        play(() => failing(observer: Answerer()), outcomeObserved: false),
        ['onError: Bad state: disk full', 'onUnanswered: Bad state: disk full'],
        reason: 'an observer that answers gets it, and the zone does not',
      );
      expect(
        play(() => failing(observer: Answerer())),
        [
          'onError: Bad state: disk full',
          'outcome: Failed(Bad state: disk full)',
        ],
        reason: 'observing the outcome takes it off the way',
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

    test('a failure an engine makes of a cancellation goes past the answer',
        () {
      for (final error in [
        const Cancelled('as a failure'),
        ParallelWaitError<List<void>, List<AsyncError?>>(
          [null, null],
          [
            AsyncError(const Cancelled('one'), StackTrace.empty),
            AsyncError(const Cancelled('two'), StackTrace.empty),
          ],
        ),
      ]) {
        final lines = play(
          () => ProbeJob<void>((ctx) async {}, observer: Answerer())
            ..drop(Failed(error, StackTrace.empty)),
          outcomeObserved: false,
        );
        expect(lines.first, startsWith('onError:'));
        expect(lines, isNot(contains(startsWith('onUnanswered:'))));
        expect(lines.last, 'zone: $error');
      }
    });

    test('the page sends an unobserved failure to the answer', () {
      const said = {
        'original': [
          '`onError`, then the answer if nobody observed the outcome',
          'if nobody observes that outcome, it goes on to the answer',
          'then the zone past the answer if nobody observed the outcome',
          'is answered for the same way, failure by failure',
        ],
        'translation': [
          '`onError`, затем ответ, если исход никто не наблюдал',
          'если этот исход никто не наблюдает, он идёт к ответу',
          'затем зона мимо ответа, если исход никто не наблюдал',
          'отвечают так же, провал за провалом',
        ],
      };
      for (final version in versions.keys) {
        final text = readAll(version).replaceAll(RegExp(r'\s+'), ' ');
        for (final phrase in said[version]!) {
          expect(text, contains(phrase), reason: version);
        }
      }
    });

    test('an unobserved failure of several is answered for one by one', () {
      // `saving` of the page with the two calls in the body: the job ends
      // `Failed` with the `ParallelWaitError` they throw.
      expect(
        play(
          () => Job<void>(
            observer: DatabaseErrors(),
            (ctx) => [saveDraft(), sendAnalytics()].wait,
          ),
          outcomeObserved: false,
        ),
        [
          'onUnanswered: DatabaseException',
          'zone: Bad state: analytics offline',
        ],
      );
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

    test('reading done or value leaves the failure of the body to the answer',
        () {
      // The outcome carries the cancellation, so neither read takes the
      // failure of the body on, unlike `ignoreFailure()`.
      final reads = <String, void Function(Job<void> job)>{
        'done': (job) => job.done.ignore(),
        'value': (job) => job.value.ignore(),
      };
      for (final MapEntry(key: way, value: read) in reads.entries) {
        expect(
          quotable(
            play(
              () {
                final job = failingBeforeCancel(observer: Answerer());
                read(job);
                return job;
              },
              cancelAt: 20,
              outcomeObserved: false,
            ),
          ),
          [
            'onError: Bad state: disk full',
            'cancel',
            'onUnanswered: Bad state: disk full',
          ],
          reason: way,
        );
      }
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

    test('one error is heard on each job whose outcome it became', () {
      // A counter of failures counts by identity: the parent hears the very
      // object its child heard.
      final heard = <(Job<Object?>, Object)>[];
      final observer = _Heard(heard);
      void expectHeard(Job<Object?> Function() start, String kinds) {
        heard.clear();
        play(start, outcomeObserved: false);
        expect(heard, hasLength(2), reason: kinds);
        expect(identical(heard.first.$2, heard.last.$2), isTrue, reason: kinds);
        expect(
          [for (final (job, _) in heard) job.isChild],
          [true, false],
          reason: kinds,
        );
      }

      ChildJob<int> failing() =>
          Job.deferred<int>((ctx) => throw StateError('one'));

      expectHeard(
        () => Job<int>(observer: observer, (ctx) => ctx.run(failing())),
        'a child of run, then its parent',
      );
      expectHeard(
        () => Job<List<int>>(
          observer: observer,
          (ctx) => ctx.runAll([failing()]),
        ),
        'a branch of runAll, then its parent',
      );

      heard.clear();
      late Job<int> source;
      late Job<int> continuation;
      play(() {
        source = Job<int>(observer: observer, (ctx) => throw StateError('one'));
        return continuation =
            source.then((ctx, value) => value, observer: observer);
      });
      expect([for (final (job, _) in heard) job], [source, continuation]);
      expect(identical(heard.first.$2, heard.last.$2), isTrue);
    });

    test('an Expando counts a failure once, and a constant error once', () {
      final counter = _Counted();
      ChildJob<int> failing() =>
          Job.deferred<int>((ctx) => throw StateError('one'));

      play(
        () => Job<int>(observer: counter, (ctx) => ctx.run(failing())),
        outcomeObserved: false,
      );
      expect(counter.count, 1, reason: 'the child and the parent');

      for (var i = 0; i < 2; i++) {
        play(
          () => Job<int>(observer: counter, (ctx) => throw const _Stopped()),
          outcomeObserved: false,
        );
      }
      expect(counter.count, 2, reason: 'two constant failures count as one');
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
      // The page holds `abandonable` to the zone only until the body ends. A
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

    test('the page holds an unawaited abandonable to the zone in the body', () {
      const said = {
        'original': [
          'a cancellation of the job makes a `ctx.abandonable` called without',
          "or with the job's cancellation, only while the body runs",
          'on purpose adds a second, past the answer',
        ],
        'translation': [
          'отмена задачи заставляет `ctx.abandonable`, вызванный без `await`',
          'или с отменой задачи, только пока тело идёт',
          'нарочно кончает задачу `Failed`, добавляет второй, мимо ответа',
        ],
      };
      for (final version in versions.keys) {
        final text = readAll(version).replaceAll(RegExp(r'\s+'), ' ');
        for (final phrase in said[version]!) {
          expect(text, contains(phrase), reason: version);
        }
      }
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

    // The line the pages quote after [lead], in each version.
    void quotes(Map<String, String> lead, String line) {
      for (final version in versions.keys) {
        expect(
          RegExp('${lead[version]}`([^`]+)`')
              .firstMatch(readAll(version))!
              .group(1),
          line,
          reason: version,
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
          'original': r'give\s+way\s+to\s+one:\s+',
          'translation': r'канал\s+печатает\s+одну:\s+',
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

  group('Reporting each error once', () {
    /// What [reportingOnce] reports while five jobs given [Reports] end
    /// the five ways the page's table names.
    List<String> reported() {
      final printed = <String>[];
      runZoned(
        () => fakeAsync((async) {
          reportingOnce(() {
            Job<void>(
              observer: Reports(),
              key: 'unread',
              (ctx) => throw StateError('one'),
            );
            final read = Job<void>(
              observer: Reports(),
              key: 'read',
              (ctx) => throw StateError('two'),
            );
            unawaited(read.done.then((outcome) => print('read: $outcome')));
            Job<void>(observer: Reports(), key: 'parent', (ctx) async {
              await ctx.run(
                Job.deferred<void>(
                  key: 'child',
                  (ctx) => throw StateError('three'),
                ),
              );
            });
            final cancelled = Job<void>(
              observer: Reports(),
              key: 'cancelled',
              (ctx) async {
                await Future<void>.delayed(const Duration(milliseconds: 10));
                throw StateError('four');
              },
            );
            Timer(const Duration(milliseconds: 1), cancelled.cancel);
            Job<void>(observer: Reports(), key: 'cleanup', (ctx) async {
              ctx.onDispose(() => throw StateError('five'));
            });
          });
          async.flushTimers();
        }),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
      return printed;
    }

    test('each error is reported once, by one of the two places', () {
      expect(reported()..sort(), [
        'read: Failed(Bad state: two)',
        'report: Job(cancelled): Bad state: four',
        'report: Job(cleanup): Bad state: five',
        'report: Job(parent): Bad state: three',
        'report: Job(unread): Bad state: one',
      ]);
    });

    test('onError hears a failure the zone reports as well', () {
      final heard = <(Job<Object?>, Object)>[];
      final zone = <Object>[];
      runZonedGuarded(
        () => fakeAsync((async) {
          Job<void>(observer: _Heard(heard), (ctx) => throw StateError('one'));
          async.flushTimers();
        }),
        (error, stackTrace) => zone.add(error),
      );
      expect(heard, hasLength(1));
      expect(zone, [same(heard.single.$2)]);
    });
  });

  // Last: the tests of a file share the isolate, and a filter left behind
  // would silence the failures of every test after it.
  test('the filter of cancellation errors is left as it was found', () {
    expect(Job.isCancellationError, isNull);
  });
}

/// Writes down each job `onError` hears about, with the error.
final class _Heard extends JobObserver {
  _Heard(this.heard);

  final List<(Job<Object?>, Object)> heard;

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) =>
      heard.add((job, error));
}

/// The counter of failures of `observing.md`: by identity, in an [Expando].
final class _Counted extends JobObserver {
  final _heard = Expando<bool>();
  int count = 0;

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {
    if (_heard[error] ?? false) return;
    _heard[error] = true;
    count++;
  }
}

/// An error thrown as a constant: one object at every throw.
final class _Stopped implements Exception {
  const _Stopped();
}
