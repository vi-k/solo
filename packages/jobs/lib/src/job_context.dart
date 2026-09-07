part of 'job_base.dart';

/// What a job body sees in the core: cancellation, waiting and children.
///
/// Every member except [log], [job], [onDispose] and [onDiscard] refuses to
/// run for a job already marked cancelled: it throws that [Cancelled].
/// What a cancellation arriving *during* a call does to that call is the
/// call's own business — see [wait], [join] and [uncancellable].
///
/// A context that outlived its job — captured by a closure nobody awaited
/// — neither waits nor starts anything: [run], [wait], [join],
/// [uncancellable] and [onCancel] throw a [StateError] once the job has
/// finished. [check] and [log] stay legal.
///
/// While the engine cleans up after the body — after the children, before
/// the outcome — the context of the body is closed: everything but [log],
/// [job] and the registration of more cleanups throws a [StateError]. A
/// disposer takes what it needs from its closure.
abstract interface class JobContext {
  /// Gives up if the job was cancelled — in `solo`, also if its rules
  /// stopped holding.
  ///
  /// [join] is the same thing around a call. Reach for `check` where there
  /// is no call to wrap: a loop over work of your own, a `switch` after
  /// one.
  void check();

  /// Runs [action] and waits for it, but no longer than this job lives.
  ///
  /// Throws [Cancelled] up front if the job is already cancelled or its
  /// rules no longer hold. If a cancellation arrives while [action] is in
  /// flight, the wait ends there with that [Cancelled] — and [action] runs
  /// on, its result discarded, an error of its own going to `onError`. It
  /// ends the waiting, not the work.
  ///
  /// For anything that must actually stop — a device, a download, a write —
  /// hand the cancellation to it through [onCancel] and wait for it to
  /// finish with [join], instead of walking away from it. For a step that
  /// must not be interrupted at all, see [uncancellable].
  ///
  /// [ifCancelled] picks up that discarded result: a value arriving after
  /// the wait is over goes there instead of on the floor, so a connection
  /// or a file opened by an abandoned action still gets closed. It runs
  /// late and alone — the job is over by then and nothing waits for it,
  /// not even the closing of an engine. A late error goes to `onError` as
  /// always,
  /// and so does an error of [ifCancelled] itself.
  ///
  /// ```dart
  /// final db = await ctx.wait(
  ///   Database.open,
  ///   ifCancelled: (db) => db.close(),
  /// );
  /// ```
  Future<T> wait<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? ifCancelled,
  });

  /// Runs [action], waits for all of it, and gives up only afterwards.
  ///
  /// The counterpart of [wait] for a call that must not be left in flight:
  /// a device command, a write already on the wire. A cancellation
  /// arriving while [action] runs is accepted — the job is marked, and an
  /// engine waiting for the job waits too, because the body is still
  /// inside this call —
  /// but the waiting is not cut short. When [action] comes back, this
  /// throws that [Cancelled]; if none arrived, it returns [action]'s
  /// value.
  ///
  /// ```dart
  /// await ctx.join(() => device.write(chunk));
  /// ```
  ///
  /// [wait] lets go of the action, `join` stays with it, so the next job
  /// never starts against a device still finishing this one, and a body
  /// written this way cannot walk past a cancellation by forgetting a
  /// line.
  ///
  /// The value is dropped when the job gives up: the throw happens inside
  /// this call, and the body is never reached. For an [action] that hands
  /// something over to own — a connection, a file, a subscription — pass
  /// [ifCancelled], and it gets that value instead. It is awaited before
  /// the [Cancelled] is thrown, so an engine waiting for the job waits for
  /// the disposal too, and the next job starts with the resource gone. Only a
  /// value is handed over: an [action] that threw has nothing to dispose
  /// of.
  ///
  /// ```dart
  /// final db = await ctx.join(
  ///   Database.open,
  ///   ifCancelled: (db) => db.close(),
  /// );
  /// ```
  ///
  /// An error from [action] is thrown as it is, cancelled or not, and the
  /// body can catch it like any other. An error from [ifCancelled] goes to
  /// `onError`, and the [Cancelled] is thrown all the same. Throws
  /// [Cancelled] up front if the job is already cancelled or its rules no
  /// longer hold, the same as [wait] and [uncancellable].
  Future<T> join<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? ifCancelled,
  });

  /// Runs [action] with the cancellation held back, and waits for it.
  ///
  /// The counterpart of [wait], for a step that cannot be taken back: a
  /// payment on its way to the server, a write already on the wire. While
  /// [action] runs the job is not marked at all, so [Job.cancel], a
  /// cancelled parent and whatever an engine of a domain adds — a queue, a
  /// closing — reach neither an [onCancel] callback nor a child, and the
  /// engine waits for the body instead of interrupting it.
  ///
  /// ```dart
  /// final receipt = await ctx.uncancellable(() => api.pay(order));
  /// ```
  ///
  /// Held, not refused: the cancellation lands the moment the section
  /// closes, and the next member of the context throws it. So the step is
  /// protected, and the job still ends up cancelled — anything after the
  /// step that has to happen anyway belongs inside the same section, and a
  /// job that must survive a cancellation altogether is created with
  /// `cancellable: false`. That refusal is final and is what a section
  /// leaves alone. Sections nest — only the outermost lets a held
  /// cancellation through — and it is let through even if [action] throws.
  ///
  /// This is what separates it from [join], which accepts the
  /// cancellation as it arrives and only keeps waiting: there the job is
  /// marked at once, and a token handed to [onCancel] stops the very call
  /// being waited for.
  ///
  /// The rules an engine of a domain adds are not covered: `solo` cancels
  /// a job whose state left its working type whatever this does, and the
  /// body learns about it at its next read as always.
  ///
  /// Throws [Cancelled] if the job is already cancelled, the same as
  /// [wait]: a step that cannot be taken back must not begin for a job
  /// that is already over.
  Future<T> uncancellable<T>(FutureOr<T> Function() action);

  /// Registers [callback] to run the moment the job is marked cancelled,
  /// before the body itself learns about it. Returns a function that
  /// unregisters it.
  ///
  /// This is how a cancellation reaches something that can really stop:
  /// a device's own cancel token, an HTTP client's abort, a subscription.
  ///
  /// ```dart
  /// final token = CancelToken();
  /// ctx.onCancel(token.cancel);
  /// // The device stops by itself, and `join` waits for it to finish
  /// // before the job ends and the next one starts.
  /// await ctx.join(() => device.seek(position, cancelToken: token));
  /// ```
  ///
  /// Throws [Cancelled] if the job is already cancelled: there is nothing
  /// to register for, and nothing should be started either. An error thrown
  /// by [callback] goes to `onError` and stops there; the cancellation
  /// itself is not affected and the other callbacks still run.
  void Function() onCancel(void Function() callback);

  /// Registers [disposer] to run when the job ends, whatever the outcome.
  ///
  /// The engine unwinds the stack after the children and before the
  /// outcome, last registration first, and it waits for every disposer.
  /// Returns a function that unregisters this one; calling it twice, or
  /// after the disposer has run, is safe.
  ///
  /// A disposer runs outside the body: nothing cancels it and nothing
  /// interrupts it, so keep it short and unconditional. It must not wait
  /// for its own job — `job.done`, `job.value` and `job.cancel()` all
  /// complete after the cleanup that would be waiting for them — nor for
  /// a job of the same queue.
  ///
  /// ```dart
  /// final lock = await ctx.join(Lock.acquire);
  /// ctx.onDispose(lock.release);
  /// ```
  void Function() onDispose(FutureOr<void> Function() disposer);

  /// Registers [disposer] to run only if the job ends without handing its
  /// value over: cancelled, or failed.
  ///
  /// For what the body returns or hands outside; everything else — a lock,
  /// a temporary file, a subscription — takes [onDispose], or it leaks on
  /// the successful path, where no test on cancellation will see it.
  /// Returns a function that unregisters it.
  ///
  /// ```dart
  /// final database = await ctx.join(Database.open);
  /// ctx.onDiscard(database.close);
  ///
  /// return database;
  /// ```
  void Function() onDiscard(FutureOr<void> Function() disposer);

  /// Starts [child] right now, as a child of this job, ahead of whatever
  /// an engine of a domain would have put it through.
  ///
  /// Returns the same handle; the parent finishes only after all its
  /// children. A cancellation of the parent cascades onto them, and a
  /// child created with `cancellable: false` refuses that cascade.
  ///
  /// Throws [ArgumentError] for a handle that is not a job of this kernel,
  /// or one an engine of a domain does not own; [StateError] for a job
  /// that has already been started; and the parent's own [Cancelled], with
  /// the child dropped, if the parent is already cancelled.
  Job<T> run<T>(Job<T> child);

  /// Sends `message.toString()` to [JobObserver.onLog]. A no-op when the
  /// job has no observer.
  void log(Object? message);

  /// The job this context belongs to.
  Job<Object?> get job;
}

/// The base of a job context: everything a body does without a state.
///
/// Subclass it to add a domain of your own; `solo` adds the state and its
/// rules. [check] is the checkpoint, and it is virtual on purpose: a
/// domain checks more than the cancellation, and [wait], [join] and
/// [uncancellable] all go through it.
abstract class JobContextBase implements JobContext {
  final JobBase<Object?> _owner;

  /// A plain positional parameter, not `this._owner`: a subclass writes
  /// `MyContext(super.owner)`, and a private name cannot be used there.
  JobContextBase(JobBase<Object?> owner) : _owner = owner;

  @override
  Job<Object?> get job => _owner;

  @override
  void check() {
    throwIfDisposing('check');
    throwIfCancelled();
  }

  /// The cancellation the job is marked with, or `null`.
  @protected
  Cancelled? get pendingCancel => _owner._pendingCancel;

  /// Throws the job's cancellation if it is marked.
  @protected
  void throwIfCancelled() {
    final cancelled = _owner._pendingCancel;
    if (cancelled != null) {
      throw cancelled;
    }
  }

  /// Throws [StateError] if the job has finished: a context that outlived
  /// its job neither writes nor starts anything. Also throws while the
  /// engine unwinds the cleanup stack — see [throwIfDisposing].
  @protected
  void throwIfFinished(String action) {
    if (_owner.isFinished) {
      throw StateError('$_owner has already finished, cannot $action');
    }
    throwIfDisposing(action);
  }

  /// Throws [StateError] while the engine unwinds the cleanup stack.
  ///
  /// The body is gone and the outcome is decided, so nothing of the body
  /// runs any more: a disposer takes what it needs from its closure and
  /// asks `job.isCancelled` about the outcome. Reads go through this one
  /// alone — after the job has finished they stay legal, as they were.
  @protected
  void throwIfDisposing(String action) {
    if (_owner.isDisposing) {
      throw StateError('$_owner is disposing, cannot $action');
    }
  }

  /// Hands [error] to the observer, or to the zone when there is none.
  @protected
  void notifyError(Object error, StackTrace stackTrace) =>
      _owner.notifyError(error, stackTrace);

  /// Registers [callback] past the public [onCancel]: the race inside
  /// [wait] needs a raw one, unguarded and removable. Returns a remover.
  @protected
  void Function() addCancelCallback(void Function() callback) {
    _owner._onCancel.add(callback);
    return () => _owner._onCancel.remove(callback);
  }

  /// Cancels the owner with a cancellation it cannot refuse: the rules of
  /// a domain come here, and they cancel a job whatever `cancellable`
  /// says.
  @protected
  void cancelOwnJob(Cancelled cancelled) =>
      _owner.cancelWith(cancelled, rejectable: false);

  /// Whether the job accepts a cancellation it may refuse, as it was
  /// created; an uncancellable section does not change it.
  @protected
  bool get cancellable => _owner._cancellable;

  /// Opens an uncancellable section on the owner: a rejectable
  /// cancellation arriving now is held until the section closes. Sections
  /// nest, and every one of them is closed by [leaveUncancellable].
  @protected
  void enterUncancellable() => _owner.enterUncancellable();

  /// Closes a section opened by [enterUncancellable]; the outermost one
  /// lets a held cancellation through.
  @protected
  void leaveUncancellable() => _owner.leaveUncancellable();

  /// The parent's last word before a child starts; `solo` checks the start
  /// rules here. A non-null result finishes the child with it.
  @protected
  Cancelled? beforeChildStart(JobBase<Object?> child) => null;

  @override
  Future<T> join<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? ifCancelled,
  }) async {
    throwIfFinished('join');
    check();
    final result = await action();
    try {
      check();
    } on Cancelled {
      if (ifCancelled != null) {
        await _dispose(ifCancelled, result);
      }
      rethrow;
    }
    return result;
  }

  /// Hands [value] to the body's own disposer. Its error belongs to
  /// `onError`: the job is already giving up, and a failed disposal must
  /// not stand in for the cancellation the body is waiting for.
  Future<void> _dispose<T>(
    FutureOr<void> Function(T value) ifCancelled,
    T value,
  ) async {
    try {
      await ifCancelled(value);
    } on Object catch (error, stackTrace) {
      notifyError(error, stackTrace);
    }
  }

  @override
  Future<T> uncancellable<T>(FutureOr<T> Function() action) async {
    throwIfFinished('run an uncancellable action');
    check();
    enterUncancellable();
    try {
      return await action();
    } finally {
      leaveUncancellable();
    }
  }

  @override
  void Function() onCancel(void Function() callback) {
    throwIfFinished('register onCancel');
    throwIfCancelled();
    void guarded() {
      // A callback of the caller's, run from inside the engine's own
      // cancellation: its error belongs to `onError`, not to whoever
      // happened to trigger the cancel.
      try {
        callback();
      } on Object catch (error, stackTrace) {
        notifyError(error, stackTrace);
      }
    }

    return addCancelCallback(guarded);
  }

  /// Puts a registration on the cleanup stack of the owner.
  ///
  /// The public [onDispose] and [onDiscard] are this with [value] unset;
  /// `wait` and `join` pass the value they hand to the body, so that
  /// `disown` can find the registration by it. Registering stays open on a
  /// job already cancelled and while the engine unwinds the stack —
  /// refusing it is the trap this whole mechanism removes.
  @protected
  void Function() addCleanup(
    FutureOr<void> Function() disposer, {
    required bool always,
    Object? value,
  }) {
    if (_owner.isFinished) {
      throw StateError(
        '$_owner has already finished, cannot register a cleanup',
      );
    }
    final cleanup = _Cleanup(disposer, always: always, value: value);
    _owner._cleanups.add(cleanup);
    return () => _owner._cleanups.remove(cleanup);
  }

  @override
  void Function() onDispose(FutureOr<void> Function() disposer) =>
      addCleanup(disposer, always: true);

  @override
  void Function() onDiscard(FutureOr<void> Function() disposer) =>
      addCleanup(disposer, always: false);

  @override
  Future<T> wait<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? ifCancelled,
  }) async {
    throwIfFinished('wait');
    check();
    final result = action();
    if (result is! Future<T>) {
      return result;
    }
    return _race(result, ifCancelled);
  }

  /// Completes with [future] or with the job's cancellation, whichever
  /// comes first. A result arriving after cancellation goes to
  /// [ifCancelled], or nowhere if there is none; an error arriving after
  /// cancellation goes to `onError`.
  Future<T> _race<T>(
    Future<T> future,
    FutureOr<void> Function(T value)? ifCancelled,
  ) {
    final completer = Completer<T>();
    late final void Function() remove;
    void onCancel() {
      if (!completer.isCompleted) {
        final cancelled = pendingCancel!;
        completer.completeError(
          cancelled,
          cancelled.stackTrace ?? StackTrace.current,
        );
      }
    }

    Future<void> forward() async {
      try {
        final value = await future;
        if (completer.isCompleted) {
          if (ifCancelled != null) {
            await _dispose(ifCancelled, value);
          }
        } else {
          completer.complete(value);
        }
      } on Object catch (error, stackTrace) {
        if (completer.isCompleted) {
          notifyError(error, stackTrace);
        } else {
          completer.completeError(error, stackTrace);
        }
      } finally {
        remove();
      }
    }

    remove = addCancelCallback(onCancel);
    // The action may have cancelled this job while it ran: `_markCancelled`
    // already emptied the callbacks, so the registration above would never
    // be called and the body would wait for the full action for nothing.
    if (pendingCancel != null) {
      onCancel();
    }
    unawaited(forward());
    return completer.future;
  }

  @override
  Job<T> run<T>(Job<T> child) {
    throwIfFinished('run a child');
    if (child is! JobBase<T>) {
      throw ArgumentError.value(child, 'child', 'is not a job of this core');
    }
    if (child.status != JobStatus.created) {
      throw StateError(
        child.status == JobStatus.running
            ? '$child is already running'
            : '$child has already finished',
      );
    }
    child
      ..adoptedBy(this)
      .._observer ??= _owner._observer
      .._parent = _owner
      ..level = _owner.level + 1;
    _owner.children.add(child);
    final pending = _owner.pendingCancel;
    if (pending != null) {
      child.cancelWith(
        Cancelled.by(
          reason: CancelReason.parent,
          started: false,
          stackTrace: pending.stackTrace,
        ),
      );
      throw pending;
    }
    final rejection = beforeChildStart(child);
    if (rejection != null) {
      child.finish(rejection);
      return child;
    }
    child.start();
    return child;
  }

  @override
  void log(Object? message) => _owner._notifyLog('$message');
}

/// The context of a job of the core itself.
final class _CoreContext extends JobContextBase {
  _CoreContext(super.owner);
}
