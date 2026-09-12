@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

/// The gate recipe from `doc/jobs.md`, written as the page shows it.
///
/// The page promises four things about it, and each of them is a promise
/// about the queue rather than about the gate. They are pinned here so a
/// change to the queue cannot quietly turn the recipe into a lie.
Completer<void>? _gate;

void pauseQueue(TestSolo solo) {
  if (_gate != null) return;
  final gate = _gate = Completer<void>();
  solo.add(
    solo.job<TestState, void>(
      key: 'gate',
      (ctx) => ctx.wait(() => gate.future),
    ),
  );
}

void resumeQueue() {
  _gate?.complete();
  _gate = null;
}

SoloJob<void> work(TestSolo solo, String key) =>
    solo.job<TestState, void>(key: key, (ctx) async => delay(100));

void main() {
  setUp(() => _gate = null);

  test('the gate holds the queue and resume runs it in order', () {
    runSolo((solo, journal, async) {
      pauseQueue(solo);
      solo
        ..add(work(solo, 'a'))
        ..add(work(solo, 'b'))
        ..add(work(solo, 'c'));
      async.flushMicrotasks();

      expect(solo.queue.length, 3);
      // The observer sees an ordinary job, not a pause: this is the price
      // the page names. No outcome has been reached.
      expect(journal.take(), ['[gate] started']);
      expect(solo.current?.key, 'gate', reason: 'the gate holds the slot');

      resumeQueue();
      async.flushTimers();

      expect(journal.take().where((line) => line.contains('started')), [
        '[a] started',
        '[b] started',
        '[c] started',
      ]);
    });
  });

  test('clear empties the queue and leaves the pause standing', () {
    runSolo((solo, journal, async) {
      pauseQueue(solo);
      solo
        ..add(work(solo, 'a'))
        ..add(work(solo, 'b'));
      async.flushMicrotasks();

      solo.queue.clear();

      expect(solo.queue.length, 0);
      expect(solo.current?.key, 'gate', reason: 'the gate is not queued');

      solo.add(work(solo, 'c'));
      async.flushMicrotasks();
      expect(solo.queue.length, 1, reason: 'the new job waits again');
    });
  });

  test('close comes back without a resume', () {
    runSolo((solo, journal, async) {
      pauseQueue(solo);
      solo.add(work(solo, 'a'));
      async.flushMicrotasks();

      var closed = false;
      unawaited(solo.close().then((_) => closed = true));
      async.flushTimers();

      expect(closed, isTrue, reason: 'the gate is cancellable');
    });
  });

  test('cancelAll(force: true) takes the gate out and the queue moves on', () {
    runSolo((solo, journal, async) {
      pauseQueue(solo);
      solo.add(work(solo, 'a'));
      async.flushMicrotasks();

      solo.cancelAll(force: true);
      async.flushTimers();

      expect(_gate!.isCompleted, isFalse, reason: 'nobody opened the gate');
      expect(solo.queue.length, 0, reason: 'and the queue ran anyway');
    });
  });
}
