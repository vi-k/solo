@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

/// Runs [future] to its end and returns the error it completed with.
Object? errorFrom(Future<Object?> future, FakeAsync async) {
  Object? caught;
  future.then<void>((_) {}, onError: (Object error) => caught = error);
  async.flushMicrotasks();
  return caught;
}

void main() {
  test('a finished context does not start an action', () {
    runSolo((solo, journal, async) {
      late JobContext<TestState, TestState> leaked;
      var began = false;
      Future<int> action() async {
        began = true;
        await delay(10);
        return 7;
      }

      solo.run<TestState, void>(key: 'job', (ctx) async {
        leaked = ctx;
      });
      async.flushTimers();
      expect(errorFrom(leaked.wait(action), async), isStateError);
      expect(errorFrom(leaked.join(action), async), isStateError);
      expect(errorFrom(leaked.uncancellable(action), async), isStateError);
      expect(began, isFalse, reason: 'none of them begins the action');
      expect(journal.take(), [
        '[job] started',
        '[job] finished Done(null)',
      ]);
    });
  });

  test('a cancelled job that finished refuses the same three', () {
    runSolo((solo, journal, async) {
      late JobContext<TestState, TestState> leaked;
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        leaked = ctx;
        await delay(100);
      });
      async.elapse(const Duration(milliseconds: 50));
      job.cancel();
      async.flushTimers();
      expect(errorFrom(leaked.wait(() => delay(10)), async), isStateError);
      expect(errorFrom(leaked.join(() => delay(10)), async), isStateError);
      expect(
        errorFrom(leaked.uncancellable(() => delay(10)), async),
        isStateError,
        reason: 'the dead context is the bug, not the cancellation',
      );
    });
  });

  test('a finished context still reads the state and logs', () {
    runSolo((solo, journal, async) {
      late JobContext<TestState, TestState> leaked;
      solo.run<TestState, void>(key: 'job', (ctx) async {
        leaked = ctx;
      });
      async.flushTimers();
      expect(leaked.state, isA<Initial>());
      leaked
        ..check()
        ..log('still here');
      expect(journal.take(), [
        '[job] started',
        '[job] finished Done(null)',
        '[job] log still here',
      ]);
    });
  });
}
