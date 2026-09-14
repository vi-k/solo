import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:solo/solo.dart';

import 'solo_select_builder.dart';

/// Rebuilds its subtree whenever a [SoloBase] notifies of a state change.
///
/// An alternative to [ValueListenableBuilder] for any controller based on
/// [SoloBase], including those that do not implement [ValueListenable].
///
/// ```dart
/// SoloBuilder<Profile>(
///   solo: controller,
///   builder: (context, state, child) => Text(state.name),
/// )
/// ```
///
/// The widget subscribes to [solo] in [State.initState], removes the
/// subscription in [State.dispose], and rebuilds from the controller's
/// current state on every notification.
///
/// If [SoloBase.close] has finished, the controller drops all listeners and
/// stops notifying; connecting an already closed controller displays its
/// current state and receives no further updates.
///
/// Selective rebuilds for a sub-state belong in [SoloSelectBuilder],
/// not here: this widget rebuilds on every state transition of [solo].
final class SoloBuilder<S extends Object> extends StatefulWidget {
  /// The controller whose state transitions trigger rebuilds.
  final SoloBase<S> solo;

  /// Builds the subtree for the controller's current state.
  final ValueWidgetBuilder<S> builder;

  /// Handed back to [builder] untouched, to keep an independent subtree
  /// out of rebuilds.
  final Widget? child;

  /// Creates a widget that rebuilds on state changes of [solo].
  const SoloBuilder({
    required this.solo,
    required this.builder,
    this.child,
    super.key,
  });

  @override
  State<SoloBuilder<S>> createState() => _SoloBuilderState<S>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<SoloBase<S>>('solo', solo),
    );
  }
}

final class _SoloBuilderState<S extends Object> extends State<SoloBuilder<S>> {
  @override
  void initState() {
    super.initState();
    widget.solo.addListener(_valueChanged);
  }

  @override
  void didUpdateWidget(covariant SoloBuilder<S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.solo, oldWidget.solo)) {
      oldWidget.solo.removeListener(_valueChanged);
      widget.solo.addListener(_valueChanged);
    }
  }

  @override
  void dispose() {
    widget.solo.removeListener(_valueChanged);
    super.dispose();
  }

  void _valueChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.solo.currentState, widget.child);
}
