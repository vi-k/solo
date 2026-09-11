part of 'solo_base.dart';

/// A job of a controller: [Job] plus the queue.
///
/// Returned by [SoloBase.job], [SoloBase.add] and [SoloBase.run]. The
/// queue belongs to the controller, so [isQueued] lives here and not on
/// the handle every job has.
abstract interface class SoloJob<T> implements Job<T> {
  /// Whether the job waits in the controller's queue.
  bool get isQueued;
}

final class _SoloJob<S extends Object, W extends S, T> extends JobBase<T>
    implements SoloJob<T> {
  final SoloBase<S> _solo;
  final Future<T> Function(SoloContext<S, W> ctx) _body;
  final bool Function(W state)? _canStart;
  final bool Function(W state)? _keepWhile;
  final S Function(S, Object, StackTrace)? _onError;
  final S Function(S, Cancelled)? _onCancel;
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
    this._body, {
    required super.key,
    required bool Function(W state)? canStart,
    required bool Function(W state)? keepWhile,
    required super.cancellable,
    required super.describe,
    required super.observer,
    S Function(S, Object, StackTrace)? onError,
    S Function(S, Cancelled)? onCancel,
  })  : _canStart = canStart,
        _keepWhile = keepWhile,
        _onError = onError,
        _onCancel = onCancel,
        _hasStateHandlers = onError != null || onCancel != null;

  @override
  bool get isQueued => _solo._queue._jobs.contains(this);

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
        SoloBase._debug(() => 'remove $this: not cancellable');
        return;
      }
      _solo._queue._jobs.remove(this);
      // Diagnostics may add another event synchronously. Detach first so
      // the group being cancelled can no longer receive it.
      SoloBase._debug(() => 'remove $this: $cancelled');
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

  /// A snapshot of what this job is doing, for [SoloBase.pending].
  SoloPending _pending({required bool closing}) => SoloPending(
        job: this,
        phase: _phase,
        cancellation: pendingCancel,
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

    return children.isEmpty ? SoloPhase.unknown : SoloPhase.children;
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
    _solo._setState(next, emitter: this, stackTrace: StackTrace.current);
  }

  @override
  JobContextBase createContext() => _SoloContext<S, W, T>(this);

  @override
  Future<T> execute(covariant _SoloContext<S, W, T> ctx) {
    _bodyEntered = true;
    return _body(ctx);
  }

  // The engine reaches a job from the side, and `@protected` holds only
  // inside a subclass; these wrappers are how `SoloBase` and `_SoloQueue`
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
  /// [SoloBase.onError] takes two kinds and cannot tell them apart by
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

  void _cancelWith(Cancelled cancelled, {bool rejectable = true}) =>
      cancelWith(cancelled, rejectable: rejectable);

  JobStatus get _jobStatus => status;

  bool get _bodyEnded => bodyEnded;

  Future<void> get _whenDone => whenDone;
}
