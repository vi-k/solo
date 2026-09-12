import 'dart:async';

import 'close_mode.dart';
import 'solo_base.dart';

/// A controller for plain Dart and `StreamBuilder`: [SoloBase] plus a
/// broadcast [stream] of states.
class Solo<S extends Object> extends SoloBase<S> {
  final _controller = StreamController<S>.broadcast();
  Future<void>? _closed;

  /// Creates a controller in [initialState].
  Solo(super.initialState);

  /// Every state change, in order, delivered on the next microtask. The
  /// source of truth is [currentState]; an event may be older than it by
  /// the time it arrives. Equality is not checked: each change is an
  /// event.
  Stream<S> get stream => _controller.stream;

  /// Closes the engine, then the stream. Repeated calls return the same
  /// future, so the chain is built once and kept.
  @override
  Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) {
    final closed = _closed;
    if (closed != null) {
      // Handed on rather than answered here: a plain `close` over a drain
      // stops it in the engine, and the chain below is already built and
      // stays the future everybody waits for.
      unawaited(super.close(mode: mode));

      return closed;
    }
    // Stored before `super.close()` runs: a hook or an observer notified
    // from inside it may call `close` again and must get this same future.
    final completer = Completer<void>();
    _closed = completer.future;
    completer.complete(
      super.close(mode: mode).then((_) => _controller.close()),
    );
    return completer.future;
  }

  /// Pushes [current] into [stream].
  @override
  void publish(S previous, S current) {
    super.publish(previous, current);
    if (!_controller.isClosed) {
      _controller.add(current);
    }
  }
}
