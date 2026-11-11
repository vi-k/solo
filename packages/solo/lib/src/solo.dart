import 'dart:async';
import 'dart:collection';

import 'package:async_job/engine.dart';
import 'package:meta/meta.dart';

import 'call_hook.dart';
import 'change_listeners.dart';
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
part 'lane.dart';
part 'queue.dart';

/// What a controller says of a job it did not make, the fix included: the
/// types let a job of the core or of another controller through. A job it
/// did make, run by a parent of the core, is refused in `adoptedBy`.
const _notCreatedHere =
    'was not created by this Solo (make it with job(...) or ctx.child of this '
    'controller)';

/// The same for a [SoloLanes], which is not a Solo.
const _notCreatedHereLanes =
    'was not created by this controller (make it with job(...) or ctx.child '
    'of this controller)';

/// Where the errors of [SoloLanes.lane] send the reader.
const _declaringLanes =
    'https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#declaring-lanes';

/// What a lane says of a job another lane or another controller made, the
/// fix included.
const _notCreatedByLane =
    'was not created by this lane (make it with job(...) of this lane, or '
    'with ctx.child of a job running in it)';

/// Why a job a [Policy.droppable] call may hand back refuses `then`.
const _handedBack =
    'is handed back to every call of its key under Policy.droppable';

/// How the pump's step in one core ends, for the pass that walks them all.
enum _StepEnd {
  /// The pass goes on to the next core.
  goOn,

  /// The pass goes on, and this core is drained: a drain is on, nothing
  /// runs in it and its queue is empty.
  drained,

  /// A [SoloController.close] that cancels came in: the pass stops here.
  stop,
}

/// The base of a controller: state, closing, hooks and its own listeners:
/// [addListener], and [addChangeListener] for a listener that takes the two
/// states of a change.
///
/// [publish] is the seam for a delivery of another kind; `SoloStream` adds a
/// broadcast stream through it.
///
/// The hooks — [onStart], [onFinish], [onError], [onUnanswered], [onLog],
/// [onChange], [onClose] and the [Solo.observer]'s — are a cross-cutting
/// channel, so an error thrown by one goes to the current zone and changes
/// nothing else: the job's outcome, the queue and [close] carry on as if the
/// hook had returned. [publish] is not one of them: it is how a subclass
/// delivers the state, and an error there is the subclass's own business.
///
/// [onUnanswered] is the one hook with a body of its own: what reaches it and
/// has nowhere else to go goes on to [Solo.unansweredHandler], or to the zone
/// when none is set. If it throws, the error it was asked about goes to the
/// zone first.
///
/// A controller extends [Solo], which adds the queue, or [SoloLanes], which
/// adds lanes. The constructor of this class is private, so nothing outside
/// its library extends it; a fake still implements it.
///
/// See [Reference](https://github.com/vi-k/solo/blob/main/packages/solo/doc/reference.md#solocontroller)
/// for every member and the section that explains it.
abstract class SoloController<S extends Object> {
  S _state;
  int _stateRevision = 0;
  Completer<void>? _closing;
  StackTrace? _closeStackTrace;
  var _draining = false;
  final _timers = <Timer>{};

  /// The observer every job of this controller is given.
  late final JobObserver _jobObserver = _SoloJobObserver<S>(this);

  final _running = <_SoloJob<S, S, Object?>>[];

  /// The changes waiting to be published, oldest first.
  ///
  /// A queue rather than a list: publishing takes them from the head, and
  /// a list moves everything behind the head down on every one.
  final _unpublished = Queue<(S, S)>();
  bool _publishing = false;

  /// How many `keepWhile` calls are answering right now: a write of the
  /// state from inside one is refused.
  int _askingKeepWhile = 0;

  static const Object _closedListeners = Object();
  Object? _listeners;
  ChangeListeners<S>? _changeListeners;

  bool get _finished => identical(_listeners, _closedListeners);

  /// The cores of this controller in the order of creation, the order a
  /// pass of the pump walks them in: one for a [Solo].
  ///
  /// Read already from the observer's `onCreate`, which this constructor
  /// calls before the body of a subclass's: a core the subclass declares
  /// here is there for a job queued and closed from that hook.
  List<_SoloLaneCore<S>> get _cores;

  bool _pumpScheduled = false;

  /// What [pending] says for this kind of controller.
  SoloPending? get _pending;

  /// Creates a controller in [initialState].
  SoloController._(S initialState) : _state = initialState {
    _callHook(() => Solo.observer?.onCreate(this));
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
    final changeListeners = _changeListeners;
    return (listeners is Listeners && !listeners.isEmpty) ||
        (changeListeners != null && !changeListeners.isEmpty);
  }

  /// Registers [listener] to be called synchronously when the state changes.
  ///
  /// If the controller has finished closing, this is a no-op: the listener
  /// is neither registered nor retained, and no error is thrown.
  ///
  /// The listener is told that the state changed, not to what: reading
  /// [currentState] in it gives the latest state, and a change written by
  /// another listener of the same pass is already there. A listener that
  /// needs every change with the state before it subscribes with
  /// [addChangeListener].
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

  /// Registers [listener] to be called with the previous and the current
  /// state on every change.
  ///
  /// Every change arrives as its own pair, synchronously, in subscription
  /// order, after the [addListener] listeners of the same change. A write
  /// made by a listener during the pass arrives as the next pair, so
  /// `current` can be older than [currentState] by the time a listener reads
  /// it: the pair is the change being told, [currentState] is where the
  /// controller stands now. The same state written twice is two changes, and
  /// so is a return to the old one.
  ///
  /// [onChange] is the subclass's own hook and says which job made the
  /// change; this is for anyone who holds the controller and compares the two
  /// states, such as a screen that reacts to a change rather than to a value.
  ///
  /// A listener that throws goes to [onListenerError], and the others are
  /// still called. If the controller has finished closing, this is a no-op:
  /// the listener is neither registered nor retained, and no error is thrown.
  ///
  /// See [Observing state](https://github.com/vi-k/solo/blob/main/packages/solo/doc/state.md#observing-state)
  /// on the state page.
  void addChangeListener(void Function(S previous, S current) listener) {
    if (_finished) {
      return;
    }
    (_changeListeners ??= ChangeListeners<S>()).add(listener);
  }

  /// Removes the earliest active registration equal to [listener].
  ///
  /// Registrations are matched with `==`, not identity, for the reason
  /// [removeListener] gives. If the listener was not registered or was
  /// already removed, this is a no-op.
  void removeChangeListener(void Function(S previous, S current) listener) {
    _changeListeners?.remove(listener);
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

  /// Notifies the engine's own listeners — the [addListener] ones, then the
  /// [addChangeListener] ones with [previous] and [current] — then stands as
  /// the seam a subclass or mixin adds a delivery of its own through.
  ///
  /// Called after `onChange` and before running jobs are re-evaluated.
  @protected
  @mustCallSuper
  void publish(S previous, S current) {
    final listeners = _listeners;
    if (listeners is Listeners) {
      listeners.notify(_reportListenerError);
    }
    _changeListeners?.notify(previous, current, _reportListenerError);
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

  /// What is holding the controller right now, or `null` when nothing the
  /// controller knows of is.
  ///
  /// Not `null` while a job runs. In a [Solo] a running job is a
  /// [SoloPendingJob], which names the job, says what it is doing and whether
  /// it has been asked to stop; a drain with no job running is a
  /// [SoloPendingQueue]: the queue it has still to run, where a group of
  /// `collect` or `accumulate` stays until its timing lets it go. A
  /// [SoloLanes] gives a [SoloPendingLanes], one of those two for each busy
  /// lane. With `SoloStream`, once the engine has closed, a subscription left
  /// paused holds the stream, and that is a [SoloPendingStream]. Read it for
  /// a `close` that has not come back, or a `cancel` that is taking its time.
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
  SoloPending? get pending => _pending;

  /// What is holding [core] right now: its running job, or what a drain
  /// has still to run in it.
  SoloPending? _pendingOf(_SoloLaneCore<S> core) {
    final current = core.current;
    if (current != null) {
      return current._pending(
        closing: isClosed,
        draining: _draining,
        // A copy, not a view, as below.
        queued: List<Job<Object?>>.unmodifiable(core.queue._jobs),
      );
    }
    if (_draining) {
      // A copy, not a view: the snapshot says what held the close when it
      // was taken. The job whose rules are being asked is queued work
      // until it is launched, and it goes first — unless a rule has
      // already ended it, which leaves it here until the pump lets go.
      final jobs = List<Job<Object?>>.unmodifiable([
        if (core.inTransition case final job? when !job.isFinished) job,
        ...core.queue._jobs,
      ]);
      if (jobs.isNotEmpty) {
        return SoloPendingQueue(jobs);
      }
    }
    return null;
  }

  /// Reflects state already changed by an external source, such as a device or
  /// socket.
  ///
  /// Re-evaluates the rules of running bodies and the permission of finishing
  /// jobs to apply their state handlers. Use the state handlers of
  /// [Solo.enqueue] or [Solo.job] for an operation's own failure or
  /// cancellation.
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
      throw StateError('$runtimeType has finished closing, cannot set state');
    }
    _debug(() => 'externalSetState: $state');
    _setState(state, emitter: null);
  }

  /// {@template solo.SoloController.close}
  /// Closes the controller, then calls the observer's `onClose` and
  /// [onClose].
  ///
  /// Repeated calls return the same future. Once closing finishes, the state
  /// is final and cannot change.
  ///
  /// [SoloCloseMode.cancel], the default, drops every queued job with
  /// `Cancelled(closed)` and cancels the current job of every lane (the one
  /// job of a [Solo]) — a `cancellable: false` job is waited for instead.
  /// [SoloCloseMode.drain] leaves the queues alone and closes once every one
  /// has run: new root jobs are refused from the call onwards, and the ones
  /// already accepted go by the usual rules, children, cleanup and
  /// accumulation windows included. A [Policy.droppable] call whose key a
  /// draining job holds gets that job back, as before the close: it is not
  /// new work.
  ///
  /// A plain `close()` over a running drain stops it where it is: the
  /// queues are dropped and the current jobs cancelled, and the same future
  /// everybody is holding completes after that. There is no way back the
  /// other way — a drain cannot be started over a `close` that is already
  /// cancelling.
  ///
  /// Awaiting the returned future from inside the body of a current job never
  /// completes: it waits for that very body.
  /// {@endtemplate}
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

  /// Drops the queues, cancels the current jobs and finishes [completer]
  /// once they are over: what [SoloCloseMode.cancel] means.
  void _stopWork(Completer<void> completer, StackTrace stackTrace) {
    _cancelTimers();
    // Every core lets go of its queued work before any running job hears of
    // the close: a job cancelled first could write while the queue of
    // another core still waits.
    for (final core in _cores) {
      final transition = core.inTransition;
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
    }
    // Every queue is emptied before the first of its jobs is dropped: a
    // dropped job's finish handlers are the caller's code, and they find no
    // queue still full, whichever core they look at.
    final queued = [for (final core in _cores) ...core.queue._drain()];
    for (final job in queued) {
      job._drop(
        Cancelled.by(
          reason: const ClosedCancelReason(),
          started: false,
          stackTrace: stackTrace,
        ),
      );
    }
    final running = [for (final core in _cores) ?core.current];
    if (running.isEmpty) {
      // Nothing to wait for, but still finish on a microtask: `onClose`
      // never arrives from inside `close`, whether the engine was busy or
      // idle.
      scheduleMicrotask(() => _finishClose(completer));
      return;
    }
    // Every running job hears of the close before the wait for any of them
    // begins.
    for (final current in running) {
      // Rejectable on purpose: `close` waits for a job that refuses.
      current._cancelWith(
        Cancelled.by(
          reason: const ClosedCancelReason(),
          stackTrace: stackTrace,
        ),
      );
    }
    // The last of them to finish finishes the close, straight from its own
    // end and with no microtask of its own; `_finishClose` guards only its
    // completer, and the first to end would close under the others.
    var unfinished = running.length;
    for (final current in running) {
      // `untilFinished`, not `done`: closing waits for the job, it does not
      // observe its outcome, so a failure here is still answered for.
      current._untilFinished.then((_) {
        unfinished--;
        if (unfinished == 0) {
          _finishClose(completer);
        }
      });
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
    _callHook(() => Solo.observer?.onClose(this));
    _callHook(onClose);
    final listeners = _listeners;
    _listeners = _closedListeners;
    if (listeners is Listeners) {
      listeners.clear();
    }
    _changeListeners?.clear();
    _changeListeners = null;
    completer.complete();
  }

  /// {@template solo.SoloController.cancelAll}
  /// Clears every queue and cancels the current job of every lane (the one
  /// job of a [Solo]); `force` affects only the queues.
  ///
  /// Completes when every current job has actually finished.
  ///
  /// Every job it ends carries [reason], a [ManualCancelReason] unless the
  /// caller names one: a policy of the domain that clears the controller
  /// can tell its own cancellations from a user's.
  ///
  /// Awaiting the returned future from inside the body of a current job never
  /// completes: it waits for that very body.
  /// {@endtemplate}
  Future<void> cancelAll({
    bool force = false,
    CancelReason reason = const ManualCancelReason(),
  }) {
    // One snapshot of every queue before the first removal: a removal runs
    // the finish handlers of the job it ends, and a job one of them puts in
    // any core outlives this call, whatever the order of the cores. The
    // queue's removals reach the job the pump holds between the queue and
    // the start, and a call from inside its rules is exactly when that
    // happens.
    final queued = [
      for (final core in _cores) (core.queue, core.queue._snapshot),
    ];
    for (final (queue, jobs) in queued) {
      queue._clear(jobs, force: force, reason: reason);
    }
    // The running jobs are read once the queues are cleared, and before
    // any of them is cancelled.
    final running = [for (final core in _cores) ?core.current];
    return switch (running) {
      [] => Future<void>.value(),
      // As it is: one running job is waited for through its own `cancel`.
      [final current] => current.cancel(reason: reason),
      _ => Future.wait<void>([
        for (final current in running) current.cancel(reason: reason),
      ]),
    };
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
  ///
  /// [answer] says what the job does about this error, as in the core: with
  /// [JobErrorAnswer.answered], [onUnanswered] is asked about it unless
  /// [Job.ignoreFailure] is called before it is. Unlike the core, `solo` passes
  /// [JobErrorAnswer.never] for an error `isExpectedError` names. See
  /// [JobErrorAnswer].
  @protected
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {}

  /// Nobody answered for this error, and this controller is the last one
  /// holding it.
  ///
  /// The default body hands the error to [Solo.unansweredHandler], or, with
  /// none set, to the zone the job was created in; setting a [Solo.observer]
  /// changes
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
  /// [Job.isCancellationError] keep some of them away, and an error the job's
  /// `isExpectedError` names never comes.
  ///
  /// See [Answering for an error](https://github.com/vi-k/solo/blob/main/packages/solo/doc/errors.md#answering-for-an-error)
  /// and [Where each error goes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/errors.md#where-each-error-goes)
  /// on the errors page.
  @protected
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    final handler = Solo.unansweredHandler;
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
    _callHook(() => Solo.observer?.onChange(this, transition));
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
      _reevaluate(except: emitter, ruleErrors: ruleErrors, revision: revision);
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

  _SoloJob<S, S, T> _own<T>(Job<T> job) {
    if (job is _SoloJob<S, S, T> && identical(job._solo, this)) {
      return job;
    }
    throw ArgumentError.value(
      '$job',
      'job',
      this is Solo ? _notCreatedHere : _notCreatedHereLanes,
    );
  }

  /// Makes a job of this controller for [core]: the one place a job is
  /// built with the controller's observer.
  ///
  /// [Solo.job] comes here, and so do [SoloLane.job], a child made for a
  /// core of a controller other than a [Solo], and every group of an
  /// accumulator. The public defaults of `cancellable` live in [Solo.job]
  /// and [SoloLane.job]; this one only repeats them for the child.
  _SoloJob<S, W, T> _makeJob<W extends S, T>(
    _SoloLaneCore<S> core,
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    Duration? timeout,
    String Function()? describe,
    S Function(S state, Object error, StackTrace stackTrace)? ifFailed,
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) => _SoloJob<S, W, T>(
    core,
    body,
    key: key,
    canStart: canStart,
    keepWhile: keepWhile,
    cancellable: cancellable,
    timeout: timeout,
    describe: describe,
    observer: _jobObserver,
    ifFailed: ifFailed,
    isExpectedError: isExpectedError,
    ifCancelled: ifCancelled,
  );

  /// Creates an accumulator of a list of events whose groups go into
  /// [core]: [Solo.collect] and [SoloLane.collect].
  SoloAccumulator<E, T> _collectIn<W extends S, E, T>(
    _SoloLaneCore<S> core,
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
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) => _SoloAccumulator<S, W, E, List<E>, T>(
    core,
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
    isExpectedError: isExpectedError,
    ifCancelled: ifCancelled,
  );

  /// Creates an accumulator of one merged value whose groups go into
  /// [core]: [Solo.accumulate] and [SoloLane.accumulate].
  SoloAccumulator<E, T> _accumulateIn<W extends S, E, T>(
    _SoloLaneCore<S> core,
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
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) => _SoloAccumulator<S, W, E, E, T>(
    core,
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
    isExpectedError: isExpectedError,
    ifCancelled: ifCancelled,
  );

  /// Queues [impl] in [core]: [Solo.enqueueJob] and [SoloLane.enqueueJob]
  /// past their check of who made the job.
  SoloJob<T> _enqueueIn<T>(
    _SoloLaneCore<S> core,
    _SoloJob<S, S, T> impl, {
    required bool first,
    required Policy policy,
  }) {
    if (policy != Policy.sequential && impl.key == null) {
      throw ArgumentError('Policy.${policy.name} requires a job key');
    }
    final queue = core.queue;
    if (impl._taken ||
        impl._jobStatus != JobStatus.created ||
        queue._jobs.contains(impl)) {
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
        ? _lastJobWhereIn(core, (other) => other.key == impl.key)
        : null;
    // The two jobs are compared with each other, not with `T`: the type
    // argument of this call is whatever the call site wrote down, and a
    // `SoloJob<void>` accepts any job at all — `void` is a top type, so
    // `is SoloJob<void>` is true of a `Job<String>` and the caller would
    // get somebody else's job back while its own work never ran.
    if (duplicate != null && duplicate._resultType != impl._resultType) {
      throw ArgumentError.value(
        '$impl',
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
    // After the refusals and before any outcome: a job this call ends at
    // once comes to `onFinish` with the core it was queued in.
    impl._execution = core;
    if (isClosed && duplicate == null) {
      _debug(() => core.said('enqueue $impl: closed'));
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
        final current = core.current;
        // A droppable method called from inside the running job -- its
        // body, a child of it, its cleanup -- hands back that very job,
        // and a wait for it there is a wait for itself. A duplicate of a
        // queued job hands back that one, which starts only after the
        // running job ends, like any job queued from inside it. Who
        // called is not known here, so the line says what holds for any
        // caller.
        if (current == null) {
          return core.said(line);
        }
        if (identical(duplicate, current)) {
          return core.said(
            '$line, which is running: if awaited from inside $name, '
            'it waits for itself',
          );
        }
        final running = '$current';
        return core.said(
          '$line, which is queued while $running is running: '
          'it starts after $running ends',
        );
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
    queue._insert(impl, first: first);
    _debug(() {
      final line = 'enqueue $impl${first ? ' first' : ''}';
      final current = core.current;
      // A method of the controller called from a running job -- its body,
      // a child of it, its cleanup -- queues a root job, and a job that
      // awaits it waits for good. Who called is not known here, so the line
      // says what holds for any caller.
      if (current == null) {
        return core.said(line);
      }
      final name = '$current';
      return core.said(
        '$line while $name is running: it starts after $name ends',
      );
    });
    if (policy == Policy.keepLatest || policy == Policy.restart) {
      // What the cancelled jobs' code does to this one is the queue's usual
      // business from here: a cancellation removes it, a `close` drops it
      // with the rest.
      queue.removeWhere(
        (other) => other.key == impl.key && !identical(other, impl),
        reason: const ReplacedCancelReason(),
      );
      // Unless that code took [job] out again: the running job is cancelled
      // for a job that is going to run, not for one that already ended.
      final current = core.current;
      if (policy == Policy.restart &&
          !impl.isFinished &&
          current != null &&
          current.key == impl.key) {
        unawaited(current.cancel(reason: const ReplacedCancelReason()));
        // The line above it says the new job waits for the running one,
        // and from it alone a refused restart reads as `sequential`.
        _debug(() => core.said('restart: ${current._restartAnswer}'));
      }
    }
    _schedulePump();
    return impl;
  }

  /// The last job of [core] matching [test]: [Solo.lastJobWhere] and
  /// [SoloLane.lastJobWhere].
  _SoloJob<S, S, Object?>? _lastJobWhereIn(
    _SoloLaneCore<S> core,
    bool Function(SoloJob<Object?> job) test,
  ) {
    // A snapshot for the same reason as in `removeWhere`: the predicate is
    // the caller's code, and it may touch the queue while it answers. It
    // may even cancel the job it is about to accept, so a job is asked
    // after the answer, too, whether it is still going to do the work.
    for (final job in core.queue._jobs.reversed.toList()) {
      if (test(job) && _goingOn(job)) {
        return job;
      }
    }
    // The job whose start rules are being asked: off the queue, not
    // started, and ahead of everything in the queue. Asked before the
    // predicate as well as after, as the current job is: `cancelAll` from
    // its rules ends it where it stands.
    final transition = core.inTransition;
    if (transition != null &&
        _goingOn(transition) &&
        test(transition) &&
        _goingOn(transition)) {
      return transition;
    }
    final current = core.current;
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

  void _onJobFinished(_SoloJob<S, S, Object?> job) {
    var wasCurrent = false;
    final core = job._execution;
    if (core != null && identical(job, core.current)) {
      core.current = null;
      wasCurrent = true;
    }
    _running.remove(job);
    // A drain ends in the pump, so whatever empties the queue has to bring
    // the pump back. Finishing the current job is one way; taking the last
    // queued job off the queue is the other, and it woke nothing. A group
    // waiting for its window keeps `current` empty and takes its timer
    // away with it when it goes, so a drain left with one of those and a
    // `cancelAll` had nothing left to finish it.
    if (wasCurrent || _draining) {
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

  /// One pass: a step in every core, in the order of creation, unless a
  /// step closes the controller with a cancel; then the drain's end.
  void _pump() {
    var drained = 0;
    for (final core in _cores) {
      final end = _step(core);
      if (end == _StepEnd.stop) {
        break;
      }
      if (end == _StepEnd.drained) {
        drained++;
      }
    }
    // A drain ends here, once a pass, and not in the step of a core: a
    // controller with no core has no step to end it, and two cores found
    // drained in one pass would end it twice. Only a pass that found every
    // core drained ends it — none of none counts as all; a core whose step
    // launched a job is not drained even when that job is already over, and
    // the end of the job brings the pump back.
    if (_draining && drained == _cores.length) {
      _finishClose(_closing!);
    }
  }

  /// How a step that took nothing more ends: the pass goes on to the next
  /// core unless a [close] that cancels came in. A drain and [cancelAll]
  /// leave it going.
  _StepEnd get _stepEnd =>
      !isClosed || _draining ? _StepEnd.goOn : _StepEnd.stop;

  /// What the pump does in [core]: takes the head of its queue, asks the
  /// start rules, steps over the jobs they turn down and launches the first
  /// one they accept.
  _StepEnd _step(_SoloLaneCore<S> core) {
    if (core.current != null || (isClosed && !_draining)) {
      return _stepEnd;
    }
    final queue = core.queue;
    var took = false;
    while (true) {
      final job = queue._takeFirst();
      if (job == null) {
        // Not the same as an empty queue: a group waiting for its window
        // stays in it, and its timer brings the pump back. A drain that
        // ended here would cut off the very case it exists for.
        if (_draining && queue._jobs.isEmpty) {
          // Drained, and said nowhere: the pass ends the drain once it has
          // seen every core.
          return _StepEnd.drained;
        }
        // A lane says nothing when it found its queue empty, and says a
        // waiting group once: a pass walks every lane, and the line would
        // come for each lane and each pass driven by another. A step that
        // took jobs and dropped them says it, as a [Solo] says it every
        // time.
        if (core.id == null) {
          _debug(() => core.said('queue has no ready jobs'));
        } else if (took || (queue._jobs.isNotEmpty && !core.saidWaiting)) {
          _debug(() => core.said('queue has no ready jobs'));
        }
        core.saidWaiting = !took && queue._jobs.isNotEmpty;

        return _stepEnd;
      }
      took = true;
      // Off the queue, not started, and not yet `current`: while the rules
      // are asked — the caller's code — this job belongs to nobody, and only
      // `inTransition` can hand it to a `cancelAll` or a `close` made from in
      // there.
      core.inTransition = job;
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
          _debug(() => core.said('rule of $job threw: $error'));
          job._drop(Failed(error, stackTrace));
          continue;
        }
        if (job.isFinished) {
          // The rules are the caller's code, and one of them ended this
          // job while answering: `cancel()` on a job that has not started
          // finishes it where it stands, and a `cancelAll` or a `close`
          // from in there reaches it through `inTransition`. Launching it
          // now would throw `has already finished` from the core and
          // leave the pump holding a finished `current` — the queue would
          // never move again. This comes before the rejection: a rule that
          // ended the job and then turned it down has not dropped it, and a
          // `drop` line would name an outcome the job does not have.
          _debug(
            () => core.said('start $job: ended while the rules were asked'),
          );
          continue;
        }
        if (rejection != null) {
          final cancelled = Cancelled.by(
            reason: const RulesCancelReason(),
            started: false,
            description: rejection,
            stackTrace: StackTrace.current,
          );
          // Said here, where the queue lets the job go: the line after it,
          // if any, is `queue has no ready jobs`, which reads as if the job
          // had never been queued.
          _debug(() => core.said('drop $job: $cancelled'));
          job._drop(cancelled);
          continue;
        }
        // The window closes here, not at the end of the launch: from now
        // on the job is the current one, and that is where a `cancelAll`
        // or a `close` from inside its body finds it.
        core
          ..current = job
          ..inTransition = null;
        job._launch();
        return _stepEnd;
      } finally {
        core.inTransition = null;
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

/// The controller with one queue: its root jobs run one at a time.
///
/// A controller's operations are methods of its own, such as `load()`, built
/// from [enqueue], or from [job] and [enqueueJob], and from [collect] and
/// [accumulate] where several events share one job. The five are protected: a
/// caller sees the operations, not how they are queued.
///
/// The state, the listeners, closing and the hooks come from
/// [SoloController].
///
/// See [Reference](https://github.com/vi-k/solo/blob/main/packages/solo/doc/reference.md#solo)
/// for every member and the section that explains it.
abstract class Solo<S extends Object> extends SoloController<S> {
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
  /// that awaits a job it queued on its own controller, within one lane for a
  /// [SoloLanes], from its body, a child or its cleanup, waits for good, and
  /// this is the line that shows it.
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

  /// The one core of this controller: its queue, its current job and the
  /// job whose start rules are being asked.
  late final _SoloLaneCore<S> _core = _SoloLaneCore<S>(this, name: null);

  // Late, not filled in the constructor body: the observer's `onCreate`
  // runs before that body and may already queue a job and close.
  @override
  late final List<_SoloLaneCore<S>> _cores = List.unmodifiable([_core]);

  @override
  SoloPending? get _pending => _pendingOf(_core);

  /// Creates a controller in [initialState].
  Solo(super.initialState) : super._();

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
  /// [isExpectedError] names the errors the job expects. `onError` hears one it
  /// names with [JobErrorAnswer.never], and nobody is asked to answer for it:
  /// not `onUnanswered`, not `unansweredHandler`, not the zone. `value` still
  /// throws it. It is asked about each error of the job on its own, the parts
  /// of a `ParallelWaitError` too, whether `ifFailed` ran or not, and a child
  /// started in the body takes it. Keep it a type check.
  ///
  /// See [Parameters of a job](https://github.com/vi-k/solo/blob/main/packages/solo/doc/reference.md#parameters-of-a-job)
  /// and [Naming the expected errors](https://github.com/vi-k/solo/blob/main/packages/solo/doc/errors.md#naming-the-expected-errors).
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
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) => _makeJob<W, T>(
    _core,
    body,
    key: key,
    canStart: canStart,
    keepWhile: keepWhile,
    cancellable: cancellable,
    timeout: timeout,
    describe: describe,
    ifFailed: ifFailed,
    isExpectedError: isExpectedError,
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
  /// at most once, however many events it holds. [isExpectedError] is the one
  /// of [job], asked for each job the accumulator queues.
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
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) => _collectIn<W, E, T>(
    _core,
    handler,
    key: key,
    policy: policy,
    timing: timing,
    canStart: canStart,
    keepWhile: keepWhile,
    cancellable: cancellable,
    timeout: timeout,
    describe: describe,
    ifFailed: ifFailed,
    isExpectedError: isExpectedError,
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
  /// state handlers, with [isExpectedError], follow [collect]. No job is
  /// created until the first event, and no state changes before the handler
  /// runs. [timing] has the same group readiness behavior as it does for
  /// [collect].
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
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) => _accumulateIn<W, E, T>(
    _core,
    handler,
    merge: merge,
    key: key,
    policy: policy,
    timing: timing,
    canStart: canStart,
    keepWhile: keepWhile,
    cancellable: cancellable,
    timeout: timeout,
    describe: describe,
    ifFailed: ifFailed,
    isExpectedError: isExpectedError,
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
  /// [Policy.keepLatest] and [Policy.restart] queue [job] before they cancel
  /// the jobs it replaces, whose `onFinish` and cancellation listeners run
  /// inside this call: a job they queue under the key replaces [job] in turn.
  /// A hook that does so on every cancellation, a replacement too, runs out of
  /// stack; such a hook leaves a [ReplacedCancelReason] alone.
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
  }) => _enqueueIn(_core, _own(job), first: first, policy: policy);

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
    bool Function(Object error)? isExpectedError,
    S Function(S state, Cancelled cancelled)? ifCancelled,
  }) => enqueueJob(
    job<W, T>(
      body,
      key: key,
      canStart: canStart,
      keepWhile: keepWhile,
      cancellable: cancellable,
      timeout: timeout,
      describe: describe,
      ifFailed: ifFailed,
      isExpectedError: isExpectedError,
      ifCancelled: ifCancelled,
    ),
    policy: policy,
  );

  /// The queue, for subclasses that manage it directly.
  @protected
  SoloQueue get queue => _core.queue;

  /// The running root job, or `null` when idle.
  @protected
  SoloJob<Object?>? get current => _core.current;

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
      _lastJobWhereIn(_core, test);

  /// {@macro solo.SoloController.close}
  @override
  @mustCallSuper
  Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) =>
      super.close(mode: mode);

  /// {@macro solo.SoloController.cancelAll}
  @override
  Future<void> cancelAll({
    bool force = false,
    CancelReason reason = const ManualCancelReason(),
  }) => super.cancelAll(force: force, reason: reason);
}

/// The controller with lanes: its root jobs run one at a time in each lane,
/// and the lanes run side by side over one state.
///
/// The lanes are declared in the constructor with [lane], and one pump walks
/// them in that order. A write of one lane asks the rules of the jobs of the
/// others again, as [externalSetState] does: a job whose `W` or `keepWhile`
/// no longer holds is cancelled. The trap is a write of a whole state read
/// before an `await`: it loses what the other lanes wrote in between, so a
/// job reads `ctx.state` where it writes.
///
/// The state, the listeners, closing and the hooks come from
/// [SoloController].
///
/// See [Two queues over one state](https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#two-queues-over-one-state)
/// and [A write that keeps the other lane's work](https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#a-write-that-keeps-the-other-lanes-work)
/// on the lanes page.
abstract class SoloLanes<S extends Object> extends SoloController<S> {
  /// The lanes in the order of creation.
  final _lanes = <_SoloLane<S>>[];

  // Filled by `lane`, from the constructor body; the observer's `onCreate`
  // runs before that body and finds no lane yet.
  @override
  final List<_SoloLaneCore<S>> _cores = [];

  /// What sealed the set of lanes first, or `null` while it is open: the
  /// microtask the constructor schedules, or the first call of `enqueueJob`
  /// of any lane, whatever came of it. A closed controller takes no lane
  /// either; `lane` asks [isClosed] for that.
  _Sealed? _sealed;

  /// Creates a controller in [initialState], with no lane until the body of
  /// the subclass's constructor declares them.
  SoloLanes(super.initialState) : super._() {
    // A lane declared after this microtask throws whenever it is declared,
    // and not only once a job has come: a `late final` field read in the
    // first call of a method would declare its lane at the mercy of the
    // order of the calls.
    scheduleMicrotask(() => _sealed ??= _Sealed.constructor);
  }

  /// Declares a lane named [name] and returns it.
  ///
  /// Called in the body of the constructor, and kept in a private field.
  /// Throws [StateError] for a [name] this controller has a lane of already,
  /// and once the set of lanes is sealed: once any lane's `enqueueJob` has
  /// been called (a refused or duplicate call seals too), after [close], or
  /// after a microtask the constructor schedules. So a lane in a `late final`
  /// field is an error: the field read after the constructor throws.
  ///
  /// See [Declaring lanes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#declaring-lanes)
  /// on the lanes page.
  @protected
  SoloLane<S> lane(String name) {
    final why = switch (_sealed) {
      _Sealed.constructor =>
        'after its constructor: lanes are declared in the constructor body, '
            'and a late final field declares its lane on its first read',
      _Sealed.enqueue =>
        'after enqueueJob of one of its lanes was called: from the first '
            'call on, the lanes are what the pump walks',
      null when isClosed => 'after close: a closed controller takes no lane',
      null => null,
    };
    if (why != null) {
      throw StateError(
        'Cannot declare lane $name of $runtimeType $why; see $_declaringLanes',
      );
    }
    for (final lane in _lanes) {
      if (lane.name == name) {
        throw StateError(
          '$runtimeType has a lane named $name already: every call of lane '
          'declares a new lane, and two of one name would read as one; see '
          '$_declaringLanes',
        );
      }
    }
    final lane = _SoloLane<S>(this, name);
    _lanes.add(lane);
    _cores.add(lane._core);
    return lane;
  }

  /// The lanes of this controller in the order they were declared, the
  /// order a pass of the pump walks them in; an unmodifiable list.
  ///
  /// See [Declaring lanes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#declaring-lanes)
  /// on the lanes page.
  @protected
  List<SoloLane<S>> get lanes => List<SoloLane<S>>.unmodifiable(_lanes);

  // The busy lanes in the order of creation, each by the rules of a `Solo`.
  // No busy lane is `null`, and one is a `SoloPendingLanes` as several are:
  // the shape does not depend on how many lanes hold the controller.
  @override
  SoloPending? get _pending {
    final lanes = <({SoloLaneId lane, SoloPending pending})>[
      for (final core in _cores)
        if (_pendingOf(core) case final pending?)
          (lane: core.id!, pending: pending),
    ];
    return lanes.isEmpty
        ? null
        : SoloPendingLanes(
            List<({SoloLaneId lane, SoloPending pending})>.unmodifiable(lanes),
          );
  }
}

/// What sealed the set of lanes of a [SoloLanes] first.
enum _Sealed {
  /// The microtask the constructor schedules.
  constructor,

  /// The first call of `enqueueJob` of any lane.
  enqueue,
}

/// Feeds the hooks of one job into [SoloObserver] and into the controller's
/// own hooks, each call isolated on its own.
///
/// A throwing observer must not switch off the instance hook standing next
/// to it, so the two calls are wrapped separately.
final class _SoloJobObserver<S extends Object>
    implements JobObserver, JobAnswerer {
  final SoloController<S> _solo;

  _SoloJobObserver(this._solo);

  @override
  void onStart(Job<Object?> job) {
    SoloController._callHook(() => Solo.observer?.onStart(_solo, job));
    SoloController._callHook(() => _solo.onStart(job));
  }

  @override
  void onFinish(Job<Object?> job) {
    SoloController._callHook(() => Solo.observer?.onFinish(_solo, job));
    SoloController._callHook(() => _solo.onFinish(job));
  }

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {
    // The verdict of `isExpectedError` is asked here, once, and kept for
    // `onUnanswered`: only an error that can go on to an answer is asked about.
    var heard = answer;
    if (answer == JobErrorAnswer.answered || answer == JobErrorAnswer.later) {
      if ((job as _SoloJob)._judge(error)) {
        heard = JobErrorAnswer.never;
      }
    }
    SoloController._callHook(
      () =>
          Solo.observer?.onError(_solo, job, error, stackTrace, answer: heard),
    );
    SoloController._callHook(
      () => _solo.onError(job, error, stackTrace, answer: heard),
    );
  }

  /// The controller answers for its jobs: [SoloController.onUnanswered], and
  /// the [Solo.unansweredHandler] behind it. [Solo.observer] is not asked —
  /// watching every controller is not answering for any of them. For an error
  /// the job's `isExpectedError` names it writes a line to [Solo.debug] and
  /// returns.
  ///
  /// Not called through [SoloController._callHook]: what the answer throws
  /// goes back to the core, which sends the error it was asked about to the
  /// zone first and then what it threw, as `onListenerError` does here.
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    if ((job as _SoloJob)._answersFor(error)) {
      SoloController._debug(
        () => '$job expected $error: nobody is asked to answer',
      );
      return;
    }
    _solo.onUnanswered(job, error, stackTrace);
  }

  @override
  void onLog(Job<Object?> job, Object? message) {
    SoloController._callHook(() => Solo.observer?.onLog(_solo, job, message));
    SoloController._callHook(() => _solo.onLog(job, message));
  }
}
