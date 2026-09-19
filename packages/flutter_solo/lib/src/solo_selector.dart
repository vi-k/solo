import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:solo/solo.dart';

import 'solo_builder.dart';
import 'solo_selection.dart';

/// Rebuilds its subtree when one value picked out of a [Solo]'s state
/// changes: a [SoloSelection] for a widget that has nowhere to keep one.
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
/// It takes any [Solo] — one with `SoloListenable`, one with `SoloStream`
/// or a plain one — and is to [SoloBuilder] what a pick is to the whole
/// state. A [ValueListenable] that is not a controller is picked from with
/// a [SoloSelection] of its own and a `ValueListenableBuilder`.
///
/// A selection earns its keep by being kept: one built in `build` and
/// dropped at the end of it subscribes and unsubscribes every frame, and
/// the announced value it holds notifications back with goes with it.
/// That is what a `State` field was for, and it is what this widget
/// carries instead — so the picking widget can be a `StatelessWidget`,
/// and a screen that picks three values out of one controller needs no
/// `State` at all. Nothing has to be disposed of: the widget going away
/// takes the last listener of the selection with it, and the selection
/// then lets go of [solo].
final class SoloSelector<S extends Object, T> extends StatefulWidget {
  /// The controller to pick out of.
  ///
  /// Compared by identity when the parent rebuilds: handed a new
  /// controller whose `==` says it is the old one, the widget moves to the
  /// new one all the same.
  final Solo<S> solo;

  /// Picks the value this widget rebuilds for.
  ///
  /// Compared by identity when the parent rebuilds, and it has to be: a
  /// new function may pick something else, and there is no way to ask one
  /// closure whether it does what another did. The inline
  /// `(state) => state.canSave` above is therefore a different object on
  /// every build of the parent, so each of those rebuilds drops the
  /// selection and makes another: one `removeListener`, one `addListener`
  /// and one pick. That is small, and it is not nothing — hold the
  /// function in a field or a `static` where the parent rebuilds often.
  final T Function(S state) selector;

  /// Answers whether the pick changed, `!=` when it is omitted. Compared
  /// by identity, the same as [selector].
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
  late SoloSelection<S, T> _selection = _select();
  late T _value;

  SoloSelection<S, T> _select() => SoloSelection.from<S, T>(
        widget.solo,
        widget.selector,
        changed: widget.changed,
      );

  @override
  void initState() {
    super.initState();
    _selection.addListener(_valueChanged);
    _value = _selection.value;
  }

  @override
  void didUpdateWidget(covariant SoloSelector<S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The selector and the answer about a change are as much a part of
    // what this widget watches as the controller is: a parent handing over
    // a new one is asking for something else to be picked, or for a
    // different answer to "did it change?". The widget manages the
    // subscription itself, moving its listener from the old selection to
    // the new one.
    if (!identical(widget.solo, oldWidget.solo) ||
        !identical(widget.selector, oldWidget.selector) ||
        !identical(widget.changed, oldWidget.changed)) {
      _selection.removeListener(_valueChanged);
      _selection = _select();
      _selection.addListener(_valueChanged);
      _value = _selection.value;
    }
  }

  @override
  void dispose() {
    _selection.removeListener(_valueChanged);
    super.dispose();
  }

  void _valueChanged() {
    setState(() {
      _value = _selection.value;
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, widget.child);
}
