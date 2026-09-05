import 'dart:async';

import 'package:meta/meta.dart';

import 'observer.dart';

part 'job_context.dart';
part 'outcome.dart';

/// A handle to a job: the outcome, the waiting and the cancellation.
///
/// Not a [Future]: calling a controller method without `await` is legal.
/// Await [done], [value] or [whenCancelled] where you need to.
///
/// A job that ends with [Failed] and is never observed hands its error to
/// the zone that created the job, the way Dart reports an unhandled
/// `Future` error. Touching [done], [value] or [ignore] counts as
/// observing it; see [ignore].
abstract interface class Job<T> {
  /// Creates a job and starts it on the next microtask.
  ///
  /// Not inside the constructor: the caller puts the handle in a variable
  /// first, listens to [done] if it wants to, and may cancel before the
  /// body ever runs — a job cancelled by then ends as
  /// `Cancelled(manual)` with `started: false`, and the body is never
  /// called.
  ///
  /// [ifCancelled] catches a value the body returned after the
  /// cancellation had already arrived; [observer] receives the hooks of
  /// this job, and a child inherits it unless given one of its own.
  ///
  /// ```dart
  /// final job = Job<Database>(
  ///   ifCancelled: (database) => database.close(),
  ///   (ctx) async {
  ///     final database = await ctx.join(Database.open);
  ///     await ctx.wait(() => database.migrate());
  ///
  ///     return database;
  ///   },
  /// );
  /// ```
  factory Job(
    Future<T> Function(JobContext ctx) body, {
    Object? key,
    String Function()? describe,
    bool cancellable,
    FutureOr<void> Function(T value)? ifCancelled,
    JobObserver? observer,
  }) = _AutoJob<T>;

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
    FutureOr<void> Function(T value)? ifCancelled,
    JobObserver? observer,
  }) =>
      _DeferredJob<T>(
        body,
        key: key,
        describe: describe,
        cancellable: cancellable,
        ifCancelled: ifCancelled,
        observer: observer,
      );

  /// The key given at creation; compared with `==` by policies and queue
  /// searches.
  Object? get key;

  /// The description given at creation, or an empty string.
  String describe();

  /// Nesting depth: 0 for a root job, `parent.level + 1` for a child.
  int get level;

  /// Whether this job was started by [JobContext.run].
  bool get isChild;

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
  /// handled elsewhere, by a [JobObserver] of your own.
  ///
  /// ```dart
  /// solo.run<Ready, void>((ctx) => ctx.wait(hw.close)).ignore();
  /// ```
  ///
  /// Waiting for [done] or [value] observes the job too; calling this
  /// afterwards changes nothing. Has no effect on [Cancelled], which is
  /// never reported to the zone.
  void ignore();
}

/// Where a job is in its life.
///
/// The queue is not here: it belongs to whoever runs jobs, not to the job.
enum JobStatus {
  /// Made, not started; the body has not run.
  created,

  /// The body is running, or its children are still finishing.
  running,

  /// The outcome is set and will not change.
  finished,
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
  final FutureOr<void> Function(T value)? _ifCancelled;

  /// Not final: a child created without one inherits the parent's
  /// observer when it is adopted.
  JobObserver? _observer;

  /// The zone the job was created in; an unobserved [Failed] goes here.
  final Zone _zone = Zone.current;

  final _done = Completer<Outcome<T>>();
  final _cancelled = Completer<void>();
  final _onCancel = <void Function()>[];
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

  JobBase<Object?>? _parent;

  bool _cancellable;

  /// Whether anyone asked for the outcome: [done], [value] or [ignore].
  bool _observed = false;

  JobStatus _status = JobStatus.created;
  Outcome<T>? _outcome;
  Cancelled? _pendingCancel;
  int _level = 0;

  /// Creates a job that has not started yet.
  JobBase({
    Object? key,
    String Function()? describe,
    bool cancellable = true,
    FutureOr<void> Function(T value)? ifCancelled,
    JobObserver? observer,
  })  : _key = key,
        _describe = describe,
        _cancellable = cancellable,
        _ifCancelled = ifCancelled,
        _observer = observer;

  static void _debug(String Function() message) {
    final debug = JobBase.debug;
    if (debug != null) {
      debug(message());
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
  Future<void> get whenCancelled => _cancelled.future;

  @override
  Future<void> cancel() {
    cancelWith(
      Cancelled.by(
        reason: CancelReason.manual,
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
  /// `cancellable: false` may refuse; the rules of a domain pass `false`,
  /// and a refusal is final — nothing is replayed later. Virtual: `solo`
  /// adds the branch for a job still waiting in its queue.
  @protected
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
        _debug(() => 'cancel $this: $marked');
        // Children first, deepest last started first, and the cascade is
        // rejectable: a child of its own mind refuses it.
        for (final child in _children.reversed.toList()) {
          child.cancelWith(
            Cancelled.by(
              reason: CancelReason.parent,
              started: true,
              stackTrace: marked.stackTrace,
            ),
          );
        }
        _markCancelled(marked);
    }
  }

  /// Where the job is in its life.
  @protected
  JobStatus get status => _status;

  /// The cancellation the job is marked with, or `null`.
  @protected
  Cancelled? get pendingCancel => _pendingCancel;

  /// Whether the job accepts a cancellation it may refuse.
  @protected
  bool get cancellable => _cancellable;

  @protected
  set cancellable(bool value) => _cancellable = value;

  /// Set by whoever adopts the job, before it starts.
  @protected
  set level(int value) => _level = value;

  /// The children this job waits for.
  @protected
  List<JobBase<Object?>> get children => _children;

  /// Waiting without observing: an engine waits for a job to finish
  /// without marking its outcome observed, so a failure nobody looked at
  /// still reaches the zone.
  @protected
  Future<void> get whenDone => _done.future.then((_) {});

  /// Runs the body. Throws [StateError] if the job already ran.
  @protected
  void start() {
    if (_status != JobStatus.created) {
      throw StateError('$this has already been added or run');
    }
    _status = JobStatus.running;
    started();
    _notifyStart();
    unawaited(_execute(createContext()));
  }

  /// Ends the job with [outcome].
  @protected
  void finish(Outcome<T> outcome) {
    _outcome = outcome;
    _status = JobStatus.finished;
    // A job cancelled before it started never went through `_markCancelled`,
    // so `whenCancelled` is still open here.
    if (outcome is Cancelled && !_cancelled.isCompleted) {
      _cancelled.complete();
    }
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
    finished();
    _notifyFinish();
    _done.complete(outcome);
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
  /// [JobContext.onCancel]. Silence is the choice of whoever listens, not
  /// the default of the package.
  @protected
  void notifyError(Object error, StackTrace stackTrace) {
    final observer = _observer;
    if (observer == null) {
      _zone.handleUncaughtError(error, stackTrace);
      return;
    }
    _debug(() => '$this error: $error');
    _notify(() => observer.onError(this, error, stackTrace));
  }

  /// The subclass joins the run: `solo` adds the job to its running list.
  @protected
  void started() {}

  /// The subclass leaves the run: `solo` clears `current` and pumps.
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

  void _notifyLog(String message) =>
      _notify(() => _observer?.onLog(this, message));

  Future<void> _execute(JobContextBase ctx) async {
    Outcome<T> outcome;
    try {
      outcome = Done(await execute(ctx));
    } on Cancelled catch (cancelled, stackTrace) {
      outcome = _pendingCancel ?? _handlerCancel(cancelled, stackTrace);
    } on Object catch (error, stackTrace) {
      notifyObserver(error, stackTrace);
      outcome = Failed(error, stackTrace);
    }
    await _awaitChildren();
    // The window the body cannot close: between its `return` and the
    // engine's decision the job is still alive — it waits for its children
    // — and a cancellation arriving there beats a value already computed.
    // Children first: they may still be using it.
    final disposer = _ifCancelled;
    if (disposer != null && _pendingCancel != null && outcome is Done<T>) {
      try {
        await disposer(outcome.value);
      } on Object catch (error, stackTrace) {
        notifyError(error, stackTrace);
      }
    }
    finish(_pendingCancel ?? outcome);
  }

  /// The body threw [thrown] without being marked cancelled: either its own
  /// `throw Cancelled(...)` or a child's cancellation via `child.value`.
  Cancelled _handlerCancel(Cancelled thrown, StackTrace stackTrace) {
    final child = _outcomeChild[thrown];
    if (child != null) {
      return Cancelled.by(
        reason: CancelReason.handler,
        started: true,
        description: 'child ${child.key}: $thrown',
        stackTrace: stackTrace,
      );
    }
    return Cancelled.by(
      reason: CancelReason.handler,
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
      _debug(() => '$this failure went to the zone');
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

/// A job that starts when it is told to.
abstract interface class DeferredJob<T> implements Job<T> {
  /// Runs the body. Throws [StateError] if the job already ran.
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
    super.ifCancelled,
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
    super.ifCancelled,
    super.observer,
  }) {
    // `scheduleMicrotask`, not `Future(...)`: that one schedules a timer,
    // and under `FakeAsync` the start would need `flushTimers`.
    scheduleMicrotask(() {
      // Idempotent: someone may have run this job as a child in the same
      // synchronous stripe, and then this microtask does nothing.
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
    super.ifCancelled,
    super.observer,
  });

  @override
  void start() => super.start();
}
