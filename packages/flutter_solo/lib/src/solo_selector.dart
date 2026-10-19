import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:solo/solo.dart';

import 'solo_builder.dart';
import 'solo_selection.dart';

/// Rebuilds its subtree when one value picked out of a [Solo]'s state
/// changes: what a [SoloSelection] does, for a widget that has nowhere to
/// keep one.
///
/// ```dart
/// SoloSelector<Profile, bool>(
///   solo: controller,
///   selector: (state) => state.canSave,
///   builder: (context, canSave, _) => ElevatedButton(
///     onPressed: canSave ? controller.save : null,
///     child: const Text('Save'),
///   ),
/// )
/// ```
///
/// The button drops the job `save` hands back: a failed save goes on to the
/// zone. A screen that tells the user of it waits for the job's `done`.
///
/// It takes any [Solo] — one with `SoloListenable`, one with `SoloStream`
/// or a plain one — and is to [SoloBuilder] what a pick is to the whole
/// state. A [ValueListenable] that is not a controller is picked from with
/// a [SoloSelection] of its own and a `ValueListenableBuilder`.
///
/// A selection earns its keep by being kept: one built in `build` and dropped
/// at the end of it is subscribed to and unsubscribed from on every build, and
/// the announced value it holds notifications back with goes with it. That is
/// what a `State` field was for, and it is what this widget carries instead:
/// its subscription to [solo] and the pick it last accepted. So the picking
/// widget can be a `StatelessWidget`, and a screen that picks three values out
/// of one controller needs no `State` at all. Nothing has to be disposed of:
/// the widget going away takes its listener off [solo].
///
/// Of what it is given the widget compares [solo] alone. [selector] and
/// [changed] are called as the widget has them at the moment, so a closure
/// written in place is as good as a function held in a field: a parent
/// rebuild moves no subscription and does not start the value over.
final class SoloSelector<S extends Object, T> extends StatefulWidget {
  /// The controller to pick out of.
  ///
  /// Compared by identity when the parent rebuilds: handed a new
  /// controller whose `==` says it is the old one, the widget moves to the
  /// new one all the same.
  final Solo<S> solo;

  /// Picks the value this widget rebuilds for.
  ///
  /// Called once on mounting and once for every change of the state. The
  /// inline `(state) => state.canSave` above is a different object on
  /// every build of the parent, and a new function may pick something
  /// else: there is no way to ask one closure whether it does what another
  /// did. So a parent rebuild that hands over another [selector] or
  /// another [changed] picks once more and puts the pick to [changed].
  /// One that hands over the same two calls neither.
  final T Function(S state) selector;

  /// Answers whether the pick changed, `!=` when it is omitted.
  ///
  /// `previous` is the pick the widget last accepted: the first one, or the
  /// last one this function called changed. It stays that across a parent
  /// rebuild, whether this function is held in a field or written in place.
  /// [builder] has usually been given it already, but not always: when two
  /// changes come before a frame and the first is accepted, the second is put
  /// against it, and [builder] has not seen it yet. So, while [selector] and
  /// this function keep their meaning, where the screen ends up depends on the
  /// changes alone, and not on how they fall into frames. Only another [solo]
  /// starts it over: the first pick from a new controller goes to [builder]
  /// unasked.
  final bool Function(T previous, T current)? changed;

  /// Builds the subtree from the picked value.
  final ValueWidgetBuilder<T> builder;

  /// Handed back to [builder] untouched, to keep a subtree out of the
  /// rebuild.
  final Widget? child;

  /// Creates a widget that rebuilds on changes of [selector] over [solo].
  const SoloSelector({
    required this.solo,
    required this.selector,
    required this.builder,
    this.changed,
    this.child,
    super.key,
  });

  @override
  State<SoloSelector<S, T>> createState() => _SoloSelectorState<S, T>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Solo<S>>('solo', solo));
  }
}

final class _SoloSelectorState<S extends Object, T>
    extends State<SoloSelector<S, T>> {
  /// The pick last accepted: what `changed` is asked against, and what the next
  /// build hands to the builder.
  late T _value;

  /// Set while the controller is being subscribed to.
  var _subscribing = false;

  T _pick() => widget.selector(widget.solo.currentState);

  bool _changed(T previous, T current) {
    final changed = widget.changed;

    return changed == null ? previous != current : changed(previous, current);
  }

  /// Subscribes to the controller of the widget and takes its first pick.
  ///
  /// The pick comes after the subscription, so a controller that publishes
  /// while it is being subscribed to is read once, with what it published;
  /// the notification itself is let pass, there being no value yet to
  /// compare it with.
  void _follow() {
    try {
      _subscribing = true;
      try {
        widget.solo.addListener(_stateChanged);
      } finally {
        _subscribing = false;
      }
      _value = _pick();
    } on Object catch (_) {
      _unfollow();
      rethrow;
    }
  }

  /// Takes the listener off the controller of the widget.
  ///
  /// Besides `dispose`, the way out of `initState` and `didUpdateWidget`
  /// when a function of the widget throws there: the framework drops a
  /// `State` that failed in either without disposing of it, and a listener
  /// left on the controller would stay for as long as the controller does.
  void _unfollow() => widget.solo.removeListener(_stateChanged);

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(covariant SoloSelector<S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.solo, oldWidget.solo)) {
      oldWidget.solo.removeListener(_stateChanged);
      _follow();

      return;
    }
    // A new function may pick something else, or answer "did it change?"
    // differently, and a closure written in `build` is a new one every
    // time. Either is a reason to pick and ask again, and neither is a
    // reason to touch the subscription or the value the answer is given
    // from. The build that follows shows what came of it.
    if (!identical(widget.selector, oldWidget.selector) ||
        !identical(widget.changed, oldWidget.changed)) {
      try {
        final next = _pick();
        if (_changed(_value, next)) {
          _value = next;
        }
      } on Object catch (_) {
        _unfollow();
        rethrow;
      }
    }
  }

  /// Set first thing in `dispose`: a controller whose `removeListener`
  /// throws keeps the listener, and the framework has let go of the element
  /// by then all the same. `mounted` would not say so: the framework clears
  /// it only after a `dispose` that returned.
  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _unfollow();
    super.dispose();
  }

  void _stateChanged() {
    if (_subscribing || _disposed) {
      return;
    }
    final next = _pick();
    if (_changed(_value, next)) {
      setState(() {
        _value = next;
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, widget.child);
}
