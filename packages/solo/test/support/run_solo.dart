import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';

import 'journal.dart';
import 'test_solo.dart';
import 'test_state.dart';

/// Runs [body] with a fresh [TestSolo] and [JournalObserver] inside
/// [fakeAsync]; closes the controller, flushes timers and resets the
/// observer afterwards.
void runSolo(
  void Function(TestSolo solo, JournalObserver journal, FakeAsync async) body, {
  TestState initialState = const Initial(),
}) {
  fakeAsync((async) {
    final journal = JournalObserver();
    SoloBase.observer = journal;
    final solo = TestSolo(initialState);
    try {
      body(solo, journal, async);
    } finally {
      solo.close();
      async.flushTimers();
      SoloBase.observer = null;
    }
  });
}

/// A fake-time delay of [milliseconds].
Future<void> delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// A cancellation-aware delay: [JobContext.wait] around [delay].
Future<void> pause(JobContext<TestState, TestState> ctx, int milliseconds) =>
    ctx.wait(() => delay(milliseconds));
