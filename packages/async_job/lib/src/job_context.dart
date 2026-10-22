part of 'job_base.dart';

/// What a job body sees in the core: cancellation, waiting and children.
///
/// Once the job has accepted a cancellation, the members that wait or start
/// something throw that [Cancelled]: [check], [abandonable], [join], [pause],
/// [uncancellable], [onCancel], [run], [runAll] and `each`. The members that
/// only register do not — [onDispose], [onDiscard], [disown] and [unattended]
/// go on working, so a body that has just been cancelled can still put what it
/// holds on the cleanup stack, and still hand out a stop nobody waits for — and
/// neither do [log], [job] and [heldCancellation]. What a cancellation
/// arriving *during* a call does to that call is the call's own business: see
/// [abandonable], [join], [pause] and [uncancellable].
///
/// A context that outlived its job — captured by a closure nobody awaited
/// — neither waits nor starts nor registers anything: every member throws
/// a [StateError] once the job has finished, except [check], [log], [job]
/// and [heldCancellation]. While the core unwinds the cleanup stack the same
/// holds for the members that wait or start something, and for [check] on a
/// job that is not cancelled — but [onDispose], [onDiscard], [disown] and
/// [unattended] go on working, because a value arriving that late is put on
/// the stack the core is unwinding, and a disposer may hand out work nobody
/// waits for.
abstract interface class JobContext {
  /// Gives up if the job was cancelled, or if a rule its engine adds stopped
  /// holding.
  ///
  /// `solo`, for example, gives up here once the rules of the job stopped
  /// holding.
  ///
  /// [join] is the same thing around a call. Reach for `check` where there
  /// is no call to wrap: a loop over work of your own, a `switch` after
  /// one.
  ///
  /// Legal after the job has finished, where it throws the [Cancelled] the
  /// job ended with, if any. While the core cleans up after the body it
  /// throws the cancellation of a cancelled job as well, so an action the
  /// body walked away from that polls `check` to stop sees the cancellation
  /// it waits for. On a job that is not cancelled it throws a [StateError]
  /// there instead: the body is gone, and no rule is asked for it any more.
  void check();

  /// Runs [action] and waits for it, but no longer than this job lives.
  ///
  /// Throws [Cancelled] up front if the job is already cancelled or its rules
  /// no longer hold. If a cancellation arrives while [action] is in flight, the
  /// wait ends there with that [Cancelled], and [action] runs on: its result is
  /// dropped, and an error of its own goes to `onError` and on to the job's
  /// answer. **It ends the waiting, not the work:** for anything that must
  /// actually stop — a device, a download, a write — hand the cancellation to
  /// it through [onCancel] and wait for it to finish with [join].
  ///
  /// ```dart
  /// final db = await ctx.abandonable(
  ///   Database.open,
  ///   discard: (db) => db.close(),
  /// );
  /// ```
  ///
  /// [dispose] runs whatever the outcome, [discard] unless the job ends
  /// [Done], and passing both is an [ArgumentError]. A value that did not reach
  /// the body is released without a condition, at once. A value that comes to
  /// a call the body walked away from without a cancellation still goes to
  /// whoever holds its future, and waits for the unwinding on the stack. The
  /// core catches a late value from the moment it learns the body has ended,
  /// not from its `return`, so a call that gives out a resource is not one to
  /// walk away from.
  ///
  /// Left unawaited on purpose, write the type out —
  /// `unawaited(ctx.abandonable<Db>(...))`: without it `T` is inferred from
  /// `unawaited` as `void`, and [dispose] has to take `void`. While the body
  /// runs, what such a call throws, its [Cancelled] included, goes to the zone.
  ///
  /// See [Stopping the operation](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cancellation.md#stopping-the-operation)
  /// on the cancellation page and
  /// [A value that comes late](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cleanup.md#a-value-that-comes-late)
  /// on the cleanup page.
  Future<T> abandonable<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  });

  /// The former name of [abandonable], kept for one release.
  ///
  /// Does what [abandonable] does; only the [StateError] of a call made
  /// after the job has finished names `wait`.
  @Deprecated('Use abandonable')
  Future<T> wait<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  });

  /// Runs [action], waits for all of it, and gives up only afterwards.
  ///
  /// For a call that must not be left in flight: a device command, a write
  /// already on the wire. A cancellation arriving while [action] runs is
  /// accepted at once, but the waiting is not cut short: when [action] comes
  /// back, this throws that [Cancelled], and if none arrived, it returns
  /// [action]'s value. Throws [Cancelled] up front if the job is already
  /// cancelled or its rules no longer hold. An error from [action] is thrown
  /// as it is, cancelled or not — **so await this call:** a body that walked
  /// on lets that error reach a future nobody awaits, and Dart hands it to the
  /// zone, past the job's observer.
  ///
  /// ```dart
  /// await ctx.join(() => device.write(chunk));
  /// ```
  ///
  /// The value is dropped when the job gives up, unless [dispose] or [discard]
  /// takes it. A value that did not reach the body is released on the spot,
  /// and here that is awaited before the [Cancelled] is thrown, so the next job
  /// starts with the resource gone; one that did goes on the cleanup stack, as
  /// in [abandonable]. Passing both is an [ArgumentError]. The checkpoint after
  /// [action] releases the value whatever it throws, a rule of a domain that
  /// throws included. An error from the disposer goes to `onError` and on to
  /// the job's answer, and the [Cancelled] is thrown all the same.
  ///
  /// See [A token through `onCancel`](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cancellation.md#a-token-through-oncancel)
  /// on the cancellation page.
  Future<T> join<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  });

  /// Runs [action] with the cancellation held back, and waits for it.
  ///
  /// For a step that cannot be taken back: a payment on its way to the server,
  /// a write already on the wire. While [action] runs the job accepts no
  /// cancellation it may refuse, so neither an [onCancel] callback nor a child
  /// hears one, and the core waits for the body. Throws [Cancelled] up front
  /// if the job is already cancelled. **Held, not refused:** the job accepts
  /// the cancellation as the section closes and still ends cancelled, so what
  /// has to happen after the step anyway belongs inside the section, and
  /// `return ctx.uncancellable(...)` carries no value out — the outcome is
  /// [Cancelled], and the registrations of [onDiscard] run. [heldCancellation]
  /// tells the step whether a cancellation is held, so it can keep what it
  /// made.
  ///
  /// ```dart
  /// final receipt = await ctx.uncancellable(() => api.pay(order));
  /// ```
  ///
  /// Sections nest, and only the outermost lets a held cancellation through,
  /// even if [action] throws. A cancellation the job cannot refuse, such as a
  /// rule an engine adds, is not held: the job ends with its reason, and the
  /// held one never lands. Always await this call: the section belongs to the
  /// job, not to the future, and one still open after the body lands its
  /// cancellation late — dropped on a job that is over, or made the outcome
  /// over the body's value while a child still runs.
  ///
  /// A section also keeps an asynchronous hand-over together with its
  /// [disown]: the step is a bare `await`, not [join], and between it and the
  /// `disown` stands nothing that throws this job's cancellation — no member
  /// of this context, no `await child.value` — because a cancellation the
  /// rules of a domain make is not held.
  ///
  /// See [Holding the cancellation back](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cancellation.md#holding-the-cancellation-back)
  /// on the cancellation page.
  Future<T> uncancellable<T>(FutureOr<T> Function() action);

  /// Waits for [duration], or until the job is cancelled.
  ///
  /// A checkpoint that takes time: it throws [Cancelled] up front if the job
  /// is already cancelled or its rules no longer hold, and a cancellation
  /// that arrives during the pause ends it there, with that [Cancelled].
  /// Without a [duration] it comes back on the next turn of the event loop,
  /// as a timer of zero length does; a negative one counts as zero.
  ///
  /// Use it wherever a body would write `Future.delayed`. Awaited bare, that
  /// one is no checkpoint, and a cancelled job sits the whole delay out before
  /// it notices. Handed to [abandonable], it lets the body go at once — and
  /// leaves its timer running to the end with nothing to wait for it: a
  /// `Future.delayed` cannot be cancelled. The timer of a pause is cancelled
  /// together with the pause.
  ///
  /// ```dart
  /// while (true) {
  ///   await ctx.join(sync);
  ///   await ctx.pause(const Duration(minutes: 5));
  /// }
  /// ```
  ///
  /// Inside [uncancellable] a cancellation is held until the section ends,
  /// and the pause runs its whole length. During cleanup this throws a
  /// [StateError], as [abandonable] does: a disposer that has to let time pass
  /// awaits a plain `Future.delayed`. A callback of [onCancel] runs in a job
  /// that is cancelled already, and a pause there throws at once.
  ///
  /// Only a cancellation ends a pause early. One the body walked away from
  /// runs to its end, timer and all, when the job ends some other way, like
  /// any call the body did not await.
  Future<void> pause([Duration duration = Duration.zero]);

  /// Registers [callback] to run the moment the job accepts a cancellation,
  /// before the body itself learns about it. Returns a function that
  /// unregisters it. Callbacks run in the order they were registered, each
  /// once.
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
  /// Throws [Cancelled] if the job is already cancelled: there is nothing to
  /// register for, and nothing should be started either. An error thrown by
  /// [callback] goes to `onError` and on to the job's answer; the cancellation
  /// itself is not affected and the other callbacks still run.
  ///
  /// A callback that registers another one runs in a job that is cancelled by
  /// then, so that registration throws [Cancelled] too, and the callback stops
  /// there. Only `onError` hears that [Cancelled], as it hears any [Cancelled]
  /// thrown outside the body, and the job still ends with its cancellation.
  /// Whatever has to happen on the cancellation, the callback does itself.
  ///
  /// A body that cancels itself — throws [Cancelled], or lets out the
  /// cancellation of a child — accepts its cancellation as it throws, and these
  /// callbacks run then: what the body started is no more needed than when the
  /// job is cancelled from outside.
  ///
  /// [callback] is synchronous, and only what it throws synchronously is
  /// caught. `void Function()` takes an `async` function without a word
  /// from the analyser, and the future one of those returns is awaited by
  /// nobody: its failure goes to the zone it happens to run in, past any
  /// observer. For something that stops asynchronously, hand the work to
  /// the core and let it hold the error:
  ///
  /// ```dart
  /// ctx.onCancel(() => ctx.unattended(device.stop));
  /// ```
  void Function() onCancel(void Function() callback);

  /// Registers [disposer] to run when the job ends, whatever the outcome.
  ///
  /// The core unwinds the stack after the children and before the outcome, last
  /// registration first, and it waits for every disposer. Returns a function
  /// that unregisters this one; calling it twice, or after the disposer has
  /// run, is safe.
  ///
  /// A disposer runs outside the body: nothing cancels it and nothing
  /// interrupts it, so keep it short and unconditional. It must not wait
  /// for its own job — `job.done`, `job.value` and `job.cancel()` all
  /// complete after the cleanup that would be waiting for them.
  void Function() onDispose(FutureOr<void> Function() disposer);

  /// Registers [disposer] to run unless the job ends [Done]: when it is
  /// cancelled, or fails.
  ///
  /// For what the body returns or hands outside; everything else — a
  /// lock, a temporary file, a subscription — takes [onDispose], or it
  /// leaks on the successful path where no test on cancellation will see
  /// it. The outcome decides, not the value: a body that ends [Done]
  /// without returning what it registered here disposes of it itself.
  /// Returns a function that unregisters it.
  ///
  /// In a branch of [runAll] the hand-over is the group's to declare, not
  /// the branch's: once the group has handed the values to the caller this
  /// does not run, whatever outcome the branch itself ends with
  /// afterwards. When the group ends otherwise, this runs for a branch
  /// that accepted the stop — and not for one created with
  /// `cancellable: false`, which refuses the stop, ends [Done] and hands
  /// its value over through [Job.value] as it always would.
  ///
  /// The registration goes nowhere with the value. It is settled by the
  /// outcome of the job that made it, so a job that took the value — a
  /// parent awaiting [run], a caller holding [Job.value] — has to register
  /// its release itself, and `ctx.run(child, discard: ...)` is how a
  /// parent does that. On the call and not on the line after it: `run`
  /// checks the parent once the value is in hand, for cancellation and
  /// for the rules of its domain, and a checkpoint that throws there takes
  /// the value with it — the line that would have registered the release
  /// is never reached. The debug channel names every job that handed a
  /// value over and dropped registrations doing so.
  ///
  /// A job that returns nothing hands that nothing over all the same: it
  /// ends [Done], and a registration made here never runs. For a resource
  /// such a job keeps to itself the member is [onDispose].
  void Function() onDiscard(FutureOr<void> Function() disposer);

  /// Drops the cleanup registered for [value] by [abandonable], [join] or
  /// [run].
  ///
  /// Returns whether anything was dropped. The lookup is by identity, so pass
  /// the very object the body was handed. What an equal one finds depends on
  /// the value and the platform: `identical` answers by value for numbers of
  /// one type and for `bool`s, and on some platforms for strings and records,
  /// so an equal value of that kind may drop a registration somebody else
  /// made. A resource such a value stands for is registered with [onDispose]
  /// or [onDiscard] instead. Registrations made by those two carry no value
  /// and are invisible here — they are dropped by the function those members
  /// return; an unknown value is not an error. With two registrations for one
  /// value the top one goes, one per call.
  ///
  /// Stands next to the hand-over: before it, when the hand-over is synchronous
  /// and may throw after its own work (`emit` of `solo`, for example), and
  /// inside the same uncancellable section, when it is asynchronous.
  bool disown(Object value);

  /// Starts [child] right now, as a child of this job, ahead of whatever an
  /// engine would have put it through.
  ///
  /// Starts synchronously, then returns a future with the child's value after
  /// the child, its children and its cleanup finish; a child's error or
  /// cancellation reaches the future with its original stack trace. The parent
  /// finishes only after all its children, and its cancellation cascades onto
  /// them. When the child succeeds while the parent's body is still active,
  /// the future checks the parent, for a cancellation and for the rules of its
  /// domain, and a check that throws takes the value with it. So a value the
  /// child hands over is registered on the call, with [dispose] or [discard],
  /// and not on the line after it: that line is never reached, and the child,
  /// having ended [Done], has already dropped its own registration.
  ///
  /// ```dart
  /// final db = await ctx.run(connect, discard: (db) => db.close());
  /// ```
  ///
  /// [dispose] and [discard] work as in [abandonable], and passing both is an
  /// [ArgumentError] thrown before the child starts. When the check throws, the
  /// disposer runs on the spot and is awaited before the [Cancelled] is thrown;
  /// when it passes, the registration goes on the cleanup stack. If the body
  /// ended without awaiting the future, a later success returns its value
  /// without checking the closed context.
  ///
  /// Admission errors are synchronous: an [ArgumentError] for a handle that is
  /// not a job of this core or one an engine does not own; a [StateError] for a
  /// job already started or finished, and for a call made after this job's
  /// body has ended or from [unattended] work; and the parent's own
  /// [Cancelled], with the child cancelled before its start, if the parent is
  /// already cancelled. An [ArgumentError] or a [StateError] leaves [child]
  /// untouched, with the code that made it: a job of [Job.deferred] refused
  /// that way stays unstarted, and its [Job.done] waits until that code starts
  /// or cancels it.
  ///
  /// See [Running a child](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/children.md#running-a-child)
  /// and [When `ctx.run` refuses a child](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/children.md#when-ctxrun-refuses-a-child)
  /// on the children page, and
  /// [Registering on arrival](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cleanup.md#registering-on-arrival)
  /// on the cleanup page.
  Future<T> run<T>(
    ChildJob<T> child, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  });

  /// Starts [child] right now, as a child of this job, and leaves its outcome
  /// to whoever holds it.
  ///
  /// Starts synchronously and returns nothing: keep [child] itself to read its
  /// outcome. Nothing here observes it, so a failure of the child goes the way
  /// a failure nobody observed goes: to [JobAnswerer.onUnanswered] of its
  /// observer, otherwise to the zone, unless [Job.ignoreFailure] was called on
  /// [child]. A cancellation of the child goes nowhere. Neither changes the
  /// outcome of this job.
  ///
  /// The child is a child like one of [run]: the parent finishes only after
  /// it, the parent's cancellation cascades onto it, and a child created with
  /// `cancellable: false` refuses that cascade. A child with no observer of its
  /// own takes the parent's.
  ///
  /// Admission errors are those of [run], and as synchronous. A rule of the
  /// engine's domain that throws ends [child] [Failed], with
  /// [Job.ignoreFailure] called on it, and its error is thrown from here.
  ///
  /// `ctx.run(child).ignore()` is not the same: [run] observes the value of
  /// the child, and `ignore()` drops the error, so nobody answers for a
  /// failure and only [JobObserver.onError] hears it.
  ///
  /// ```dart
  /// ctx.start(Job.deferred<void>((ctx) => sendReport(rows)));
  /// ```
  void start(ChildJob<Object?> child);

  /// Runs [children] side by side and stops the rest as soon as one of them
  /// goes wrong.
  ///
  /// Starts every child synchronously, in the order of the list, and returns
  /// their values in that same order. As soon as the body of a branch ends in
  /// anything but a value, the other branches are asked to stop with
  /// [SiblingCancelReason], and what comes out is decided by the final
  /// outcomes: a real failure if there is one, otherwise the first cancellation
  /// that arrived, thrown as `await ctx.run(child)` would throw it. **A branch
  /// must not wait for another branch of the same group** — for its [Job.value]
  /// or [Job.done], or for a lock or a slot of a pool it releases in its
  /// cleanup. No branch unwinds before the group has decided, so the group
  /// hangs, with no timer and no error. Take such a lock in a child of the
  /// branch, which releases it when the child ends, still inside the body, or
  /// use `[a, b].wait`, under which every branch unwinds on its own.
  ///
  /// The list is read once, by copy, before the first start. A failure the
  /// group received and did not throw goes the way an error nobody answered for
  /// goes, and so does the failure of the body of a branch that ends
  /// [Cancelled]; [Job.ignoreFailure] on the branch silences both. A branch an
  /// engine ends by hand with a value after the group heard its body fail
  /// counts as ending with that failure: see [JobBase.finish]. What a child
  /// that holds the lock opens for the caller, the branch registers on arrival,
  /// `run(child, discard: ...)`, and that `discard` runs without the lock.
  ///
  /// Admission errors are those of [run], and the same handle twice is an
  /// [ArgumentError]. Everything that needs no adoption is asked of every
  /// handle before the first one starts, so such a refusal starts none of them,
  /// the sound ones included: each stays with the code that made it, and its
  /// `done` waits until that code starts or cancels it. A refusal only the
  /// adoption can give — an engine turning the parent down, a rule of its
  /// domain that throws — may arrive after some branches have started: it stops
  /// them and waits for them, and the handles after the refused one are never
  /// started. Under a cancelled parent every branch is turned away, and so is
  /// the rest of the list when a branch cancels the parent before its first
  /// `await`. An empty group returns an empty list after the checks [run]
  /// makes; a body that ended without awaiting the future gets the values
  /// unchecked, as from [run].
  ///
  /// How this differs from `.wait` and [Future.wait] is in [When one failure makes the rest pointless](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/groups.md#when-one-failure-makes-the-rest-pointless)
  /// on the groups page, and the hang in [Branches that wait for each other](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/groups.md#branches-that-wait-for-each-other).
  Future<List<T>> runAll<T>(Iterable<ChildJob<T>> children);

  /// Starts a child job that processes [stream] one event at a time.
  ///
  /// Returns the child at once without observing its outcome; the parent waits
  /// for it even when the body does not, so an open stream keeps the parent
  /// alive until the stream ends or the child is cancelled. [onData] gets the
  /// child's context, and an asynchronous callback is awaited before the next
  /// event. Throws synchronously if a child cannot be started, as [run] does.
  /// [key] and [describe] name the child as they name any job, see
  /// [A job's name](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/observing.md#a-jobs-name);
  /// without [describe] its description is `each`. The child's cleanup stack
  /// unwinds when the child ends, not after an event: what the callback
  /// registers piles up for as long as the stream lasts.
  ///
  /// ```dart
  /// final listening = ctx.each<int>(events, (child, event) {
  ///   child.log(event);
  /// });
  /// await listening.cancel();
  /// ```
  ///
  /// See [Processing a stream](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/streams.md#processing-a-stream)
  /// on the streams page.
  Job<void> each<T>(
    Stream<T> stream,
    FutureOr<void> Function(JobContext ctx, T event) onData, {
    Object? key,
    String Function()? describe,
  });

  /// Hands [message] to [JobObserver.onLog] as it is.
  ///
  /// Nothing happens to it on the way: a listener that wants a line makes one,
  /// a listener that wants the object keeps it. A no-op when the job has no
  /// observer, so a body logs unconditionally.
  ///
  /// Only a message passed unbuilt costs nothing until somebody listens: the
  /// object itself, or a closure the observer calls. A string with
  /// interpolation is built before this call, observer or not.
  ///
  /// ```dart
  /// ctx.log(() => 'migration failed: $error');
  /// ```
  void log(Object? message);

  /// Runs [action] as work this job does not wait for.
  ///
  /// Comes back at once and hands the work to the core: the job neither waits
  /// for it nor cancels it, and whatever [action] leaves uncaught — now, or
  /// long after the job is over — belongs to the job. Its observer hears it
  /// through `onError`, one that is a [JobAnswerer] answers for it, and by
  /// default it goes to the zone the job was created in; it never reaches the
  /// body, because background work must not decide the outcome of the job that
  /// started it. The job's own cancellation left uncaught is not reported.
  /// Legal on a job that has accepted a cancellation and while the core unwinds
  /// the cleanup stack; once the job has finished it throws a [StateError].
  /// **Start the work in here and take nothing out of it:** the work runs in an
  /// error zone of its own, so a future made outside and awaited in here never
  /// comes back if it fails, and one born in here and awaited outside hangs
  /// whoever waits for it if it fails. The `void` return does not stop a
  /// closure carrying one out.
  ///
  /// ```dart
  /// ctx.unattended(() => analytics.report(event));
  /// ```
  ///
  /// **Unfinished work holds the job**, its outcome and the body's closure with
  /// everything it captured — and whatever an engine hangs on the job: in
  /// `solo`, for example, the controller itself, with its state and its
  /// listeners, after `close()` too. A periodic timer left running in here
  /// leaks all of that. Work that must end with the job puts its own stop on
  /// the cleanup stack, `ctx.onDispose(timer.cancel)`, or takes the
  /// cancellation through [onCancel]. Polling [check] is no stop: on a job
  /// nobody cancelled it throws a [StateError] while the core unwinds the
  /// cleanup stack, and once the job has ended [Done] it does not throw at all,
  /// so a loop waiting for it holds the job forever. Ask `job.isFinished`, or
  /// wait for `job.done`.
  ///
  /// [run], [runAll], `each` and [uncancellable] throw a [StateError] in here:
  /// they act on the whole job, and this work is not the job. [abandonable] and
  /// [join] work, on the body's terms even after the body has ended: on a job
  /// that has accepted a cancellation the value is released and the call throws
  /// the cancellation, and on a job that is over a value with a `dispose` or
  /// `discard` is released and the call throws a [StateError] instead of
  /// handing it over closed.
  ///
  /// A job created in here is not this work: it has an outcome and an observer
  /// of its own, and its body runs in the zone this work was started from. Its
  /// unobserved failure goes to the answer of its own observer, or to that
  /// zone, rather than to the observer of this job. For work inside the work of
  /// another job, that zone is the one the outer work was started from.
  ///
  /// See [Work the job does not wait for](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/errors.md#work-the-job-does-not-wait-for)
  /// on the errors page.
  void unattended(FutureOr<void> Function() action);

  /// The job this context belongs to.
  Job<Object?> get job;

  /// The cancellation an open [uncancellable] section of this job is holding
  /// back, or `null`.
  ///
  /// The job takes a held cancellation as the section closes, before the
  /// body returns, so a step that made something worth keeping — a receipt
  /// of a payment that went through — keeps it inside the section:
  ///
  /// ```dart
  /// final receipt = await ctx.uncancellable(() async {
  ///   final receipt = await api.pay(order);
  ///   if (ctx.heldCancellation != null || ctx.job.isCancelled) {
  ///     // The job ends Cancelled once the section closes: keep the receipt.
  ///     await store.save(receipt);
  ///   }
  ///   return receipt;
  /// });
  /// ```
  ///
  /// A cancellation the job cannot refuse is not held: it marks the job at
  /// once, and the one held until then is dropped, so this goes back to
  /// `null` while [job]'s `isCancelled` turns `true` — hence both checks
  /// above. A job created with `cancellable: false` refuses a cancellation
  /// rather than holding it, and this stays `null`.
  ///
  /// One value for the whole job, not for one section: code of the job
  /// outside a section, a branch next to it or [unattended] work, sees what
  /// another section holds. A snapshot: a cancellation asked after the read
  /// is held all the same, and one read here may still never land — a
  /// section the body did not await outlives a job that ends first. `null`
  /// once the job is over. Never throws.
  Cancelled? get heldCancellation;
}

/// The base of a job context: everything a body does without a state.
///
/// Subclass it to add a domain of your own — `solo`, for example, adds the
/// state and its rules. [check] is the checkpoint, and it is virtual on
/// purpose: a domain checks more than the cancellation. While the body runs,
/// [abandonable], [join], [pause] and [uncancellable] ask it before the action,
/// [join] again after it, [run] once the child's value has arrived, and
/// [runAll] before it hands the values back. An override calls `super.check()`,
/// and calls it first. That is where the cancellation of the job is asked:
/// without it [join] hands a value to a job already cancelled and
/// [uncancellable] begins its step on one. And while the core cleans up after
/// the body it throws the cancellation of a cancelled job and a [StateError]
/// otherwise: the body is gone, and no rule is asked for it any more.
///
/// A rule that no longer holds throws a [Cancelled] with a reason of the
/// engine's own. The body lets it out and cancels itself, and a job whose body
/// cancels itself is cancelled the way [Job.cancel] cancels it: its children
/// stop and its [onCancel] callbacks run. The job accepts that cancellation as
/// the throw leaves the body, not before: a body that catches it and goes on is
/// not cancelled. To stop the job whatever the body does, cancel it through
/// [cancelOwnJob].
abstract class JobContextBase implements JobContext {
  final JobBase<Object?> _owner;

  /// Creates the context [owner] hands to its body.
  ///
  /// A subclass passes the job on: `MyContext(super.owner)`.
  JobContextBase(JobBase<Object?> owner) : _owner = owner;

  @override
  Job<Object?> get job => _owner;

  @override
  Cancelled? get heldCancellation => _owner.heldCancel;

  /// Creates the unstarted child used by [each], named by [key] and
  /// [describe].
  ///
  /// A domain that restricts child ownership overrides this factory to
  /// return its own job with the appropriate context and rules, and hands
  /// [key] and [describe] to it. They come as the caller of [each] gave them,
  /// except that [describe] already holds the core's default, `each`, when the
  /// caller gave none. The result must be accepted by [startChild]. This
  /// factory must not start the child.
  @visibleForOverriding
  Job<void> createEachJob(
    Future<void> Function(JobContext ctx) body, {
    Object? key,
    String Function()? describe,
  }) =>
      Job.deferred<void>(body, key: key, describe: describe);

  @override
  Job<void> each<T>(
    Stream<T> stream,
    FutureOr<void> Function(JobContext ctx, T event) onData, {
    Object? key,
    String Function()? describe,
  }) {
    // Asked here, with its own verb, before `startChild` asks again with
    // one about children: the caller followed a stream, and the message
    // names what they did.
    _checkCanRun('follow a stream');
    final child = createEachJob(
      (child) => child._followStream(stream, (event) => onData(child, event)),
      key: key,
      describe: describe ?? () => 'each',
    );
    startChild(child);
    return child;
  }

  @override
  @mustCallSuper
  void check() {
    throwIfCancelled();
    throwIfDisposing('check');
  }

  /// The cancellation the job has accepted, or `null`.
  @protected
  Cancelled? get pendingCancel => _owner._pendingCancel;

  /// Throws the cancellation the job has accepted, or the one it ended with: a
  /// job an engine finished by hand has no [pendingCancel], and its
  /// cancellation lives in the outcome alone.
  @protected
  void throwIfCancelled() {
    final cancelled = _owner._pendingCancel;
    if (cancelled != null) {
      throw cancelled;
    }
    final outcome = _owner._outcome;
    if (outcome is Cancelled) {
      throw outcome;
    }
  }

  /// Throws [StateError] if the job has finished: a context that outlived
  /// its job neither writes nor starts anything. Also throws while the
  /// core unwinds the cleanup stack — see [throwIfDisposing].
  @protected
  void throwIfFinished(String action) {
    if (_owner.isFinished) {
      throw StateError('$_owner has already finished, cannot $action');
    }
    throwIfDisposing(action);
  }

  /// Throws [StateError] while the core unwinds the cleanup stack.
  ///
  /// The body is gone and the outcome is decided, so nothing of the body
  /// runs any more: a disposer takes what it needs from its closure and
  /// asks `job.isCancelled` about the outcome. Reads go through this one
  /// alone — after the job has finished they stay legal, as they were.
  @protected
  void throwIfDisposing(String action) {
    if (_owner.isDisposing) {
      throw StateError('$_owner is cleaning up after its body, cannot $action');
    }
  }

  /// Throws [StateError] when called from inside this job's own
  /// [JobContext.unattended] work.
  ///
  /// Four members act on the whole job, [JobContext.run], [JobContext.runAll],
  /// [JobContext.each] and [JobContext.uncancellable], and unattended work is
  /// not the job: a child started there would hang on the fork's boundary with
  /// the parent waiting for it forever, and a section opened there would hold a
  /// cancellation of a body that stands in no section at all. Another job's
  /// fork is not this job's business, and the key is the job's own: forks nest,
  /// and a shared key would let the inner one pass for the outer.
  @protected
  void throwIfUnattended(String action) {
    if (_inOwnFork) {
      throw StateError('$_owner cannot $action inside unattended work');
    }
  }

  /// Whether the code running now is work this job handed over with
  /// [JobContext.unattended].
  bool get _inOwnFork => identical(Zone.current[_owner._forkKey], _owner);

  /// Announces [error] and asks for an answer to it: the observer's
  /// `onError`, then `onUnanswered` of an observer that is a [JobAnswerer],
  /// or the zone.
  @protected
  void notifyError(Object error, StackTrace stackTrace) =>
      _owner.notifyError(error, stackTrace);

  /// Registers [callback] past the public [onCancel]: the race inside
  /// [abandonable] needs a raw one, unguarded and removable. Returns a remover.
  ///
  /// Unguarded means [callback] must not throw. It runs inside the call that
  /// cancels the job, and an error escapes from that call — [Job.cancel], the
  /// cascade from a parent — and stops the pass: the callbacks registered
  /// after it never run, and [Job.whenCancelled] listeners hear the
  /// cancellation only when the job finishes, not when it is accepted.
  /// Register through [onCancel] for code that may throw.
  @protected
  void Function() addCancelCallback(void Function() callback) =>
      _owner._onCancel.add(callback);

  /// Cancels the owner with a cancellation it cannot refuse: the rules of
  /// a domain come here, and they cancel a job whatever `cancellable`
  /// says.
  ///
  /// [cancelled] belongs to the owner alone, as [JobBase.finish] explains.
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

  /// The parent's last word before a child starts.
  ///
  /// A non-null result finishes the child with it, and belongs to that child
  /// alone, as [JobBase.finish] explains: it is built at every call. `solo`,
  /// for example, checks its start rules here.
  @visibleForOverriding
  Cancelled? beforeChildStart(JobBase<Object?> child) => null;

  @override
  Future<T> join<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  }) async {
    throwIfFinished('join');
    _oneCleanupOnly(dispose, discard);
    check();
    final result = await action();
    if (_owner.bodyEnded && _inOwnFork) {
      // Called from work handed over with `unattended`, and that work is
      // waiting for the value: it is the receiver, on the body's terms. A job
      // marked cancelled -- from outside, or by a body that cancelled itself --
      // releases the value and throws the cancellation, the rules of a domain
      // aside: they speak to the body, which is gone. Otherwise the value is
      // the work's on the terms the call asked for, and on a job that is over
      // it is released and the call throws, as for a job an engine finished by
      // hand.
      try {
        throwIfCancelled();
      } on Cancelled {
        final disposer = dispose ?? discard;
        if (disposer != null) {
          await _dispose(disposer, result);
        }
        rethrow;
      }
      _keepOnStack(dispose, discard, result);
      return result;
    }
    if (_owner.bodyEnded) {
      // The body ended while the call was in flight: the value did not
      // reach it, and nothing is waiting for this call any more. It hands
      // the value to its cleanup and ends quietly — neither `check` nor
      // the job's cancellation goes in, because either would land in a
      // future nobody awaits and Dart would hand it to the zone.
      await _keepLate(dispose, discard, result);
      return result;
    }
    try {
      check();
    } on Object {
      // Whatever the checkpoint threw, the value stops here: it reaches no
      // body, and the stack below is never reached, so this is its only
      // way out. `on Object`, not `on Cancelled`: a domain checks its own
      // rules in here, and a rule that threw instead of answering must not
      // cost the caller the resource it already holds.
      final disposer = dispose ?? discard;
      if (disposer != null) {
        await _dispose(disposer, result);
      }
      rethrow;
    }
    _keepOnStack(dispose, discard, result);
    return result;
  }

  void _oneCleanupOnly(Object? dispose, Object? discard) {
    if (dispose != null && discard != null) {
      throw ArgumentError('pass either dispose or discard, not both');
    }
  }

  /// Puts the cleanup of [value] on the stack, as `dispose` or `discard`,
  /// whichever was given.
  ///
  /// Synchronous on purpose: `abandonable` registers between taking the value
  /// and handing it to the body, and an `await` in that gap would let a
  /// cancellation in — the body would then hold a value whose cleanup is
  /// registered nowhere.
  void _keepOnStack<T>(
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
    T value,
  ) {
    final disposer = dispose ?? discard;
    if (disposer == null) {
      return;
    }
    if (_owner.isFinished) {
      // The job ended while the call was in flight, and an engine finishing by
      // hand is the only way in. There is no stack left to register on:
      // `addCleanup` would throw a complaint about registering on a finished
      // job, the caller would see that instead of its value, and the value
      // itself would be left to nobody. Released on the spot, the way one that
      // came back too late is, and the caller hears the plain truth about the
      // job instead. With no disposer there is nothing to lose, so nothing
      // changes there.
      unawaited(_dispose(disposer, value));
      throwIfFinished('take the value of a call it made');
    }
    addCleanup(() => disposer(value), always: dispose != null, value: value);
  }

  /// Cleans up [value] that came out after the body had ended.
  ///
  /// It did not reach the body, so the outcome does not matter: on a job that
  /// has finished the disposer runs on the spot and nobody waits for it, and
  /// while the job is still alive the registration is unconditional and waits
  /// for the unwinding. Not sooner: the call still hands the value to whoever
  /// holds its future, and a body that walked away may have handed that future
  /// to a child, which the job waits for before the unwinding.
  Future<void> _keepLate<T>(
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
    T value,
  ) async {
    final disposer = dispose ?? discard;
    if (disposer == null) {
      return;
    }
    if (_owner.isFinished) {
      await _dispose(disposer, value);
      return;
    }
    addCleanup(() => disposer(value), always: true, value: value);
  }

  /// Cleans up [value] that came to a call the cancellation had already
  /// finished.
  ///
  /// Whoever holds the future of the call got the cancellation instead, so
  /// the value reaches nobody at all, and nothing the job registered can
  /// depend on it. Before the unwinding the disposer runs on the spot, and
  /// the stack gets only the wait for it, so the job still ends after the
  /// release. Kept for the unwinding, the value would be held while the job
  /// waits for its children, and a child waiting for that very value — a
  /// slot of a pool — would never end. So the release runs alongside the
  /// body, the children and whatever else the job is doing then. A branch
  /// of [JobContext.runAll] standing at its second barrier runs no callback
  /// either, and its group waits there for the cleanup of a sibling that
  /// may want the same slot: it releases on the spot too. While the core
  /// runs the stack the registration goes on the stack as a late one does,
  /// and the same pass takes it off after the callback that is running: the
  /// callbacks of the stack do not overlap. On a job that has finished the
  /// disposer runs on the spot and nobody waits for it.
  void _releaseAbandoned<T>(
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
    T value,
  ) {
    final disposer = dispose ?? discard;
    if (disposer == null) {
      return;
    }
    if (_owner.isFinished) {
      unawaited(_dispose(disposer, value));
      return;
    }
    if (_owner.isDisposing && !_owner._betweenPasses) {
      addCleanup(() => disposer(value), always: true, value: value);
      return;
    }
    // No `value:` on the registration: the value is being released, and
    // `disown` must not take back what is no longer there to hand on. Taken
    // off once the release is over, so that a job an engine finishes by hand
    // does not count it among the cleanups it leaves behind. Registered
    // before the release starts: a disposer that finishes the job by hand
    // would leave no stack to register on.
    late final Future<void> release;
    final remove = addCleanup(() => release, always: true);
    release = _dispose(disposer, value);
    release.whenComplete(remove).ignore();
  }

  /// Hands [value] to the body's own disposer. Its error goes to
  /// [notifyError]: the job is already giving up, and a failed disposal must
  /// not stand in for the cancellation the body is waiting for.
  Future<void> _dispose<T>(
    FutureOr<void> Function(T value) disposer,
    T value,
  ) async {
    try {
      await disposer(value);
    } on Object catch (error, stackTrace) {
      notifyError(error, stackTrace);
    }
  }

  @override
  Future<T> uncancellable<T>(FutureOr<T> Function() action) async {
    // Before `throwIfFinished`: for work that outlived its job both
    // complaints are true, but the call from the fork is the one to fix.
    throwIfUnattended('run an uncancellable action');
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
  Future<void> pause([Duration duration = Duration.zero]) async {
    // Asked here, before `abandonable` asks: the message names the call made.
    throwIfFinished('pause');
    Timer? timer;
    try {
      // `abandonable` asks the checkpoint first, so on a job that is cancelled
      // already no timer is made.
      await abandonable<void>(() {
        final elapsed = Completer<void>();
        timer = Timer(duration, elapsed.complete);
        return elapsed.future;
      });
    } finally {
      // What `Future.delayed` under `abandonable` cannot do: the walk away from
      // the waiting takes the timer with it.
      timer?.cancel();
    }
  }

  @override
  void Function() onCancel(void Function() callback) {
    throwIfFinished('register onCancel');
    throwIfCancelled();
    void guarded() {
      // A callback of the caller's, run from inside the core's own
      // cancellation: its error belongs to `notifyError`, not to whoever
      // happened to trigger the cancel.
      try {
        callback();
      } on Object catch (error, stackTrace) {
        if (error is StackOverflowError && _owner._outOfStack) {
          // Not `onError`, and above all not the zone, while the core
          // is unwinding a cascade that ran out of stack: see
          // `JobBase.whenCancelled`, which keeps the same rule for the
          // same reason.
          rethrow;
        }
        notifyError(error, stackTrace);
      }
    }

    return addCancelCallback(guarded);
  }

  /// Puts a registration on the cleanup stack of the owner.
  ///
  /// The public [onDispose] and [onDiscard] are this with [value] unset;
  /// `abandonable`, `join` and `run` pass the value they hand to the body, so
  /// that `disown` can find the registration by it.
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
    final cleanup = _Cleanup(
      disposer,
      always: always,
      order: _owner._cleanupOrder++,
      value: value,
    );
    _owner._cleanups.add(cleanup);
    // Both lists: the unwinding moves a registration it decided to put off
    // out of the stack, and a disposer running below it may still take
    // that one back.
    return () {
      _owner._cleanups.remove(cleanup);
      _owner._skipped.remove(cleanup);
    };
  }

  @override
  void Function() onDispose(FutureOr<void> Function() disposer) =>
      addCleanup(disposer, always: true);

  @override
  void Function() onDiscard(FutureOr<void> Function() disposer) =>
      addCleanup(disposer, always: false);

  @override
  bool disown(Object value) {
    if (_owner.isFinished) {
      throw StateError('$_owner has already finished, cannot disown');
    }
    // Both stores, and the newest wins: the unwinding moves the
    // registrations it puts off out of the stack, and a late value can be
    // registered while they are aside, so neither list alone holds the
    // order. One waiting for an outcome that has not happened yet is still
    // a registration, and handing the value on must still take it back.
    List<_Cleanup>? found;
    var at = -1;
    void look(List<_Cleanup> list) {
      for (var i = list.length - 1; i >= 0; i--) {
        if (identical(list[i].value, value) &&
            (found == null || list[i].order > found![at].order)) {
          found = list;
          at = i;
        }
      }
    }

    look(_owner._cleanups);
    look(_owner._skipped);
    if (found case final list?) {
      list.removeAt(at);
      return true;
    }
    return false;
  }

  /// The former name of [abandonable], kept for one release.
  ///
  /// Does what [abandonable] does; only the [StateError] of a call made
  /// after the job has finished names `wait`.
  @Deprecated('Use abandonable')
  @override
  Future<T> wait<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  }) async {
    throwIfFinished('wait');
    return abandonable(action, dispose: dispose, discard: discard);
  }

  @override
  Future<T> abandonable<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  }) async {
    throwIfFinished('run an abandonable action');
    _oneCleanupOnly(dispose, discard);
    check();
    final result = action();
    if (result is! Future<T>) {
      // Work handed over with `unattended` waits for the value, so it goes
      // on below like the body's: see `join`.
      if (_owner.bodyEnded && !_inOwnFork) {
        await _keepLate(dispose, discard, result);
        return result;
      }
      // The action may have cancelled this job while it ran, and a value
      // made after the mark is one the body must not see: `_race` answers
      // that way for a future completing after the mark, and `join` for an
      // action of its own. A member whose answer turns on whether the call
      // happened to be synchronous is a member nobody can reason about.
      //
      // The cancellation alone, not `check()`: `abandonable` promises to end
      // the waiting when the job is marked, and the rules of a domain are no
      // part of that promise.
      try {
        throwIfCancelled();
      } on Cancelled {
        final disposer = dispose ?? discard;
        if (disposer != null) {
          await _dispose(disposer, result);
        }
        rethrow;
      }
      _keepOnStack(dispose, discard, result);
      return result;
    }
    return _race(result, dispose, discard);
  }

  /// Completes with [future] or with the job's cancellation, whichever
  /// comes first. A result arriving after cancellation goes to [dispose] or
  /// [discard], or nowhere if there is none, as `_releaseAbandoned` says; an
  /// error arriving after cancellation goes to [notifyError].
  Future<T> _race<T>(
    Future<T> future,
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  ) {
    final completer = Completer<T>();
    // Whether this call was made from inside work handed over with
    // `unattended`. A late failure then still has a listener -- the work
    // itself -- and the fork announces what the work leaves uncaught, so
    // the core announcing it as well would say one error twice.
    final fromFork = _inOwnFork;
    late final void Function() remove;
    void onCancel() {
      if (!completer.isCompleted) {
        final cancelled = pendingCancel!;
        completer.completeError(
          cancelled,
          cancelled.stackTrace ?? StackTrace.current,
        );
        // A body that has ended walked away from this call, and a body that
        // cancels itself is told here as much as one cancelled from outside.
        // The cancellation is the job's own outcome, and its copy must not
        // reach the zone as an error of an abandoned call; the error branch of
        // `forward` does the same.
        if (_owner.bodyEnded) {
          completer.future.ignore();
        }
      }
    }

    Future<void> forward() async {
      try {
        final value = await future;
        if (completer.isCompleted) {
          // The cancellation finished the call first, so the value reaches
          // nobody: cleaned up whatever the outcome, and at once.
          _releaseAbandoned(dispose, discard, value);
        } else if (fromFork && pendingCancel != null) {
          // The work waits for the value, and the job is marked without this
          // race having heard it: the pass over the callbacks never reached it.
          // An engine ended the job by hand while its cancellation went down to
          // the children, and `finish` dropped the callbacks; or a raw callback
          // registered before this one threw and stopped the pass. The work
          // gets what the body would: the cancellation, and the value is
          // released.
          onCancel();
          final disposer = dispose ?? discard;
          if (disposer != null) {
            await _dispose(disposer, value);
          }
        } else if (_owner.bodyEnded && !fromFork) {
          // Nobody is waiting for the value. Work handed over with
          // `unattended` is, and it takes the branch below: the value is
          // its on the terms the call asked for, and on a job that is over
          // `_keepOnStack` releases it and throws, and the work hears that.
          //
          // The registration below costs a microtask even when there is
          // nothing to register, and a cancellation arriving in it
          // finishes this future through the callback still standing.
          // Hence the second reading: without it the completion throws
          // `Future already completed` out of the core, and the job
          // reports an error of its own internals to whoever listens.
          await _keepLate(dispose, discard, value);
          if (!completer.isCompleted) {
            completer.complete(value);
          }
        } else {
          // Synchronously and before `complete`: between the registration
          // and the body there must be no `await`.
          _keepOnStack(dispose, discard, value);
          completer.complete(value);
        }
      } on Object catch (error, stackTrace) {
        if (!completer.isCompleted && _owner.bodyEnded && !fromFork) {
          // The body is gone, and it is not the one still holding this future.
          // Whatever is -- a `.timeout` that fired, a `Future.any` that took
          // another branch -- walked away from it and swallows what it is
          // handed, so handing the error over and saying nothing would lose it
          // for good. Announced here, the way the failure of any abandoned
          // action is, and the future completed all the same, so that nothing
          // left waiting on it waits for ever; `ignore` keeps that copy from
          // being announced a second time by the zone.
          if (!_isOwnCancellation(error)) {
            notifyError(error, stackTrace);
          }
          completer.completeError(error, stackTrace);
          completer.future.ignore();
        } else if (completer.isCompleted) {
          // Less this job giving up. A call the body walked away from
          // keeps the context, and after the mark every door back into it
          // — `check`, `join`, `run` — throws the very cancellation that
          // became the outcome. Reported, it would arrive at `onError` as
          // a failure of something, when it is the answer to a decision
          // whoever listens has heard already. The same filter stands in
          // `_unattendedError`, for work handed over the same way.
          if (!_isOwnCancellation(error)) {
            notifyError(error, stackTrace);
          }
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
  Future<T> run<T>(
    ChildJob<T> child, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  }) {
    // Before the child starts: an admission error must leave nothing
    // running behind it.
    _oneCleanupOnly(dispose, discard);
    startChild(child);

    return _awaitChild(child, dispose: dispose, discard: discard);
  }

  @override
  void start(ChildJob<Object?> child) => startChild(child);

  @override
  Future<List<T>> runAll<T>(Iterable<ChildJob<T>> children) {
    // Read once, by copy, before anything starts: an `Iterable` promises
    // neither repeatability nor stability, and the bodies below start
    // synchronously and may change the list this was made from. A
    // generator that throws throws from here, before any child has run.
    final branches = List<Job<T>>.of(children);
    // By identity and not by `==`: a job of a domain may compare itself by
    // a key, and two children of one queue are equal and still two jobs.
    // Before the first start, so that a repeat is refused without half of
    // the group already running.
    // The places go into the message: a job with no key reads `Job()`, and
    // two of those are told apart only by where they stand.
    final seen = Map<Job<T>, int>.identity();
    for (final (index, child) in branches.indexed) {
      if (seen[child] case final first?) {
        throw ArgumentError.value(
          '$child',
          'children',
          'is in the group more than once, at $first and at $index',
        );
      }
      seen[child] = index;
    }
    // Everything that needs no adoption, for every handle, before the first
    // start: otherwise a handle refused at the end of the list leaves the
    // branches before it started, their bodies already past their first
    // `await`. An empty group is asked the same about the context: it is
    // not a way around its checks.
    _checkCanRun('run a group of children');
    for (final child in branches) {
      _checkChild(child, 'children');
    }
    if (_owner.pendingCancel case final pending?) {
      // Every branch turned away, not the first one alone: the rest would be
      // left `created`, and whoever awaits one of them would wait for good. An
      // engine refusing the adoption is a different answer, and the one `run`
      // would give: the first such refusal comes out instead of the
      // cancellation, once the rest are turned away.
      (Object, StackTrace)? refusal;
      for (final child in branches) {
        try {
          startChild(child);
        } on Object catch (error, stackTrace) {
          if (!identical(error, pending)) {
            refusal ??= (error, stackTrace);
          }
        }
      }
      if (refusal case (final error, final stackTrace)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      throw pending;
    }
    if (branches.isEmpty) {
      // A checkpoint all the same, as a group of children is once they have
      // committed: a body that goes on after the call must find the rules
      // of its domain still holding. Through the future, as theirs comes.
      return Future<List<T>>.sync(() {
        check();
        return <T>[];
      });
    }
    return _RunAllGroup<T>(this, branches).run();
  }

  Future<T> _awaitChild<T>(
    Job<T> child, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  }) async {
    final value = await child.value;
    if (_owner.bodyEnded) {
      await _keepLate(dispose, discard, value);
      return value;
    }
    // The child ended [Done], so its own conditional registration went with
    // the value and is gone: this call is the only one holding the
    // resource. A checkpoint throwing here -- the parent's cancellation, or
    // a rule of its domain refusing -- takes the value away from the body,
    // and the body may catch that and still end [Done]. So the value is
    // released on the spot, as `join` releases it, and not left on the
    // stack, where a `discard` would never run on a job that succeeded.
    try {
      check();
    } on Object {
      final disposer = dispose ?? discard;
      if (disposer != null) {
        await _dispose(disposer, value);
      }
      rethrow;
    }
    _keepOnStack(dispose, discard, value);

    return value;
  }

  /// Adopts and starts [child] synchronously.
  ///
  /// A domain that restricts child ownership overrides this method, performs
  /// its own validation, then calls `super.startChild(child)`. It applies the
  /// synchronous admission rules of [run] and does not observe the child's
  /// outcome. It takes any [Job], so the type that keeps a job which starts
  /// itself away from [run] does not guard it: such a job is refused here with
  /// an [ArgumentError] — one from `Job(body)`, [Job.then] or [Job.each].
  @protected
  @mustCallSuper
  void startChild<T>(Job<T> child) {
    _checkCanRun('run a child');
    _checkChild(child, 'child');
    child as JobBase<T>;
    child
      ..adoptedBy(this)
      .._observer ??= _owner._observer
      .._parent = _owner
      .._level = _owner.level + 1;
    if (_owner.pendingCancel case final pending?) {
      throw _refuseChild(child, pending);
    }
    _startAdopted(child);
  }

  /// Turns [child] away because this job is already giving up, and returns
  /// the cancellation to throw into the body.
  Cancelled _refuseChild(JobBase<Object?> child, Cancelled pending) {
    _owner._cancelChild(child, pending);
    return pending;
  }

  /// Whether this job may start children right now, for [action].
  void _checkCanRun(String action) {
    throwIfUnattended(action);
    throwIfFinished(action);
    if (_owner.bodyEnded) {
      // The body is gone, and a child started now would be waited for by
      // nobody: the core has already left the children behind.
      throw StateError('$_owner has ended its body, cannot $action');
    }
  }

  /// The checks of a child that need no adoption: what it is and where it
  /// is in its life. [runAll] makes them for the whole list before the
  /// first start, so that a handle refused here leaves nothing running.
  void _checkChild<T>(Job<T> child, String name) {
    if (child is! JobBase<T> || JobBase._builtOnCore[child] != true) {
      throw ArgumentError.value('$child', name, 'is not a job of this core');
    }
    if (child is _AutoJob) {
      // Refused before the status is even looked at, so that the answer
      // does not depend on which got here first: on the same synchronous
      // stripe this call would still find it `created` and adopt it, one
      // microtask later it is already running on its own. The start of a
      // child belongs to its parent.
      throw ArgumentError.value(
        '$child',
        name,
        'starts itself; a child is made with Job.deferred',
      );
    }
    if (child is _ThenJob<Object?, Object?>) {
      // Refused before the status too, and for the same reason: while its
      // source runs this call would find it `created`, and once the source
      // has finished it is already running on its own.
      throw ArgumentError.value(
        '$child',
        name,
        'is a continuation, which starts itself once its source finishes',
      );
    }
    if (child is _SharedJob) {
      throw ArgumentError.value(
        '$child',
        name,
        'is a continuation, which finishes with its source',
      );
    }
    if (child is _EachJob) {
      // Running since the call that made it, so the status below would
      // refuse it too — with words about a job somebody started, which say
      // nothing to a caller who wrote `Job.each` where `ctx.each` belongs.
      throw ArgumentError.value(
        '$child',
        name,
        'follows its stream by itself; a child is made with ctx.each',
      );
    }
    if (child.status != JobStatus.created) {
      // Words of the way out too, as the refusals above give: a handle
      // started by hand, or passed to a second call, is the usual cause.
      throw StateError(
        child.status == JobStatus.running
            ? '$child is already running; a child is started by the call '
                'that takes it, and not before'
            : '$child has already finished; a job runs once, and a child '
                'needs a new Job.deferred',
      );
    }
  }

  /// Asks the rule of the domain and starts [child], adopted already.
  void _startAdopted<T>(JobBase<T> child) {
    // Everything that can refuse the child happens before it joins the waiting
    // list, and a refusal that arrives as a throw — a rule of a domain, a
    // context that would not be built — ends the child rather than leaving it
    // be. By now it has a parent, a level and an observer, and a job like that,
    // left alive, would sit half-adopted: parented, levelled, never started and
    // waited for by nobody. `finish` tells the child's observer, as it does for
    // every failure handed in, and a child the rule has already ended is told
    // too. `ignoreFailure` first: the error is already on its way to the body
    // through the rethrow, and the body is where it is answered for, not the
    // zone. Two throws leave the child be after all, and the `catch` says why:
    // one that threw the routine of the child out of its start, and a stack
    // that ran out while the start was under way.
    Cancelled? markedWhileAsking;
    try {
      final rejection = beforeChildStart(child);
      if (rejection != null) {
        child.finish(rejection);
        return;
      }
      // The rule is code of a domain, and it may give up on this job while
      // answering: `solo` lets a `canStart` call `cancel()` or `close()`
      // and still say yes. A child joining the list after that would be
      // waited for by a parent whose cascade has already walked the list
      // without it, and nothing would ever reach it — a second `cancel`
      // turns around on the mark. Read here and refused below, outside the
      // `catch`: the child ends `Cancelled`, not `Failed(Cancelled)`.
      markedWhileAsking = _owner.pendingCancel;
      if (markedWhileAsking == null) {
        // Up before the child joins the list and down once its start has
        // returned, by a store both times.
        child._startInFlight = true;
        _owner._waitFor(child);
        child
          ..start()
          .._startInFlight = false;
      }
    } on Object catch (error, stackTrace) {
      if (child._startInFlight &&
          (child._tornError != null || error is StackOverflowError)) {
        // Nothing here. The routine of the child was thrown out of the
        // start, and only the rest of that routine ends such a job: the
        // body may have run, and what it registered is released there. Or
        // the stack ran out, and whatever this did would need the stack
        // that has just run out; the check for that is itself allowed to
        // throw. The child stays where the throw left it, the mark of its
        // start still up: on the list, and the owner ends it once its own
        // body is over. A child the stack ran out on at the door of
        // `_waitFor`, before the list took it, is on no list, and nothing
        // ends it, as nothing ends a job `run` never took.
        rethrow;
      }
      // Off the list by hand: `finish` below takes a child off it, and
      // turns around on one that is over already. A rule that ended the
      // child and still let it in put such a child on the list, and its
      // start threw.
      _owner._stopWaitingFor(child);
      child
        ..ignoreFailure()
        ..finish(Failed(error, stackTrace));
      rethrow;
    }
    if (markedWhileAsking case final pending?) {
      throw _refuseChild(child, pending);
    }
  }

  @override
  void log(Object? message) => _owner._notifyLog(message);

  @override
  void unattended(FutureOr<void> Function() action) {
    // First, and by name: a context outliving its job is the mistake this
    // member is likeliest to be caught in, and the message has to say
    // which call threw. The cleanup window stays open on purpose — a
    // disposer starting work nobody waits for is what this is for.
    if (_owner.isFinished) {
      throw StateError(
        '$_owner has already finished, cannot start unattended work',
      );
    }
    // The zone a job born in this work reports to. Taken from the fork
    // around us when there is one, so nesting does not walk the address
    // one fork outwards on every level: the answer is the zone the body
    // itself runs in, however deep the call is.
    final from = (Zone.current[_unattendedKey] as Zone?) ?? Zone.current;
    runZonedGuarded<void>(
      () {
        action();
      },
      _unattendedError,
      // Two values, and the key of the second is the job's own: forks of
      // different jobs nest, and one shared key would let the inner one
      // hide the outer. Under a key of its own each job sees its own work
      // and nobody else's.
      //
      // Not the job itself as the key. A zone looks a key up by `==`, and a
      // job of a domain may well compare itself by a key of its own: of two
      // such jobs with forks nested, the inner fork would answer for the
      // outer job too, and work of one would pass for work of the other.
      zoneValues: {_unattendedKey: from, _owner._forkKey: _owner},
    );
  }

  /// The fork's handler: everything the work leaves uncaught, less this
  /// job's own giving up.
  void _unattendedError(Object error, StackTrace stackTrace) {
    if (_isOwnCancellation(error)) {
      return;
    }
    notifyError(error, stackTrace);
  }

  /// Whether [error] is this job giving up rather than something failing.
  ///
  /// The job's own cancellation is not news: whoever listens has heard it
  /// on the outcome already. A `Cancelled` built inside the work is not
  /// this — there is nobody to cancel there, and the observer gets it.
  bool _isOwnCancellation(Object error) {
    // The type first: everything below compares by identity against an
    // outcome, and an outcome is not always a cancellation. Work that
    // outlived its job and threw `job.outcome!` would otherwise have a
    // `Done` or a `Failed` swallowed here.
    if (error is! Cancelled) {
      return false;
    }
    // `_outcome` and not only `_pendingCancel`: an engine that finishes a job
    // by hand never marks it, and the cancellation lives in the outcome alone.
    if (identical(error, _owner._pendingCancel) ||
        identical(error, _owner._outcome)) {
      return true;
    }
    // A child this job's own cascade took down, reaching the work through
    // `child.value`. The lookup is exact — the key is the outcome object
    // itself — so anyone else's child still comes through.
    final child = _owner._outcomeChild[error];
    return child != null &&
        error.reason is ParentCancelReason &&
        identical(_owner._cascadeChild[error.reason], child._cascadeIdentity);
  }
}

/// The zone-value key under which a fork of [JobContext.unattended]
/// carries the zone of the body. A fresh object, so nothing outside this
/// library can name it. The fork's other value is the mark of the job
/// that made it, under a key of that job's own.
final _unattendedKey = Object();

/// The context of a job of the core itself.
final class _CoreContext extends JobContextBase {
  _CoreContext(super.owner);
}
