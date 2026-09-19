import 'package:flutter/foundation.dart';
import 'package:solo/solo.dart';

/// Makes a [Solo] a [ValueListenable] as well, so the controller drops
/// into `ValueListenableBuilder`, `ListenableBuilder`, `AnimatedBuilder`
/// and `Listenable.merge`:
///
/// ```dart
/// final class ProfileController extends Solo<Profile> with SoloListenable {
///   ProfileController() : super(Empty());
/// }
/// ```
///
/// The type argument comes from the superclass. In a type position it is
/// written out, `SoloListenable<Profile>`, and nothing makes you: the
/// analyzer lets a bare `SoloListenable` through as a
/// `SoloListenable<Object>`.
///
/// The engine's listeners are the whole delivery: a widget rebuilds from
/// [value], and an operation's result is awaited through its `Job`. A
/// controller that needs a broadcast `stream` as well mixes `SoloStream`
/// in too, `with SoloStream, SoloListenable`. The order makes no difference
/// here -- this mixin overrides nothing `SoloStream` does -- and
/// `SoloStream` goes first by its own rule; see "A controller with both
/// deliveries" in `doc/flutter.md` for what the combination costs.
///
/// A listener's failure is reported through [FlutterError] by
/// [onListenerError], and which report wins follows the chain, where a
/// class sits above the mixins it mixes in, as in the rule of
/// `SoloStream`. The class that mixes `SoloListenable` in, and every class
/// above it, overrides the mixin: a base that mixes it in and overrides
/// [onListenerError] keeps its own report. The classes below the mixin are
/// overridden by it: a base without Flutter, with the mixin on the leaf,
/// loses its override to this one, and the leaf cannot reach it through
/// `super` either, which lands here. A base that wants its own report keeps
/// it in a method of another name, and the leaf's override calls that. Mix
/// it in once, in the base or in the leaf: mixed in again on a leaf over a
/// base that has it already, it sits above the base's override and silences
/// it the same way.
///
/// Read-only on purpose: a `ValueNotifier` setter would break the
/// ownership guarantee. [value] and [currentState] are the same object.
mixin SoloListenable<S extends Object> on Solo<S>
    implements ValueListenable<S> {
  /// The current state; the same object as [currentState].
  @override
  S get value => currentState;

  /// Notifies through the engine's listeners, isolated through [FlutterError].
  ///
  /// The engine publishes from inside a state change and re-evaluates rules
  /// right after: a subscriber's failure is its own, and letting it out of
  /// here would cost a job the cancellation the new state owes it.
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
