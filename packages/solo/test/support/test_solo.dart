import 'package:solo/solo.dart';

import 'test_state.dart';

/// Opens the protected surface of [Solo] for tests.
final class TestSolo extends Solo<TestState> {
  TestSolo([super.initialState = const Initial()]);
}
