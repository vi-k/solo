part of 'solo.dart';

/// A job of a controller: [Job] plus the queue.
///
/// Returned by [Solo.job], [Solo.add] and [Solo.run]. The
/// queue belongs to the controller, so [isQueued] lives here and not on
/// the handle every job has.
abstract interface class SoloJob<T> implements Job<T> {
  /// Whether the job waits in the controller's queue.
  bool get isQueued;
}

final class _SoloJob<S extends Object, W extends S, T> extends JobBase<T>
    implements SoloJob<T> {
  final Solo<S> _solo;

  /// Let go of when the job is over, the way the core lets go of its own
  /// body and of the parent chain. A body runs once, and the handlers of
  /// a job that has an outcome have had their turn; kept after that, they
  /// hold everything they captured -- a controller, a connection, a
  /// buffer -- and `_parentJob` holds a whole tree of jobs that are over,
  /// for as long as anyone holds this handle. A handle is held exactly to
  /// be read later.
  Future<T> Function(SoloContext<S, W> ctx)? _body;
  S Function(S, Object, StackTrace)? _onError;
  S Function(S, Cancelled)? _onCancel;

  /// The rules outlive the job on purpose: a context that leaked out of a
  /// body reads the state through them long after the outcome, and the
  /// cancellation it builds from a rejection is the whole diagnosis it
  /// has to offer.
  final bool Function(W state)? _canStart;
  final bool Function(W state)? _keepWhile;
  _AccumulationGroup<Object?>? _accumulation;
  _SoloJob<S, S, Object?>? _parentJob;
  final bool _hasStateHandlers;
  bool _stateCorrectionRevoked = false;
  bool _bodyEntered = false;

  /// Whether the controller has taken this handle already.
  ///
  /// The status and the queue together nearly say it, and for a moment
  /// they do not: a job the pump has taken out and not yet started is
  /// `created` and not queued, and a hook running right then — the error
  /// hook of a rule that threw — would be handed a job that looks brand
  /// new.
  var _added = false;

  _SoloJob(
    this._solo,
    Future<T> Function(SoloContext<S, W> ctx) body, {
    required super.key,
    required bool Function(W state)? canStart,
    required bool Function(W state)? keepWhile,
    required super.cancellable,
    required super.describe,
    required super.observer,
    S Function(S, Object, StackTrace)? onError,
    S Function(S, Cancelled)? onCancel,
  })  : _body = body,
        _canStart = canStart,
        _keepWhile = keepWhile,
        _onError = onError,
        _onCancel = onCancel,
        _hasStateHandlers = onError != null || onCancel != null;

  @override
  bool get isQueued => _solo._queue._jobs.contains(this);

  /// The result type this job was created with.
  ///
  /// Read off the instance rather than matched against a type argument:
  /// two jobs under one key have to be the same operation, and `is`
  /// answers yes to a supertype — to every job at all when the type
  /// asked about is `void`.
  Type get _resultType => T;

  @override
  void adoptedBy(JobContextBase parent) {
    if (parent is! _SoloContext<S, S, Object?> ||
        !identical(parent._solo, _solo)) {
      throw ArgumentError.value(this, 'child', 'was not created by this Solo');
    }
    if (_solo._queue._jobs.contains(this)) {
      throw StateError('$this is queued and cannot be run as a child');
    }
    // Adoption is the controller taking the handle, the same as `add`: from
    // here nothing else may take it, and a rule of the child's own — asked
    // a moment later, while the child is still `created` and in no list —
    // must not be able to put it in the queue.
    _added = true;
    _parentJob = parent._job;
  }

  @override
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    if (cancelled.reason is RulesCancelReason) {
      _stateCorrectionRevoked = true;
    }
    if (_solo._queue._jobs.contains(this)) {
      if (!cancellable && rejectable) {
        Solo._debug(() => 'remove $this: not cancellable');
        return;
      }
      _solo._queue._jobs.remove(this);
      // Diagnostics may add another event synchronously. Detach first so
      // the group being cancelled can no longer receive it.
      Solo._debug(() => 'remove $this: $cancelled');
    }
    super.cancelWith(cancelled, rejectable: rejectable);
  }

  /// A rejection description if [state] fails the start rules, else null.
  String? _rejectStart(S state) {
    if (state is! W) {
      return 'is not $W';
    }
    final canStart = _canStart;
    if (canStart != null && !canStart(state)) {
      return 'canStart';
    }
    return _rejectKeep(state);
  }

  /// A rejection description if [state] fails the keep rules, else null.
  String? _rejectKeep(S state) {
    if (state is! W) {
      return 'is not $W';
    }
    final keepWhile = _keepWhile;
    if (keepWhile != null && !keepWhile(state)) {
      return 'keepWhile';
    }
    return null;
  }

  /// A snapshot of what this job is doing, for [Solo.pending].
  SoloPending _pending({required bool closing}) => SoloPending(
        job: this,
        phase: _phase,
        cancellation: pendingCancel,
        heldCancellation: heldCancel,
        children: children.length,
        inUncancellableSection: inUncancellableSection,
        refusesCancellation: !cancellable,
        closing: closing,
      );

  SoloPhase get _phase {
    if (isDisposing) {
      return SoloPhase.cleanup;
    }
    if (!bodyEnded) {
      return SoloPhase.body;
    }

    // Past the body with no child left, what remains is the job's own
    // ending: its cleanup stack if it has one, then the outcome.
    return children.isEmpty ? SoloPhase.cleanup : SoloPhase.children;
  }

  @override
  void started() {
    _solo._running.add(this);
    _accumulation?._started();
  }

  @override
  void finished() {
    try {
      _correctState();
    } finally {
      _accumulation?._release();
      _accumulation = null;
      _solo._onJobFinished(this);
      // After the controller has let go of this job, not before: the
      // state correction above calls these very handlers and reads the
      // parent through `_mayCorrectState`, and the line above takes this
      // job out of `_running` and out of `_current`.
      _body = null;
      _onError = null;
      _onCancel = null;
      _parentJob = null;
    }
  }

  bool get _mayCorrectState =>
      !_stateCorrectionRevoked && (_parentJob?._mayCorrectState ?? true);

  bool _checkCorrectionState(S state) {
    if (!_hasStateHandlers || !_mayCorrectState) return false;
    try {
      final rejection = _rejectKeep(state);
      if (rejection != null) _stateCorrectionRevoked = true;
      return false;
    } on Object catch (error, stackTrace) {
      // Without a valid rule decision, a finishing job must leave the
      // external state alone. Resource cleanup and its outcome still run.
      _stateCorrectionRevoked = true;
      notifyError(error, stackTrace);
      return true;
    }
  }

  void _correctState() {
    if (!_bodyEntered || !_mayCorrectState) return;
    final S next;
    switch (outcome) {
      case Failed(:final error, :final stackTrace):
        final handler = _onError;
        if (handler == null) return;
        next = handler(_solo._state, error, stackTrace);
      case final Cancelled cancelled:
        final handler = _onCancel;
        if (handler == null) return;
        next = handler(_solo._state, cancelled);
      default:
        return;
    }
    // A handler can synchronously notify an external state source. Such
    // a transition may revoke permission before the result is applied.
    if (!_mayCorrectState) return;
    _solo._setState(
      next,
      emitter: this,
      stackTrace: Solo.traceStateChanges ? StackTrace.current : null,
    );
  }

  @override
  JobContextBase createContext() => _SoloContext<S, W, T>(this);

  @override
  Future<T> execute(covariant _SoloContext<S, W, T> ctx) {
    _bodyEntered = true;
    // Non-null while the job runs: a finished job is never started again,
    // and only finishing clears this.
    return _body!(ctx);
  }

  // The engine reaches a job from the side, and `@protected` holds only
  // inside a subclass; these wrappers are how `Solo` and `_SoloQueue`
  // touch it.
  void _launch() => start();

  void _drop(Outcome<T> outcome) => finish(outcome);

  void _notifyObserver(Object error, StackTrace stackTrace) =>
      notifyObserver(error, stackTrace);

  void _notifyError(Object error, StackTrace stackTrace) =>
      notifyError(error, stackTrace);

  /// Marks the controller while an error with nowhere to go passes
  /// through the hooks.
  ///
  /// [Solo.onError] takes two kinds and cannot tell them apart by
  /// itself: the body's failure, which has an outcome carrying it to the
  /// zone already, and this one, which has nothing. Only this one may end
  /// in the zone. Saved and restored, not merely set: the hooks are
  /// synchronously reentrant through `externalSetState` → `_reevaluate` →
  /// `_notifyError`.
  @override
  void notifyError(Object error, StackTrace stackTrace) {
    final previous = _solo._homeless;
    _solo._homeless = this;
    try {
      super.notifyError(error, stackTrace);
    } finally {
      _solo._homeless = previous;
    }
  }

  void _reportToZone(Object error, StackTrace stackTrace) =>
      reportToZone(error, stackTrace);

  /// The route of a failure of this job that its group did not throw.
  ///
  /// Not through the observer: the body's failure was announced there
  /// already, where it was caught, and one error is announced once. What
  /// is left is the answer for an error nobody handled, and in a
  /// controller that is [Solo.onError] and the [Solo.errorHandler]
  /// behind it. Marked homeless the same way [notifyError] marks it, so
  /// the hook knows this error has nowhere else to go.
  @override
  void handleUnanswered(Object error, StackTrace stackTrace) {
    final previous = _solo._homeless;
    _solo._homeless = this;
    try {
      Solo._callHook(() => _solo.onError(this, error, stackTrace));
    } finally {
      _solo._homeless = previous;
    }
  }

  void _cancelWith(Cancelled cancelled, {bool rejectable = true}) =>
      cancelWith(cancelled, rejectable: rejectable);

  JobStatus get _jobStatus => status;

  bool get _bodyEnded => bodyEnded;

  Future<void> get _whenDone => whenDone;
}
