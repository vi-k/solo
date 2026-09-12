import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'solo_selection.dart';

/// Rebuilds its subtree when one value picked out of a [ValueListenable]
/// changes: a [SoloSelection] for a widget that has nowhere to keep one.
///
/// ```dart
/// SoloSelector<Profile, bool>(
///   listenable: controller,
///   selector: (state) => state.canSave,
///   builder: (context, canSave, _) => ElevatedButton(
///     onPressed: canSave ? controller.save : null,
///     child: const Text('Save'),
///   ),
/// )
/// ```
///
/// A selection earns its keep by being kept: one built in `build` and
/// dropped at the end of it subscribes and unsubscribes every frame, and
/// the announced value it holds notifications back with goes with it.
/// That is what a `State` field was for, and it is what this widget
/// carries instead — so the picking widget can be a `StatelessWidget`,
/// and a screen that picks three values out of one controller needs no
/// `State` at all. Nothing has to be disposed of: the widget going away
/// takes the last listener of the selection with it, and the selection
/// then lets go of [listenable].
final class SoloSelector<S, T> extends StatefulWidget {
  /// The listenable to pick out of.
  final ValueListenable<S> listenable;

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
  final T Function(S value) selector;

  /// Answers whether the pick changed, `!=` when it is omitted; `true`
  /// means changed. Compared by identity, the same as [selector].
  final bool Function(T previous, T current)? compare;

  /// Builds the subtree from the picked value.
  final ValueWidgetBuilder<T> builder;

  /// Handed back to [builder] untouched, to keep a subtree out of the
  /// rebuild.
  final Widget? child;

  /// Creates a widget that rebuilds on changes of [selector] over
  /// [listenable].
  const SoloSelector({
    required this.listenable,
    required this.selector,
    required this.builder,
    this.compare,
    this.child,
    super.key,
  });

  @override
  State<SoloSelector<S, T>> createState() => _SoloSelectorState<S, T>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<ValueListenable<S>>('listenable', listenable),
    );
  }
}

final class _SoloSelectorState<S, T> extends State<SoloSelector<S, T>> {
  late SoloSelection<S, T> _selection = _select();

  SoloSelection<S, T> _select() => SoloSelection<S, T>(
        widget.listenable,
        widget.selector,
        compare: widget.compare,
      );

  @override
  void didUpdateWidget(covariant SoloSelector<S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The selector and the comparison are as much a part of what this
    // widget watches as the listenable is: a parent handing over a new
    // one is asking for something else to be picked, or for a different
    // answer to "did it change?". The old selection is not cancelled
    // here and needs no cancelling — the builder below takes its listener
    // away as it moves to the new one, and that was its only listener.
    if (!identical(widget.listenable, oldWidget.listenable) ||
        !identical(widget.selector, oldWidget.selector) ||
        !identical(widget.compare, oldWidget.compare)) {
      _selection = _select();
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<T>(
        valueListenable: _selection,
        builder: widget.builder,
        child: widget.child,
      );
}
