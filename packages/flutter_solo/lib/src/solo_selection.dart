import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:solo/solo.dart';

import 'listeners.dart';
import 'solo_listenable.dart';
import 'solo_selector.dart';

/// One value picked out of a [ValueListenable], as a [ValueListenable] of
/// its own: a widget that needs the name rebuilds when the name changes
/// and not when the progress does.
///
/// [value] answers from the value the source has now, with or without
/// listeners, so it is never behind — a selector is a pick and is expected
/// to be cheap, and to answer the same for the same value of the source.
/// That lets a subscribed selection pick once per change: the pick made to
/// decide whether to notify is the one a listener reads back from [value].
/// What the selection keeps besides is the last value it announced, and it
/// keeps it to hold notifications back: listeners hear only a pick that
/// `changed` calls changed — `!=` unless another answer is given — so a
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
/// exists for is thrown away with it. A field is built from the first
/// widget only, though: a `State` whose widget can be handed another
/// source builds the selection again in `didUpdateWidget`, or it goes on
/// picking from the old one. [SoloSelector] is the same pick over a
/// controller, with nowhere to hold it — the widget keeps the selection
/// itself and follows a new controller on its own.
/// Nothing has to be disposed of — the last listener to go takes the
/// subscription with it — and a selection outlives its source harmlessly:
/// a closed [SoloListenable] no longer changes state, while [value] keeps
/// reading the source's final state.
///
/// The selector runs inside the change that triggered it, so it should
/// only pick: over a [SoloListenable] that means it must not change the
/// state, start a job or close the controller. An error it throws is
/// reported and changes nothing else, the same as an error of a listener.
final class SoloSelection<S, T> implements ValueListenable<T> {
  final ValueListenable<S> _source;
  final T Function(S value) _selector;
  final bool Function(T previous, T current) _changed;
  final _listeners = Listeners();

  /// The last value announced to the listeners, kept to tell a change
  /// from a change of the source that left the pick alone.
  late T _selected;
  var _subscribing = false;

  /// The source value the last pick was made from, while the selection is
  /// subscribed. A notification is what says the value may have changed,
  /// so a read of [value] against the same object is answered with
  /// [_picked] rather than picked again. Without a subscription nothing
  /// says so, and [value] picks every time; the field is cleared then only
  /// so an idle selection does not hold on to an old value of the source.
  Object? _pickedFrom = _none;
  late T _picked;

  /// Set when the source notifies while it is being subscribed to.
  var _heardWhileSubscribing = false;

  static const _none = Object();

  /// Picks [selector] out of [source]; [changed] answers whether the pick
  /// changed, `!=` when it is omitted.
  SoloSelection(
    ValueListenable<S> source,
    T Function(S value) selector, {
    bool Function(T previous, T current)? changed,
  })  : _source = source,
        _selector = selector,
        _changed = changed ?? _differ;

  /// Picks [selector] out of [solo], a controller that need not be a
  /// [ValueListenable]: a plain [Solo], or one with `SoloStream`.
  ///
  /// A static method rather than a constructor: a constructor takes the
  /// type parameters of its class, and this class leaves `S` unbounded
  /// where [Solo] requires `S extends Object`.
  static SoloSelection<S, T> from<S extends Object, T>(
    Solo<S> solo,
    T Function(S state) selector, {
    bool Function(T previous, T current)? changed,
  }) =>
      SoloSelection<S, T>(
        _SoloSource(solo),
        selector,
        changed: changed,
      );

  /// The default answer of `changed`.
  static bool _differ<T>(T previous, T current) => previous != current;

  /// The picked value, as the source has it right now.
  @override
  T get value {
    final source = _source.value;
    if (!_listeners.isEmpty && identical(source, _pickedFrom)) {
      return _picked;
    }
    return _pick(source);
  }

  /// Picks [source], kept for [value] while somebody listens.
  T _pick(S source) {
    final picked = _selector(source);
    if (!_listeners.isEmpty) {
      _pickedFrom = source;
      _picked = picked;
    }
    return picked;
  }

  /// Adds [listener], called when the picked value changes.
  ///
  /// The first one subscribes to the source; every one after it costs
  /// nothing more.
  @override
  void addListener(VoidCallback listener) {
    final first = _listeners.isEmpty;
    _listeners.add(listener);
    if (first) {
      // Before the subscription, not after: a source may publish while it
      // is being subscribed to, and that change is found by comparing
      // against the pick it had before.
      var subscriptionAttempted = false;
      try {
        final before = _source.value;
        _selected = _pick(before);
        _subscribing = true;
        _heardWhileSubscribing = false;
        subscriptionAttempted = true;
        _source.addListener(_onSourceChanged);
        _subscribing = false;

        // Picked again only when the source moved while it was being
        // subscribed to, the way a lazy source does on its first listener.
        final after = _source.value;
        if (_heardWhileSubscribing || !identical(before, after)) {
          final next = _pick(after);
          if (_changed(_selected, next)) {
            _selected = next;
            scheduleMicrotask(() => _listeners.notify(this));
          }
        }
      } on Object catch (_) {
        _subscribing = false;
        if (subscriptionAttempted) {
          _source.removeListener(_onSourceChanged);
        }
        _listeners.remove(listener);
        _pickedFrom = _none;
        rethrow;
      }
    }
  }

  /// Removes one registration of [listener]; unknown listeners are
  /// ignored. Losing the last one drops the subscription to the source.
  @override
  void removeListener(VoidCallback listener) {
    if (!_listeners.remove(listener) || !_listeners.isEmpty) {
      return;
    }
    _source.removeListener(_onSourceChanged);
    _pickedFrom = _none;
  }

  void _onSourceChanged() {
    if (_subscribing) {
      _heardWhileSubscribing = true;
      return;
    }
    // Picked afresh, not looked up: a source may change its value in place
    // and say so, and the notification is the only sign of it. The kept
    // pick goes first, so a selector that throws here leaves none behind.
    final source = _source.value;
    _pickedFrom = _none;
    final next = _pick(source);
    if (!_changed(_selected, next)) {
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

final class _SoloSource<S extends Object> implements ValueListenable<S> {
  final Solo<S> _solo;

  _SoloSource(this._solo);

  @override
  S get value => _solo.currentState;

  @override
  void addListener(VoidCallback listener) => _solo.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _solo.removeListener(listener);
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
/// a controller of a domain mixes it in, and `select` is a name such a
/// controller may well want for itself — a list controller with
/// `select(id)`, say. A member of the mixin would collide with it and stop
/// the controller from compiling; an extension steps aside, and the
/// controller's own `select` wins.
extension SoloSelect<S> on ValueListenable<S> {
  /// A [SoloSelection] of [selector] over this listenable.
  ///
  /// Hold the result rather than calling this in `build`; see
  /// [SoloSelection].
  SoloSelection<S, T> select<T>(
    T Function(S value) selector, {
    bool Function(T previous, T current)? changed,
  }) =>
      SoloSelection<S, T>(this, selector, changed: changed);
}
