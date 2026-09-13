import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:solo/solo.dart';

import 'solo_selection.dart';

/// Rebuilds its subtree when one value picked out of a [SoloBase]
/// changes: a [SoloSelection] built directly over the controller.
///
/// ```dart
/// SoloSelectBuilder<Profile, bool>(
///   solo: controller,
///   selector: (state) => state.canSave,
///   builder: (context, canSave, _) => ElevatedButton(
///     onPressed: canSave ? controller.save : null,
///     child: const Text('Save'),
///   ),
/// )
/// ```
///
/// The widget creates a [SoloSelection] via [SoloSelection.of] and holds
/// it in its [State] across parent rebuilds so that the comparison
/// baseline used by [compare] is preserved. Recreating the selection on
/// every rebuild would lose that baseline and cause unnecessary work.
///
/// The selection is recreated in [State.didUpdateWidget] if and only if
/// at least one of [solo], [selector], or [compare] is not identical
/// to the previous widget's value. Comparing [selector] and [compare] by
/// identity is necessary because closures cannot otherwise be compared
/// for equality.
final class SoloSelectBuilder<S extends Object, T> extends StatefulWidget {
  /// The controller to pick out of.
  final SoloBase<S> solo;

  /// Picks the value this widget rebuilds for.
  ///
  /// Compared by identity when the parent rebuilds: an inline closure is
  /// a new object on every parent rebuild, causing the selection to be
  /// recreated. Hold the function in a field or a static method when the
  /// parent rebuilds frequently.
  final T Function(S state) selector;

  /// Answers whether the pick changed, `!=` when omitted; `true` means
  /// changed. Compared by identity when the parent rebuilds.
  final bool Function(T previous, T current)? compare;

  /// Builds the subtree from the picked value.
  final ValueWidgetBuilder<T> builder;

  /// Handed back to [builder] untouched, to keep an independent subtree
  /// out of rebuilds.
  final Widget? child;

  /// Creates a widget that rebuilds on changes of [selector] over [solo].
  const SoloSelectBuilder({
    required this.solo,
    required this.selector,
    required this.builder,
    this.compare,
    this.child,
    super.key,
  });

  @override
  State<SoloSelectBuilder<S, T>> createState() =>
      _SoloSelectBuilderState<S, T>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<SoloBase<S>>('solo', solo),
    );
  }
}

final class _SoloSelectBuilderState<S extends Object, T>
    extends State<SoloSelectBuilder<S, T>> {
  late SoloSelection<S, T> _selection = _select();

  SoloSelection<S, T> _select() => SoloSelection.of<S, T>(
        widget.solo,
        widget.selector,
        compare: widget.compare,
      );

  @override
  void didUpdateWidget(covariant SoloSelectBuilder<S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.solo, oldWidget.solo) ||
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
