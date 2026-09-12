import 'package:flutter/foundation.dart';

import 'listeners.dart';
import 'solo_listenable.dart';
import 'solo_selector.dart';

/// One value picked out of a [ValueListenable], as a [ValueListenable] of
/// its own: a widget that needs the name rebuilds when the name changes
/// and not when the progress does.
///
/// [value] answers from the source every time, with or without listeners,
/// so it is never behind — a selector is a pick and is expected to be
/// cheap. What the selection keeps is the last value it announced, and it
/// keeps it to hold notifications back: listeners hear only a pick that
/// `compare` calls changed — `!=` unless another answer is given — so a
/// change of the source that leaves the pick alone reaches nobody here.
/// With nobody listening the source is not subscribed to at all.
///
/// ```dart
/// class _ProfileState extends State<Profile> {
///   late final canSave =
///       SoloSelection(widget.controller, (state) => state.canSave);
///
///   @override
///   Widget build(BuildContext context) => ValueListenableBuilder(
///         valueListenable: canSave,
///         builder: (context, canSave, _) => ElevatedButton(
///           onPressed: canSave ? _save : null,
///           child: const Text('Save'),
///         ),
///       );
/// }
/// ```
///
/// Hold the selection, do not build one in `build`: a new object every
/// frame subscribes and unsubscribes every frame, and the kept value it
/// exists for is thrown away with it. [SoloSelector] is the same pick
/// with nowhere to hold it — the widget keeps the selection itself.
/// Nothing has to be disposed of — the last listener to go takes the
/// subscription with it — and a selection outlives its source harmlessly:
/// a closed [SoloListenable] notifies nobody, while [value] goes on
/// answering, because it reads the source and `externalSetState` is not
/// blocked by closing either.
///
/// The selector runs inside the change that triggered it, so it should
/// only pick: over a [SoloListenable] that means it must not change the
/// state, start a job or close the controller. An error it throws is
/// reported and changes nothing else, the same as an error of a listener.
final class SoloSelection<S, T> implements ValueListenable<T> {
  final ValueListenable<S> _source;
  final T Function(S value) _selector;
  final bool Function(T previous, T current) _compare;
  final _listeners = Listeners();

  /// The last value announced to the listeners, kept to tell a change
  /// from a change of the source that left the pick alone.
  T _selected;

  /// Picks [selector] out of [source]; [compare] answers whether the pick
  /// changed, `!=` when it is omitted.
  SoloSelection(
    ValueListenable<S> source,
    T Function(S value) selector, {
    bool Function(T previous, T current)? compare,
  })  : _source = source,
        _selector = selector,
        _compare = compare ?? _changed,
        _selected = selector(source.value);

  /// `true` means the pick changed, the same way `compare` answers.
  static bool _changed<T>(T previous, T current) => previous != current;

  /// The picked value, as the source has it right now.
  @override
  T get value => _selector(_source.value);

  /// Adds [listener], called when the picked value changes.
  ///
  /// The first one subscribes to the source; every one after it costs
  /// nothing more.
  @override
  void addListener(VoidCallback listener) {
    if (_listeners.isEmpty) {
      // Before the subscription, not after: the pick kept from now on must
      // be the one the source has at this moment, or the first change would
      // be compared against a value from whenever this object was made.
      _selected = _selector(_source.value);
      _source.addListener(_onSourceChanged);
    }
    _listeners.add(listener);
  }

  /// Removes one registration of [listener]; unknown listeners are
  /// ignored. Losing the last one drops the subscription to the source.
  @override
  void removeListener(VoidCallback listener) {
    if (!_listeners.remove(listener) || !_listeners.isEmpty) {
      return;
    }
    _source.removeListener(_onSourceChanged);
  }

  void _onSourceChanged() {
    final next = _selector(_source.value);
    if (!_compare(_selected, next)) {
      return;
    }
    // Written before the listeners run: one of them is free to change the
    // source from in here, and the pick it has already been handed must not
    // set a walk of its own going. Not taken back when a listener throws
    // either — [value] reads the source rather than this, so a listener that
    // missed a notification is a rebuild missed, not a value stuck.
    _selected = next;
    _listeners.notify(this);
  }
}

/// [select] on every [ValueListenable].
///
/// Exported from `package:flutter_solo/listenable.dart` and not from the
/// package itself: it sits on a type of the framework, where a `select`
/// of another package sits too, and two extensions with the same member
/// name on the same type make every call of it ambiguous. Import the one
/// you want the method from; without it the selection is still built
/// directly, `SoloSelection(controller, (state) => state.canSave)`.
///
/// An extension and not a member of [SoloListenable] for a second reason:
/// a controller of a domain is a subclass of it, and `select` is a name
/// such a subclass may well want for itself — a list controller with
/// `select(id)`, say. A member would collide with it and stop the
/// subclass from compiling; an extension steps aside, and the subclass's
/// own `select` wins.
extension SoloSelect<S> on ValueListenable<S> {
  /// A [SoloSelection] of [selector] over this listenable.
  ///
  /// Hold the result rather than calling this in `build`, or let
  /// [SoloSelector] hold it; see [SoloSelection].
  SoloSelection<S, T> select<T>(
    T Function(S value) selector, {
    bool Function(T previous, T current)? compare,
  }) =>
      SoloSelection<S, T>(this, selector, compare: compare);
}
