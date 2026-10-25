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

/// What a controller says of a job it did not make, the fix included: the
/// types let a job of the core or of another controller through. A job it
/// did make, run by a parent of the core, is refused in `adoptedBy`.
const _notCreatedHere =
    'was not created by this Solo (make it with job(...) of this controller)';

/// The engine: state, queue, hooks and its own listeners ([addListener]).
///
/// [publish] is the seam for a delivery of another kind; `SoloStream` adds a
/// broadcast stream through it.
///
/// A controller's operations are methods of its own, such as `load()`, built
/// from [enqueue], or from [job] and [enqueueJob], and from [collect] and
/// [accumulate] where several events share one job. The five are protected: a
/// caller sees the operations, not how they are queued.
///
/// The hooks — [onStart], [onFinish], [onError], [onUnanswered], [onLog],
/// [onChange], [onClose] and the [observer]'s — are a cross-cutting channel, so
/// an error thrown by one goes to the current zone and changes nothing else:
/// the job's outcome, the queue and [close] carry on as if the hook had
/// returned. [publish] is not one of them: it is how a subclass delivers the
/// state, and an error there is the subclass's own business.
///
/// [onUnanswered] is the one hook with a body of its own: what reaches it and
/// has nowhere else to go goes on to [unansweredHandler], or to the zone when
/// none is set. If it throws, the error it was asked about goes to the zone
/// first.
///
/// See [Reference](https://github.com/vi-k/solo/blob/main/packages/solo/doc/reference.md#solo)
/// for every member and the section that explains it.
abstract class Solo<S extends Object> {
  /// A global observer for all controllers; `null` by default.
  ///
  /// Watching only. Setting one changes nothing about where an error then
  /// goes; [unansweredHandler] is what takes that over.
  static SoloObserver? observer;

  /// Where an error with nowhere else to go goes instead of the zone;
  /// `null` by default.
  ///
  /// The errors [onError] describes — a disposer, an `onCancel` callback, a
  /// late failure of an abandoned call, the failure of the body of a job that
  /// ends [Cancelled], a rule that threw — have no outcome of their own to
  /// carry them anywhere, and a [Failed] nobody observes has nobody to read
  /// it. With nobody set here they reach the zone the job was created in; with
  /// a handler set they go to it instead, for every controller of the process,
  /// and what it does with one is the end of it.
  ///
  /// One global handler, set once at startup, the way [observer] is. It is
  /// separate from the observer on purpose: answering for an error is a
  /// responsibility somebody takes, not a side effect of switching a log
  /// on. A handler that throws does not take the error with it: the error
  /// goes to the zone the job was created in, and then what the handler
  /// threw goes to the current zone. A [Cancelled] it throws stays out, and
  /// so does the error itself thrown back: the error goes there alone.
  ///
  /// ```dart
  /// Solo.unansweredHandler = (solo, job, error, stackTrace) =>
  ///     Sentry.captureException(error, stackTrace: stackTrace);
  /// ```
  ///
  /// The handler gets one failure at a time: each failure inside a
  /// `ParallelWaitError` that `[a, b].wait` throws comes in a call of its own,
  /// with its own stack trace. An uncaught [Cancelled], alone or inside one,
  /// does not come. Nor does a failure of a cancelled job that
  /// [Job.isCancellationError] names: the app names there, once, the errors an
  /// operation throws because a cancellation stopped it.
  static SoloUnansweredHandler? unansweredHandler;

  /// Engine tracing for debugging the engine itself; `null` by default.
  ///
  /// The queue, the state and the closing report here. The life of each job,
  /// its start, its errors, a cancellation that reaches it and its outcome, is
  /// on [Job.debug]; to follow both sides, set both.
  ///
  /// A job in a line here is printed the way it prints itself: a key or a
  /// `describe` that throws shows as a mark, `Job(<key threw StateError>)`,
  /// and the error goes no further. [Job.debug] hands such an error to the
  /// zone as well.
  ///
  /// A job queued while another one runs gets a tail on its line, `enqueue
  /// Job(inner) while Job(outer) is running: it starts after Job(outer) ends`.
  /// For a job queued from outside that is only when it starts. A running job
  /// that awaits a job it queued on its own controller, from its body, a child
  /// or its cleanup, waits for good, and this is the line that shows it.
  ///
  /// A droppable duplicate gets a tail too, since [enqueueJob] hands back the
  /// job it duplicates. A duplicate of a queued job gets the tail of the job
  /// it duplicates, and a duplicate of the running job gets `enqueue Job(x):
  /// duplicate of Job(x), which is running: if awaited from inside Job(x), it
  /// waits for itself`. Who called is not known here, so a duplicate enqueued
  /// from outside, by a second tap on a button, gets the tail as well, and a
  /// wait for the job there is no trap.
  ///
  /// See [Steps in a row](https://github.com/vi-k/solo/blob/main/packages/solo/doc/children.md#steps-in-a-row)
  /// on the children page for both traps.
  static void Function(String message)? debug;

  S _state;
  int _stateRevision = 0;
  Completer<void>? _closing;
  StackTrace? _closeStackTrace;
  var _draining = false;
  late final _queue = _SoloQueue<S>(this);
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
  bool _pumpScheduled = false;

  /// The changes waiting to be published, oldest first.
  ///
  /// A queue rather than a list: publishing takes them from the head, and
  /// a list moves everything behind the head down on every one.
  final _unpublished = Queue<(S, S)>();
  bool _publishing = false;

  /// How many `keepWhile` calls are answering right now: a write of the
  /// state from inside one is refused.
  int _askingKeepWhile = 0;

  /// Why a job a [Policy.droppable] call may hand back refuses `then`.
  static const _handedBack =
      'is handed back to every call of its key under Policy.droppable';

  static const Object _closedListeners = Object();
  Object? _listeners;

  bool get _finished => identical(_listeners, _closedListeners);

  /// Creates a controller in [initialState].
  Solo(S initialState) : _state = initialState {
    _callHook(() => observer?.onCreate(this));
  }

  /// Calls [hook] the way every hook is called: see [callHook].
  static void _callHook(void Function() hook) => callHook(hook);

  /// The current state, for a reader outside a job.
  ///
  /// Reading is always safe; only jobs write. Not named `state` on purpose: a
  /// body reads through [SoloContext.state], a checkpoint, and this name makes
  /// the wrong one impossible to write by habit.
  ///
  /// See [Why `currentState` and not `state`](https://github.com/vi-k/solo/blob/main/packages/solo/README.md#why-currentstate-and-not-state)
  /// in the package README.
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
  /// identical — matching by identity would leave the listener registered
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
  /// subclass or mixin adds a delivery of its own through.
  ///
  /// Called after `onChange` and before running jobs are re-evaluated.
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
  /// first. A [Cancelled] the hook throws stays out of the zone, as with
  /// every other hook, and the listener's failure reaches it alone.
  void _reportListenerError(Object error, StackTrace stackTrace) {
    try {
      onListenerError(error, stackTrace);
    } on Object catch (hookError, hookStackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
      reportHookError(hookError, hookStackTrace);
    }
  }

  /// Creates a job without queueing it, for [enqueueJob] or for
  /// [JobContext.run].
  ///
  /// Queued, the job starts in the zone this method is called in, where an
  /// unread failure of it goes as well, and not in the zone of [enqueueJob].
  /// Throws [ArgumentError] when [timeout] is zero or negative, or comes with
  /// `cancellable: false`: the deadline is a cancellation, and such a job would
  /// refuse it.
  ///
  /// `cancellable: false` turns down `cancel`, `clear` without `force`, parent
  /// cancellation and, once the job runs, `close` — not a state that stops
  /// matching `W` or `keepWhile`. The flag counts only once the engine holds
  /// the job: one made here that nobody has enqueued is cancelled like any
  /// other. A queued job that turned down `cancel` starts in its turn and runs
  /// to its end, and `await job.cancel()` comes back only then.
  ///
  /// [ifFailed] and [ifCancelled] compute the state after a failed or cancelled
  /// body, once its children and cleanup are over, and change nothing about the
  /// outcome. [timeout] counts from the start of the body and lands as a
  /// cancellation, not as a `TimeoutException`.
  ///
  /// See [Parameters of a job](https://github.com/vi-k/solo/blob/main/packages/solo/doc/reference.md#parameters-of-a-job)
  /// on the reference page, which leads to the section of each parameter.
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
  /// and duplicates; the list is copied once when the group is sealed. The
  /// handler receives a regular context and runs under the same rules as [job].
  /// It changes state only when it runs, never when an event is added. [policy]
  /// chooses the waiting group and its position, and [timing] when a group is
  /// ready.
  ///
  /// [timeout] is a deadline for each job the accumulator queues, counted from
  /// the start of the handler, after the window of [timing]. The jobs are made
  /// lazily, by [SoloAccumulator.add], so the cancellation a deadline makes
  /// carries the trace of the `add` that made the job, and not of this call.
  ///
  /// Throws [ArgumentError] when the accumulator is created, not on its
  /// first event, if [timeout] is zero or negative, or comes with
  /// `cancellable: false`. A `late final` field creates it on its first
  /// read, which is the first `add` when nothing reads it before.
  ///
  /// [ifFailed] and [ifCancelled] are the state handlers of [job], and they
  /// write for the group: each job the accumulator queues calls one of them
  /// at most once, however many events it holds.
  ///
  /// See [Accumulation rules](https://github.com/vi-k/solo/blob/main/packages/solo/doc/accumulation-rules.md)
  /// for grouping, timing, start and closing.
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
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    S Function(S state, Cancelled cancelled)? ifCancelled,
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
        ifFailed: ifFailed,
        ifCancelled: ifCancelled,
      );

  /// Creates an accumulator holding one value, combined synchronously by
  /// [merge] on each addition after the first.
  ///
  /// Nullable events are supported. [merge] must be pure: do not mutate either
  /// argument, the controller or its queue. Errors escape from
  /// [SoloAccumulator.add] without changing the previous value. A recursive
  /// add from merge throws [StateError]. Only the latest merged value is
  /// retained; no event history is stored. The handler, rules, key, policy and
  /// state handlers follow [collect]. No job is created until the first event,
  /// and no state changes before the handler runs. [timing] has the same group
  /// readiness behavior as it does for [collect].
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
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    S Function(S state, Cancelled cancelled)? ifCancelled,
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
        ifFailed: ifFailed,
        ifCancelled: ifCancelled,
      );

  /// Queues [job] and returns it, or the existing job found by
  /// [Policy.droppable].
  ///
  /// A job [Policy.droppable] may hand back to another caller refuses a
  /// plain `then`: every caller continues it through `shared()`.
  ///
  /// [first] puts the job at the head of the queue instead of the tail, past
  /// what is waiting and not past the running job. A replacement queued by
  /// [Policy.restart] waits at the tail like any other, so a job enqueued
  /// `first` after it starts ahead of it.
  ///
  /// [Policy.replace] and [Policy.restart] queue [job] before they cancel the
  /// jobs it replaces, whose `onFinish` and cancellation listeners run inside
  /// this call: a job they queue under the key replaces [job] in turn. A hook
  /// that does so on every cancellation, a replacement too, runs out of stack;
  /// such a hook leaves a [ReplacedCancelReason] alone.
  ///
  /// Throws [StateError] if [job] was already enqueued or run, and
  /// [ArgumentError] if [policy] is not [Policy.sequential] and the job has no
  /// key, if [job] was created by another controller, or if [Policy.droppable]
  /// finds that key on a job of another result type. Every [ArgumentError] here
  /// is thrown before [job] is taken, so the job can be enqueued again.
  ///
  /// After `close` the job finishes at once with `Cancelled(closed)`, and a key
  /// held by another result type is not looked for at all — except by
  /// [Policy.droppable] during a [SoloCloseMode.drain], which hands back a job
  /// with the key that the drain still runs, as before the close.
  ///
  /// See [Queue and policies](https://github.com/vi-k/solo/blob/main/packages/solo/doc/jobs.md#queue-and-policies)
  /// on the jobs page.
  @protected
  SoloJob<T> enqueueJob<T>(
    Job<T> job, {
    bool first = false,
    Policy policy = Policy.sequential,
  }) {
    final impl = _own(job);
    if (policy != Policy.sequential && impl.key == null) {
      throw ArgumentError('Policy.${policy.name} requires a job key');
    }
    if (impl._taken ||
        impl._jobStatus != JobStatus.created ||
        _queue._jobs.contains(impl)) {
      throw StateError('$impl has already been enqueued or run');
    }
    // Looked up before the job is marked as enqueued, and the answer reused
    // below: a key shared with a job of another result type is the caller's
    // mistake, and `enqueueJob` must not bury the job it then refuses to hand
    // back. Nothing between here and the branch touches the queue. A closed
    // controller takes no new work, but a `drain` still runs what it had: a
    // duplicate found there is handed back as before the close, since its work
    // is going to be done, and only new work gets the closed answer.
    final duplicate = (!isClosed || _draining) && policy == Policy.droppable
        ? _lastJobWhere((other) => other.key == impl.key)
        : null;
    // The two jobs are compared with each other, not with `T`: the type
    // argument of this call is whatever the call site wrote down, and a
    // `SoloJob<void>` accepts any job at all — `void` is a top type, so
    // `is SoloJob<void>` is true of a `Job<String>` and the caller would
    // get somebody else's job back while its own work never ran.
    if (duplicate != null && duplicate._resultType != impl._resultType) {
      throw ArgumentError.value(
        '$job',
        'job',
        'key ${impl.key} is held by a job of result type '
            '${duplicate._resultType}, not ${impl._resultType}',
      );
    }
    // Set before anything can go wrong below: a job dropped by a closed
    // controller has been enqueued too, and one handle is one enqueue.
    impl._taken = true;
    // Any job of this call may be handed to the next caller of the key, so
    // every one of them refuses a plain `then` from the start, the first
    // caller's included: otherwise whether a caller throws would depend on
    // who came first.
    if (policy == Policy.droppable) impl._requireShared(_handedBack);
    if (isClosed && duplicate == null) {
      _debug(() => 'enqueue $impl: closed');
      impl._drop(
        Cancelled.by(
          reason: const ClosedCancelReason(),
          started: false,
          stackTrace: _closeStackTrace,
        ),
      );
      return impl;
    }
    // Found by [Policy.droppable] only.
    if (duplicate != null) {
      // A job of another policy is marked here, when it first has a second
      // caller, and before any code of the caller runs below; a `then` its
      // own caller took before stays.
      duplicate._requireShared(_handedBack);
      _debug(() {
        final name = '$duplicate';
        final line = 'enqueue $impl: duplicate of $name';
        final current = _current;
        // A droppable method called from inside the running job -- its
        // body, a child of it, its cleanup -- hands back that very job,
        // and a wait for it there is a wait for itself. A duplicate of a
        // queued job hands back that one, which starts only after the
        // running job ends, like any job queued from inside it. Who
        // called is not known here, so the line says what holds for any
        // caller.
        if (current == null) {
          return line;
        }
        if (identical(duplicate, current)) {
          return '$line, which is running: if awaited from inside $name, '
              'it waits for itself';
        }
        final running = '$current';
        return '$line, which is queued while $running is running: '
            'it starts after $running ends';
      });
      impl._drop(
        Cancelled.by(
          reason: const DuplicateCancelReason(),
          started: false,
          stackTrace: StackTrace.current,
        ),
      );
      // The type was checked before the job was marked as enqueued.
      return duplicate as SoloJob<T>;
    }
    // Queued before the others are cancelled, not after: cancelling one
    // runs its `onFinish` and its cancellation listeners synchronously, and
    // that code may queue a job of its own under the same key. Inserted
    // first, this job is the one such a call finds and replaces; inserted
    // afterwards, it would land behind that call and replace it instead,
    // and the job queued last would not be the one to run last.
    _queue._insert(impl, first: first);
    _debug(() {
      final line = 'enqueue $impl${first ? ' first' : ''}';
      final current = _current;
      // A method of the controller called from a running job -- its body,
      // a child of it, its cleanup -- queues a root job, and a job that
      // awaits it waits for good. Who called is not known here, so the line
      // says what holds for any caller.
      if (current == null) {
        return line;
      }
      final name = '$current';
      return '$line while $name is running: it starts after $name ends';
    });
    if (policy == Policy.replace || policy == Policy.restart) {
      // What the cancelled jobs' code does to this one is the queue's usual
      // business from here: a cancellation removes it, a `close` drops it
      // with the rest.
      _queue.removeWhere(
        (other) => other.key == impl.key && !identical(other, impl),
        reason: const ReplacedCancelReason(),
      );
      // Unless that code took [job] out again: the running job is cancelled
      // for a job that is going to run, not for one that already ended.
      final current = _current;
      if (policy == Policy.restart &&
          !impl.isFinished &&
          current != null &&
          current.key == impl.key) {
        unawaited(current.cancel(reason: const ReplacedCancelReason()));
        // The line above it says the new job waits for the running one,
        // and from it alone a refused restart reads as `sequential`.
        _debug(() => 'restart: ${current._restartAnswer}');
      }
    }
    _schedulePump();
    return impl;
  }

  /// `enqueueJob(job(...), policy: policy)` in one call: how a method of a
  /// controller builds its job and queues it.
  ///
  /// Every parameter but [policy] belongs to [job], which documents them all;
  /// [policy] belongs to [enqueueJob]. Returns the queued job; on a closed
  /// controller it gives back one already finished with `Cancelled(closed)`
  /// rather than throwing — except that a [Policy.droppable] call during a
  /// [SoloCloseMode.drain] gets back the draining job that holds its key, as
  /// from [enqueueJob]. It does throw what [enqueueJob] throws for a job it
  /// cannot take: [ArgumentError] for a policy that needs a key without one,
  /// and another from [Policy.droppable] when one key is shared by jobs with
  /// different result types. And it throws what [job] throws, before anything
  /// is queued.
  ///
  /// ```dart
  /// Job<String> load() => enqueue<Profile, String>(
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
  ///
  /// See [Creating and scheduling jobs](https://github.com/vi-k/solo/blob/main/packages/solo/doc/jobs.md#creating-and-scheduling-jobs)
  /// and [Queue and policies](https://github.com/vi-k/solo/blob/main/packages/solo/doc/jobs.md#queue-and-policies)
  /// on the jobs page.
  @protected
  SoloJob<T> enqueue<W extends S, T>(
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
      enqueueJob(
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
  /// Not `null` while a job runs, whether or not anybody has asked it to
  /// stop: a running job is a [SoloPendingJob], which names the job, says
  /// what it is doing and whether it has been asked to stop. A drain with
  /// no job running is a [SoloPendingQueue]: the queue it has still to run,
  /// where a group of `collect` or `accumulate` stays until its timing
  /// lets it go. With `SoloStream`, once the engine has closed, a
  /// subscription left paused holds the stream, and that is a
  /// [SoloPendingStream]. Read it for a `close` that has not come back, or
  /// a `cancel` that is taking its time.
  ///
  /// ```dart
  /// unawaited(controller.close().timeout(
  ///   const Duration(seconds: 5),
  ///   onTimeout: () => log('closing is held by ${controller.pending}'),
  /// ));
  /// ```
  ///
  /// A close that is finishing reads `null` from `onFinish` of its last job and
  /// from [onClose], though the returned future has not completed yet, and an
  /// idle controller reads `null` right after `close()`. The last
  /// subscription's `onDone` still reads [SoloPendingStream]. A subclass whose
  /// `close` waits for something of its own before or after `super.close`
  /// holds it where the controller does not see: domain cleanup belongs in
  /// [onClose].
  ///
  /// See [What is holding the controller](https://github.com/vi-k/solo/blob/main/packages/solo/doc/diagnostics.md#what-is-holding-the-controller)
  /// on the diagnostics page.
  SoloPending? get pending {
    final current = _current;
    if (current != null) {
      return current._pending(
        closing: isClosed,
        draining: _draining,
        // A copy, not a view, as below.
        queued: List<Job<Object?>>.unmodifiable(_queue._jobs),
      );
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
  SoloJob<Object?>? get current => _current;

  /// The last queued job matching [test], else the current job if it
  /// matches, else `null`.
  ///
  /// A job whose start rules are being asked counts as queued, ahead of the
  /// rest: it is off the queue and not started yet, and a rule of it may ask.
  ///
  /// Only a job that is still going to do the work answers. A queued one
  /// always is — cancelling it takes it off the queue — but the current
  /// job stays in [current] for the whole of its unwinding and for the
  /// state handlers after that, and in there it will never do anything
  /// again. `cancelAll()` and a fresh request a line later are two
  /// ordinary calls of one frame, and the second must not be answered
  /// with the job the first one has just stopped.
  @protected
  SoloJob<Object?>? lastJobWhere(bool Function(SoloJob<Object?> job) test) =>
      _lastJobWhere(test);

  _SoloJob<S, S, Object?>? _lastJobWhere(
    bool Function(SoloJob<Object?> job) test,
  ) {
    // A snapshot for the same reason as in `removeWhere`: the predicate is
    // the caller's code, and it may touch the queue while it answers. It
    // may even cancel the job it is about to accept, so a job is asked
    // after the answer, too, whether it is still going to do the work.
    for (final job in _queue._jobs.reversed.toList()) {
      if (test(job) && _goingOn(job)) {
        return job;
      }
    }
    // The job whose start rules are being asked: off the queue, not
    // started, and ahead of everything in the queue. Asked before the
    // predicate as well as after, as the current job is: `cancelAll` from
    // its rules ends it where it stands.
    final transition = _inTransition;
    if (transition != null &&
        _goingOn(transition) &&
        test(transition) &&
        _goingOn(transition)) {
      return transition;
    }
    final current = _current;
    return current != null &&
            _goingOn(current) &&
            test(current) &&
            _goingOn(current)
        ? current
        : null;
  }

  /// Whether [job] is still going to do its work: neither cancelled nor
  /// finished.
  static bool _goingOn(Job<Object?> job) => !job.isCancelled && !job.isFinished;

  /// Reflects state already changed by an external source, such as a device or
  /// socket.
  ///
  /// Re-evaluates the rules of running bodies and the permission of finishing
  /// jobs to apply their state handlers. Use the state handlers of [enqueue] or
  /// [job] for an operation's own failure or cancellation.
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
    _setState(state, emitter: null);
  }

  /// Closes the controller, then calls the observer's `onClose` and
  /// [onClose].
  ///
  /// Repeated calls return the same future. Once closing finishes, the state
  /// is final and cannot change.
  ///
  /// [SoloCloseMode.cancel], the default, drops every queued job with
  /// `Cancelled(closed)` and cancels the current one — a `cancellable: false`
  /// job is waited for instead. [SoloCloseMode.drain] leaves the queue alone
  /// and closes once it has run: new root jobs are refused from the call
  /// onwards, and the ones already accepted go by the usual rules, children,
  /// cleanup and accumulation windows included. A [Policy.droppable] call whose
  /// key a draining job holds gets that job back, as before the close: it is
  /// not new work.
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
    // Kept for `enqueueJob` after close: every `Cancelled(closed)` points its
    // stack trace at the `close` call, whether `close` cancelled the job or
    // `enqueueJob` refused it after the close.
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
    final transition = _inTransition;
    if (transition != null && !transition.isFinished) {
      // Held by the pump, which is about to launch it: closing takes this
      // one the way it takes the queue, without asking, and ahead of it,
      // as the queue's own removals do.
      transition._drop(
        Cancelled.by(
          reason: const ClosedCancelReason(),
          started: false,
          stackTrace: stackTrace,
        ),
      );
    }
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
          stackTrace: stackTrace,
        ),
      );
      // `untilFinished`, not `done`: closing waits for the job, it does not
      // observe its outcome, so a failure here is still answered for.
      current._untilFinished.then((_) => _finishClose(completer));
    }
  }

  void _finishClose(Completer<void> completer) {
    // A drain that was stopped by a plain `close` has two routes to here:
    // the pump it left behind and the job the stop was waiting for.
    if (completer.isCompleted) {
      return;
    }
    // Both ways of closing end here, and a drain arrives with its timers still
    // running: `_stopWork` takes them down at the call, the pump does not. An
    // interval timer that outlives the controller holds its accumulator and the
    // accumulator holds this -- in a widget test that is "A Timer is still
    // pending even after the widget tree was disposed" for somebody who only
    // closed a controller.
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
  /// queue.
  ///
  /// Completes when the current job has actually finished.
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
    // The queue's removals reach the job the pump holds between the queue
    // and the start, and a call from inside its rules is exactly when that
    // happens.
    _queue.clear(force: force, reason: reason);
    final current = _current;
    return current == null
        ? Future<void>.value()
        : current.cancel(reason: reason);
  }

  /// A job body is about to run.
  @protected
  void onStart(Job<Object?> job) {}

  /// A job has an outcome, including jobs dropped before start.
  @protected
  void onFinish(Job<Object?> job) {}

  /// Something a job did threw, whether its outcome carries the error or not.
  ///
  /// The body; an action abandoned by [JobContext.abandonable] failing later; a
  /// disposer or an `onCancel` callback; work handed over with
  /// [JobContext.unattended]; and a rule of this controller — `canStart` or
  /// `keepWhile` — that threw instead of answering. A failure of the body comes
  /// here even when it is the job's [Failed] and the caller reads it there.
  ///
  /// Called once for every such error, to be seen: this hook reports and
  /// nothing else, and overriding it changes nowhere the error goes. One error
  /// at a time: each failure and each cancellation inside a `ParallelWaitError`
  /// comes in a call of its own, with its own stack trace. [onUnanswered] is
  /// the hook that answers, for the errors nothing else holds. The job's own
  /// cancellation is not an error and never comes here; a [Cancelled] thrown by
  /// an abandoned action does, because for an observer that is a late failure
  /// like any other. See [Failed] for the errors that also reach the zone.
  @protected
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}

  /// Nobody answered for this error, and this controller is the last one
  /// holding it.
  ///
  /// The default body hands the error to [unansweredHandler], or, with none
  /// set, to the zone the job was created in; setting an [observer] changes
  /// neither: watching is not answering. Override it to answer here instead: an
  /// override that says nothing keeps the error out of the handler and the
  /// zone, `super.onUnanswered(job, error, stackTrace)` keeps the default route
  /// as well, and one that throws does not take the error with it.
  ///
  /// What comes here: a [Failed] nobody observes, a microtask after the job
  /// ends — `enqueue(ifFailed: ...)` is no observing — and the errors an
  /// outcome cannot carry, which the errors page lists. A [Cancelled], alone
  /// or inside a `ParallelWaitError`, never comes, and a [Failed] made of a
  /// cancellation goes to the zone past this hook. [Job.ignoreFailure] and
  /// [Job.isCancellationError] keep some of them away.
  ///
  /// See [Answering for an error](https://github.com/vi-k/solo/blob/main/packages/solo/doc/errors.md#answering-for-an-error)
  /// and [Where each error goes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/errors.md#where-each-error-goes)
  /// on the errors page.
  @protected
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    final handler = unansweredHandler;
    if (handler == null) {
      // Every job that reaches this hook is one of this controller's.
      (job as _SoloJob)._reportToZone(error, stackTrace);
    } else {
      // A handler that throws is caught by the core, which sends the error
      // to the zone and then what the handler threw.
      handler(this, job, error, stackTrace);
    }
  }

  /// A job called [JobContext.log].
  @protected
  void onLog(Job<Object?> job, Object? message) {}

  /// The state changed, from a job or from [externalSetState].
  ///
  /// [SoloTransition.job] says whose change it was — a job of this
  /// controller, a child of one, or nobody for an external change — and
  /// [SoloTransition.revision] puts two of them in order.
  @protected
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
  @protected
  void onClose() {}

  _SoloJob<S, S, T> _own<T>(Job<T> job) {
    if (job is _SoloJob<S, S, T> && identical(job._solo, this)) {
      return job;
    }
    throw ArgumentError.value('$job', 'job', _notCreatedHere);
  }

  void _setState(S next, {required _SoloJob<S, S, Object?>? emitter}) {
    // A change asks every running job's `keepWhile` again, and a rule that
    // writes the state while it answers asks itself again: one that writes
    // every time it is asked never comes back. Refused at the first write,
    // as an accumulator refuses an `add` from inside its `merge`.
    if (_askingKeepWhile > 0) {
      throw StateError(
        'Cannot set the state of $runtimeType while a keepWhile is '
        'answering; a rule answers about the state, it does not change it',
      );
    }
    // Every write comes through here, and none can arrive once closing has
    // finished: `externalSetState` throws before the call, and a job that
    // could still emit is a job `close` is waiting for. Asserted rather
    // than checked, so a path that ever lets a write through shows up as
    // the defect it is instead of moving a state that is final.
    assert(!_finished, 'the state of a closed controller is final');
    final previous = _state;
    _state = next;
    final revision = ++_stateRevision;
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
    // The rules are asked even when a delivery throws: the state has
    // changed either way, and a job the new state rejects is owed its
    // cancellation whatever a `publish` did with the news. The failure
    // still goes back to whoever wrote the state. Should the rules fail
    // after it -- a cancellation that cascades through a tree deeper than
    // the stack -- theirs is the second failure and goes where the second
    // failure of a delivery goes.
    Object? failure;
    StackTrace? failureTrace;
    try {
      _publishPending();
    } on Object catch (error, stackTrace) {
      failure = error;
      failureTrace = stackTrace;
    }
    try {
      _reevaluate(
        except: emitter,
        ruleErrors: ruleErrors,
        revision: revision,
      );
    } on Object catch (error, stackTrace) {
      if (failure == null) rethrow;
      Zone.current.handleUncaughtError(error, stackTrace);
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureTrace!);
    }
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
        // Observers may change a predicate's captured data without replacing S.
        // Always ask again after delivering the transition.
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
            // Still inside the change: the trace leads back to whoever made it.
            stackTrace: StackTrace.current,
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
      // Off the queue, not started, and not yet `_current`: while the rules are
      // asked — the caller's code — this job belongs to nobody, and only
      // `_inTransition` can hand it to a `cancelAll` or a `close` made from in
      // there.
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

  // [answer] goes no further: neither [Solo.onError] nor [SoloObserver]
  // takes it.
  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {
    Solo._callHook(
      () => Solo.observer?.onError(_solo, job, error, stackTrace),
    );
    Solo._callHook(() => _solo.onError(job, error, stackTrace));
  }

  /// The controller answers for its jobs: [Solo.onUnanswered], and the
  /// [Solo.unansweredHandler] behind it. [Solo.observer] is not asked —
  /// watching every controller is not answering for any of them.
  ///
  /// Not called through [Solo._callHook]: what the answer throws goes back
  /// to the core, which sends the error it was asked about to the zone
  /// first and then what it threw, as `onListenerError` does here.
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _solo.onUnanswered(job, error, stackTrace);

  @override
  void onLog(Job<Object?> job, Object? message) {
    Solo._callHook(() => Solo.observer?.onLog(_solo, job, message));
    Solo._callHook(() => _solo.onLog(job, message));
  }
}
