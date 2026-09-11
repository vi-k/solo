import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

import 'observer.dart';

part 'job_context.dart';
part 'job_stream.dart';
part 'job_then.dart';
part 'outcome.dart';

/// A handle to a job: the outcome, the waiting and the cancellation.
///
/// Not a [Future]: a method that starts a job may be called without an
/// `await`, and the analyzer will not ask for one. Await [done] or [value]
/// where you need to, or register a cancellation listener with [whenCancelled].
///
/// A job that ends with [Failed] and is never observed hands its error to
/// the zone that created the job, the way Dart reports an unhandled
/// `Future` error. Touching [done], [value] or [ignore], or forwarding a
/// failure through [then], counts as observing it; see [ignore].
abstract interface class Job<T> {
  /// Creates a job and starts it on the next microtask.
  ///
  /// Not inside the constructor: the caller puts the handle in a variable
  /// first, listens to [done] if it wants to, and may cancel before the
  /// body ever runs — a job cancelled by then ends as
  /// `Cancelled(manual)` with `started: false`, and the body is never
  /// called.
  ///
  /// A job made this way is a root and stays one: [JobContext.run] refuses
  /// it, its own start being already on the way. A child is made with
  /// [deferred].
  ///
  /// [observer] receives the hooks of this job, and a child inherits it
  /// unless given one of its own. What the body opens is released through
  /// the cleanup stack of the context — see [JobContext.onDispose] and
  /// [JobContext.onDiscard].
  ///
  /// ```dart
  /// final job = Job<Database>((ctx) async {
  ///   final database = await ctx.join(
  ///     Database.open,
  ///     discard: (database) => database.close(),
  ///   );
  ///   await ctx.join(database.migrate);
  ///
  ///   return database;
  /// });
  /// ```
  factory Job(
    Future<T> Function(JobContext ctx) body, {
    Object? key,
    String Function()? describe,
    bool cancellable = true,
    JobObserver? observer,
  }) =>
      _AutoJob<T>(
        body,
        key: key,
        describe: describe,
        cancellable: cancellable,
        observer: observer,
      );

  /// Creates a job that waits to be told to start.
  ///
  /// A static method and not a constructor: the result is a
  /// [DeferredJob], and a constructor of [Job] could only be typed as one.
  /// Whoever owns the job starts it — by hand, a queue, or a parent
  /// through [JobContext.run].
  static DeferredJob<T> deferred<T>(
    Future<T> Function(JobContext ctx) body, {
    Object? key,
    String Function()? describe,
    bool cancellable = true,
    JobObserver? observer,
  }) =>
      _DeferredJob<T>(
        body,
        key: key,
        describe: describe,
        cancellable: cancellable,
        observer: observer,
      );

  /// The key given at creation.
  ///
  /// The kernel does not read it: it is there for [toString], for the
  /// observer, and for whatever an engine of a domain does with it —
  /// `solo` compares keys with `==` in its queue policies.
  Object? get key;

  /// The description given at creation, or an empty string.
  String describe();

  /// Nesting depth: 0 for a root job, `parent.level + 1` for a child.
  int get level;

  /// Whether this job was started by [JobContext.run].
  bool get isChild;

  /// Whether the body is running or its children are still finishing.
  ///
  /// Still `true` while the engine cleans up after the body: the outcome
  /// is decided by then, but the job has not finished.
  bool get isRunning;

  /// Whether [outcome] is set.
  bool get isFinished;

  /// Whether the job is marked cancelled, even if the body still runs.
  ///
  /// While the engine cleans up after the body it answers by the decided
  /// outcome, so a disposer of a body that threw a [Cancelled] of its own
  /// sees `true` here as well.
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

  /// Creates a job that runs [onValue] after this job succeeds and cleans up.
  ///
  /// The callback receives its own [JobContext] and this job's value. It is
  /// called asynchronously, even when this job has already finished, and may
  /// return a value or a future. A failed source forwards its error and stack
  /// trace without calling [onValue]; cancellation cancels the continuation.
  ///
  /// Cancellation also travels backwards: cancelling the continuation asks
  /// its unfinished source to cancel, back through earlier links. Other
  /// continuations of that source receive its accepted cancellation too.
  /// [ChainCancelReason.cause] preserves each cancellation that was forwarded.
  /// Completed jobs keep their outcomes. Sources may refuse or hold a request
  /// under their usual cancellation rules.
  ///
  /// Until the source finishes, the continuation is not running. Cancelling
  /// it marks it immediately but still waits for the source, including its
  /// children and cleanup, even if the source refuses cancellation. Its
  /// cancellation outcome has `started: false` while waiting for the source.
  /// Once started, its body, children and cleanup follow the ordinary [Job]
  /// lifecycle. Awaiting its [cancel] waits for that work as well.
  ///
  /// This does not start a deferred source. The continuation starts itself
  /// when ready and cannot be adopted through [JobContext.run]. It is a root
  /// job of the core, with its own optional [observer]; it inherits no
  /// observer, domain state, queue slot or rules. Awaiting it from its
  /// source's body or cleanup deadlocks, just like awaiting its own [done].
  ///
  /// Forwarding a failure observes the source and transfers responsibility
  /// to the continuation. A cancelled continuation does not observe a source
  /// failure it cannot forward; observe the source separately if needed.
  /// Returned jobs are ordinary values, not automatically awaited: start and
  /// await deferred children with `await ctx.run(child)`. Keep the original
  /// child separately when its handle is needed.
  ///
  /// ```dart
  /// final length = Job<String>((ctx) async => 'hello')
  ///     .then<int>((ctx, text) => text.length);
  /// print(await length.value); // 5
  /// ```
  Job<R> then<R>(
    FutureOr<R> Function(JobContext ctx, T value) onValue, {
    JobObserver? observer,
  });

  /// Registers [callback] for cancellation and returns an unregister function.
  ///
  /// Calls it synchronously with the [Cancelled] carrying the reason,
  /// description, start status and stack trace. For a running job this is
  /// after cancellation has cascaded to its children and [JobContext.onCancel]
  /// callbacks have run, before the body finishes; for a job cancelled before
  /// start, when it is dropped. If the body throws [Cancelled] itself, this
  /// runs after the body and its children end, right before cleanup. That
  /// path does not call [JobContext.onCancel].
  ///
  /// If cancellation has already been accepted, calls [callback] immediately,
  /// even if the job has finished. A refused or held cancellation does not
  /// trigger it; a held one triggers it when it is accepted. A job that ends
  /// [Done] or [Failed] without cancellation never calls it and releases its
  /// registrations on finish. Registering does not observe a [Failed] outcome.
  ///
  /// Each registration runs once. Pending callbacks run in registration
  /// order, from a snapshot: unregistering during notification does not remove
  /// a callback from that pass. Registering during notification calls the new
  /// callback immediately. Unregistering more than once is harmless.
  ///
  /// A synchronous error goes to [JobObserver.onError], or to the job's
  /// creation zone if there is no observer; a thrown [Cancelled] is kept out
  /// of the zone. The error changes neither cancellation nor other callbacks.
  /// The callback is synchronous: an `async` callback's future is not awaited
  /// and its errors are not caught here.
  ///
  /// ```dart
  /// final unregister = job.whenCancelled((cancelled) {
  ///   print(cancelled.reason);
  /// });
  /// // When the listener is no longer needed:
  /// unregister();
  /// ```
  void Function() whenCancelled(void Function(Cancelled) callback);

  /// Cancels the job with [reason] and waits for it to actually finish.
  ///
  /// Pass a custom [CancelReason] subclass to carry data to [whenCancelled]
  /// and the [Cancelled] outcome. The accepted reason is kept by identity;
  /// another cancellation does not replace it, even while it is held.
  ///
  /// A job created with `cancellable: false` refuses this once it has
  /// started; before that there is no body to protect, and a job cancelled
  /// then is dropped like any other — unless an engine of a domain holds
  /// it before the start and refuses on its behalf, as `solo` does for a
  /// job waiting in its queue: there `cancellable: false` turns this call
  /// down already, and the job runs when its turn comes. A job inside
  /// [JobContext.uncancellable] is cancelled when that section closes.
  /// Either way the returned future waits for it to finish.
  ///
  /// Awaited from inside the body it never completes: the waiting is for
  /// the job, and the job is this body. A body gives itself up with
  /// `throw Cancelled('why')` instead.
  Future<void> cancel({CancelReason reason = const ManualCancelReason()});

  /// Tells the engine that nobody is interested in this job's failure.
  ///
  /// The counterpart of `Future.ignore`. A job that ends with [Failed]
  /// without ever being observed hands its error to the zone that created
  /// it; call this on a fire-and-forget job whose failure is already
  /// handled elsewhere, by a [JobObserver] of your own.
  ///
  /// ```dart
  /// Job<void>((ctx) => ctx.wait(device.close)).ignore();
  /// ```
  ///
  /// Waiting for [done] or [value] observes the job too; calling this
  /// afterwards changes nothing. Has no effect on [Cancelled], which is
  /// never reported to the zone.
  ///
  /// A job is not background work: it has an outcome and an observer of
  /// its own, and this is how it is quenched. Work with neither goes to
  /// [JobContext.unattended] instead.
  void ignore();
}

/// Where a job is in its life.
///
/// For engines built on [JobBase], which read it through `status`; a
/// handle answers with [Job.isRunning] and [Job.isFinished] instead.
///
/// The queue is not here: it belongs to whoever runs jobs, not to the job.
enum JobStatus {
  /// Made, not started; the body has not run.
  created,

  /// The body is running, its children are still finishing, or the engine
  /// is cleaning up after them.
  running,

  /// The outcome is set and will not change.
  finished,
}

/// One registration on the cleanup stack of a job.
///
/// [always] tells the two kinds apart: a `dispose` registration runs
/// whatever the outcome, a `discard` one only when the value reached
/// nobody. [value] is set for registrations made by `wait` and `join`, and
/// it is what `disown` looks up.
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
/// domain needs is protected, and the subclass opens exactly what it needs
/// through private wrappers of its own: `@protected` holds inside a
/// subclass, and an engine reaches a job from the side.
abstract class JobBase<T> implements Job<T> {
  /// Tracing of the job lifecycle for debugging; `null` by default.
  ///
  /// An engine built on this one prints its own side elsewhere — `solo`
  /// puts the queue, the state and the closing into `SoloBase.debug`. To
  /// follow both sides, set both.
  static void Function(String message)? debug;

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
  /// its own, and `ignore()` is how it is quenched.
  final Zone _zone = _creationZone();

  static Zone _creationZone() =>
      (Zone.current[_unattendedKey] as Zone?) ?? Zone.current;

  final _done = Completer<Outcome<T>>();
  Cancelled? _cancelled;
  final _cancelListeners = <void Function(Cancelled)>[];
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
  final _children = <JobBase<Object?>>[];

  /// The child behind an outcome of a child, for the description of this
  /// job's own.
  ///
  /// The key is the outcome instance itself, so a child must never be
  /// finished with a canonicalized constant: two identical
  /// `const Cancelled.by(...)` are one object and one entry. Today that
  /// holds by itself — every cancellation the engine builds carries a
  /// stack trace of its own.
  final _outcomeChild = Expando<JobBase<Object?>>();

  // A public reason type is not proof that this job issued the cancellation.
  // Tokens identify the child without retaining its handle through a reason.
  late final _cascadeChild = Expando<Object>();
  late final Object _cascadeIdentity = Object();

  JobBase<Object?>? _parent;

  final bool _cancellable;
  var _uncancellableDepth = 0;
  Cancelled? _heldCancel;

  /// Whether anyone observed the outcome, directly or by forwarding it.
  bool _observed = false;

  /// Continuations still waiting to receive this outcome. A late listener
  /// may attach within the observation grace period but receive the result
  /// on the next microtask; give it that chance before reporting a failure.
  int _pendingContinuations = 0;

  JobStatus _status = JobStatus.created;
  Outcome<T>? _outcome;
  Cancelled? _pendingCancel;
  bool _bodyEnded = false;
  bool _disposing = false;
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

  /// Builds and delivers a diagnostic message, guarded on both halves.
  ///
  /// Guarded because the channel stands between transitions a job cannot be
  /// left in the middle of: an error here once left a job `isFinished` with
  /// its `done` never completing. Both halves belong to whoever turned the
  /// channel on — `message()` runs their `describe` and `toString`, and
  /// [debug] is theirs — and a diagnostic channel is cross-cutting like an
  /// observer: an error in it changes nothing else.
  static void _debug(String Function() message) {
    final debug = JobBase.debug;
    if (debug == null) {
      return;
    }
    try {
      debug(message());
    } on Object catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
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
  Job<R> then<R>(
    FutureOr<R> Function(JobContext ctx, T value) onValue, {
    JobObserver? observer,
  }) =>
      _ThenJob<T, R>(this, onValue, observer: observer);

  @override
  void Function() whenCancelled(void Function(Cancelled) callback) {
    void guarded(Cancelled cancelled) {
      try {
        callback(cancelled);
      } on Object catch (error, stackTrace) {
        notifyError(error, stackTrace);
      }
    }

    final outcome = _outcome;
    final cancelled =
        _cancelled ?? _pendingCancel ?? (outcome is Cancelled ? outcome : null);
    if (cancelled != null) {
      guarded(cancelled);
      return () {};
    }
    if (isFinished) return () {};
    _cancelListeners.add(guarded);
    return () => _cancelListeners.remove(guarded);
  }

  @override
  Future<void> cancel({CancelReason reason = const ManualCancelReason()}) {
    cancelWith(
      Cancelled.by(
        reason: reason,
        started: true,
        stackTrace: StackTrace.current,
      ),
    );
    // The engine's own waiting is not observation, so cancelling a job does
    // not silence its failure.
    return whenDone;
  }

  /// Cancels the job with [cancelled], correcting `started` to its status.
  ///
  /// Idempotent. [rejectable] is what a job created with
  /// `cancellable: false` may refuse, and its refusal is final — nothing
  /// is replayed later. Inside [JobContext.uncancellable] a rejectable
  /// cancellation is held instead: the step runs untouched, and the
  /// cancellation lands the moment the last section closes. The rules of a
  /// domain pass `false` and go through both.
  ///
  /// The one member of the lifecycle a subclass extends rather than
  /// replaces: `solo` adds the branch for a job still waiting in its
  /// queue and then calls `super`. An override that forgets the call
  /// silently switches cancellation off — for [Job.cancel], for the
  /// cascade from a parent and for whatever an engine of a domain adds.
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
        if (!_cancellable && rejectable) {
          _debug(() => 'cancel $this: not cancellable');
          return;
        }
        final marked = withStarted(true);
        if (_uncancellableDepth > 0 && rejectable) {
          // Held, not refused, and the job is not marked: `onCancel`
          // callbacks and the cascade onto children would stop the very
          // step this section protects.
          _debug(() => 'cancel $this: held until the step ends: $marked');
          _heldCancel ??= marked;
          return;
        }
        _debug(() => 'cancel $this: $marked');
        // Marked before the cascade, and only marked: a callback of a child
        // may come back for this job, and the early return above is the only
        // thing that stops it from cascading and marking a second time.
        // What the marking brings with it — `whenCancelled` and the
        // callbacks — still waits for the children, because `solo` pins the
        // order in which a cancellation is seen.
        _pendingCancel = marked;
        cascadeToChildren(marked);
        if (_status == JobStatus.finished) {
          // A callback of a child reached the engine of a domain, and it
          // ended the job by hand: `whenCancelled` was notified already, and
          // the callbacks below would run on a job that is over.
          return;
        }
        _markCancelled(marked);
    }
  }

  /// Cancels every child of this job, deepest last started first.
  ///
  /// The cascade is rejectable: a child created with `cancellable: false`
  /// refuses it. Each child receives [ParentCancelReason] with [cancelled]
  /// as its cause, preserving the parent's reason and data. The cancellation
  /// stack trace is carried over as well.
  @protected
  void cascadeToChildren(Cancelled cancelled) {
    for (final child in _children.reversed.toList()) {
      _cancelChild(child, cancelled);
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

  /// Whether the engine is unwinding the cleanup stack.
  ///
  /// The body is gone and the outcome is decided, but the job has not
  /// finished: [isFinished] is still `false`.
  @protected
  bool get isDisposing => _disposing;

  /// The cancellation the job is marked with, or `null`.
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
  /// say why. A held cancellation is one of the answers, and this is the
  /// only thing that knows it.
  @protected
  bool get inUncancellableSection => _uncancellableDepth > 0;

  /// Opens an uncancellable section: a rejectable cancellation arriving
  /// now is held, and the job is not marked until the section closes.
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
    cancelWith(held);
  }

  /// Set by whoever adopts the job, before it starts.
  @protected
  set level(int value) => _level = value;

  /// The children this job waits for; read-only.
  ///
  /// The way in is [JobContext.run] alone: it sets the parent, the level
  /// and the observer of the child, and nothing else may put a job on this
  /// list — the engine would wait for a child it never adopted.
  @protected
  List<JobBase<Object?>> get children => UnmodifiableListView(_children);

  /// Waiting without observing: an engine waits for a job to finish
  /// without marking its outcome observed, so a failure nobody looked at
  /// still reaches the zone.
  @protected
  Future<void> get whenDone => _done.future.then((_) {});

  /// Runs the body. Throws [StateError] if the job already ran.
  @protected
  void start() {
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
    _status = JobStatus.running;
    started();
    _notifyStart();
    unawaited(_execute(ctx));
  }

  /// Ends the job with [outcome].
  ///
  /// On a job that has already finished this does nothing, the same as
  /// [cancel]: an outcome is final, and an engine of a domain racing its
  /// own body must not be able to replace one.
  ///
  /// Ending a job that is still running is not a way to cancel it: this
  /// waits for no children and unwinds no cleanup stack, so everything the
  /// body opened stays open. Cancel with [cancelWith] instead, and let the
  /// body unwind; how many cleanups were left behind is in the debug
  /// trace.
  @protected
  void finish(Outcome<T> outcome) {
    if (_status == JobStatus.finished) {
      return;
    }
    if (_cleanups.isNotEmpty) {
      _debug(
        () => '$this finished with ${_cleanups.length} cleanups pending',
      );
    }
    _outcome = outcome;
    _status = JobStatus.finished;
    // The list of children is a waiting list, so it shrinks; the link from
    // an outcome to the child that carried it lives on, in the parent's
    // `Expando`. Both happen here, where they are observable: in `finished`
    // and in `onFinish` the parent's list is already without this child.
    final parent = _parent;
    if (parent != null) {
      parent._children.remove(this);
      if (outcome is Cancelled) {
        parent._outcomeChild[outcome] = this;
      }
    }
    // Guarded: the hook belongs to an engine of a domain, and its error
    // must not stand between the job and its outcome — an unfinished job
    // holds its parent, its waiters and the engine itself forever.
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
    _done.complete(outcome);
    // Notify only after the domain has detached this job and delivered its
    // finish hooks: a synchronous subscriber may immediately add more work.
    if (outcome is Cancelled) _notifyCancelled(outcome);
    _cancelListeners.clear();
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
  /// [JobContext.onCancel] or [Job.whenCancelled], work handed over with
  /// [JobContext.unattended].
  /// Silence is the choice of whoever listens, not the default of the
  /// package. A [Cancelled] is the one thing that never reaches the zone
  /// from here: a cancellation is a decision somebody made, not a failure,
  /// and without an observer it is heard by nobody.
  @protected
  void notifyError(Object error, StackTrace stackTrace) {
    // Traced on both paths: the one without an observer is the harder of
    // the two to debug, and it is the one that reaches the zone.
    _debug(() => '$this error: $error');
    final observer = _observer;
    if (observer == null) {
      _toZone(error, stackTrace);
      return;
    }
    _notify(() => observer.onError(this, error, stackTrace));
  }

  /// Hands [error] to the zone the job was created in, unless it is a
  /// [Cancelled].
  ///
  /// For an engine of a domain whose own route for an error with nowhere
  /// to go ends with nobody: `solo` sends one here when neither an
  /// observer nor its hook took it. The core reaches the zone by itself,
  /// through [notifyError] without an observer and through an unobserved
  /// [Failed]. A cancellation is held back here as it is there, so an
  /// engine of a domain does not write that rule again.
  @protected
  void reportToZone(Object error, StackTrace stackTrace) =>
      _toZone(error, stackTrace);

  /// The one door to the zone for an error with nowhere else to go.
  ///
  /// A [Cancelled] does not go through it. A cancellation is a decision
  /// somebody made, not a failure; the one that ends this job has been
  /// heard on the outcome already, and any other has an owner of its own.
  /// In Flutter the zone is `PlatformDispatcher.onError`, and a
  /// cancellation reaching it says nothing anybody can act on.
  ///
  /// The route of an unobserved [Failed] is not this one and keeps its own
  /// rule: there the outcome decides, not the object it carries, so a
  /// failure somebody built out of a [Cancelled] on purpose still reaches
  /// the zone.
  void _toZone(Object error, StackTrace stackTrace) {
    if (error is Cancelled) {
      _debug(() => '$this kept a cancellation out of the zone: $error');
      return;
    }
    _debug(() => '$this error went to the zone: $error');
    _zone.handleUncaughtError(error, stackTrace);
  }

  /// The subclass joins the run: `solo` adds the job to its running list.
  ///
  /// Called with the job already [JobStatus.running], so it must not
  /// throw: an error here leaves a job that is running and has no body,
  /// and nothing will ever finish it.
  @protected
  void started() {}

  /// The subclass leaves the run: `solo` clears `current` and pumps.
  ///
  /// Called for every job that gets an outcome, including one dropped
  /// before its body ever ran — then there was no [started] to match it.
  /// An error thrown here goes to `onError` and the job finishes all the
  /// same, but the engine of the domain is left half-way through its own
  /// bookkeeping: keep it short and unconditional.
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

  void _notifyLog(Object? message) =>
      _notify(() => _observer?.onLog(this, message));

  Future<void> _execute(JobContextBase ctx) async {
    Outcome<T> outcome;
    // The body gave itself up: the children go, the same as they do for a
    // job cancelled from outside. Not from inside the `catch`: the cascade
    // runs the callbacks of the children, which is the caller's code, and
    // it must find a parent that already refuses to start anything.
    Cancelled? selfCancelled;
    // Whether the body failed before anything marked the job. Only such a
    // failure is a diagnosis the cancellation would swallow; one thrown
    // *after* the mark is the body's own way of giving up, and its error
    // belongs to the observer alone.
    var failedFirst = false;
    try {
      outcome = Done(await execute(ctx));
    } on Cancelled catch (cancelled, stackTrace) {
      if (_pendingCancel case final pending?) {
        outcome = pending;
      } else {
        outcome = selfCancelled = _handlerCancel(cancelled, stackTrace);
      }
    } on Object catch (error, stackTrace) {
      // Read before the observer hears: it is handed the job, and an
      // `onError` that cancels would otherwise make a failure that came
      // first look like it came second. The order is the whole diagnosis,
      // and it is settled at the moment of the throw.
      failedFirst = _pendingCancel == null;
      notifyObserver(error, stackTrace);
      outcome = Failed(error, stackTrace);
    }
    // The body has ended: from here a value coming out of a call it walked
    // away from can no longer reach it, and no child is started any more.
    _bodyEnded = true;
    if (selfCancelled != null) {
      cascadeToChildren(selfCancelled);
    }
    await _awaitChildren();
    if (isFinished) {
      // An engine of a domain ended the job by hand while the body was
      // playing out: the outcome is not ours, the children were not waited
      // for, and the stack stays where it is.
      return;
    }
    // The outcome is decided. The cancellation goes in by a bare
    // assignment and not through `_markCancelled`: that would run the
    // `onCancel` callbacks and finish the waits the body walked away from
    // with an error, where today they quietly get their value. After the
    // children and not in the `catch`: until then `cancelWith` still has
    // to cascade onto them, and a filled `_pendingCancel` stops it.
    if (outcome is Cancelled) {
      _pendingCancel ??= outcome;
      _notifyCancelled(_pendingCancel!);
      // A synchronous subscriber may reach an engine that finishes by hand.
      if (isFinished) return;
    }
    if (_cleanups.isNotEmpty) {
      _disposing = true;
      // The loop lives here and not in a method of its own: between the
      // last look at the stack and `finish` there must be no `await`, or
      // the window after `return` grows by a microtask.
      //
      // The condition of a `discard` registration is read as it comes off
      // the stack, from the outcome as it stands then: a cancellation may
      // arrive into the unwinding itself. The ones it passed over wait for
      // a second pass instead of being dropped.
      while (_cleanups.isNotEmpty) {
        final cleanup = _cleanups.removeLast();
        if (!cleanup.always && (_pendingCancel ?? outcome) is Done<T>) {
          _skipped.add(cleanup);
          continue;
        }
        await _runCleanup(cleanup);
      }
      // `removeAt(0)`, not `removeLast`: the skipped registrations were
      // collected in the order they came off the stack, and that is the
      // order they run in — the top one first, as if they had never been
      // put aside.
      while (_skipped.isNotEmpty && (_pendingCancel ?? outcome) is! Done<T>) {
        await _runCleanup(_skipped.removeAt(0));
        while (_cleanups.isNotEmpty) {
          await _runCleanup(_cleanups.removeLast());
        }
      }
      // Whatever is still put aside will never run: the loop above drains
      // the list for every outcome but [Done], and a [Done] is what put
      // them there. Left behind, they would hold their values and their
      // closures for as long as anyone holds the handle — the job is over,
      // and the list is a field now, not a local that dies with the call.
      _skipped.clear();
      _disposing = false;
    }
    final decided = _pendingCancel ?? outcome;
    finish(decided);
    // After `finish`, not before: the terms are those of an uncovered
    // failure, and those include the window to observe — `finished`,
    // `onFinish`, the completion of `done`, and a microtask after them.
    // Reported earlier, this reached the zone while an observer taking the
    // outcome at finish had not been called yet.
    if (failedFirst && outcome is Failed && !identical(decided, outcome)) {
      _reportCovered(outcome);
    }
  }

  /// Hands an error the outcome no longer carries to the zone.
  ///
  /// The body failed and a cancellation arrived afterwards, so the job ends
  /// [Cancelled] and the path that reports an unobserved [Failed] never
  /// runs. An observer has heard the error already, through
  /// [notifyObserver] where it was caught; without one it would be lost,
  /// and an error is never lost silently. It goes on exactly the terms an
  /// uncovered [Failed] would: only when nobody looked at the outcome, and
  /// whether or not there is an observer — one hearing it through
  /// [notifyObserver] does not settle where an error nobody handled
  /// belongs, and an engine of a domain that puts an observer on every job
  /// would otherwise silence this for good. [Job.ignore] silences it, as
  /// it silences any other failure nobody wants.
  void _reportCovered(Failed outcome) {
    _zone.scheduleMicrotask(() {
      if (_observed) {
        return;
      }
      _debug(() => '$this failure covered by a cancellation went to the zone');
      _zone.handleUncaughtError(outcome.error, outcome.stackTrace);
    });
  }

  /// Runs one registration; its error belongs to `onError` and ends there.
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
      String description;
      try {
        description = 'child ${child.key}: $thrown';
      } on Object catch (error, stackTrace) {
        notifyError(error, stackTrace);
        description = 'child cancellation';
      }
      return Cancelled.by(
        reason: HandlerCancelReason(cause: thrown),
        started: true,
        description: description,
        stackTrace: stackTrace,
      );
    }
    return Cancelled.by(
      reason: thrown.reason,
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
      if (_pendingContinuations > 0) {
        _reportUnobserved(outcome);
        return;
      }
      _debug(() => '$this failure went to the zone');
      _zone.handleUncaughtError(outcome.error, outcome.stackTrace);
    });
  }

  /// Lets everyone waiting know, after [cancelWith] has marked the job.
  ///
  /// Runs once and once only: the mark goes on before the cascade, so a
  /// callback that comes back to `cancelWith` through a path of its own
  /// turns around at the early return and never reaches this.
  void _markCancelled(Cancelled cancelled) {
    // In registration order, and from a copy: a callback may register
    // another one, and one it removes still runs. `JobContext.onCancel`
    // wraps the caller's callbacks, so an error of theirs never reaches
    // this loop.
    for (final callback in _onCancel.toList()) {
      callback();
    }
    _onCancel.clear();
    _notifyCancelled(cancelled);
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

  @override
  String toString() {
    final description = describe();
    final key = _key;
    if (key == null) {
      // Not `Job(null)`: a job without a key has no name to print, and a
      // `null` in every error message reads as a defect of its own.
      return 'Job($description)';
    }
    return description.isEmpty ? 'Job($key)' : 'Job($key: $description)';
  }
}

/// A job that starts when it is told to.
abstract interface class DeferredJob<T> implements Job<T> {
  /// Runs the body.
  ///
  /// Throws [StateError] if the job already ran, and also if it was
  /// cancelled before it started: a job dropped then is finished, and a
  /// finished job does not run.
  void start();
}

/// The job of the core itself: a body and nothing else.
class _Job<T> extends JobBase<T> {
  final Future<T> Function(JobContext ctx) _body;

  _Job(
    this._body, {
    super.key,
    super.describe,
    super.cancellable,
    super.observer,
  });

  @override
  JobContextBase createContext() => _CoreContext(this);

  @override
  Future<T> execute(covariant _CoreContext ctx) => _body(ctx);
}

/// Starts itself on the next microtask.
final class _AutoJob<T> extends _Job<T> {
  _AutoJob(
    super.body, {
    super.key,
    super.describe,
    super.cancellable,
    super.observer,
  }) {
    // `scheduleMicrotask`, not `Future(...)`: that one schedules a timer,
    // and under `FakeAsync` the start would need `flushTimers`.
    scheduleMicrotask(() {
      // A job dropped before its own start ever came round is finished
      // already, and a finished job does not run.
      if (status == JobStatus.created) {
        start();
      }
    });
  }
}

/// Waits for [start].
final class _DeferredJob<T> extends _Job<T> implements DeferredJob<T> {
  _DeferredJob(
    super.body, {
    super.key,
    super.describe,
    super.cancellable,
    super.observer,
  });

  @override
  void start() => super.start();
}
