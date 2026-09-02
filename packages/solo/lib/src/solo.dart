import 'solo_base.dart';

/// A controller for plain Dart and `StreamBuilder`: [SoloBase] plus a
/// broadcast stream of states.
class Solo<S extends Object> extends SoloBase<S> {
  /// Creates a controller in [initialState].
  Solo(super.initialState);
}
