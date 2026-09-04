@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

Job<void> slow(
  TestSolo solo,
  String key, {
  Cancellable cancellable = Cancellable.always,
}) =>
    solo.job<TestState, void>(
      key: key,
      cancellable: cancellable,
      (ctx) async => delay(100),
    );

void main() {
  test('first: true puts the job ahead of the queue', () {
    runSolo((solo, journal, async) {
      solo.add(slow(solo, 'a'));
      solo.add(slow(solo, 'b'));
      solo.add(slow(solo, 'c'), first: true);
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
      final a = solo.add(slow(solo, 'a'));
      final b = solo.add(slow(solo, 'b'));
      expect(solo.queue.remove(b), isTrue);
      expect(solo.queue.remove(b), isFalse, reason: 'no longer queued');
      expect(solo.queue.length, 1);
      expect(journal.take(), ['[b] dropped Cancelled(manual)']);
      async.flushTimers();
      expect(a.outcome, isA<Done<void>>());
    });
  });

  test('remove skips a Cancellable.never job unless forced', () {
    runSolo((solo, journal, async) {
      solo.add(slow(solo, 'a'));
      final stubborn = solo.add(
        slow(solo, 'stubborn', cancellable: Cancellable.never),
      );
      expect(solo.queue.remove(stubborn), isFalse);
      expect(solo.queue.isNotEmpty, isTrue);
      expect(solo.queue.remove(stubborn, force: true), isTrue);
      expect(journal.take(), ['[stubborn] dropped Cancelled(manual)']);
      async.flushTimers();
    });
  });

  test('remove takes a whileQueued job out of the queue', () {
    runSolo((solo, journal, async) {
      solo.add(slow(solo, 'a'));
      final pending = solo.add(
        slow(solo, 'pending', cancellable: Cancellable.whileQueued),
      );
      expect(solo.queue.remove(pending), isTrue, reason: 'not started yet');
      expect(journal.take(), ['[pending] dropped Cancelled(manual)']);
      async.flushTimers();
    });
  });

  test('removeWhere and clear count what they removed', () {
    runSolo((solo, journal, async) {
      solo.add(slow(solo, 'a1'));
      solo.add(slow(solo, 'b'));
      solo.add(slow(solo, 'a2'));
      solo.add(slow(solo, 'keep', cancellable: Cancellable.never));
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

  test('lastWhere and lastJobWhere search from the end, then current', () {
    runSolo((solo, journal, async) {
      solo.add(slow(solo, 'a'));
      async.flushMicrotasks();
      final b1 = solo.add(slow(solo, 'b'));
      final b2 = solo.add(slow(solo, 'b'));
      expect(identical(solo.queue.lastWhere((j) => j.key == 'b'), b2), isTrue);
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
      solo.add(job);
      expect(() => solo.add(job), throwsStateError);
      async.flushTimers();
      expect(job.isFinished, isTrue);
      expect(() => solo.add(job), throwsStateError);
    });
  });

  test('a job from another controller is rejected', () {
    runSolo((solo, journal, async) {
      final other = TestSolo();
      final foreign = other.job<TestState, void>((ctx) async {});
      expect(() => solo.add(foreign), throwsArgumentError);
      other.close();
      async.flushMicrotasks();
    });
  });

  test('cancelAll clears the queue and cancels the current job', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'a', (ctx) async {
        await delay(100);
        ctx.check();
      });
      solo.add(slow(solo, 'b'));
      solo.add(slow(solo, 'keep', cancellable: Cancellable.never));
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

  test('add from inside a body runs after the current job', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'outer', (ctx) async {
        solo.add(slow(solo, 'later'), first: true);
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
