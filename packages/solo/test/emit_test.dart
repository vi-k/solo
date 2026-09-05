@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/journal.dart';
import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('emit gives up on a cancellation that arrived inside it', () {
    fakeAsync((async) {
      final journal = JournalObserver();
      SoloBase.observer = journal;
      final solo = _DisposeOnPreparing();
      var past = false;
      try {
        solo.run<NotDisposed, void>(key: 'job', (ctx) async {
          ctx.emit(const Preparing());
          past = true;
        });
        async.flushMicrotasks();
        expect(past, isFalse, reason: 'the hook cancelled the job meanwhile');
        expect(journal.take(), [
          '[job] started',
          'state: Preparing(progress: 0)',
          'state: Disposed()',
          '[job] finished Cancelled(rules: is not NotDisposed)',
        ]);
      } finally {
        solo.close();
        async.flushTimers();
        SoloBase.observer = null;
      }
    });
  });

  test('a child cancelled by its own emit does not run past it', () {
    runSolo((solo, journal, async) {
      var past = false;
      solo.run<NotDisposed, void>(key: 'parent', (ctx) async {
        final child = solo.job<TestState, void>(key: 'child', (ctx) async {
          ctx.emit(const Disposed());
          past = true;
        });
        await ctx.run(child).done;
      });
      async.flushTimers();
      expect(past, isFalse, reason: 'the parent went down inside the emit');
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        'state: Disposed()',
        '> [child] finished Cancelled(parent)',
        '[parent] finished Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('emit still returns when nothing cancels the job inside it', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        ctx
          ..emit(const Preparing())
          ..emit(const Working());
      });
      async.flushTimers();
      expect(journal.take(), [
        '[job] started',
        'state: Preparing(progress: 0)',
        'state: Working(a: 0, b: 0)',
        '[job] finished Done(null)',
      ]);
    });
  });
}

/// Pushes the state out of `NotDisposed` from inside the change itself.
final class _DisposeOnPreparing extends Solo<TestState> {
  _DisposeOnPreparing() : super(const Initial());

  @override
  void onChange(TestState previous, TestState current) {
    if (current is Preparing) {
      externalSetState(const Disposed());
    }
  }
}
