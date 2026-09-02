import 'package:solo/solo.dart';

import 'test_state.dart';

/// Opens the protected surface of [Solo] for tests.
final class TestSolo extends Solo<TestState> {
  TestSolo([super.initialState = const Initial()]);

  @override
  SoloQueue get queue => super.queue;

  @override
  Job<Object?>? get current => super.current;

  @override
  Job<Object?>? lastJobWhere(bool Function(Job<Object?> job) test) =>
      super.lastJobWhere(test);

  @override
  void externalSetState(TestState state) => super.externalSetState(state);
}
