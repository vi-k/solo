import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

part 'envelope.dart';
part 'job_context.dart';
part 'job_stream.dart';
part 'job_then.dart';
part 'observer.dart';
part 'outcome.dart';
part 'run_all.dart';

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
  /// The result is a [DeferredJob], and whoever owns it starts it: by hand
  /// through [DeferredJob.start], or a parent through [JobContext.run] or
  /// [JobContext.runAll]. Cancelled before that, it ends [Cancelled] with
  /// `started: false`, and its body never runs.
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

  /// Tracing of the job lifecycle for debugging; `null` by default.
  ///
  /// Every job reports here, one made by an engine of a domain included: the
  /// start, a cancellation, an error, the outcome and a value handed over.
  ///
  /// ```dart
  /// Job.debug = print;
  /// ```
  ///
  /// An engine of a domain prints its own side elsewhere — `solo`, for example,
  /// puts the queue, the state and the closing into `Solo.debug`. To follow
  /// both sides, set both.
  static void Function(String message)? debug;

  /// Walks [error] and hands each failure in it to [onFailure] and each
  /// cancellation to [onCancelled], one at a time.
  ///
  /// [JobAnswerer.onUnanswered] and [JobObserver.onError] are handed an error
  /// whole, and so is `Solo.errorHandler` in `solo`. That error can be a
  /// `ParallelWaitError`: `[a, b].wait` throws one when any of its futures
  /// fails, and it holds failures and cancellations side by side, other such
  /// errors too. A check for `error is Cancelled` lets a cancellation inside
  /// it through, and a report of the whole error names none of its failures.
  /// To report each failure and drop the cancellations:
  ///
  /// ```dart
  /// @override
  /// void onUnanswered(
  ///   Job<Object?> job,
  ///   Object error,
  ///   StackTrace stackTrace,
  /// ) =>
  ///     Job.visitErrors(error, stackTrace, onFailure: report);
  /// ```
  ///
  /// The rules:
  ///
  /// * A [Cancelled] goes to [onCancelled] and any other error that is not a
  ///   `ParallelWaitError` to [onFailure], with [stackTrace].
  /// * A `ParallelWaitError` is walked depth first, its branches in order. A
  ///   `null` branch succeeded and is skipped. An [AsyncError] branch holding a
  ///   [Cancelled] goes to [onCancelled], one holding a `ParallelWaitError` is
  ///   walked in turn, and one holding anything else goes to [onFailure], each
  ///   with the branch's stack trace.
  /// * Nothing is lost. What the walk cannot read goes to [onFailure] whole: a
  ///   `ParallelWaitError` of a record longer than nine or of a shape it does
  ///   not know, one whose list throws when read, one already being walked
  ///   further up, and a branch that is not an [AsyncError]. The readable
  ///   branches of a partly readable list are walked all the same. What has no
  ///   branch of its own gets the stack trace the enclosing error came with.
  ///   An error with neither a failure nor a cancellation anywhere in it goes
  ///   to [onFailure] whole, with [stackTrace].
  /// * Each `ParallelWaitError` is walked once and handed over whole at most
  ///   once, by identity, however many branches lead to it.
  ///
  /// No call to [onFailure] means that a job drops this error as a
  /// cancellation and keeps it out of the zone: the job decides by this walk.
  ///
  /// A callback that throws ends the walk, and the error reaches the caller.
  /// When the caller is a hook of an observer, the job catches it: the zone
  /// gets it, except a [Cancelled], which is dropped, along with the branches
  /// not yet walked.
  static void visitErrors(
    Object error,
    StackTrace stackTrace, {
    required void Function(Object error, StackTrace stackTrace) onFailure,
    void Function(Cancelled cancelled, StackTrace stackTrace)? onCancelled,
  }) =>
      _visitErrors(
        error,
        stackTrace,
        onFailure: onFailure,
        onCancelled: onCancelled,
      );

  /// The key given at creation.
  ///
  /// The core does not read it: it is there for [toString], for the observer,
  /// and for whatever an engine of a domain does with it — `solo`, for example,
  /// compares keys with `==` in its queue policies.
  Object? get key;

  /// The description given at creation, or an empty string.
  String describe();

  /// Nesting depth: 0 for a root job, `parent.level + 1` for a child.
  int get level;

  /// Whether this job was adopted by a parent — through [JobContext.run],
  /// [JobContext.runAll] or [JobContext.each].
  ///
  /// A child the parent turned away — it was already giving up, or a rule of
  /// its domain refused the start — is one too: its [level] is its parent's
  /// plus one, and it never ran.
  bool get isChild;

  /// Whether the body is running or its children are still finishing.
  ///
  /// Still `true` while the core cleans up after the body: the outcome
  /// is decided by then, but the job has not finished. For a branch of
  /// [JobContext.runAll] not even that much — a branch is held until the
  /// group decides, and until then its outcome is not settled at all.
  bool get isRunning;

  /// Whether [outcome] is set.
  bool get isFinished;

  /// Whether the job has accepted a cancellation, even if the body still runs,
  /// or has ended with one.
  ///
  /// While the core cleans up after the body it answers by the decided
  /// outcome, so a disposer of a body that threw a [Cancelled] of its own
  /// sees `true` here as well. On a branch of [JobContext.runAll] it can
  /// still change after the body returned a value: a branch is held until
  /// the group decides, and a cancellation reaching it in that window
  /// ends it [Cancelled].
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
  /// Until the source finishes, the continuation is not running. It accepts a
  /// cancellation at once but still waits for the source, including its
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
  /// callbacks have run: before the body finishes, or, for a body that gives
  /// itself up by throwing [Cancelled], as it ends. For a job cancelled
  /// before start, it is when the job is dropped.
  ///
  /// If cancellation has already been accepted and its callbacks have run,
  /// calls [callback] immediately, even if the job has finished. Registering
  /// in between, while the cancellation cascades onto the children, puts the
  /// callback in that pass instead, after the ones registered before it. A
  /// refused or held cancellation does not trigger it; a held one triggers
  /// it when it is accepted. A job that ends [Done] or [Failed] without
  /// cancellation never calls it and releases its registrations on finish.
  /// Registering does not observe a [Failed] outcome.
  ///
  /// Each registration runs once. Pending callbacks run in registration
  /// order, from a snapshot: unregistering during notification does not remove
  /// a callback from that pass. Registering during notification calls the new
  /// callback immediately, ahead of the callbacks still waiting in that pass.
  /// Unregistering more than once is harmless.
  ///
  /// A synchronous error is one no outcome carries: [JobObserver.onError] hears
  /// it and an observer that is a [JobAnswerer] answers for it; by default, and
  /// without such an observer, it goes to the job's creation zone, and a thrown
  /// [Cancelled] is kept out of it. The error changes neither cancellation nor
  /// other callbacks. The callback is synchronous: an `async` callback's future
  /// is not awaited and its errors are not caught here.
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
  /// another cancellation does not replace it. Nor does a later one replace
  /// a cancellation an `uncancellable` section holds, with one exception: a
  /// cancellation the job cannot refuse, such as the one an engine of a
  /// domain makes for its rules, is not held, and the job accepts it at
  /// once and drops the held one. A body that gives itself up accepts one
  /// the same way, from the moment it throws: this call then finds the job
  /// already cancelled and waits for it, exactly as a second call does.
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

  /// Tells the core that nobody is interested in this job's failure.
  ///
  /// The counterpart of `Future.ignore`. A job that ends with [Failed]
  /// without ever being observed hands its error to the zone that created
  /// it; call this on a fire-and-forget job whose failure is already
  /// handled elsewhere, by a [JobObserver] of your own.
  ///
  /// ```dart
  /// Job<void>(observer: reporter, (ctx) => ctx.wait(device.close)).ignore();
  /// ```
  ///
  /// Waiting for [done] or [value] observes a [Failed] too: the one waiting has
  /// the error. A failure of the body that a cancellation covered afterwards —
  /// while the job waited for its children or ran its cleanup, say — is not in
  /// the outcome, and the one waiting gets the [Cancelled]. That failure is
  /// answered through [JobAnswerer.onUnanswered] of an observer that answers,
  /// otherwise in the zone, however the outcome was read, and this is what
  /// silences it. [JobObserver.onError] hears it either way.
  ///
  /// So it is for a child of [JobContext.run] and a branch of
  /// [JobContext.runAll] as well. A [Failed] their parent takes reaches the
  /// parent's caller whether or not this was called. A failure a cancellation
  /// covered, and that of a branch the group did not throw, do not reach the
  /// parent's caller, and this silences them. To answer for them differently
  /// instead, give the child an observer that is a [JobAnswerer] — the
  /// parent's is the child's unless the child has one of its own.
  ///
  /// Call it before the job ends, or at the latest from [JobObserver.onFinish]
  /// or a callback of [whenCancelled] registered before it ends. A failure a
  /// cancellation covered is answered as the job finishes, and a call from a
  /// listener of [done] comes too late for it.
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

  /// The body is running, its children are still finishing, or the core
  /// is cleaning up after them.
  running,

  /// The outcome is set and will not change.
  finished,
}

/// One registration on the cleanup stack of a job.
///
/// [always] tells the two kinds apart: a `dispose` registration runs whatever
/// the outcome, a `discard` one only when the value reached nobody. [value] is
/// set for registrations made by `wait`, `join` and `run`, and it is what
/// `disown` looks up.
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
  /// holds by itself — every cancellation the core builds carries a
  /// stack trace of its own.
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

  /// Whether anyone observed the outcome, directly or by forwarding it.
  bool _observed = false;

  /// Whether [Job.ignore] was called: nobody wants this job's failure.
  ///
  /// More than [_observed]. Whoever reads the outcome has the failure the
  /// outcome carries. A failure a cancellation covered is in no outcome, and
  /// one of a branch the group did not throw is in nothing the group passes on;
  /// only this keeps them from being answered for — see [_reportCovered] and
  /// `_RunAllGroup._conclude`.
  bool _ignored = false;

  /// The error of the last failure the core has announced for this job:
  /// the body's, where it was caught, the one a continuation received from
  /// its source, or one an engine of a domain handed to [finish]. The same
  /// error arriving by a second route — a body that throws what the engine
  /// has already ended the job with, say — is not announced again. By
  /// identity: two errors equal by `==` are still two errors.
  Object? _announcedError;

  /// Continuations still waiting to receive this outcome. A late listener
  /// may attach within the observation grace period but receive the result
  /// on the next microtask; give it that chance before reporting a failure.
  int _pendingContinuations = 0;

  JobStatus _status = JobStatus.created;
  Outcome<T>? _outcome;
  Cancelled? _pendingCancel;
  bool _bodyEnded = false;

  /// The failures on their way to the body that happened before anything
  /// marked the job, held weakly.
  ///
  /// The core reads the order at the throw, and a failure takes time to
  /// travel there: a microtask out of [JobContext.wait], several out of the
  /// callback or the source of [JobContext.each], all the time a child that
  /// failed spends on its own children and its cleanup, and
  /// [JobContext.uncancellable] lands the cancellation it was holding on
  /// the failure's way out. A cancellation arriving in that time would look
  /// first, and a failure that came first is a diagnosis it must not
  /// swallow. So every place a failure bound for the body passes through
  /// says so here, at the moment it happens. Every such failure and not
  /// only the latest: [JobContext.runAll] throws the first failure of its
  /// branches, and another branch may fail after it and before the mark.
  ///
  /// It names the error and not just the fact: a body that caught one of
  /// these and went on may fail again after the job accepted a
  /// cancellation, and that failure is not first; the same error thrown
  /// again is, and a constant error the body throws itself counts as the
  /// same one. Weakly, because a body that catches failures in a loop would
  /// otherwise hold every one of them until the job is over.
  Expando<bool>? _failedBeforeMark;

  /// The failures of [_failedBeforeMark] that an [Expando] cannot hold: a
  /// string, a number, a boolean or a record.
  ///
  /// Every one of them, as for objects: [JobContext.runAll] throws the
  /// first failure of its branches, another branch may fail with a string
  /// of its own before the mark, and both have to stay noted. Held
  /// strongly, because no weak reference can hold them, and by identity, so
  /// a body that throws the same constant in a loop keeps one entry. A body
  /// that catches distinct ones in a loop before any mark keeps them all
  /// until [finish] — and a record keeps whatever it references.
  Set<Object>? _plainFailedBeforeMark;

  static bool _isPlain(Object error) =>
      error is String || error is num || error is bool || error is Record;

  /// Notes [error] as a failure that came before any mark, if nothing has
  /// marked the job yet and it is not over.
  ///
  /// Once the job is over nothing reads the note, and [finish] has already
  /// let go of it. A call from work handed over with
  /// [JobContext.unattended], or from a body still playing out on a job an
  /// engine of a domain finished by hand, may fail after that, and a string
  /// or a record would then stay in [_plainFailedBeforeMark] for as long as
  /// the job lives.
  void _failedUnmarked(Object error) {
    if (_pendingCancel != null || isFinished) {
      return;
    }
    if (_isPlain(error)) {
      (_plainFailedBeforeMark ??= Set.identity()).add(error);
    } else {
      (_failedBeforeMark ??= Expando<bool>())[error] = true;
    }
  }

  /// Whether [error] was noted by [_failedUnmarked].
  bool _wasFailedUnmarked(Object error) => _isPlain(error)
      ? _plainFailedBeforeMark?.contains(error) ?? false
      : _failedBeforeMark?[error] ?? false;

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

  /// What the body ended with, from that moment until the job has an
  /// outcome of its own.
  ///
  /// A group of [JobContext.runAll] attaches its hold after the branch is
  /// admitted, and a body that throws before its first `await` has ended
  /// by then: the early word found nothing to say itself to. This is
  /// where the group reads what it was not there to hear.
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
  /// branch itself ends with. The other way round it does not work: a
  /// group that failed does not make a branch give up a value it hands
  /// over through [Job.value] all the same.
  bool _committedByGroup = false;

  /// Creates a job that has not started yet.
  JobBase({
    Object? key,
    String Function()? describe,
    bool cancellable = true,
    JobObserver? observer,
  })  : _key = key,
        _describe = describe,
        _cancellable = cancellable,
        _observer = observer {
    _builtOnCore[this] = true;
  }

  /// The jobs that went through this constructor.
  ///
  /// `is JobBase` answers yes to a class that implements the protocol
  /// instead of extending it — a mock, a fake — and such a job has none of
  /// the state the core adopts a child with: the first private field the
  /// core touches throws `NoSuchMethodError`. Asked here instead, it is
  /// refused as what it is, a job of no core.
  static final _builtOnCore = Expando<bool>('builtOnCore');

  /// Says what went nowhere when the value of this job went to somebody.
  ///
  /// Said out loud because the silence is the whole trouble. A conditional
  /// registration is settled by the outcome of the job that made it, so a
  /// value handed over takes none of them with it: from here on the
  /// resource belongs to whoever received it, and registering its release
  /// is theirs to do. Forget that, and nothing looks wrong until the
  /// receiver ends badly — and then the resource is simply lost, with no
  /// trace anywhere.
  void _traceDroppedCleanups() {
    if (_skipped.isEmpty) {
      return;
    }
    final count = '${_skipped.length} conditional '
        'cleanup${_skipped.length == 1 ? '' : 's'}';
    // Two ways to leave them behind, and the message must not mix them up.
    // Normally the job is still deciding and the value went to somebody.
    // But an engine of a domain may finish a job by hand while it unwinds,
    // and then the outcome is already something else and the value went
    // nowhere — saying it was handed over would be a plain lie.
    _debug(
      () => isFinished
          ? '$this was finished as $_outcome with $count left aside'
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
    try {
      debug(message());
    } on Object catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
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
      // The same rule as `_toZone`: a cancellation is a decision, not a
      // failure. A lazy message whose closure asks a job that has accepted
      // one throws it from `onLog`, and the zone can do nothing with it.
      if (_isCancellation(error)) {
        return;
      }
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
  void ignore() {
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

  @override
  void Function() whenCancelled(void Function(Cancelled) callback) {
    void guarded(Cancelled cancelled) {
      try {
        callback(cancelled);
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
    }

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
  Future<void> cancel({CancelReason reason = const ManualCancelReason()}) {
    cancelWith(
      Cancelled.by(
        reason: reason,
        started: true,
        stackTrace: StackTrace.current,
      ),
    );
    // The core's own waiting is not observation, so cancelling a job does
    // not silence its failure.
    return whenDone;
  }

  /// Cancels the job with [cancelled], correcting `started` to its status.
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
  /// A subclass extends this member rather than replacing it: `solo` adds
  /// the branch for a job still waiting in its queue and then calls
  /// `super`. An override that forgets the call silently switches
  /// cancellation off — for [Job.cancel], for the cascade from a parent and
  /// for whatever an engine of a domain adds.
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
        // Only a cancellation the job cannot refuse gets here inside a
        // section, and it is accepted over the one the section holds: that
        // one would never land, and `heldCancel` must not keep showing it.
        _heldCancel = null;
        // Marked before the cascade, and only marked: a callback of a child
        // may come back for this job, and the early return above is the only
        // thing that stops it from cascading and marking a second time.
        // What the marking brings with it — `whenCancelled` and the
        // callbacks — still waits for the children, because `solo` pins the
        // order in which a cancellation is seen.
        _pendingCancel = marked;
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
          // Skipped when a callback of a child reached the engine of a
          // domain and it ended the job by hand. A no-op by then rather
          // than a defect waiting to happen -- `finish` clears the
          // callbacks and tells the listeners itself -- and kept because
          // the phase a job is in decides who announces its cancellation,
          // and reading that off the status is cheaper than trusting the
          // two to stay in step. The window still has to close: it is
          // `_markCancelled` that closes it, and that path skips it.
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
    for (final child in _children.reversed.toList()) {
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
        // One child is not the rest of them. A subtree deep enough to run
        // the stack out, or an engine of a domain whose `cancelWith`
        // threw, must not take the cancellation away from the siblings
        // that come after it here -- and those siblings are not deep by
        // association: the one that overflows may be a chain of thousands
        // next to a leaf. The first failure is the one that leaves, the
        // way the first refusal leaves a group.
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
  /// Set when a cancellation the job may refuse arrives inside a section
  /// opened by [enterUncancellable], and cleared when the outermost section
  /// closes and lets it through. The job does not accept it meanwhile —
  /// [pendingCancel] stays `null` — so this is the only place such a
  /// request shows. A cancellation the job cannot refuse is not held: the
  /// job accepts it at once, and the one held until then is dropped and
  /// cleared here. So is one a section the body walked away from still
  /// holds when the body gives itself up or the job ends: it would land on
  /// a job already cancelled or over.
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
    cancelWith(held);
  }

  /// The children this job waits for; read-only.
  ///
  /// The way in is [JobContextBase.startChild] alone, which [JobContext.run],
  /// [JobContext.runAll] and [JobContext.each] go through: it sets the parent,
  /// the level and the observer of the child, and nothing else may put a job on
  /// this list — the core would wait for a child it never adopted.
  @protected
  List<JobBase<Object?>> get children => UnmodifiableListView(_children);

  /// Waiting without observing: an engine waits for a job to finish
  /// without marking its outcome observed, so a failure nobody looked at
  /// still reaches the zone.
  @protected
  Future<void> get whenDone => _done.future.then((_) {});

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
      // Ended while the context was being built -- an engine of a domain
      // asked a rule there and cancelled, or finished the job by hand. It
      // has its outcome, and a finished job does not run.
      return;
    }
    _status = JobStatus.running;
    // Guarded as `finished` is: the job is running by now, and an error of
    // the engine's bookkeeping left to escape would leave it running with
    // no body, and nothing would ever finish it.
    try {
      started();
    } on Object catch (error, stackTrace) {
      notifyError(error, stackTrace);
    }
    _notifyStart();
    unawaited(_execute(ctx));
  }

  /// Ends the job with [outcome].
  ///
  /// On a job that has already finished the outcome stays, the same as with
  /// [cancel]: an outcome is final, and an engine of a domain racing its own
  /// body must not be able to replace one. A [Failed] handed in there has no
  /// outcome to carry it, and it goes where the errors with no outcome go: to
  /// [JobObserver.onError] and to the answer of the observer — the zone unless
  /// it is a [JobAnswerer] — or to [JobObserver.onError] alone once
  /// [Job.ignore] was called.
  ///
  /// Ending a job that is still running is not a way to cancel it: this
  /// waits for no children and unwinds no cleanup stack, so everything the
  /// body opened stays open. Cancel with [cancelWith] instead, and let the
  /// body unwind; how many cleanups were left behind is in the debug
  /// trace.
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
  /// whatever is handed in. A [Done] is replaced, and its value goes
  /// nowhere and is closed by nobody: release it before calling this. A
  /// [Failed] is replaced too, and its error goes where a failure a
  /// cancellation covered goes — to [JobObserver.onError] and to the
  /// answer of the observer. A [Cancelled] handed in stands.
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
      if (outcome is Failed && !identical(outcome.error, _announcedError)) {
        _announcedError = outcome.error;
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
    // A [Cancelled] handed in is not that: the handle stays coherent, and
    // an engine of a domain ending a job from inside the cascade says how
    // it ended it -- that description is the whole diagnosis it has. The
    // route of the core hands the mark in itself, so nothing here is
    // about it.
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
    // A section the body walked away from may still hold a cancellation;
    // it would land on a job that is over, which drops it.
    _heldCancel = null;
    // The list of children is a waiting list, so it shrinks; the link from
    // an outcome to the child that carried it lives on, in the parent's
    // `Expando`. Both happen here, where they are observable: in `finished`
    // and in `onFinish` the parent's list is already without this child.
    // By identity, never by `==`: a job of a domain may compare itself by a
    // key, and two children equal by that key are still two jobs. Plain
    // `remove` would take the first equal one off the list and leave this
    // one on it — the parent would then wait for a job that is over and
    // walk away from one that is still running.
    final parent = _parent;
    if (parent != null) {
      parent._children.removeWhere((child) => identical(child, this));
      if (decided is Cancelled) {
        parent._outcomeChild[decided] = this;
      }
      // On its way to the parent's body through `run` or `value`. A failure
      // the body threw was noted when it was thrown; this is the one an
      // engine of a domain finishes the job with by hand.
      if (decided is Failed) {
        parent._failedUnmarked(decided.error);
      }
    }
    // A failure an engine of a domain hands in has been told to nobody,
    // unless the body threw the same error first. Announced here, once the
    // job is over, so an `onError` that cancels finds a finished job
    // instead of marking one that is about to end `Failed`; and before
    // `finished`, so the observer hears the error before the engine's
    // bookkeeping and `onFinish`. One handed in over the mark goes the way
    // of a covered failure below.
    if (decided is Failed &&
        replaced == null &&
        !identical(decided.error, _announcedError)) {
      _announcedError = decided.error;
      notifyObserver(decided.error, decided.stackTrace);
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
    _done.complete(decided);
    // Notify only after the domain has detached this job and delivered its
    // finish hooks: a synchronous subscriber may immediately add more work.
    if (decided is Cancelled) _notifyCancelled(decided);
    _cancelListeners.clear();
    // Let go of the graph. The handle stays -- it is kept precisely to be
    // read later, by a controller holding the last job, by a widget, by a
    // journal -- but nothing it reached through is of any use now: the
    // parent chain leads to jobs that are over, the group of
    // [JobContext.runAll] has taken its verdict, the outcome of the body
    // has become the outcome, and a failure noted on its way to the body
    // has arrived or never will. Held on, these turn one handle in a field
    // into the whole tree it came out of, every closure that tree captured
    // and an error with everything it references.
    _parent = null;
    _hold = null;
    _bodyOutcome = null;
    _failedBeforeMark = null;
    _plainFailedBeforeMark = null;
    if (decided is Failed && !_observed) {
      _reportUnobserved(decided);
    }
    // A failure handed in over the mark. The cancellation decides the
    // outcome, but an error is never lost silently: it goes where one the
    // body threw before a cancellation goes. It came in here and not
    // through the body, so nobody has announced it yet — unless the body
    // threw this very error, and then the body's route answers for it.
    if (replaced is Failed && !identical(replaced.error, _announcedError)) {
      _announcedError = replaced.error;
      _reportCovered(replaced, announced: false);
    }
  }

  /// Announces [error] to the observer and asks nobody to answer for it.
  ///
  /// For an error that has an outcome of its own — the body's. It reaches the
  /// zone through that outcome, if nobody observes it, and shouting twice about
  /// one error is worse than once. When a cancellation covers it afterwards,
  /// the outcome no longer carries it, and it is answered later without being
  /// announced again — unless [Job.ignore] was called, and then nobody answers
  /// for it. A [Failed] an engine of a domain hands to [finish] needs no call
  /// here: [finish] announces it itself. [notifyError] starts here too, and
  /// goes on to the answer.
  @protected
  void notifyObserver(Object error, StackTrace stackTrace) {
    _debug(() => '$this error: $error');
    _notify(() => _observer?.onError(this, error, stackTrace));
  }

  /// Announces [error] and asks for an answer to it.
  ///
  /// For the errors that have nowhere else to go: an action abandoned by
  /// [JobContext.wait] failing later, a disposer, a callback of
  /// [JobContext.onCancel] or [Job.whenCancelled], work handed over with
  /// [JobContext.unattended]. The observer hears it through
  /// [JobObserver.onError], and one that is a [JobAnswerer] answers for it
  /// through [JobAnswerer.onUnanswered], whose default body sends it to the
  /// zone the job was created in; without such an observer the error goes to
  /// that zone directly. Two calls, each guarded on its own: an `onError` that
  /// throws does not cost the error its answer.
  ///
  /// A cancellation — a [Cancelled], or a `ParallelWaitError` carrying
  /// nothing but cancellations — never reaches the zone from here: it is a
  /// decision somebody made, not a failure. An observer hears it through
  /// `onError`; without one, nobody does.
  @protected
  void notifyError(Object error, StackTrace stackTrace) {
    notifyObserver(error, stackTrace);
    _handleUnanswered(error, stackTrace);
  }

  /// Hands [error] to the zone the job was created in, unless it is a
  /// cancellation.
  ///
  /// For an engine of a domain whose own answer for an error with nowhere to go
  /// ends with the zone: `solo`, for example, sends one here when neither an
  /// override of `Solo.onUnanswered` nor `Solo.errorHandler` took it. The core
  /// reaches the zone by itself, through the default body of
  /// [JobAnswerer.onUnanswered], through [notifyError] without an observer that
  /// answers and through an unobserved [Failed]. A cancellation is held back
  /// here as it is there, so an engine of a domain does not write that rule
  /// again.
  @protected
  void reportToZone(Object error, StackTrace stackTrace) =>
      _toZone(error, stackTrace);

  /// Answers for [error] without announcing it.
  ///
  /// The observer's [JobAnswerer.onUnanswered], or the zone the job was created
  /// in when the observer does not answer or there is none. [notifyError] ends
  /// here, and so do two failures of a body: that of a branch of
  /// [JobContext.runAll] the group did not throw, and one a cancellation
  /// covered afterwards, unless [Job.ignore] was called on the job. The job
  /// told its observer itself, where its body was caught, and one error is
  /// announced once — but an error nobody answered for still has to reach
  /// somebody.
  ///
  /// An engine of a domain answers through the observer it puts on its
  /// jobs, as `solo` does: there is no second door.
  void _handleUnanswered(Object error, StackTrace stackTrace) {
    _debug(() => '$this error nobody answered for: $error');
    final observer = _observer;
    if (observer is! JobAnswerer) {
      _toZone(error, stackTrace);
      return;
    }
    _notify(() => observer.onUnanswered(this, error, stackTrace));
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
  /// rule: there the outcome decides, not the object it carries, so a
  /// failure somebody built out of a [Cancelled] on purpose still reaches
  /// the zone. A failure the outcome no longer carries — of a branch the
  /// group did not throw, or one a cancellation covered — has no outcome
  /// to decide, comes this way, and such a [Cancelled] stays out.
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
  /// the engine of the domain is left half-way through its own bookkeeping:
  /// keep it short and unconditional. `solo`, for example, clears `current`
  /// here and moves its queue on.
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
    // The outcome of a body that threw [cancelled]: the mark if there is
    // one, and otherwise its own decision to give up.
    Cancelled gaveUp(Cancelled cancelled, StackTrace stackTrace) {
      if (_pendingCancel case final pending?) {
        return pending;
      }
      final own = _handlerCancel(cancelled, stackTrace);
      // Read again: putting the cancellation into words runs the caller's
      // code -- the `toString` of a child's key, `onError` when that
      // throws -- and code that cancels this job in between marks it with
      // its own reason, which `whenCancelled` then hears. That one stands.
      return _pendingCancel ?? (selfCancelled = own);
    }

    try {
      outcome = Done(await execute(ctx));
    } on Cancelled catch (cancelled, stackTrace) {
      outcome = gaveUp(cancelled, stackTrace);
    } on Object catch (error, stackTrace) {
      final envelope = _analyzeEnvelope(error);
      if (envelope != null && envelope.isCleanCancellation) {
        outcome = gaveUp(
          envelope.firstCancelled!,
          envelope.firstStackTrace!,
        );
      } else {
        // Read before the observer hears: it is handed the job, and an
        // `onError` that cancels would otherwise make a failure that came
        // first look like it came second. The order is the whole diagnosis,
        // and it is settled at the moment of the throw.
        failedFirst = _pendingCancel == null || _wasFailedUnmarked(error);
        if (!identical(error, _announcedError)) {
          _announcedError = error;
          notifyObserver(error, stackTrace);
        }
        outcome = Failed(error, stackTrace);
      }
    }
    // The body has ended: from here a value coming out of a call it walked
    // away from can no longer reach it, and no child is started any more.
    _bodyEnded = true;
    _bodyOutcome = outcome;
    // On its way to the parent's body through `run` or `value` from this
    // moment, and it gets there only when this job is over: after its
    // children and its cleanup, which may take any time.
    if (outcome case Failed(:final error)) {
      _parent?._failedUnmarked(error);
    }
    if (selfCancelled != null) {
      // Marked before the children are waited for, and only marked. The
      // body gave itself up, so from here the job is cancelled to anyone
      // who asks -- `isCancelled`, `check`, a `cancel()` from outside --
      // and the decision it made is the one that stands: `cancelWith`
      // turns around at its own early return instead of laying another
      // reason over this one. Without the mark that whole wait was a
      // window: `isCancelled` answered `false`, a cancellation arriving
      // in it won by `??=`, and the children were left carrying a cause
      // their parent never had.
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
    }
    // The early word of a branch to its group: the siblings are asked to
    // stop while this one is still waiting for its own descendants. It
    // decides nothing and hands nothing over — what comes out of a group
    // is settled by the final outcomes, later and elsewhere. After the
    // classification and not before it: a clean envelope thrown by a child
    // is a cancellation here, not a failure.
    _hold?.bodyEnded(outcome);
    if (selfCancelled case final cancelled?) {
      // The rest of what `cancelWith` does, in its order: the children are
      // asked first, then the `onCancel` callbacks run and `whenCancelled`
      // hears it. A job whose body gives itself up no longer needs what
      // the body started any more than one cancelled from outside does.
      try {
        try {
          _cascadeToChildren(cancelled);
        } finally {
          // Skipped when a callback of a child reached the engine of a
          // domain and it ended the job by hand, as in `cancelWith`.
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
    await _awaitChildren();
    if (isFinished) {
      // An engine of a domain ended the job by hand while the body was
      // playing out: the outcome is not ours, the children were not waited
      // for, and the stack stays where it is.
      return;
    }
    // The outcome is decided, and the mark is already on: the body either
    // caught the one that was there or gave itself up and was marked
    // above. Asserted rather than assigned, so a path that ever arrives
    // here unmarked shows up as the defect it is instead of quietly
    // changing the reason the job ends with. Nothing is told here: both
    // paths told everyone when the mark went on.
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
      await hold.beforeDisposal();
      if (isFinished) {
        // An engine of a domain ended the branch by hand while it stood
        // there. A bare `return` would leave the phase where it is, and
        // the job would read as disposing for good. Nothing is put aside
        // yet -- the loops below are what fill that list -- so there is
        // nothing to say on the debug channel either.
        _disposing = false;
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

    if (_cleanups.isNotEmpty || hold != null) {
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
        if (!cleanup.always && valueHandedOver()) {
          _skipped.add(cleanup);
          continue;
        }
        await _runCleanup(cleanup);
      }
      if (hold != null) {
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
          _disposing = false;
          return;
        }
        // The stack is read again, and this pass is not the second one: a
        // branch at the barrier is not over, and an `onDispose` from a
        // background timer or an event of a domain lands on it legally.
        // Without this reading such a registration would never run at all.
        while (_cleanups.isNotEmpty) {
          final cleanup = _cleanups.removeLast();
          if (!cleanup.always && valueHandedOver()) {
            _skipped.add(cleanup);
            continue;
          }
          await _runCleanup(cleanup);
        }
      }
      // `removeAt(0)`, not `removeLast`: the skipped registrations were
      // collected in the order they came off the stack, and that is the
      // order they run in — the top one first, as if they had never been
      // put aside.
      while (_skipped.isNotEmpty && !valueHandedOver()) {
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
      _traceDroppedCleanups();
      _skipped.clear();
      _disposing = false;
    }
    final decided = _pendingCancel ?? outcome;
    finish(decided);
    // After `finish`, not before, and on the spot. `finished` and
    // `onFinish` run first, and an engine of a domain may still call
    // [Job.ignore] there; a parent's body hears the cancellation only
    // after the answer. Reading the outcome settles nothing here, so there
    // is no window to wait for.
    if (failedFirst && outcome is Failed && !identical(decided, outcome)) {
      _reportCovered(outcome, announced: true);
    }
  }

  /// Hands on an error the outcome does not carry.
  ///
  /// The body failed and a cancellation arrived afterwards, so the job ends
  /// [Cancelled] and the path that reports an unobserved [Failed] never runs.
  /// An engine of a domain can bring one here too: a [Failed] it hands to
  /// [finish] over the mark, or to a job that is already over. Whoever reads
  /// the outcome — [Job.value], [Job.done], [JobContext.run], a group of
  /// [JobContext.runAll] — gets the cancellation, or whatever the job ended
  /// with first, and not this, so reading it settles nothing. It is an error no
  /// outcome carries, answered the way the failure of a branch the group did
  /// not throw is: through [JobAnswerer.onUnanswered] of an observer that
  /// answers, otherwise in the zone. [announced] says whether
  /// [JobObserver.onError] has heard it already — a failure of the body was
  /// told where it was caught, one an engine of a domain handed to [finish] was
  /// told nowhere.
  ///
  /// [Job.ignore] takes the answer away and leaves the notice: one handed
  /// to [finish] is still told to [JobObserver.onError], once. An uncovered
  /// [Failed] needs no notice to be seen — the outcome shows it; this one
  /// the outcome does not show, and without the notice it would vanish.
  ///
  /// A job an engine of a domain ends by hand while a body that failed
  /// first waits for its children never comes here: the engine decided the
  /// outcome, and [JobObserver.onError] alone has heard the failure.
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
      // `whenDone`, not `done`: waiting for a child is the core's
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
  /// Runs the body, in the zone this is called from. Called inside the work
  /// of [JobContext.unattended], the job starts in the zone that work was
  /// started from, past any zone forked inside the work, as a job made in
  /// there does.
  ///
  /// Throws [StateError] if the job already ran, and also if it was
  /// cancelled before it started: a job dropped then is finished, and a
  /// finished job does not run.
  void start();
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
