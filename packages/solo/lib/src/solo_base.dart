import 'dart:async';
import 'dart:collection';

import 'package:async_job/async_job.dart';
import 'package:meta/meta.dart';

import 'close_mode.dart';
import 'observer.dart';
import 'pending.dart';
import 'policy.dart';
import 'solo_cancel_reason.dart';
import 'transition.dart';

part 'accumulator.dart';
part 'accumulation_timing.dart';
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
  ///
  /// Watching only. Setting one changes nothing about where an error then
  /// goes; [errorHandler] is what takes that over.
  static SoloObserver? observer;

  /// Where an error with nowhere else to go goes instead of the zone;
  /// `null` by default.
  ///
  /// The errors [onError] describes — a disposer, an `onCancel` callback,
  /// a late failure of an abandoned call, a rule that threw — have no
  /// outcome of their own to carry them anywhere. With nobody set here
  /// they reach the zone the job was created in; with a handler set they
  /// go to it instead, for every controller of the process, and what it
  /// does with one is the end of it.
  ///
  /// One global handler, set once at startup, the way [observer] is. It is
  /// separate from the observer on purpose: answering for an error is a
  /// responsibility somebody takes, not a side effect of switching a log
  /// on. An error it throws itself goes to the zone.
  ///
  /// ```dart
  /// SoloBase.errorHandler = (solo, job, error, stackTrace) =>
  ///     Sentry.captureException(error, stackTrace: stackTrace);
  /// ```
  static SoloErrorHandler? errorHandler;

  /// Engine tracing for debugging the engine itself; `null` by default.
  static void Function(String message)? debug;

  S _state;
  int _stateRevision = 0;
  Completer<void>? _closing;
  StackTrace? _closeStackTrace;
  var _draining = false;
  final _queue = _SoloQueue<S>();
  final _timers = <Timer>{};

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

  /// Whether [close] was called with [SoloCloseMode.drain] and the queue
  /// it is running has not emptied yet.
  ///
  /// New root jobs are refused the whole time — [isClosed] is true from
  /// the call — while the engine goes on with the ones it already had.
  bool get isDraining => _draining;

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
  /// turns down every cancellation that may be turned down — `cancel`,
  /// `clear` without `force`, parent cancellation and `close` — but not a
  /// state that stopped matching `W` or `keepWhile`.
  ///
  /// The flag is consulted only once the engine holds the job. One this
  /// method has made and nobody has added is cancelled like any other.
  /// Queued, it turns down `cancel` and a `clear` without `force`, while
  /// `close` and `clear` with `force` take it out anyway — they do not
  /// ask. Running, it turns down all four. [JobContext.uncancellable] says
  /// the same about one step of the body rather than about the whole job.
  ///
  /// [onError] and [onCancel] synchronously map the current state to the
  /// state after a failed or cancelled body. They run after children and
  /// resource cleanup, with the outcome fixed, before [SoloBase.onFinish]
  /// and before the next queued job. They do not change or observe the
  /// outcome: [Job.value] still throws, and an unobserved failure is still
  /// reported. A handler error goes to the error hook and observer without
  /// replacing the original outcome.
  ///
  /// Neither runs on success or when the body never started. An external
  /// state change that violates `W` or [keepWhile] permanently suppresses
  /// both handlers, including during cancellation, child waiting or
  /// cleanup. A parent's lost permission also suppresses its descendants'
  /// handlers. A parent without state handlers stops checking its rules
  /// when its body ends, as usual. A rule error suppresses correction and
  /// is reported.
  /// [canStart] is not repeated, and the job's own emit is exempt.
  ///
  /// Handlers receive `S`, which may differ from the body's working `W`,
  /// and should only compute the next state. Cleanup belongs in
  /// [JobContext.onDispose] or [JobContext.onDiscard]. The [onCancel]
  /// parameter runs at completion; [JobContext.onCancel] instead delivers
  /// the cancellation signal immediately to the operation being stopped.
  SoloJob<T> job<W extends S, T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    String Function()? describe,
    S Function(S state, Object error, StackTrace stackTrace)? onError,
    S Function(S state, Cancelled cancelled)? onCancel,
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
        onError: onError,
        onCancel: onCancel,
      );

  /// Creates an accumulator that collects events into an immutable list.
  ///
  /// No job is created until [SoloAccumulator.add]. Events retain their order
  /// and duplicates; the list is copied once when the group is sealed.
  /// The handler receives a regular context and runs under the same rules as
  /// [job]. It changes state only when it runs, never when an event is added.
  /// [policy] chooses the waiting group and its position; [key] is an ordinary
  /// job key and does not make different accumulators compatible. [timing]
  /// can debounce each group or throttle starts across this accumulator;
  /// ready jobs later in the queue can bypass a group waiting for its window.
  SoloAccumulator<E, T> collect<W extends S, E, T>(
    Future<T> Function(SoloContext<S, W> ctx, List<E> events) handler, {
    Object? key,
    AccumulationPolicy policy = AccumulationPolicy.adjacent,
    AccumulationTiming? timing,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    String Function()? describe,
  }) =>
      _SoloAccumulator<S, W, E, List<E>, T>(
        this,
        handler,
        seed: (event) => <E>[event],
        merge: (events, event) => events..add(event),
        snapshot: List<E>.unmodifiable,
        key: key,
        policy: policy,
        timing: timing,
        canStart: canStart,
        keepWhile: keepWhile,
        cancellable: cancellable,
        describe: describe,
      );

  /// Creates an accumulator holding one value, combined synchronously by
  /// [merge] on each addition after the first. Nullable events are supported.
  ///
  /// [merge] must be pure: do not mutate either argument, the controller or
  /// its queue. Errors escape from [SoloAccumulator.add] without changing the
  /// previous value. A recursive add from merge throws [StateError].
  /// Only the latest merged value is retained; no event history is stored.
  /// The handler, rules, key and policy follow [collect]. No job is created
  /// until the first event, and no state changes before the handler runs.
  /// [timing] has the same group readiness behavior as it does for [collect].
  SoloAccumulator<E, T> accumulate<W extends S, E, T>(
    Future<T> Function(SoloContext<S, W> ctx, E value) handler, {
    required E Function(E accumulated, E incoming) merge,
    Object? key,
    AccumulationPolicy policy = AccumulationPolicy.adjacent,
    AccumulationTiming? timing,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    String Function()? describe,
  }) =>
      _SoloAccumulator<S, W, E, E, T>(
        this,
        handler,
        seed: (event) => event,
        merge: merge,
        snapshot: (value) => value,
        key: key,
        policy: policy,
        timing: timing,
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
  /// no key, if [job] was created by another controller, or if
  /// [Policy.droppable] finds that key on a job of another result type.
  /// Every one of them throws before [job] is taken, so a job refused here
  /// is untouched and can be added again. After `close` the job finishes at
  /// once with `Cancelled(closed)`.
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
    // Looked up before the job is marked as added, and the answer reused
    // below: a key shared with a job of another result type is the
    // caller's mistake, and `add` must not bury the job it then refuses to
    // hand back. Nothing between here and the branch touches the queue. A
    // closed controller never reaches a policy and keeps its own answer.
    final duplicate = !isClosed && policy == Policy.droppable
        ? lastJobWhere((other) => other.key == impl.key)
        : null;
    if (duplicate != null && duplicate is! SoloJob<T>) {
      throw ArgumentError.value(
        job,
        'job',
        'key ${impl.key} belongs to a job of another result type',
      );
    }
    // Set before anything can go wrong below: a job dropped by a closed
    // controller has been added too, and one handle is one add.
    impl._added = true;
    if (isClosed) {
      _debug(() => 'add $impl: closed');
      impl._drop(
        Cancelled.by(
          reason: const ClosedCancelReason(),
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
        if (duplicate != null) {
          _debug(() => 'add $impl: duplicate of $duplicate');
          impl._drop(
            Cancelled.by(
              reason: const ManualCancelReason(),
              started: false,
              description: 'duplicate',
              stackTrace: StackTrace.current,
            ),
          );
          // The type was checked before the job was marked as added.
          return duplicate as SoloJob<T>;
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
    if (isClosed) {
      // A policy above removes jobs, and removing one finishes it: its
      // `onFinish` is a hook of a domain, and a hook may close the
      // controller. The check at the top of this method is stale by then,
      // and a job inserted into a drained queue would wait for a pump that
      // never comes.
      _debug(() => 'add $impl: closed while the policy was applied');
      impl._drop(
        Cancelled.by(
          reason: const ClosedCancelReason(),
          started: false,
          stackTrace: _closeStackTrace,
        ),
      );
      return impl;
    }
    // A removed job's synchronous cancellation listener may cancel the
    // incoming job. It must not occupy a queue slot or match a later policy.
    if (impl.isFinished) return impl;
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
  /// needs a key without one, and another from [Policy.droppable] when one
  /// key is shared by jobs with different result types.
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
    S Function(S state, Object error, StackTrace stackTrace)? onError,
    S Function(S state, Cancelled cancelled)? onCancel,
  }) =>
      add(
        job<W, T>(
          body,
          key: key,
          canStart: canStart,
          keepWhile: keepWhile,
          cancellable: cancellable,
          describe: describe,
          onError: onError,
          onCancel: onCancel,
        ),
        policy: policy,
      );

  /// The queue, for subclasses that manage it directly.
  @protected
  SoloQueue get queue => _queue;

  /// What is holding the controller right now, or `null` when no job is
  /// running.
  ///
  /// For a `close` that has not come back, or a `cancel` that is taking
  /// its time: it names the job, says what it is doing and whether
  /// anybody has asked it to stop.
  ///
  /// ```dart
  /// unawaited(controller.close().timeout(
  ///   const Duration(seconds: 5),
  ///   onTimeout: () => log('closing is held by ${controller.pending}'),
  /// ));
  /// ```
  ///
  /// It reports and does not diagnose. A job that holds on for reasons of
  /// its own — a bare `await` on a slow call, an external operation the
  /// body is inside — shows up as [SoloPhase.unknown], because that is
  /// what the engine knows about it.
  SoloPending? get pending => _current?._pending(closing: isClosed);

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

  /// Reflects state already changed by an external source, such as a
  /// device or socket. Re-evaluates the rules of running bodies and the
  /// permission of finishing jobs to apply their state handlers.
  /// Use the state handlers of [run] or [job] for an operation's own
  /// failure or cancellation.
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

  /// Closes the controller, then calls the observer's `onClose`. Repeated
  /// calls return the same future. The state is left as is.
  ///
  /// [SoloCloseMode.cancel], the default, drops every queued job with
  /// `Cancelled(closed)` and cancels the current one — a
  /// `cancellable: false` job is waited for instead.
  /// [SoloCloseMode.drain] leaves the queue alone and closes once it has
  /// run: new root jobs are refused from the call onwards, and the ones
  /// already accepted go by the usual rules, children, cleanup and
  /// accumulation windows included.
  ///
  /// A plain `close()` over a running drain stops it where it is: the
  /// queue is dropped and the current job cancelled, and the same future
  /// everybody is holding completes after that. There is no way back the
  /// other way — a drain cannot be started over a `close` that is already
  /// cancelling.
  ///
  /// Awaiting the returned future from inside the current job's body never
  /// completes: it waits for that very body.
  @mustCallSuper
  Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) {
    final closing = _closing;
    if (closing != null) {
      if (_draining && mode == SoloCloseMode.cancel) {
        _debug(() => 'close: the drain gives way');
        _draining = false;
        _stopWork(closing, _closeStackTrace!);
      }
      return closing.future;
    }
    final completer = _closing = Completer<void>();
    // Kept for `add` after close: section 5.1 points every `closed` outcome
    // at the `close` call, whichever of the two sources made it.
    final stackTrace = _closeStackTrace = StackTrace.current;
    switch (mode) {
      case SoloCloseMode.cancel:
        _debug(() => 'close');
        _stopWork(completer, stackTrace);
      case SoloCloseMode.drain:
        _debug(() => 'close: draining');
        _draining = true;
        // Even with nothing running: an idle controller closes from the
        // pump like any other, on a microtask, so `onClose` never arrives
        // from inside `close`.
        _schedulePump();
    }
    return completer.future;
  }

  /// Drops the queue, cancels the current job and finishes [completer]
  /// once it is over: what [SoloCloseMode.cancel] means.
  void _stopWork(Completer<void> completer, StackTrace stackTrace) {
    for (final timer in _timers.toList()) {
      timer.cancel();
    }
    _timers.clear();
    for (final job in _queue._drain()) {
      job._drop(
        Cancelled.by(
          reason: const ClosedCancelReason(),
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
          reason: const ClosedCancelReason(),
          started: true,
          stackTrace: stackTrace,
        ),
      );
      // `whenDone`, not `done`: closing waits for the job, it does not
      // observe its outcome, so a failure here still reaches the zone.
      current._whenDone.then((_) => _finishClose(completer));
    }
  }

  void _finishClose(Completer<void> completer) {
    // A drain that was stopped by a plain `close` has two routes to here:
    // the pump it left behind and the job the stop was waiting for.
    if (completer.isCompleted) {
      return;
    }
    _draining = false;
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
  /// **What the default body does.** With no [errorHandler] set and this
  /// hook not overridden, the error goes to the zone the job was created
  /// in — the same thing the core does when a job has no observer at all.
  /// With a handler set it goes there instead, and nowhere else. Setting
  /// an [observer] changes neither: watching is not answering. A
  /// [Cancelled] is the one exception and never goes to the zone: a
  /// cancellation is a decision somebody made, not a failure, and the core
  /// keeps one out of the zone whatever route leads there. The body's own
  /// failure does not go there from here either — it reaches the zone
  /// through its unobserved outcome instead, and one error is announced
  /// once.
  ///
  /// **Overriding replaces that**, so an override that says nothing keeps
  /// the error out of the zone; call `super.onError(job, error,
  /// stackTrace)` to keep the default route as well.
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    final homeless = _homeless;
    // Only an error with nowhere else to go. A cancellation is not weeded
    // out here: the core holds one back at its own door, and the rule is
    // written in one place.
    if (homeless == null || !identical(homeless, job)) {
      return;
    }
    final handler = errorHandler;
    if (handler == null) {
      homeless._reportToZone(error, stackTrace);
    } else {
      // Already inside `_callHook`, so a handler that throws reaches the
      // zone without a wrapper of its own.
      handler(this, job, error, stackTrace);
    }
  }

  /// A job called [JobContext.log].
  void onLog(Job<Object?> job, Object? message) {}

  /// The state changed, from a job or from [externalSetState].
  ///
  /// [SoloTransition.job] says whose change it was — a job of this
  /// controller, a child of one, or nobody for an external change — and
  /// [SoloTransition.revision] puts two of them in order.
  void onChange(SoloTransition<S> transition) {}

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
    final revision = ++_stateRevision;
    _lastChange = stackTrace;
    _debug(() => 'state: $next');
    _unpublished.add((previous, next));
    // Record lost correction rights before observers can synchronously
    // replace this external state with a compatible one again.
    final ruleErrors = <_SoloJob<S, S, Object?>>{};
    for (final job in _running.reversed.toList()) {
      if (identical(job, emitter)) continue;
      if (job._checkCorrectionState(next)) ruleErrors.add(job);
    }
    final transition = SoloTransition<S>(
      previous: previous,
      current: next,
      job: emitter,
      revision: revision,
    );
    _callHook(() => observer?.onChange(this, transition));
    _callHook(() => onChange(transition));
    _publishPending();
    _reevaluate(
      except: emitter,
      stackTrace: stackTrace,
      ruleErrors: ruleErrors,
      revision: revision,
    );
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
    required Set<_SoloJob<S, S, Object?>> ruleErrors,
    required int revision,
  }) {
    for (final job in _running.reversed.toList()) {
      if (identical(job, except)) continue;
      // After the body, rules protect only state correction. Cancellation
      // itself still follows the original body lifetime.
      final canCancel = !job.isCancelled && !job._bodyEnded;
      if (!canCancel && (!job._hasStateHandlers || !job._mayCorrectState)) {
        continue;
      }
      final String? rejection;
      try {
        // Observers may change a predicate's captured data without
        // replacing S. Always ask again after delivering the transition.
        rejection = job._rejectKeep(_state);
      } on Object catch (error, stackTrace) {
        if (job._hasStateHandlers) job._stateCorrectionRevoked = true;
        final alreadyReported =
            revision == _stateRevision && ruleErrors.contains(job);
        if (!alreadyReported) job._notifyError(error, stackTrace);
        continue;
      }
      if (rejection != null) {
        job._stateCorrectionRevoked = true;
        if (!canCancel) continue;
        // A rule of the job's own: it may not refuse this one.
        job._cancelWith(
          Cancelled.by(
            reason: const RulesCancelReason(),
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

  Timer _startTimer(Duration duration, void Function(Timer timer) callback) {
    late final Timer timer;
    timer = Timer(duration, () {
      _timers.remove(timer);
      callback(timer);
    });
    _timers.add(timer);
    return timer;
  }

  void _cancelTimer(Timer timer) {
    timer.cancel();
    _timers.remove(timer);
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
    if (_current != null || (isClosed && !_draining)) {
      return;
    }
    while (true) {
      final job = _queue._takeFirst();
      if (job == null) {
        // Not the same as an empty queue: a group waiting for its window
        // stays in it, and its timer brings the pump back. A drain that
        // ended here would cut off the very case it exists for.
        if (_draining && _queue._jobs.isEmpty) {
          _finishClose(_closing!);

          return;
        }
        _debug(() => 'queue has no ready jobs');

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
            reason: const RulesCancelReason(),
            started: false,
            description: rejection,
            stackTrace: StackTrace.current,
          ),
        );
        continue;
      }
      if (isClosed && !_draining) {
        // The rules are the caller's code, and one of them closed the
        // controller while it was being asked. Nothing starts after that
        // — unless the closing is a drain, whose whole point is to start
        // what is already in the queue.
        _debug(() => 'start $job: closed while the rules were asked');
        job._drop(
          Cancelled.by(
            reason: const ClosedCancelReason(),
            started: false,
            stackTrace: _closeStackTrace,
          ),
        );
        continue;
      }
      if (job.isFinished) {
        // The rules are the caller's code, and one of them gave this job
        // up while answering: `cancel()` on a job that has not started
        // finishes it where it stands. Launching it now would throw
        // `has already finished` from the kernel and leave the pump
        // holding a finished `_current` — the queue would never move again.
        _debug(() => 'start $job: given up while the rules were asked');
        continue;
      }
      _current = job;
      job._launch();
      return;
    }
  }

  static void _debug(String Function() message) {
    final debug = SoloBase.debug;
    if (debug == null) {
      return;
    }
    // Isolated like the channel of the kernel: building the message is the
    // caller's code as well, and a diagnostic that throws must not leave a
    // lifecycle half-done. `close` fills `_closing` before it logs, so a
    // throw from there would hang the controller for good.
    try {
      debug(message());
    } on Object catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
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
  void onLog(Job<Object?> job, Object? message) {
    SoloBase._callHook(() => SoloBase.observer?.onLog(_solo, job, message));
    SoloBase._callHook(() => _solo.onLog(job, message));
  }
}
