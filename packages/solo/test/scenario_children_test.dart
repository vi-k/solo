@Timeout(Duration(seconds: 5))
library;

import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

/// Queues the nested fixture ported from 1.x: `test1` runs 0..400 ms,
/// `test2` 100..300 as a child of `test1`, `test3` 200..300 as a child of
/// `test2`.
///
/// Every wait goes through [pause], that is `ctx.guard`, so a cancelled
/// body ends at the moment it is marked, not on its next context access.
/// The timer behind an abandoned wait still fires, so `flushTimers` can
/// leave `async.elapsed` past the moment of the last journal line.
void addNested(TestSolo solo) {
  final test3 = solo.job<Preparing, void>(
    key: 'test3',
    keepWhile: (state) => state.progress <= 100,
    (ctx) async {
      await pause(ctx, 100);
      ctx.emit(ctx.state.copyWith(progress: 100));
    },
  );
  final test2 = solo.job<PreparingAndWorking, void>(
    key: 'test2',
    canStart: (state) => state is Preparing,
    keepWhile: (state) => state is! Preparing || state.progress <= 100,
    (ctx) async {
      await pause(ctx, 100);
      ctx.emit(ctx.stateAs<Preparing>().copyWith(progress: 50));
      await ctx.run(test3).done;
      ctx.emit(const Working());
    },
  );
  solo.run<NotDisposed, void>(
    key: 'test1',
    canStart: (state) => state is Initial,
    (ctx) async {
      await pause(ctx, 100);
      ctx.emit(const Preparing());
      await ctx.run(test2).done;
      await pause(ctx, 100);
      ctx.emit(ctx.stateAs<Working>().copyWith(a: 1, b: 1));
      ctx.emit(const Disposed());
    },
  );
}

/// The journal of [addNested] when nothing interferes: 12 lines, the last
/// one at 400 ms.
const nestedPath = [
  '[test1] started',
  'state: Preparing(progress: 0)',
  '> [test2] started',
  'state: Preparing(progress: 50)',
  '>> [test3] started',
  'state: Preparing(progress: 100)',
  '>> [test3] finished Done(null)',
  'state: Working(a: 0, b: 0)',
  '> [test2] finished Done(null)',
  'state: Working(a: 1, b: 1)',
  'state: Disposed()',
  '[test1] finished Done(null)',
];

/// Queues the «check state on yield» fixture from 1.x: `parent` waits
/// 100 ms, runs `child`, which emits three states in a row, then emits
/// `Preparing(100)` and waits 100 ms more.
void addOnEmit(
  TestSolo solo, {
  bool Function(Preparing state)? childKeepWhile,
}) {
  solo.run<Preparing, void>(key: 'parent', (ctx) async {
    await pause(ctx, 100);
    final child = solo.job<Preparing, void>(
      key: 'child',
      keepWhile: childKeepWhile,
      (ctx) async {
        ctx
          ..emit(const Preparing(progress: 25))
          ..emit(const Preparing(progress: 50))
          ..emit(const Preparing(progress: 75));
      },
    );
    await ctx.run(child).done;
    ctx.emit(const Preparing(progress: 100));
    await pause(ctx, 100);
  });
}

/// The journal of [addOnEmit] when nothing interferes: the child emits
/// three states, nobody's rules break, the parent ends at 200 ms.
const onEmitPath = [
  '[parent] started',
  '> [child] started',
  'state: Preparing(progress: 25)',
  'state: Preparing(progress: 50)',
  'state: Preparing(progress: 75)',
  '> [child] finished Done(null)',
  'state: Preparing(progress: 100)',
  '[parent] finished Done(null)',
];

void main() {
  test('nested jobs complete in 400 ms', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), nestedPath);
    });
  });

  test('cancel after 50 ms ends test1 before any child', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 100));
      expect(journal.take(), [
        '[test1] started',
        '[test1] finished Cancelled(manual)',
      ]);
    });
  });

  test('cancel after 150 ms cascades to test2 first', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 150));
      solo.current!.cancel();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 200));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 3),
        '> [test2] finished Cancelled(parent)',
        '[test1] finished Cancelled(manual)',
      ]);
    });
  });

  test('cancel after 250 ms cascades through test2 down to test3', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 250));
      solo.current!.cancel();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 300));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 5),
        '>> [test3] finished Cancelled(parent)',
        '> [test2] finished Cancelled(parent)',
        '[test1] finished Cancelled(manual)',
      ]);
    });
  });

  test('cancel after 350 ms catches test1 alone, children already done', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 350));
      solo.current!.cancel();
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 9),
        '[test1] finished Cancelled(manual)',
      ]);
    });
  });

  test('Disposed set after 50 ms cancels test1 by its type', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 100));
      expect(journal.take(), [
        '[test1] started',
        'state: Disposed()',
        '[test1] finished Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test(
      'Disposed set after 150 ms cancels test2 and test1 by their own '
      'rules', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 150));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 200));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 3),
        'state: Disposed()',
        '> [test2] finished Cancelled(rules: is not PreparingAndWorking)',
        '[test1] finished Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test(
      'Disposed set after 250 ms cancels all three by rules, not by '
      'cascade', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 250));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 300));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 5),
        'state: Disposed()',
        '>> [test3] finished Cancelled(rules: is not Preparing)',
        '> [test2] finished Cancelled(rules: is not PreparingAndWorking)',
        '[test1] finished Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('Disposed set after 350 ms cancels test1 after its children', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 350));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 9),
        'state: Disposed()',
        '[test1] finished Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('Preparing(100) set after 50 ms is overwritten by test1', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Preparing(progress: 100));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        '[test1] started',
        'state: Preparing(progress: 100)',
        ...nestedPath.sublist(1),
      ]);
    });
  });

  test('Preparing(100) set after 150 ms passes every rule, test2 goes on', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 150));
      solo.externalSetState(const Preparing(progress: 100));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 3),
        'state: Preparing(progress: 100)',
        ...nestedPath.sublist(3),
      ]);
    });
  });

  test('Preparing(100) set after 250 ms is the edge of keepWhile of test3', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 250));
      solo.externalSetState(const Preparing(progress: 100));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 5),
        'state: Preparing(progress: 100)',
        ...nestedPath.sublist(5),
      ]);
    });
  });

  test('Preparing(100) set after 350 ms breaks stateAs<Working> of test1', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 350));
      solo.externalSetState(const Preparing(progress: 100));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 9),
        'state: Preparing(progress: 100)',
        '[test1] finished Cancelled(rules: is not Working)',
      ]);
    });
  });

  test(
      'Preparing(999) set after 50 ms is overwritten before anyone reads '
      'it', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Preparing(progress: 999));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        '[test1] started',
        'state: Preparing(progress: 999)',
        ...nestedPath.sublist(1),
      ]);
    });
  });

  test('Preparing(999) set after 150 ms breaks keepWhile of test2', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 150));
      solo.externalSetState(const Preparing(progress: 999));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 250));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 3),
        'state: Preparing(progress: 999)',
        '> [test2] finished Cancelled(rules: keepWhile)',
        '[test1] finished Cancelled(rules: is not Working)',
      ]);
    });
  });

  test('Preparing(999) set after 250 ms breaks keepWhile of test3 and test2',
      () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 250));
      solo.externalSetState(const Preparing(progress: 999));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 350));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 5),
        'state: Preparing(progress: 999)',
        '>> [test3] finished Cancelled(rules: keepWhile)',
        '> [test2] finished Cancelled(rules: keepWhile)',
        '[test1] finished Cancelled(rules: is not Working)',
      ]);
    });
  });

  test('Preparing(999) set after 350 ms breaks stateAs<Working> of test1', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 350));
      solo.externalSetState(const Preparing(progress: 999));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 9),
        'state: Preparing(progress: 999)',
        '[test1] finished Cancelled(rules: is not Working)',
      ]);
    });
  });

  test('Working set after 50 ms is overwritten by the first emit of test1', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Working(a: 999, b: 999));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        '[test1] started',
        'state: Working(a: 999, b: 999)',
        ...nestedPath.sublist(1),
      ]);
    });
  });

  test(
      'Working set after 150 ms passes the rules of test2 and breaks its '
      'stateAs<Preparing>', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 150));
      solo.externalSetState(const Working(a: 999, b: 999));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 300));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 3),
        'state: Working(a: 999, b: 999)',
        '> [test2] finished Cancelled(rules: is not Preparing)',
        ...nestedPath.sublist(9),
      ]);
    });
  });

  test('Working set after 250 ms cancels test3 by type, test2 goes on', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 250));
      solo.externalSetState(const Working(a: 999, b: 999));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 350));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 5),
        'state: Working(a: 999, b: 999)',
        '>> [test3] finished Cancelled(rules: is not Preparing)',
        ...nestedPath.sublist(7),
      ]);
    });
  });

  test('Working set after 350 ms survives into the last emit of test1', () {
    runSolo((solo, journal, async) {
      addNested(solo);
      async.elapse(const Duration(milliseconds: 350));
      solo.externalSetState(const Working(a: 999, b: 999));
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 400));
      expect(journal.take(), [
        ...nestedPath.sublist(0, 9),
        'state: Working(a: 999, b: 999)',
        ...nestedPath.sublist(9),
      ]);
    });
  });

  test('a child emitting three states leaves the parent running', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      addOnEmit(solo);
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 200));
      expect(journal.take(), onEmitPath);
    });
  });

  test('a child breaking its own keepWhile runs on: it is checked lazily', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      addOnEmit(solo, childKeepWhile: (state) => state.progress != 50);
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 200));
      expect(journal.take(), onEmitPath);
    });
  });

  test('an external change cancels the parent before its child starts', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      addOnEmit(solo);
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(async.elapsed, const Duration(milliseconds: 100));
      expect(journal.take(), [
        '[parent] started',
        'state: Disposed()',
        '[parent] finished Cancelled(rules: is not Preparing)',
      ]);
    });
  });
}
