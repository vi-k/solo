part of 'solo.dart';

/// The core context plus the state: what a job body of `solo` sees.
///
/// The state is narrowed to the job's working type `W`, and [emit] is the
/// only way to change it. Reading it is a checkpoint of its own: [state],
/// [stateAs] and [check] throw the job's [Cancelled] once its rules
/// stopped holding, and so does [each], whose child would keep them. [emit]
/// throws a [StateError] for a job that has already finished.
///
/// A child handed to [run], [start] or [runAll] is made by `job(...)` of the
/// same controller or by [child]. A `Job.deferred` of the core, or a job of
/// another controller, passes the types and is refused with an
/// [ArgumentError]:
///
/// ```dart
/// final name = await ctx.run(job<Idle, String>((child) => api.fetchName()));
/// ```
///
/// See [Children and chains](https://github.com/vi-k/solo/blob/main/packages/solo/doc/children.md)
/// for the rules a child starts under.
abstract interface class SoloContext<S extends Object, W extends S>
    implements JobContext {
  /// The current state.
  ///
  /// Throws [Cancelled] if the job is cancelled, if the state is not `W`, or
  /// if `keepWhile` returns `false`.
  W get state;

  /// [state] narrowed to `T`; cancels the job with `Cancelled(rules,
  /// 'is not T')` on mismatch.
  T stateAs<T extends S>();

  /// Sets the controller state.
  ///
  /// The new state is not checked against this job's rules; other running
  /// jobs are re-evaluated.
  ///
  /// A checkpoint on both sides. It throws the job's [Cancelled] before the
  /// write, as every member does, and again after it if the write cancelled
  /// this job on the way: hooks, observers and listeners run inside it and
  /// may set the state again, and a parent that goes down there takes its
  /// children with it. A delivery that throws comes first: its error is
  /// what `emit` throws, and a cancellation the write brought waits for
  /// the next checkpoint.
  ///
  /// ```dart
  /// ctx.emit(ctx.state.copyWith(loading: true));
  /// final name = await ctx.abandonable(api.fetchName);
  /// ctx.emit(Profile(name: name));
  /// ```
  void emit(S next);

  /// Makes an unstarted child of this controller under this job's rules, for
  /// [run], [start] and [runAll].
  ///
  /// The child gets a [SoloContext] of its own and keeps this job's working
  /// type `W` and `keepWhile` rule, so a state they refuse cancels it with
  /// `Cancelled(rules)`, at the start or while it runs. The rules are those
  /// of this job even when another job of the controller starts the child,
  /// and after this job's body ends. The `canStart` rule is not repeated, and
  /// the child is cancellable independently of the `cancellable` setting of
  /// this job.
  ///
  /// ```dart
  /// final rows = await ctx.run(ctx.child(load, key: 'rows', timeout: limit));
  /// ```
  ///
  /// The child has no `isExpectedError` of its own: it takes the one of the job
  /// whose body runs it, if that job has one.
  ///
  /// All other behavior is [JobContext.child]'s: [key] and [describe] only
  /// name the child, and the queue policies do not govern it.
  @override
  @useResult
  SoloJob<T> child<T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    String Function()? describe,
    Duration? timeout,
  });

  /// Runs [child], made by `job(...)` of this controller or by `ctx.child`,
  /// as a child of this job and returns its value.
  ///
  /// A `Job.deferred` of the core or a job of another controller is refused
  /// with an [ArgumentError], and a job already in the queue with a
  /// [StateError]. All other behavior is [JobContext.run]'s.
  ///
  /// ```dart
  /// final name = await ctx.run(job<Idle, String>((child) => api.fetchName()));
  /// ```
  @override
  Future<T> run<T>(
    ChildJob<T> child, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  });

  /// Starts [child], made by `job(...)` of this controller or by
  /// `ctx.child`, right now as a child of this job, and leaves its outcome to
  /// whoever holds it.
  ///
  /// Refuses the children [run] refuses. All other behavior is
  /// [JobContext.start]'s.
  ///
  /// ```dart
  /// ctx.start(job<Idle, void>((child) => sendReport(rows)));
  /// ```
  @override
  void start(ChildJob<Object?> child);

  /// Runs [children], each made by `job(...)` of this controller or by
  /// `ctx.child`, side by side, and stops the rest as soon as one of them goes
  /// wrong.
  ///
  /// Refuses the children [run] refuses. All other behavior is
  /// [JobContext.runAll]'s.
  @override
  Future<List<T>> runAll<T>(Iterable<ChildJob<T>> children);

  /// Starts a stream-processing child with its own [SoloContext].
  ///
  /// The child belongs to this controller and keeps the parent's working
  /// type `W` and `keepWhile` rule, including after the parent's body ends.
  /// The parent's `canStart` rule is not repeated. The child is cancellable
  /// independently of the parent's `cancellable` setting.
  ///
  /// A checkpoint of the parent's rules, as a read of [state] is: a state
  /// they refuse would refuse the child too, so this job's own [emit] of
  /// such a state, followed by `each`, ends this job [Cancelled] by the
  /// rules, and `each` throws it instead of handing back a child that never
  /// listened.
  ///
  /// The child has no `isExpectedError` of its own: it takes the one of this
  /// job, if there is one.
  ///
  /// Use the context passed to [onData] for [emit], state access and
  /// cancellation checkpoints. [key] and [describe] only name the child: the
  /// queue policies govern the root jobs of the controller, and the child is
  /// not one. All other behavior is [JobContext.each]'s.
  @override
  SoloJob<void> each<T>(
    Stream<T> stream,
    FutureOr<void> Function(SoloContext<S, W> ctx, T event) onData, {
    Object? key,
    String Function()? describe,
  });
}

final class _SoloContext<S extends Object, W extends S, R>
    extends JobContextBase
    implements SoloContext<S, W> {
  final _SoloJob<S, W, R> _job;

  _SoloContext(this._job) : super(_job);

  SoloController<S> get _solo => _job._solo;

  @override
  SoloJob<void> createEachJob(
    Future<void> Function(JobContext ctx) body, {
    Object? key,
    String Function()? describe,
  }) {
    // The child gets the parent's working type and `keepWhile`, so a state
    // they refuse would refuse it at the start, and `each` would hand back
    // a child that is over and never listened -- with nobody to read its
    // outcome, a stream nobody hears and a parent that ends `Done`. The
    // parent's own `emit` is how a body gets there, and the read that
    // follows such an `emit` cancels the parent; `each` does the same.
    // Called by the core after its refusals of unattended work and of a
    // body that has ended, so those come first. Its refusal of a job that
    // has already accepted a cancellation comes later, in `startChild`, and
    // is left to it: asked here, the rules would mark that job cancelled by
    // the rules too, which takes its `ifCancelled` away, and observers
    // would not see the child `startChild` drops, as they do for `run`.
    if (pendingCancel == null) {
      _checkedState();
    }
    return child<void>(body, key: key, describe: describe);
  }

  @override
  @useResult
  SoloJob<T> child<T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    String Function()? describe,
    Duration? timeout,
  }) {
    // Made for the core this job runs in, not the one that made it: a child
    // handed to a job of another core runs there.
    // A running job always has one: it was queued into a core or adopted
    // by a parent that runs in one.
    final core = _job._execution!;
    final controller = core.controller;
    if (controller is Solo<S>) {
      // Through the controller's own `job`, which a subclass may override;
      // it ends in `_makeJob`, as the other branch does.
      return controller.job<W, T>(
        body,
        key: key,
        describe: describe,
        keepWhile: _job._keepWhile,
        timeout: timeout,
      );
    }
    return controller._makeJob<W, T>(
      core,
      body,
      key: key,
      describe: describe,
      keepWhile: _job._keepWhile,
      timeout: timeout,
    );
  }

  // The core hands back the child that `createEachJob` above made, and that
  // one is a `SoloJob`.
  @override
  SoloJob<void> each<T>(
    Stream<T> stream,
    FutureOr<void> Function(SoloContext<S, W> ctx, T event) onData, {
    Object? key,
    String Function()? describe,
  }) =>
      super.each(
            stream,
            (child, event) => onData(child as SoloContext<S, W>, event),
            key: key,
            describe: describe,
          )
          as SoloJob<void>;

  @override
  void check() {
    super.check();
    _checkedState();
  }

  W _readState([String action = 'state']) {
    // The reads are closed while the engine cleans up after the body: a
    // read checks the rules against the state the body itself emitted, and
    // on a job that ended `Done` that would turn its outcome into a
    // cancellation by the rules — nobody cancelled it, the reading did.
    throwIfDisposing(action);
    throwIfCancelled();
    final state = _checkedState();
    // A read, not a checkpoint: `check` and every wait ask the rules too,
    // and the body has seen nothing there.
    _job._seenRevision = _solo._stateRevision;
    return state;
  }

  /// The state, once the rules of the job still hold for it.
  W _checkedState() {
    final current = _solo._state;
    final rejection = _job._rejectKeep(current);
    if (rejection != null) {
      final cancelled = Cancelled.by(
        reason: const RulesCancelReason(),
        description: rejection,
        stackTrace: StackTrace.current,
      );
      // The rules give the job up, so its handlers may not correct a state
      // the rules turned down. The reason cannot say it: anyone may build a
      // `RulesCancelReason` and pass it to `cancel`.
      _job._stateCorrectionRevoked = true;
      cancelOwnJob(cancelled);
      throw pendingCancel ?? cancelled;
    }
    // `keepWhile` is the caller's code, and it may have given the job up
    // while answering. A checkpoint that returned here would let the
    // member that called it start its action on a job already marked.
    throwIfCancelled();

    // The state the rules held for: `keepWhile` cannot write it while it
    // answers.
    return _solo._state as W;
  }

  @override
  W get state => _readState();

  @override
  T stateAs<T extends S>() {
    final current = _readState('stateAs');
    if (current is! T) {
      final cancelled = Cancelled.by(
        reason: const RulesCancelReason(),
        description: 'is not $T',
        stackTrace: StackTrace.current,
      );
      _job._stateCorrectionRevoked = true;
      cancelOwnJob(cancelled);
      throw pendingCancel ?? cancelled;
    }
    return current;
  }

  @override
  void emit(S next) {
    // The core's words say what happened and not where it came from: a
    // finished job is written to by a stream subscription or a future the
    // body started and did not wait for, and the text names the way out.
    if (_job.isFinished) {
      throw StateError(
        '$_job has already finished, cannot emit; code that outlived the '
        'body called it: await that code in the body, or take a stream with '
        'ctx.each',
      );
    }
    throwIfFinished('emit');
    throwIfCancelled();
    // `W` is a condition of the whole run, not only of the start, and a
    // body that emits its way out of it is cancelled by the rules at its
    // next checkpoint — far from this line, which is where the mistake is.
    SoloController._debug(
      () => next is W
          ? '$_job emit: $next'
          : '$_job emit: $next, which is not $W: the rules cancel $_job at '
                'its next checkpoint',
    );
    // A state read before a wait and written back after it undoes what
    // another lane wrote meanwhile, and nothing else says so: the write is
    // legal, and a snapshot from the server is written over on purpose.
    if (_solo._wroteSinceSeen(_job) case final lane?) {
      SoloController._debug(
        () =>
            '$_job emit over a write of lane $lane made after $_job last '
            'read the state: read ctx.state after the wait, or this write '
            'undoes the work of $lane',
      );
    }
    _solo._setState(next, emitter: _job);
    // The write is a checkpoint on both sides: hooks, observers and
    // listeners run inside `_setState` and may cancel this job — through a
    // reentrant `externalSetState` or through a parent going down with it.
    // The body must not walk past that. A delivery that throws leaves
    // before this line, and its failure is what the body hears first.
    throwIfCancelled();
  }

  @override
  Cancelled? beforeChildStart(JobBase<Object?> child) {
    // `run` has already asked `_own` whether the child is ours.
    final impl = child as _SoloJob<S, S, Object?>;
    // A rule that throws is not caught here: the core ends the child
    // `Failed`, tells its observer and hands the error to the body of the
    // parent, which may catch it.
    final rejection = impl._rejectStart(_solo._state);
    if (rejection != null) {
      return Cancelled.by(
        reason: const RulesCancelReason(),
        started: false,
        description: rejection,
        stackTrace: StackTrace.current,
      );
    }
    // A rule is the caller's code, and it may end the child while saying
    // yes: `cancel()` on a job that has not started finishes it where it
    // stands. Started anyway, it would throw `has already finished` into
    // the body of the parent; handed back, its own cancellation reaches
    // the parent the way a refusal does, as the root pump steps over such
    // a job.
    if (impl.outcome case final Cancelled cancelled) {
      return cancelled;
    }
    return null;
  }

  @override
  void startChild<T>(Job<T> child) {
    // Ownership is the parent's business: a bare job of the core has no
    // `adoptedBy` of ours to refuse it. The queue is asked by the child,
    // in `adoptedBy`.
    _solo._own(child);
    super.startChild(child);
  }
}
