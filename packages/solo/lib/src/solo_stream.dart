import 'dart:async';

import 'close_mode.dart';
import 'solo.dart';

/// Adds a broadcast [stream] of states to [Solo].
///
/// The stream is fed from [publish]: put `SoloStream` first among the
/// mixins in `with` unless a neighbor's own delivery should decide what
/// the stream sees. A neighbor that calls `super.publish` and then
/// throws still lets the stream receive the change when it sits above
/// `SoloStream`; sitting below it, the throw happens on the way back
/// through `SoloStream`'s own line, and the stream never sees the
/// event. Either order, the error itself still escapes and costs the
/// running jobs their re-evaluation of state rules -- see "A failure
/// must not leave `publish`" in `doc/state.md`.
mixin SoloStream<S extends Object> on Solo<S> {
  final _controller = StreamController<S>.broadcast();
  Future<void>? _closed;

  /// Every state change, in order, delivered on the next microtask. The
  /// source of truth is [currentState]; an event may be older than it by
  /// the time it arrives. Equality is not checked: each change is an
  /// event.
  Stream<S> get stream => _controller.stream;

  /// Closes the engine, then the stream. Repeated calls return the same
  /// future, so the chain is built once and kept.
  ///
  /// The stream closes once every subscription has taken its done event,
  /// so one left paused holds the returned future until it is resumed or
  /// cancelled. The engine is closed by then: [isFinished] is true and
  /// [pending] is `null`, and a close held with both is held here.
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
