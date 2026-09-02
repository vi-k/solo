import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';

import 'journal.dart';
import 'test_solo.dart';
import 'test_state.dart';

/// Runs [body] with a fresh [TestSolo] and [JournalObserver] inside
/// [fakeAsync]; flushes timers and resets the observer afterwards.
/// Cancels the controller afterwards; closing it arrives in Task 12.
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
      solo.cancelAll();
      async.flushTimers();
      SoloBase.observer = null;
    }
  });
}

/// A fake-time delay of [milliseconds].
Future<void> delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));
