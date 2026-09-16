import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/journal.dart';
import 'support/plain_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

void main() {
  tearDown(() => Solo.observer = null);

  test('state is the initial state and the controller is open', () {
    final solo = TestSolo();
    expect(solo.currentState, const Initial());
    expect(solo.isClosed, isFalse);
  });

  test('observer.onCreate is called from the constructor', () {
    final journal = JournalObserver();
    Solo.observer = journal;
    final solo = TestSolo(const Working());
    expect(journal.created, [solo]);
  });

  test('a Solo subclass compiles and reads state, with no stream of its own',
      () {
    final solo = PlainSolo<TestState>(const Preparing());
    expect(solo.currentState, const Preparing());
  });
}
