@Timeout(Duration(seconds: 5))
library;

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

  test('remove skips a cancellable: false job unless forced', () {
    runSolo((solo, journal, async) {
      solo.enqueueJob(slow(solo, 'a'));
      final stubborn =
          solo.enqueueJob(slow(solo, 'stubborn', cancellable: false));
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
      expect(journal.take(), [
        '[a] started',
        '[b] dropped Cancelled(manual)',
      ]);
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
}
