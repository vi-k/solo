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

  /// How many registrations each listener has, to tell a listener still
  /// registered from one removed mid-pass without walking [_listeners]:
  /// a list lookup for every listener makes one pass quadratic.
  final _registrations = <VoidCallback, int>{};
  Future<void>? _closed;
  var _dropped = false;

  /// Creates a controller in [initialState].
  SoloListenable(super.initialState);

  /// The current state; the same object as [state].
  @override
  S get value => state;

  /// Adds [listener], called on every state change until removed.
  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    _registrations.update(listener, (count) => count + 1, ifAbsent: () => 1);
  }

  /// Removes one registration of [listener]; unknown listeners are ignored.
  @override
  void removeListener(VoidCallback listener) {
    if (!_listeners.remove(listener)) {
      return;
    }
    final count = _registrations[listener]!;
    if (count == 1) {
      _registrations.remove(listener);
    } else {
      _registrations[listener] = count - 1;
    }
  }

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
    for (final listener in _listeners.toList()) {
      if (!_registrations.containsKey(listener)) {
        continue;
      }
      try {
        listener();
      } on Object catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'flutter_solo',
            context: ErrorDescription('notifying a listener of $runtimeType'),
          ),
        );
      }
    }
  }

  /// Closes the engine and the stream, then drops every listener and stops
  /// notifying for good. Repeated calls return the same future, so the
  /// chain is built once and kept.
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
    completer.complete(
      super.close().then((_) {
        _dropped = true;
        _listeners.clear();
        _registrations.clear();
      }),
    );
    return completer.future;
  }
}
