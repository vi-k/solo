import 'package:flutter/foundation.dart';
import 'package:solo/solo.dart';

/// Makes a [Solo] a [ValueListenable] as well, so the controller drops
/// into `ValueListenableBuilder`, `ListenableBuilder`, `AnimatedBuilder`
/// and `Listenable.merge`.
///
/// [value] is [currentState], the same object, and has no setter on purpose: a
/// `ValueNotifier` setter would break the ownership guarantee. The type
/// argument comes from the superclass; in a type position write it out,
/// `SoloListenable<Profile>`, because the analyzer lets a bare `SoloListenable`
/// through as a `SoloListenable<Object>`. A controller that needs a broadcast
/// `stream` as well mixes `SoloStream` in first:
/// `with SoloStream, SoloListenable`.
///
/// ```dart
/// final class ProfileController extends Solo<Profile> with SoloListenable {
///   ProfileController() : super(Empty());
/// }
/// ```
///
/// A listener's failure is reported through [FlutterError] by
/// [onListenerError], and the chain decides whose report wins. The class that
/// mixes `SoloListenable` in, and every class above it, overrides the mixin;
/// the mixin overrides the classes below it, so a base without Flutter, with
/// the mixin on the leaf, loses its override to this one, and `super` from the
/// leaf lands here. Mix it in once: mixed in again on a leaf over a base that
/// has it, it silences the base's override the same way.
///
/// See [The controller as a `ValueListenable`](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.md#the-controller-as-a-valuelistenable) in the package README,
/// and [A controller with both deliveries](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/doc/mixins.md#a-controller-with-both-deliveries)
/// and [A base class without Flutter](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/doc/mixins.md#a-base-class-without-flutter) on the mixins page.
mixin SoloListenable<S extends Object> on Solo<S>
    implements ValueListenable<S> {
  /// The current state; the same object as [currentState].
  @override
  S get value => currentState;

  /// Reports a listener's failure through [FlutterError], the way a
  /// `ChangeNotifier` reports one, instead of to the zone.
  ///
  /// A listener's failure is its own and never reaches whoever wrote the
  /// state: the engine hands it here and goes on to the next listener. An
  /// override that throws sends both errors to the zone, the listener's
  /// first.
  ///
  /// `@protected` is repeated because Dart does not inherit it. Left off,
  /// this override makes a hook of the engine a public member of every
  /// controller that mixes this in, and of `dart doc` along with it.
  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'flutter_solo',
        context: ErrorDescription(
          'notifying a listener of ${describeIdentity(this)}',
        ),
      ),
    );
  }
}
