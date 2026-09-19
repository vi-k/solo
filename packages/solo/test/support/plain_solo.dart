import 'package:solo/solo.dart';

import 'test_solo.dart';

/// A bare [Solo] with no stream, for tests that need a controller and
/// nothing about its delivery. Its protected surface is open, as
/// [TestSolo]'s is.
final class PlainSolo<S extends Object> extends Solo<S> with OpenSolo<S> {
  PlainSolo(super.initialState);
}
