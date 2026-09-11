import 'package:flutter/foundation.dart';

import 'listeners.dart';
import 'solo_listenable.dart';

/// One value picked out of a [SoloListenable], as a [ValueListenable] of
/// its own: a widget that needs the name rebuilds when the name changes
/// and not when the progress does.
///
/// [value] answers from the state every time, with or without listeners,
/// so it is never behind — a selector is a pick and is expected to be
/// cheap. What the selection keeps is the last value it announced, and it
/// keeps it to hold notifications back: listeners hear only a pick that
/// changed by `equals` — `==` unless another comparison is given — so a
/// state change that leaves the pick alone reaches nobody here. With
/// nobody listening the source is not subscribed to at all.
///
/// ```dart
/// class _ProfileState extends State<Profile> {
///   late final canSave = widget.controller.select((state) => state.canSave);
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
/// exists for is thrown away with it. Nothing has to be disposed of — the
/// last listener to go takes the subscription with it — and a selection
/// outlives its source harmlessly: a closed [SoloListenable] notifies
/// nobody, while [value] goes on answering, because it reads the state
/// and `externalSetState` is not blocked by closing either.
///
/// The selector runs inside the state change that triggered it, so it
/// should only pick: it must not change the state, start a job or close
/// the controller. An error it throws is reported and changes nothing
/// else, the same as an error of a listener.
final class SoloSelection<S extends Object, T> implements ValueListenable<T> {
  final SoloListenable<S> _source;
  final T Function(S state) _selector;
  final bool Function(T previous, T current) _equals;
  final _listeners = Listeners();

  /// The last value announced to the listeners, kept to tell a change
  /// from a state change that left the pick alone.
  T _selected;

  /// Picks [selector] out of [source], comparing the results with [equals]
  /// or with `==`.
  SoloSelection(
    SoloListenable<S> source,
    T Function(S state) selector, {
    bool Function(T previous, T current)? equals,
  })  : _source = source,
        _selector = selector,
        _equals = equals ?? _sameValue,
        _selected = selector(source.state);

  static bool _sameValue<T>(T previous, T current) => previous == current;

  /// The picked value, as the state has it right now.
  @override
  T get value => _selector(_source.state);

  /// Adds [listener], called when the picked value changes.
  ///
  /// The first one subscribes to the source; every one after it costs
  /// nothing more.
  @override
  void addListener(VoidCallback listener) {
    if (_listeners.isEmpty) {
      // Before the subscription, not after: the pick kept from now on must
      // be the one the state has at this moment, or the first change would
      // be compared against a value from whenever this object was made.
      _selected = _selector(_source.state);
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
    final next = _selector(_source.state);
    if (_equals(_selected, next)) {
      return;
    }
    _selected = next;
    _listeners.notify(this);
  }
}

/// [select] on every [SoloListenable].
///
/// An extension and not a member of the class: a controller of a domain is
/// a subclass of [SoloListenable], and `select` is a name such a subclass
/// may well want for itself — a list controller with `select(id)`, say.
/// A member would collide with it and stop the subclass from compiling; an
/// extension steps aside, and the subclass's own `select` wins.
extension SoloSelect<S extends Object> on SoloListenable<S> {
  /// A [SoloSelection] of [selector] over this controller.
  ///
  /// Hold the result rather than calling this in `build`; see
  /// [SoloSelection].
  SoloSelection<S, T> select<T>(
    T Function(S state) selector, {
    bool Function(T previous, T current)? equals,
  }) =>
      SoloSelection<S, T>(this, selector, equals: equals);
}
