part of 'job_base.dart';

/// What a job body sees in the core: cancellation, waiting and children.
///
/// Once the job has accepted a cancellation, the members that wait or start
/// something throw that [Cancelled]: [check], [abandonable], [join], [pause],
/// [uncancellable], [onCancel], [run], [runAll] and `each`. The members that
/// only register do not — [onDispose], [onDiscard], [disown] and [unattended]
/// go on working, so a body that has just been cancelled can still put what it
/// holds on the cleanup stack, and still hand out a stop nobody waits for — and
/// neither do [log] and [job]. What a cancellation arriving *during* a call
/// does to that call is the call's own business: see [abandonable], [join],
/// [pause] and [uncancellable].
///
/// A context that outlived its job — captured by a closure nobody awaited
/// — neither waits nor starts nor registers anything: every member throws
/// a [StateError] once the job has finished, except [check], [log] and
/// [job]. While the core unwinds the cleanup stack the same holds for
/// the members that wait or start something, and [check] throws a
/// [StateError] there too — but [onDispose], [onDiscard], [disown] and
/// [unattended] go on working, because a value arriving that late is put
/// on the stack the core is unwinding, and a disposer may hand out work
/// nobody waits for.
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
  /// Legal after the job has finished, where it throws that [Cancelled] as
  /// always — but not while the core cleans up after the body: there it
  /// throws a [StateError] instead. An action the body walked away from
  /// that polls `check` to stop will see that error, not a cancellation,
  /// if it polls inside that window.
  void check();

  /// Runs [action] and waits for it, but no longer than this job lives.
  ///
  /// Throws [Cancelled] up front if the job is already cancelled or its rules
  /// no longer hold. If a cancellation arrives while [action] is in flight, the
  /// wait ends there with that [Cancelled] — and [action] runs on, its result
  /// discarded, an error of its own going to `onError` and on to the job's
  /// answer. It ends the waiting, not the work.
  ///
  /// For anything that must actually stop — a device, a download, a write —
  /// hand the cancellation to it through [onCancel] and wait for it to finish
  /// with [join], instead of walking away from it. Left deliberately unawaited,
  /// write the type out — `unawaited(ctx.abandonable<Db>(...))`: without it `T`
  /// is inferred from `unawaited`, which takes a `Future<void>`, and [dispose]
  /// then has to be a `void Function(void)`, which is not what the call site
  /// says and not what the analyzer explains. What such a call throws while the
  /// body runs, its [Cancelled] included, goes to the zone, as from any future
  /// nobody awaits. For a step that must not be interrupted at all, see
  /// [uncancellable].
  ///
  /// [dispose] and [discard] say how the value is cleaned up, and the rule is
  /// one: **a value that did not reach the body is cleaned up without a
  /// condition; a value that did goes on the cleanup stack.** So a connection
  /// or a file opened by an action the cancellation abandoned still gets
  /// closed, and at once, alongside whatever the job is still doing: a child
  /// the job waits for may want the same slot of a pool, and held for the
  /// unwinding the value would keep it from that child for good. The job ends
  /// only after that release all the same, so the closing of an engine waits
  /// for it too. A value arriving while the job runs its cleanup stack joins
  /// the stack instead, and one arriving once the job is over is released on
  /// the spot — late and alone. A value that comes to a call the body walked
  /// away from without a cancellation still goes to whoever holds its future,
  /// and waits for the unwinding on the stack. A late error goes to `onError`
  /// and on to the job's answer as always, and so does an error of the disposer
  /// itself.
  ///
  /// On the stack the two differ: [dispose] runs whatever the outcome,
  /// [discard] only if the value reaches nobody. So [discard] is for what
  /// the body returns or hands outside, and a lock, a temporary file or a
  /// subscription takes [dispose] — or it leaks on the successful path,
  /// where no test on cancellation will see it. Passing both is an
  /// [ArgumentError].
  ///
  /// The core catches a late value from the moment it learns the body
  /// has ended, not from its `return`: a call the body walked away from
  /// with `unawaited` may hand its value over before that. A call that
  /// gives out a resource is not one to walk away from.
  ///
  /// ```dart
  /// final db = await ctx.abandonable(
  ///   Database.open,
  ///   discard: (db) => db.close(),
  /// );
  /// ```
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
  /// The counterpart of [abandonable] for a call that must not be left in
  /// flight: a device command, a write already on the wire. A cancellation
  /// arriving while [action] runs is accepted at once — and an engine waiting
  /// for the job waits too, because the body is still inside this call — but
  /// the waiting is not cut short. When [action] comes back, this throws that
  /// [Cancelled]; if none arrived, it returns [action]'s value.
  ///
  /// ```dart
  /// await ctx.join(() => device.write(chunk));
  /// ```
  ///
  /// [abandonable] lets go of the action, `join` stays with it, so the next job
  /// never starts against a device still finishing this one, and a body
  /// written this way cannot walk past a cancellation by forgetting a
  /// line.
  ///
  /// The value is dropped when the job gives up: the throw happens inside this
  /// call, and the body is never reached. For an [action] that hands something
  /// over to own — a connection, a file, a subscription — pass [dispose] or
  /// [discard], and the value goes there instead. The rule is the same as in
  /// [abandonable]: a value that did not reach the body is cleaned up on the
  /// spot — and here that is awaited before the [Cancelled] is thrown, so an
  /// engine waiting for the job waits for the disposal too and the next job
  /// starts with the resource gone; a value that did reach the body goes on the
  /// cleanup stack, [dispose] to run whatever the outcome and [discard] only if
  /// the value reaches nobody. Passing both is an [ArgumentError]. Only a value
  /// is handed over: an [action] that threw has nothing to dispose of.
  ///
  /// ```dart
  /// final db = await ctx.join(
  ///   Database.open,
  ///   discard: (db) => db.close(),
  /// );
  /// ```
  ///
  /// An error from [action] is thrown as it is, cancelled or not, and the body
  /// can catch it like any other — **so await this call.** A body that walked
  /// on can end while [action] is still in flight, and the error then reaches a
  /// future nobody awaits: Dart hands that to the zone, where [abandonable]
  /// would have handed it to `onError` and on to the job's answer. The value
  /// half of the same case is taken care of — it goes quietly to [dispose] or
  /// [discard]. An error from the disposer goes to `onError` and on to the
  /// job's answer, and the [Cancelled] is thrown all the same. Throws
  /// [Cancelled] up front if the job is already cancelled or its rules no
  /// longer hold, the same as [abandonable] and [uncancellable].
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
  /// The counterpart of [abandonable], for a step that cannot be taken back: a
  /// payment on its way to the server, a write already on the wire. While
  /// [action] runs the job accepts no cancellation it may refuse, so
  /// [Job.cancel], a cancelled parent and whatever an engine of a domain adds —
  /// a queue, a closing — reach neither an [onCancel] callback nor a child, and
  /// the core waits for the body instead of interrupting it.
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
  /// cancellation covered does — see [Failed]. So does an error of [action]
  /// the body caught and throws again after a cancellation that came later,
  /// whether the section held it or not. That is said of this error alone:
  /// the body keeps it first by letting it through or throwing it again,
  /// while a new error thrown in its place, a wrapper included, comes after
  /// the cancellation and only [JobObserver.onError] hears it.
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
  /// registrations of [JobContext.onDiscard] run. A body that walked on and
  /// then gives itself up accepts a cancellation no section holds: the
  /// [onCancel] callbacks run while the section is still open, and a call of
  /// [abandonable] inside it throws.
  ///
  /// This is what separates it from [join], which accepts the cancellation as
  /// it arrives and only keeps waiting: there the job accepts it at once, and a
  /// token handed to [onCancel] stops the very call being waited for.
  ///
  /// The rules an engine of a domain adds are not covered: `solo`, for example,
  /// cancels a job whose state left its working type whatever this does, and
  /// the body learns about it at its next read as always. A cancellation the
  /// section held until then gives way: the job ends with the reason of the
  /// rule, and the held one never lands.
  ///
  /// Throws [Cancelled] if the job is already cancelled, the same as
  /// [abandonable]: a step that cannot be taken back must not begin for a job
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
  /// A body that gives itself up — throws [Cancelled], or lets out the
  /// cancellation of a child — accepts its cancellation as it throws, and
  /// these callbacks run then: what the body started is no more needed
  /// than when the job is cancelled from outside.
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
  /// The core unwinds the stack after the children and before the
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
  /// future returned here even when [Job.ignoreFailure] was called on [child]:
  /// that ignores the job's own reporting, not an error carried by this future.
  /// A failure of the child's body that a cancellation covered afterwards does
  /// not come through the future: the future throws the [Cancelled], and the
  /// child answers for the failure through [JobAnswerer.onUnanswered] of its
  /// observer, otherwise in the zone, unless [Job.ignoreFailure] was called on
  /// [child].
  ///
  /// A child is a job nobody starts by itself: [Job.deferred], or a job of
  /// an engine whose start belongs to the engine. One from `Job(body)` or
  /// [Job.then] is refused, whether or not its own start has come round
  /// yet: which of the two got there first is a matter of microtasks nobody
  /// can see in the source.
  ///
  /// Admission errors are synchronous: throws [ArgumentError] for a handle that
  /// is not a job of this core, one an engine of a domain does not own, or one
  /// that starts itself; [StateError] for a job that has already been started
  /// or has finished — one cancelled before its start included — and for a call
  /// made after this job's body has ended — from its cleanup, say — or from
  /// [unattended] work; and the parent's own [Cancelled], with the child
  /// dropped, if the parent is already cancelled.
  ///
  /// [dispose] and [discard] say how the child's value is cleaned up, and they
  /// work as they do in [abandonable]: [dispose] runs whatever the outcome,
  /// [discard] only if the value reaches nobody, and passing both is an
  /// [ArgumentError] thrown before the child starts. They are how a value that
  /// travels is registered again on arrival, and the registration is made the
  /// moment the value comes back — before the checkpoint above, because that
  /// checkpoint is what takes the value away:
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
  /// Starts every child synchronously, in the order of the list, and returns
  /// their values in that same order — not in the order they finished. The list
  /// is read once, by copy, before the first start: an `Iterable` promises
  /// neither repeatability nor stability, and the bodies start soon enough to
  /// change the list it was built from. The same handle twice is refused with
  /// an [ArgumentError] before anything starts.
  ///
  /// As soon as the body of any branch ends in anything but a value, the other
  /// branches are asked to stop with [SiblingCancelReason] — the branch the
  /// trouble came from is not, or its own error would turn into a cancellation
  /// and be lost. What comes out is decided by the final outcomes, not by that
  /// early word: a real failure if there is one, otherwise the first
  /// cancellation that arrived. The object thrown is the one the outcome
  /// carries — exactly what `await ctx.run(child)` would have thrown — so a
  /// cancellation arrives as a cancellation and there is no envelope to take
  /// apart. A failure the group received and did not throw is not lost either:
  /// it goes the way an error nobody answered for goes, once. Nor is a failure
  /// of a branch's body that a cancellation covered afterwards: the outcome
  /// carries the cancellation, and the branch answers for the failure the same
  /// way. [Job.ignoreFailure] on a branch silences both: [JobObserver.onError]
  /// hears them, and nobody answers for them.
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
  /// **The stop is cooperative.** A branch that waits through [abandonable]
  /// ends, and the operation behind it plays on and writes its result; to stop
  /// the work itself, hand the cancellation to it through [onCancel] and wait
  /// for it with [join]. A branch created with `cancellable: false` refuses the
  /// stop, and the group waits for it. The descendants of the branch that
  /// failed are not cancelled — a failure never cascades — so the group waits
  /// for them too.
  ///
  /// **No branch ends before the group has decided.** A branch stands
  /// twice: once when its body and its children are over and before it
  /// unwinds, once between
  /// the two passes of its unwinding. That is what keeps a resource a
  /// branch took for the caller — one registered through `discard` — alive
  /// until the group is sure the caller will get it, and closed by the
  /// branch itself when it will not. While a branch is held, its outcome
  /// is not final: a body that returned a value may still end [Cancelled].
  ///
  /// **A branch must not wait for another branch of the same group.** Awaiting
  /// a sibling's [Job.value] or [Job.done] hangs the group: the sibling is held
  /// until the group decides, and the group decides only once every branch is
  /// held, or once the body of one of them has ended in anything but a value.
  /// Nothing here catches that. A cancellation unties it on the same terms as
  /// the lock below: a branch awaiting the sibling through [abandonable] ends,
  /// unless it was created with `cancellable: false` or waits inside
  /// [uncancellable]; one in a bare `await` does not. For branches that depend
  /// on each other use `[a, b].wait` instead, which waits for all of them and
  /// stops none.
  ///
  /// **Nor for what another branch releases in its cleanup.** A branch starts
  /// unwinding only when every branch has ended its body and its children, or
  /// when the body of one of them has ended in anything but a value; until then
  /// its `dispose` and [onDispose] callbacks wait too. A lock the branches
  /// share, or a slot of a pool with fewer free slots than the branches that
  /// want one, taken with `dispose`, stays with the branch that got it. The
  /// branch waiting for it keeps every branch from unwinding, and the group
  /// hangs with no timer and no error until the body of another branch ends in
  /// anything but a value. A cancellation, of the parent or of a branch, unties
  /// it only by ending something a branch still waits for before it unwinds,
  /// its body or a child of it: one waiting through [abandonable], or on an
  /// operation that hears [onCancel]. It does not end one stuck in [join] on an
  /// operation deaf to it, in a bare `await`, inside [uncancellable], or in a
  /// job created with `cancellable: false`, and cancelling the branch that
  /// holds the lock does nothing: its body is over. Take such a lock in a child
  /// of the branch, which releases it when the child ends, still inside the
  /// body. If that child also opens what the branch hands out, the branch
  /// registers it on arrival, `run(child, discard: ...)`, and that `discard`
  /// runs without the lock. Or use `[a, b].wait`, under which every branch
  /// unwinds on its own.
  ///
  /// On success the group does not wait for its branches to finish: the
  /// values are handed over the moment the decision is made, and whatever
  /// a branch still has to unwind plays out under the parent, which waits
  /// for its children as always. On failure it is the other way round —
  /// every branch is stopped and waited for, so that by the time the error
  /// arrives everything the branches took is closed. If the body ended
  /// without awaiting the future, the group hands the values over without
  /// checking the parent, as [run] does.
  ///
  /// An empty group starts nothing and returns an empty list, after making
  /// the same checks [run] would make. Admission errors are those of [run].
  /// Everything that needs no adoption is asked of every handle before the
  /// first one starts, so such a refusal leaves nothing running, and under a
  /// parent that is already cancelled every branch is turned away the way
  /// [run] turns away its child, and so is the rest of the list when a branch
  /// cancels the parent before its first `await`, while the list starts. A
  /// refusal only the adoption can give — an
  /// engine of a domain turning the parent down, a rule of its domain that
  /// throws — may arrive after some branches have started: it stops them and
  /// waits for them before it comes out, and the handles after the refused
  /// one are left as they were, never started.
  Future<List<T>> runAll<T>(Iterable<Job<T>> children);

  /// Starts a child job that processes [stream] one event at a time.
  ///
  /// Returns the child immediately without observing its outcome. Await its
  /// [Job.value] to propagate its outcome into the body, or use [Job.done] to
  /// inspect the outcome. The parent waits for this child even when the body
  /// does not await it. An open stream therefore keeps the parent alive until
  /// the stream ends or the child is cancelled. Cancelling the child alone does
  /// not cancel the parent.
  ///
  /// [onData] receives the child's context. Use its checkpoints to react to the
  /// child's cancellation. An asynchronous callback is awaited before the next
  /// event is delivered. Stream and callback errors end the child and follow
  /// the usual [Job] error reporting rules.
  ///
  /// Cancellation stops delivery and cancels the subscription immediately, then
  /// waits for an active callback before finishing the child and running its
  /// cleanup. A plain future inside the callback cannot be interrupted; use the
  /// child's [abandonable] or [join] as appropriate. Do not await the child's
  /// own completion or cancellation from its callback.
  ///
  /// The future returned by the subscription's cancellation is not awaited:
  /// cleanup owned by the source is the source's to finish. If it fails, the
  /// error goes to [JobObserver.onError] of the child and to its answer, as
  /// other errors no outcome carries do. A normal stream ending still depends
  /// on the source delivering its `onDone` notification.
  ///
  /// Throws synchronously if a child cannot be started, as [run] does: a
  /// [StateError] after the parent's body ended, during cleanup and from
  /// [unattended] work, and the parent's [Cancelled] after it accepted a
  /// cancellation.
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
  /// The fourth member of the waiting family, and the one that does not wait:
  /// [abandonable] waits for the call but not the work, [join] waits for all of
  /// it, [uncancellable] waits with the cancellation held back, and this one
  /// hands the work to the core and comes back at once. Whatever [action]
  /// leaves uncaught — now, or long after the job is over — belongs to the job:
  /// its observer hears it through `onError`, and one that is a [JobAnswerer]
  /// answers for it; by default, and without such an observer, it goes to the
  /// zone the job was created in. Written any other way, such a failure belongs
  /// to nobody and lands in whatever zone it happens to fail in.
  ///
  /// ```dart
  /// ctx.unattended(() => analytics.report(event));
  /// ```
  ///
  /// The job does not wait for the work, does not cancel it and does not stop
  /// it outliving the job. The job's own cancellation is not reported when the
  /// work leaves it uncaught: a cancellation is a decision, not a failure, and
  /// whoever listens has heard it on the outcome already. That covers what
  /// comes out of [action]; a call of [abandonable] or [join] made in here
  /// keeps its own rules, and an action *it* was left holding still reports its
  /// late failure — a [Cancelled] included — the way it does anywhere else. A
  /// throw of [action] goes the same way as one from a future it started — to
  /// `onError` and on to the job's answer, never into the body: background work
  /// must not decide the outcome of the job that started it.
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
  /// [run], [runAll], `each` and [uncancellable] throw a [StateError] when
  /// called from inside [action]: they act on the whole job, and this work is
  /// not the job. A child started here, by [run], [runAll] or `each`, would
  /// hang on that boundary with the parent waiting for it forever, and a
  /// section opened here would hold back the cancellation of a body that stands
  /// in no section at all. [abandonable] and [join] are fine — they register on
  /// the job and behave. The work waits for their value, so it gets it on the
  /// body's terms even after the body has ended: on a job that has accepted a
  /// cancellation the value is released and the call throws the cancellation,
  /// and on a job that is over a value with a `dispose` or `discard` is
  /// released and the call throws a [StateError] instead of handing it over
  /// closed.
  ///
  /// **How the work stops.** Not by polling [check]: while the core
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
  /// **Unfinished work holds the job**, its outcome and the body's closure with
  /// everything it captured — and whatever an engine of a domain hangs on the
  /// job: in `solo`, for example, the controller itself, with its state and its
  /// listeners, after `close()` too. A periodic timer left running in here
  /// leaks all of that.
  ///
  /// A job created in here is not this work: it has an outcome and an observer
  /// of its own. Its unobserved failure goes to the zone this work was started
  /// from rather than to this job's observer, and a job that starts itself runs
  /// its body there. So does a job started in here by hand, wherever it was
  /// made: it starts in that zone, past any zone forked inside the work. When
  /// the work of one job runs inside the work of another, that zone is the one
  /// the outer work was started from. Quench it with [Job.ignoreFailure].
  ///
  /// Legal on a job that has already accepted a cancellation, and legal while
  /// the core unwinds the cleanup stack — a disposer starting work nobody waits
  /// for is the case this member was made for. Once the job has finished it
  /// throws a [StateError].
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
/// Subclass it to add a domain of your own — `solo`, for example, adds the
/// state and its rules. [check] is the checkpoint, and it is virtual on
/// purpose: a domain checks more than the cancellation. While the body runs,
/// [abandonable], [join], [pause] and [uncancellable] ask it before the action,
/// [join] again after it, [run] once the child's value has arrived, and
/// [runAll] before it hands the values back. An override calls `super.check()`,
/// and calls it first. That is where the cancellation of the job is asked:
/// without it [join] hands a value to a job already cancelled and
/// [uncancellable] begins its step on one. And while the core cleans up after
/// the body it throws a [StateError]: the body is gone, and no rule is asked
/// for it any more.
///
/// A rule that no longer holds throws a [Cancelled] with a reason of the
/// engine's own. The body lets it out and gives itself up, and a job whose body
/// gives itself up is cancelled the way [Job.cancel] cancels it: its children
/// stop and its [onCancel] callbacks run. The job accepts that cancellation as
/// the throw leaves the body, not before: a body that catches it and goes on
/// is not cancelled. To stop the job whatever the body does, cancel it through
/// [cancelOwnJob].
abstract class JobContextBase implements JobContext {
  final JobBase<Object?> _owner;

  /// Creates the context [owner] hands to its body.
  ///
  /// A subclass passes the job on: `MyContext(super.owner)`.
  JobContextBase(JobBase<Object?> owner) : _owner = owner;

  @override
  Job<Object?> get job => _owner;

  /// Creates the unstarted child used by [each].
  ///
  /// A domain that restricts child ownership overrides this factory to
  /// return its own job with the appropriate context and rules. The result
  /// must be accepted by [startChild]. This factory must not start the child.
  @visibleForOverriding
  Job<void> createEachJob(Future<void> Function(JobContext ctx) body) =>
      Job.deferred<void>(body, describe: () => 'each');

  @override
  Job<void> each<T>(
    Stream<T> stream,
    FutureOr<void> Function(JobContext ctx, T event) onData,
  ) {
    // Asked here, with its own verb, before `startChild` asks again with
    // one about children: the caller followed a stream, and the message
    // names what they did.
    _checkCanRun('follow a stream');
    final child = createEachJob(
      (child) => child._followStream(stream, (event) => onData(child, event)),
    );
    startChild(child);
    return child;
  }

  @override
  @mustCallSuper
  void check() {
    throwIfDisposing('check');
    throwIfCancelled();
  }

  /// The cancellation the job has accepted, or `null`.
  @protected
  Cancelled? get pendingCancel => _owner._pendingCancel;

  /// Throws the cancellation the job has accepted, or the one it ended
  /// with: a job an engine of a domain finished by hand has no
  /// [pendingCancel], and its cancellation lives in the outcome alone.
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
  /// Four members act on the whole job, [JobContext.run],
  /// [JobContext.runAll], [JobContext.each] and [JobContext.uncancellable],
  /// and unattended work is not the job: a child started there would hang
  /// on the fork's boundary with the parent waiting for it forever, and a
  /// section opened there would hold a cancellation of a body that stands
  /// in no section at all.
  /// Another job's fork is not this job's business, and the key is the
  /// job itself: forks nest, and a shared key would let the inner one
  /// pass for the outer.
  @protected
  void throwIfUnattended(String action) {
    if (identical(Zone.current[_owner], _owner)) {
      throw StateError('$_owner cannot $action inside unattended work');
    }
  }

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

  /// The parent's last word before a child starts.
  ///
  /// A non-null result finishes the child with it. `solo`, for example, checks
  /// its start rules here.
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
    final T result;
    try {
      result = await action();
    } on Object catch (error) {
      // It reaches the body in this very microtask, but the body may catch
      // it, go on and throw it again after a cancellation.
      _owner._failedUnmarked(error);
      rethrow;
    }
    if (_owner.bodyEnded && identical(Zone.current[_owner], _owner)) {
      // Called from work handed over with `unattended`, and that work is
      // waiting for the value: it is the receiver, on the body's terms. A
      // job marked cancelled -- from outside, or by a body that gave itself
      // up -- releases the value and throws the cancellation, the rules of
      // a domain aside: they speak to the body, which is gone. Otherwise
      // the value is the work's on the terms the call asked for, and on a
      // job that is over it is released and the call throws, as for a job
      // an engine finished by hand.
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
  /// It did not reach the body, so the outcome does not matter: on a job
  /// that has finished the disposer runs on the spot and nobody waits for
  /// it, and while the job is still alive the registration is
  /// unconditional and waits for the unwinding. Not sooner: the call still
  /// hands the value to whoever holds its future, and a body that walked
  /// away may have handed that future to a child, which the job waits for
  /// before the unwinding.
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
    } on Object catch (error) {
      // The step failed, and the cancellation this section was holding
      // lands on the way out -- before the error has reached the body,
      // where the core decides which of the two came first. It was the
      // failure, and said nowhere else the diagnosis of the one step that
      // cannot be rolled back is the one the cancellation swallows. After
      // a mark -- a rule of a domain makes one inside the section -- the
      // held one has nothing left to land, and the step failed after it.
      _owner._failedUnmarked(error);
      rethrow;
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
      if (_owner.bodyEnded && !identical(Zone.current[_owner], _owner)) {
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
    final fromFork = identical(Zone.current[_owner], _owner);
    late final void Function() remove;
    void onCancel() {
      if (!completer.isCompleted) {
        final cancelled = pendingCancel!;
        completer.completeError(
          cancelled,
          cancelled.stackTrace ?? StackTrace.current,
        );
        // A body that has ended walked away from this call, and a body
        // that gives itself up is told here as much as one cancelled from
        // outside. The cancellation is the job's own outcome, and its
        // copy must not reach the zone as an error of an abandoned call;
        // the error branch of `forward` does the same.
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
          // The work waits for the value, and the job is marked without
          // this race having heard it: the pass over the callbacks never
          // reached it. An engine of a domain ended the job by hand while
          // its cancellation went down to the children, and `finish`
          // dropped the callbacks; or a raw callback registered before this
          // one threw and stopped the pass. The work gets what the body
          // would: the cancellation, and the value is released.
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
          // The completer hands the error on a microtask later, and the
          // body throws it later still: a cancellation arriving in between
          // would look first.
          _owner._failedUnmarked(error);
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
          '$child',
          'children',
          'is in the group more than once',
        );
      }
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
      // Every branch turned away, not the first one alone: the rest would
      // be left `created`, and whoever awaits one of them would wait for
      // good.
      // An engine of a domain refusing the adoption is a different answer,
      // and the one `run` would give: the first such refusal comes out
      // instead of the cancellation, once the rest are turned away.
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
      throw StateError(
        child.status == JobStatus.running
            ? '$child is already running'
            : '$child has already finished',
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
    // zone.
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
