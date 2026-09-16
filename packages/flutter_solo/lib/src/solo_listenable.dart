import 'package:flutter/foundation.dart';
import 'package:solo/solo.dart';

/// A [Solo] that is also a [ValueListenable]: drop it into
/// `ValueListenableBuilder` or `ListenableBuilder`.
///
/// The listeners are its only delivery. It is built on the engine
/// itself, not on `SoloStream`, because a widget has no use for a
/// broadcast `stream`: a screen rebuilds from [value], and an operation's
/// result is awaited through its `Job`. So there is no `StreamController`
/// here to carry, feed on every change and close afterwards -- unless
/// a subclass mixes `SoloStream` in for a caller that needs one too; see
/// "A controller with both deliveries" in `doc/flutter.md` for what that
/// combination costs.
///
/// Read-only on purpose: a `ValueNotifier` setter would break the
/// ownership guarantee. [value] and [currentState] are the same object.
class SoloListenable<S extends Object> extends Solo<S>
    implements ValueListenable<S> {
  /// Creates a controller in [initialState].
  SoloListenable(super.initialState);

  /// The current state; the same object as [currentState].
  @override
  S get value => currentState;

  /// Notifies through the engine's listeners, isolated through [FlutterError].
  ///
  /// The engine publishes from inside a state change and re-evaluates rules
  /// right after: a subscriber's failure is its own, and letting it out of
  /// here would cost a job the cancellation the new state owes it.
  @override
  void onListenerError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'flutter_solo',
        context: ErrorDescription(
          'notifying a listener of ${describeIdentity(this)}',
        ),
      ),
    );
  }
}
