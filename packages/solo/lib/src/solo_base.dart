import 'dart:async';

import 'package:meta/meta.dart';

import 'observer.dart';

part 'outcome.dart';
part 'job.dart';
part 'job_context.dart';
part 'queue.dart';

/// The engine: state, queue, hooks. Subclasses add a delivery channel
/// through [publish]; see `Solo` for a stream.
abstract class SoloBase<S extends Object> {
  /// A global observer for all controllers; `null` by default.
  static SoloObserver? observer;

  /// Engine tracing for debugging the engine itself; `null` by default.
  static void Function(String message)? debug;

  // Not final: Task 4's engine assigns a new value when a job emits.
  // ignore: prefer_final_fields
  S _state;
  Completer<void>? _closing;

  /// Creates a controller in [initialState].
  SoloBase(S initialState) : _state = initialState {
    observer?.onCreate(this);
  }

  /// The current state. Reading is always safe; only jobs write.
  S get state => _state;

  // `close` is added in Task 12; until then this forward reference does not
  // resolve.
  // ignore: comment_references
  /// Whether [close] was called.
  bool get isClosed => _closing != null;

  /// Delivery point for subclasses; empty here. Called after `onChange` and
  /// before running jobs are re-evaluated.
  @protected
  @mustCallSuper
  void publish(S previous, S current) {}

  /// A job body is about to run.
  void onStart(Job<Object?> job) {}

  /// A job has an outcome, including jobs dropped before start.
  void onFinish(Job<Object?> job) {}

  /// A job body threw a non-[Cancelled] error, even after cancellation.
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}

  /// A job called [JobContext.log].
  void onLog(Job<Object?> job, String message) {}

  // `externalSetState` is added in Task 4; until then this forward
  // reference does not resolve.
  // ignore: comment_references
  /// The state changed, from a job or from [externalSetState].
  void onChange(S previous, S current) {}

  // Unused until Task 4 wires the engine to call it; kept here because
  // `isClosed`/`_closing` and the class shell already exist in Task 3.
  // ignore: unused_element
  static void _debug(String Function() message) {
    final debug = SoloBase.debug;
    if (debug != null) {
      debug(message());
    }
  }
}
