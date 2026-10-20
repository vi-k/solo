import 'dart:async';

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

  /// What is registered on the listenable: this subscription's own rather
  /// than [_listener], so [cancel] takes back this registration and no
  /// other. One callback listened to twice is two registrations, and
  /// `removeListener` with the callback itself takes off the first of
  /// them, whichever subscription is cancelled. Kept in a field rather than
  /// torn off again: a new tear-off is `==` to this one but not identical,
  /// and a listenable of somebody's own may compare either way.
  late final VoidCallback _registered = _notify;

  var _cancelled = false;

  /// The groups that hold this subscription. Cancelled on its own, it
  /// leaves them at once rather than waiting to be swept out.
  ///
  /// Weakly: a group dropped without [SoloSubscriptions.cancel] would
  /// otherwise live as long as any one of its members is kept, and hold
  /// every other member with it.
  final _groups = <WeakReference<SoloSubscriptions>>[];

  SoloSubscription._(this._listenable, this._listener);

  /// A listenable whose `removeListener` threw keeps the callback and may
  /// call it still; cancelled is cancelled all the same.
  void _notify() {
    if (!_cancelled) {
      _listener();
    }
  }

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Puts this subscription into [subscriptions].
  void addTo(SoloSubscriptions subscriptions) => subscriptions.add(this);

  /// Takes the listener back; calling it again does nothing.
  ///
  /// Repeating it is not a mistake worth a complaint, the same way a
  /// repeated `close` of a controller is not, and an unknown listener
  /// handed to `removeListener` is not.
  ///
  /// From here on the listener is not called, even by a listenable whose
  /// `removeListener` throws and keeps it.
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    for (final group in _groups) {
      group.target?._subscriptions.remove(this);
    }
    _groups.clear();
    _listenable.removeListener(_registered);
  }
}

/// A group of subscriptions cancelled together, for a screen or an object
/// that listens to several things at once.
///
/// The group holds what it would cancel and nothing else: a member cancelled on
/// its own is forgotten, so a long-lived group — a screen that resubscribes on
/// every update, a service that listens to whatever it is handed — does not
/// grow one dead entry per subscription that ended by itself.
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
  /// In the order they came, and each one once.
  final _subscriptions = <SoloSubscription>{};

  var _cancelled = false;

  /// Creates an empty group.
  SoloSubscriptions();

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// How many live subscriptions the group holds.
  ///
  /// A cancelled one is not held, whether the group cancelled it or
  /// somebody cancelled that one alone.
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
    // A cancelled subscription has nothing left for the group to do, and
    // held on to, it keeps the listener and whatever the closure closed
    // over alive — the leak this class exists to prevent, one object
    // further along.
    if (subscription.isCancelled || !_subscriptions.add(subscription)) {
      return;
    }
    subscription._groups.add(WeakReference(this));
  }

  /// Cancels every subscription in the group and empties it; calling it
  /// again does nothing.
  ///
  /// One that cannot let go is no reason to walk away from the ones behind
  /// it, which are still listening — that is the leak this class exists to
  /// prevent. So every member is cancelled and every failure goes to
  /// [FlutterError.reportError], or to the zone when the reporter throws.
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
    // A copy, emptied out of the group first: `removeListener` is the
    // source's code, and whatever it does to the group — reads [length],
    // cancels another member — must not cut the walk short.
    final members = _subscriptions.toList();
    _subscriptions.clear();
    for (final subscription in members) {
      try {
        subscription.cancel();
      } on Object catch (error, stackTrace) {
        _report(error, stackTrace);
      }
    }
  }

  /// Reports a member's failure through [FlutterError].
  ///
  /// A reporter that throws does not take the member's failure with it,
  /// nor the members behind it: both errors go to the zone, the member's
  /// first, and the walk goes on.
  void _report(Object error, StackTrace stackTrace) {
    try {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'flutter_solo',
          context: ErrorDescription('while cancelling a $SoloSubscriptions'),
        ),
      );
    } on Object catch (reporterError, reporterStackTrace) {
      Zone.current
        ..handleUncaughtError(error, stackTrace)
        ..handleUncaughtError(reporterError, reporterStackTrace);
    }
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
  /// [Listenable.addListener] with the callback kept for you; see
  /// [SoloSubscription]. What goes to `addListener` is the subscription's
  /// own callback that calls [listener], so the subscription is the way
  /// back: `removeListener(listener)` does not find it.
  ///
  /// An `addListener` that throws is thrown on, with the subscription
  /// cancelled first: nobody would get it to cancel later. The listener is
  /// not called whatever the listenable kept, and a `removeListener` that
  /// throws as well is thrown in place of the first error.
  SoloSubscription listen(VoidCallback listener) {
    final subscription = SoloSubscription._(this, listener);
    try {
      addListener(subscription._registered);
    } on Object catch (_) {
      subscription.cancel();
      rethrow;
    }

    return subscription;
  }
}
