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

  /// Whether the job waits in the queue.
  bool get isQueued;

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
  /// solo.run<Ready, void>((ctx) => ctx.guard(hw.close)).ignore();
  /// ```
  ///
  /// Waiting for [done] or [value] observes the job too; calling this
  /// afterwards changes nothing. Has no effect on [Cancelled], which is
  /// never reported to the zone.
  void ignore();
}

enum _JobStatus { created, queued, running, finished }

final class _Job<S extends Object, W extends S, T> implements Job<T> {
  final SoloBase<S> _solo;
  final Future<T> Function(JobContext<S, W> ctx) _body;
  final bool Function(W state)? _canStart;
  final bool Function(W state)? _keepWhile;
  final String Function()? _describe;
  bool cancellable;

  @override
  final Object? key;

  @override
  int level = 0;

  /// The zone the job was created in; an unobserved [Failed] goes here.
  final Zone _zone = Zone.current;

  /// Whether anyone asked for the outcome: [done], [value] or [ignore].
  bool _observed = false;

  _JobStatus _status = _JobStatus.created;
  Outcome<T>? _outcome;
  Cancelled? _pendingCancel;
  final _done = Completer<Outcome<T>>();
  final _cancelled = Completer<void>();
  final _onCancel = <void Function()>[];
  final _children = <_Job<S, S, Object?>>[];

  _Job(
    this._solo,
    this._body, {
    required this.key,
    required bool Function(W state)? canStart,
    required bool Function(W state)? keepWhile,
    required this.cancellable,
    required String Function()? describe,
  })  : _canStart = canStart,
        _keepWhile = keepWhile,
        _describe = describe;

  @override
  String describe() => _describe?.call() ?? '';

  @override
  bool get isChild => level > 0;

  @override
  bool get isQueued => _status == _JobStatus.queued;

  @override
  bool get isRunning => _status == _JobStatus.running;

  @override
  bool get isFinished => _status == _JobStatus.finished;

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

  @override
  Future<void> cancel() {
    _solo._cancel(
      this,
      Cancelled._(
        reason: CancelReason.manual,
        started: true,
        stackTrace: StackTrace.current,
      ),
    );
    // The engine's own waiting is not observation: `_done.future`, not
    // `done`, so cancelling a job does not silence its failure.
    return _done.future.then((_) {});
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

  void _start(int level) {
    _status = _JobStatus.running;
    this.level = level;
    _solo._running.add(this);
    _solo._notifyStart(this);
    unawaited(_execute(_JobContext<S, W, T>(this)));
  }

  Future<void> _execute(_JobContext<S, W, T> ctx) async {
    Outcome<T> outcome;
    try {
      outcome = Done(await _body(ctx));
    } on Cancelled catch (cancelled, stackTrace) {
      outcome = _pendingCancel ?? _handlerCancel(cancelled, stackTrace);
    } on Object catch (error, stackTrace) {
      _solo._notifyError(this, error, stackTrace);
      outcome = Failed(error, stackTrace);
    }
    await _awaitChildren();
    _finish(_pendingCancel ?? outcome);
  }

  /// The body threw [thrown] without being marked cancelled: either its own
  /// `throw Cancelled(...)` or a child's cancellation via `child.value`.
  Cancelled _handlerCancel(Cancelled thrown, StackTrace stackTrace) {
    for (final child in _children) {
      if (identical(child._outcome, thrown)) {
        return Cancelled._(
          reason: CancelReason.handler,
          started: true,
          description: 'child ${child.key}: $thrown',
          stackTrace: stackTrace,
        );
      }
    }
    return Cancelled._(
      reason: CancelReason.handler,
      started: true,
      description: thrown.description,
      stackTrace: stackTrace,
    );
  }

  Future<void> _awaitChildren() async {
    while (true) {
      // `_done.future`, not `done`: waiting for a child is the engine's
      // business and must not mark the child observed for the parent.
      final pending = [
        for (final child in _children)
          if (!child.isFinished) child._done.future,
      ];
      if (pending.isEmpty) {
        return;
      }
      await Future.wait(pending);
    }
  }

  void _finish(Outcome<T> outcome) {
    _outcome = outcome;
    _status = _JobStatus.finished;
    // A job cancelled before it started never went through `_markCancelled`,
    // so `whenCancelled` is still open here.
    if (outcome is Cancelled && !_cancelled.isCompleted) {
      _cancelled.complete();
    }
    _solo._onJobFinished(this);
    _done.complete(outcome);
    if (outcome is Failed && !_observed) {
      _reportUnobserved(outcome);
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
      SoloBase._debug(() => '$this failure went to the zone');
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
