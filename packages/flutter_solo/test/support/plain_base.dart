// Imports `solo` and nothing of Flutter: the base class a package without
// Flutter holds, with `SoloListenable` mixed in at the leaf.
import 'package:solo/solo.dart';

/// The base of "A base class without Flutter" in `doc/mixins.md`, as the
/// page writes it.
abstract class AppController<S extends Object> extends Solo<S> {
  /// Creates a controller in [initialState].
  AppController(super.initialState);
}

/// A base without Flutter that reports a listener's failure itself.
abstract class ReportingBase<S extends Object> extends Solo<S> {
  /// Every error this base's own report received.
  final reported = <Object>[];

  /// Creates a controller in [initialState].
  ReportingBase(super.initialState);

  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      reported.add(error);
}
