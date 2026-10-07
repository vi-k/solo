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
    Solo.observer = journal;
    // Watching is not answering: without a handler every homeless error
    // would also reach the zone of the test. The journal has already
    // recorded it through `onError`, so answering for it is all this does.
    Solo.unansweredHandler = journal.answerForErrors;
    final solo = TestSolo(initialState);
    try {
      body(solo, journal, async);
    } finally {
      solo.close();
      async.flushTimers();
      Solo.observer = null;
      Solo.unansweredHandler = null;
    }
  });
}

/// [runSolo] with a [TestSoloStream], for the few tests that read
/// [TestSoloStream.stream].
void runSoloStream(
  void Function(TestSoloStream solo, JournalObserver journal, FakeAsync async)
      body, {
  TestState initialState = const Initial(),
}) {
  fakeAsync((async) {
    final journal = JournalObserver();
    Solo.observer = journal;
    Solo.unansweredHandler = journal.answerForErrors;
    final solo = TestSoloStream(initialState);
    try {
      body(solo, journal, async);
    } finally {
      solo.close();
      async.flushTimers();
      Solo.observer = null;
      Solo.unansweredHandler = null;
    }
  });
}

/// A fake-time delay of [milliseconds].
Future<void> delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// A cancellation-aware delay: [JobContext.abandonable] around [delay].
Future<void> pause(SoloContext<TestState, TestState> ctx, int milliseconds) =>
    ctx.abandonable(() => delay(milliseconds));
