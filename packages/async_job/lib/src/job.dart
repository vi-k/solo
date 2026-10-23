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
/// `Future` error. Touching [done], [value] or [ignoreFailure], or carrying a
/// failure on through [then] or a handle of [shared], counts as observing it;
/// see [ignoreFailure].
abstract interface class Job<T> {
  /// Creates a job and starts it on the next microtask.
  ///
  /// Not inside the constructor: the caller may listen to [done] or cancel
  /// first, and a job cancelled by then ends `Cancelled(manual)` with
  /// `started: false`, its body never called. The job is a root, so
  /// [JobContext.run] does not take it: a child is made with [deferred]. A job
  /// a body returns is not waited for: a body of `Job<void>` that returns a
  /// job of [deferred] nobody has started ends the job [Failed] with an
  /// [ArgumentError], and a body of a wider type keeps such a job as its value.
  ///
  /// [observer] receives the hooks of this job, and a child inherits it unless
  /// given one of its own. [timeout] is a deadline counted from the start of
  /// the body: when it runs out first, the job ends `Cancelled(timeout)`.
  /// Throws [ArgumentError] when [timeout] is zero or negative, or comes with
  /// `cancellable: false`.
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
  ///
  /// See [A deadline of the job](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/time.md#a-deadline-of-the-job)
  /// on the time page for what the deadline bounds.
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
  /// The job is running when this returns: it subscribes inside the call, so
  /// [JobObserver.onStart] and even [onData] may be called before the caller
  /// has the handle. [onData] receives the context of the job itself, and an
  /// asynchronous callback is awaited before the next event is delivered. The
  /// job ends [Done] when the stream ends, and [Failed] on an error of the
  /// stream or of the callback. A cancellation cancels the subscription at
  /// once and waits for the callback that is running, so the callback must not
  /// await the job's own completion or cancellation. The rest is what
  /// [JobContext.each] says of its child.
  ///
  /// The named parameters are those of [Job.new] but `timeout`: a deadline on
  /// following a stream is set from outside. With `cancellable: false` the
  /// future of [cancel] completes only when the job ends by itself; do not
  /// await it on a stream that may never end.
  ///
  /// ```dart
  /// final saving = Job.each<String>(messages, (ctx, message) {
  ///   return ctx.join(() => save(message));
  /// });
  /// await saving.value;
  /// ```
  ///
  /// See [A job that only follows a stream](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/streams.md#a-job-that-only-follows-a-stream)
  /// on the streams page.
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
  /// An outcome and a `catch` keep an error as it was thrown, and that can be
  /// a `ParallelWaitError` of `[a, b].wait`, holding failures and cancellations
  /// side by side: a check for `error is Cancelled` lets a cancellation inside
  /// it through. The hooks of an observer need no such walk: the job walks the
  /// error this way itself. A callback that throws ends the walk, and the error
  /// reaches the caller; when the caller is a hook of an observer, the job
  /// catches it and the zone gets it, except a [Cancelled], which is dropped.
  ///
  /// ```dart
  /// if (outcome case Failed(:final error, :final stackTrace)) {
  ///   Job.visitErrors(error, stackTrace, onFailure: report);
  /// }
  /// ```
  ///
  /// Nothing is lost: what the walk cannot read goes to [onFailure] whole, with
  /// the stack trace of the error around it — a `ParallelWaitError` of a record
  /// longer than nine or of a shape it does not know, one whose list throws
  /// when read, one already being walked further up, and a branch that is not
  /// an [AsyncError]. The readable branches of a partly readable list are
  /// walked all the same. Each `ParallelWaitError` is walked at most once, by
  /// identity.
  ///
  /// See [Several failures in one error](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/error-rules.md#several-failures-in-one-error)
  /// on the error rules page for the order of the walk.
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
  /// [Failed] outcome: the one reading has it. Any read counts, a `print` or
  /// a debugger's watch on the getter as well.
  Future<Outcome<T>> get done;

  /// Completes with the returned value, or throws [Cancelled] with the
  /// cancellation stack trace, or throws the body's error.
  ///
  /// Reading it marks the job observed, so nobody is asked to answer for a
  /// [Failed] outcome; any read counts, a `print` or a debugger's watch on
  /// the getter as well. Handle the error the future carries, or it becomes
  /// an unhandled `Future` error instead.
  Future<T> get value;

  /// Creates a job that runs [onValue] after this job succeeds and cleans up.
  ///
  /// The callback receives its own [JobContext] and this job's value, is
  /// called asynchronously even when this job has already finished, and may
  /// return a value or a future. A failed source forwards its error and stack
  /// trace without calling [onValue], and the continuation answers for the
  /// failure from then on. **A job is continued once:** a second call throws a
  /// [StateError] before anything is made, and so does a call on a job that
  /// [shared] has continued; give each branch a handle of [shared]. An engine
  /// that hands one job to several callers may refuse this call from the first
  /// one on.
  ///
  /// The continuation is a root job of the core with its own optional
  /// [observer], not a [ChildJob], and awaiting it from its source's body or
  /// cleanup deadlocks. [key] and [describe] name it as they name any job, see
  /// [A job's name](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/observing.md#a-jobs-name);
  /// without [describe] its description is `then`.
  ///
  /// ```dart
  /// final length = Job<String>((ctx) async => 'hello')
  ///     .then<int>((ctx, text) => text.length);
  /// print(await length.value); // 5
  /// ```
  ///
  /// See [Chains](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/chains.md)
  /// for cancelling a chain, a link that fails and what the callback returns.
  Job<R> then<R>(
    FutureOr<R> Function(JobContext ctx, T value) onValue, {
    Object? key,
    String Function()? describe,
    JobObserver? observer,
  });

  /// Creates a handle that finishes with the outcome of this job and cannot
  /// reach it: one branch of a job continued in several.
  ///
  /// A job is continued once, by one [then] or by handles of this: a call on a
  /// job that [then] has continued throws a [StateError] before anything is
  /// made. Each handle is cancelled independently of the others and carries
  /// the same value, so a resource it holds is closed by code that waits for
  /// every branch, not by each branch.
  ///
  /// The handle has no body: it ends with the [Done] or [Failed] of this job,
  /// or [Cancelled] with a [ChainCancelReason] as soon as this job accepts a
  /// cancellation, and waits while this job refuses or holds one. It does not
  /// start a job of [Job.deferred]. On a job that has finished or accepted a
  /// cancellation already it ends on the next microtask, not inside the call.
  ///
  /// The handle is a root job that inherits nothing, with its own optional
  /// [observer], which hears [JobObserver.onFinish] and not
  /// [JobObserver.onStart]. Without [describe] its description is `shared`.
  ///
  /// ```dart
  /// final text = Job<String>((ctx) async => 'hello');
  /// final length = text.shared().then<int>((ctx, text) => text.length);
  /// final loud = text.shared().then((ctx, text) => text.toUpperCase());
  /// length.cancel(); // text and loud run on
  /// print(await loud.value); // HELLO
  /// ```
  ///
  /// See [A handle for each branch](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/chains.md#a-handle-for-each-branch)
  /// on the chains page, and [A job's name](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/observing.md#a-jobs-name)
  /// on the observing page for [key] and [describe].
  Job<T> shared({
    Object? key,
    String Function()? describe,
    JobObserver? observer,
  });

  /// Registers [callback] for cancellation and returns an unregister function.
  ///
  /// Calls it once, synchronously, with the [Cancelled] when the job accepts a
  /// cancellation, without waiting for the body; a refused cancellation does
  /// not call it, and a job that ends [Done] or [Failed] releases it uncalled.
  /// Registering does not observe a [Failed] outcome. The callback is
  /// synchronous: its error goes to [JobObserver.onError] and on to the
  /// answer, and the future of an `async` one is not awaited, nor are its
  /// errors caught here.
  ///
  /// ```dart
  /// final unregister = job.whenCancelled((cancelled) {
  ///   print(cancelled.reason);
  /// });
  /// // When the listener is no longer needed:
  /// unregister();
  /// ```
  ///
  /// See [Listening for the cancellation](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/outcomes.md#listening-for-the-cancellation)
  /// on the outcomes page for when the callback runs and where its errors go.
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

  /// Tells the core that nobody is interested in this job's failure.
  ///
  /// The failure then reaches neither the zone nor [JobAnswerer.onUnanswered];
  /// [JobObserver.onError] still hears it, and the outcome stays there to be
  /// read. Call it on a fire-and-forget job whose failure is already handled
  /// elsewhere; code that waits for [done] or [value] observes the failure
  /// itself and needs no call. It silences this job alone, not its children.
  /// Waiting does not observe the failure of the body of a job that ends
  /// [Cancelled]: the outcome does not carry it, and this call silences it
  /// only when made before the job ends, or at the latest from
  /// [JobObserver.onFinish] or a callback of [whenCancelled] or [whenFinished]
  /// registered before it ends.
  ///
  /// ```dart
  /// Job<void>(
  ///   observer: reporter,
  ///   (ctx) => ctx.abandonable(device.close),
  /// ).ignoreFailure();
  /// ```
  ///
  /// See [Telling the core it is handled](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/outcomes.md#telling-the-core-it-is-handled)
  /// on the outcomes page.
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
  /// Runs the body, in the zone this is called from.
  ///
  /// Called inside the work of [JobContext.unattended], the job starts in the
  /// zone that work was started from, past any zone forked inside the work, as
  /// a job made in there does.
  ///
  /// Throws [StateError] if the job already ran, and also if it was
  /// cancelled before it started: a job dropped then is finished, and a
  /// finished job does not run.
  ///
  /// See [Deferred start](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/extending.md#deferred-start)
  /// on the extending page.
  void start();
}
