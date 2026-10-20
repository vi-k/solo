import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

part 'envelope.dart';
part 'job.dart';
part 'job_context.dart';
part 'job_stream.dart';
part 'job_then.dart';
part 'observer.dart';
part 'outcome.dart';
part 'run_all.dart';

/// `void` as a type to compare with: `T == void` does not parse.
typedef _Void = void;

/// One registration on the cleanup stack of a job.
///
/// [always] tells the two kinds apart: a `dispose` registration runs whatever
/// the outcome, a `discard` one only when the job did not end [Done].
/// [value] is set for registrations made by `abandonable`, `join` and `run`,
/// and it is what `disown` looks up.
final class _Cleanup {
  final FutureOr<void> Function() run;
  final bool always;
  final Object? value;

  /// Where this registration stands in the order they were made.
  ///
  /// The stack alone stops answering that once the unwinding starts: it
  /// moves the registrations it puts off out of the list, and a late value
  /// can be registered while they are aside. `disown` promises the top
  /// one, and the top one is the newest, wherever it is being kept.
  final int order;

  _Cleanup(this.run, {required this.always, required this.order, this.value});
}

/// The lifecycle of a job: start, body, children, cancellation, outcome.
///
/// Subclass it to add a domain of your own — the state, the rules and the
/// queue in `solo`, a scope elsewhere. Everything the engine of that
/// domain needs is protected, and the subclass hands out exactly what it
/// needs through private wrappers of its own: a `@protected` member is for
/// the subclass alone, and an engine reaches a job from the side.
abstract class JobBase<T> implements Job<T> {
  final Object? _key;
  final String Function()? _describe;

  /// Not final: a child created without one inherits the parent's
  /// observer when it is adopted.
  JobObserver? _observer;

  /// The zone the job was created in; an unobserved [Failed] goes here.
  ///
  /// A job created inside [JobContext.unattended] takes the zone that work
  /// was started from, not the fork: the failure is the new job's own, and
  /// it must not arrive at the observer of the job that started the work.
  /// A job is not unattended work — it has an outcome and an observer of
  /// its own, and `ignoreFailure()` is how it is quenched.
  final Zone _zone = _creationZone();

  static Zone _creationZone() =>
      (Zone.current[_unattendedKey] as Zone?) ?? Zone.current;

  /// Made in [_zone], not in the current zone: a future keeps the zone it
  /// was made in, and inside the work of [JobContext.unattended] that is
  /// the fork, whose values carry the job that started the work. A handle
  /// kept for the outcome would hold that job, and all it holds, for as
  /// long as the handle lives.
  final _done = _newDone<T>();

  /// Through `run` only inside the work: everywhere else [_zone] is the
  /// current zone, and `run` would cost every job a call into the zone's
  /// handlers for nothing.
  static Completer<Outcome<R>> _newDone<R>() {
    final outside = Zone.current[_unattendedKey] as Zone?;
    return outside == null
        ? Completer<Outcome<R>>()
        : outside.run(Completer<Outcome<R>>.new);
  }

  Cancelled? _cancelled;
  final _cancelListeners = <void Function(Cancelled)>[];

  /// Whether the pass that tells the [whenFinished] listeners has run: from
  /// then on a registration is called at once. Not `isFinished`: the outcome
  /// is set before `onFinish` and the pass, and a registration made in there
  /// belongs to the pass, after the ones made earlier.
  bool _finishTold = false;
  final _finishListeners = <void Function(Outcome<T>)>[];
  final _onCancel = <void Function()>[];
  final _cleanups = <_Cleanup>[];

  /// The registrations the first pass of the unwinding has put aside.
  ///
  /// They are still waiting, not gone: an outcome of [Done] that a late
  /// cancellation takes away brings them back. A disposer running below
  /// them may take one back — through the function [JobContext.onDispose]
  /// returned, or through [JobContext.disown] — so they have to stay
  /// reachable from both, and a local list would hide them.
  final _skipped = <_Cleanup>[];

  /// Hands out [_Cleanup.order] — the order registrations were made in.
  int _cleanupOrder = 0;

  /// The first and the last of the children this job waits for, in the
  /// order they were adopted; each child holds its neighbours, in
  /// [_previousSibling] and [_nextSibling].
  ///
  /// A chain and not a collection, for three reasons. A child goes on it
  /// where the stack may have run out, and there only a store is sure to be
  /// done: a hash set that grows re-adds its keys by calls, and one cut
  /// short halfway leaves the set empty and the parent with no child to wait
  /// for. A child is found by what it is and never by `==`: a job of a
  /// domain may compare itself by a key, two children equal by that key are
  /// still two jobs, and a list searched by `==` would let the one that
  /// finishes take its sibling off instead. And a child leaves at once,
  /// where a list had to be walked to find it and a parent of thousands of
  /// children took time quadratic in their number.
  JobBase<Object?>? _firstChild;
  JobBase<Object?>? _lastChild;

  /// The neighbours of this job on the chain of [_waitedForBy].
  JobBase<Object?>? _previousSibling;
  JobBase<Object?>? _nextSibling;

  /// The job whose chain of children this one is on.
  ///
  /// Not [_parent]: that one is set before the child joins the chain, and a
  /// handle whose start was cut short may be handed to another parent while
  /// the first still lists it.
  JobBase<Object?>? _waitedForBy;

  /// The child behind an outcome of a child, for the description of this
  /// job's own.
  ///
  /// The key is the outcome instance itself, so two children of one job must
  /// never end with one instance, const or not: they would share one entry, and
  /// the job would name the one that finished last. Every cancellation the core
  /// builds is an instance of its own; an engine that hands one to [finish] or
  /// [cancelWith] builds one per job too, and with asserts on [finish] says so
  /// when it did not.
  ///
  /// `late final` and not `final`, the way `_cascadeChild` below already
  /// is: only a parent whose child's outcome came out through its body
  /// ever writes here, and an `Expando` on every job that never has a
  /// child is most of what a job weighs.
  late final _outcomeChild = Expando<JobBase<Object?>>();

  // A public reason type is not proof that this job issued the cancellation.
  // Tokens identify the child without retaining its handle through a reason.
  late final _cascadeChild = Expando<Object>();
  late final Object _cascadeIdentity = Object();

  JobBase<Object?>? _parent;

  final bool _cancellable;
  var _uncancellableDepth = 0;
  Cancelled? _heldCancel;

  /// The deadline given with `timeout`, or `null` for a job without one.
  final Duration? _timeout;

  /// Where the job with a deadline was created: the cancellation the
  /// deadline makes carries it. Taken when the timer fires, it would be a
  /// bare event loop; taken at the start, it would lead to a queue or to
  /// `ctx.run`. The constructor leads to the code that set the deadline.
  final StackTrace? _timeoutTrace;

  /// The timer of the deadline, from the start until the body and the
  /// children are over or the job ends.
  Timer? _timeoutTimer;

  /// The reason the timer cancelled this job with, once it has fired.
  ///
  /// The request of the deadline is told apart by this very instance, not by
  /// the [Cancelled] that carries it: an engine may wrap a cancellation into a
  /// new [Cancelled] with the same reason before it calls `super`.
  TimeoutCancelReason? _timeoutReason;

  /// A rejectable cancellation that arrived while a section held the
  /// deadline in [_heldCancel].
  ///
  /// `??=` keeps the first request held, and the deadline is lifted at the
  /// end of the body and the children: a request made after it would be
  /// lifted with it. It takes the place of the deadline there instead.
  /// Cleared wherever [_heldCancel] is cleared.
  Cancelled? _heldBehindTimeout;

  /// Whether anyone observed the outcome, directly or by forwarding it.
  bool _observed = false;

  /// Whether the zone has heard the failure of this job: it went there because
  /// nobody observed it in time — see [_reportUnobserved] — or it is the
  /// failure of a source the zone heard it from, carried on. A continuation
  /// attached later still carries it, and must not send it there a second time.
  bool _failureWentToZone = false;

  /// Whether [Job.ignoreFailure] was called: nobody wants this job's failure.
  ///
  /// More than [_observed]. Whoever reads the outcome has the failure the
  /// outcome carries. A failure of the body of a job that ends [Cancelled], or
  /// of one an engine ended by hand with an outcome of its own, is in no
  /// outcome, and one of a branch the group did not throw is in nothing the
  /// group passes on; only this keeps them all from being answered for — see
  /// [_reportCovered] and `_RunAllGroup._conclude`. [Job.isCancellationError]
  /// keeps out the failures of a cancelled job it names, and those alone.
  bool _ignored = false;

  /// The key of the mark a fork of [JobContext.unattended] made by this job
  /// carries. An object of its own and not the job: a zone looks a key up
  /// by `==`, a job of a domain may compare itself by a key of its own, and
  /// the fork of one of two equal jobs nested in the other's would then pass
  /// for the outer one.
  final _forkKey = Object();

  /// The error of the last failure the core has announced for this job: the
  /// body's, where it was caught, the one a continuation received from its
  /// source, or one an engine handed to [finish]. The same error arriving by a
  /// second route — a body that throws what the engine has already ended the
  /// job with, say — is not announced again. By identity: two errors equal by
  /// `==` are still two errors.
  ///
  /// Held weakly. A failure of the body of a job that ends [Cancelled] is in no
  /// outcome, and the handle of that job would otherwise keep the error, and
  /// everything it references, for as long as the handle lives. What [_isPlain]
  /// says cannot be held weakly is held as it is, in [_announcedPlain], and a
  /// record keeps whatever it references.
  WeakReference<Object>? _announcedError;

  /// The error of the last announcement, when it cannot be held weakly.
  Object? _announcedPlain;

  /// Whether [error] is the error the core announced last for this job.
  bool _wasAnnounced(Object error) => _isPlain(error)
      ? identical(error, _announcedPlain)
      : identical(error, _announcedError?.target);

  /// Notes [error] as the error the core announced last for this job.
  void _noteAnnounced(Object error) {
    if (_isPlain(error)) {
      _announcedPlain = error;
      _announcedError = null;
    } else {
      _announcedError = WeakReference(error);
      _announcedPlain = null;
    }
  }

  /// Continuations still waiting to receive this outcome. A late listener
  /// may attach within the observation grace period but receive the result
  /// on the next microtask; give it that chance before reporting a failure.
  int _pendingContinuations = 0;

  JobStatus _status = JobStatus.created;
  Outcome<T>? _outcome;
  Cancelled? _pendingCancel;
  bool _bodyEnded = false;

  /// Whether [error] cannot be held weakly: a string, a number, a boolean,
  /// a record, or a `Pointer`, `Struct` or `Union` of `dart:ffi`. The last
  /// three are not named, so the package does not import `dart:ffi` and
  /// still builds for the web; [_weakProbe] is asked instead, and its
  /// refusal is the answer.
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

  /// Read by [_isPlain] and never written: it refuses exactly what an
  /// [Expando] or a [WeakReference] cannot hold.
  static final _weakProbe = Expando<bool>();

  /// Whether this job is unwinding a cascade that ran out of stack.
  ///
  /// True only between the moment the descent threw and the end of the pass
  /// that tells this job's callbacks. In that window an overflow landing in a
  /// callback is the cascade's own, not the callback's, and the two guards that
  /// wrap user code let it through instead of announcing it. Outside the window
  /// a callback that runs out of stack did it by itself, and the promise
  /// stands: its error goes to `onError` and on to the job's answer and changes
  /// nothing else.
  bool _outOfStack = false;

  /// Whether [_execute] has taken its first step.
  ///
  /// Written by the routine, and by the parent that ends the job in its
  /// place. A job that is running with this still `false` has no routine:
  /// its start was cut short before it got that far.
  bool _routineEntered = false;

  /// Whether the start of this job, a child, is on the stack.
  ///
  /// Written by the parent: up before the child joins the waiting list,
  /// down once [start] has returned. While it stands the child may be
  /// anywhere in its start, and the parent does not judge it. A start is
  /// synchronous, so a turn later it is on no stack, and a mark that still
  /// stands then was left by a start that was thrown out: where the stack
  /// has run out nothing is done, and that includes taking this down. The
  /// parent takes it down itself -- see [_awaitChildren]. On a job that has
  /// finished it says nothing.
  bool _startInFlight = false;

  /// What escaped the synchronous part of [_execute], and its trace.
  ///
  /// That part runs on the stack of whoever starts the job, and when that
  /// stack has run out, it is out for every handler on the way up as well:
  /// whatever one of them calls throws again, a type check included, and a
  /// handler cut short leaves its bookkeeping half done. So nothing is done
  /// down there. What escaped is written down, [_start] throws it to
  /// whoever started the job, and the parent ends the job once its own
  /// body is over, on a stack of its own -- see [_startWasTorn].
  Object? _tornError;
  StackTrace? _tornTrace;

  /// Whether [_start] has returned: the synchronous part of [_execute] is
  /// over, and whatever escapes the routine from here on did not happen on
  /// the stack of the start.
  bool _startReturned = false;

  /// What the body ended with, from that moment until the job has an
  /// outcome of its own.
  ///
  /// A group of [JobContext.runAll] attaches its hold after the branch is
  /// admitted, and a body that is not `async` and throws in its start has ended
  /// by then: the early word found nothing to say itself to. This is where the
  /// group reads what it was not there to hear.
  Outcome<T>? _bodyOutcome;
  bool _disposing = false;

  /// A branch of [JobContext.runAll] stands at its second barrier, between
  /// the two passes over the cleanup stack.
  ///
  /// It is disposing, yet no callback of its stack runs there, and a value
  /// that reached nobody need not wait for the second pass: a cleanup of a
  /// sibling the group is waiting for may want that very slot of a pool.
  bool _betweenPasses = false;
  int _level = 0;

  /// The newest of the groups of [JobContext.runAll] this job has formed
  /// and that have not ended; each holds the one before it -- see
  /// [_RunAllGroup._next].
  ///
  /// A chain and not a list: a group goes on it where the stack may have
  /// run out, and there only a store is sure to be done. One of the groups
  /// with no routine of its own was cut short while it was forming, and
  /// this job takes it up once its body is over -- see
  /// [_RunAllGroup._concludeTorn].
  _RunAllGroup<Object?>? _firstGroup;

  /// What holds this job while a group of [JobContext.runAll] decides.
  ///
  /// Set by the group once the branch is admitted and never again. The
  /// branch stands at its barriers in [_execute] and takes the verdict
  /// from there; a job nobody grouped has none of this.
  _GroupHold? _hold;

  /// Whether a group has committed the value of this branch.
  ///
  /// A committed value is in the caller's hands, so a conditional
  /// registration of this job must not run any more, whatever outcome the
  /// branch itself ends with, and a cancellation has nothing left to stop:
  /// [cancelWith] turns it away. The other way round it does not work: a
  /// group that failed does not make a branch give up a value it hands
  /// over through [Job.value] all the same.
  ///
  /// Set by the group in the step that hands the values over, and read
  /// again from the verdict at the second barrier.
  bool _committedByGroup = false;

  /// Whether the group of [JobContext.runAll] goes by the failure of the body
  /// of this branch instead of the value an engine handed in after the group
  /// heard of that failure. The group throws that failure or answers for it.
  ///
  /// Set in [finish], once, and read by the body's route, which then leaves
  /// that failure to the group.
  bool _failureWentToGroup = false;

  /// Creates a job that has not started yet.
  ///
  /// The named parameters are those of [Job.new], [timeout] included, and
  /// so are the errors: [ArgumentError] for a [timeout] that is zero or
  /// negative, or that comes with `cancellable: false`.
  JobBase({
    Object? key,
    String Function()? describe,
    bool cancellable = true,
    Duration? timeout,
    JobObserver? observer,
  })  : _timeout = _checkTimeout(timeout, cancellable: cancellable),
        _timeoutTrace = timeout == null ? null : StackTrace.current,
        _key = key,
        _describe = describe,
        _cancellable = cancellable,
        _observer = observer {
    _builtOnCore[this] = true;
  }

  /// Returns [timeout] if a job may have it, and throws otherwise.
  ///
  /// Before anything else is set: a job refused here never exists.
  static Duration? _checkTimeout(
    Duration? timeout, {
    required bool cancellable,
  }) {
    if (timeout == null) {
      return null;
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('must be positive, not $timeout', 'timeout');
    }
    if (!cancellable) {
      throw ArgumentError(
        'needs a cancellable job, and cancellable: false refuses the '
            'cancellation the deadline makes',
        'timeout',
      );
    }
    return timeout;
  }

  /// The jobs that went through this constructor.
  ///
  /// `is JobBase` answers yes to a class that implements the protocol
  /// instead of extending it — a mock, a fake — and such a job has none of
  /// the state the core adopts a child with: the first private field the
  /// core touches throws `NoSuchMethodError`. Asked here instead, it is
  /// refused as what it is, a job of no core.
  static final _builtOnCore = Expando<bool>('builtOnCore');

  /// Whether the value of this job is `void`, and not just one that admits
  /// `null`: a `Job<Object?>` may end with a handle on purpose.
  bool get _isVoid => T == _Void;

  /// Whether [value] is a job of [Job.deferred] that nobody has started.
  static bool _neverStartedDeferredJob(Object? value) =>
      value is _DeferredJob<Object?> && value.status == JobStatus.created;

  /// Says what went nowhere when the value of this job went to somebody.
  ///
  /// Said out loud because the silence is the whole trouble. A conditional
  /// registration is settled by the outcome of the job that made it, so a
  /// value handed over takes none of them with it: from here on the
  /// resource belongs to whoever received it, and registering its release
  /// is theirs to do. Forget that, and nothing looks wrong until the
  /// receiver ends badly — and then the resource is simply lost, with no
  /// trace anywhere.
  void _traceDroppedCleanups() => _droppedCleanupsTrace()?.call();

  /// The line of [_traceDroppedCleanups], taken in two steps.
  ///
  /// The count and the outcome a hand finish left are read now, while the
  /// list is full. The line itself, the job's `describe` and `toString`
  /// included, is built and said when called: the unwinding calls it after
  /// `finish`, and the caller's code that builds or hears the line finds the
  /// job over.
  void Function()? _droppedCleanupsTrace() {
    if (_skipped.isEmpty) {
      return null;
    }
    final count = '${_skipped.length} conditional '
        'cleanup${_skipped.length == 1 ? '' : 's'}';
    // Two ways to leave them behind, and the message must not mix them up.
    // Normally the job is still deciding and the value went to somebody. But an
    // engine may finish a job by hand while it unwinds, and then the outcome is
    // already something else and the value went nowhere — saying it was handed
    // over would be a plain lie.
    final finishedAs = isFinished ? _outcome : null;
    return () => _debug(
          () => finishedAs != null
              ? '$this was finished as $finishedAs with $count left aside'
              : '$this handed its value over: $count dropped',
        );
  }

  /// Builds and delivers a diagnostic message, guarded on both halves.
  ///
  /// Guarded because the channel stands between transitions a job cannot be
  /// left in the middle of: an error here once left a job `isFinished` with its
  /// `done` never completing. Both halves belong to whoever turned the channel
  /// on — `message()` runs their `describe` and `toString`, and [Job.debug] is
  /// theirs — and a diagnostic channel is cross-cutting like an observer: an
  /// error in it changes nothing else.
  static void _debug(String Function() message) {
    final debug = Job.debug;
    if (debug == null) {
      return;
    }
    final marked = <(Object, StackTrace)>[];
    try {
      final line = _collectingMarks(marked, message);
      _marksToZone(marked);
      debug(line);
    } on Object catch (error, stackTrace) {
      _marksToZone(marked);
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  /// Hands [marked] to the current zone and empties it, so a mark already
  /// reported is not reported again.
  static void _marksToZone(List<(Object, StackTrace)> marked) {
    for (final (error, stackTrace) in marked) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
    marked.clear();
  }

  /// Calls [hook] and hands whatever it throws to the current zone, a
  /// cancellation excepted.
  ///
  /// The observer of a job is a cross-cutting channel: an error in it
  /// changes nothing else.
  static void _notify(void Function() hook) {
    try {
      hook();
    } on Object catch (error, stackTrace) {
      _hookErrorToZone(error, stackTrace);
    }
  }

  /// Hands what a hook threw to the current zone.
  ///
  /// The same rule as `_toZone`: a cancellation is a decision, not a
  /// failure. A lazy message whose closure asks a job that has accepted one
  /// throws it from `onLog`, and the zone can do nothing with it.
  static void _hookErrorToZone(Object error, StackTrace stackTrace) {
    if (_isCancellation(error)) {
      return;
    }
    Zone.current.handleUncaughtError(error, stackTrace);
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
  void ignoreFailure() {
    _observed = true;
    _ignored = true;
  }

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
  Job<R> then<R>(
    FutureOr<R> Function(JobContext ctx, T value) onValue, {
    JobObserver? observer,
  }) =>
      _ThenJob<T, R>(this, onValue, observer: observer);

  /// [callback], with its errors gone where the errors of a listener go.
  void Function(A) _guardListener<A>(void Function(A) callback) => (event) {
        try {
          callback(event);
        } on Object catch (error, stackTrace) {
          if (error is StackOverflowError && _outOfStack) {
            // Not `onError`, and above all not the zone. At the bottom of a
            // cascade that has just run out of stack this is that same
            // overflow, landing in the first callback to ask for a few
            // frames more; reporting it would name the callback for
            // something it did not do, and would format a stack trace with
            // no stack left to do it on. It leaves with the error that is
            // already unwinding. Outside that window the callback ran out
            // of stack on its own, and that is its error like any other.
            rethrow;
          }
          notifyError(error, stackTrace);
        }
      };

  @override
  void Function() whenCancelled(void Function(Cancelled) callback) {
    final guarded = _guardListener(callback);

    // `_cancelled` and not `_pendingCancel`: between the mark and the pass
    // that tells the listeners there is a window -- the cascade onto the
    // children -- and a registration made in there belongs in that pass,
    // not ahead of it.
    // Calling it on the spot would run it before everyone who registered
    // earlier and is still waiting. Once the pass has run, `_cancelled` is
    // set and a late registration is called at once, as promised; a job
    // that finished cancelled set it on the way out.
    final cancelled = _cancelled;
    if (cancelled != null) {
      guarded(cancelled);
      return () {};
    }
    // Only a job that finished without a cancellation has nothing left to
    // tell. One that finished cancelled and has not told its listeners yet
    // -- `finished` and `onFinish` run first, and for a job dropped before
    // its start there was no mark to set `_cancelled` earlier -- still has
    // the pass ahead of it, and this registration belongs in it.
    if (isFinished && _outcome is! Cancelled) return () {};
    _cancelListeners.add(guarded);
    return () => _cancelListeners.remove(guarded);
  }

  @override
  void Function() whenFinished(void Function(Outcome<T> outcome) callback) {
    final guarded = _guardListener(callback);
    if (_finishTold) {
      guarded(_outcome!);
      return () {};
    }
    _finishListeners.add(guarded);
    return () => _finishListeners.remove(guarded);
  }

  @override
  Future<void> cancel({CancelReason reason = const ManualCancelReason()}) {
    cancelWith(
      Cancelled.by(
        reason: reason,
        stackTrace: StackTrace.current,
      ),
    );
    // The core's own waiting is not observation, so cancelling a job does
    // not silence its failure.
    return untilFinished;
  }

  /// Cancels the job with [cancelled], correcting `started` to its status.
  ///
  /// [cancelled] belongs to this job alone, as [finish] explains.
  ///
  /// Idempotent. [rejectable] is what a job created with
  /// `cancellable: false` may refuse, and its refusal is final — nothing
  /// is replayed later. Inside [JobContext.uncancellable] a rejectable
  /// cancellation is held instead: the step runs untouched, and the
  /// cancellation lands the moment the last section closes — it comes
  /// through here a second time then, so an override hears a held
  /// cancellation twice. The rules of a domain pass `false` and go through
  /// both.
  ///
  /// A subclass extends this member rather than replacing it: `solo` adds the
  /// branch for a job still waiting in its queue and then calls `super`. An
  /// override that forgets the call silently switches cancellation off — for
  /// [Job.cancel], for the cascade from a parent and for whatever an engine
  /// adds.
  @protected
  @mustCallSuper
  void cancelWith(Cancelled cancelled, {bool rejectable = true}) {
    Cancelled withStarted(bool started) => cancelled.started == started
        ? cancelled
        : Cancelled.by(
            reason: cancelled.reason,
            started: started,
            description: cancelled.description,
            stackTrace: cancelled.stackTrace,
          );
    switch (_status) {
      case JobStatus.finished:
        return;
      case JobStatus.created:
        _debug(() => 'cancel $this before start: $cancelled');
        finish(withStarted(false));
      case JobStatus.running:
        if (_pendingCancel != null) {
          return;
        }
        if (_committedByGroup) {
          // A branch whose value its group has handed over is still
          // unwinding, and nothing is left for a cancellation to stop: the
          // value is in the caller's hands, and the mark would only make the
          // branch end [Cancelled] with it. Any cancellation, the rules of a
          // domain too, finds it as it would find a child of `run` that
          // handed its value over by ending.
          _debug(() => 'cancel $this: its group has its value');
          return;
        }
        if (!_cancellable && rejectable) {
          _debug(() => 'cancel $this: not cancellable');
          return;
        }
        final marked = withStarted(true);
        if (_uncancellableDepth > 0 && rejectable) {
          // Held, not refused, and the job is not marked: `onCancel`
          // callbacks and the cascade onto children would stop the very
          // step this section protects.
          //
          // A request behind a held deadline is kept apart: the deadline is
          // lifted at the end of the body and the children, and this one
          // must not be lifted with it.
          final held = _heldCancel;
          if (held != null && _isOwnTimeout(held) && !_isOwnTimeout(marked)) {
            _heldBehindTimeout ??= marked;
          }
          _heldCancel ??= marked;
          // Said once the request is held, as the line below is said once
          // the job is marked: see there.
          _debug(() => 'cancel $this: held until the step ends: $marked');
          return;
        }
        // Only a cancellation the job cannot refuse gets here inside a
        // section, and it is accepted over the one the section holds: that
        // one would never land, and `heldCancel` must not keep showing it.
        _heldCancel = null;
        _heldBehindTimeout = null;
        // Marked before the cascade, and only marked: a callback of a child
        // may come back for this job, and the early return above is the only
        // thing that stops it from cascading and marking a second time.
        // What the marking brings with it — `whenCancelled` and the
        // callbacks — still waits for the children, because `solo` pins the
        // order in which a cancellation is seen.
        _pendingCancel = marked;
        // Said after the mark, not before it. `Job.debug` is code of the
        // caller's, and one that cancels this job on hearing the line would
        // come back in here: before the mark it would mark and announce its
        // own reason, and this call would then overwrite the mark with
        // another -- the listeners would hear one cancellation and the job
        // end with a second. After the mark it turns around at the early
        // return above, like a callback of a child does.
        _debug(() => 'cancel $this: $marked');
        try {
          _cascadeToChildren(marked);
        } finally {
          // In a `finally`, because the cascade is recursive and a deep
          // enough tree overflows the stack inside it. Everything the
          // cascade reached is marked by then, and without this the
          // unwinding would leave every one of those jobs marked and
          // unannounced: no `onCancel` runs, nothing is told to stop, and
          // a second `cancel()` turns around at the early return above.
          // The error still reaches whoever asked.
          //
          // Skipped when a callback of a child reached the engine and it ended
          // the job by hand. A no-op by then rather than a defect waiting to
          // happen -- `finish` clears the callbacks and tells the listeners
          // itself -- and kept because the phase a job is in decides who
          // announces its cancellation, and reading that off the status is
          // cheaper than trusting the two to stay in step. The window still has
          // to close: it is `_markCancelled` that closes it, and that path
          // skips it.
          if (_status != JobStatus.finished) {
            _markCancelled(marked);
          } else {
            _outOfStack = false;
          }
        }
    }
  }

  /// Cancels every child of this job, deepest last started first.
  ///
  /// The cascade is rejectable: a child created with `cancellable: false`
  /// refuses it. Each child receives [ParentCancelReason] with [cancelled]
  /// as its cause, preserving the parent's reason and data. The cancellation
  /// stack trace is carried over as well.
  ///
  /// Every child is asked, even when asking one of them throws — an engine
  /// whose `cancelWith` fails, a subtree deep enough to run the stack out. The
  /// first error is rethrown once the last child has been asked.
  void _cascadeToChildren(Cancelled cancelled) {
    (Object, StackTrace)? failure;
    for (final child in _childrenNow().reversed) {
      try {
        // The body of `_cancelChild`, written out rather than called.
        // Every frame on this path is paid for at every level of the
        // descent, and one function is worth about six hundred levels of
        // depth: with the call the tree runs out of stack at 2463 jobs,
        // without it at 3128 -- where it was before this loop learned to
        // guard each child at all. `_cancelChild` stays for the other
        // caller, the one that turns a child away before it starts.
        final reason = ParentCancelReason(cause: cancelled);
        _cascadeChild[reason] = child._cascadeIdentity;
        child.cancelWith(
          Cancelled.by(
            reason: reason,
            started: child.isRunning,
            stackTrace: cancelled.stackTrace,
          ),
        );
      } on Object catch (error, stackTrace) {
        if (error is StackOverflowError) {
          _outOfStack = true;
        }
        // One child is not the rest of them. A subtree deep enough to run the
        // stack out, or an engine whose `cancelWith` threw, must not take the
        // cancellation away from the siblings that come after it here -- and
        // those siblings are not deep by association: the one that overflows
        // may be a chain of thousands next to a leaf. The first failure is the
        // one that leaves, the way the first refusal leaves a group.
        failure ??= (error, stackTrace);
      }
    }
    if (failure case (final error, final stackTrace)) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _cancelChild(JobBase<Object?> child, Cancelled cause) {
    final reason = ParentCancelReason(cause: cause);
    _cascadeChild[reason] = child._cascadeIdentity;
    child.cancelWith(
      Cancelled.by(
        reason: reason,
        started: child.isRunning,
        stackTrace: cause.stackTrace,
      ),
    );
  }

  /// Where the job is in its life.
  @protected
  JobStatus get status => _status;

  /// Whether the body has ended — returned or thrown.
  ///
  /// From this moment a value coming out of a call the body walked away
  /// from can no longer reach it, and the rules of a domain have nothing
  /// left to guard.
  @protected
  bool get bodyEnded => _bodyEnded;

  /// Whether the core is unwinding the cleanup stack.
  ///
  /// The body is gone and the outcome is decided, but the job has not
  /// finished: [isFinished] is still `false`.
  ///
  /// A branch of [JobContext.runAll] answers `true` while it waits for the
  /// group between the two passes of its unwinding, whether or not it has
  /// a cleanup stack at all: what a branch may do while it is held must
  /// not depend on that. Its outcome is not decided there — the group has
  /// yet to say so.
  @protected
  bool get isDisposing => _disposing;

  /// The cancellation the job has accepted, or `null`.
  @protected
  Cancelled? get pendingCancel => _pendingCancel;

  /// Whether the job accepts a cancellation it may refuse, as it was
  /// created. An uncancellable section does not change this: it holds a
  /// cancellation rather than refusing it.
  @protected
  bool get cancellable => _cancellable;

  /// Whether a section opened by [enterUncancellable] is open right now.
  ///
  /// For diagnostics: an engine that is waiting for this job and wants to
  /// say why. An open section is not a held cancellation — nobody may have
  /// asked; [heldCancel] is the one that says whether somebody did.
  @protected
  bool get inUncancellableSection => _uncancellableDepth > 0;

  /// The cancellation an open section is holding back, or `null`.
  ///
  /// Set when a cancellation the job may refuse arrives inside a section opened
  /// by [enterUncancellable], and cleared when the outermost section closes and
  /// lets it through. The job does not accept it meanwhile — [pendingCancel]
  /// stays `null` — so this is the only place such a request shows. A
  /// cancellation the job cannot refuse is not held: the job accepts it at
  /// once, and the one held until then is dropped and cleared here. So is one a
  /// section the body walked away from still holds when the body cancels itself
  /// or the job ends: it would land on a job already cancelled or over. And so
  /// is the request of the job's own deadline once the body and the children
  /// are over: the deadline ends there, and a rejectable request that arrived
  /// behind it shows here in its place.
  @protected
  Cancelled? get heldCancel => _heldCancel;

  /// Opens an uncancellable section: a rejectable cancellation arriving
  /// now is held, and the job accepts it only when the section closes.
  /// Sections nest.
  @protected
  void enterUncancellable() => _uncancellableDepth++;

  /// Closes a section opened by [enterUncancellable] and lets a held
  /// cancellation through — the outermost section is the one that lands
  /// it, and a job that finished meanwhile ignores it as it would any
  /// other late cancellation.
  @protected
  void leaveUncancellable() {
    if (--_uncancellableDepth > 0) {
      return;
    }
    final held = _heldCancel;
    if (held == null) {
      return;
    }
    _heldCancel = null;
    _heldBehindTimeout = null;
    cancelWith(held);
  }

  /// The children this job waits for, in the order they were adopted;
  /// read-only.
  ///
  /// A copy taken at the call, not a view: a child that finishes after it
  /// is still in the list, and one adopted after it is not.
  ///
  /// The way in is [JobContextBase.startChild] alone, which [JobContext.run],
  /// [JobContext.runAll] and [JobContext.each] go through: it sets the parent,
  /// the level and the observer of the child, and nothing else may put a job on
  /// this list — the core would wait for a child it never adopted.
  @protected
  List<JobBase<Object?>> get children => UnmodifiableListView(_childrenNow());

  /// The chain of children as it is now, first adopted first.
  ///
  /// A list of its own: whoever walks it may end a child, and a child that
  /// ends takes itself off the chain.
  List<JobBase<Object?>> _childrenNow() {
    final children = <JobBase<Object?>>[];
    for (var child = _firstChild; child != null; child = child._nextSibling) {
      children.add(child);
    }
    return children;
  }

  /// Puts [child] at the end of the chain.
  ///
  /// Whole or not at all: the stack may run out at the door of this call or
  /// of the one it begins with, before anything is written, and past that
  /// there are only stores.
  void _waitFor(JobBase<Object?> child) {
    // A handle whose start was cut short is still on the chain of the job
    // that started it, and is started again here: by that job or by
    // another.
    child._waitedForBy?._stopWaitingFor(child);
    // Asserted, so an edit that ever leaves the child where it stood shows
    // up as the defect it is: linked below to itself, it would make every
    // walk of the chain endless.
    assert(child._waitedForBy == null, '$child is on a chain already');
    final last = _lastChild;
    child
      .._previousSibling = last
      .._waitedForBy = this;
    if (last == null) {
      _firstChild = child;
    } else {
      last._nextSibling = child;
    }
    _lastChild = child;
  }

  /// Takes [child] off the chain, if it is on it.
  void _stopWaitingFor(JobBase<Object?> child) {
    if (!identical(child._waitedForBy, this)) {
      return;
    }
    final previous = child._previousSibling;
    final next = child._nextSibling;
    if (previous == null) {
      _firstChild = next;
    } else {
      previous._nextSibling = next;
    }
    if (next == null) {
      _lastChild = previous;
    } else {
      next._previousSibling = previous;
    }
    child
      .._previousSibling = null
      .._nextSibling = null
      .._waitedForBy = null;
  }

  /// Waiting without observing: an engine waits for a job to finish
  /// without marking its outcome observed, so a failure nobody looked at
  /// still reaches the zone. Code outside an engine registers with
  /// [whenFinished] instead.
  @protected
  Future<void> get untilFinished => _done.future.then((_) {});

  /// The zone the job was created in, where an unobserved failure of the
  /// job goes.
  ///
  /// An engine that starts a job later, from a queue, starts it here, as
  /// `creationZone.run(start)`: the queue runs in the zone of whatever woke
  /// it, and a body started from there takes that zone's timers, values
  /// and error handler for its own.
  ///
  /// For a job made inside the work of [JobContext.unattended] this is the
  /// zone that work was started from, the one [start] moves to out of the
  /// fork; when the work of one job runs inside the work of another, it is
  /// the zone the outer work was started from. It is not the fork, the zone
  /// current at creation: the fork carries the job that started the work,
  /// and an engine that kept it would hold that job for as long as it kept
  /// the fork.
  @protected
  Zone get creationZone => _zone;

  /// Runs the body.
  ///
  /// The job starts in the zone this is called from: its body runs there, and
  /// so do [started] and the observer's `onStart`. Called inside the work of
  /// [JobContext.unattended], it starts in the zone that work was started
  /// from, past any zone forked inside the work, as a job made in there does:
  /// a job is not that work, and its errors are not the observer's of the job
  /// that started it.
  ///
  /// Throws [StateError] if the job already ran, and also if it was cancelled
  /// before it started: a job dropped then is finished, and a finished job does
  /// not run. Nor does one ended while [createContext] built its context, and
  /// then this returns without a word: that end was the engine's own.
  @protected
  void start() {
    // Inside the work of `JobContext.unattended` the whole start moves out,
    // not the body alone: `started` and `onStart` are the job's own too, and
    // a hook that throws in the work would report to the observer of the job
    // that started it. To the zone the work was started from, the one a job
    // made in there reports to. Through `run`, not a microtask: the job
    // starts now, as it does anywhere else, and a `StateError` still reaches
    // the caller.
    final outsideTheWork = Zone.current[_unattendedKey] as Zone?;
    if (outsideTheWork == null) {
      _start();
    } else {
      outsideTheWork.run(_start);
    }
  }

  void _start() {
    if (_status != JobStatus.created) {
      throw StateError(
        _status == JobStatus.running
            ? '$this is already running'
            : '$this has already finished',
      );
    }
    // Built before the job is running: a context that throws on creation
    // leaves the job as it was, and not running with no body.
    final ctx = createContext();
    if (_status != JobStatus.created) {
      // Ended while the context was being built -- an engine asked a rule there
      // and cancelled, or finished the job by hand. It has its outcome, and a
      // finished job does not run.
      return;
    }
    _status = JobStatus.running;
    // Armed before `started`, in the zone of the start: an engine that ends
    // the job by hand from there goes through `finish`, which lifts it, and
    // one armed after that would wait for a job already over.
    final timeout = _timeout;
    if (timeout != null) {
      _timeoutTimer = Timer(timeout, _timeoutRanOut);
    }
    // Guarded as `finished` is: the job is running by now, and an error of
    // the engine's bookkeeping left to escape would leave it running with
    // no body, and nothing would ever finish it.
    try {
      started();
    } on Object catch (error, stackTrace) {
      notifyError(error, stackTrace);
    }
    _notifyStart();
    final routine = _execute(ctx);
    // By a store, before anything is called again: a call may find no
    // stack, and the routine has returned whether or not one does.
    _startReturned = true;
    unawaited(routine);
    if (_tornError != null) {
      // The synchronous part of the routine was cut short and left where it
      // stood. Thrown to whoever started the job, the way an overflow
      // anywhere else in the start reaches them.
      _throwTorn();
    }
  }

  Never _throwTorn() => Error.throwWithStackTrace(_tornError!, _tornTrace!);

  Never _throwWhatEndedTheBody() {
    final ended = _bodyOutcome! as Failed;
    Error.throwWithStackTrace(ended.error, ended.stackTrace);
  }

  /// The deadline ran out: an ordinary rejectable cancellation, with a
  /// reason of its own and the trace of the constructor.
  void _timeoutRanOut() {
    _timeoutTimer = null;
    final reason = TimeoutCancelReason(_timeout!);
    _timeoutReason = reason;
    // Caught: the cascade is recursive and an engine may throw from its
    // `cancelWith`, and nobody called this callback to hand the error to. Left
    // to escape, it would reach the zone of the start and no observer; caught,
    // it goes out the door `_execute` sends such an error through after a
    // cascade: the observer, else the zone of the job.
    try {
      cancelWith(
        Cancelled.by(
          reason: reason,
          stackTrace: _timeoutTrace,
        ),
      );
    } on Object catch (error, stackTrace) {
      notifyError(error, stackTrace);
    }
  }

  /// Whether [cancelled] is the request of this job's own deadline.
  bool _isOwnTimeout(Cancelled cancelled) {
    final reason = _timeoutReason;
    return reason != null && identical(cancelled.reason, reason);
  }

  /// Lifts the deadline: the body and the children are over.
  ///
  /// The request of the deadline a section still holds goes too — a section
  /// the body left running would otherwise land it in the cleanup or at a
  /// barrier of a group — and a request that came behind it takes its place.
  void _liftTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final held = _heldCancel;
    if (held != null && _isOwnTimeout(held)) {
      _heldCancel = _heldBehindTimeout;
      _heldBehindTimeout = null;
    }
  }

  /// Ends the job with [outcome].
  ///
  /// On a job that has already finished the outcome stays, the same as with
  /// [cancel]: an outcome is final, and an engine racing its own body must not
  /// be able to replace one. A [Failed] handed in there has no outcome to carry
  /// it, and it goes where the errors with no outcome go: to
  /// [JobObserver.onError] and to the answer of the observer — the zone unless
  /// it is a [JobAnswerer] — or to [JobObserver.onError] alone once
  /// [Job.ignoreFailure] was called.
  ///
  /// Ending a job that is still running is not a way to cancel it: this waits
  /// for no children and unwinds no cleanup stack, so everything the body
  /// opened stays open. Cancel with [cancelWith] instead, and let the body
  /// unwind; how many cleanups were left behind is in the debug trace. A
  /// failure of the body, thrown before this or after, is in no outcome then,
  /// unless it is the one handed in: [JobObserver.onError] hears it where the
  /// body is caught, and it goes on to the answer, as a failure of the body of
  /// a cancelled job does.
  ///
  /// A branch of [JobContext.runAll] that ends with a [Done] handed in after
  /// its group heard that its body failed is the exception. The value comes too
  /// late for the group: it goes by the failure, as if the branch had ended
  /// with it, and throws it, or answers for it as for any failure of a branch
  /// it does not throw, and the value stays in the outcome of the branch alone.
  /// The group hears of the failure right after [JobObserver.onError] does, or,
  /// for a body that is not `async` and threw while [JobContext.runAll] was
  /// starting the branches, once it has started them all. A value handed in
  /// before that, from `onError` too, is what the group goes by, and the branch
  /// answers for the failure itself.
  ///
  /// A [Failed] handed in is announced here: [JobObserver.onError] hears it
  /// once, before [finished] and [JobObserver.onFinish]. Unlike a failure
  /// of the body, which is announced while the job still runs, it is
  /// announced after the job is over, so an `onError` that cancels finds
  /// it finished and the outcome stays [Failed]. If nobody then observes
  /// the outcome, the error reaches the zone as any [Failed] does. Do not
  /// call [notifyObserver] for it first: the observer would hear it twice.
  /// An error the core has announced for this job already — one its body
  /// threw — is not announced again.
  ///
  /// A job that has accepted a cancellation ends with that cancellation,
  /// whatever is handed in. A [Done] is replaced, and its value goes nowhere
  /// and is closed by nobody: release it before calling this. A [Failed] is
  /// replaced too, and its error goes where a failure of the body of a
  /// cancelled job goes — to [JobObserver.onError] and on to the answer, unless
  /// [Job.isCancellationError] names it. A [Cancelled] handed in stands.
  ///
  /// A [Cancelled] handed in here or to [cancelWith] belongs to this job
  /// alone. The parent finds the child behind a cancellation by the
  /// instance, and with one instance for two of its children — a `const`
  /// one is one for the whole program — it names the child that ended last.
  /// With asserts on, the second of them ends as it does without them, and
  /// an [AssertionError] goes to the zone it was created in.
  ///
  /// An override calls `super.finish`: this is where the job gets its
  /// outcome, and without it the job never ends.
  @protected
  @mustCallSuper
  void finish(Outcome<T> outcome) {
    if (_status == JobStatus.finished) {
      // The outcome stays. A failure handed in now has no outcome to carry
      // it — a rule of a domain that ended the job and then threw looks
      // like that — and dropped here it would be heard by nobody.
      if (outcome is Failed && !_wasAnnounced(outcome.error)) {
        _noteAnnounced(outcome.error);
        _reportCovered(outcome, announced: false);
      }
      return;
    }
    // A marked job does not end with a value. `isCancelled`, `check` and
    // `whenCancelled` have been reporting that cancellation since the
    // mark went on, and a `Done` or a `Failed` handed in afterwards would
    // leave the handle contradicting itself for good -- cancelled and
    // `Done(42)` at the same time. So the mark decides those.
    //
    // A [Cancelled] handed in is not that: the handle stays coherent, and an
    // engine ending a job from inside the cascade says how it ended it -- that
    // description is the whole diagnosis it has. The route of the core hands
    // the mark in itself, so nothing here is about it.
    final decided =
        outcome is Cancelled ? outcome : (_pendingCancel ?? outcome);
    final replaced = identical(decided, outcome) ? null : outcome;
    if (replaced != null) {
      _debug(
        () => '$this was finished as $replaced and ends $decided: '
            'the cancellation it accepted decides',
      );
    }
    if (_cleanups.isNotEmpty) {
      _debug(
        () => '$this finished with ${_cleanups.length} cleanups pending',
      );
    }
    _outcome = decided;
    _status = JobStatus.finished;
    // A value a branch of a group is handed by hand, if it is the outcome: a
    // cancellation the branch accepted turns it away. The group goes by what it
    // heard first, and a failure of the body it heard of is what it throws or
    // answers for -- see [_RunAllGroup._takeFailure]. Asked here, among the
    // stores, before any code that is not the core's runs.
    if (decided is Done) {
      _failureWentToGroup = _hold?.takeFailure() ?? false;
    }
    // A section the body walked away from may still hold a cancellation;
    // it would land on a job that is over, which drops it.
    _heldCancel = null;
    _heldBehindTimeout = null;
    // However the job ended — the core's route has lifted the deadline already,
    // an engine ending it by hand has not.
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    // The list of children is a waiting list, so it shrinks; the link from
    // an outcome to the child that carried it lives on, in the parent's
    // `Expando`. Both happen here, where they are observable: in `finished`
    // and in `onFinish` the parent's list is already without this child.
    _waitedForBy?._stopWaitingFor(this);
    final parent = _parent;
    JobBase<Object?>? endedWithTheSame;
    if (parent != null) {
      if (decided is Cancelled) {
        assert(
          () {
            endedWithTheSame = parent._outcomeChild[decided];
            return true;
          }(),
          'never fails: it reads the entry the next line replaces',
        );
        parent._outcomeChild[decided] = this;
      }
    }
    // A failure an engine hands in has been told to nobody, unless the body
    // threw the same error first. Announced here, once the job is over, so an
    // `onError` that cancels finds a finished job instead of marking one that
    // is about to end `Failed`; and before `finished`, so the observer hears
    // the error before the engine's bookkeeping and `onFinish`. One handed in
    // over the mark goes the way of a failure of the body of a cancelled job,
    // below.
    if (decided is Failed &&
        replaced == null &&
        !_wasAnnounced(decided.error)) {
      _noteAnnounced(decided.error);
      notifyObserver(decided.error, decided.stackTrace);
    }
    // Guarded: the hook belongs to an engine, and its error must not stand
    // between the job and its outcome — an unfinished job holds its parent, its
    // waiters and the engine itself forever.
    try {
      finished();
    } on Object catch (error, stackTrace) {
      notifyError(error, stackTrace);
    }
    _notifyFinish();
    // Nothing will call them: `cancelWith` turns around on a finished job.
    // They hold whatever the body gave them — a subscription, a buffer, a
    // token — for as long as anyone holds the handle.
    _onCancel.clear();
    // Nor will anything run the cleanups of a job an engine ended by hand
    // before its unwinding: the core's route turns around on a job that is
    // over. Inside the unwinding the routine that runs the stack is still
    // alive; it reads what is left and lets go of it itself, and the
    // registrations put aside exist only in there.
    if (!_disposing) _cleanups.clear();
    _done.complete(decided);
    // Notify only after the domain has detached this job and delivered its
    // finish hooks: a synchronous subscriber may immediately add more work.
    if (decided is Cancelled) _notifyCancelled(decided);
    _cancelListeners.clear();
    _notifyFinished(decided);
    // Let go of the graph. The handle stays -- it is kept precisely to be read
    // later, by a controller holding the last job, by a widget, by a journal --
    // but nothing it reached through is of any use now: the parent chain leads
    // to jobs that are over, the group of [JobContext.runAll] has taken its
    // verdict and what it goes by, and the outcome of the body has become the
    // outcome, or is the body's route's own to answer for. Held on, these turn
    // one handle in a field into the whole tree it came out of, every closure
    // that tree captured and an error with everything it references.
    _parent = null;
    _hold = null;
    _bodyOutcome = null;
    if (decided is Failed && !_observed) {
      _reportUnobserved(decided);
    }
    // A failure handed in over the mark. The cancellation decides the outcome,
    // but an error is never lost silently: it goes where a failure of the body
    // of a cancelled job goes. It came in here and not through the body, so
    // nobody has announced it yet — unless the body threw this very error, and
    // then the body's route answers for it.
    if (replaced is Failed && !_wasAnnounced(replaced.error)) {
      _noteAnnounced(replaced.error);
      _reportCovered(replaced, announced: false);
    }
    // Said and not thrown, and last of all: the job has ended the way it
    // ends with asserts off. Thrown from here, it would leave through the
    // routine of a job whose engine handed the instance to `cancelWith`,
    // and take the rest of that routine with it.
    if (endedWithTheSame case final other?) {
      _notify(
        () => _toZone(
          AssertionError(
            '$decided ended two children of $parent, $other and $this: a '
            'Cancelled an engine ends a job with belongs to that job, build '
            'one for each',
          ),
          StackTrace.current,
        ),
      );
    }
  }

  /// Announces [error] to the observer and asks nobody to answer for it.
  ///
  /// For an error that has an outcome of its own — the body's. It reaches the
  /// zone through that outcome, if nobody observes it, and shouting twice about
  /// one error is worse than once. When the job ends [Cancelled], the outcome
  /// does not carry it, and it is answered later without being announced again
  /// — unless [Job.ignoreFailure] was called or [Job.isCancellationError] names
  /// it, and then nobody answers for it. A [Failed] an engine hands to [finish]
  /// needs no call here: [finish] announces it itself. [notifyError] starts
  /// here too, and goes on to the answer.
  ///
  /// The observer is told about one error at a time: a `ParallelWaitError` is
  /// walked as [Job.visitErrors] walks it, and each failure and each
  /// cancellation inside it gets a call of its own, with its own stack trace.
  /// The job's own cancellation inside one is left out: the outcome says it.
  @protected
  void notifyObserver(Object error, StackTrace stackTrace) {
    _debug(() => '$this error: $error');
    final observer = _observer;
    if (observer == null) {
      return;
    }
    // One call for each error, each guarded on its own. A cancellation is
    // told like a failure: this hook is the only place that hears one.
    void tell(Object error, StackTrace stackTrace) =>
        _notify(() => observer.onError(this, error, stackTrace));
    _visitErrors(
      error,
      stackTrace,
      onFailure: tell,
      onCancelled: (cancelled, cancelledStackTrace) {
        // The job's own cancellation inside an envelope is not news: the
        // outcome says it. One that comes alone was thrown by a callback,
        // and that is told.
        if (identical(cancelled, error) ||
            (!identical(cancelled, _pendingCancel) &&
                !identical(cancelled, _outcome))) {
          tell(cancelled, cancelledStackTrace);
        }
      },
    );
  }

  /// Announces [error] and asks for an answer to it.
  ///
  /// For the errors that have nowhere else to go: an action abandoned by
  /// [JobContext.abandonable] failing later, a disposer, a callback of
  /// [JobContext.onCancel], [Job.whenCancelled] or [Job.whenFinished], work
  /// handed over with [JobContext.unattended]. The observer hears it through
  /// [JobObserver.onError], and one that is a [JobAnswerer] answers for it
  /// through [JobAnswerer.onUnanswered], whose default body sends it to the
  /// zone the job was created in; without such an observer the error goes to
  /// that zone directly. Two calls, each guarded on its own: an `onError` that
  /// throws does not cost the error its answer. Both go by the walk of
  /// [Job.visitErrors]: `onError` is told about each error inside a
  /// `ParallelWaitError` on its own, and the answer is asked for each failure.
  ///
  /// A cancellation — a [Cancelled], or a `ParallelWaitError` carrying
  /// nothing but cancellations — never reaches the zone from here, and
  /// nobody is asked to answer for it: it is a decision somebody made, not a
  /// failure. An observer hears it through `onError`; without one, nobody
  /// does. Nor is anybody asked about a failure that [Job.isCancellationError]
  /// names, once the job has accepted a cancellation.
  @protected
  void notifyError(Object error, StackTrace stackTrace) {
    notifyObserver(error, stackTrace);
    _handleUnanswered(error, stackTrace);
  }

  /// Hands [error] to the zone the job was created in, unless it is a
  /// cancellation.
  ///
  /// For an engine whose own answer for an error with nowhere to go ends with
  /// the zone: `solo`, for example, sends one here when neither an override of
  /// `Solo.onUnanswered` nor `Solo.unansweredHandler` took it. The core reaches
  /// the zone by itself, through the default body of
  /// [JobAnswerer.onUnanswered], through [notifyError] without an observer that
  /// answers and through an unobserved [Failed]. A cancellation is held back
  /// here as it is there, so an engine does not write that rule again.
  @protected
  void reportToZone(Object error, StackTrace stackTrace) =>
      _toZone(error, stackTrace);

  /// Answers for [error] without announcing it.
  ///
  /// The observer's [JobAnswerer.onUnanswered], or the zone the job was created
  /// in when the observer does not answer or there is none. [notifyError] ends
  /// here, and so do three failures of a body: that of a branch of
  /// [JobContext.runAll] the group did not throw, that of a job that ends
  /// [Cancelled], and that of a job an engine ended by hand with an outcome of
  /// its own, unless [Job.ignoreFailure] was called on the job. The last is the
  /// group's when the group took that failure in place of a value handed in
  /// after the group heard of it (see [_failureWentToGroup]), and comes here
  /// only as the first, when the group does not throw it. The job told its
  /// observer itself, where its body was caught, and one error is announced
  /// once — but an error nobody answered for still has to reach somebody.
  ///
  /// The answer is asked for one failure at a time: a `ParallelWaitError` is
  /// walked as [Job.visitErrors] walks it, each failure in it goes to the
  /// observer or to the zone with its own stack trace, and a cancellation
  /// goes to neither. Nor does a failure [Job.isCancellationError] names,
  /// once the job has accepted a cancellation: it is asked about each failure
  /// of such a job here, and only here, so that [JobObserver.onError] has
  /// heard it like any other.
  ///
  /// An engine answers through the observer it puts on its jobs, as `solo`
  /// does: there is no second door.
  void _handleUnanswered(Object error, StackTrace stackTrace) {
    final observer = _observer;
    // Read once for the whole walk, and only for a job that has accepted a
    // cancellation: what the filter names is an error the cancellation of
    // this job stopped, and a job nobody cancelled has none.
    final isCancellationError = isCancelled ? Job.isCancellationError : null;
    var said = false;
    // One answer for each failure, each guarded on its own: an answer that
    // throws does not cost the next failure its own.
    _visitErrors(
      error,
      stackTrace,
      onFailure: (failure, failureStackTrace) {
        if (isCancellationError != null &&
            _askIsCancellationError(isCancellationError, failure)) {
          _debug(
            () => '$this kept a cancellation error out of the answer: '
                '$failure',
          );
          return;
        }
        if (!said) {
          said = true;
          _debug(() => '$this error nobody answered for: $error');
        }
        if (observer is JobAnswerer) {
          try {
            observer.onUnanswered(this, failure, failureStackTrace);
          } on Object catch (hookError, hookStackTrace) {
            // The answer is the channel here, not the fact, and a broken
            // channel is a second problem rather than a reason to lose the
            // first: nothing else holds this error. Both reach the zone,
            // this one first; a cancellation the answer throws stays out,
            // and so does the error itself thrown back, which is there once.
            _toZone(failure, failureStackTrace);
            if (!identical(hookError, failure)) {
              _hookErrorToZone(hookError, hookStackTrace);
            }
          }
        } else {
          _toZone(failure, failureStackTrace);
        }
      },
    );
  }

  /// What [isCancellationError] says of [failure], and `false` when it
  /// throws.
  ///
  /// Its error is the caller's code failing, not this job's, and nobody is
  /// asked about it: it goes to the zone the job was created in, past the
  /// answer of the job, and a cancellation is dropped there. Not to the
  /// current zone: the answer may be asked for from work handed over with
  /// [JobContext.unattended], whose zone hands what reaches it back to the
  /// answer of this job.
  bool _askIsCancellationError(
    bool Function(Object error) isCancellationError,
    Object failure,
  ) {
    try {
      return isCancellationError(failure);
    } on Object catch (error, stackTrace) {
      _toZone(error, stackTrace);
      return false;
    }
  }

  /// Whether [error] is a cancellation and stays out of the zone: a
  /// [Cancelled], or a `ParallelWaitError` carrying nothing but
  /// cancellations.
  static bool _isCancellation(Object error) {
    if (error is Cancelled) {
      return true;
    }
    final envelope = _analyzeEnvelope(error);
    return envelope != null && envelope.isCleanCancellation;
  }

  /// The one door to the zone for an error with nowhere else to go.
  ///
  /// A cancellation does not go through it. A cancellation is a decision
  /// somebody made, not a failure; the one that ends this job has been
  /// heard on the outcome already, and any other has an owner of its own.
  /// In Flutter the zone is `PlatformDispatcher.onError`, and a
  /// cancellation reaching it says nothing anybody can act on.
  ///
  /// The route of an unobserved [Failed] is not this one and keeps its own
  /// rule: there the outcome decides, not the object it carries, so a failure
  /// somebody built out of a [Cancelled] on purpose still reaches the zone. A
  /// failure the outcome does not carry — of a branch the group did not throw,
  /// or of the body of a job that ends [Cancelled] — has no outcome to decide,
  /// comes this way, and such a [Cancelled] stays out.
  void _toZone(Object error, StackTrace stackTrace) {
    if (_isCancellation(error)) {
      _debug(() => '$this kept a cancellation out of the zone: $error');
      return;
    }
    _debug(() => '$this error went to the zone: $error');
    _zone.handleUncaughtError(error, stackTrace);
  }

  /// The subclass joins the run.
  ///
  /// Called with the job already [JobStatus.running]. An error thrown here
  /// goes to [notifyError] and the body runs all the same, but the engine of
  /// the domain is left half-way through its own bookkeeping: keep it short
  /// and unconditional. `solo`, for example, adds the job to its running list
  /// here.
  @visibleForOverriding
  void started() {}

  /// The subclass leaves the run.
  ///
  /// Called for every job that gets an outcome, including one dropped before
  /// its body ever ran — then there was no [started] to match it. An error
  /// thrown here goes to [notifyError] and the job finishes all the same, but
  /// the engine is left half-way through its own bookkeeping: keep it short
  /// and unconditional. `solo`, for example, clears `current` here and moves
  /// its queue on.
  @visibleForOverriding
  void finished() {}

  /// The child's own word on who may adopt it. Empty here:
  /// [JobContextBase.startChild] has already checked that the child is a job of
  /// this core.
  ///
  /// To refuse, throw — an [ArgumentError] for a parent that may not have this
  /// child, a [StateError] for a child that is spoken for. The error comes out
  /// of the call that asked — for [JobContext.runAll], once the branches it
  /// already started have stopped — before the child has a parent, and the
  /// child stays `created`.
  @visibleForOverriding
  void adoptedBy(JobContextBase parent) {}

  /// The context this job hands to its body.
  @visibleForOverriding
  JobContextBase createContext();

  /// Runs the body with [ctx]; a subclass narrows the type with
  /// `covariant`.
  @visibleForOverriding
  Future<T> execute(JobContextBase ctx);

  void _notifyStart() {
    _debug(() => '$this started');
    _notify(() => _observer?.onStart(this));
  }

  void _notifyFinish() {
    _debug(() => '$this finished: $_outcome');
    _notify(() => _observer?.onFinish(this));
  }

  void _notifyLog(Object? message) =>
      _notify(() => _observer?.onLog(this, message));

  /// The routine of a job, from the body to [finish].
  ///
  /// No loop stands here. Thousands of jobs let go together sleep in this
  /// routine at once, and under JIT a frame that went to sleep in
  /// unoptimized code wakes up in it. At the header of a loop such a frame
  /// asks the VM to replace it with optimized code, and the VM compiles the
  /// whole routine again for that one frame: two milliseconds or so for a
  /// routine this big, once for every job that wakes up there. Moving a loop
  /// out does not settle it by itself, and only a measure does: one big
  /// local function took 30 000 branches of `let_go_together_test.dart` 13 s,
  /// and a loop of a few lines in a small local one took 30 000 jobs waking
  /// in it 6 to 8.5 s. The loop of [_unwind] costs nothing there, under
  /// 0.4 s and no replacement asked. So the only loop that sleeps over the
  /// cleanup stack is the one of [_unwind]; the one of [_nextCleanup] never
  /// awaits. The local functions below go round through [_unwind], and each
  /// of these places is held by its own test in that file.
  Future<void> _execute(JobContextBase? ctx) async {
    try {
      _routineEntered = true;
      Outcome<T> outcome;
      // The body cancelled itself: the children go, the same as they do for a
      // job cancelled from outside. Not from inside the `catch`: the cascade
      // runs the callbacks of the children, which is the caller's code, and it
      // must find a parent that already refuses to start anything.
      Cancelled? selfCancelled;
      // Whether the error the body threw was announced before it threw it: an
      // engine handed that very error to [finish], and it was answered for
      // there. The body's route does not answer for it again. The first pass of
      // a start cut short announces it too, but answers for nothing: the second
      // pass throws it again on a job still running.
      var announcedBefore = false;
      // The outcome of a body that threw [cancelled]: the mark if there is
      // one, and otherwise the body's own cancellation.
      Cancelled ownCancellation(Cancelled cancelled, StackTrace stackTrace) {
        if (_pendingCancel case final pending?) {
          return pending;
        }
        final own = _handlerCancel(cancelled, stackTrace);
        // Read again: putting the cancellation into words runs the caller's
        // code -- the child's `toString`, with its key and `describe` or an
        // engine's own, and `onError` when that throws -- and code that
        // cancels this job in between marks it with its own reason, which
        // `whenCancelled` then hears. That one stands.
        return _pendingCancel ?? (selfCancelled = own);
      }

      try {
        if (ctx == null) {
          // The second time round, on a stack of its own: the start was cut
          // short, and the parent has come back for this job. The body is
          // over, or never began, and it is not asked again. It ended with
          // what the parent found written down for it: its own failure if
          // the first pass got that far, and what cut the start short
          // otherwise.
          _throwWhatEndedTheBody();
        }
        final value = await execute(ctx);
        if (_isVoid && _neverStartedDeferredJob(value)) {
          // `void` takes any value, so the analyzer lets a body hand back a
          // deferred child it meant to run: nothing here starts it or waits for
          // it, and unless somebody else does, the work in it is lost without a
          // word. Only a deferred job is refused: one made by `Job(...)`, a
          // continuation or a job an engine has queued is still `created` for a
          // while, and starts without anyone telling it to. A wider type keeps
          // the handle: there it may be the value.
          throw ArgumentError(
            '$this returned $value, a deferred job that never started; '
            'run it with ctx.run or start it',
          );
        }
        outcome = Done(value);
      } on Cancelled catch (cancelled, stackTrace) {
        outcome = ownCancellation(cancelled, stackTrace);
      } on Object catch (error, stackTrace) {
        final envelope = _analyzeEnvelope(error);
        if (envelope != null && envelope.isCleanCancellation) {
          outcome = ownCancellation(
            envelope.firstCancelled!,
            envelope.firstStackTrace!,
          );
        } else {
          final announced = _wasAnnounced(error);
          announcedBefore = announced && isFinished;
          if (!announced) {
            _noteAnnounced(error);
            notifyObserver(error, stackTrace);
          }
          outcome = Failed(error, stackTrace);
        }
      }
      // The body has ended: from here a value coming out of a call it walked
      // away from can no longer reach it, and no child is started any more.
      _bodyEnded = true;
      _bodyOutcome = outcome;
      if (selfCancelled != null) {
        // Marked before the children are waited for, and only marked. The body
        // cancelled itself, so from here the job is cancelled to anyone who
        // asks -- `isCancelled`, `check`, a `cancel()` from outside -- and the
        // decision it made is the one that stands: `cancelWith` turns around at
        // its own early return instead of laying another reason over this one.
        // Without the mark that whole wait was a window: `isCancelled` answered
        // `false`, a cancellation arriving in it won by `??=`, and the children
        // were left carrying a cause their parent never had.
        //
        // And marked before the group below hears of it: asking the siblings
        // to stop runs their `onCancel` callbacks, which are the caller's
        // code, and one that cancels this job must find the decision already
        // made. Marked after, that `cancelWith` would mark the job with its
        // own reason, `whenCancelled` would hear that one, and the outcome
        // would carry the body's.
        _pendingCancel = selfCancelled;
        // A cancellation a section still holds would land on a job already
        // cancelled, and `cancelWith` turns such a one around: it never
        // lands, so `heldCancel` stops naming it.
        _heldCancel = null;
        _heldBehindTimeout = null;
      }
      // The early word of a branch to its group: the siblings are asked to stop
      // while this one is still waiting for its own descendants. It hands
      // nothing over, and decides only that a value an engine hands in after it
      // comes too late for the group — see [_RunAllGroup._takeFailure]. What
      // comes out of a group is settled by the final outcomes, later and
      // elsewhere. After the classification and not before it: a clean envelope
      // thrown by a child is a cancellation here, not a failure.
      _hold?.bodyEnded(outcome);
      if (selfCancelled case final cancelled?) {
        // The rest of what `cancelWith` does, in its order: the children are
        // asked first, then the `onCancel` callbacks run and `whenCancelled`
        // hears it. A job whose body cancels itself no longer needs what the
        // body started any more than one cancelled from outside does.
        try {
          try {
            _cascadeToChildren(cancelled);
          } finally {
            // Skipped when a callback of a child reached the engine and it
            // ended the job by hand, as in `cancelWith`.
            if (_status != JobStatus.finished) {
              _markCancelled(cancelled);
            } else {
              _outOfStack = false;
            }
          }
        } on Object catch (error, stackTrace) {
          // The cascade is recursive, and a deep enough tree overflows the
          // stack inside it; a callback a domain registered unguarded may
          // throw. Here there is nobody to hand that to: the outcome is
          // decided, the job still has to wait for its children and unwind
          // its cleanup stack, and an error thrown out of `_execute` would
          // leave it running for good. It goes out the one door for an
          // error with nowhere else to go.
          notifyError(error, stackTrace);
        }
      }
      if (!_startReturned) {
        // The body never left the stack it was entered on: it threw before
        // its first `await`. That stack belongs to the start of this job,
        // and it may be the one that ran out. The rest is done on a stack
        // of its own.
        await null;
      }
      await _awaitChildren();
      if (isFinished) {
        // An engine ended the job by hand while the body was playing out: the
        // outcome is not ours, the children were not waited for, and the stack
        // is not unwound -- `finish` let go of it. A failure of the body still
        // has to be answered for.
        _answerForHandFinished(outcome, announcedBefore: announcedBefore);
        return;
      }
      // The deadline bounds the body and the children, and ends here. Past
      // this point come the cleanup stack and the barriers of a group, and a
      // cancellation landing there turns the outcome of a job that did its
      // work into `Cancelled` and closes its value through `discard`.
      _liftTimeout();
      // The outcome is decided, and the mark is already on: the body either
      // caught the one that was there or cancelled itself and was marked above.
      // Asserted rather than assigned, so a path that ever arrives here
      // unmarked shows up as the defect it is instead of quietly changing the
      // reason the job ends with. Nothing is told here: both paths told
      // everyone when the mark went on.
      if (outcome is Cancelled) {
        assert(
          identical(_pendingCancel, outcome),
          'a cancelled body reaches its outcome marked',
        );
      }
      final hold = _hold;
      if (hold != null) {
        // The first barrier. The body is over, the descendants are done and
        // the outcome is counted — but it is not final, and nothing has
        // looked at the cleanup stack yet. The group gathers every branch
        // here before any of them starts unwinding.
        //
        // The hold is deliberate. It is what lets a branch that returned a
        // value close it through `discard` when a sibling fails later: let
        // go, the branch would hand the value to a group that hands it to
        // nobody. Its price is the hang of a branch waiting for a sibling,
        // or for what a sibling releases in its cleanup, which the dartdoc
        // of `runAll` names. A core change that unwinds a branch before
        // this barrier has been tried and did not converge; the hang stays
        // documented, not fixed.
        await hold.beforeDisposal();
        if (isFinished) {
          // An engine ended the branch by hand while it stood there. A bare
          // `return` would leave the phase where it is, and the job would read
          // as disposing for good. Nothing is put aside yet -- the passes below
          // are what fill that list -- so there is nothing to say on the debug
          // channel either.
          _disposing = false;
          _answerForHandFinished(outcome, announcedBefore: announcedBefore);
          return;
        }
      }
      // Whether a conditional registration has to be passed over: its value
      // went to somebody. A group overrides this one way only — towards
      // success. A branch that refused the group's cancellation and ends
      // [Done] hands its value over through [Job.value] all the same, and a
      // group that failed must not close what that branch is about to give.
      bool valueHandedOver() =>
          _committedByGroup || (_pendingCancel ?? outcome) is Done<T>;

      // The tail, from the last look at the cleanup stack to the end. Called
      // in the same turn as that look: an `await` between the two would
      // widen the window after `return` by a microtask.
      void conclude() {
        // Whatever is still put aside will never run: the passes drain the
        // list for every outcome but [Done], and a [Done] is what put them
        // there. Left behind, they would hold their values and their
        // closures for as long as anyone holds the handle — the job is
        // over, and the list is a field now, not a local that dies with the
        // call.
        final sayDropped = _droppedCleanupsTrace();
        _skipped.clear();
        _disposing = false;
        final decided = _pendingCancel ?? outcome;
        // An engine may have ended the job by hand while the stack unwound --
        // from a cleanup, or while one was awaited. The outcome is the engine's
        // then, and nothing is handed to `finish`: on a finished job it would
        // answer for a failure of the body, and the answer below does that
        // already.
        final endedByHand = isFinished;
        if (!endedByHand) finish(decided);
        // Said after `finish` and not before: the debug channel is the
        // caller's code, and so are `describe` and `toString` that build the
        // line. One that cancels this job there would land between the
        // dropped registrations and the outcome — the job would end
        // `Cancelled` with its `discard` gone and its value with nobody.
        // After `finish` the cancellation finds the job over.
        sayDropped?.call();
        // After `finish`, not before, and on the spot. `finished` and
        // `onFinish` run first, and an engine may still call
        // [Job.ignoreFailure] there; a parent's body hears the cancellation
        // only after the answer. Reading the outcome settles nothing here, so
        // there is no window to wait for.
        if (endedByHand) {
          _answerForHandFinished(outcome, announcedBefore: announcedBefore);
        } else if (outcome is Failed && !identical(decided, outcome)) {
          _reportCovered(outcome, announced: true);
        }
      }

      if (_cleanups.isEmpty && hold == null) {
        conclude();
        return;
      }
      _disposing = true;
      // The registrations put aside. `removeAt(0)`, not `removeLast`: they
      // were collected in the order they came off the stack, and that is
      // the order they run in — the top one first, as if they had never
      // been put aside.
      // No loop here either, for the reason on [_execute]: it goes round
      // through [_unwind], which runs what the skipped one registered.
      Future<void> skippedPass() async {
        if (_skipped.isEmpty || valueHandedOver()) {
          conclude();
          return;
        }
        await _runCleanup(_skipped.removeAt(0));
        return _unwind(() => false, skippedPass);
      }

      // The condition of a `discard` registration is read as it comes off
      // the stack, from the outcome as it stands then: a cancellation may
      // arrive into the unwinding itself. The ones it passed over wait for
      // [skippedPass] instead of being dropped.
      await _unwind(valueHandedOver, () async {
        if (hold == null) {
          return skippedPass();
        }
        // The second barrier, between the two passes — where the core
        // re-reads the outcome anyway. A branch stands here disposing
        // whether or not it registered a thing: what it may do while it
        // waits must not depend on that, and the group needs every branch
        // to check against, not only the ones with a cleanup stack.
        _betweenPasses = true;
        _committedByGroup = await hold.beforeOutcome();
        _betweenPasses = false;
        if (isFinished) {
          _traceDroppedCleanups();
          // Ended by hand at the barrier: neither pass runs again, and what
          // is left would be held for as long as the handle is.
          _skipped.clear();
          _cleanups.clear();
          _disposing = false;
          _answerForHandFinished(outcome, announcedBefore: announcedBefore);
          return;
        }
        // The stack is read again, and this pass is not the second one: a
        // branch at the barrier is not over, and an `onDispose` from a
        // background timer or an event of a domain lands on it legally.
        // Without this reading such a registration would never run at all.
        return _unwind(valueHandedOver, skippedPass);
      });
    } on Object catch (error, stackTrace) {
      if (_startReturned) {
        rethrow;
      }
      // Still inside the start, and its stack may be the one that ran out:
      // two stores and nothing else. `_start` throws this to whoever
      // started the job.
      _tornError = error;
      _tornTrace = stackTrace;
    }
  }

  /// Whether this job, a child on the list of its parent and not finished,
  /// has no routine alive: its start was cut short.
  ///
  /// Never reached [_execute] -- not started at all, or started and cut
  /// short before the routine -- or reached it and was thrown out of its
  /// synchronous part. Asked by the parent once its body is over and the
  /// start of this job is on no stack: until then a job that has not
  /// reached its routine is one on its way there.
  bool get _startWasTorn => !_routineEntered || _tornError != null;

  /// Ends the children whose start was cut short.
  void _concludeTornChildren() {
    final body = _bodyOutcome;
    final Object error;
    final StackTrace stackTrace;
    if (body is Failed && body.error is StackOverflowError) {
      // The overflow that reached this body through the throw.
      error = body.error;
      stackTrace = body.stackTrace;
    } else {
      error = const StackOverflowError();
      stackTrace = StackTrace.current;
    }
    var group = _firstGroup;
    while (group != null) {
      // Read first: the group leaves the chain below.
      final next = group._next;
      if (!group._settling) {
        // Off the chain before anything else, so that a group this fails
        // to take up is not asked again, forever.
        group._leave();
        try {
          group._concludeTorn(error, stackTrace);
        } on Object catch (error, stackTrace) {
          notifyError(error, stackTrace);
        }
      }
      group = next;
    }
    // By copy: a child that finishes takes itself off the list.
    for (final child in _childrenNow()) {
      if (child.isFinished || !child._startWasTorn) {
        continue;
      }
      try {
        child._concludeTorn(error, stackTrace);
      } on Object catch (error, stackTrace) {
        notifyError(error, stackTrace);
      }
    }
  }

  /// Ends this job, whose start was cut short, as a job whose body failed
  /// with what cut it short, [error] if nothing else was written down.
  void _concludeTorn(Object error, StackTrace stackTrace) {
    final tornError = _tornError ?? error;
    final tornTrace = _tornError == null ? stackTrace : _tornTrace!;
    // Before anything else, and for good: whatever happens below, the
    // parent does not take this job for one cut short again, and come back
    // for it without end.
    _routineEntered = true;
    _tornError = null;
    _tornTrace = null;
    final ended = _bodyOutcome;
    if (ended is! Failed || ended.error is StackOverflowError) {
      // The overflow reached the parent's body by the throw, and the body
      // is where it is answered for, not the zone. A failure of its own
      // that the body of this job wrote down reached nobody, and it is
      // reported the way any unobserved one is.
      ignoreFailure();
    }
    if (_status == JobStatus.created) {
      finish(Failed(tornError, tornTrace));
      return;
    }
    if (ended is! Failed) {
      // What the second pass takes the body to have ended with.
      _bodyOutcome = Failed(tornError, tornTrace);
    }
    _startReturned = true;
    unawaited(_execute(null));
  }

  /// Hands on an error the outcome does not carry.
  ///
  /// The body failed and the job ends [Cancelled] all the same — it failed and
  /// was cancelled while it waited for its children, say, or a cancellation
  /// stopped an operation and the body threw that operation's error — so the
  /// path that reports an unobserved [Failed] never runs. The same goes for the
  /// failures inside an envelope the body threw next to the job's own
  /// cancellation. An engine can bring one here too: a [Failed] it hands to
  /// [finish] over the mark, or to a job that is already over. Whoever reads
  /// the outcome — [Job.value], [Job.done], [JobContext.run], a group of
  /// [JobContext.runAll] — gets the cancellation, or whatever the job ended
  /// with first, and not this, so reading it settles nothing. It is an error no
  /// outcome carries, answered the way the failure of a branch the group did
  /// not throw is: through [JobAnswerer.onUnanswered] of an observer that
  /// answers, otherwise in the zone, and [Job.isCancellationError] is asked
  /// about it on the way, as about any failure of a job that has accepted a
  /// cancellation. [announced] says whether [JobObserver.onError] has heard it
  /// already — a failure of the body was told where it was caught, one an
  /// engine handed to [finish] was told nowhere.
  ///
  /// [Job.ignoreFailure] takes the answer away and leaves the notice: one
  /// handed to [finish] is still told to [JobObserver.onError], once. An
  /// uncovered [Failed] needs no notice to be seen — the outcome shows it; this
  /// one the outcome does not show, and without the notice it would vanish.
  ///
  /// A failure of the body of a job an engine ended by hand comes here too,
  /// whether the body threw before that or after, unless the engine handed in
  /// that very failure: the outcome is the engine's, and the failure is in
  /// none. Nor does one the group of [JobContext.runAll] took in place of a
  /// value handed in after the group heard of it: the group throws it or
  /// answers for it — see [_failureWentToGroup].
  void _reportCovered(Failed outcome, {required bool announced}) {
    if (_ignored) {
      if (!announced) {
        notifyObserver(outcome.error, outcome.stackTrace);
      }
      return;
    }
    if (announced) {
      _handleUnanswered(outcome.error, outcome.stackTrace);
    } else {
      notifyError(outcome.error, outcome.stackTrace);
    }
  }

  /// Answers for the failure of the body of a job an engine ended by hand, at
  /// whatever point of the run it did so. The outcome is the engine's, and the
  /// failure is in it only when the engine handed in that very error; otherwise
  /// it goes where the failure of the body of a cancelled job goes. One the
  /// engine handed in before the body threw it was answered for in [finish]
  /// already: [announcedBefore]. One the group of [JobContext.runAll] took in
  /// place of a value is the group's to throw or answer for:
  /// [_failureWentToGroup].
  void _answerForHandFinished(
    Outcome<T> body, {
    required bool announcedBefore,
  }) {
    // Written by the body's route after [finish] let go of it: nothing reads it
    // past this point, and it must hold neither the failure nor the value the
    // body ended with.
    _bodyOutcome = null;
    if (body is! Failed || announcedBefore || _failureWentToGroup) return;
    final ended = _outcome;
    if (ended is Failed && identical(ended.error, body.error)) return;
    _reportCovered(body, announced: true);
  }

  /// Runs the cleanup stack from the top until it is empty, and then
  /// [then], in the same turn as that last look at the stack.
  ///
  /// A registration that [passOver] says to skip goes onto [_skipped]
  /// instead of running. Each one is read as it comes off the stack, and
  /// one may register more while it runs.
  ///
  /// The only loop that sleeps over the stack: why it is not in
  /// [_execute], and why nothing else loops there, is said on [_execute].
  Future<void> _unwind(
    bool Function() passOver,
    FutureOr<void> Function() then,
  ) async {
    for (var cleanup = _nextCleanup(passOver);
        cleanup != null;
        cleanup = _nextCleanup(passOver)) {
      await _runCleanup(cleanup);
    }
    return then();
  }

  /// Takes the next registration to run off the stack, putting aside the
  /// ones [passOver] says to skip; `null` once the stack is empty.
  _Cleanup? _nextCleanup(bool Function() passOver) {
    while (_cleanups.isNotEmpty) {
      final cleanup = _cleanups.removeLast();
      if (!cleanup.always && passOver()) {
        _skipped.add(cleanup);
        continue;
      }
      return cleanup;
    }
    return null;
  }

  /// Runs one registration; its error goes to [notifyError], and the stack
  /// unwinds on.
  Future<void> _runCleanup(_Cleanup cleanup) async {
    try {
      await cleanup.run();
    } on Object catch (error, stackTrace) {
      notifyError(error, stackTrace);
    }
  }

  /// The body threw [thrown] without being marked cancelled: either its own
  /// `throw Cancelled(...)` or a child's cancellation via `child.value`.
  Cancelled _handlerCancel(Cancelled thrown, StackTrace stackTrace) {
    final child = _outcomeChild[thrown];
    if (child != null) {
      final marked = <(Object, StackTrace)>[];
      String description;
      try {
        // The child as it prints itself: `Job(thumbnail)`, and `Job()` for a
        // child without a key, never `null`.
        description = _collectingMarks(marked, () => '$child: $thrown');
      } on Object catch (error, stackTrace) {
        // An engine's own `toString`, or the `Cancelled`, threw.
        marked.add((error, stackTrace));
        description = 'child cancellation';
      }
      for (final (error, stackTrace) in marked) {
        notifyError(error, stackTrace);
      }
      return Cancelled.by(
        reason: HandlerCancelReason(cause: thrown),
        description: description,
        stackTrace: stackTrace,
      );
    }
    return Cancelled.by(
      reason: thrown.reason,
      description: thrown.description,
      stackTrace: stackTrace,
    );
  }

  Future<void> _awaitChildren() async {
    while (true) {
      var starting = false;
      var torn = false;
      for (var group = _firstGroup; group != null; group = group._next) {
        if (group._forming) {
          starting = true;
        } else if (!group._settling) {
          torn = true;
        }
      }
      // `untilFinished`, not `done`: waiting for a child is the core's
      // business and must not mark the child observed for the parent.
      final pending = <Future<void>>[];
      for (var child = _firstChild; child != null; child = child._nextSibling) {
        if (child.isFinished) {
          continue;
        }
        if (child._startInFlight) {
          starting = true;
        } else if (child._startWasTorn) {
          torn = true;
        } else {
          pending.add(child.untilFinished);
        }
      }
      if (starting) {
        // The body ended inside the start of a child of its, or a start
        // was thrown out and left its mark up. Which of the two cannot be
        // told from here, and need not be: a start is synchronous, so a
        // turn later it is on no stack, and a mark that still stands then
        // was left behind.
        await null;
        _takeDownStartMarks();
        continue;
      }
      if (torn) {
        // On a stack of its own. The first time round `_execute` comes to
        // this routine past a suspension. The second time it comes straight
        // in, on the stack of the parent that has come back for this job,
        // and finds every start that was cut short still marked: nothing
        // but the lines above takes such a mark down, and they do it a
        // turn later. So no job is ended under another.
        _concludeTornChildren();
        continue;
      }
      if (pending.isEmpty) {
        return;
      }
      await Future.wait(pending);
    }
  }

  /// Takes down the marks of the starts of children and groups: none of
  /// those starts is on a stack any more.
  void _takeDownStartMarks() {
    for (var group = _firstGroup; group != null; group = group._next) {
      group._forming = false;
    }
    for (var child = _firstChild; child != null; child = child._nextSibling) {
      child._startInFlight = false;
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
      if (_pendingContinuations > 0) {
        _reportUnobserved(outcome);
        return;
      }
      _debug(() => '$this failure went to the zone');
      _failureWentToZone = true;
      _zone.handleUncaughtError(outcome.error, outcome.stackTrace);
    });
  }

  /// Lets everyone waiting know, after [cancelWith] has marked the job.
  ///
  /// Runs once and once only: the mark goes on before the cascade, so a
  /// callback that comes back to `cancelWith` through a path of its own
  /// turns around at the early return and never reaches this.
  void _markCancelled(Cancelled cancelled) {
    try {
      // In registration order, and from a copy: a callback may register
      // another one, and one it removes still runs. `JobContext.onCancel`
      // wraps the caller's callbacks, so an error of theirs never reaches
      // this loop -- an overflow of the cascade itself does, and it is on
      // its way out anyway.
      for (final callback in _onCancel.toList()) {
        callback();
      }
      _onCancel.clear();
      _notifyCancelled(cancelled);
    } finally {
      // Whatever happened, the pass is over and the window with it: what
      // runs out of stack after this did it on its own.
      _outOfStack = false;
    }
  }

  /// Tells the [whenFinished] listeners, from a snapshot: one registered on
  /// the way is called at once, one removed on the way still runs.
  void _notifyFinished(Outcome<T> outcome) {
    _finishTold = true;
    final listeners = _finishListeners.toList();
    _finishListeners.clear();
    for (final listener in listeners) {
      listener(outcome);
    }
  }

  /// Saves the event before calling user code, including reentrant listeners.
  void _notifyCancelled(Cancelled cancelled) {
    if (_cancelled != null) return;
    _cancelled = cancelled;
    final listeners = _cancelListeners.toList();
    _cancelListeners.clear();
    for (final listener in listeners) {
      listener(cancelled);
    }
  }

  /// Never throws: a key whose `toString` throws, or a [describe] that
  /// does, is printed as a mark, `Job(key: <describe threw StateError>)`.
  /// The core builds its own error messages with this, and the message
  /// must stay the core's rather than turn into the error of a name. The
  /// error itself is reported where the core names a job on a channel of
  /// its own: in a parent's cancellation, to [JobObserver.onError], and
  /// on a line of [Job.debug], to the zone.
  @override
  String toString() {
    String part(String what, String Function() print) {
      try {
        return print();
      } on Object catch (error, stackTrace) {
        _marked?.add((error, stackTrace));
        return '<$what threw ${_typeOf(error)}>';
      }
    }

    final key = _key;
    if (key == null) {
      // Not `Job(null)`: a job without a key has no name to print, and a
      // `null` in every error message reads as a defect of its own.
      return 'Job(${part('describe', describe)})';
    }
    // The key first, the way it is printed, and so its error is reported
    // first too.
    final name = part('key', () => '$key');
    final description = part('describe', describe);
    return description.isEmpty ? 'Job($name)' : 'Job($name: $description)';
  }

  /// Where [toString] puts the errors it printed as marks, while
  /// [_collectingMarks] runs.
  static List<(Object, StackTrace)>? _marked;

  /// Runs [print] and puts into [marked] every error a [toString] inside
  /// it printed as a mark, for a caller that reports them: a parent naming
  /// a child in its cancellation, a line of [Job.debug]. Everything printed
  /// inside counts, an error message of the core built there included;
  /// one built outside reports nothing, and its marks stay marks.
  static String _collectingMarks(
    List<(Object, StackTrace)> marked,
    String Function() print,
  ) {
    final outer = _marked;
    _marked = marked;
    try {
      return print();
    } finally {
      _marked = outer;
    }
  }

  /// The type of [error] for a mark, or a word when even that throws: a
  /// `runtimeType` is a getter like any other.
  static String _typeOf(Object error) {
    try {
      return '${error.runtimeType}';
    } on Object {
      return 'an error';
    }
  }
}

/// The job of the core itself: a body and nothing else.
class _Job<T> extends JobBase<T> {
  /// Dropped once the job is over, the way [_ThenJob] drops what it
  /// carried. A body runs once; kept after that, it holds everything it
  /// captured -- a controller, a connection, a buffer -- for as long as
  /// anyone holds the handle, and a handle is held exactly to read an
  /// outcome later.
  Future<T> Function(JobContext ctx)? _body;

  _Job(
    Future<T> Function(JobContext ctx) body, {
    super.key,
    super.describe,
    super.cancellable,
    super.timeout,
    super.observer,
  }) : _body = body;

  @override
  JobContextBase createContext() => _CoreContext(this);

  // Non-null while the job runs: `start` refuses a job that has finished,
  // and only finishing clears this.
  @override
  Future<T> execute(covariant _CoreContext ctx) => _body!(ctx);

  @override
  void finished() => _body = null;
}

/// Starts itself on the next microtask.
final class _AutoJob<T> extends _Job<T> {
  _AutoJob(
    super.body, {
    super.key,
    super.describe,
    super.cancellable,
    super.timeout,
    super.observer,
  }) {
    // `scheduleMicrotask`, not `Future(...)`: that one schedules a timer,
    // and under `FakeAsync` the start would need `flushTimers`. From the
    // job's own zone and not the current one: inside the work of
    // `JobContext.unattended` the current zone is that work's, and the body
    // of a job made there would run in it and report to the observer of
    // the job that started the work. Through `run` and the top-level
    // function, not `_zone.scheduleMicrotask`: that hands the callback to
    // the zone's handler unbound, and a handler that runs it wherever it
    // happens to flush -- `fake_async` before 1.3.3 -- would run the body
    // in none of the zones the job knows.
    _zone.run(() => scheduleMicrotask(_startIfStillCreated));
  }

  /// A job dropped before its own start ever came round is finished
  /// already, and a finished job does not run.
  void _startIfStillCreated() {
    if (status == JobStatus.created) {
      start();
    }
  }
}

/// The root made by [Job.each], started inside that call.
///
/// A class of its own so that [JobContextBase.startChild] can tell it from a
/// job that merely happens to be running, and say what to do instead.
final class _EachJob extends _Job<void> {
  _EachJob(
    super.body, {
    super.key,
    super.describe,
    super.cancellable,
    super.observer,
  });
}

/// Waits for [start].
final class _DeferredJob<T> extends _Job<T> implements DeferredJob<T> {
  _DeferredJob(
    super.body, {
    super.key,
    super.describe,
    super.cancellable,
    super.timeout,
    super.observer,
  });

  @override
  void start() => super.start();
}
