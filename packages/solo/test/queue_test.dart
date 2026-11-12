@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

SoloJob<void> slow(TestSolo solo, String key, {bool cancellable = true}) =>
    solo.job<TestState, void>(
      key: key,
      cancellable: cancellable,
      (ctx) async => delay(100),
    );

void main() {
  test('the queue and the current job hand out jobs of the controller', () {
    runSolo((solo, journal, async) {
      solo.enqueueJob(slow(solo, 'a'));
      solo.enqueueJob(slow(solo, 'b'));
      async.flushMicrotasks();
      // No cast in sight: `isQueued` belongs to `SoloJob`, not to `Job`, so
      // each of these reads compiles only on the narrower type.
      final queued = solo.queue.jobs.single;
      final running = solo.current;
      expect(queued.isQueued, isTrue);
      expect(running?.isQueued, isFalse);
      expect(solo.lastJobWhere((job) => job.isQueued), same(queued));
      expect(solo.queue.removeWhere((job) => job.isQueued), 1);
      async.flushTimers();
    });
  });

  test('queue.jobs is a live view that counts what the queue holds', () {
    runSolo((solo, journal, async) {
      final jobs = solo.queue.jobs;
      expect(jobs, isEmpty);
      solo.enqueueJob(slow(solo, 'a'));
      solo.enqueueJob(slow(solo, 'b'));
      solo.enqueueJob(slow(solo, 'c'));
      // `a` runs, `b` and `c` wait.
      async.flushMicrotasks();
      expect(jobs, hasLength(2));
      expect(jobs.isEmpty, isFalse);
      expect(jobs.length, solo.queue.length);
      expect(jobs.toString(), '[Job(b), Job(c)]');
      expect(solo.queue.clear(), 2);
      expect(jobs.length, 0);
      expect(jobs.isEmpty, isTrue);
      async.flushTimers();
    });
  });

  test('first: true puts the job ahead of the queue', () {
    runSolo((solo, journal, async) {
      solo.enqueueJob(slow(solo, 'a'));
      solo.enqueueJob(slow(solo, 'b'));
      solo.enqueueJob(slow(solo, 'c'), first: true);
      expect(solo.queue.jobs.map((j) => j.key), ['c', 'a', 'b']);
      async.flushTimers();
      expect(journal.take(), [
        '[c] started',
        '[c] finished Done(null)',
        '[a] started',
        '[a] finished Done(null)',
        '[b] started',
        '[b] finished Done(null)',
      ]);
    });
  });

  test('remove drops a queued job and reports the result', () {
    runSolo((solo, journal, async) {
      final a = solo.enqueueJob(slow(solo, 'a'));
      final b = solo.enqueueJob(slow(solo, 'b'));
      expect(solo.queue.remove(b), isTrue);
      expect(solo.queue.remove(b), isFalse, reason: 'no longer queued');
      expect(solo.queue.length, 1);
      expect(journal.take(), ['[b] dropped Cancelled(manual)']);
      async.flushTimers();
      expect(a.outcome, isA<Done<void>>());
    });
  });

  test('removeWhere survives a predicate that touches the queue', () {
    runSolo((solo, journal, async) {
      // The predicate is the caller's code, and this one takes a job out
      // while it answers about another: the walk used to be over the very
      // list it was changing.
      solo.enqueueJob(slow(solo, 'a'));
      solo.enqueueJob(slow(solo, 'b'));
      final c = solo.enqueueJob(slow(solo, 'c'));
      final removed = solo.queue.removeWhere((job) {
        if (job.key == 'a') {
          solo.queue.remove(c);
        }

        return job.key != 'b';
      });
      expect(removed, 1, reason: 'c was already gone when its turn came');
      expect(solo.queue.jobs.map((job) => job.key), ['b']);
      async.flushTimers();
    });
  });

  test('lastJobWhere survives a predicate that touches the queue', () {
    runSolo((solo, journal, async) {
      // The same walk with the same caller's code in it, one method over.
      solo.enqueueJob(slow(solo, 'a'));
      final b = solo.enqueueJob(slow(solo, 'b'));
      final found = solo.lastJobWhere((job) {
        if (job.key == 'b') {
          solo.queue.remove(b);
        }

        return job.key == 'a';
      });
      expect(found?.key, 'a');
      async.flushTimers();
    });
  });

  test('lastJobWhere does not answer with a job its predicate cancelled', () {
    runSolo((solo, journal, async) {
      final a = solo.enqueueJob(slow(solo, 'a'));
      async.flushMicrotasks();
      final b1 = solo.enqueueJob(slow(solo, 'b'));
      final b2 = solo.enqueueJob(slow(solo, 'b'));
      SoloJob<Object?>? cancelling(SoloJob<Object?> target) =>
          solo.lastJobWhere((job) {
            if (identical(job, target)) {
              job.cancel().ignore();
            }
            return job.key == target.key;
          });

      expect(identical(cancelling(b2), b1), isTrue, reason: 'the next match');
      expect(cancelling(a), isNull, reason: 'the current job, stopped');
      expect(b2.isCancelled, isTrue);
      expect(a.isCancelled, isTrue);
      journal.take();
      async.flushTimers();
    });
  });

  test('lastJobWhere from a start rule does not answer with the job its '
      'predicate cancelled', () {
    runSolo((solo, journal, async) {
      // The job whose rules are being asked is checked before the
      // predicate as well as after it: the predicate is the caller's code,
      // and it may cancel the very job it is about to accept.
      Object? found = 'not asked';
      var started = false;
      late final SoloJob<void> first;
      first = solo.job<TestState, void>(
        key: 'k',
        canStart: (state) {
          found = solo.lastJobWhere((job) {
            if (identical(job, first)) {
              job.cancel().ignore();
            }
            return job.key == 'k';
          });
          return true;
        },
        (ctx) async => started = true,
      );
      solo.enqueueJob(first);
      final next = solo.enqueueJob(slow(solo, 'next'));
      async.flushTimers();

      expect(found, isNull);
      expect(started, isFalse);
      expect(first.outcome, isA<Cancelled>());
      expect(next.outcome, isA<Done<void>>(), reason: 'the queue goes on');
      journal.take();
    });
  });

  test('remove skips a cancellable: false job unless forced', () {
    runSolo((solo, journal, async) {
      solo.enqueueJob(slow(solo, 'a'));
      final stubborn = solo.enqueueJob(
        slow(solo, 'stubborn', cancellable: false),
      );
      expect(solo.queue.remove(stubborn), isFalse);
      expect(solo.queue.isNotEmpty, isTrue);
      expect(solo.queue.remove(stubborn, force: true), isTrue);
      expect(journal.take(), ['[stubborn] dropped Cancelled(manual)']);
      async.flushTimers();
    });
  });

  test('removeWhere and clear count what they removed', () {
    runSolo((solo, journal, async) {
      solo.enqueueJob(slow(solo, 'a1'));
      solo.enqueueJob(slow(solo, 'b'));
      solo.enqueueJob(slow(solo, 'a2'));
      solo.enqueueJob(slow(solo, 'keep', cancellable: false));
      expect(
        solo.queue.removeWhere((j) => (j.key! as String).startsWith('a')),
        2,
      );
      expect(solo.queue.clear(), 1);
      expect(solo.queue.jobs.map((j) => j.key), ['keep']);
      expect(solo.queue.clear(force: true), 1);
      expect(journal.take(), [
        '[a1] dropped Cancelled(manual)',
        '[a2] dropped Cancelled(manual)',
        '[b] dropped Cancelled(manual)',
        '[keep] dropped Cancelled(manual)',
      ]);
    });
  });

  // Off the queue and not started yet, the job the pump holds while its
  // start rules are asked is queued work until it is launched: the
  // policies, `lastJobWhere` and `cancelAll` reach it, and so must these.
  const removals = [('remove', 1), ('removeWhere', 1), ('clear', 2)];
  for (final (how, count) in removals) {
    test('$how reaches the job whose start rules are being asked', () {
      runSolo((solo, journal, async) {
        int? removed;
        bool? listed;
        var ran = false;
        final asked = <Object?>[];
        late final SoloJob<void> b;
        b = solo.job<TestState, void>(
          key: 'b',
          canStart: (state) {
            listed = solo.queue.jobs.contains(b);
            removed = switch (how) {
              'remove' => solo.queue.remove(b) ? 1 : 0,
              'removeWhere' => solo.queue.removeWhere((job) {
                asked.add(job.key);
                return job.key == 'b';
              }),
              _ => solo.queue.clear(),
            };
            return true;
          },
          (ctx) async => ran = true,
        );
        solo
          ..enqueueJob(b)
          ..enqueueJob(slow(solo, 'c'));
        async.flushTimers();
        expect(listed, isFalse, reason: 'the view is the queue itself');
        expect(removed, count);
        expect(ran, isFalse);
        expect(b.outcome, isA<Cancelled>());
        if (how == 'removeWhere') {
          expect(asked, ['b', 'c'], reason: 'it goes ahead of the rest');
        }
        expect(journal.take(), [
          '[b] dropped Cancelled(manual)',
          if (how == 'clear')
            '[c] dropped Cancelled(manual)'
          else ...[
            '[c] started',
            '[c] finished Done(null)',
          ],
        ]);
      });
    });
  }

  test('remove leaves a cancellable: false job being asked unless forced', () {
    runSolo((solo, journal, async) {
      final answers = <bool>[];
      late final SoloJob<void> b;
      b = solo.job<TestState, void>(
        key: 'b',
        cancellable: false,
        canStart: (state) {
          answers
            ..add(solo.queue.remove(b))
            ..add(solo.queue.remove(b, force: true));
          return true;
        },
        (ctx) async {},
      );
      solo.enqueueJob(b);
      async.flushTimers();
      expect(answers, [false, true]);
      expect(journal.take(), ['[b] dropped Cancelled(manual)']);
    });
  });

  test('lastJobWhere searches the queue from the end, then current', () {
    runSolo((solo, journal, async) {
      solo.enqueueJob(slow(solo, 'a'));
      async.flushMicrotasks();
      final b1 = solo.enqueueJob(slow(solo, 'b'));
      final b2 = solo.enqueueJob(slow(solo, 'b'));
      expect(identical(solo.lastJobWhere((j) => j.key == 'b'), b2), isTrue);
      expect(solo.lastJobWhere((j) => j.key == 'a')?.key, 'a');
      expect(solo.lastJobWhere((j) => j.key == 'z'), isNull);
      expect(b1.isQueued, isTrue);
      async.flushTimers();
    });
  });

  test('adding a job twice or after finish throws StateError', () {
    runSolo((solo, journal, async) {
      final job = slow(solo, 'a');
      solo.enqueueJob(job);
      expect(() => solo.enqueueJob(job), throwsStateError);
      async.flushTimers();
      expect(job.isFinished, isTrue);
      expect(() => solo.enqueueJob(job), throwsStateError);
    });
  });

  test('a job from another controller is rejected', () {
    runSolo((solo, journal, async) {
      final other = TestSolo();
      final foreign = other.job<TestState, void>((ctx) async {});
      expect(() => solo.enqueueJob(foreign), throwsArgumentError);
      other.close();
      async.flushMicrotasks();
    });
  });

  test('cancelAll clears the queue and cancels the current job', () {
    runSolo((solo, journal, async) {
      solo.enqueue<TestState, void>(key: 'a', (ctx) async {
        await delay(100);
        ctx.check();
      });
      solo.enqueueJob(slow(solo, 'b'));
      solo.enqueueJob(slow(solo, 'keep', cancellable: false));
      async.elapse(const Duration(milliseconds: 50));
      var done = false;
      solo.cancelAll().then((_) => done = true);
      async.flushMicrotasks();
      expect(done, isFalse);
      expect(journal.take(), ['[a] started', '[b] dropped Cancelled(manual)']);
      async.elapse(const Duration(milliseconds: 50));
      expect(done, isTrue);
      expect(journal.take(), [
        '[a] finished Cancelled(manual)',
        '[keep] started',
      ]);
      async.flushTimers();
      expect(journal.take(), ['[keep] finished Done(null)']);
    });
  });

  test('enqueueJob from inside a body runs after the current job', () {
    runSolo((solo, journal, async) {
      solo.enqueue<TestState, void>(key: 'outer', (ctx) async {
        solo.enqueueJob(slow(solo, 'later'), first: true);
        await delay(10);
        ctx.check();
      });
      async.flushTimers();
      expect(journal.take(), [
        '[outer] started',
        '[outer] finished Done(null)',
        '[later] started',
        '[later] finished Done(null)',
      ]);
    });
  });

  test(
    'a long queue costs each job the same, not the length of the queue',
    () async {
      // A list asked each job whether it was queued by a walk, and shifted
      // its tail to take the head: 40 000 jobs took 15 seconds to queue, to
      // clear and to run. Each of them costs a constant now: under a second
      // alone, two in a loaded run of the whole suite. The bound sits between
      // the two costs, with room on either side.
      const n = 40000;
      final solo = TestSolo();
      final gate = Completer<void>();
      solo.enqueue<TestState, void>((ctx) => ctx.join(() => gate.future));
      await Future<void>.delayed(Duration.zero);
      final watch = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        solo.enqueue<TestState, void>((ctx) async {});
      }
      expect(solo.queue.clear(), n);
      final jobs = [
        for (var i = 0; i < n; i++)
          solo.enqueue<TestState, void>((ctx) async {}),
      ];
      gate.complete();
      await jobs.last.done;
      expect(jobs.last.outcome, isA<Done<void>>());
      expect(watch.elapsed, lessThan(const Duration(seconds: 6)));
      await solo.close();
    },
  );

  test('a policy with a key asks the jobs of its key, not the queue', () async {
    // `droppable`, `keepLatest` and `restart` walked the whole queue on every
    // call: 20 000 calls with as many keys took 17 to 27 seconds each. They
    // ask the jobs of their own key now, and the three together take well
    // under a second alone.
    const n = 20000;
    final watch = Stopwatch()..start();
    for (final policy in [
      Policy.droppable,
      Policy.keepLatest,
      Policy.restart,
    ]) {
      final solo = TestSolo();
      final gate = Completer<void>();
      solo.enqueue<TestState, void>((ctx) => ctx.join(() => gate.future));
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < n; i++) {
        solo.enqueue<TestState, void>(key: i, policy: policy, (ctx) async {});
      }
      expect(solo.queue.length, n);
      // One key replaced over and over: the jobs it replaced are gone from
      // what the next call asks.
      for (var i = 0; i < n; i++) {
        solo.enqueue<TestState, void>(
          key: 'same',
          policy: Policy.keepLatest,
          (ctx) async {},
        );
      }
      expect(solo.queue.length, n + 1);
      gate.complete();
      await solo.close();
    }
    expect(watch.elapsed, lessThan(const Duration(seconds: 6)));
  });

  test('droppable hands back the last job of its key in the queue', () {
    runSolo((solo, journal, async) {
      solo.enqueueJob(slow(solo, 'busy'));
      async.flushMicrotasks();
      final tail = solo.enqueueJob(slow(solo, 'k'));
      final head = solo.enqueueJob(slow(solo, 'k'), first: true);
      expect(solo.queue.jobs, [head, tail]);
      expect(
        solo.enqueueJob(slow(solo, 'k'), policy: Policy.droppable),
        same(tail),
      );
      async.flushTimers();
      journal.take();
    });
  });

  test('keepLatest cancels the jobs of its key in their queue order', () {
    runSolo((solo, journal, async) {
      solo.enqueueJob(slow(solo, 'busy'));
      async.flushMicrotasks();
      for (final name in ['first', 'second']) {
        solo.enqueue<TestState, void>(
          key: 'k',
          describe: () => name,
          (ctx) async {},
        );
      }
      journal.take();
      solo.enqueueJob(slow(solo, 'k'), policy: Policy.keepLatest);
      expect(journal.take(), [
        '[k: first] dropped Cancelled(replaced)',
        '[k: second] dropped Cancelled(replaced)',
      ]);
      async.flushTimers();
      journal.take();
    });
  });

  test('an accumulator asks its own groups, not the queue', () async {
    // Each accumulator looked for its group, and asked whether it was idle,
    // by a walk of the queue: 10 000 accumulators with an event each took 2
    // to 6 seconds per policy. Each asks its own groups now.
    const n = 10000;
    final watch = Stopwatch()..start();
    for (final policy in AccumulationPolicy.values) {
      final solo = TestSolo();
      final gate = Completer<void>();
      solo.enqueue<TestState, void>((ctx) => ctx.join(() => gate.future));
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < n; i++) {
        solo
            .accumulate<TestState, int, void>(
              (ctx, value) async {},
              merge: (a, b) => a + b,
              policy: policy,
            )
            .add(1);
      }
      expect(solo.queue.length, n);
      gate.complete();
      await solo.close();
    }
    expect(watch.elapsed, lessThan(const Duration(seconds: 6)));
  });

  test('a key built twice is one key for the policies', () {
    runSolo((solo, journal, async) {
      String user(int id) => 'user-$id';
      final first = solo.enqueue<TestState, void>(
        key: (user(1), 2),
        policy: Policy.droppable,
        (ctx) async => delay(100),
      );
      final second = solo.enqueue<TestState, void>(
        key: (user(1), 2),
        policy: Policy.droppable,
        (ctx) async => delay(100),
      );
      expect(second, same(first));
      final queued = solo.enqueue<TestState, void>(
        key: (user(3), 4),
        (ctx) async => delay(100),
      );
      final latest = solo.enqueue<TestState, void>(
        key: (user(3), 4),
        policy: Policy.keepLatest,
        (ctx) async => delay(100),
      );
      async.flushMicrotasks();
      expect(queued.outcome, isA<Cancelled>());
      expect(latest.isQueued, isTrue);
      async.flushTimers();
    });
  });
}
