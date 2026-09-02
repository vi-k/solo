import 'dart:async';

import 'solo_base.dart';

/// A controller for plain Dart and `StreamBuilder`: [SoloBase] plus a
/// broadcast [stream] of states.
class Solo<S extends Object> extends SoloBase<S> {
  final _controller = StreamController<S>.broadcast();

  /// Creates a controller in [initialState].
  Solo(super.initialState);

  /// Every state change, in order, delivered on the next microtask. The
  /// source of truth is [state]; an event may be older than [state] by the
  /// time it arrives. Equality is not checked: each change is an event.
  Stream<S> get stream => _controller.stream;

  /// Pushes [current] into [stream].
  @override
  void publish(S previous, S current) {
    super.publish(previous, current);
    if (!_controller.isClosed) {
      _controller.add(current);
    }
  }
}
