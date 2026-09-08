@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';

// Named constants rather than adjacent literals inside the list: the
// analyzer forbids the latter, and the whole journal is what these tests
// compare.
const _noChild =
    '[j] error Bad state: Job(j) cannot run a child inside unattended work';
const _noSection = '[j] error Bad state: Job(j) cannot run an uncancellable '
    'action inside unattended work';

void main() {
  test('run inside unattended work throws and starts no child', () {
    final journal = JobJournal();
    var childRan = false;
    fakeAsync((async) {
      final job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() {
          ctx.run(
            Job.deferred<void>(key: 'child', (c) async => childRan = true),
          );
        });
        await ctx.wait(() => delay(1));
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

  test('uncancellable inside unattended work throws and holds nothing', () {
    final journal = JobJournal();
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
        await ctx.wait(() => delay(100));
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

  test('wait inside unattended work is allowed', () {
    final journal = JobJournal();
    var reached = false;
    fakeAsync((async) {
      Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() async {
          await ctx.wait(() => delay(5));
          // The line after the wait, not just the wait itself: a refusal
          // is thrown *into* the work, and without this the test would
          // not tell a ban from a permission.
          reached = true;
        });
        await ctx.wait(() => delay(50));
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
        await ctx.wait(() => delay(50));
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
            inner.run(
              Job.deferred<void>(key: 'c', (c) async => childRan = true),
            );
            await inner.wait(() => delay(1));
          });
        });
        await ctx.wait(() => delay(30));
      });
      async.flushTimers();
    });
    expect(childRan, isTrue);
    expect(journal.take().where((line) => line.contains('error')), isEmpty);
  });

  test('a nested fork of another job does not lift the ban on run', () {
    final journal = JobJournal();
    var childRan = false;
    late final Job<void> a;
    late final JobContext ctxA;
    late final JobContext ctxB;
    fakeAsync((async) {
      a = Job<void>(key: 'a', observer: journal, (ctx) async {
        ctxA = ctx;
        await ctx.wait(() => delay(100));
      });
      Job<void>(key: 'b', observer: journal, (ctx) async {
        ctxB = ctx;
        await ctx.wait(() => delay(100));
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

  test(
    'a nested fork of another job does not lift the ban on uncancellable',
    () {
      final journal = JobJournal();
      var actionRan = false;
      late final Job<void> a;
      late final JobContext ctxA;
      late final JobContext ctxB;
      fakeAsync((async) {
        a = Job<void>(key: 'a', observer: journal, (ctx) async {
          ctxA = ctx;
          await ctx.wait(() => delay(100));
        });
        Job<void>(key: 'b', observer: journal, (ctx) async {
          ctxB = ctx;
          await ctx.wait(() => delay(100));
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
}
