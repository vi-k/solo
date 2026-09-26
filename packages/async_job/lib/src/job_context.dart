part of 'job_base.dart';

/// What a job body sees in the core: cancellation, waiting and children.
///
/// Once the job is marked cancelled, the members that wait or start
/// something throw that [Cancelled]: [check], [wait], [join],
/// [uncancellable], [onCancel], [run] and `each`. The members that only
/// register do not — [onDispose], [onDiscard], [disown] and [unattended]
/// go on working, so a body that has just been cancelled can still put
/// what it holds on the cleanup stack, and still hand out a stop nobody
/// waits for — and neither do [log] and [job]. What a cancellation
/// arriving *during* a call does to that call is the call's own business:
/// see [wait], [join] and [uncancellable].
///
/// A context that outlived its job — captured by a closure nobody awaited
/// — neither waits nor starts nor registers anything: every member throws
/// a [StateError] once the job has finished, except [check], [log] and
/// [job]. While the engine unwinds the cleanup stack the same holds for
/// the members that wait or start something, and [check] throws a
/// [StateError] there too — but [onDispose], [onDiscard], [disown] and
/// [unattended] go on working, because a value arriving that late is put
/// on the stack the engine is unwinding, and a disposer may hand out work
/// nobody waits for.
abstract interface class JobContext {
  /// Gives up if the job was cancelled — in `solo`, also if its rules
  /// stopped holding.
  ///
  /// [join] is the same thing around a call. Reach for `check` where there
  /// is no call to wrap: a loop over work of your own, a `switch` after
  /// one.
  ///
  /// Legal after the job has finished, where it throws that [Cancelled] as
  /// always — but not while the engine cleans up after the body: there it
  /// throws a [StateError] instead. An action the body walked away from
  /// that polls `check` to stop will see that error, not a cancellation,
  /// if it polls inside that window.
  void check();

  /// Runs [action] and waits for it, but no longer than this job lives.
  ///
  /// Throws [Cancelled] up front if the job is already cancelled or its
  /// rules no longer hold. If a cancellation arrives while [action] is in
  /// flight, the wait ends there with that [Cancelled] — and [action] runs
  /// on, its result discarded, an error of its own going to `onError` and
  /// on to `onUnanswered`. It ends the waiting, not the work.
  ///
  /// For anything that must actually stop — a device, a download, a write —
  /// hand the cancellation to it through [onCancel] and wait for it to
  /// finish with [join], instead of walking away from it. Left deliberately
  /// unawaited, write the type out — `unawaited(ctx.wait<Db>(...))`: without
  /// it `T` is inferred from `unawaited`, which takes a `Future<void>`, and
  /// [dispose] then has to be a `void Function(void)`, which is not what the
  /// call site says and not what the analyzer explains. For a step that
  /// must not be interrupted at all, see [uncancellable].
  ///
  /// [dispose] and [discard] say how the value is cleaned up, and the rule
  /// is one: **a value that did not reach the body is cleaned up without
  /// a condition; a value that did goes on the cleanup stack.** So a
  /// connection or a file opened by an abandoned action still gets closed:
  /// through the stack while the job is still unwinding it, so the closing
  /// of an engine waits for that too, and on the spot — late and alone —
  /// once the job is over. A late error goes to `onError` and
  /// `onUnanswered` as always, and so does an error of the disposer itself.
  ///
  /// On the stack the two differ: [dispose] runs whatever the outcome,
  /// [discard] only if the value reaches nobody. So [discard] is for what
  /// the body returns or hands outside, and a lock, a temporary file or a
  /// subscription takes [dispose] — or it leaks on the successful path,
  /// where no test on cancellation will see it. Passing both is an
  /// [ArgumentError].
  ///
  /// The engine catches a late value from the moment it learns the body
  /// has ended, not from its `return`: a call the body walked away from
  /// with `unawaited` may hand its value over before that. A call that
  /// gives out a resource is not one to walk away from.
  ///
  /// ```dart
  /// final db = await ctx.wait(
  ///   Database.open,
  ///   discard: (db) => db.close(),
  /// );
  /// ```
  Future<T> wait<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
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
  /// [dispose] or [discard], and the value goes there instead. The rule is
  /// the same as in [wait]: a value that did not reach the body is cleaned
  /// up on the spot — and here that is awaited before the [Cancelled] is
  /// thrown, so an engine waiting for the job waits for the disposal too
  /// and the next job starts with the resource gone; a value that did
  /// reach the body goes on the cleanup stack, [dispose] to run whatever
  /// the outcome and [discard] only if the value reaches nobody. Passing
  /// both is an [ArgumentError]. Only a value is handed over: an [action]
  /// that threw has nothing to dispose of.
  ///
  /// ```dart
  /// final db = await ctx.join(
  ///   Database.open,
  ///   discard: (db) => db.close(),
  /// );
  /// ```
  ///
  /// An error from [action] is thrown as it is, cancelled or not, and the
  /// body can catch it like any other — **so await this call.** A body that
  /// walked on can end while [action] is still in flight, and the error
  /// then reaches a future nobody awaits: Dart hands that to the zone,
  /// where [wait] would have handed it to `onError` and `onUnanswered`. The
  /// value half of the same case is taken care of — it goes quietly to
  /// [dispose] or [discard]. An error from the disposer goes to `onError`
  /// and `onUnanswered`, and the [Cancelled] is thrown all the same. Throws
  /// [Cancelled] up front if the job is already cancelled or its rules no
  /// longer hold, the same as [wait] and [uncancellable].
  ///
  /// The checkpoint after [action] releases the value whatever it throws,
  /// not only for a [Cancelled]: a rule of a domain that throws instead of
  /// answering ends the job with that error, and the resource goes to
  /// [dispose] or [discard] on the way out.
  Future<T> join<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
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
  /// closes, and the next member of the context throws it. Plainly: while
  /// the body is inside, the callbacks of [onCancel] are not called at all
  /// — they are called the moment the section closes, before the body goes
  /// on, and the body itself learns of the cancellation after that. So the
  /// step is protected, and the job still ends up cancelled — anything
  /// after the step that has to happen anyway belongs inside the same
  /// section, and a job that must survive a cancellation altogether is
  /// created with `cancellable: false`. That refusal is final and is what a
  /// section leaves alone. Sections nest — only the outermost lets a held
  /// cancellation through — and it is let through even if [action] throws.
  ///
  /// When [action] throws while a cancellation is held, the error came
  /// before the cancellation, and it goes on the way a failure a
  /// cancellation covered does — see [Failed]. That is said of this error
  /// alone: the body keeps it so by letting it through or rethrowing it,
  /// while a new error thrown in its place, a wrapper included, comes after
  /// the cancellation landed and only [JobObserver.onError] hears it.
  ///
  /// **Always await this call.** The section belongs to the job, not to the
  /// future returned here: it opens on the call and holds a cancellation
  /// whether the body waits for it or not. A body that walked on can end
  /// while the section is still open, and then the held cancellation lands
  /// on a job that is already over and is dropped — [Job.cancel] returns on
  /// a job whose outcome is [Done], and nothing says otherwise. What
  /// [action] throws has nowhere to go either: nobody awaits this future,
  /// so its error reaches the zone instead of the observer. And if the job
  /// is not over yet — its body ended but a child of it is still running —
  /// the held cancellation lands on a job that is very much alive: it
  /// becomes the outcome over the value the body returned, and the
  /// registrations of [JobContext.onDiscard] run.
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
  ///
  /// A section is also how an asynchronous hand-over stays together with
  /// its [disown]: inside it, between the step and the `disown`, there
  /// must be nothing that throws this job's cancellation — no member of
  /// this context, no `await child.value` of its child. A cancellation
  /// the rules of a domain make cannot be held, and any of those would
  /// throw after the step, leaving the value handed over and its cleanup
  /// still registered.
  ///
  /// ```dart
  /// await ctx.uncancellable(() async {
  ///   await transaction.commit(); // a bare await, not ctx.join
  ///   ctx.disown(transaction);
  /// });
  /// ```
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
  /// by [callback] goes to `onError` and `onUnanswered`; the cancellation
  /// itself is not affected and the other callbacks still run.
  ///
  /// [callback] is synchronous, and only what it throws synchronously is
  /// caught. `void Function()` takes an `async` function without a word
  /// from the analyser, and the future one of those returns is awaited by
  /// nobody: its failure goes to the zone it happens to run in, past any
  /// observer. For something that stops asynchronously, hand the work to
  /// the engine and let it hold the error:
  ///
  /// ```dart
  /// ctx.onCancel(() => ctx.unattended(device.stop));
  /// ```
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
  /// complete after the cleanup that would be waiting for them.
  void Function() onDispose(FutureOr<void> Function() disposer);

  /// Registers [disposer] to run only if the job ends without handing its
  /// value over: cancelled, or failed.
  ///
  /// For what the body returns or hands outside; everything else — a
  /// lock, a temporary file, a subscription — takes [onDispose], or it
  /// leaks on the successful path where no test on cancellation will see
  /// it. Returns a function that unregisters it.
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

  /// Drops the cleanup registered for [value] by [wait] or [join].
  ///
  /// Returns whether anything was dropped. The lookup is by identity, so
  /// pass the very object the body was handed: an equal one of its own —
  /// a string, a record, a number built again — finds nothing.
  /// Registrations made by [onDispose] and [onDiscard] carry no value and
  /// are invisible here — they are dropped by the function those members
  /// return; an unknown value is not an error. With two registrations for
  /// one value the top one goes, one per call.
  ///
  /// Stands next to the hand-over: before it, when the hand-over is
  /// synchronous and may throw after its own work (`emit` of `solo`), and
  /// inside the same uncancellable section, when it is asynchronous.
  bool disown(Object value);

  /// Starts [child] right now, as a child of this job, ahead of whatever
  /// an engine of a domain would have put it through.
  ///
  /// Starts synchronously, then returns a future with the child's value after
  /// the child, its children and its cleanup finish. Keep [child] itself when
  /// its handle is needed. A child error or cancellation reaches the future
  /// with its original stack trace.
  ///
  /// The parent finishes only after all its children. Its cancellation
  /// cascades onto them, and a child created with `cancellable: false` refuses
  /// that cascade. The future still waits for a child that refuses or holds
  /// cancellation. If that child succeeds while the parent's body is still
  /// active, the future checks the parent and throws its accepted [Cancelled]
  /// instead of returning the value. If the body ended without awaiting the
  /// future, a later success returns its value without checking the closed
  /// context.
  ///
  /// Once the child starts, this method observes its [Job.value]. Handle the
  /// future returned here even when [Job.ignore] was called on [child]: that
  /// ignores the job's own reporting, not an error carried by this future. A
  /// failure of the child's body that a cancellation covered afterwards does
  /// not come through the future: the future throws the [Cancelled], and the
  /// child answers for the failure through [JobObserver.onUnanswered], by
  /// default in the zone, unless [Job.ignore] was called on [child].
  ///
  /// A child is a job nobody starts by itself: [Job.deferred], or a job of
  /// an engine whose start belongs to the engine. One from `Job(body)` is
  /// refused, whether or not its own start has come round yet: which of
  /// the two got there first is a matter of microtasks nobody can see in
  /// the source.
  ///
  /// Admission errors are synchronous: throws [ArgumentError] for a handle
  /// that is not a job of this kernel, one an engine of a domain does not own,
  /// or one that starts itself; [StateError] for a job that has already been
  /// started; and the parent's own [Cancelled], with the child dropped, if the
  /// parent is already cancelled.
  ///
  /// [dispose] and [discard] say how the child's value is cleaned up, and
  /// they work as they do in [wait]: [dispose] runs whatever the outcome,
  /// [discard] only if the value reaches nobody, and passing both is an
  /// [ArgumentError] thrown before the child starts. They are how a value
  /// that travels is registered again on arrival, and the registration is
  /// made the moment the value comes back — before the checkpoint above,
  /// because that checkpoint is what takes the value away:
  ///
  /// ```dart
  /// final db = await ctx.run(connect, discard: (db) => db.close());
  /// ```
  ///
  /// Written on the next line instead, the registration is never reached
  /// when the parent is cancelled or a rule of its domain refuses right
  /// there — and the child, having ended [Done], has already dropped its
  /// own. Nothing would close the database at all.
  Future<T> run<T>(
    Job<T> child, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  });

  /// Runs [children] side by side and stops the rest as soon as one of
  /// them goes wrong.
  ///
  /// Starts every child synchronously, in the order of the list, and
  /// returns their values in that same order — not in the order they
  /// finished. The list is read once, by copy, before the first start: an
  /// `Iterable` promises neither repeatability nor stability, and the
  /// bodies start soon enough to change the list it was built from. The
  /// same handle twice is refused before anything starts.
  ///
  /// As soon as the body of any branch ends in anything but a value, the
  /// other branches are asked to stop with [SiblingCancelReason] — the
  /// branch the trouble came from is not, or its own error would turn into
  /// a cancellation and be lost. What comes out is decided by the final
  /// outcomes, not by that early word: a real failure if there is one,
  /// otherwise the first cancellation that arrived. The object thrown is
  /// the one the outcome carries — exactly what `await ctx.run(child)`
  /// would have thrown — so a cancellation arrives as a cancellation and
  /// there is no envelope to take apart. A failure the group received and
  /// did not throw is not lost either: it goes the way an error nobody
  /// answered for goes, once. Nor is a failure of a branch's body that a
  /// cancellation covered afterwards: the outcome carries the cancellation,
  /// and the branch answers for the failure the same way. [Job.ignore] on a
  /// branch silences both: [JobObserver.onError] hears them, and nobody
  /// answers for them.
  ///
  /// **When which.** `[ctx.run(a), ctx.run(b)].wait` and [Future.wait] wait
  /// for every branch and stop none, so a branch whose sibling has already
  /// failed runs to its end and settles its own registrations on the way.
  /// They differ in what comes out: `.wait` throws a `ParallelWaitError`
  /// holding the values and the errors of every branch at once, and
  /// [Future.wait] throws the first error to reach it and lets the rest go.
  /// Take either when the branches do not depend on each other's failure,
  /// or when one of them waits for another.
  /// Take this one when a result missing one of its parts is of no use
  /// anyway: it asks the rest to stop, holds every branch until the decision
  /// is made, and throws the outcome itself. `eagerError: true` is not the
  /// middle ground it looks like: it wakes the body on the first error and
  /// asks nobody to stop, so the job still ends with its last child.
  ///
  /// **The stop is cooperative.** A branch that waits through [wait] ends,
  /// and the operation behind it plays on and writes its result; to stop
  /// the work itself, hand the cancellation to it through [onCancel] and
  /// wait for it with [join]. A branch created with `cancellable: false`
  /// refuses the stop, and the group waits for it. The descendants of the
  /// branch that failed are not cancelled — a failure never cascades — so
  /// the group waits for them too.
  ///
  /// **No branch ends before the group has decided.** A branch stands
  /// twice: once when its body is over and before it unwinds, once between
  /// the two passes of its unwinding. That is what keeps a resource a
  /// branch took for the caller — one registered through `discard` — alive
  /// until the group is sure the caller will get it, and closed by the
  /// branch itself when it will not. While a branch is held, its outcome
  /// is not final: a body that returned a value may still end [Cancelled].
  ///
  /// **A branch must not wait for another branch of the same group.**
  /// Awaiting a sibling's [Job.value] never finishes: the sibling is held
  /// until the group decides, and the group decides only once every branch
  /// is held. Nothing here catches that; for branches that depend on each
  /// other use `[a, b].wait` instead, which waits for all of them and
  /// stops none.
  ///
  /// On success the group does not wait for the tails of its branches: the
  /// values are handed over the moment the decision is made, and whatever
  /// a branch still has to unwind plays out under the parent, which waits
  /// for its children as always. On failure it is the other way round —
  /// every branch is stopped and waited for, so that by the time the error
  /// arrives everything the branches took is closed.
  ///
  /// An empty group starts nothing and returns an empty list, after making
  /// the same checks [run] would make. Admission errors are those of [run],
  /// and a refusal that arrives after some branches have started stops them
  /// and waits for them before it comes out.
  Future<List<T>> runAll<T>(Iterable<Job<T>> children);

  /// Starts a child job that processes [stream] one event at a time.
  ///
  /// Returns the child immediately without observing its outcome. Await its
  /// [Job.value] to propagate its outcome into the body, or use [Job.done] to
  /// inspect the outcome. The parent waits for this child even when the body
  /// does not await it.
  /// An open stream therefore keeps the parent alive until the stream ends
  /// or the child is cancelled. Cancelling the child alone does not mark
  /// the parent cancelled.
  ///
  /// [onData] receives the child's context. Use its checkpoints to react
  /// to the child's cancellation. An asynchronous handler is awaited before
  /// the next event is delivered. Stream and handler errors end the child
  /// and follow the usual [Job] error reporting rules.
  ///
  /// Cancellation stops delivery and cancels the subscription immediately,
  /// then waits for an active handler before finishing the child and running
  /// its cleanup. A plain future inside the handler cannot be interrupted;
  /// use the child's [wait] or [join] as appropriate. Do not await the
  /// child's own completion or cancellation from its handler.
  ///
  /// The future returned by the subscription's cancellation is ignored:
  /// cleanup owned by the source is not awaited. A normal stream ending
  /// still depends on the source delivering its `onDone` notification.
  ///
  /// Throws synchronously if a child cannot be started, as [run] does:
  /// after the parent's body ended, during cleanup, from [unattended] work,
  /// or after cancellation was accepted.
  ///
  /// ```dart
  /// final listening = ctx.each<int>(events, (child, event) {
  ///   child.log(event);
  /// });
  /// await listening.cancel();
  /// ```
  Job<void> each<T>(
    Stream<T> stream,
    FutureOr<void> Function(JobContext ctx, T event) onData,
  );

  /// Hands [message] to [JobObserver.onLog] as it is.
  ///
  /// Nothing happens to it on the way: a listener that wants a line makes
  /// one, a listener that wants the object keeps it. A no-op when the job
  /// has no observer, so a body logs unconditionally, and a message that
  /// is expensive to put into words costs nothing until somebody listens.
  void log(Object? message);

  /// Runs [action] as work this job does not wait for.
  ///
  /// The fourth member of the waiting family, and the one that does not
  /// wait: [wait] waits for the call but not the work, [join] waits for
  /// all of it, [uncancellable] waits with the cancellation held back, and
  /// this one hands the work to the engine and comes back at once.
  /// Whatever [action] leaves uncaught — now, or long after the job is
  /// over — belongs to the job: its observer hears it through `onError`,
  /// and `onUnanswered` answers for it, in the zone the job was created in
  /// by default and there too when there is no observer. Written any other
  /// way, such a failure belongs to nobody and lands in whatever zone it
  /// happens to fail in.
  ///
  /// ```dart
  /// ctx.unattended(() => analytics.report(event));
  /// ```
  ///
  /// The job does not wait for the work, does not cancel it and does not
  /// stop it outliving the job. The job's own cancellation is not
  /// reported when the work leaves it uncaught: a cancellation is a
  /// decision, not a failure, and whoever listens has heard it on the
  /// outcome already. That covers what comes out of [action]; a [wait] or
  /// a [join] made in here keeps its own rules, and an action *it* was
  /// left holding still reports its late failure — a [Cancelled]
  /// included — the way it does anywhere else. A throw of [action] goes
  /// the same way as one from a future it started — to `onError` and
  /// `onUnanswered`, never into the body: background work must not decide
  /// the outcome of the job that started it.
  ///
  /// **Start the work in here and take nothing out of it.** The work runs
  /// in an error zone of its own, and that boundary holds both ways. A
  /// future made outside and awaited in here never comes back if it
  /// fails, and its error goes to whoever made it — the process, in an
  /// ordinary program. A future born in here and awaited outside hangs
  /// whoever waits for it **if it fails** — a body that changed its mind,
  /// a disposer, a memoized cache first filled from the background — and
  /// a failure is exactly the case nobody plans for. The `void` return
  /// does not stop a closure carrying one out, and nothing will warn you.
  ///
  /// [run] and [uncancellable] throw a [StateError] when called from
  /// inside [action]: both act on the whole job, and this work is not the
  /// job. A child started here would hang on that boundary with the
  /// parent waiting for it forever, and a section opened here would hold
  /// back the cancellation of a body that stands in no section at all.
  /// [wait] and [join] are fine — they register on the job and behave.
  ///
  /// **How the work stops.** Not by polling [check]: while the engine
  /// unwinds the cleanup stack it throws a [StateError] instead of the
  /// cancellation, and on a job that ended [Done] it does not throw at
  /// all, so a loop waiting for it waits forever and holds the job while
  /// it waits. Ask `job.isFinished`, or wait for `job.done`. Work that
  /// must end with the job puts its own stop on the cleanup stack —
  /// `ctx.onDispose(timer.cancel)` — or takes the cancellation through
  /// [onCancel], which is also the natural place to hand out an
  /// asynchronous stop whose failure should be heard:
  ///
  /// ```dart
  /// ctx.onCancel(() => ctx.unattended(device.stop));
  /// ```
  ///
  /// **Unfinished work holds the job**, its outcome and the body's
  /// closure with everything it captured — and, in `solo`, the controller
  /// itself, with its state and its listeners, after `close()` too. A
  /// periodic timer left running in here leaks all of that.
  ///
  /// A job created in here is not this work: it has an outcome and an
  /// observer of its own, and its unobserved failure goes to the zone the
  /// body runs in rather than to this job's observer. Quench it with
  /// [Job.ignore]. The `emit` of `solo` works from in here too, while the
  /// job is alive, the same as [wait] does.
  ///
  /// Legal on a job already marked cancelled, and legal while the engine
  /// unwinds the cleanup stack — a disposer starting work nobody waits
  /// for is the case this member was made for. Once the job has finished
  /// it throws a [StateError].
  ///
  /// A bare `unawaited(work())` is not covered: it belongs to no member of
  /// this context, its failure goes to the zone as it always has, and this
  /// member is what to write instead of it.
  void unattended(FutureOr<void> Function() action);

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

  /// Creates the unstarted child used by [each].
  ///
  /// A domain that restricts child ownership overrides this factory to
  /// return its own job with the appropriate context and rules. The result
  /// must be accepted by [startChild]. This factory must not start the child.
  @protected
  Job<void> createEachJob(Future<void> Function(JobContext ctx) body) =>
      Job.deferred<void>(body, describe: () => 'each');

  @override
  Job<void> each<T>(
    Stream<T> stream,
    FutureOr<void> Function(JobContext ctx, T event) onData,
  ) {
    throwIfUnattended('follow a stream');
    throwIfFinished('follow a stream');
    final child = createEachJob(
      (child) => child._followStream(stream, (event) => onData(child, event)),
    );
    startChild(child);
    return child;
  }

  @override
  void check() {
    throwIfDisposing('check');
    throwIfCancelled();
  }

  /// The cancellation the job is marked with, or `null`.
  @protected
  Cancelled? get pendingCancel => _owner._pendingCancel;

  /// Throws the job's cancellation if it is marked, or if it ended with
  /// one: an engine of a domain that finished the job by hand never marked
  /// it, and the cancellation lives in the outcome alone.
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

  /// Throws [StateError] when called from inside this job's own
  /// [JobContext.unattended] work.
  ///
  /// Two members act on the whole job, and unattended work is not the
  /// job: a child started there would hang on the fork's boundary with
  /// the parent waiting for it forever, and a section opened there would
  /// hold a cancellation of a body that stands in no section at all.
  /// Another job's fork is not this job's business, and the key is the
  /// job itself: forks nest, and a shared key would let the inner one
  /// answer for the outer.
  @protected
  void throwIfUnattended(String action) {
    if (identical(Zone.current[_owner], _owner)) {
      throw StateError('$_owner cannot $action inside unattended work');
    }
  }

  /// Announces [error] and asks for an answer to it: the observer's
  /// `onError` and `onUnanswered`, or the zone when there is no observer.
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
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  }) async {
    throwIfFinished('join');
    _oneCleanupOnly(dispose, discard);
    check();
    final result = await action();
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
  /// Synchronous on purpose: `wait` registers between taking the value and
  /// handing it to the body, and an `await` in that gap would let a
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
      // The job ended while the call was in flight, and an engine of a
      // domain finishing by hand is the only way in. There is no stack
      // left to register on: `addCleanup` would throw a complaint about
      // registering on a finished job, the caller would see that instead
      // of its value, and the value itself would be left to nobody.
      // Released on the spot, the way one that came back too late is, and
      // the caller hears the plain truth about the job instead. With no
      // disposer there is nothing to lose, so nothing changes there.
      unawaited(_dispose(disposer, value));
      throwIfFinished('take the value of a call it made');
    }
    addCleanup(() => disposer(value), always: dispose != null, value: value);
  }

  /// Cleans up [value] that came out after the body had ended.
  ///
  /// It reached nobody, so the outcome does not matter: on a job that has
  /// finished the disposer runs on the spot and nobody waits for it, and
  /// while the engine unwinds the stack the registration is unconditional
  /// — the same pass takes it off.
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
    } on Object catch (error) {
      // The step failed, and the cancellation this section was holding
      // lands on the way out -- before the error has reached the body,
      // where the kernel decides which of the two came first. It was the
      // failure, and said nowhere else the diagnosis of the one step that
      // cannot be rolled back is the one the cancellation swallows. Only
      // when a cancellation is held and nothing has marked the job: without
      // one nothing lands on the way out, and after a mark -- a rule of a
      // domain makes one inside the section -- the held one has nothing
      // left to land, and the step failed after the mark.
      if (_owner._heldCancel != null && _owner._pendingCancel == null) {
        _owner._failedBeforeMark = error;
      }
      rethrow;
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
      // cancellation: its error belongs to `notifyError`, not to whoever
      // happened to trigger the cancel.
      try {
        callback();
      } on Object catch (error, stackTrace) {
        if (error is StackOverflowError && _owner._outOfStack) {
          // Not `onError`, and above all not the zone, while the engine
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
  /// `wait` and `join` pass the value they hand to the body, so that
  /// `disown` can find the registration by it.
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

  @override
  Future<T> wait<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  }) async {
    throwIfFinished('wait');
    _oneCleanupOnly(dispose, discard);
    check();
    final result = action();
    if (result is! Future<T>) {
      if (_owner.bodyEnded) {
        await _keepLate(dispose, discard, result);
        return result;
      }
      // The action may have cancelled this job while it ran, and a value
      // made after the mark is one the body must not see: `_race` answers
      // that way for a future completing after the mark, and `join` for an
      // action of its own. A member whose answer turns on whether the call
      // happened to be synchronous is a member nobody can reason about.
      //
      // The cancellation alone, not `check()`: `wait` promises to end the
      // waiting when the job is marked, and the rules of a domain are no
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
  /// comes first. A result arriving after cancellation goes to
  /// [discard], or nowhere if there is none; an error arriving after
  /// cancellation goes to [notifyError].
  Future<T> _race<T>(
    Future<T> future,
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  ) {
    final completer = Completer<T>();
    // Whether this call was made from inside work handed over with
    // `unattended`. A late failure then still has a listener -- the work
    // itself -- and the fork announces what the work leaves uncaught, so
    // the kernel announcing it as well would say one error twice.
    final fromFork = identical(Zone.current[_owner], _owner);
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
          // The value did not reach the body: cleaned up whatever the
          // outcome, and on the same terms as any other late value — on
          // the stack while the job is still unwinding it, so whoever
          // waits for the job waits for the release too.
          await _keepLate(dispose, discard, value);
        } else if (_owner.bodyEnded) {
          // The registration below costs a microtask even when there is
          // nothing to register, and a cancellation arriving in it
          // finishes this future through the callback still standing.
          // Hence the second reading: without it the completion throws
          // `Future already completed` out of the kernel, and the job
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
          // The body is gone, and it is not the one still holding this
          // future. Whatever is -- a `.timeout` that fired, a
          // `Future.any` that took another branch -- walked away from it
          // and swallows what it is handed, so handing the error over and
          // saying nothing would lose it for good. Announced here, the
          // way the failure of any abandoned action is, and the future
          // completed all the same, so that nothing left waiting on it
          // waits for ever; `ignore` keeps that copy from being announced
          // a second time by the zone.
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
    Job<T> child, {
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
  Future<List<T>> runAll<T>(Iterable<Job<T>> children) {
    // Read once, by copy, before anything starts: an `Iterable` promises
    // neither repeatability nor stability, and the bodies below start
    // synchronously and may change the list this was made from. A
    // generator that throws throws from here, before any child has run.
    final branches = List<Job<T>>.of(children);
    // By identity and not by `==`: a job of a domain may compare itself by
    // a key, and two children of one queue are equal and still two jobs.
    // Before the first start, so that a repeat is refused without half of
    // the group already running.
    final seen = Set<Job<T>>.identity();
    for (final child in branches) {
      if (!seen.add(child)) {
        throw ArgumentError.value(
          child,
          'children',
          'is in the group more than once',
        );
      }
    }
    if (branches.isEmpty) {
      // Nothing to start, and the same answers `run` would give: an empty
      // group is not a way around the checks of the context.
      throwIfUnattended('run a group of children');
      throwIfFinished('run a group of children');
      if (_owner.bodyEnded) {
        throw StateError('$_owner has ended its body, cannot run a child');
      }
      if (_owner.pendingCancel case final pending?) {
        throw pending;
      }
      return Future<List<T>>.value(<T>[]);
    }
    return _RunAllGroup<T>(this, branches).run();
  }

  Future<T> _awaitChild<T>(
    Job<T> child, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  }) async {
    final value = await child.value;
    // Registered before the checkpoint, and that is the whole of it. The
    // child ended [Done], so its own conditional registration went with
    // the value and is gone; a checkpoint throwing here -- the parent's
    // cancellation, or a rule of its domain refusing -- would take the
    // value with it, and there would be nobody left holding the resource.
    if (_owner.bodyEnded) {
      await _keepLate(dispose, discard, value);
    } else {
      _keepOnStack(dispose, discard, value);
      check();
    }

    return value;
  }

  /// Adopts and starts [child] synchronously.
  ///
  /// A domain that restricts child ownership overrides this method, performs
  /// its own validation, then calls `super.startChild(child)`. It applies the
  /// synchronous admission rules of [run] and does not observe the child's
  /// outcome.
  @protected
  void startChild<T>(Job<T> child) {
    throwIfUnattended('run a child');
    throwIfFinished('run a child');
    if (_owner.bodyEnded) {
      // The body is gone, and a child started now would be waited for by
      // nobody: the engine has already left the children behind.
      throw StateError('$_owner has ended its body, cannot run a child');
    }
    if (child is! JobBase<T>) {
      throw ArgumentError.value(child, 'child', 'is not a job of this core');
    }
    if (child is _AutoJob) {
      // Refused before the status is even looked at, so that the answer
      // does not depend on which got here first: on the same synchronous
      // stripe this call would still find it `created` and adopt it, one
      // microtask later it is already running on its own. The start of a
      // child belongs to its parent.
      throw ArgumentError.value(
        child,
        'child',
        'starts itself; a child is made with Job.deferred',
      );
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

    /// Turns [child] away because this job is already giving up, and
    /// returns the cancellation to throw into the body.
    Cancelled refuse(Cancelled pending) {
      _owner._cancelChild(child, pending);
      return pending;
    }

    if (_owner.pendingCancel case final pending?) {
      throw refuse(pending);
    }
    // Everything that can refuse the child happens before it joins the
    // waiting list, and a refusal that arrives as a throw — a rule of a
    // domain, a context that would not be built — ends the child rather
    // than leaving it be. By now it has a parent, a level and an observer,
    // and a job like that, left alive, would sit half-adopted: parented,
    // levelled, never started and waited for by nobody. `ignore` first: the
    // error is already on its way to the body through the rethrow, and one
    // error is announced once.
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
        _owner._children.add(child);
        child.start();
      }
    } on Object catch (error, stackTrace) {
      // By identity, as in `finish`: the refused child is taken off the
      // list here, before it is finished, so `finish` will not do it later
      // and a plain `remove` would take a sibling equal by `==` instead.
      _owner._children.removeWhere((each) => identical(each, child));
      child
        ..ignore()
        ..finish(Failed(error, stackTrace));
      rethrow;
    }
    if (markedWhileAsking case final pending?) {
      throw refuse(pending);
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
      // Two values, and the key of the second is the job itself: forks of
      // different jobs nest, and one shared key would let the inner one
      // hide the outer. Under a key of its own each job sees its own work
      // and nobody else's.
      //
      // The job is the value as well as the key, and the readers compare
      // it by identity. A zone looks a key up by `==`, and a job of a
      // domain may well compare itself by a key of its own: two such jobs
      // are equal, and one would otherwise find itself inside the other's
      // fork and refuse what is perfectly legal.
      zoneValues: {_unattendedKey: from, _owner: _owner},
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
    // `_outcome` and not only `_pendingCancel`: an engine of a domain
    // that finishes a job by hand never marks it, and the cancellation
    // lives in the outcome alone.
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
/// that made it, and its key is that job.
final _unattendedKey = Object();

/// The context of a job of the core itself.
final class _CoreContext extends JobContextBase {
  _CoreContext(super.owner);
}

/// What a group of [JobContext.runAll] needs from a branch it holds.
///
/// It lives on the branch because the barriers are inside the kernel's own
/// unwinding; every call here goes straight back to the group.
final class _GroupHold {
  /// The body of the branch has ended with this outcome, and nothing at
  /// all is decided by that.
  final void Function(Outcome<Object?> outcome) bodyEnded;

  /// Stands at the first barrier until the group lets the branch unwind.
  final Future<void> Function() beforeDisposal;

  /// Stands at the second barrier. The answer is the verdict of the group:
  /// `true` when it has committed the value of this branch.
  final Future<bool> Function() beforeOutcome;

  _GroupHold({
    required this.bodyEnded,
    required this.beforeDisposal,
    required this.beforeOutcome,
  });
}

/// One branch of a group, and everything the group keeps about it.
final class _GroupBranch<T> {
  final JobBase<T> job;

  /// Completed when the group lets the branch into its unwinding.
  final pastFirstBarrier = Completer<void>();

  /// Completed with the verdict when the group lets the branch to its
  /// outcome.
  final pastSecondBarrier = Completer<bool>();

  /// Whether the branch is standing at the first barrier right now.
  bool atFirstBarrier = false;

  /// Whether the branch is standing at the second barrier right now.
  bool atSecondBarrier = false;

  /// The outcome of the body, as the early word gave it.
  Outcome<T>? bodyOutcome;

  /// Whether this call asked the branch to stop.
  ///
  /// The cancellation that then ends the branch is not an outcome of the
  /// group, whoever built it: the request may have been refused, or lost
  /// to a cancellation that arrived in the same minute, and a match of
  /// objects would not prove who created one anyway. A [Failed] is never
  /// filtered — a branch that refused the stop and failed on its own has
  /// a diagnosis of its own.
  bool askedToStop = false;

  /// The final outcome, once the branch has one.
  Outcome<T>? settled;

  _GroupBranch(this.job);
}

/// The coordinator behind [JobContext.runAll].
///
/// It starts every branch, asks the others to stop as soon as one goes
/// wrong, holds each of them at two barriers so that none can reach an
/// outcome before the group has decided, and then either hands the values
/// over in one synchronous step or waits for every branch to finish and
/// throws.
final class _RunAllGroup<T> {
  final JobContextBase _ctx;
  final List<Job<T>> _children;
  final _branches = <_GroupBranch<T>>[];

  /// The branches that have finished, in the order the group learned it.
  /// Which one came first is what decides between two cancellations.
  final _received = <_GroupBranch<T>>[];

  /// Set once the group is on its way out with an error.
  bool _failing = false;

  /// Whether the group has handed its values over.
  bool _committed = false;

  /// A refusal of admission. It wins over whatever the branches end with:
  /// the caller asked for a group that was never allowed to form.
  (Object, StackTrace)? _refusal;

  /// An error thrown by the code of the group itself — the check of the
  /// parent above all. It wins the same way.
  (Object, StackTrace)? _ownError;

  Completer<void>? _changing;

  _RunAllGroup(this._ctx, this._children);

  Future<List<T>> run() {
    for (final child in _children) {
      try {
        _ctx.startChild(child);
      } on Object catch (error, stackTrace) {
        // `startChild` has already finished this child with this very
        // error, and the error is what comes out of the group. The child
        // does not join the branches, or the group would report it a
        // second time as a failure nobody chose.
        _refusal = (error, stackTrace);
        break;
      }
      if (child is! JobBase<T>) {
        // Unreachable: `startChild` refuses a handle that is not a job of
        // this core before it starts anything.
        continue;
      }
      // Attached after the admission and not before it, and the difference
      // is not cosmetic: a handle already running as a branch of another
      // group is refused here by `StateError`, and touching its hold on
      // the way would take that group's branch out of its hold — the very
      // hole this member exists to close. The barriers are safe after:
      // `_execute` awaits the descendants before it reaches one. The early
      // word is not, and it is read off the branch below.
      final branch = _GroupBranch<T>(child);
      branch.job._hold = _holdFor(branch);
      _branches.add(branch);
      // `done` and not `whenDone`: the group looks at every outcome and
      // answers for the failures it does not throw, so no branch is left
      // reporting one on its own as well. A failure a cancellation covered
      // is in no outcome, and the group never sees it: the branch answers
      // for that one itself, as any job does.
      branch.job.done
          .then((outcome) => _branchFinished(branch, outcome))
          .ignore();
    }
    // The early word a branch said before it had a hold. A body that
    // throws before its first `await` runs to its end inside `startChild`,
    // and the hold attached a line later was not there to hear it. Read
    // here and not from the loop: until every branch is admitted and on
    // the list, a stop would go round the siblings the loop has not
    // started yet. Still the same synchronous step, so none of them has
    // moved past its first suspension point, and the stop reaches every
    // one of them before it does any more work.
    for (final branch in _branches) {
      if (branch.bodyOutcome != null) {
        continue;
      }
      if (branch.job._bodyOutcome case final outcome?) {
        _branchBodyEnded(branch, outcome);
      }
    }
    if (_refusal case final refusal?) {
      if (_branches.isEmpty) {
        // Nothing started and nobody to wait for: the refusal comes out
        // the way `run` gives one, synchronously.
        Error.throwWithStackTrace(refusal.$1, refusal.$2);
      }
      _beginFailing(refusal.$1, null);
    }
    return _settle();
  }

  _GroupHold _holdFor(_GroupBranch<T> branch) => _GroupHold(
        bodyEnded: (outcome) => _branchBodyEnded(branch, outcome),
        beforeDisposal: () => _parkBeforeDisposal(branch),
        beforeOutcome: () => _parkBeforeOutcome(branch),
      );

  void _branchBodyEnded(_GroupBranch<T> branch, Outcome<Object?> outcome) {
    // The branch is a `JobBase<T>`, so this is an outcome of its own type.
    branch.bodyOutcome = outcome as Outcome<T>;
    _sawTrouble(branch, outcome);
    _wake();
  }

  void _branchFinished(_GroupBranch<T> branch, Outcome<T> outcome) {
    branch.settled = outcome;
    _received.add(branch);
    _sawTrouble(branch, outcome);
    _wake();
  }

  /// Starts the stop unless [outcome] is a value, or the cancellation this
  /// very call asked for.
  void _sawTrouble(_GroupBranch<T> branch, Outcome<Object?> outcome) {
    if (_failing || _committed || outcome is Done<Object?>) {
      return;
    }
    if (outcome is Cancelled && branch.askedToStop) {
      // Not trouble: the stop working.
      return;
    }
    _beginFailing(_causeOf(outcome), branch);
  }

  Object _causeOf(Outcome<Object?> outcome) =>
      outcome is Failed ? outcome.error : outcome;

  /// Asks every branch but [source] to stop, and lets go of whoever is
  /// already waiting at a barrier.
  void _beginFailing(Object cause, _GroupBranch<T>? source) {
    _failing = true;
    final reason = SiblingCancelReason(cause: cause);
    for (final branch in _branches) {
      if (identical(branch, source) ||
          branch.askedToStop ||
          branch.job.isFinished) {
        continue;
      }
      final cancelled = Cancelled.by(
        reason: reason,
        started: branch.job.isRunning,
        stackTrace: StackTrace.current,
      );
      // Remembered before the call and not after it: `cancelWith` reaches
      // code that may come straight back here.
      branch.askedToStop = true;
      try {
        branch.job.cancelWith(cancelled);
      } on Object catch (error, stackTrace) {
        // An engine of a domain threw while being asked to stop. That is
        // not an outcome of any branch, and above all it must not leave
        // the rest of them standing at their barriers: the loop goes on,
        // and the error comes out of the group the way a refusal of
        // admission does.
        _ownError ??= (error, stackTrace);
      }
    }
    for (final branch in _branches) {
      _letPastFirstBarrier(branch);
      _letPastSecondBarrier(branch, committed: false);
    }
  }

  void _letPastFirstBarrier(_GroupBranch<T> branch) {
    if (!branch.atFirstBarrier) {
      return;
    }
    branch.atFirstBarrier = false;
    branch.pastFirstBarrier.complete();
  }

  void _letPastSecondBarrier(
    _GroupBranch<T> branch, {
    required bool committed,
  }) {
    if (!branch.atSecondBarrier) {
      return;
    }
    branch.atSecondBarrier = false;
    branch.pastSecondBarrier.complete(committed);
  }

  Future<void> _parkBeforeDisposal(_GroupBranch<T> branch) {
    branch.atFirstBarrier = true;
    if (_failing) {
      _letPastFirstBarrier(branch);
    }
    _wake();
    return branch.pastFirstBarrier.future;
  }

  Future<bool> _parkBeforeOutcome(_GroupBranch<T> branch) {
    branch.atSecondBarrier = true;
    if (_failing) {
      _letPastSecondBarrier(branch, committed: false);
    }
    _wake();
    return branch.pastSecondBarrier.future;
  }

  Future<void> _somethingChanges() => (_changing ??= Completer<void>()).future;

  void _wake() {
    final changing = _changing;
    if (changing == null) {
      return;
    }
    _changing = null;
    changing.complete();
  }

  bool _everyBranchIsAtFirstBarrier() => _branches.every(
        (branch) =>
            branch.atFirstBarrier ||
            branch.pastFirstBarrier.isCompleted ||
            branch.job.isFinished,
      );

  bool _everyBranchIsAtSecondBarrier() => _branches.every(
        (branch) => branch.atSecondBarrier || branch.job.isFinished,
      );

  Future<List<T>> _settle() async {
    try {
      while (!_failing && !_everyBranchIsAtFirstBarrier()) {
        await _somethingChanges();
      }
      if (!_failing) {
        _branches.forEach(_letPastFirstBarrier);
        while (!_failing && !_everyBranchIsAtSecondBarrier()) {
          await _somethingChanges();
        }
      }
      if (!_failing) {
        // Step two of the commit: the parent. The successful path does not
        // wait for `child.value`, and the check of the parent that waiting
        // makes goes with it — without this one a group would commit under
        // a parent that is already cancelled, or one whose rules of a
        // domain no longer hold.
        _ctx.check();
        // Step three, and after the check rather than before it: the check
        // runs a predicate of a domain, and that predicate may cancel a
        // branch on its way to answering yes.
        _rereadBranches();
      }
      if (!_failing) {
        return _commit();
      }
    } on Object catch (error, stackTrace) {
      // The code of the group itself threw while the branches stood at
      // their barriers. Nothing may be left held, and a branch whose body
      // returned a value must not slip away as [Done] with what it took
      // for the caller passed over.
      _ownError ??= (error, stackTrace);
      if (!_failing) {
        _beginFailing(error, null);
      }
    }
    // Every branch is stopped and every branch unwinds; the group waits
    // for all of them. That waiting is the promise: by the time the error
    // reaches the parent, whatever the branches took is closed.
    while (_received.length < _branches.length) {
      await _somethingChanges();
    }
    return _conclude();
  }

  /// The outcome a branch would end with if it ended right now.
  Outcome<T>? _provisionalOf(_GroupBranch<T> branch) =>
      branch.job._outcome ?? branch.job._pendingCancel ?? branch.bodyOutcome;

  void _rereadBranches() {
    for (final branch in _branches) {
      final provisional = _provisionalOf(branch);
      if (provisional is Done<T>) {
        continue;
      }
      // The branch that changed is the source, exactly as it would be had
      // it spoken up earlier: naming nobody would mark it asked-to-stop
      // along with the rest, and the filter would then swallow the very
      // outcome the group has to give.
      _beginFailing(
        provisional == null
            ? StateError('${branch.job} stands at the barrier with no outcome')
            : _causeOf(provisional),
        branch,
      );
      return;
    }
  }

  List<T> _commit() {
    // From here to the return there is no `await`. The group decides, takes
    // the put-aside registrations off the branches and hands the values
    // over in one synchronous step, so that a cancellation arriving after
    // it finds nothing left to close.
    final values = [
      for (final branch in _branches)
        (_provisionalOf(branch)! as Done<T>).value,
    ];
    _committed = true;
    for (final branch in _branches) {
      // Step four. On the successful path nobody runs them — exactly as
      // nobody runs what is still put aside at the end of the unwinding.
      // Traced here and not by the branch: by the time it reaches the end
      // of its own unwinding the list is already empty, and the receiver of
      // the values would learn nothing.
      branch.job
        .._traceDroppedCleanups()
        .._skipped.clear();
    }
    for (final branch in _branches) {
      // Step five: released with the verdict, and the list goes back.
      _letPastSecondBarrier(branch, committed: true);
    }
    return values;
  }

  List<T> _conclude() {
    final chosen = _chooseOutcome();
    final refusal = _refusal ?? _ownError;
    for (final branch in _received) {
      final outcome = branch.settled;
      if (outcome is! Failed) {
        continue;
      }
      if (refusal == null && identical(outcome, chosen)) {
        // The caller is about to receive this one.
        continue;
      }
      // Received and not chosen, and where it goes depends on whether it
      // has been announced once already. A failure the body threw was
      // handed to the observer where it was caught, so only the route for
      // an error nobody answered for is left. A failure that never went
      // through the body — an engine of a domain ending the branch by hand
      // with [Failed] — was announced nowhere, and the group is the last
      // one holding it. A branch that [Job.ignore] was called on wants no
      // answer: the notice stays, as it does for a failure a cancellation
      // covered.
      final announced = identical(outcome, branch.bodyOutcome);
      if (branch.job._ignored) {
        if (!announced) {
          branch.job.notifyObserver(outcome.error, outcome.stackTrace);
        }
      } else if (announced) {
        branch.job._handleUnanswered(outcome.error, outcome.stackTrace);
      } else {
        branch.job.notifyError(outcome.error, outcome.stackTrace);
      }
    }
    if (refusal != null) {
      Error.throwWithStackTrace(refusal.$1, refusal.$2);
    }
    if (chosen is Failed) {
      Error.throwWithStackTrace(chosen.error, chosen.stackTrace);
    }
    if (chosen is Cancelled) {
      Error.throwWithStackTrace(
        chosen,
        chosen.stackTrace ?? StackTrace.current,
      );
    }
    throw StateError('${_ctx._owner}: a group failed with nothing to throw');
  }

  /// A real failure if the group received one, otherwise the first
  /// cancellation that arrived — never one this call asked for.
  Outcome<T>? _chooseOutcome() {
    Cancelled? cancelled;
    for (final branch in _received) {
      final outcome = branch.settled;
      if (outcome == null || (outcome is Cancelled && branch.askedToStop)) {
        continue;
      }
      if (outcome is Failed) {
        return outcome;
      }
      if (outcome is Cancelled) {
        cancelled ??= outcome;
      }
    }
    return cancelled;
  }
}
