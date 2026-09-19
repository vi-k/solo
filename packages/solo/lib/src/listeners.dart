/// The listeners of one notifier, in subscription order.
///
/// Plain Dart, no Flutter dependencies: what the core notifies through,
/// and what `flutter_solo` notifies through as well, from
/// `package:solo/listeners.dart`. Reporting a listener's failure is the
/// caller's, so the Flutter side of it stays in the Flutter package.
final class Listeners {
  final _entries = <_ListenerEntry>[];

  /// Whether nobody is listening.
  bool get isEmpty => _entries.isEmpty;

  /// Adds one registration of [listener].
  void add(void Function() listener) {
    _entries.add(_ListenerEntry(listener));
  }

  /// Deactivates and removes the earliest active registration of [listener].
  ///
  /// Returns `true` if a registration was found and removed, or `false`
  /// otherwise.
  bool remove(void Function() listener) {
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      // No test of `alive` here: a deactivated entry is taken out of the
      // list in the same breath, so the list holds live ones only. The
      // flag is for the snapshot `notify` walks, which is not this list.
      if (entry.listener == listener) {
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
  /// is isolated: an error thrown by a listener is handed to [report], and
  /// the pass continues.
  void notify(void Function(Object error, StackTrace stackTrace) report) {
    if (_entries.isEmpty) {
      return;
    }
    final snapshot = _entries.toList();
    for (final entry in snapshot) {
      if (!entry.alive) {
        continue;
      }
      try {
        entry.listener();
      } on Object catch (error, stackTrace) {
        report(error, stackTrace);
      }
    }
  }
}

final class _ListenerEntry {
  final void Function() listener;
  bool alive = true;

  _ListenerEntry(this.listener);
}
