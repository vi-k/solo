part of 'solo.dart';

/// A job of a controller: [Job] plus the queue.
///
/// Returned by [Solo.job], [Solo.enqueueJob] and [Solo.enqueue]. The queue
/// belongs to the controller, so [isQueued] lives here and not on the handle
/// every job has. It is a [ChildJob], so a body runs one as its child with
/// `ctx.run`, and it has no `start` of its own: the queue or the parent starts
/// it.
abstract interface class SoloJob<T> implements ChildJob<T> {
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
  S Function(S, Object, StackTrace)? _ifFailed;
  S Function(S, Cancelled)? _ifCancelled;

  /// Names the errors the job expects; see `Solo.job`.
  ///
  /// Not let go of in [finished], unlike the handlers above: a [Failed] nobody
  /// observed goes to its answer a microtask after the job is over, and the
  /// answer asks this predicate.
  bool Function(Object error)? _isExpectedError;

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
  var _taken = false;

  _SoloJob(
    this._solo,
    Future<T> Function(SoloContext<S, W> ctx) body, {
    required super.key,
    required bool Function(W state)? canStart,
    required bool Function(W state)? keepWhile,
    required super.cancellable,
    required super.timeout,
    required super.describe,
    required super.observer,
    S Function(S, Object, StackTrace)? ifFailed,
    S Function(S, Cancelled)? ifCancelled,
    bool Function(Object error)? isExpectedError,
  }) : _body = body,
       _canStart = canStart,
       _keepWhile = keepWhile,
       _ifFailed = ifFailed,
       _ifCancelled = ifCancelled,
       _isExpectedError = isExpectedError,
       _hasStateHandlers = ifFailed != null || ifCancelled != null;

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
      throw ArgumentError.value(
        '$this',
        'child',
        'runs as a child only in a body of the Solo that made it',
      );
    }
    if (_solo._queue._jobs.contains(this)) {
      throw StateError('$this is queued and cannot be run as a child');
    }
    // Taken already, and still `created`: a rule of the child's own runs it
    // again while the first adoption is asking that rule. The core lets a
    // `created` job in, and a second adoption would start it with nobody
    // waiting for it.
    if (_taken) {
      throw StateError('$this has already been enqueued or run');
    }
    // Adoption is the controller taking the handle, the same as `enqueueJob`:
    // from here nothing else may take it, and a rule of the child's own — asked
    // a moment later, while the child is still `created` and in no list — must
    // not be able to put it in the queue.
    _taken = true;
    _parentJob = parent._job;
    // A predicate of its own is stronger; a child made by `ctx.child` or
    // `each` has none and takes the one of the job whose body starts it.
    _isExpectedError ??= parent._job._isExpectedError;
  }

  @override
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    final queued = _solo._queue._jobs.contains(this);
    // A job the pump holds between the queue and the start is queued work
    // too: it has not run a line, and a `cancellable: false` one turns
    // down a rejectable cancellation the same way. Left to the core it
    // would not: a job that has not started is `created`, and `created` is
    // finished without asking.
    if (queued || identical(this, _solo._inTransition)) {
      if (!cancellable && rejectable) {
        Solo._debug(() => 'remove $this: not cancellable');
        return;
      }
      if (queued) {
        _solo._queue._jobs.remove(this);
        // Diagnostics may add another event synchronously. Detach first so
        // the group being cancelled can no longer receive it.
        Solo._debug(() => 'remove $this: $cancelled');
      }
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
    // The keep rules against the state as it is now: `canStart` is the
    // caller's code, and it may write the state while it answers. It is
    // not asked again — it said yes, and whatever it did is done.
    return _rejectKeep(_solo._state);
  }

  /// A rejection description if [state] fails the keep rules, else null.
  ///
  /// `keepWhile` cannot write the state while it answers — the write
  /// throws [StateError] — so the answer is about the state the controller
  /// has now.
  String? _rejectKeep(S state) {
    if (state is! W) {
      return 'is not $W';
    }
    final keepWhile = _keepWhile;
    if (keepWhile == null) {
      return null;
    }
    final bool keep;
    _solo._askingKeepWhile++;
    try {
      keep = keepWhile(state);
    } finally {
      _solo._askingKeepWhile--;
    }
    return keep ? null : 'keepWhile';
  }

  /// A snapshot of what this job is doing, for [Solo.pending].
  SoloPendingJob _pending({
    required bool closing,
    required bool draining,
    required List<Job<Object?>> queued,
  }) => SoloPendingJob(
    job: this,
    phase: _phase,
    cancellation: pendingCancel,
    heldCancellation: heldCancel,
    children: children.length,
    inUncancellableSection: inUncancellableSection,
    cancellable: cancellable,
    closing: closing,
    draining: draining,
    queued: queued,
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
      _ifFailed = null;
      _ifCancelled = null;
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
    final state = _solo._state;
    final S next;
    switch (outcome) {
      case Failed(:final error, :final stackTrace):
        final handler = _ifFailed;
        if (handler == null) return;
        next = handler(state, error, stackTrace);
      case final Cancelled cancelled:
        final handler = _ifCancelled;
        if (handler == null) return;
        next = handler(state, cancelled);
      default:
        return;
    }
    // A handler can synchronously notify an external state source. Such
    // a transition may revoke permission before the result is applied.
    if (!_mayCorrectState) return;
    // The very state it was given is the answer "as it was", not a write:
    // nothing is published, and a write made from inside the handler, if
    // the rules took it, stays.
    if (identical(next, state)) return;
    _solo._setState(next, emitter: this);
  }

  /// Verdicts of [_judge] that [_answersFor] has not taken yet, for the errors
  /// that can be held weakly.
  ///
  /// Held weakly, as the core holds the error it announced last: a verdict for
  /// an error that never reaches [_answersFor] -- the outcome was observed, or
  /// `Job.isCancellationError` named the error -- must not keep it alive.
  Expando<bool>? _verdicts;

  /// The verdicts for the errors [_isPlain] says cannot be held weakly:
  /// strings, numbers, booleans and records. Found by identity.
  List<(Object, bool)>? _plainVerdicts;

  /// A copy of `JobBase._isPlain`, which is private to the core: the same
  /// question has to get the same answer here.
  static bool _isPlain(Object error) {
    if (error is String || error is num || error is bool || error is Record) {
      return true;
    }
    try {
      // Never written, so a lookup that goes through answers false.
      return _weakProbe[error] ?? false;
    } on Object {
      return true;
    }
  }

  static final _weakProbe = Expando<bool>();

  void _noteVerdict(Object error, bool expected) {
    if (_isPlain(error)) {
      (_plainVerdicts ??= []).add((error, expected));
    } else {
      (_verdicts ??= Expando<bool>())[error] = expected;
    }
  }

  /// The verdict noted for [error], forgotten by the taking.
  bool? _takeVerdict(Object error) {
    if (_isPlain(error)) {
      final plain = _plainVerdicts;
      if (plain == null) return null;
      for (var i = 0; i < plain.length; i++) {
        if (identical(plain[i].$1, error)) {
          return plain.removeAt(i).$2;
        }
      }
      return null;
    }
    final verdicts = _verdicts;
    if (verdicts == null) return null;
    final verdict = verdicts[error];
    verdicts[error] = null;
    return verdict;
  }

  /// Whether the predicate names [error]. A predicate that throws names
  /// nothing: its error goes to the zone the job was made in, and [error]
  /// goes on by its own route.
  bool _isExpected(Object error) {
    final isExpectedError = _isExpectedError;
    if (isExpectedError == null) return false;
    try {
      return isExpectedError(error);
    } on Object catch (thrown, stackTrace) {
      _reportToZone(thrown, stackTrace);
      return false;
    }
  }

  /// The verdict for `onError`: asks, notes it for [_answersFor] and says
  /// whether [error] is expected.
  bool _judge(Object error) {
    if (_isExpectedError == null) return false;
    final expected = _isExpected(error);
    _noteVerdict(error, expected);
    return expected;
  }

  /// The verdict for `onUnanswered`: the one [_judge] noted, taken, or, for
  /// an error that did not pass `onError`, a question that is not noted.
  bool _answersFor(Object error) {
    if (_isExpectedError == null) return false;
    return _takeVerdict(error) ?? _isExpected(error);
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

  /// Starts the job in the zone the core keeps for it: the zone it was made
  /// in, or the zone the work was started from for a job made inside the
  /// work of `JobContext.unattended`.
  ///
  /// The pump runs in the zone of whatever woke the queue: the call that
  /// queued a job just before this one, the end of the job before, a
  /// window's timer. A body started from there took that zone's timers,
  /// values and error handler for its own, and a future of its own zone
  /// that failed while the body ran under another `runZonedGuarded` never
  /// reached it: the body waited for good. The whole start moves, with
  /// the deadline and the hooks the core calls in it; the rules the pump
  /// asks before the start are still asked from the pump.
  ///
  /// Not the zone current at creation: inside the work that is the fork,
  /// which carries the job that started the work, and a job that kept it
  /// would hold that job for as long as it waited and ran.
  void _launch() => creationZone.run(start);

  void _drop(Outcome<T> outcome) => finish(outcome);

  void _requireShared(String reason) => requireShared(reason);

  void _notifyError(Object error, StackTrace stackTrace) =>
      notifyError(error, stackTrace);

  void _reportToZone(Object error, StackTrace stackTrace) =>
      reportToZone(error, stackTrace);

  void _cancelWith(Cancelled cancelled, {bool rejectable = true}) =>
      cancelWith(cancelled, rejectable: rejectable);

  /// What the cancellation of a [Policy.restart] came to, read right after
  /// it was asked, for the line of [Solo.debug].
  String get _restartAnswer {
    if (isCancelled) return 'cancel $this';
    if (heldCancel != null) {
      return '$this holds the cancellation back until its uncancellable '
          'section closes';
    }
    return '$this turns the cancellation down: it is not cancellable';
  }

  JobStatus get _jobStatus => status;

  bool get _bodyEnded => bodyEnded;

  Future<void> get _untilFinished => untilFinished;
}
