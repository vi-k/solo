import 'package:flutter/foundation.dart';

/// The listeners of one notifier, in subscription order.
///
/// A list keeps the order and the repeated registrations; the map beside
/// it answers whether one is still registered in a single step, so a pass
/// over n listeners costs n lookups and not n squared.
final class Listeners {
  final _order = <VoidCallback>[];
  final _registrations = <VoidCallback, int>{};

  /// Whether nobody is listening.
  bool get isEmpty => _order.isEmpty;

  /// Adds one registration of [listener].
  void add(VoidCallback listener) {
    _order.add(listener);
    _registrations.update(listener, (count) => count + 1, ifAbsent: () => 1);
  }

  /// Removes one registration of [listener] and says whether there was
  /// one; unknown listeners are ignored.
  bool remove(VoidCallback listener) {
    if (!_order.remove(listener)) {
      return false;
    }
    final count = _registrations[listener]!;
    if (count == 1) {
      _registrations.remove(listener);
    } else {
      _registrations[listener] = count - 1;
    }

    return true;
  }

  /// Drops every registration.
  void clear() {
    _order.clear();
    _registrations.clear();
  }

  /// Calls every listener in subscription order, synchronously.
  ///
  /// One removed during the pass is skipped; one added during it hears the
  /// next change. A listener that throws is reported through
  /// [FlutterError.reportError], the way [ChangeNotifier] reports one, and
  /// the pass goes on to the listeners behind it: [owner] names the
  /// notifier in the report.
  void notify(Object owner) {
    for (final listener in _order.toList()) {
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
            context: ErrorDescription(
              'notifying a listener of ${owner.runtimeType}',
            ),
          ),
        );
      }
    }
  }
}
