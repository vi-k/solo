@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:test/test.dart';

import 'support/lifecycle.dart';
import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('Disposed set before the pump drops every job by type', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, Duration.zero);
      expect(journal.take(), [
        'state: Disposed()',
        '[init] dropped Cancelled(rules: is not NotDisposed)',
        '[incrementA] dropped Cancelled(rules: is not Working)',
        '[incrementB] dropped Cancelled(rules: is not Working)',
        '[finish] dropped Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('Disposed set from a microtask lands after init started', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      scheduleMicrotask(() => solo.externalSetState(const Disposed()));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 100));
      expect(journal.take(), [
        '[init] started',
        'state: Preparing(progress: 0)',
        'state: Disposed()',
        '[init] finished Cancelled(rules: is not NotDisposed)',
        '[incrementA] dropped Cancelled(rules: is not Working)',
        '[incrementB] dropped Cancelled(rules: is not Working)',
        '[finish] dropped Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('Disposed set after 50 ms cancels init and drops the rest', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 100));
      expect(journal.take(), [
        '[init] started',
        'state: Preparing(progress: 0)',
        'state: Disposed()',
        '[init] finished Cancelled(rules: is not NotDisposed)',
        '[incrementA] dropped Cancelled(rules: is not Working)',
        '[incrementB] dropped Cancelled(rules: is not Working)',
        '[finish] dropped Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('Disposed set after 150 ms catches init on its second step', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 150));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 200));
      expect(journal.take(), [
        '[init] started',
        'state: Preparing(progress: 0)',
        'state: Preparing(progress: 50)',
        'state: Disposed()',
        '[init] finished Cancelled(rules: is not NotDisposed)',
        '[incrementA] dropped Cancelled(rules: is not Working)',
        '[incrementB] dropped Cancelled(rules: is not Working)',
        '[finish] dropped Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('Disposed set after 250 ms catches init on its third step', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 250));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 300));
      expect(journal.take(), [
        '[init] started',
        'state: Preparing(progress: 0)',
        'state: Preparing(progress: 50)',
        'state: Preparing(progress: 100)',
        'state: Disposed()',
        '[init] finished Cancelled(rules: is not NotDisposed)',
        '[incrementA] dropped Cancelled(rules: is not Working)',
        '[incrementB] dropped Cancelled(rules: is not Working)',
        '[finish] dropped Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('Disposed set after 350 ms cancels incrementA', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 350));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        ...happyPath.sublist(0, 7),
        'state: Disposed()',
        '[incrementA] finished Cancelled(rules: is not Working)',
        '[incrementB] dropped Cancelled(rules: is not Working)',
        '[finish] dropped Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('Disposed set after 450 ms cancels incrementB', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 450));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 500));
      expect(journal.take(), [
        ...happyPath.sublist(0, 10),
        'state: Disposed()',
        '[incrementB] finished Cancelled(rules: is not Working)',
        '[finish] dropped Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('Disposed set after 550 ms cancels finish', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 550));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 600));
      expect(journal.take(), [
        ...happyPath.sublist(0, 13),
        'state: Disposed()',
        '[finish] finished Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('Disposed set after 650 ms only repeats the state', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 650));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 650));
      expect(journal.take(), [...happyPath, 'state: Disposed()']);
    });
  });

  test('Working set at 50 ms keeps init until it asks for Preparing', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Working());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        '[init] started',
        'state: Preparing(progress: 0)',
        'state: Working(a: 0, b: 0)',
        '[init] finished Cancelled(rules: is not Preparing)',
        ...happyPath.sublist(6),
      ]);
    });
  });

  test('Working set at 350 ms leaves incrementA on the new numbers', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 350));
      solo.externalSetState(const Working(a: 10, b: 10));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 600));
      expect(journal.take(), [
        ...happyPath.sublist(0, 7),
        'state: Working(a: 10, b: 10)',
        'state: Working(a: 11, b: 10)',
        '[incrementA] finished Done(null)',
        '[incrementB] started',
        'state: Working(a: 11, b: 11)',
        '[incrementB] finished Done(null)',
        '[finish] started',
        'state: Disposed()',
        '[finish] finished Done(null)',
      ]);
    });
  });

  test('Working set at 450 ms leaves incrementB on the new numbers', () {
    runSolo((solo, journal, async) {
      addLifecycle(solo);
      async.elapse(const Duration(milliseconds: 450));
      solo.externalSetState(const Working(a: 10, b: 10));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 600));
      expect(journal.take(), [
        ...happyPath.sublist(0, 10),
        'state: Working(a: 10, b: 10)',
        'state: Working(a: 10, b: 11)',
        '[incrementB] finished Done(null)',
        '[finish] started',
        'state: Disposed()',
        '[finish] finished Done(null)',
      ]);
    });
  });

  test('a job sets the state from outside itself and from a microtask', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'extremal', (ctx) async {
        solo.externalSetState(const Working());
        scheduleMicrotask(
          () => solo.externalSetState(const Working(a: 2, b: 2)),
        );
        ctx.emit(ctx.stateAs<Working>().copyWith(a: 1, b: 1));
      });
      async.flushTimers();
      expect(async.elapsed, Duration.zero);
      expect(journal.take(), [
        '[extremal] started',
        'state: Working(a: 0, b: 0)',
        'state: Working(a: 1, b: 1)',
        'state: Working(a: 2, b: 2)',
        '[extremal] finished Done(null)',
      ]);
    });
  });
}
