import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:solo/solo.dart';

import 'listeners.dart';

/// A [Solo] that is also a [ValueListenable]: drop it into
/// `ValueListenableBuilder` or `ListenableBuilder`.
///
/// Read-only on purpose: a `ValueNotifier` setter would break the
/// ownership guarantee. [value] and [currentState] are the same object.
class SoloListenable<S extends Object> extends Solo<S>
    implements ValueListenable<S> {
  final _listeners = Listeners();
  Future<void>? _closed;
  var _dropped = false;

  /// Creates a controller in [initialState].
  SoloListenable(super.initialState);

  /// The current state; the same object as [currentState].
  @override
  S get value => currentState;

  /// Adds [listener], called on every state change until removed.
  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  /// Removes one registration of [listener]; unknown listeners are ignored.
  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Queues the event for the stream, then notifies listeners in
  /// subscription order, synchronously. A listener removed during the pass
  /// is skipped; one added during the pass hears the next change.
  ///
  /// Nobody is notified once [close] has finished — the listeners are gone
  /// by then, and one added afterwards hears nothing either, the same way
  /// the stream of a closed [Solo] drops its events. A state can still
  /// change there: `externalSetState` is not blocked by [close].
  ///
  /// A listener that throws is reported through [FlutterError.reportError],
  /// the way [ChangeNotifier] reports one, and the pass goes on to the
  /// listeners behind it. The engine publishes from inside a state change
  /// and re-evaluates the rules of running jobs right after: a subscriber's
  /// failure is its own, and letting it out of here would cost a job the
  /// cancellation the new state owes it.
  @override
  void publish(S previous, S current) {
    super.publish(previous, current);
    if (_dropped) {
      return;
    }
    _listeners.notify(this);
  }

  /// Closes the engine and the stream, then drops every listener and stops
  /// notifying for good. Repeated calls return the same future, so the
  /// chain is built once and kept. [mode] is [Solo.close]'s.
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
    // Stored before `super.close()` runs: a hook or a listener notified
    // from inside it may call `close` again and must get this same future.
    final completer = Completer<void>();
    _closed = completer.future;
    completer.complete(
      super.close(mode: mode).then((_) {
        _dropped = true;
        _listeners.clear();
      }),
    );
    return completer.future;
  }
}
