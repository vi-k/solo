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

final class _JobContext<S extends Object, W extends S, R>
    implements JobContext<S, W> {
  final _Job<S, W, R> _job;

  _JobContext(this._job);

  SoloBase<S> get _solo => _job._solo;

  @override
  Job<Object?> get job => _job;

  void _throwIfCancelled() {
    final cancelled = _job._pendingCancel;
    if (cancelled != null) {
      throw cancelled;
    }
  }

  void _throwIfFinished(String action) {
    if (_job.isFinished) {
      throw StateError('$_job has already finished, cannot $action');
    }
  }

  W _checkedState() {
    _throwIfCancelled();
    final current = _solo._state;
    final rejection = _job._rejectKeep(current);
    if (rejection != null) {
      final cancelled = Cancelled._(
        reason: CancelReason.rules,
        started: true,
        description: rejection,
        stackTrace: _solo._lastChange,
      );
      _solo._cancel(_job, cancelled);
      throw _job._pendingCancel ?? cancelled;
    }
    return current as W;
  }

  @override
  W get state => _checkedState();

  @override
  T stateAs<T extends S>() {
    final current = _checkedState();
    if (current is! T) {
      final cancelled = Cancelled._(
        reason: CancelReason.rules,
        started: true,
        description: 'is not $T',
        stackTrace: StackTrace.current,
      );
      _solo._cancel(_job, cancelled);
      throw _job._pendingCancel ?? cancelled;
    }
    return current;
  }

  @override
  void emit(S next) {
    _throwIfFinished('emit');
    _throwIfCancelled();
    SoloBase._debug(() => '$_job emit: $next');
    _solo._setState(next, emitter: _job, stackTrace: StackTrace.current);
  }

  @override
  void check() {
    _checkedState();
  }

  @override
  Future<T> guard<T>(FutureOr<T> Function() action) =>
      throw UnimplementedError('task 11');

  @override
  Job<T> run<T>(Job<T> child) => throw UnimplementedError('task 10');

  @override
  void log(Object? message) => _solo._notifyLog(_job, '$message');
}
