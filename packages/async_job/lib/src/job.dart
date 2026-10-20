part of 'job_base.dart';

/// A handle to a job: the outcome, the waiting and the cancellation.
///
/// Not a [Future]: a method that starts a job may be called without an
/// `await`, and the analyzer will not ask for one. Await [done] or [value]
/// where you need to, or register a cancellation listener with [whenCancelled]
/// and one for the end with [whenFinished].
///
/// A job that ends with [Failed] and is never observed hands its error to
/// [JobAnswerer.onUnanswered] of its observer, and without one that answers
/// to the zone that created the job, the way Dart reports an unhandled
/// `Future` error. Touching [done], [value] or [ignoreFailure], or forwarding a
/// failure through [then], counts as observing it; see [ignoreFailure].
abstract interface class Job<T> {
  /// Creates a job and starts it on the next microtask.
  ///
  /// Not inside the constructor: the caller puts the handle in a variable
  /// first, listens to [done] if it wants to, and may cancel before the
  /// body ever runs — a job cancelled by then ends as
  /// `Cancelled(manual)` with `started: false`, and the body is never
  /// called.
  ///
  /// A job made this way is a root and stays one: its own start is already on
  /// the way, so it is not a [ChildJob] and [JobContext.run] does not take it.
  /// A child is made with [deferred].
  ///
  /// The job ends [Failed] with an [ArgumentError] when a body of
  /// `Job<void>` returns a job of [deferred] that nobody has started: `void`
  /// lets the analyzer take the handle, and nothing here starts the job or
  /// waits for it. A body of a wider type keeps the job as its value, and
  /// any other job a body returns is not waited for: run a child with
  /// [JobContext.run].
  ///
  /// [observer] receives the hooks of this job, and a child inherits it
  /// unless given one of its own. What the body opens is released through
  /// the cleanup stack of the context — see [JobContext.onDispose] and
  /// [JobContext.onDiscard].
  ///
  /// [timeout] gives the job a deadline of its own, counted from the start of
  /// the body: the time before the start is not counted. It bounds the body and
  /// the children the job waits for after the body, and not the cleanup stack —
  /// a cancellation arriving there would turn a job that did its work into a
  /// cancelled one. When the deadline runs out first, the job is cancelled with
  /// a [TimeoutCancelReason] and ends `Cancelled(timeout)`: unlike
  /// `Future.timeout` there is no `TimeoutException`, and the request is a
  /// cancellation like that of [cancel]. The body stops at its next checkpoint,
  /// a section of [JobContext.uncancellable] holds the request until the
  /// section closes, a job cancelled already keeps its own reason, and the
  /// children hear it as the cause of their [ParentCancelReason]. If the body
  /// and its children are over while a section still holds the request, the
  /// request goes with the timer, and the job ends with what the body returned.
  /// The timer is cancelled once the body and its children are over, or
  /// whenever else the job ends, and cancelling it observes nothing: a failure
  /// goes where it would go without a deadline. A job still running when a test
  /// ends — under `fakeAsync` or in `testWidgets` — still holds that timer: end
  /// the job or wait for it.
  ///
  /// Throws [ArgumentError] when [timeout] is zero or negative, and when it
  /// comes with `cancellable: false`: the deadline is a cancellation the
  /// job may refuse, and such a job would refuse it.
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
    Duration? timeout,
    JobObserver? observer,
  }) =>
      _AutoJob<T>(
        body,
        key: key,
        describe: describe,
        cancellable: cancellable,
        timeout: timeout,
        observer: observer,
      );

  /// Creates a job that waits to be told to start.
  ///
  /// The result is a [DeferredJob], and whoever owns it starts it: by hand
  /// through [DeferredJob.start], or a parent through [JobContext.run] or
  /// [JobContext.runAll]. Cancelled before that, it ends [Cancelled] with
  /// `started: false`, and its body never runs.
  ///
  /// The named parameters are those of [Job.new]. The deadline of [timeout]
  /// is counted from the start, so the time the job waits for it is not
  /// counted; and a child with a deadline is how one step of a body gets
  /// one: `await ctx.run(Job.deferred(step, key: 'step', timeout: limit))`
  /// throws the child's `Cancelled(timeout)` into the body of the parent,
  /// which catches it or lets it out.
  static DeferredJob<T> deferred<T>(
    Future<T> Function(JobContext ctx) body, {
    Object? key,
    String Function()? describe,
    bool cancellable = true,
    Duration? timeout,
    JobObserver? observer,
  }) =>
      _DeferredJob<T>(
        body,
        key: key,
        describe: describe,
        cancellable: cancellable,
        timeout: timeout,
        observer: observer,
      );

  /// Creates a root job that follows [stream], one event at a time.
  ///
  /// The job is running when this returns, and the subscription is made
  /// inside the call: an event a broadcast stream sends right afterwards is
  /// not lost, as it would be to a job that subscribes from a body started on
  /// the next microtask. So [JobObserver.onStart] is heard before the caller
  /// has the handle, and so may [onData] be called: a source that hands an
  /// event over from inside `listen` reaches the callback before this returns.
  /// A callback that needs its own job reads [JobContext.job].
  ///
  /// [onData] receives the context of the job itself. An asynchronous callback
  /// is awaited before the next event is delivered; use the checkpoints of the
  /// context, [JobContext.abandonable] and [JobContext.join], to stop for a
  /// cancellation. The job ends [Done] when the stream ends, and an error of
  /// the stream or of the callback ends it [Failed] — and so does a callback
  /// that returns a job of [Job.deferred] nobody has started, with an
  /// [ArgumentError]: nothing here starts it. A cancellation cancels the
  /// subscription at once and waits for the callback that is running. Do not
  /// await the job's own completion or cancellation from the callback. The rest
  /// is what [JobContext.each] says of its child.
  ///
  /// The cleanup stack unwinds when the job ends, not after an event: a
  /// [JobContext.onDispose] registered for every event piles up for as long
  /// as the stream lasts, and so does a `dispose` or a `discard` of
  /// [JobContext.join]. What one event opens belongs to a child started for
  /// that event with [JobContext.run]: its stack unwinds when it ends.
  ///
  /// The named parameters are those of [Job.new] but `timeout`: a deadline on
  /// following a stream is set from outside. With `cancellable: false`
  /// there is no moment before the start to drop the job in: it refuses every
  /// cancellation from outside, and the future of [cancel] completes only
  /// when the job ends by itself — the stream ends or fails, or the callback
  /// throws, a [Cancelled] included. On a stream that never ends nothing
  /// outside the job stops it.
  ///
  /// The job is a root wherever it is made: inside the body of another job
  /// that job neither waits for it nor cancels it, and it is not a [ChildJob]
  /// that [JobContext.run] takes. A body follows a stream with
  /// [JobContext.each].
  ///
  /// ```dart
  /// final saving = Job.each<String>(messages, (ctx, message) {
  ///   return ctx.join(() => save(message));
  /// });
  /// await saving.value;
  /// ```
  static Job<void> each<E>(
    Stream<E> stream,
    FutureOr<void> Function(JobContext ctx, E event) onData, {
    Object? key,
    String Function()? describe,
    bool cancellable = true,
    JobObserver? observer,
  }) =>
      _EachJob(
        (ctx) => ctx._followStream(stream, (event) => onData(ctx, event)),
        key: key,
        describe: describe ?? () => 'each',
        cancellable: cancellable,
        observer: observer,
      )..start();

  /// Tracing of the job lifecycle for debugging; `null` by default.
  ///
  /// Every job reports here, one made by an engine included: the start, a
  /// cancellation, an error and where it went, the outcome and a value handed
  /// over.
  ///
  /// ```dart
  /// Job.debug = print;
  /// ```
  ///
  /// An engine prints its own side elsewhere — `solo`, for example, puts the
  /// queue, the state and the closing into `Solo.debug`. To follow both sides,
  /// set both.
  static void Function(String message)? debug;

  /// Says which errors an operation throws because the cancellation of its job
  /// stopped it, such as the error a migration throws once a token cancelled
  /// through [JobContext.onCancel] stops it.
  ///
  /// Asked about each failure of a job that has accepted a cancellation, when
  /// the job is about to send the failure to the answer, and only then: such an
  /// error reaches [JobObserver.onError] like any other, and nobody is asked to
  /// answer for it, neither [JobAnswerer.onUnanswered] nor the zone. A failure
  /// of a job that was not cancelled is not asked about, nor is one that
  /// [Job.ignoreFailure] has already kept out of the answer. `null`, the
  /// default, names none.
  ///
  /// ```dart
  /// Job.isCancellationError = (error) => error is DatabaseStopped;
  /// ```
  ///
  /// Called synchronously, with one failure at a time, never a [Cancelled]:
  /// keep it to a type test. Read when the answer is asked for, so a new one
  /// applies to every answer from then on. One that throws is an error of the
  /// app: its error goes to the zone the job was created in, and the failure it
  /// was asked about goes on to the answer. A [Cancelled] it throws is dropped.
  ///
  /// Set by the application, once, in `main`. A library does not set it, and
  /// `solo` does not either.
  static bool Function(Object error)? isCancellationError;

  /// Walks [error] and hands each failure in it to [onFailure] and each
  /// cancellation to [onCancelled], one at a time.
  ///
  /// An outcome keeps an error as it was thrown, and so does a `catch`. That
  /// error can be a `ParallelWaitError`: `[a, b].wait` throws one when any of
  /// its futures fails, and it holds failures and cancellations side by side,
  /// other such errors too. A check for `error is Cancelled` lets a
  /// cancellation inside it through, and a report of the whole error names
  /// none of its failures. To report each failure and drop the cancellations:
  ///
  /// ```dart
  /// if (outcome case Failed(:final error, :final stackTrace)) {
  ///   Job.visitErrors(error, stackTrace, onFailure: report);
  /// }
  /// ```
  ///
  /// The hooks of an observer need no such walk: the job walks the error this
  /// way itself. [JobObserver.onError] is told about each failure and each
  /// cancellation on its own, [JobAnswerer.onUnanswered] is asked about each
  /// failure, and that is how `Solo.unansweredHandler` in `solo` gets them.
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
  /// and for whatever an engine does with it — `solo`, for example, compares
  /// keys with `==` in its queue policies.
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
  /// Reading it marks the job observed, so nobody is asked to answer for a
  /// [Failed] outcome: the one reading has it.
  Future<Outcome<T>> get done;

  /// Completes with the returned value, or throws [Cancelled] with the
  /// cancellation stack trace, or throws the body's error.
  ///
  /// Reading it marks the job observed, so nobody is asked to answer for a
  /// [Failed] outcome. Handle the error the future carries, or it becomes an
  /// unhandled `Future` error instead.
  Future<T> get value;

  /// Creates a job that runs [onValue] after this job succeeds and cleans up.
  ///
  /// The callback receives its own [JobContext] and this job's value. It is
  /// called asynchronously, even when this job has already finished, and may
  /// return a value or a future. A failed source forwards its error and stack
  /// trace without calling [onValue]; cancellation cancels the continuation.
  ///
  /// A job is continued once. A second call throws a [StateError] before
  /// anything is made, and so does a call on a job that [shared] has
  /// continued: the count is for the whole life of the job, the way a
  /// single-subscription stream counts its one `listen`. To continue one job
  /// in several branches, give each branch a handle of [shared].
  ///
  /// Cancellation also travels backwards: cancelling the continuation asks
  /// its unfinished source to cancel, back through earlier links.
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
  /// This does not start a deferred source. The continuation starts itself when
  /// ready and is not a [ChildJob]: [JobContext.run] does not take it. It is a
  /// root job of the core, with its own optional [observer]; it inherits no
  /// observer, domain state, queue slot or rules. Awaiting it from its source's
  /// body or cleanup deadlocks, just like awaiting its own [done].
  ///
  /// Forwarding a failure observes the source and transfers responsibility
  /// to the continuation. A cancelled continuation does not observe a source
  /// failure it cannot forward; observe the source separately if needed.
  /// Returned jobs are ordinary values, not automatically awaited: start and
  /// await deferred children with `await ctx.run(child)`. Keep the original
  /// child separately when its handle is needed. A continuation of `void`
  /// fails with an [ArgumentError] when its callback returns a job of
  /// [Job.deferred] that nobody has started: nothing here starts it.
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

  /// Creates a handle that finishes with the outcome of this job and cannot
  /// reach it: one branch of a job continued in several.
  ///
  /// A job is continued once: by one [then], or by handles of this. Each call
  /// makes a new handle, independent of the others. A call on a job that
  /// [then] has continued throws a [StateError] before anything is made, and
  /// so does [then] on a job that has a handle.
  ///
  /// The handle has no body. It ends with the [Done] or [Failed] of this job,
  /// and with a [Cancelled] whose reason is a [ChainCancelReason] as soon as
  /// this job accepts a cancellation, without waiting for its cleanup. While
  /// this job refuses or holds a cancellation, the handle waits. Cancelling
  /// the handle, or a continuation after it, ends the handle at once and
  /// leaves this job alone. Nor does the handle start a job of
  /// [Job.deferred] that nobody has started.
  ///
  /// A failure the handle carries observes this job, and the handle answers
  /// for it unless somebody observes the handle. Several handles that carry
  /// one failure answer for it once. A handle cancelled before this job
  /// failed carries nothing, and this job answers for its own failure.
  ///
  /// The handle is a root job of the core with its own optional [observer],
  /// which hears [JobObserver.onFinish] and not [JobObserver.onStart]. It
  /// inherits nothing and is not a [ChildJob]: [JobContext.run] does not take
  /// it. It is continued like any job, by one [then] or by handles of its
  /// own.
  ///
  /// ```dart
  /// final text = Job<String>((ctx) async => 'hello');
  /// final length = text.shared().then<int>((ctx, text) => text.length);
  /// final loud = text.shared().then((ctx, text) => text.toUpperCase());
  /// length.cancel(); // text and loud run on
  /// print(await loud.value); // HELLO
  /// ```
  Job<T> shared({JobObserver? observer});

  /// Registers [callback] for cancellation and returns an unregister function.
  ///
  /// Calls it synchronously with the [Cancelled] carrying the reason,
  /// description, start status and stack trace. For a running job this is after
  /// cancellation has cascaded to its children and [JobContext.onCancel]
  /// callbacks have run: before the body finishes, or, for a body that cancels
  /// itself by throwing [Cancelled], as it ends. For a job cancelled before
  /// start, it is when the job is dropped.
  ///
  /// The continuation of [then] is not a child, and when it is cancelled
  /// depends on where the cancellation came from. Cancelling a source
  /// cancels its continuation before these callbacks run; a continuation
  /// that is cancelled cancels its source first. A handle of [shared]
  /// registers here when it is made, so it is cancelled in this pass, in
  /// registration order; a cancelled handle never reaches its source.
  ///
  /// If cancellation has already been accepted and its callbacks have run,
  /// calls [callback] immediately, even if the job has finished. Registering
  /// in between, while the cancellation cascades onto the children or the
  /// job's [JobContext.onCancel] callbacks run, puts the callback in that
  /// pass instead, after the ones registered before it. A refused or held
  /// cancellation does not trigger it; a held one triggers it when it is
  /// accepted. A job that ends [Done] or [Failed] without cancellation never
  /// calls it and releases its registrations on finish.
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

  /// Registers [callback] for the end of the job and returns an unregister
  /// function.
  ///
  /// Calls it synchronously with the outcome once the job has finished: after
  /// its cleanup, after the [whenCancelled] listeners of a cancelled job and
  /// [JobObserver.onFinish], and before anything waiting on [done] or [value]
  /// resumes. A job cancelled before its start calls it as it is dropped; one
  /// that never starts never calls it. An engine that ends the job by hand
  /// calls it then, ahead of any cleanup still to run.
  ///
  /// Registering does not observe the outcome: a [Failed] handed to
  /// [callback] is still answered for, unless somebody observes it — reads
  /// [done] or [value], or calls [ignoreFailure]. That is what it is for: a
  /// widget that turns a spinner off when the job ends without taking over
  /// a failure the job's owner answers for.
  ///
  /// ```dart
  /// final unregister = job.whenFinished((_) => setState(() => busy = false));
  /// // In dispose(), if the widget goes before the job does:
  /// unregister();
  /// ```
  ///
  /// Registering on a finished job calls [callback] at once, and so does
  /// registering during the pass; one made after the outcome is set but
  /// before the pass, from [JobObserver.onFinish] say, joins the pass.
  /// Otherwise the registrations, the errors of a callback and unregistering
  /// behave as they do for [whenCancelled]: each runs once, in registration
  /// order and from a snapshot, and the job releases them as it finishes.
  void Function() whenFinished(void Function(Outcome<T> outcome) callback);

  /// Cancels the job with [reason] and waits for it to actually finish.
  ///
  /// Pass a custom [CancelReason] subclass to carry data to [whenCancelled] and
  /// the [Cancelled] outcome. The accepted reason is kept by identity; another
  /// cancellation does not replace it. Nor does a later one replace a
  /// cancellation an `uncancellable` section holds, with one exception: a
  /// cancellation the job cannot refuse, such as the one an engine makes for
  /// its rules, is not held, and the job accepts it at once and drops the held
  /// one. A body that cancels itself accepts one the same way, from the moment
  /// it throws: this call then finds the job already cancelled and waits for
  /// it, exactly as a second call does.
  ///
  /// A job created with `cancellable: false` refuses this once it has started;
  /// before that there is no body to protect, and a job cancelled then is
  /// dropped like any other — unless an engine holds it before the start and
  /// refuses on its behalf, as `solo` does for a job waiting in its queue:
  /// there `cancellable: false` turns this call down already, and the job runs
  /// when its turn comes. A job inside [JobContext.uncancellable] is cancelled
  /// when that section closes. Either way the returned future waits for it to
  /// finish.
  ///
  /// Awaited from inside the body it never completes: the waiting is for the
  /// job, and the job is this body. A body cancels itself with `throw
  /// Cancelled('why')` instead.
  Future<void> cancel({CancelReason reason = const ManualCancelReason()});

  /// Tells the core that nobody is interested in this job's failure. The
  /// failure then reaches neither the zone nor [JobAnswerer.onUnanswered];
  /// [JobObserver.onError] still hears it.
  ///
  /// A job that ends with [Failed] without ever being observed hands its
  /// error to [JobAnswerer.onUnanswered] of its observer, and without one
  /// that answers to the zone that created it; call this on a fire-and-forget
  /// job whose failure is already handled elsewhere, by a [JobObserver] of
  /// your own. Like `Future.ignore`, it keeps the error from the zone, and
  /// from the answer too. Unlike it, the error is still told:
  /// [JobObserver.onError] hears it, and the outcome stays there to be
  /// read.
  ///
  /// ```dart
  /// Job<void>(
  ///   observer: reporter,
  ///   (ctx) => ctx.abandonable(device.close),
  /// ).ignoreFailure();
  /// ```
  ///
  /// Waiting for [done] or [value] observes a [Failed] too: the one waiting has
  /// the error. A failure of the body of a job that ends [Cancelled] is not in
  /// the outcome, and the one waiting gets the [Cancelled]; nor is one of a job
  /// an engine ended by hand with an outcome of its own. Such a failure is
  /// answered through [JobAnswerer.onUnanswered] of an observer that answers,
  /// otherwise in the zone, however the outcome was read, and this is what
  /// silences it. [JobObserver.onError] hears it either way. An error an
  /// operation throws because the cancellation stopped it is better named once,
  /// in [Job.isCancellationError], than silenced job by job.
  ///
  /// So it is for a child of [JobContext.run] and a branch of
  /// [JobContext.runAll] as well. A [Failed] their parent takes reaches the
  /// parent's caller whether or not this was called, and so does the failure of
  /// the body of a branch the group throws in place of a value an engine handed
  /// in once the group had heard of that failure — see [JobBase.finish]. A
  /// failure of the body of a child that ends [Cancelled], and that of a branch
  /// the group did not throw, do not reach the parent's caller, and this,
  /// called on the child, silences them. Called on their parent, it silences
  /// neither. To answer for them differently instead, give the child an
  /// observer that is a [JobAnswerer] — the parent's is the child's unless the
  /// child has one of its own.
  ///
  /// Call it before the job ends, or at the latest from [JobObserver.onFinish]
  /// or a callback of [whenCancelled] or [whenFinished] registered before it
  /// ends. A failure the
  /// outcome does not carry is answered as the job finishes, and a call from a
  /// listener of [done] comes too late for it.
  ///
  /// A job is not background work: it has an outcome and an observer of
  /// its own, and this is how it is quenched. Work with neither goes to
  /// [JobContext.unattended] instead.
  void ignoreFailure();
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

/// A job a parent may start: [JobContext.run] and [JobContext.runAll] take
/// nothing else.
///
/// [Job.deferred] makes one. An engine declares it on a job of its own that a
/// parent may run, `implements ChildJob<T>`. It adds no `start`: a parent
/// starts the job through [JobContext.run], the engine through its queue, and a
/// job that waits for a queue stays with the queue. A job that starts itself is
/// not one: neither `Job(body)` nor [Job.then] nor [Job.each] makes a child.
abstract interface class ChildJob<T> implements Job<T> {}

/// A job that starts when it is told to: by hand, through [start], or by a
/// parent, through [JobContext.run].
abstract interface class DeferredJob<T> implements ChildJob<T> {
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
