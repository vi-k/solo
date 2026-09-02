part of 'solo_base.dart';

/// What a job body sees: the state, narrowed to `W`, and the tools to change
/// it, check for cancellation and run children.
///
/// Every member except [log] and [job] throws the job's [Cancelled] once
/// the job is marked cancelled.
abstract interface class JobContext<S extends Object, W extends S> {
  /// The current state. Throws [Cancelled] if the job is cancelled, if the
  /// state is not `W`, or if `keepWhile` returns `false`.
  W get state;

  /// [state] narrowed to `T`; cancels the job with `Cancelled(rules,
  /// 'is not T')` on mismatch.
  T stateAs<T extends S>();

  /// Sets the controller state. The new state is not checked against this
  /// job's rules; other running jobs are re-evaluated.
  void emit(S next);

  /// Reads [state] and discards it. Call after a bare `await`.
  void check();

  /// Runs [action] unless the job is already cancelled, then waits for its
  /// result or for cancellation, whichever comes first.
  Future<T> guard<T>(FutureOr<T> Function() action);

  /// Starts [child] right now, bypassing the queue, as a child of this job.
  /// Returns the same handle; the parent finishes only after all children.
  Job<T> run<T>(Job<T> child);

  /// Sends `message.toString()` to `onLog` of the observer and the
  /// controller.
  void log(Object? message);

  /// The job this context belongs to.
  Job<Object?> get job;
}
