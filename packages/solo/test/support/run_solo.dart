import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

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
    // would also reach the zone of the test. The handler records it as a
    // line of its own, and the test goes red if nobody reads that line.
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
    _failOnUnanswered(journal);
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
    _failOnUnanswered(journal);
  });
}

/// Fails the test if an error nobody answered for is still in [journal]:
/// the handler of the harness answers for it so that it does not reach the
/// zone, and a test that never reads the journal would be green on it.
/// A test that expects one reads it, and one that does not care about the
/// tail of the journal calls `journal.take()`.
void _failOnUnanswered(JournalObserver journal) {
  final unread = [
    for (final line in journal.lines)
      if (line.contains('] unanswered ')) line,
  ];
  if (unread.isNotEmpty) fail('unanswered errors left unread: $unread');
}

/// A fake-time delay of [milliseconds].
Future<void> delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// A cancellation-aware delay: [JobContext.abandonable] around [delay].
Future<void> pause(SoloContext<TestState, TestState> ctx, int milliseconds) =>
    ctx.abandonable(() => delay(milliseconds));
