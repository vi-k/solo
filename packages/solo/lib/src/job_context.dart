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

  /// Reads [state] and discards it: gives up if the job was cancelled or
  /// its rules stopped holding.
  ///
  /// [join] is the same thing around a call. Reach for `check` where there
  /// is no call to wrap: a loop over work of your own, a `switch` on the
  /// state after one.
  void check();

  /// Runs [action] and waits for it, but no longer than this job lives.
  ///
  /// Throws [Cancelled] up front if the job is already cancelled or its
  /// rules no longer hold. If a cancellation arrives while [action] is in
  /// flight, the wait ends there with that [Cancelled] — and [action] runs
  /// on, its result discarded, an error of its own going to `onError`. It
  /// ends the waiting, not the work.
  ///
  /// For anything that must actually stop — a device, a download, a write —
  /// hand the cancellation to it through [onCancel] and wait for it to
  /// finish with [join], instead of walking away from it. For a step that
  /// must not be interrupted at all, see [uncancellable].
  ///
  /// [ifCancelled] picks up that discarded result: a value arriving after
  /// the wait is over goes there instead of on the floor, so a connection
  /// or a file opened by an abandoned action still gets closed. It runs
  /// late and alone — the job is over by then and nothing waits for it,
  /// [SoloBase.close] included. A late error goes to `onError` as always,
  /// and so does an error of [ifCancelled] itself.
  ///
  /// ```dart
  /// final db = await ctx.wait(
  ///   Database.open,
  ///   ifCancelled: (db) => db.close(),
  /// );
  /// ```
  Future<T> wait<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? ifCancelled,
  });

  /// Runs [action], waits for all of it, and gives up only afterwards.
  ///
  /// The counterpart of [wait] for a call that must not be left in flight:
  /// a device command, a write already on the wire. A cancellation
  /// arriving while [action] runs is accepted — the job is marked, and
  /// [SoloBase.close] waits, because the body is still inside this call —
  /// but the waiting is not cut short. When [action] comes back, this
  /// throws that [Cancelled]; if none arrived, it returns [action]'s
  /// value.
  ///
  /// ```dart
  /// await ctx.join(() => device.write(chunk));
  /// ```
  ///
  /// [wait] lets go of the action, `join` stays with it, so the next job
  /// never starts against a device still finishing this one, and a body
  /// written this way cannot walk past a cancellation by forgetting a
  /// line.
  ///
  /// The value is dropped when the job gives up: the throw happens inside
  /// this call, and the body is never reached. For an [action] that hands
  /// something over to own — a connection, a file, a subscription — pass
  /// [ifCancelled], and it gets that value instead. It is awaited before
  /// the [Cancelled] is thrown, so [SoloBase.close] waits for the disposal
  /// too and the next job starts with the resource already gone. Only a
  /// value is handed over: an [action] that threw has nothing to dispose
  /// of.
  ///
  /// ```dart
  /// final db = await ctx.join(
  ///   Database.open,
  ///   ifCancelled: (db) => db.close(),
  /// );
  /// ```
  ///
  /// An error from [action] is thrown as it is, cancelled or not, and the
  /// body can catch it like any other. An error from [ifCancelled] goes to
  /// `onError`, and the [Cancelled] is thrown all the same. Throws
  /// [Cancelled] up front if the job is already cancelled or its rules no
  /// longer hold, the same as [wait] and [uncancellable].
  Future<T> join<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? ifCancelled,
  });

  /// Runs [action] with cancellation refused, and waits for it.
  ///
  /// The counterpart of [wait], for a step that cannot be taken back: a
  /// payment on its way to the server, a write already on the wire. While
  /// [action] runs, [Job.cancel], the queue, a cancelled parent and
  /// [SoloBase.close] are all turned down, and `close` waits for the body
  /// instead of interrupting it.
  ///
  /// ```dart
  /// final receipt = await ctx.uncancellable(() => api.pay(order));
  /// ```
  ///
  /// A refusal is final, not deferred: nothing is replayed once [action]
  /// returns. Sections nest — the answer in force before this one is
  /// restored, not assumed — and the answer is restored even if [action]
  /// throws.
  ///
  /// The job's own rules are not covered: a state outside `W`, or a
  /// `keepWhile` that turned false, cancels the job whatever this does, and
  /// the body learns about it at its next read as always.
  ///
  /// Throws [Cancelled] if the job is already cancelled, the same as
  /// [wait]: a step that cannot be taken back must not begin for a job
  /// that is already over.
  Future<T> uncancellable<T>(FutureOr<T> Function() action);

  /// Registers [callback] to run the moment the job is marked cancelled,
  /// before the body itself learns about it. Returns a function that
  /// unregisters it.
  ///
  /// This is how a cancellation reaches something that can really stop:
  /// a device's own cancel token, an HTTP client's abort, a subscription.
  ///
  /// ```dart
  /// final token = CancelToken();
  /// ctx.onCancel(token.cancel);
  /// // The device stops by itself, and `join` waits for it to finish
  /// // before the job ends and the next one starts.
  /// await ctx.join(() => device.seek(position, cancelToken: token));
  /// ```
  ///
  /// Throws [Cancelled] if the job is already cancelled: there is nothing
  /// to register for, and nothing should be started either. An error thrown
  /// by [callback] goes to `onError` and stops there; the cancellation
  /// itself is not affected and the other callbacks still run.
  void Function() onCancel(void Function() callback);

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
  Future<T> join<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? ifCancelled,
  }) async {
    _checkedState();
    final result = await action();
    try {
      _checkedState();
    } on Cancelled {
      if (ifCancelled != null) {
        await _dispose(ifCancelled, result);
      }
      rethrow;
    }
    return result;
  }

  /// Hands [value] to the body's own disposer. Its error belongs to
  /// `onError`: the job is already giving up, and a failed disposal must
  /// not stand in for the cancellation the body is waiting for.
  Future<void> _dispose<T>(
    FutureOr<void> Function(T value) ifCancelled,
    T value,
  ) async {
    try {
      await ifCancelled(value);
    } on Object catch (error, stackTrace) {
      _solo._notifyError(_job, error, stackTrace);
    }
  }

  @override
  Future<T> uncancellable<T>(FutureOr<T> Function() action) async {
    _checkedState();
    final previous = _job.cancellable;
    _job.cancellable = false;
    try {
      return await action();
    } finally {
      _job.cancellable = previous;
    }
  }

  @override
  void Function() onCancel(void Function() callback) {
    _throwIfFinished('register onCancel');
    _throwIfCancelled();
    void guarded() {
      // A callback of the caller's, run from inside the engine's own
      // cancellation: its error belongs to `onError`, not to whoever
      // happened to trigger the cancel.
      try {
        callback();
      } on Object catch (error, stackTrace) {
        _solo._notifyError(_job, error, stackTrace);
      }
    }

    _job._onCancel.add(guarded);
    return () => _job._onCancel.remove(guarded);
  }

  @override
  Future<T> wait<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? ifCancelled,
  }) async {
    _checkedState();
    final result = action();
    if (result is! Future<T>) {
      return result;
    }
    return _race(result, ifCancelled);
  }

  /// Completes with [future] or with the job's cancellation, whichever
  /// comes first. A result arriving after cancellation goes to
  /// [ifCancelled], or nowhere if there is none; an error arriving after
  /// cancellation goes to `onError`.
  Future<T> _race<T>(
    Future<T> future,
    FutureOr<void> Function(T value)? ifCancelled,
  ) {
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
        if (completer.isCompleted) {
          if (ifCancelled != null) {
            await _dispose(ifCancelled, value);
          }
        } else {
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
