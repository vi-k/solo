import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/journal.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

void main() {
  tearDown(() => SoloBase.observer = null);

  test('state is the initial state and the controller is open', () {
    final solo = TestSolo();
    expect(solo.state, const Initial());
    expect(solo.isClosed, isFalse);
  });

  test('observer.onCreate is called from the constructor', () {
    final journal = JournalObserver();
    SoloBase.observer = journal;
    final solo = TestSolo(const Working());
    expect(journal.created, [solo]);
  });

  test('a SoloBase subclass without a stream compiles and reads state', () {
    final solo = _Bare(const Preparing());
    expect(solo.state, const Preparing());
  });
}

final class _Bare extends SoloBase<TestState> {
  _Bare(super.initialState);
}
