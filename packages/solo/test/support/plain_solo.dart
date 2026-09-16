import 'package:solo/solo.dart';

/// A bare [Solo] with no stream, for tests that need a controller and
/// nothing about its delivery.
final class PlainSolo<S extends Object> extends Solo<S> {
  PlainSolo(super.initialState);
}
