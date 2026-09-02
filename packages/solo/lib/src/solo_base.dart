import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

import 'observer.dart';
import 'policy.dart';

part 'outcome.dart';
part 'job.dart';
part 'job_context.dart';
part 'queue.dart';

/// The engine: state, queue, hooks. Subclasses add a delivery channel
/// through [publish]; see `Solo` for a stream.
abstract class SoloBase<S extends Object> {
  /// A global observer for all controllers; `null` by default.
  static SoloObserver? observer;

  /// Engine tracing for debugging the engine itself; `null` by default.
  static void Function(String message)? debug;

  S _state;
  Completer<void>? _closing;
  late final _SoloQueue<S> _queue = _SoloQueue<S>(this);
  _Job<S, S, Object?>? _current;
  final _running = <_Job<S, S, Object?>>[];
  StackTrace? _lastChange;
  bool _pumpScheduled = false;

  /// Creates a controller in [initialState].
  SoloBase(S initialState) : _state = initialState {
    observer?.onCreate(this);
  }

  /// The current state. Reading is always safe; only jobs write.
  S get state => _state;

  // `close` is added in Task 12; until then this forward reference does not
  // resolve.
  // ignore: comment_references
  /// Whether [close] was called.
  bool get isClosed => _closing != null;

  /// Delivery point for subclasses; empty here. Called after `onChange` and
  /// before running jobs are re-evaluated.
  @protected
  @mustCallSuper
  void publish(S previous, S current) {}

  /// Creates a job without queueing it. Use for job factories such as
  /// `_closeCameraJob()` that are added or run as children later.
  ///
  /// `canStart` is checked once, when the job is taken from the queue;
  /// `keepWhile` is checked at start, on every state change while the job
  /// runs, and on every read through the context. `cancellable: false`
  /// protects the running job from `cancel`, `clear` without `force`,
  /// parent cancellation and `close`, but not from a state that stopped
  /// matching `W` or `keepWhile`.
  Job<T> job<W extends S, T>(
    Future<T> Function(JobContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    String Function()? describe,
  }) =>
      _Job<S, W, T>(
        this,
        body,
        key: key,
        canStart: canStart,
        keepWhile: keepWhile,
        cancellable: cancellable,
        describe: describe,
      );

  /// Queues [job] and returns it, or the existing job found by
  /// [Policy.droppable].
  ///
  /// Throws [StateError] if [job] was already added or run, and
  /// [ArgumentError] if [policy] is not [Policy.sequential] and the job has
  /// no key, or if [job] was created by another controller. After `close`
  /// the job finishes at once with `Cancelled(closed)`.
  Job<T> add<T>(
    Job<T> job, {
    bool first = false,
    Policy policy = Policy.sequential,
  }) {
    final impl = _own(job);
    if (policy != Policy.sequential && impl.key == null) {
      throw ArgumentError.value(policy, 'policy', 'requires a job key');
    }
    if (impl._status != _JobStatus.created) {
      throw StateError('$impl has already been added or run');
    }
    if (isClosed) {
      _debug(() => 'add $impl: closed');
      impl._finish(
        Cancelled._(
          reason: CancelReason.closed,
          started: false,
          stackTrace: StackTrace.current,
        ),
      );
      return job;
    }
    if (policy != Policy.sequential) {
      throw UnimplementedError('task 9');
    }
    impl._status = _JobStatus.queued;
    _queue._insert(impl, first: first);
    _debug(() => 'add $impl${first ? ' first' : ''}');
    _schedulePump();
    return job;
  }

  /// `add(job(...), policy: policy)` in one call.
  Job<T> run<W extends S, T>(
    Future<T> Function(JobContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    String Function()? describe,
    Policy policy = Policy.sequential,
  }) =>
      add(
        job<W, T>(
          body,
          key: key,
          canStart: canStart,
          keepWhile: keepWhile,
          cancellable: cancellable,
          describe: describe,
        ),
        policy: policy,
      );

  /// The queue, for subclasses that manage it directly.
  @protected
  SoloQueue get queue => _queue;

  /// The running root job, or `null` when idle.
  @protected
  Job<Object?>? get current => _current;

  /// The last queued job matching [test], else the current job if it
  /// matches, else `null`.
  @protected
  Job<Object?>? lastJobWhere(bool Function(Job<Object?> job) test) {
    final queued = _queue.lastWhere(test);
    if (queued != null) {
      return queued;
    }
    final current = _current;
    return current != null && test(current) ? current : null;
  }

  /// Sets the state from outside any job: hardware listeners, forced
  /// transitions. Re-evaluates the rules of every running job.
  @protected
  void externalSetState(S state) {
    _debug(() => 'externalSetState: $state');
    _setState(state, emitter: null, stackTrace: StackTrace.current);
  }

  /// Clears the queue and cancels the current job; `force` affects only the
  /// queue. Completes when the current job has actually finished.
  Future<void> cancelAll({bool force = false}) {
    _queue.clear(force: force);
    final current = _current;
    return current == null ? Future<void>.value() : current.cancel();
  }

  /// A job body is about to run.
  void onStart(Job<Object?> job) {}

  /// A job has an outcome, including jobs dropped before start.
  void onFinish(Job<Object?> job) {}

  /// A job body threw a non-[Cancelled] error, even after cancellation.
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}

  /// A job called [JobContext.log].
  void onLog(Job<Object?> job, String message) {}

  /// The state changed, from a job or from [externalSetState].
  void onChange(S previous, S current) {}

  _Job<S, S, T> _own<T>(Job<T> job) {
    if (job is _Job<S, S, T> && identical(job._solo, this)) {
      return job;
    }
    throw ArgumentError.value(job, 'job', 'was not created by this Solo');
  }

  void _setState(
    S next, {
    required _Job<S, S, Object?>? emitter,
    required StackTrace stackTrace,
  }) {
    final previous = _state;
    _state = next;
    _lastChange = stackTrace;
    _debug(() => 'state: $next');
    observer?.onChange(this, previous, next);
    onChange(previous, next);
    publish(previous, next);
    _reevaluate(except: emitter, stackTrace: stackTrace);
  }

  /// Re-evaluates the rules of every running job except [except] against
  /// the current state, children before parents.
  void _reevaluate({
    required _Job<S, S, Object?>? except,
    required StackTrace stackTrace,
  }) {
    for (final job in _running.reversed.toList()) {
      if (identical(job, except) || job.isCancelled) {
        continue;
      }
      final rejection = job._rejectKeep(_state);
      if (rejection != null) {
        _cancel(
          job,
          Cancelled._(
            reason: CancelReason.rules,
            started: true,
            description: rejection,
            stackTrace: stackTrace,
          ),
        );
      }
    }
  }

  /// Cancels [job] with [cancelled]; `started` is corrected to the job's
  /// status. Idempotent. [force] lets a queued `cancellable: false` job go.
  void _cancel(
    _Job<S, S, Object?> job,
    Cancelled cancelled, {
    bool force = false,
  }) {
    Cancelled notStarted() => Cancelled._(
          reason: cancelled.reason,
          started: false,
          description: cancelled.description,
          stackTrace: cancelled.stackTrace,
        );
    switch (job._status) {
      case _JobStatus.finished:
        return;
      case _JobStatus.created:
        _debug(() => 'cancel $job before add: $cancelled');
        job._finish(notStarted());
      case _JobStatus.queued:
        if (!job.cancellable && !force) {
          _debug(() => 'cancel $job: not cancellable');
          return;
        }
        _debug(() => 'remove $job: $cancelled');
        _queue._jobs.remove(job);
        job._finish(notStarted());
      case _JobStatus.running:
        if (job._pendingCancel != null) {
          return;
        }
        if (!job.cancellable && cancelled.reason != CancelReason.rules) {
          _debug(() => 'cancel $job: not cancellable');
          return;
        }
        _debug(() => 'cancel $job: $cancelled');
        for (final child in job._children.reversed.toList()) {
          _cancel(
            child,
            Cancelled._(
              reason: CancelReason.parent,
              started: true,
              stackTrace: cancelled.stackTrace,
            ),
          );
        }
        job._markCancelled(cancelled);
    }
  }

  void _onJobFinished(_Job<S, S, Object?> job) {
    final wasCurrent = identical(job, _current);
    if (wasCurrent) {
      _current = null;
    }
    _running.remove(job);
    _debug(() => '$job finished: ${job.outcome}');
    observer?.onFinish(this, job);
    onFinish(job);
    if (wasCurrent) {
      _schedulePump();
    }
  }

  void _notifyStart(_Job<S, S, Object?> job) {
    _debug(() => '$job started');
    observer?.onStart(this, job);
    onStart(job);
  }

  void _notifyError(
    _Job<S, S, Object?> job,
    Object error,
    StackTrace stackTrace,
  ) {
    _debug(() => '$job error: $error');
    observer?.onError(this, job, error, stackTrace);
    onError(job, error, stackTrace);
  }

  void _notifyLog(_Job<S, S, Object?> job, String message) {
    observer?.onLog(this, job, message);
    onLog(job, message);
  }

  /// Schedules a pump so the caller finishes its synchronous part first:
  /// it may add several jobs and rearrange the queue before the first
  /// one starts.
  void _schedulePump() {
    if (_pumpScheduled) {
      return;
    }
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  void _pump() {
    if (_current != null || isClosed) {
      return;
    }
    while (true) {
      final job = _queue._takeFirst();
      if (job == null) {
        _debug(() => 'queue is empty');
        return;
      }
      final rejection = job._rejectStart(_state);
      if (rejection != null) {
        job._finish(
          Cancelled._(
            reason: CancelReason.rules,
            started: false,
            description: rejection,
            stackTrace: StackTrace.current,
          ),
        );
        continue;
      }
      _current = job;
      job._start(0);
      return;
    }
  }

  static void _debug(String Function() message) {
    final debug = SoloBase.debug;
    if (debug != null) {
      debug(message());
    }
  }
}
