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
  SoloJob<Object?>? lastJobWhere(bool Function(Job<Object?> job) test) =>
      super.lastJobWhere(test);

  @override
  bool get hasListeners => super.hasListeners;

  @override
  void externalSetState(TestState state) => super.externalSetState(state);
}

/// [TestSolo] with a stream, for the few tests that read one.
final class TestSoloStream extends Solo<TestState> with SoloStream {
  TestSoloStream([super.initialState = const Initial()]);

  @override
  SoloQueue get queue => super.queue;

  @override
  Job<Object?>? get current => super.current;

  @override
  SoloJob<Object?>? lastJobWhere(bool Function(Job<Object?> job) test) =>
      super.lastJobWhere(test);

  @override
  bool get hasListeners => super.hasListeners;

  @override
  void externalSetState(TestState state) => super.externalSetState(state);
}
