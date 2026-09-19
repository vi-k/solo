import 'package:flutter/foundation.dart';

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
/// The group holds what it would cancel and nothing else: a member
/// cancelled on its own is forgotten, so a long-lived group — a screen
/// that resubscribes on every update, a service that listens to whatever
/// it is handed — does not grow one dead entry per subscription that
/// ended by itself.
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

  /// How many live subscriptions the group holds.
  ///
  /// A cancelled one is not held, whether the group cancelled it or
  /// somebody cancelled that one alone.
  int get length {
    _forgetCancelled();

    return _subscriptions.length;
  }

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
    // Takes out this one, if it was cancelled before it got here, and the
    // members somebody cancelled one at a time: what is left is what the
    // group would cancel.
    _forgetCancelled();
  }

  /// Drops the members somebody cancelled one at a time.
  ///
  /// A cancelled subscription has nothing left for the group to do, and
  /// held on to it keeps the listener and whatever the closure closed over
  /// alive — the leak this class exists to prevent, one object further
  /// along.
  void _forgetCancelled() =>
      _subscriptions.removeWhere((subscription) => subscription.isCancelled);

  /// Cancels every subscription in the group and empties it; calling it
  /// again does nothing.
  ///
  /// One that cannot let go is no reason to walk away from the ones behind
  /// it, which are still listening — that is the leak this class exists to
  /// prevent. So every member is cancelled and every failure goes to
  /// [FlutterError.reportError].
  ///
  /// This never throws, whatever a member does. The place for the call is
  /// `State.dispose()`, and an exception out of `dispose()` stops the
  /// framework unmounting the rest of that frame: the elements queued
  /// behind this one lose their `dispose()` altogether, and their
  /// listeners stay registered — the leak again, one widget further along.
  /// There is nobody to catch a throw from here, and a frame is what it
  /// costs.
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    for (final subscription in _subscriptions) {
      try {
        subscription.cancel();
      } on Object catch (error, stackTrace) {
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
    _subscriptions.clear();
  }
}

/// [listen] on every [Listenable].
///
/// Exported from `package:flutter_solo/listenable.dart` and not from the
/// package itself: it sits on a type of the framework, where a `listen`
/// of another package sits too, and two extensions with the same member
/// name on the same type make every call of it ambiguous. Import the one
/// you want the method from.
extension SoloListen on Listenable {
  /// Registers [listener] and hands back the way to take it back.
  ///
  /// The same thing as [Listenable.addListener], with the callback kept
  /// for you; see [SoloSubscription].
  SoloSubscription listen(VoidCallback listener) {
    addListener(listener);

    return SoloSubscription._(this, listener);
  }
}
