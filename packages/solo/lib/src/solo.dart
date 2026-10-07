import 'dart:async';
import 'dart:collection';

import 'package:async_job/engine.dart';
import 'package:meta/meta.dart';

import 'call_hook.dart';
import 'close_mode.dart';
import 'listeners.dart';
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

/// The engine: state, queue, hooks and its own listeners ([addListener]).
/// [publish] is the seam for a delivery of another kind; `SoloStream`
/// adds a broadcast stream through it.
///
/// A controller's operations are methods of its own, such as `load()`,
/// built from [run], or from [job] and [add], and from [collect] and
/// [accumulate] where several events share one job. The five are
/// protected: a caller sees the operations, not how they are queued.
///
/// The hooks — [onStart], [onFinish], [onError], [onUnanswered], [onLog],
/// [onChange], [onClose] and the [observer]'s — are a cross-cutting
/// channel, so an error thrown by one goes to the current zone and changes
/// nothing else: the job's outcome, the queue and [close] carry on as if
/// the hook had returned. [onUnanswered] is the one with a body of its own:
/// what reaches it and has nowhere else to go — a disposer, an `onCancel`
/// callback, a late failure of an abandoned call or of work handed to
/// `JobContext.unattended`, a rule that threw — goes on to [errorHandler],
/// or to the zone when none is set. [publish] is not one of them: it is how
/// a subclass delivers the state, and an error there is the subclass's own
/// business.
abstract class Solo<S extends Object> {
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
  /// Solo.errorHandler = (solo, job, error, stackTrace) => Job.visitErrors(
  ///       error,
  ///       stackTrace,
  ///       onFailure: (failure, failureStackTrace) => Sentry.captureException(
  ///         failure,
  ///         stackTrace: failureStackTrace,
  ///       ),
  ///     );
  /// ```
  ///
  /// The handler gets each error as it came, cancellations included: a
  /// [Cancelled], and a `ParallelWaitError` that `[a, b].wait` throws with
  /// several errors in it. [Job.visitErrors] hands `onFailure` each failure
  /// inside a `ParallelWaitError` on its own and drops each uncaught
  /// [Cancelled], alone or inside one.
  static SoloErrorHandler? errorHandler;

  /// Engine tracing for debugging the engine itself; `null` by default.
  ///
  /// The queue, the state and the closing report here. The life of each job,
  /// its start, its errors, a cancellation that reaches it and its outcome, is
  /// on [Job.debug]; to follow both sides, set both.
  static void Function(String message)? debug;

  /// Whether a change of state records where it was made.
  ///
  /// The record is the stack trace of a job its rules cancel: the `emit`
  /// or `externalSetState` whose state they turned down. Taking it costs
  /// most of what a change costs, so by default it is taken only where
  /// assertions are on — in development and in tests — and not in a
  /// release or profile build. Set it to `true` to have it there too, or to
  /// `false` to go without it everywhere.
  ///
  /// Without the record a cancellation by the rules still has a trace:
  /// the one of the place that noticed. When a change is what cancels a
  /// running job, that place is inside the change itself, and the trace
  /// leads back to it through a few frames of the engine; a job that finds
  /// its rules broken at a checkpoint of its own gets the checkpoint.
  static bool traceStateChanges = _assertionsOn();

  static bool _assertionsOn() {
    var on = false;
    assert(on = true, 'only evaluated where assertions are on');
    return on;
  }

  S _state;
  int _stateRevision = 0;
  Completer<void>? _closing;
  StackTrace? _closeStackTrace;
  var _draining = false;
  final _queue = _SoloQueue<S>();
  final _timers = <Timer>{};

  /// The observer every job of this controller is given.
  late final JobObserver _jobObserver = _SoloJobObserver<S>(this);

  _SoloJob<S, S, Object?>? _current;

  /// The job the pump holds while it asks its start rules: taken off the
  /// queue, not started, not yet [_current].
  ///
  /// The rules are the caller's code and may cancel everything or close
  /// the controller, and in that window neither the queue nor [_current]
  /// leads to this job. It is queued work until it is launched, and this
  /// is what says so.
  _SoloJob<S, S, Object?>? _inTransition;
  final _running = <_SoloJob<S, S, Object?>>[];
  StackTrace? _lastChange;
  bool _pumpScheduled = false;

  /// The changes waiting to be published, oldest first.
  ///
  /// A queue rather than a list: publishing takes them from the head, and
  /// a list moves everything behind the head down on every one.
  final _unpublished = Queue<(S, S)>();
  bool _publishing = false;
  static const Object _closedListeners = Object();
  Object? _listeners;

  bool get _finished => identical(_listeners, _closedListeners);

  /// Creates a controller in [initialState].
  Solo(S initialState) : _state = initialState {
    _callHook(() => observer?.onCreate(this));
  }

  /// Calls [hook] the way every hook is called: see [callHook].
  static void _callHook(void Function() hook) => callHook(hook);

  /// The current state, for a reader outside a job. Reading is always
  /// safe; only jobs write.
  ///
  /// Not named `state` on purpose. A job body is a closure inside a method
  /// of the controller, so every member of the controller is in scope
  /// there, and a bare `state` would compile and read the state without a
  /// checkpoint — past a cancellation the body was supposed to honour. A
  /// body reads through [SoloContext.state] instead, and this name makes
  /// the wrong one impossible to write by habit.
  S get currentState => _state;

  /// Whether [close] was called.
  bool get isClosed => _closing != null;

  /// Whether [close] was called with [SoloCloseMode.drain] and the queue
  /// it is running has not emptied yet.
  ///
  /// New root jobs are refused the whole time — [isClosed] is true from
  /// the call — while the engine goes on with the ones it already had.
  bool get isDraining => _draining;

  /// Whether the engine has finished closing: the queue is empty, the
  /// observer's `onClose` and [onClose] have run, the listeners are gone,
  /// and the state can no longer change.
  ///
  /// [isClosed] says that `close` was asked for, [isDraining] that the
  /// queue it left is still running; this says the engine is done. A
  /// subclass that feeds external facts guards [externalSetState] with it,
  /// and a `drain` goes on being fed for as long as it runs. Check it after
  /// the last `await`: a suspension between the check and the write lets
  /// the line arrive in between.
  bool get isFinished => _finished;

  /// Whether at least one listener is registered on this controller.
  @protected
  bool get hasListeners {
    final listeners = _listeners;
    return listeners is Listeners && !listeners.isEmpty;
  }

  /// Registers [listener] to be called synchronously when the state changes.
  ///
  /// If the controller has finished closing, this is a no-op: the listener
  /// is neither registered nor retained, and no error is thrown.
  void addListener(void Function() listener) {
    if (_finished) {
      return;
    }
    final existing = _listeners;
    final Listeners listeners;
    if (existing is Listeners) {
      listeners = existing;
    } else {
      listeners = Listeners();
      _listeners = listeners;
    }
    listeners.add(listener);
  }

  /// Removes the earliest active registration equal to [listener].
  ///
  /// Registrations are matched with `==`, not identity, because a widget
  /// subscribes and unsubscribes with a method of its own: `addListener` in
  /// `initState`, `removeListener` in `dispose`. Naming the method twice
  /// tears it off twice, and the two function values are equal without being
  /// identical -- matching by identity would leave the listener registered
  /// for good. `ChangeNotifier` matches the same way.
  ///
  /// If the listener was not registered or was already removed, this is a
  /// no-op.
  void removeListener(void Function() listener) {
    final listeners = _listeners;
    if (listeners is Listeners) {
      listeners.remove(listener);
    }
  }

  /// Called when a listener throws during notification.
  ///
  /// By default forwards the error to [Zone.handleUncaughtError].
  /// Subclasses may override this to integrate with framework error
  /// reporting (such as Flutter error reporting). A mixin applied above a
  /// base class overrides it in turn: `SoloListenable` of `flutter_solo`,
  /// mixed into a leaf, reports through Flutter whatever the leaf's base
  /// class says here.
  @protected
  void onListenerError(Object error, StackTrace stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }

  /// Notifies the engine's own listeners, then stands as the seam a
  /// subclass or mixin adds a delivery of its own through. Called after
  /// `onChange` and before running jobs are re-evaluated.
  @protected
  @mustCallSuper
  void publish(S previous, S current) {
    final listeners = _listeners;
    if (listeners is Listeners) {
      listeners.notify(_reportListenerError);
    }
  }

  /// Hands a listener's failure to [onListenerError], isolated.
  ///
  /// A hook that throws instead of reporting does not take with it the
  /// failure it was called about: both errors reach the zone, the
  /// listener's first. The hook is the channel here, not the fact, and a
  /// broken channel is a second problem rather than a reason to lose the
  /// first.
  void _reportListenerError(Object error, StackTrace stackTrace) {
    try {
      onListenerError(error, stackTrace);
    } on Object catch (hookError, hookStackTrace) {
      Zone.current
        ..handleUncaughtError(error, stackTrace)
        ..handleUncaughtError(hookError, hookStackTrace);
    }
  }

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
  /// [ifFailed] and [ifCancelled] synchronously map the current state to the
  /// state after a failed or cancelled body. They run after children and
  /// resource cleanup, with the outcome fixed, before [Solo.onFinish]
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
  /// and should only compute the next state: the value they return is
  /// their write. A write made from inside one — [externalSetState], or a
  /// source that calls it synchronously — does not combine with that
  /// value: if the job's rules accept it, the handler's result lands on
  /// top of it, computed from the state before it; if they refuse it,
  /// the handler's result is dropped. Cleanup belongs in
  /// [JobContext.onDispose] or [JobContext.onDiscard]. [ifCancelled] runs at
  /// completion; the signal to the operation being stopped belongs in
  /// [JobContext.onCancel], which delivers it immediately.
  ///
  /// [timeout] gives the job a deadline counted from the start of its body,
  /// not from [add]: the time in the queue is not counted. What it bounds
  /// and how it lands are what [Job.new] says of its own `timeout`. The
  /// deadline is a cancellation, not an error: [ifCancelled] receives a
  /// `Cancelled(timeout)` whose reason is a [TimeoutCancelReason], [ifFailed]
  /// is not called, and [Job.value] throws that [Cancelled], which
  /// `on TimeoutException` does not catch. A handler that rolls back a
  /// cancellation and reports an error tells the two apart by the reason:
  ///
  /// ```dart
  /// ifCancelled: (state, cancelled) => cancelled.reason is TimeoutCancelReason
  ///     ? const Failure('timed out')
  ///     : const Initial(),
  /// ```
  ///
  /// The queue is not cleared after a deadline: the next job starts once
  /// this one has cleaned up, as after any cancellation.
  ///
  /// Throws [ArgumentError] when [timeout] is zero or negative, or comes
  /// with `cancellable: false`: the deadline is a cancellation the job may
  /// refuse, and such a job would refuse it.
  @protected
  SoloJob<T> job<W extends S, T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) =>
      _SoloJob<S, W, T>(
        this,
        body,
        key: key,
        canStart: canStart,
        keepWhile: keepWhile,
        cancellable: cancellable,
        timeout: timeout,
        describe: describe,
        observer: _jobObserver,
        ifFailed: ifFailed,
        ifCancelled: ifCancelled,
      );

  /// Creates an accumulator that collects events into an immutable list.
  ///
  /// No job is created until [SoloAccumulator.add]. Events retain their order
  /// and duplicates; the list is copied once when the group is sealed.
  /// The handler receives a regular context and runs under the same rules as
  /// [job]. It changes state only when it runs, never when an event is added.
  /// [policy] chooses the waiting group and its position; the default joins
  /// the last open group of this accumulator wherever it stands, so a job of
  /// another kind queued between two events is not a boundary. Take
  /// [AccumulationPolicy.adjacent] where it has to be one. [key] is an
  /// ordinary job key and does not make different accumulators compatible.
  /// [timing]
  /// can debounce each group or throttle starts across this accumulator;
  /// ready jobs later in the queue can bypass a group waiting for its window.
  ///
  /// [timeout] is a deadline for each job the accumulator queues, not for
  /// the accumulator, and it lands as the `timeout` of [job] does. It is
  /// counted from the start of the handler, after the window of [timing]:
  /// the window is time in the queue. The jobs are made lazily, by
  /// [SoloAccumulator.add], so the cancellation a deadline makes carries the
  /// trace of the `add` that made the job — the event the group came about
  /// for — and not of this call.
  ///
  /// Throws [ArgumentError] when the accumulator is created, not on its
  /// first event, if [timeout] is zero or negative, or comes with
  /// `cancellable: false`. A `late final` field creates it on its first
  /// read, which is the first `add` when nothing reads it before.
  @protected
  SoloAccumulator<E, T> collect<W extends S, E, T>(
    Future<T> Function(SoloContext<S, W> ctx, List<E> events) handler, {
    Object? key,
    AccumulationPolicy policy = AccumulationPolicy.join,
    AccumulationTiming? timing,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
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
        timeout: timeout,
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
  ///
  /// [timeout] is a deadline for each job, as for [collect]: counted from
  /// the start of the handler, after the window of [timing], and the
  /// cancellation it makes carries the trace of the [SoloAccumulator.add]
  /// that made the job. Throws [ArgumentError] when the accumulator is
  /// created, as [collect] does.
  @protected
  SoloAccumulator<E, T> accumulate<W extends S, E, T>(
    Future<T> Function(SoloContext<S, W> ctx, E value) handler, {
    required E Function(E accumulated, E incoming) merge,
    Object? key,
    AccumulationPolicy policy = AccumulationPolicy.join,
    AccumulationTiming? timing,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
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
        timeout: timeout,
        describe: describe,
      );

  /// Queues [job] and returns it, or the existing job found by
  /// [Policy.droppable].
  ///
  /// [first] puts the job at the head of the queue instead of the tail. It
  /// passes what is waiting and nothing else: the running job is not the
  /// queue's to touch, so this one starts when that job finishes. A
  /// replacement queued by [Policy.restart] waits at the tail like any
  /// other, so a job added `first` after it starts ahead of it — cancelling
  /// the running job does not reserve the slot after it.
  ///
  /// Throws [StateError] if [job] was already added or run, and
  /// [ArgumentError] if [policy] is not [Policy.sequential] and the job has
  /// no key, if [job] was created by another controller, or if
  /// [Policy.droppable] finds that key on a job of another result type.
  /// Every [ArgumentError] here is thrown before [job] is taken, so a job
  /// refused for one of those reasons is untouched and can be added again;
  /// the [StateError] is about a handle that has been taken once already.
  /// After `close` the job finishes at once with `Cancelled(closed)`, and a
  /// key held by another result type is not looked for at all.
  @protected
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
        ? _lastJobWhere((other) => other.key == impl.key)
        : null;
    // The two jobs are compared with each other, not with `T`: the type
    // argument of this call is whatever the call site wrote down, and a
    // `SoloJob<void>` accepts any job at all — `void` is a top type, so
    // `is SoloJob<void>` is true of a `Job<String>` and the caller would
    // get somebody else's job back while its own work never ran.
    if (duplicate != null && duplicate._resultType != impl._resultType) {
      throw ArgumentError.value(
        job,
        'job',
        'key ${impl.key} is held by a job of result type '
            '${duplicate._resultType}, not ${impl._resultType}',
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
              reason: const DuplicateCancelReason(),
              started: false,
              stackTrace: StackTrace.current,
            ),
          );
          // The type was checked before the job was marked as added.
          return duplicate as SoloJob<T>;
        }
      case Policy.replace:
        _queue.removeWhere(
          (other) => other.key == impl.key,
          reason: const ReplacedCancelReason(),
        );
      case Policy.restart:
        _queue.removeWhere(
          (other) => other.key == impl.key,
          reason: const ReplacedCancelReason(),
        );
        final current = _current;
        if (current != null && current.key == impl.key) {
          unawaited(current.cancel(reason: const ReplacedCancelReason()));
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
  /// key is shared by jobs with different result types. And it throws what
  /// [job] throws, before anything is queued: [ArgumentError] for a
  /// [timeout] that is zero or negative or comes with `cancellable: false`.
  ///
  /// A [timeout] that runs out reaches [ifCancelled], not [ifFailed]: the
  /// deadline is a cancellation with a [TimeoutCancelReason], counted from
  /// the start of the body and not from this call. To show it as a failure,
  /// branch on the reason:
  ///
  /// ```dart
  /// ifCancelled: (state, cancelled) => cancelled.reason is TimeoutCancelReason
  ///     ? const Failure('timed out')
  ///     : const Initial(),
  /// ```
  ///
  /// ```dart
  /// Job<String> load() => run<Profile, String>(
  ///       key: 'load',
  ///       policy: Policy.droppable,
  ///       (ctx) async {
  ///         final name = await ctx.abandonable(api.fetchName);
  ///         ctx.emit(Profile(name: name));
  ///
  ///         return name;
  ///       },
  ///     );
  /// ```
  @protected
  SoloJob<T> run<W extends S, T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    Policy policy = Policy.sequential,
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) =>
      add(
        job<W, T>(
          body,
          key: key,
          canStart: canStart,
          keepWhile: keepWhile,
          cancellable: cancellable,
          timeout: timeout,
          describe: describe,
          ifFailed: ifFailed,
          ifCancelled: ifCancelled,
        ),
        policy: policy,
      );

  /// The queue, for subclasses that manage it directly.
  @protected
  SoloQueue get queue => _queue;

  /// What is holding the controller right now, or `null` when nothing the
  /// controller knows of is.
  ///
  /// For a `close` that has not come back, or a `cancel` that is taking
  /// its time. A running job is a [SoloPendingJob]: it names the job, says
  /// what it is doing and whether anybody has asked it to stop. A drain
  /// with no job running is a [SoloPendingQueue]: the queue it has still
  /// to run, where a group of `collect` or `accumulate` stays until its
  /// timing lets it go. With `SoloStream`, once the engine has closed, a
  /// subscription left paused holds the stream, and that is a
  /// [SoloPendingStream].
  ///
  /// ```dart
  /// unawaited(controller.close().timeout(
  ///   const Duration(seconds: 5),
  ///   onTimeout: () => log('closing is held by ${controller.pending}'),
  /// ));
  /// ```
  ///
  /// A timer reads it between the steps of a close; a synchronous hook
  /// reads it in the middle of one. A close that is finishing reads `null`
  /// from `onFinish` of its last job and from [onClose], though the
  /// returned future has not completed yet, and an idle controller reads
  /// `null` right after `close()`. The last subscription's `onDone` still
  /// reads [SoloPendingStream]. A subclass whose `close` waits for
  /// something of its own before or after `super.close` holds it where
  /// the controller does not see: domain cleanup belongs in [onClose].
  ///
  /// It reports and does not diagnose. A body that holds on for reasons of
  /// its own — a bare `await` on a slow call, an external operation it is
  /// inside — shows up as [SoloPhase.body]: the engine knows the body has
  /// not come back, and not what it waits for.
  SoloPending? get pending {
    final current = _current;
    if (current != null) {
      return current._pending(closing: isClosed, draining: _draining);
    }
    if (_draining) {
      // A copy, not a view: the snapshot says what held the close when it
      // was taken. The job whose rules are being asked is queued work
      // until it is launched, and it goes first — unless a rule has
      // already ended it, which leaves it here until the pump lets go.
      final jobs = List<Job<Object?>>.unmodifiable([
        if (_inTransition case final job? when !job.isFinished) job,
        ..._queue._jobs,
      ]);
      if (jobs.isNotEmpty) {
        return SoloPendingQueue(jobs);
      }
    }
    return null;
  }

  /// The running root job, or `null` when idle.
  @protected
  Job<Object?>? get current => _current;

  /// The last queued job matching [test], else the current job if it
  /// matches, else `null`.
  ///
  /// Only a job that is still going to do the work answers. A queued one
  /// always is — cancelling it takes it off the queue — but the current
  /// job stays in [current] for the whole of its unwinding and for the
  /// state handlers after that, and in there it will never do anything
  /// again. `cancelAll()` and a fresh request a line later are two
  /// ordinary calls of one frame, and the second must not be answered
  /// with the job the first one has just stopped.
  @protected
  SoloJob<Object?>? lastJobWhere(bool Function(Job<Object?> job) test) =>
      _lastJobWhere(test);

  _SoloJob<S, S, Object?>? _lastJobWhere(
    bool Function(Job<Object?> job) test,
  ) {
    // A snapshot for the same reason as in `removeWhere`: the predicate is
    // the caller's code, and it may touch the queue while it answers.
    for (final job in _queue._jobs.reversed.toList()) {
      if (test(job)) {
        return job;
      }
    }
    final current = _current;
    return current != null &&
            !current.isCancelled &&
            !current.isFinished &&
            test(current)
        ? current
        : null;
  }

  /// Reflects state already changed by an external source, such as a
  /// device or socket. Re-evaluates the rules of running bodies and the
  /// permission of finishing jobs to apply their state handlers.
  /// Use the state handlers of [run] or [job] for an operation's own
  /// failure or cancellation.
  ///
  /// Accepted for as long as the engine is running, a [close] with
  /// [SoloCloseMode.drain] included. Once closing has finished the state is
  /// final, and this throws a [StateError]. A subclass that feeds external
  /// facts guards its source with [isFinished], checked after the last
  /// `await`: a suspension between the check and the write lets the engine
  /// finish in between.
  @protected
  void externalSetState(S state) {
    if (_finished) {
      throw StateError(
        '$runtimeType has finished closing, cannot set state',
      );
    }
    _debug(() => 'externalSetState: $state');
    _setState(
      state,
      emitter: null,
      stackTrace: traceStateChanges ? StackTrace.current : null,
    );
  }

  /// Closes the controller, then calls the observer's `onClose` and
  /// [onClose]. Repeated calls return the same future. Once closing
  /// finishes, the state is final and cannot change.
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
    _cancelTimers();
    for (final job in _queue._drain()) {
      job._drop(
        Cancelled.by(
          reason: const ClosedCancelReason(),
          started: false,
          stackTrace: stackTrace,
        ),
      );
    }
    final transition = _inTransition;
    if (transition != null && !transition.isFinished) {
      // Held by the pump, which is about to launch it: closing takes this
      // one the way it takes the queue, without asking.
      transition._drop(
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
    // Both ways of closing end here, and a drain arrives with its timers
    // still running: `_stopWork` takes them down at the call, the pump
    // does not. An interval timer that outlives the controller holds its
    // accumulator and the accumulator holds this -- in a widget test that
    // is "A Timer is still pending even after the widget tree was
    // disposed" for somebody who only closed a controller.
    _cancelTimers();
    _draining = false;
    _debug(() => 'closed');
    _callHook(() => observer?.onClose(this));
    _callHook(onClose);
    final listeners = _listeners;
    _listeners = _closedListeners;
    if (listeners is Listeners) {
      listeners.clear();
    }
    completer.complete();
  }

  /// Clears the queue and cancels the current job; `force` affects only the
  /// queue. Completes when the current job has actually finished.
  ///
  /// Every job it ends carries [reason], a [ManualCancelReason] unless the
  /// caller names one: a policy of the domain that clears the controller
  /// can tell its own cancellations from a user's.
  ///
  /// Awaiting the returned future from inside the current job's body never
  /// completes: it waits for that very body.
  Future<void> cancelAll({
    bool force = false,
    CancelReason reason = const ManualCancelReason(),
  }) {
    _queue.clear(force: force, reason: reason);
    // The pump may be holding one between the queue and the start, and a
    // call from inside its rules is exactly when that happens.
    _inTransition?._cancelWith(
      Cancelled.by(
        reason: reason,
        started: false,
        stackTrace: StackTrace.current,
      ),
      rejectable: !force,
    );
    final current = _current;
    return current == null
        ? Future<void>.value()
        : current.cancel(reason: reason);
  }

  /// A job body is about to run.
  void onStart(Job<Object?> job) {}

  /// A job has an outcome, including jobs dropped before start.
  void onFinish(Job<Object?> job) {}

  /// Something a job did threw where there was nowhere else to put it.
  ///
  /// The body; an action abandoned by [JobContext.abandonable] failing later; a
  /// disposer or an `onCancel` callback; and a rule of this controller —
  /// `canStart` or `keepWhile` — that threw instead of answering.
  ///
  /// Called once for every such error, to be seen: this hook reports and
  /// nothing else, and overriding it changes nowhere the error goes.
  /// [onUnanswered] is the hook that answers. The job's own cancellation
  /// is not an error and never comes here; a [Cancelled] thrown by an
  /// abandoned action does, because for an observer that is a late failure
  /// like any other. See [Failed] for the errors that also reach the zone.
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}

  /// Nobody answered for this error, and this controller is the last one
  /// holding it.
  ///
  /// The errors an outcome cannot carry: an action abandoned by
  /// [JobContext.abandonable] failing later, a disposer, an `onCancel`
  /// callback, work handed over with [JobContext.unattended], a `keepWhile`
  /// that threw anywhere but at a checkpoint of the body, the failure of a
  /// branch of [JobContext.runAll] that the group did not throw, and a failure
  /// of the body that a cancellation covered afterwards — the outcome carries
  /// the cancellation, whoever reads it: `job.value`, `ctx.run`, a group.
  /// [Job.ignoreFailure] keeps the last two from coming here. Any other failure
  /// of a body does not come here — it becomes a [Failed], where `run(ifFailed:
  /// ...)` computes a state from it and an outcome nobody observes reaches the
  /// zone by itself — and neither does a `canStart` that threw, for the same
  /// reason. Every error that comes here has been through [onError] already:
  /// one error is announced once.
  ///
  /// **What the default body does.** With no [errorHandler] set, the error
  /// goes to the zone the job was created in — the same thing the core does
  /// by default, with an observer or without one. With a handler set it
  /// goes there instead, and nowhere else. Setting an [observer] changes
  /// neither: watching is not answering. A [Cancelled] is the one exception
  /// and never goes to the zone: a cancellation is a decision somebody
  /// made, not a failure, and the core keeps one out of the zone whatever
  /// route leads there.
  ///
  /// **Override it to answer here instead** — a controller that owns what
  /// its jobs failed at reports to its own system and stops there. An
  /// override that says nothing keeps these errors out of the handler and
  /// out of the zone; call `super.onUnanswered(job, error, stackTrace)` to
  /// keep the default route as well.
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    final handler = errorHandler;
    if (handler == null) {
      // Every job that reaches this hook is one of this controller's.
      (job as _SoloJob)._reportToZone(error, stackTrace);
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

  /// The engine is about to finish closing.
  ///
  /// Called once, whatever mode closed the controller and however many
  /// times [close] was called, after the observer's `onClose`: every job
  /// is over by then, while [isFinished] is still false and a synchronous
  /// [externalSetState] still goes through. It is the place for what the
  /// controller holds beside its jobs — a subscription to a source it
  /// reflects, a resource of its domain:
  ///
  /// ```dart
  /// @override
  /// void onClose() => unawaited(_link.cancel());
  /// ```
  ///
  /// An override of [close] is the wrong place for the same line. It runs
  /// at the call, while a drain or a job that refuses the close still
  /// depends on the source, and it runs on every call, where this runs
  /// once. A future started here is not waited for: [close] completes
  /// without it.
  void onClose() {}

  _SoloJob<S, S, T> _own<T>(Job<T> job) {
    if (job is _SoloJob<S, S, T> && identical(job._solo, this)) {
      return job;
    }
    throw ArgumentError.value('$job', 'job', 'was not created by this Solo');
  }

  void _setState(
    S next, {
    required _SoloJob<S, S, Object?>? emitter,
    required StackTrace? stackTrace,
  }) {
    // Every write comes through here, and none can arrive once closing has
    // finished: `externalSetState` throws before the call, and a job that
    // could still emit is a job `close` is waiting for. Asserted rather
    // than checked, so a path that ever lets a write through shows up as
    // the defect it is instead of moving a state that is final.
    assert(!_finished, 'the state of a closed controller is final');
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
  ///
  /// A `publish` that throws does not take the rest of the queue with it.
  /// The change it failed on is gone either way -- it was taken off the
  /// queue before the call, and nothing publishes it a second time -- but
  /// the ones behind it are changes of their own, and `currentState`
  /// already holds what they say. Dropped here, they would never be
  /// published at all, by this call or by any later one. So the queue is
  /// drained to the end, the first failure leaves this method once it is,
  /// and the ones after it go where a failing hook's error goes.
  void _publishPending() {
    if (_publishing) {
      return;
    }
    _publishing = true;
    Object? failure;
    StackTrace? failureTrace;
    try {
      while (_unpublished.isNotEmpty) {
        final change = _unpublished.removeFirst();
        try {
          publish(change.$1, change.$2);
        } on Object catch (error, stackTrace) {
          if (failure == null) {
            failure = error;
            failureTrace = stackTrace;
          } else {
            Zone.current.handleUncaughtError(error, stackTrace);
          }
        }
      }
    } finally {
      _publishing = false;
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureTrace!);
    }
  }

  /// Re-evaluates the rules of every running job except [except] against
  /// the current state, children before parents.
  void _reevaluate({
    required _SoloJob<S, S, Object?>? except,
    required StackTrace? stackTrace,
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
            description: rejection,
            // Taken here when the change took none: this is still inside
            // the change, so the trace leads back to whoever made it.
            stackTrace: stackTrace ?? StackTrace.current,
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
    // A drain ends in the pump, so whatever empties the queue has to bring
    // the pump back. Finishing the current job is one way; taking the last
    // queued job off the queue is the other, and it woke nothing. A group
    // waiting for its window keeps `_current` empty and takes its timer
    // away with it when it goes, so a drain left with one of those and a
    // `cancelAll` had nothing left to finish it.
    if (wasCurrent || _draining) {
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

  void _cancelTimers() {
    for (final timer in _timers.toList()) {
      timer.cancel();
    }
    _timers.clear();
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
      // Off the queue, not started, and not yet `_current`: while the
      // rules are asked — the caller's code — this job belongs to nobody,
      // and only `_inTransition` can hand it to a `cancelAll` or a
      // `close` made from in there.
      _inTransition = job;
      try {
        final String? rejection;
        try {
          rejection = job._rejectStart(_state);
        } on Object catch (error, stackTrace) {
          // The rules are the caller's code, and this one threw. The job is
          // already out of the queue: left as it is, it would never finish,
          // and the pump would never come back for the ones behind it. The
          // core tells the observer of a failure handed in, and of one handed
          // to a job the rule has already ended — cancelled, or dropped by a
          // `close` made from inside it.
          _debug(() => 'rule of $job threw: $error');
          job._drop(Failed(error, stackTrace));
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
        if (job.isFinished) {
          // The rules are the caller's code, and one of them ended this
          // job while answering: `cancel()` on a job that has not started
          // finishes it where it stands, and a `cancelAll` or a `close`
          // from in there reaches it through `_inTransition`. Launching it
          // now would throw `has already finished` from the core and
          // leave the pump holding a finished `_current` — the queue would
          // never move again.
          _debug(() => 'start $job: ended while the rules were asked');
          continue;
        }
        _current = job;
        // The window closes here, not at the end of the launch: from now
        // on the job is the current one, and that is where a `cancelAll`
        // or a `close` from inside its body finds it.
        _inTransition = null;
        job._launch();
        return;
      } finally {
        _inTransition = null;
      }
    }
  }

  static void _debug(String Function() message) {
    final debug = Solo.debug;
    if (debug == null) {
      return;
    }
    // Isolated like the channel of the core: building the message is the
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
final class _SoloJobObserver<S extends Object>
    implements JobObserver, JobAnswerer {
  final Solo<S> _solo;

  _SoloJobObserver(this._solo);

  @override
  void onStart(Job<Object?> job) {
    Solo._callHook(() => Solo.observer?.onStart(_solo, job));
    Solo._callHook(() => _solo.onStart(job));
  }

  @override
  void onFinish(Job<Object?> job) {
    Solo._callHook(() => Solo.observer?.onFinish(_solo, job));
    Solo._callHook(() => _solo.onFinish(job));
  }

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    Solo._callHook(
      () => Solo.observer?.onError(_solo, job, error, stackTrace),
    );
    Solo._callHook(() => _solo.onError(job, error, stackTrace));
  }

  /// The controller answers for its jobs: [Solo.onUnanswered], and the
  /// [Solo.errorHandler] behind it. [Solo.observer] is not asked — watching
  /// every controller is not answering for any of them.
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    Solo._callHook(() => _solo.onUnanswered(job, error, stackTrace));
  }

  @override
  void onLog(Job<Object?> job, Object? message) {
    Solo._callHook(() => Solo.observer?.onLog(_solo, job, message));
    Solo._callHook(() => _solo.onLog(job, message));
  }
}
