import 'dart:async';

import 'package:flutter/foundation.dart';

/// The listeners of one notifier, in subscription order.
///
/// Duplicated from `solo` because the core cannot import Flutter.
final class Listeners {
  final _entries = <_ListenerEntry>[];

  /// Whether nobody is listening.
  bool get isEmpty => _entries.isEmpty;

  /// Adds one registration of [listener].
  void add(VoidCallback listener) {
    _entries.add(_ListenerEntry(listener));
  }

  /// Deactivates and removes the earliest active registration of [listener].
  ///
  /// Returns `true` if a registration was found and removed, or `false`
  /// otherwise.
  bool remove(VoidCallback listener) {
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      if (entry.alive && entry.listener == listener) {
        entry.alive = false;
        _entries.removeAt(i);
        return true;
      }
    }
    return false;
  }

  /// Deactivates and drops every registration.
  void clear() {
    for (final entry in _entries) {
      entry.alive = false;
    }
    _entries.clear();
  }

  /// Calls every active listener in subscription order, synchronously.
  ///
  /// Iterates over a snapshot of entries. A listener removed during the pass
  /// is skipped; one added during the pass hears the next change. Each call
  /// is isolated: an error thrown by a listener is reported through
  /// [FlutterError.reportError], with [owner] naming the notifier in the
  /// report. If the reporter itself throws, the pass continues and the
  /// reporter's error is routed to [Zone.handleUncaughtError].
  void notify(Object owner) {
    final snapshot = _entries.toList();
    for (final entry in snapshot) {
      if (!entry.alive) {
        continue;
      }
      try {
        entry.listener();
      } on Object catch (error, stackTrace) {
        _report(owner, error, stackTrace);
      }
    }
  }

  static void _report(Object owner, Object error, StackTrace stackTrace) {
    try {
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
    } on Object catch (reporterError, reporterStackTrace) {
      Zone.current.handleUncaughtError(reporterError, reporterStackTrace);
    }
  }
}

final class _ListenerEntry {
  final VoidCallback listener;
  bool alive = true;

  _ListenerEntry(this.listener);
}
