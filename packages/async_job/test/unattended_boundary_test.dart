@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';
import 'support/probe_job.dart';

// Named constants rather than adjacent literals inside the list: the
// analyzer forbids the latter, and the whole journal is what these tests
// compare.
const _noChild =
    '[j] error Bad state: Job(j) cannot run a child inside unattended work';
const _noGroup = '[j] error Bad state: Job(j) cannot run a group of children '
    'inside unattended work';
const _noSection = '[j] error Bad state: Job(j) cannot run an uncancellable '
    'action inside unattended work';

void main() {
  // A journal that records the refusal answers for it too: these tests are
  // about the ban, and where its error goes after the observer is
  // `unattended_test.dart`'s business.
  test('run inside unattended work throws and starts no child', () {
    final journal = JobJournal(answers: true);
    var childRan = false;
    fakeAsync((async) {
      final job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() {
          ctx.run(
            Job.deferred<void>(key: 'child', (c) async => childRan = true),
          );
        });
        await ctx.abandonable(() => delay(1));
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
    });
    // The whole journal, not the error lines alone: a check moved below
    // `child.start()` would still leave one error and a `Done` parent, and
    // filtering by the word `error` would throw away the very lines that
    // say the child ran.
    expect(journal.take(), [
      '[j] started',
      _noChild,
      '[j] finished Done(null)',
    ]);
    expect(childRan, isFalse);
  });

  test('runAll inside unattended work throws and starts no branch', () {
    final journal = JobJournal(answers: true);
    var branchRan = false;
    fakeAsync((async) {
      final job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() {
          ctx.runAll([
            Job.deferred<void>(key: 'branch', (c) async => branchRan = true),
          ]);
        });
        await ctx.abandonable(() => delay(1));
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
    });
    expect(journal.take(), [
      '[j] started',
      _noGroup,
      '[j] finished Done(null)',
    ]);
    expect(branchRan, isFalse);
  });

  test('uncancellable inside unattended work throws and holds nothing', () {
    final journal = JobJournal(answers: true);
    var actionRan = false;
    late final Job<void> job;
    fakeAsync((async) {
      job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(
          () => ctx.uncancellable(() async {
            actionRan = true;
            await delay(50);
          }),
        );
        await ctx.abandonable(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 5));
      job.cancel();
      async.flushTimers();
    });
    expect(journal.take(), [
      '[j] started',
      _noSection,
      '[j] finished Cancelled(manual)',
    ]);
    // The refused section neither ran its action nor held the body's
    // cancellation: the job is cancelled at once, not 50 ms later.
    expect(actionRan, isFalse);
  });

  test('abandonable inside unattended work is allowed', () {
    final journal = JobJournal();
    var reached = false;
    fakeAsync((async) {
      Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() async {
          await ctx.abandonable(() => delay(5));
          // The line after the wait, not just the wait itself: a refusal
          // is thrown *into* the work, and without this the test would
          // not tell a ban from a permission.
          reached = true;
        });
        await ctx.abandonable(() => delay(50));
      });
      async.flushTimers();
    });
    expect(reached, isTrue);
    expect(journal.take().where((line) => line.contains('error')), isEmpty);
  });

  test('join inside unattended work is allowed', () {
    final journal = JobJournal();
    var reached = false;
    fakeAsync((async) {
      Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() async {
          await ctx.join(() => delay(5));
          reached = true;
        });
        await ctx.abandonable(() => delay(50));
      });
      async.flushTimers();
    });
    expect(reached, isTrue);
    expect(journal.take().where((line) => line.contains('error')), isEmpty);
  });

  test("a job of its own may run a child from inside another job's fork", () {
    final journal = JobJournal();
    var childRan = false;
    fakeAsync((async) {
      Job<void>(key: 'a', observer: journal, (ctx) async {
        ctx.unattended(() {
          Job<void>(key: 'b', observer: journal, (inner) async {
            inner
                .run(
                  Job.deferred<void>(key: 'c', (c) async => childRan = true),
                )
                .ignore();
            await inner.abandonable(() => delay(1));
          });
        });
        await ctx.abandonable(() => delay(30));
      });
      async.flushTimers();
    });
    expect(childRan, isTrue);
    expect(journal.take().where((line) => line.contains('error')), isEmpty);
  });

  test('a nested fork of another job does not lift the ban on run', () {
    final journal = JobJournal(answers: true);
    var childRan = false;
    late final Job<void> a;
    late final JobContext ctxA;
    late final JobContext ctxB;
    fakeAsync((async) {
      a = Job<void>(key: 'a', observer: journal, (ctx) async {
        ctxA = ctx;
        await ctx.abandonable(() => delay(100));
      });
      Job<void>(key: 'b', observer: journal, (ctx) async {
        ctxB = ctx;
        await ctx.abandonable(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 5));
      ctxA.unattended(
        () => ctxB.unattended(
          () => ctxA.run(
            Job.deferred<void>(key: 'c', (c) async => childRan = true),
          ),
        ),
      );
      async.flushTimers();
    });
    // Reported under `b`: the innermost fork is its, and the handler of
    // that fork is the one that catches the refusal.
    const refused =
        '[b] error Bad state: Job(a) cannot run a child inside unattended '
        'work';
    expect(childRan, isFalse);
    expect(journal.take().where((line) => line.contains('error')), [refused]);
    expect(a.outcome, isA<Done<void>>());
  });

  test('a job created inside unattended work reports to the body zone', () {
    final journal = JobJournal();
    final caught = <String>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>(key: 'j', observer: journal, (ctx) async {
            ctx.unattended(() {
              Job<void>(key: 'stray', (c) async => throw StateError('stray'));
            });
            await ctx.abandonable(() => delay(1));
          });
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add('$error'),
    );
    expect(caught, ['Bad state: stray']);
    expect(journal.take().where((line) => line.contains('error')), isEmpty);
  });

  test(
      'a job created inside nested unattended work still reports to the '
      'body zone', () {
    final journal = JobJournal();
    final caught = <String>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>(key: 'j', observer: journal, (ctx) async {
            ctx.unattended(
              () => ctx.unattended(() {
                Job<void>(
                  key: 'stray',
                  (c) async => throw StateError('stray'),
                );
              }),
            );
            await ctx.abandonable(() => delay(1));
          });
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add('$error'),
    );
    expect(caught, ['Bad state: stray']);
    expect(journal.take().where((line) => line.contains('error')), isEmpty);
  });

  for (final continuation in [false, true]) {
    final what = continuation ? 'a continuation' : 'a job';
    test('the body of $what created inside unattended work runs outside it',
        () {
      // Its outcome was already the new job's own; its body is too. A bare
      // `unawaited` error in it lands in the zone the work was started
      // from, not at the observer of the job that started the work.
      final journal = JobJournal();
      final caught = <String>[];
      runZonedGuarded(
        () {
          fakeAsync((async) {
            Job<void>(key: 'j', observer: journal, (ctx) async {
              ctx.unattended(() {
                Future<void> leak(JobContext c) async =>
                    unawaited(Future<void>.error(StateError('leak')));
                if (continuation) {
                  Job<void>(key: 'source', (c) async {}).then<void>(
                    (c, _) => leak(c),
                  );
                } else {
                  Job<void>(key: 'stray', leak);
                }
              });
              await ctx.abandonable(() => delay(1));
            });
            async.flushTimers();
          });
        },
        (error, stackTrace) => caught.add('$error'),
      );
      expect(caught, ['Bad state: leak']);
      expect(journal.take().where((line) => line.contains('error')), isEmpty);
    });
  }

  for (final (made, nested) in [
    ('inside', false),
    ('elsewhere', false),
    ('inside', true),
  ]) {
    final where = nested ? 'nested unattended work' : 'unattended work';
    test(
        'the body of a job made $made and started by hand inside $where runs '
        'outside it', () {
      // Started there, not only made there: `start` is called inside the
      // work, and the body would run in the work's zone. It runs in the
      // zone the work was started from, the one a job made there reports
      // to, and its bare `unawaited` error lands there -- not in the zone
      // a job made elsewhere was made in, either. It starts at once, as a
      // job started anywhere else does.
      final journal = JobJournal();
      final caught = <String>[];
      var bodyStarted = false;
      runZonedGuarded(
        () {
          fakeAsync((async) {
            Job<void>(key: 'j', observer: journal, (ctx) async {
              Future<void> leak(JobContext c) async {
                bodyStarted = true;
                unawaited(Future<void>.error(StateError('leak')));
              }

              final elsewhere = made == 'elsewhere'
                  ? runZonedGuarded(
                      () => Job.deferred<void>(key: 'stray', leak),
                      (error, stackTrace) => caught.add('made in: $error'),
                    )
                  : null;
              void startIt() {
                (elsewhere ?? Job.deferred<void>(key: 'stray', leak)).start();
                expect(bodyStarted, isTrue);
              }

              ctx.unattended(
                nested ? () => ctx.unattended(startIt) : startIt,
              );
              await ctx.abandonable(() => delay(1));
            });
            async.flushTimers();
          });
        },
        (error, stackTrace) => caught.add('$error'),
      );
      expect(bodyStarted, isTrue);
      expect(caught, ['Bad state: leak']);
      expect(journal.take().where((line) => line.contains('error')), isEmpty);
    });
  }

  test('a job started by hand inside the work of another job starts outside',
      () {
    // Forks of two jobs, one inside the other: the job starts where the
    // outer work was started from, the way a job made in there reports.
    // Its observer's `onStart` throwing is its own, and reaches neither
    // observer of the two jobs.
    final journal = JobJournal();
    final caught = <String>[];
    late final JobContext ctxB;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          runZonedGuarded(
            () => Job<void>(key: 'b', observer: journal, (ctx) async {
              ctxB = ctx;
              await ctx.abandonable(() => delay(100));
            }),
            (error, stackTrace) => caught.add('zone of b: $error'),
          );
          async.elapse(const Duration(milliseconds: 5));
          Job<void>(key: 'a', observer: journal, (ctx) async {
            ctx.unattended(
              () => ctxB.unattended(
                () => Job.deferred<void>(
                  key: 'stray',
                  observer: _ThrowingStart(),
                  (c) async =>
                      unawaited(Future<void>.error(StateError('leak'))),
                ).start(),
              ),
            );
            await ctx.abandonable(() => delay(1));
          });
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add('zone of a: $error'),
    );
    expect(caught, [
      'zone of a: Bad state: onStart of stray',
      'zone of a: Bad state: leak',
    ]);
    expect(journal.take().where((line) => line.contains('error')), isEmpty);
  });

  test(
    'a nested fork of another job does not lift the ban on uncancellable',
    () {
      final journal = JobJournal(answers: true);
      var actionRan = false;
      late final Job<void> a;
      late final JobContext ctxA;
      late final JobContext ctxB;
      fakeAsync((async) {
        a = Job<void>(key: 'a', observer: journal, (ctx) async {
          ctxA = ctx;
          await ctx.abandonable(() => delay(100));
        });
        Job<void>(key: 'b', observer: journal, (ctx) async {
          ctxB = ctx;
          await ctx.abandonable(() => delay(100));
        });
        async.elapse(const Duration(milliseconds: 5));
        ctxA.unattended(
          () => ctxB.unattended(
            () => ctxA.uncancellable(() async {
              actionRan = true;
              await delay(5);
            }),
          ),
        );
        async.flushTimers();
      });
      const refused =
          '[b] error Bad state: Job(a) cannot run an uncancellable action '
          'inside unattended work';
      expect(actionRan, isFalse);
      expect(
        journal.take().where((line) => line.contains('error')),
        [refused],
      );
      expect(a.outcome, isA<Done<void>>());
    },
  );

  test('a job equal to another is not inside the work of that other', () {
    fakeAsync((async) {
      Object? thrown;
      var ranTheStep = false;
      final outer = KeyedJob<void>(key: 'same', (ctx) async {
        ctx.unattended(() async {
          // A job of the same domain, started from inside the work: its
          // body runs in this fork's zone. The two are equal by key, and a
          // zone looks its keys up by `==`, so without an identity check
          // the inner job finds itself inside somebody's unattended work
          // and refuses a step that is perfectly legal.
          final inner = KeyedJob<void>(key: 'same', (inner) async {
            await inner.uncancellable(() async => ranTheStep = true);
          })
            ..ignore();
          try {
            inner.launch();
          } on Object catch (error) {
            thrown = error;
          }
        });
        await ctx.abandonable(() => delay(10));
      })
        ..ignore()
        ..launch();
      async.flushTimers();
      expect(thrown, isNull);
      expect(ranTheStep, isTrue);
      expect(outer.outcome, isA<Done<void>>());
    });
  });
}

final class _ThrowingStart extends JobObserver {
  @override
  void onStart(Job<Object?> job) => throw StateError('onStart of stray');
}
