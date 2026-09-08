import 'dart:async';
import 'dart:collection';

import 'package:jobs/jobs.dart';
import 'package:meta/meta.dart';

import 'observer.dart';
import 'policy.dart';
import 'solo_cancel_reason.dart';

part 'job.dart';
part 'job_context.dart';
part 'queue.dart';

/// The engine: state, queue, hooks. Subclasses add a delivery channel
/// through [publish]; see `Solo` for a stream.
///
/// The hooks — [onStart], [onFinish], [onError], [onLog], [onChange] and
/// the [observer]'s — are a cross-cutting channel, so an error thrown by
/// one goes to the current zone and changes nothing else: the job's outcome,
/// the queue and [close] carry on as if the hook had returned. [onError] is
/// the one with a body of its own: what reaches it and has nowhere else to
/// go — a disposer, an `onCancel` callback, a late failure of an abandoned
/// call or of work handed to `JobContext.unattended`, a rule that threw —
/// goes on to the zone when nobody is listening. [publish] is
/// not one of them: it is how a subclass delivers the state, and an error
/// there is the subclass's own business.
abstract class SoloBase<S extends Object> {
  /// A global observer for all controllers; `null` by default.
  static SoloObserver? observer;

  /// Engine tracing for debugging the engine itself; `null` by default.
  static void Function(String message)? debug;

  S _state;
  Completer<void>? _closing;
  StackTrace? _closeStackTrace;
  final _queue = _SoloQueue<S>();

  /// The observer every job of this controller is given.
  late final JobObserver _jobObserver = _SoloJobObserver<S>(this);

  /// The job whose error with nowhere to go is going through the hooks
  /// right now, set by `_SoloJob.notifyError`.
  _SoloJob<S, S, Object?>? _homeless;
  _SoloJob<S, S, Object?>? _current;
  final _running = <_SoloJob<S, S, Object?>>[];
  StackTrace? _lastChange;
  bool _pumpScheduled = false;
  final _unpublished = <(S, S)>[];
  bool _publishing = false;

  /// Creates a controller in [initialState].
  SoloBase(S initialState) : _state = initialState {
    _callHook(() => observer?.onCreate(this));
  }

  /// Calls [hook] and hands whatever it throws to the current zone, the way
  /// Dart reports an unhandled `Future` error.
  ///
  /// Hooks are a cross-cutting channel — analytics, logging, error
  /// reporting — called independently of each other and of the job. A
  /// failure in one is therefore not allowed to change anything else: not a
  /// job's outcome, not the queue, not the closing. Each call is isolated on
  /// its own, so a throwing observer does not switch off the instance hook
  /// standing next to it.
  static void _callHook(void Function() hook) {
    try {
      hook();
    } on Object catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  /// The current state. Reading is always safe; only jobs write.
  S get state => _state;

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
  /// protects the job from `cancel`, `clear` without `force`, parent
  /// cancellation and `close`, but not from a state that stopped matching
  /// `W` or `keepWhile`; [JobContext.uncancellable] says the same about one
  /// step of the body rather than about the whole job.
  SoloJob<T> job<W extends S, T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    String Function()? describe,
  }) =>
      _SoloJob<S, W, T>(
        this,
        body,
        key: key,
        canStart: canStart,
        keepWhile: keepWhile,
        cancellable: cancellable,
        describe: describe,
        observer: _jobObserver,
      );

  /// Queues [job] and returns it, or the existing job found by
  /// [Policy.droppable].
  ///
  /// Throws [StateError] if [job] was already added or run, and
  /// [ArgumentError] if [policy] is not [Policy.sequential] and the job has
  /// no key, or if [job] was created by another controller. After `close`
  /// the job finishes at once with `Cancelled(closed)`.
  SoloJob<T> add<T>(
    Job<T> job, {
    bool first = false,
    Policy policy = Policy.sequential,
  }) {
    final impl = _own(job);
    if (policy != Policy.sequential && impl.key == null) {
      throw ArgumentError('Policy.${policy.name} requires a job key');
    }
    if (impl._added ||
        impl._jobStatus != JobStatus.created ||
        _queue._jobs.contains(impl)) {
      throw StateError('$impl has already been added or run');
    }
    // Set before anything can go wrong below: a job dropped by a closed
    // controller has been added too, and one handle is one add.
    impl._added = true;
    if (isClosed) {
      _debug(() => 'add $impl: closed');
      impl._drop(
        Cancelled.by(
          reason: SoloCancelReason.closed,
          started: false,
          stackTrace: _closeStackTrace,
        ),
      );
      return impl;
    }
    switch (policy) {
      case Policy.sequential:
        break;
      case Policy.droppable:
        final existing = lastJobWhere((other) => other.key == impl.key);
        if (existing != null) {
          _debug(() => 'add $impl: duplicate of $existing');
          impl._drop(
            Cancelled.by(
              reason: CancelReason.manual,
              started: false,
              description: 'duplicate',
              stackTrace: StackTrace.current,
            ),
          );
          return existing as SoloJob<T>;
        }
      case Policy.replace:
        _queue.removeWhere((other) => other.key == impl.key);
      case Policy.restart:
        _queue.removeWhere((other) => other.key == impl.key);
        final current = _current;
        if (current != null && current.key == impl.key) {
          unawaited(current.cancel());
        }
    }
    _queue._insert(impl, first: first);
    _debug(() => 'add $impl${first ? ' first' : ''}');
    _schedulePump();
    return impl;
  }

  /// `add(job(...), policy: policy)` in one call: how a method of a
  /// controller builds its job and queues it.
  ///
  /// Every parameter but [policy] belongs to [job], which documents them
  /// all; [policy] belongs to [add]. Returns the queued job; on a closed
  /// controller it gives back one already finished with
  /// `Cancelled(closed)` rather than throwing. It does throw what [add]
  /// throws for a job it cannot take: [ArgumentError] for a policy that
  /// needs a key without one, and a [TypeError] from [Policy.droppable]
  /// when one key is shared by jobs with different result types.
  ///
  /// ```dart
  /// Job<String> load() => run<Profile, String>(
  ///       key: 'load',
  ///       policy: Policy.droppable,
  ///       (ctx) async {
  ///         final name = await ctx.wait(api.fetchName);
  ///         ctx.emit(Profile(name: name));
  ///
  ///         return name;
  ///       },
  ///     );
  /// ```
  SoloJob<T> run<W extends S, T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
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
  SoloJob<Object?>? lastJobWhere(bool Function(Job<Object?> job) test) {
    for (final job in _queue._jobs.reversed) {
      if (test(job)) {
        return job;
      }
    }
    final current = _current;
    return current != null && test(current) ? current : null;
  }

  /// Sets the state from outside any job: hardware listeners, forced
  /// transitions. Re-evaluates the rules of every running job.
  ///
  /// Not blocked by [close]: after closing it still changes [state], calls
  /// `onChange` and re-evaluates the rules, while a subclass channel that is
  /// already closed — `Solo`'s stream, for one — drops the event. Stop the
  /// source of external states before closing the controller.
  @protected
  void externalSetState(S state) {
    _debug(() => 'externalSetState: $state');
    _setState(state, emitter: null, stackTrace: StackTrace.current);
  }

  /// Closes the controller: drops every queued job with `Cancelled(closed)`,
  /// cancels the current job (a `cancellable: false` job is waited for
  /// instead), then calls the observer's `onClose`. Repeated calls return
  /// the same future. The state is left as is.
  ///
  /// Awaiting the returned future from inside the current job's body never
  /// completes: it waits for that very body.
  @mustCallSuper
  Future<void> close() {
    final closing = _closing;
    if (closing != null) {
      return closing.future;
    }
    final completer = _closing = Completer<void>();
    _debug(() => 'close');
    // Kept for `add` after close: section 5.1 points every `closed` outcome
    // at the `close` call, whichever of the two sources made it.
    final stackTrace = _closeStackTrace = StackTrace.current;
    for (final job in _queue._drain()) {
      job._drop(
        Cancelled.by(
          reason: SoloCancelReason.closed,
          started: false,
          stackTrace: stackTrace,
        ),
      );
    }
    final current = _current;
    if (current == null) {
      // Nothing to wait for, but still finish on a microtask: `onClose`
      // never arrives from inside `close`, whether the engine was busy or
      // idle.
      scheduleMicrotask(() => _finishClose(completer));
    } else {
      // Rejectable on purpose: `close` waits for a job that refuses.
      current._cancelWith(
        Cancelled.by(
          reason: SoloCancelReason.closed,
          started: true,
          stackTrace: stackTrace,
        ),
      );
      // `whenDone`, not `done`: closing waits for the job, it does not
      // observe its outcome, so a failure here still reaches the zone.
      current._whenDone.then((_) => _finishClose(completer));
    }
    return completer.future;
  }

  void _finishClose(Completer<void> completer) {
    _debug(() => 'closed');
    _callHook(() => observer?.onClose(this));
    completer.complete();
  }

  /// Clears the queue and cancels the current job; `force` affects only the
  /// queue. Completes when the current job has actually finished.
  ///
  /// Awaiting the returned future from inside the current job's body never
  /// completes: it waits for that very body.
  Future<void> cancelAll({bool force = false}) {
    _queue.clear(force: force);
    final current = _current;
    return current == null ? Future<void>.value() : current.cancel();
  }

  /// A job body is about to run.
  void onStart(Job<Object?> job) {}

  /// A job has an outcome, including jobs dropped before start.
  void onFinish(Job<Object?> job) {}

  /// Something a job did threw where there was nowhere else to put it.
  ///
  /// The body; an action abandoned by [JobContext.wait] failing later; a
  /// disposer or an `onCancel` callback; and a rule of this controller —
  /// `canStart` or `keepWhile` — that threw instead of answering.
  ///
  /// Called for every such error. The job's own cancellation is not an
  /// error and never comes here; a [Cancelled] thrown by an abandoned
  /// action does, because for an observer that is a late failure like any
  /// other. See [Failed] for the errors that also reach the zone.
  ///
  /// **What the default body does.** With no [observer] set and this hook
  /// not overridden, nobody is listening, and the error goes to the zone
  /// the job was created in — the same thing the core does when a job has
  /// no observer at all. Silence is the choice of whoever listens, not the
  /// default of the package. A [Cancelled] is the one exception and never
  /// goes there: a cancellation is a decision somebody made, not a
  /// failure. The body's own failure does not go there from here either —
  /// it reaches the zone through its unobserved outcome instead, and one
  /// error is announced once.
  ///
  /// **Overriding replaces that**, so an override that says nothing keeps
  /// the error out of the zone; call `super.onError(job, error,
  /// stackTrace)` to keep the default route as well.
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    final homeless = _homeless;
    // Only an error with nowhere else to go, only when nobody is
    // listening, and never a cancellation: a cancellation is a decision
    // somebody made, not a failure, and in Flutter it would reach
    // `PlatformDispatcher.onError` for nothing.
    if (homeless != null &&
        identical(homeless, job) &&
        observer == null &&
        error is! Cancelled) {
      homeless._reportToZone(error, stackTrace);
    }
  }

  /// A job called [JobContext.log].
  void onLog(Job<Object?> job, String message) {}

  /// The state changed, from a job or from [externalSetState].
  void onChange(S previous, S current) {}

  _SoloJob<S, S, T> _own<T>(Job<T> job) {
    if (job is _SoloJob<S, S, T> && identical(job._solo, this)) {
      return job;
    }
    throw ArgumentError.value(job, 'job', 'was not created by this Solo');
  }

  void _setState(
    S next, {
    required _SoloJob<S, S, Object?>? emitter,
    required StackTrace stackTrace,
  }) {
    final previous = _state;
    _state = next;
    _lastChange = stackTrace;
    _debug(() => 'state: $next');
    _unpublished.add((previous, next));
    _callHook(() => observer?.onChange(this, previous, next));
    _callHook(() => onChange(previous, next));
    _publishPending();
    _reevaluate(except: emitter, stackTrace: stackTrace);
  }

  /// Publishes the recorded changes, oldest first.
  ///
  /// A hook, an observer or a listener may set the state again from inside
  /// this call: the nested change joins the same queue instead of being
  /// published ahead of the older one it is nested in.
  void _publishPending() {
    if (_publishing) {
      return;
    }
    _publishing = true;
    try {
      while (_unpublished.isNotEmpty) {
        final change = _unpublished.removeAt(0);
        publish(change.$1, change.$2);
      }
    } finally {
      _publishing = false;
    }
  }

  /// Re-evaluates the rules of every running job except [except] against
  /// the current state, children before parents.
  void _reevaluate({
    required _SoloJob<S, S, Object?>? except,
    required StackTrace stackTrace,
  }) {
    for (final job in _running.reversed.toList()) {
      // Тела нет — правилам нечего стеречь: они держат работу тела, а не
      // ожидание детей и не уборку. `cancel()`, `close()` и каскад
      // родителя дотягиваются до задачи по-прежнему.
      if (identical(job, except) || job.isCancelled || job._bodyEnded) {
        continue;
      }
      final String? rejection;
      try {
        rejection = job._rejectKeep(_state);
      } on Object catch (error, stackTrace) {
        // A rule that threw says nothing about whether the job may go on,
        // and the jobs behind it still have to be looked at.
        job._notifyError(error, stackTrace);
        continue;
      }
      if (rejection != null) {
        // A rule of the job's own: it may not refuse this one.
        job._cancelWith(
          Cancelled.by(
            reason: SoloCancelReason.rules,
            started: true,
            description: rejection,
            stackTrace: stackTrace,
          ),
          rejectable: false,
        );
      }
    }
  }

  void _onJobFinished(_SoloJob<S, S, Object?> job) {
    final wasCurrent = identical(job, _current);
    if (wasCurrent) {
      _current = null;
    }
    _running.remove(job);
    if (wasCurrent) {
      _schedulePump();
    }
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
      final String? rejection;
      try {
        rejection = job._rejectStart(_state);
      } on Object catch (error, stackTrace) {
        // The rules are the caller's code, and this one threw. The job is
        // already out of the queue: left as it is, it would never finish,
        // and the pump would never come back for the ones behind it.
        _debug(() => 'rule of $job threw: $error');
        job
          .._notifyObserver(error, stackTrace)
          .._drop(Failed(error, stackTrace));
        continue;
      }
      if (rejection != null) {
        job._drop(
          Cancelled.by(
            reason: SoloCancelReason.rules,
            started: false,
            description: rejection,
            stackTrace: StackTrace.current,
          ),
        );
        continue;
      }
      if (isClosed) {
        // The rules are the caller's code, and one of them closed the
        // controller while it was being asked. Nothing starts after that.
        _debug(() => 'start $job: closed while the rules were asked');
        job._drop(
          Cancelled.by(
            reason: SoloCancelReason.closed,
            started: false,
            stackTrace: _closeStackTrace,
          ),
        );
        continue;
      }
      _current = job;
      job._launch();
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

/// Feeds the hooks of one job into [SoloObserver] and into the controller's
/// own hooks, each call isolated on its own.
///
/// A throwing observer must not switch off the instance hook standing next
/// to it, so the two calls are wrapped separately.
final class _SoloJobObserver<S extends Object> implements JobObserver {
  final SoloBase<S> _solo;

  _SoloJobObserver(this._solo);

  @override
  void onStart(Job<Object?> job) {
    SoloBase._callHook(() => SoloBase.observer?.onStart(_solo, job));
    SoloBase._callHook(() => _solo.onStart(job));
  }

  @override
  void onFinish(Job<Object?> job) {
    SoloBase._callHook(() => SoloBase.observer?.onFinish(_solo, job));
    SoloBase._callHook(() => _solo.onFinish(job));
  }

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    SoloBase._callHook(
      () => SoloBase.observer?.onError(_solo, job, error, stackTrace),
    );
    SoloBase._callHook(() => _solo.onError(job, error, stackTrace));
  }

  @override
  void onLog(Job<Object?> job, String message) {
    SoloBase._callHook(() => SoloBase.observer?.onLog(_solo, job, message));
    SoloBase._callHook(() => _solo.onLog(job, message));
  }
}
