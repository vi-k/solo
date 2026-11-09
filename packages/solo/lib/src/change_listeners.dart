/// The listeners of one controller that are told each change as a pair, in
/// subscription order.
///
/// The same rules as `Listeners` of `listeners.dart`, for a listener that
/// takes the previous and the current state. Not exported: a caller sees
/// `Solo.addChangeListener`, not this list.
final class ChangeListeners<S> {
  final _entries = <_ChangeListenerEntry<S>>[];

  /// Whether nobody is listening.
  bool get isEmpty => _entries.isEmpty;

  /// Adds one registration of [listener].
  void add(void Function(S previous, S current) listener) {
    _entries.add(_ChangeListenerEntry(listener));
  }

  /// Deactivates and removes the earliest active registration of [listener].
  ///
  /// Returns `true` if a registration was found and removed, or `false`
  /// otherwise.
  bool remove(void Function(S previous, S current) listener) {
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      // The list holds live entries only, as in `Listeners`: the flag is for
      // the snapshot `notify` walks.
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

  /// Calls every active listener with [previous] and [current] in
  /// subscription order, synchronously.
  ///
  /// Iterates over a snapshot of entries. A listener removed during the pass
  /// is skipped; one added during the pass hears the next change. Each call
  /// is isolated: an error thrown by a listener is handed to [report], and
  /// the pass continues.
  void notify(
    S previous,
    S current,
    void Function(Object error, StackTrace stackTrace) report,
  ) {
    if (_entries.isEmpty) {
      return;
    }
    final snapshot = _entries.toList();
    for (final entry in snapshot) {
      if (!entry.alive) {
        continue;
      }
      try {
        entry.listener(previous, current);
      } on Object catch (error, stackTrace) {
        report(error, stackTrace);
      }
    }
  }
}

final class _ChangeListenerEntry<S> {
  final void Function(S previous, S current) listener;
  bool alive = true;

  _ChangeListenerEntry(this.listener);
}
