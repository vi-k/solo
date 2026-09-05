part of 'solo_base.dart';

/// The core context plus the state: what a job body of `solo` sees.
///
/// The state is narrowed to the job's working type `W`, and [emit] is the
/// only way to change it. Reading it is a checkpoint of its own: [state],
/// [stateAs] and [check] throw the job's [Cancelled] once its rules
/// stopped holding, and [emit] throws a [StateError] for a job that has
/// already finished.
abstract interface class SoloContext<S extends Object, W extends S>
    implements JobContext {
  /// The current state. Throws [Cancelled] if the job is cancelled, if the
  /// state is not `W`, or if `keepWhile` returns `false`.
  W get state;

  /// [state] narrowed to `T`; cancels the job with `Cancelled(rules,
  /// 'is not T')` on mismatch.
  T stateAs<T extends S>();

  /// Sets the controller state. The new state is not checked against this
  /// job's rules; other running jobs are re-evaluated.
  ///
  /// A checkpoint on both sides. It throws the job's [Cancelled] before the
  /// write, as every member does, and again after it if the write cancelled
  /// this job on the way: hooks, observers and listeners run inside it and
  /// may set the state again, and a parent that goes down there takes its
  /// children with it.
  void emit(S next);
}

final class _SoloContext<S extends Object, W extends S, R>
    extends JobContextBase implements SoloContext<S, W> {
  final _SoloJob<S, W, R> _job;

  _SoloContext(this._job) : super(_job);

  SoloBase<S> get _solo => _job._solo;

  @override
  void check() => _checkedState();

  W _checkedState() {
    throwIfCancelled();
    final current = _solo._state;
    final rejection = _job._rejectKeep(current);
    if (rejection != null) {
      final cancelled = Cancelled.by(
        reason: SoloCancelReason.rules,
        started: true,
        description: rejection,
        stackTrace: _solo._lastChange,
      );
      cancelOwnJob(cancelled);
      throw pendingCancel ?? cancelled;
    }
    return current as W;
  }

  @override
  W get state => _checkedState();

  @override
  T stateAs<T extends S>() {
    final current = _checkedState();
    if (current is! T) {
      final cancelled = Cancelled.by(
        reason: SoloCancelReason.rules,
        started: true,
        description: 'is not $T',
        stackTrace: StackTrace.current,
      );
      cancelOwnJob(cancelled);
      throw pendingCancel ?? cancelled;
    }
    return current;
  }

  @override
  void emit(S next) {
    throwIfFinished('emit');
    throwIfCancelled();
    SoloBase._debug(() => '$_job emit: $next');
    _solo._setState(next, emitter: _job, stackTrace: StackTrace.current);
    // The write is a checkpoint on both sides: hooks, observers and
    // listeners run inside `_setState` and may cancel this job — through a
    // reentrant `externalSetState` or through a parent going down with it.
    // The body must not walk past that.
    throwIfCancelled();
  }

  @override
  Cancelled? beforeChildStart(JobBase<Object?> child) {
    // `run` has already asked `_own` whether the child is ours.
    final impl = child as _SoloJob<S, S, Object?>;
    final rejection = impl._rejectStart(_solo._state);
    return rejection == null
        ? null
        : Cancelled.by(
            reason: SoloCancelReason.rules,
            started: false,
            description: rejection,
            stackTrace: StackTrace.current,
          );
  }

  @override
  Job<T> run<T>(Job<T> child) {
    // Ownership is the parent's business: a bare job of the core has no
    // `adoptedBy` of ours to refuse it. The queue is asked by the child,
    // in `adoptedBy`.
    _solo._own(child);
    return super.run(child);
  }
}
