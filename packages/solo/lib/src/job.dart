part of 'solo_base.dart';

/// A handle to a job created by [SoloBase.job] or [SoloBase.run].
///
/// Not a [Future]: calling a controller method without `await` is legal.
/// Await [done], [value] or [whenCancelled] where you need to.
///
/// A job that ends with [Failed] and is never observed hands its error to
/// the zone that created the job, the way Dart reports an unhandled
/// `Future` error. Touching [done], [value] or [ignore] counts as
/// observing it; see [ignore].
abstract interface class Job<T> {
  /// The key given at creation; compared with `==` by policies and queue
  /// searches.
  Object? get key;

  /// The description given at creation, or an empty string.
  String describe();

  /// Nesting depth: 0 for a root job, `parent.level + 1` for a child.
  int get level;

  /// Whether this job was started by [JobContext.run].
  bool get isChild;

  /// Whether the body is running or its children are still finishing.
  bool get isRunning;

  /// Whether [outcome] is set.
  bool get isFinished;

  /// Whether the job is marked cancelled, even if the body still runs.
  bool get isCancelled;

  /// The outcome, or `null` until the job is finished.
  Outcome<T>? get outcome;

  /// Completes with the outcome; never throws.
  ///
  /// Reading it marks the job observed, so a [Failed] outcome is not
  /// reported to the zone.
  Future<Outcome<T>> get done;

  /// Completes with the returned value, or throws [Cancelled] with the
  /// cancellation stack trace, or throws the body's error.
  ///
  /// Reading it marks the job observed, so a [Failed] outcome is not
  /// reported to the zone. Handle the error the future carries, or it
  /// becomes an unhandled `Future` error instead.
  Future<T> get value;

  /// Completes on every [Cancelled] outcome, and never on any other one.
  ///
  /// For a running job, the moment it is marked cancelled, before the body
  /// finishes; for a job cancelled before it started, when it is dropped;
  /// for a body that cancelled itself with `throw Cancelled(...)`, when the
  /// job finishes, since nothing marked it beforehand.
  Future<void> get whenCancelled;

  /// Cancels the job and waits for it to actually finish.
  ///
  /// A job created with `cancellable: false`, or one inside
  /// [JobContext.uncancellable], is not cancelled; the returned future
  /// still waits for it to finish.
  Future<void> cancel();

  /// Tells the engine that nobody is interested in this job's failure.
  ///
  /// The counterpart of `Future.ignore`. A job that ends with [Failed]
  /// without ever being observed hands its error to the zone that created
  /// it; call this on a fire-and-forget job whose failure is already
  /// handled elsewhere, by [SoloBase.onError] or by [SoloObserver.onError].
  ///
  /// ```dart
  /// solo.run<Ready, void>((ctx) => ctx.wait(hw.close)).ignore();
  /// ```
  ///
  /// Waiting for [done] or [value] observes the job too; calling this
  /// afterwards changes nothing. Has no effect on [Cancelled], which is
  /// never reported to the zone.
  void ignore();
}

/// Where a job is in its life.
///
/// The queue is not here: it belongs to whoever runs jobs, not to the job.
enum JobStatus {
  /// Made, not started; the body has not run.
  created,

  /// The body is running, or its children are still finishing.
  running,

  /// The outcome is set and will not change.
  finished,
}

/// A job of a controller: [Job] plus the queue.
///
/// Returned by [SoloBase.job], [SoloBase.add] and [SoloBase.run]. The
/// queue belongs to the controller, so [isQueued] lives here and not on
/// the handle every job has.
abstract interface class SoloJob<T> implements Job<T> {
  /// Whether the job waits in the controller's queue.
  bool get isQueued;
}

/// The lifecycle of a job: start, body, children, cancellation, outcome.
///
/// Subclass it to add a domain of your own — the state, the rules and the
/// queue in `solo`. Everything the engine of that domain needs is
/// protected, and the subclass opens exactly what it needs through private
/// wrappers of its own: `@protected` holds inside a subclass, and an
/// engine reaches a job from the side.
abstract class JobBase<T> implements Job<T> {
  /// Tracing of the job lifecycle for debugging; `null` by default.
  ///
  /// The queue, the state and the closing of a controller print into
  /// [SoloBase.debug] instead. To follow both sides, set both.
  static void Function(String message)? debug;

  final Object? _key;
  final String Function()? _describe;
  final JobObserver? _observer;

  /// The zone the job was created in; an unobserved [Failed] goes here.
  final Zone _zone = Zone.current;

  final _done = Completer<Outcome<T>>();
  final _cancelled = Completer<void>();
  final _onCancel = <void Function()>[];
  final _children = <JobBase<Object?>>[];

  bool _cancellable;

  /// Whether anyone asked for the outcome: [done], [value] or [ignore].
  bool _observed = false;

  JobStatus _status = JobStatus.created;
  Outcome<T>? _outcome;
  Cancelled? _pendingCancel;
  int _level = 0;

  /// Creates a job that has not started yet.
  JobBase({
    Object? key,
    String Function()? describe,
    bool cancellable = true,
    JobObserver? observer,
  })  : _key = key,
        _describe = describe,
        _cancellable = cancellable,
        _observer = observer;

  static void _debug(String Function() message) {
    final debug = JobBase.debug;
    if (debug != null) {
      debug(message());
    }
  }

  /// Calls [hook] and hands whatever it throws to the current zone.
  ///
  /// The observer of a job is a cross-cutting channel: an error in it
  /// changes nothing else.
  static void _notify(void Function() hook) {
    try {
      hook();
    } on Object catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  @override
  Object? get key => _key;

  @override
  String describe() => _describe?.call() ?? '';

  @override
  int get level => _level;

  @override
  bool get isChild => _level > 0;

  @override
  bool get isRunning => _status == JobStatus.running;

  @override
  bool get isFinished => _status == JobStatus.finished;

  @override
  bool get isCancelled => _pendingCancel != null || _outcome is Cancelled;

  @override
  Outcome<T>? get outcome => _outcome;

  @override
  Future<Outcome<T>> get done {
    _observed = true;
    return _done.future;
  }

  @override
  void ignore() => _observed = true;

  @override
  Future<T> get value async {
    _observed = true;
    final outcome = await _done.future;
    return switch (outcome) {
      Done(:final value) => value,
      Failed(:final error, :final stackTrace) =>
        Error.throwWithStackTrace(error, stackTrace),
      Cancelled() => Error.throwWithStackTrace(
          outcome,
          outcome.stackTrace ?? StackTrace.current,
        ),
    };
  }

  @override
  Future<void> get whenCancelled => _cancelled.future;

  /// Where the job is in its life.
  @protected
  JobStatus get status => _status;

  /// The cancellation the job is marked with, or `null`.
  @protected
  Cancelled? get pendingCancel => _pendingCancel;

  /// Whether the job accepts a cancellation it may refuse.
  @protected
  bool get cancellable => _cancellable;

  @protected
  set cancellable(bool value) => _cancellable = value;

  /// Set by whoever adopts the job, before it starts.
  @protected
  set level(int value) => _level = value;

  /// The children this job waits for.
  @protected
  List<JobBase<Object?>> get children => _children;

  /// Waiting without observing: an engine waits for a job to finish
  /// without marking its outcome observed, so a failure nobody looked at
  /// still reaches the zone.
  @protected
  Future<void> get whenDone => _done.future.then((_) {});

  /// Runs the body. Throws [StateError] if the job already ran.
  @protected
  void start() {
    if (_status != JobStatus.created) {
      throw StateError('$this has already been added or run');
    }
    _status = JobStatus.running;
    started();
    _notifyStart();
    unawaited(_execute(createContext()));
  }

  /// Ends the job with [outcome].
  @protected
  void finish(Outcome<T> outcome) {
    _outcome = outcome;
    _status = JobStatus.finished;
    // A job cancelled before it started never went through `_markCancelled`,
    // so `whenCancelled` is still open here.
    if (outcome is Cancelled && !_cancelled.isCompleted) {
      _cancelled.complete();
    }
    finished();
    _notifyFinish();
    _done.complete(outcome);
    if (outcome is Failed && !_observed) {
      _reportUnobserved(outcome);
    }
  }

  /// Hands [error] to the observer alone.
  ///
  /// For an error that has an outcome of its own — the body's. It reaches
  /// the zone through that outcome, if nobody observes it, and shouting
  /// twice about one error is worse than once.
  @protected
  void notifyObserver(Object error, StackTrace stackTrace) {
    _debug(() => '$this error: $error');
    _notify(() => _observer?.onError(this, error, stackTrace));
  }

  /// Hands [error] to the observer, or to the zone when there is none.
  ///
  /// For the errors that have nowhere else to go: an action abandoned by
  /// [JobContext.wait] failing later, a disposer, a callback of
  /// [JobContext.onCancel]. Silence is the choice of whoever listens, not
  /// the default of the package.
  @protected
  void notifyError(Object error, StackTrace stackTrace) {
    final observer = _observer;
    if (observer == null) {
      _zone.handleUncaughtError(error, stackTrace);
      return;
    }
    _debug(() => '$this error: $error');
    _notify(() => observer.onError(this, error, stackTrace));
  }

  /// The subclass joins the run: `solo` adds the job to its running list.
  @protected
  void started() {}

  /// The subclass leaves the run: `solo` clears `current` and pumps.
  @protected
  void finished() {}

  /// The child's own word on who may adopt it. Empty here: [JobContext.run]
  /// has already checked that the child is a job of this core.
  @protected
  void adoptedBy(JobContextBase parent) {}

  /// The context this job hands to its body.
  @protected
  JobContextBase createContext();

  /// Runs the body with [ctx]; a subclass narrows the type with
  /// `covariant`.
  @protected
  Future<T> execute(JobContextBase ctx);

  void _notifyStart() {
    _debug(() => '$this started');
    _notify(() => _observer?.onStart(this));
  }

  void _notifyFinish() {
    _debug(() => '$this finished: $_outcome');
    _notify(() => _observer?.onFinish(this));
  }

  void _notifyLog(String message) =>
      _notify(() => _observer?.onLog(this, message));

  Future<void> _execute(JobContextBase ctx) async {
    Outcome<T> outcome;
    try {
      outcome = Done(await execute(ctx));
    } on Cancelled catch (cancelled, stackTrace) {
      outcome = _pendingCancel ?? _handlerCancel(cancelled, stackTrace);
    } on Object catch (error, stackTrace) {
      notifyObserver(error, stackTrace);
      outcome = Failed(error, stackTrace);
    }
    await _awaitChildren();
    finish(_pendingCancel ?? outcome);
  }

  /// The body threw [thrown] without being marked cancelled: either its own
  /// `throw Cancelled(...)` or a child's cancellation via `child.value`.
  Cancelled _handlerCancel(Cancelled thrown, StackTrace stackTrace) {
    for (final child in _children) {
      if (identical(child._outcome, thrown)) {
        return Cancelled.by(
          reason: CancelReason.handler,
          started: true,
          description: 'child ${child.key}: $thrown',
          stackTrace: stackTrace,
        );
      }
    }
    return Cancelled.by(
      reason: CancelReason.handler,
      started: true,
      description: thrown.description,
      stackTrace: stackTrace,
    );
  }

  Future<void> _awaitChildren() async {
    while (true) {
      // `whenDone`, not `done`: waiting for a child is the engine's
      // business and must not mark the child observed for the parent.
      final pending = [
        for (final child in _children)
          if (!child.isFinished) child.whenDone,
      ];
      if (pending.isEmpty) {
        return;
      }
      await Future.wait(pending);
    }
  }

  /// Hands an unobserved failure to the zone that created the job.
  ///
  /// One microtask of grace, the same as Dart gives an unhandled `Future`
  /// error: a listener attached right after the job finished still counts.
  void _reportUnobserved(Failed outcome) {
    _zone.scheduleMicrotask(() {
      if (_observed) {
        return;
      }
      _debug(() => '$this failure went to the zone');
      _zone.handleUncaughtError(outcome.error, outcome.stackTrace);
    });
  }

  void _markCancelled(Cancelled cancelled) {
    _pendingCancel = cancelled;
    _cancelled.complete();
    // In registration order, and from a copy: a callback may register or
    // remove another one. `JobContext.onCancel` wraps the caller's
    // callbacks, so an error of theirs never reaches this loop.
    for (final callback in _onCancel.toList()) {
      callback();
    }
    _onCancel.clear();
  }

  @override
  String toString() {
    final description = describe();
    return description.isEmpty ? 'Job($key)' : 'Job($key: $description)';
  }
}

final class _SoloJob<S extends Object, W extends S, T> extends JobBase<T>
    implements SoloJob<T> {
  final SoloBase<S> _solo;
  final Future<T> Function(SoloContext<S, W> ctx) _body;
  final bool Function(W state)? _canStart;
  final bool Function(W state)? _keepWhile;

  _SoloJob(
    this._solo,
    this._body, {
    required super.key,
    required bool Function(W state)? canStart,
    required bool Function(W state)? keepWhile,
    required super.cancellable,
    required super.describe,
    required super.observer,
  })  : _canStart = canStart,
        _keepWhile = keepWhile;

  @override
  bool get isQueued => _solo._queue._jobs.contains(this);

  @override
  Future<void> cancel() {
    _solo._cancel(
      this,
      Cancelled.by(
        reason: CancelReason.manual,
        started: true,
        stackTrace: StackTrace.current,
      ),
    );
    // The engine's own waiting is not observation, so cancelling a job does
    // not silence its failure.
    return whenDone;
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

  @override
  void started() => _solo._running.add(this);

  @override
  void finished() => _solo._onJobFinished(this);

  @override
  JobContextBase createContext() => _SoloContext<S, W, T>(this);

  @override
  Future<T> execute(covariant _SoloContext<S, W, T> ctx) => _body(ctx);

  // The engine reaches a job from the side, and `@protected` holds only
  // inside a subclass; these wrappers are how `SoloBase` and `_SoloQueue`
  // touch it.
  void _launch() => start();

  void _drop(Outcome<T> outcome) => finish(outcome);

  JobStatus get _jobStatus => status;

  Cancelled? get _pending => pendingCancel;

  bool get _isCancellable => cancellable;

  List<JobBase<Object?>> get _childJobs => children;

  Future<void> get _whenDone => whenDone;
}
