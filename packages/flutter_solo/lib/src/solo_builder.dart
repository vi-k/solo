import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:solo/solo.dart';

import 'solo_selector.dart';

/// Rebuilds its subtree whenever a [Solo] notifies of a state change.
///
/// An alternative to [ValueListenableBuilder] for any controller based on
/// [Solo], including those that do not implement [ValueListenable].
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
/// Once the engine has finished closing — [Solo.isFinished], which is
/// not the same moment as the future of [Solo.close] completing — the
/// listeners are gone and nothing notifies this widget again; connecting an
/// already closed controller displays its final state.
///
/// Selective rebuilds for a sub-state belong in [SoloSelector], not
/// here: this widget rebuilds on every state transition of [solo].
final class SoloBuilder<S extends Object> extends StatefulWidget {
  /// The controller whose state transitions trigger rebuilds.
  final Solo<S> solo;

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
    properties.add(DiagnosticsProperty<Solo<S>>('solo', solo));
  }
}

final class _SoloBuilderState<S extends Object> extends State<SoloBuilder<S>> {
  /// Puts the listener on the controller of the widget.
  ///
  /// A controller of somebody's own may register the listener and then
  /// throw. The framework drops a `State` that failed in `initState` or in
  /// `didUpdateWidget` without disposing of it, and a listener left on the
  /// controller would stay for as long as the controller does.
  void _follow() {
    try {
      widget.solo.addListener(_valueChanged);
    } on Object catch (_) {
      widget.solo.removeListener(_valueChanged);
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(covariant SoloBuilder<S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.solo, oldWidget.solo)) {
      oldWidget.solo.removeListener(_valueChanged);
      _follow();
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
    widget.solo.removeListener(_valueChanged);
    super.dispose();
  }

  void _valueChanged() {
    if (_disposed) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.solo.currentState, widget.child);
}
