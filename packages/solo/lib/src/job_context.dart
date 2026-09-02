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
  Future<T> guard<T>(FutureOr<T> Function() action) async {
    _checkedState();
    final result = action();
    if (result is! Future<T>) {
      return result;
    }
    return _race(result);
  }

  /// Completes with [future] or with the job's cancellation, whichever
  /// comes first. A result arriving after cancellation is ignored; an
  /// error arriving after cancellation goes to `onError`.
  Future<T> _race<T>(Future<T> future) {
    final completer = Completer<T>();
    void onCancel() {
      if (!completer.isCompleted) {
        final cancelled = _job._pendingCancel!;
        completer.completeError(
          cancelled,
          cancelled.stackTrace ?? StackTrace.current,
        );
      }
    }

    Future<void> forward() async {
      try {
        final value = await future;
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      } on Object catch (error, stackTrace) {
        if (completer.isCompleted) {
          _solo._notifyError(_job, error, stackTrace);
        } else {
          completer.completeError(error, stackTrace);
        }
      } finally {
        _job._onCancel.remove(onCancel);
      }
    }

    _job._onCancel.add(onCancel);
    // The action may have cancelled this job while it ran: `_markCancelled`
    // already emptied `_onCancel`, so the registration above would never be
    // called and the body would wait for the full action for nothing.
    if (_job._pendingCancel != null) {
      onCancel();
    }
    unawaited(forward());
    return completer.future;
  }

  @override
  Job<T> run<T>(Job<T> child) {
    _throwIfFinished('run a child');
    final impl = _solo._own(child);
    if (impl._status != _JobStatus.created) {
      throw StateError('$impl has already been added or run');
    }
    impl.level = _job.level + 1;
    _job._children.add(impl);
    final pending = _job._pendingCancel;
    if (pending != null) {
      _solo._cancel(
        impl,
        Cancelled._(
          reason: CancelReason.parent,
          started: false,
          stackTrace: pending.stackTrace,
        ),
      );
      throw pending;
    }
    final rejection = impl._rejectStart(_solo._state);
    if (rejection != null) {
      impl._finish(
        Cancelled._(
          reason: CancelReason.rules,
          started: false,
          description: rejection,
          stackTrace: StackTrace.current,
        ),
      );
      return child;
    }
    impl._start(impl.level);
    return child;
  }

  @override
  void log(Object? message) => _solo._notifyLog(_job, '$message');
}
