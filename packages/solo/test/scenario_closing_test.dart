@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:test/test.dart';

import 'support/lifecycle.dart';
import 'support/run_solo.dart';

void main() {
  test('close immediately drops everything at zero time', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      solo.close();
      async.flushTimers();
      expect(async.elapsed, Duration.zero);
      expect(journal.take(), [
        '[init] dropped Cancelled(closed)',
        '[incrementA] dropped Cancelled(closed)',
        '[incrementB] dropped Cancelled(closed)',
        '[finish] dropped Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('close from a microtask lands after init made its first emit', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      scheduleMicrotask(solo.close);
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 100));
      expect(journal.take(), [
        '[init] started',
        'state: Preparing(progress: 0)',
        '[incrementA] dropped Cancelled(closed)',
        '[incrementB] dropped Cancelled(closed)',
        '[finish] dropped Cancelled(closed)',
        '[init] finished Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('close after 50 ms cancels init, which notices at 100 ms', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 50));
      solo.close();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 100));
      expect(journal.take(), [
        '[init] started',
        'state: Preparing(progress: 0)',
        '[incrementA] dropped Cancelled(closed)',
        '[incrementB] dropped Cancelled(closed)',
        '[finish] dropped Cancelled(closed)',
        '[init] finished Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('close after 150 ms cancels init, which notices at 200 ms', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 150));
      solo.close();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 200));
      expect(journal.take(), [
        '[init] started',
        'state: Preparing(progress: 0)',
        'state: Preparing(progress: 50)',
        '[incrementA] dropped Cancelled(closed)',
        '[incrementB] dropped Cancelled(closed)',
        '[finish] dropped Cancelled(closed)',
        '[init] finished Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('close after 250 ms cancels init, which notices at 300 ms', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 250));
      solo.close();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 300));
      expect(journal.take(), [
        '[init] started',
        'state: Preparing(progress: 0)',
        'state: Preparing(progress: 50)',
        'state: Preparing(progress: 100)',
        '[incrementA] dropped Cancelled(closed)',
        '[incrementB] dropped Cancelled(closed)',
        '[finish] dropped Cancelled(closed)',
        '[init] finished Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('close after 350 ms cancels incrementA, which notices at 400 ms', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 350));
      solo.close();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        ...happyPath.sublist(0, 7),
        '[incrementB] dropped Cancelled(closed)',
        '[finish] dropped Cancelled(closed)',
        '[incrementA] finished Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('close after 450 ms cancels incrementB, which notices at 500 ms', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 450));
      solo.close();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 500));
      expect(journal.take(), [
        ...happyPath.sublist(0, 10),
        '[finish] dropped Cancelled(closed)',
        '[incrementB] finished Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('close after 550 ms cancels finish, which notices at 600 ms', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 550));
      solo.close();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 600));
      expect(journal.take(), [
        ...happyPath.sublist(0, 13),
        '[finish] finished Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('close after 650 ms finds everything done', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 650));
      solo.close();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 650));
      expect(journal.take(), [...happyPath, 'closed']);
    });
  });

  test('close after 350 ms while incrementA is cancellable: false', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo, cancellableA: false);
      async.elapse(const Duration(milliseconds: 350));
      solo.close();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        ...happyPath.sublist(0, 7),
        '[incrementB] dropped Cancelled(closed)',
        '[finish] dropped Cancelled(closed)',
        'state: Working(a: 1, b: 0)',
        '[incrementA] finished Done(null)',
        'closed',
      ]);
    });
  });
}
