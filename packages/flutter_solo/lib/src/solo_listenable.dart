import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:solo/solo.dart';

/// A [Solo] that is also a [ValueListenable]: drop it into
/// `ValueListenableBuilder` or `ListenableBuilder`.
///
/// Read-only on purpose: a `ValueNotifier` setter would break the
/// ownership guarantee. [value] and [state] are the same object.
class SoloListenable<S extends Object> extends Solo<S>
    implements ValueListenable<S> {
  final _listeners = <VoidCallback>[];
  Future<void>? _closed;

  /// Creates a controller in [initialState].
  SoloListenable(super.initialState);

  /// The current state; the same object as [state].
  @override
  S get value => state;

  /// Adds [listener], called on every state change until removed.
  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  /// Removes one registration of [listener]; unknown listeners are ignored.
  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Queues the event for the stream, then notifies listeners in
  /// subscription order, synchronously. A listener removed during the pass
  /// is skipped; one added during the pass hears the next change.
  @override
  void publish(S previous, S current) {
    super.publish(previous, current);
    for (final listener in _listeners.toList()) {
      if (_listeners.contains(listener)) {
        listener();
      }
    }
  }

  /// Closes the engine and the stream, then drops every listener. Repeated
  /// calls return the same future, so the chain is built once and kept.
  @override
  Future<void> close() {
    final closed = _closed;
    if (closed != null) {
      return closed;
    }
    // Stored before `super.close()` runs: a hook or a listener notified
    // from inside it may call `close` again and must get this same future.
    final completer = Completer<void>();
    _closed = completer.future;
    completer.complete(super.close().then((_) => _listeners.clear()));
    return completer.future;
  }
}
