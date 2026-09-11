import 'package:flutter/foundation.dart';

import 'solo_listenable.dart';
import 'solo_selection.dart';

/// A listener registered on a [Listenable], and the way to take it back.
///
/// The plain way needs the callback kept somewhere so that
/// [Listenable.removeListener] can be given the same object back:
///
/// ```dart
/// void _listener() {}
///
/// controller.addListener(_listener);
/// controller.removeListener(_listener);
/// ```
///
/// A subscription holds it instead, so a closure works as well as a method
/// and the listening ends where the object goes:
///
/// ```dart
/// final subscription = controller.listen(() => print(controller.value));
/// subscription.cancel();
/// ```
final class SoloSubscription {
  final Listenable _listenable;
  final VoidCallback _listener;

  var _cancelled = false;

  SoloSubscription._(this._listenable, this._listener);

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Puts this subscription into [subscriptions].
  void addTo(SoloSubscriptions subscriptions) => subscriptions.add(this);

  /// Takes the listener back; calling it again does nothing.
  ///
  /// Repeating it is not a mistake worth a complaint, the same way a
  /// repeated `close` of a controller is not, and an unknown listener
  /// handed to `removeListener` is not.
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _listenable.removeListener(_listener);
  }
}

/// A group of subscriptions cancelled together, for a screen or an object
/// that listens to several things at once.
///
/// ```dart
/// final _listening = SoloSubscriptions();
///
/// void _start() {
///   controller.listen(_onState).addTo(_listening);
///   canSave.listen(_onCanSave).addTo(_listening);
/// }
///
/// @override
/// void dispose() {
///   _listening.cancel();
///   super.dispose();
/// }
/// ```
final class SoloSubscriptions {
  final _subscriptions = <SoloSubscription>[];

  var _cancelled = false;

  /// Creates an empty group.
  SoloSubscriptions();

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// How many subscriptions are held, cancelled ones included.
  int get length => _subscriptions.length;

  /// Takes [subscription] into the group.
  ///
  /// A group that has been cancelled takes nothing, and cancels what it is
  /// handed on the spot rather than keeping it: the subscription was made
  /// on the line before this call, nothing else holds it, and dropping it
  /// silently would leave behind exactly the listener this class exists to
  /// take back.
  void add(SoloSubscription subscription) {
    if (_cancelled) {
      subscription.cancel();

      return;
    }
    _subscriptions.add(subscription);
  }

  /// Cancels every subscription in the group and empties it; calling it
  /// again does nothing.
  ///
  /// One that cannot let go is no reason to walk away from the ones behind
  /// it, which are still listening — that is the leak this class exists to
  /// prevent. So every member is cancelled, the first error is thrown when
  /// the pass is over, and the ones after it go to
  /// [FlutterError.reportError]: a throw carries one failure and the first
  /// has claimed it.
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    Object? failure;
    StackTrace? failureTrace;
    for (final subscription in _subscriptions) {
      try {
        subscription.cancel();
      } on Object catch (error, stackTrace) {
        if (failure == null) {
          failure = error;
          failureTrace = stackTrace;
        } else {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'flutter_solo',
              context: ErrorDescription(
                'while cancelling a $SoloSubscriptions',
              ),
            ),
          );
        }
      }
    }
    _subscriptions.clear();
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureTrace!);
    }
  }
}

/// [listen] on a controller.
extension SoloListen<S extends Object> on SoloListenable<S> {
  /// Registers [listener] and hands back the way to take it back.
  ///
  /// The same thing as [Listenable.addListener], with the callback kept
  /// for you; see [SoloSubscription].
  SoloSubscription listen(VoidCallback listener) {
    addListener(listener);

    return SoloSubscription._(this, listener);
  }
}

/// [listen] on a selection.
extension SoloSelectionListen<S extends Object, T> on SoloSelection<S, T> {
  /// Registers [listener] and hands back the way to take it back.
  ///
  /// The same thing as [Listenable.addListener], with the callback kept
  /// for you; see [SoloSubscription].
  SoloSubscription listen(VoidCallback listener) {
    addListener(listener);

    return SoloSubscription._(this, listener);
  }
}
