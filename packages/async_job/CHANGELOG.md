## Unreleased

### Breaking changes

- **`Job.ignore()` is renamed to `Job.ignoreFailure()`.**
- **`JobBase.whenDone` is renamed to `JobBase.untilFinished`,** so that a
  `when` member is always a listener: `whenCancelled` and the new
  `whenFinished`. A subclass of `JobBase` with a member named `untilFinished`
  renames its own.
- **`Job` gains `whenFinished`.** A class that implements `Job` itself adds it,
  and a subclass of `JobBase` with a member of that name renames its own.
- **`JobObserver.onError` is a notice, and the new `JobAnswerer` answers for an
  error no outcome carries.** An observer from `0.2.0` compiles unchanged, and
  the errors it used to swallow reach the zone; one that mixes in `JobAnswerer`
  and overrides `onUnanswered` answers for them there. See
  [Answering for errors](doc/observing.md#answering-for-errors).
- **`JobBase`, `JobContextBase` and `JobStatus` moved to
  `package:async_job/engine.dart`.** `JobBase.debug` is `Job.debug` now. See
  [Building on the core](doc/extending.md).
- **`JobContextBase.check` is marked `@mustCallSuper`.** See
  [A rule of your own](doc/extending.md#a-rule-of-your-own).
- **`JobBase.finish` and `JobContextBase.startChild` are marked
  `@mustCallSuper`, and the hooks an engine overrides are marked
  `@visibleForOverriding`:** `started`, `finished`, `adoptedBy`,
  `createContext`, `execute`, `createEachJob` and `beforeChildStart`.
- **`JobBase.cascadeToChildren` and the `JobBase.level` setter are no longer
  part of the protected surface.** Cancel a job through `cancelWith` or
  `cancelOwnJob`, and adopt a child through `startChild`.
- **The core announces a `Failed` an engine hands to `finish`.** An engine that
  called `notifyObserver` before `finish` drops that call, or the observer
  hears the error twice.
- **`ctx.run` takes `dispose` and `discard`,** the way `ctx.abandonable` does.
  See [Registering on arrival](doc/cleanup.md#registering-on-arrival).
- **`ctx.run` and `ctx.runAll` take a `ChildJob`,** the new interface of a job
  a parent may start. `Job.deferred` returns a `DeferredJob`, which is one, so
  a body that runs those compiles unchanged where the type of the handle is
  inferred. A handle declared `Job<T>` no longer compiles in `ctx.run`: the
  return type of a helper, a parameter, a variable, a `List<Job<T>>`. Declare
  it `ChildJob<T>`, or `DeferredJob<T>` where the code calls `start()`. A job
  from `Job(body)`, `then` or `Job.each`, which `ctx.run` refused with an
  `ArgumentError`, no longer compiles there. An engine whose jobs a body runs
  as children declares `implements ChildJob<T>` on them;
  `JobContextBase.startChild` still takes any `Job`. See
  [A job of your own](doc/extending.md#a-job-of-your-own).
- **`JobContext` gains `runAll`,** which runs children side by side and asks
  the rest to stop as soon as one of them goes wrong; the branches it asks to
  stop get the new `SiblingCancelReason`. An extension named `runAll` on
  `JobContext` is shadowed by it without a warning. See
  [When one failure makes the rest pointless](doc/groups.md#when-one-failure-makes-the-rest-pointless).
- **A cancellation that travels inside a `ParallelWaitError` is a cancellation
  again.** A child cancelled under `[ctx.run(a), ctx.run(b)].wait` ends the
  parent `Cancelled`, where it ended it `Failed`; an envelope that carries a
  real failure is untouched. See
  [Registered on arrival, waited for in one envelope](doc/groups.md#registered-on-arrival-waited-for-in-one-envelope).
- **A body that cancels itself is cancelled the way a cancelled job is.** When
  a body throws `Cancelled`, or lets out the cancellation of a child, the
  children are asked to stop, then the `ctx.onCancel` callbacks run and
  `whenCancelled` fires.
- **`JobBase` gains the protected `inUncancellableSection`, `heldCancel` and
  `creationZone`.**
- **`JobContext` gains `pause`,** a delay a cancellation ends. See
  [Letting time pass](doc/cancellation.md#letting-time-pass).

### Deprecated

- `ctx.wait` is deprecated in favour of `ctx.abandonable` and goes away in the
  next release.

### Changes you will see on upgrade

Errors that `0.2.0` lost, or told only to the observer, now reach the zone the
job was created in. In a test that zone is the test's, and the test fails:

- the failure of the body of a job that ends `Cancelled`: an operation that
  stops at a token the job cancels through `ctx.onCancel` throws one on every
  cancellation, and so does a body that wraps its own cancellation in an
  exception of its own;
- the failure of the body of a job that an engine ends by hand with an outcome
  of its own, earlier or later than the body throws;
- the late failure of an action under `ctx.abandonable` that the body left
  through `.timeout` or `Future.any`, arriving once the job is over;
- an error no outcome carries, of a job that has an observer;
- the failure of a source's own cleanup when `ctx.each` lets go of a stream.

`Job.isCancellationError` names the errors a cancellation causes, once, in
`main`: they reach `onError` and go no further. `job.ignoreFailure()` silences
the first two for that job alone: a child whose body failed answers for its
failure itself, whatever its parent calls. An observer that mixes in
`JobAnswerer` and overrides `onUnanswered` answers for the rest. See
[Where errors go](doc/observing.md#where-errors-go).

A job that gives up inside a call it walked away from no longer reaches
`onError` as a failure.

`ctx.check()` throws the job's `Cancelled` while the core cleans up after the
body of a cancelled job, where `0.2.0` threw a `StateError`: an action the body
walked away from that polls it to stop gets the cancellation it waits for. A
cleanup callback that calls it on a cancelled job stops there, and the
`Cancelled` reaches `onError` and no further, where `0.2.0` sent a `StateError`
on to the zone. See
[Cleanup order and late results](doc/cleanup.md#cleanup-order-and-late-results).

`onError` hears each failure and each cancellation inside a `ParallelWaitError`
in a call of its own, where `0.2.0` handed it the whole error once. See
[Answering for errors](doc/observing.md#answering-for-errors).

A child's cancellation that the body lets out names the child as the job prints
itself: `Cancelled(handler: Job(thumbnail): Cancelled(timeout))`, where `0.2.0`
printed `child thumbnail`, and `child null` for a child without a key.

`JobBase.children` is a copy taken at the call: a child that finishes later is
still in it and one adopted later is not, where the view `0.2.0` returned
followed both.

With asserts on, an `AssertionError` reaches the zone when an engine ends two
children of one job with one `Cancelled` instance. See
[Not waiting for the checkpoint](doc/extending.md#not-waiting-for-the-checkpoint).

A `Job<void>` whose body returns a job of `Job.deferred` that nobody has
started, and a `then<void>` continuation whose callback does the same, end
`Failed` with an `ArgumentError`, where `0.2.0` ended them `Done`. See
[Chains](doc/chains.md).

Several error messages are reworded: a test that matches them by text needs the
new wording.

### Added

- **`started` of `Cancelled.by` is optional and defaults to `true`.**
- **`Job.whenFinished` hears the end of a job without observing its outcome.**
  A screen that redraws when the job is over no longer takes over a failure the
  job's owner is responsible for, as waiting for `done` does. See
  [Hearing the end without the failure](doc/outcomes.md#hearing-the-end-without-the-failure).
- **`timeout` gives a job a deadline of its own.** `Job(...)`,
  `Job.deferred(...)` and the constructor of `JobBase` take it; when it runs
  out, the job ends `Cancelled(timeout)` with the new `TimeoutCancelReason`.
  See [A deadline](doc/cancellation.md#a-deadline).
- **`Job.each` makes a root job that follows a stream.** See
  [A job that only follows a stream](doc/streams.md#a-job-that-only-follows-a-stream).
- **`JobObserver.all` makes one observer of several.** See
  [Several observers](doc/observing.md#several-observers).
- **`JobObserver` is an `abstract mixin class`,** where `0.2.0` declared an
  `abstract class`: an observer that already extends another class mixes
  `JobObserver` in: `with JobObserver`. See
  [Observer](doc/observing.md#observer).
- **`Job.isCancellationError` names the errors a cancellation causes.** Set
  once, in `main`, it keeps them out of the answer: `onError` hears them, and
  nobody is asked to answer for them. A stop at a token is named by its type,
  `(error) => error is DatabaseStopped`, and a wrapper of the job's own
  cancellation by its cause,
  `(error) => error is AppException && error.cause is Cancelled`. See
  [Errors of a cancellation](doc/observing.md#errors-of-a-cancellation).
- **`Job.visitErrors` hands each failure and each cancellation inside an error
  to a callback of its own.** See
  [Answering for errors](doc/observing.md#answering-for-errors).
- The debug channel names a job that handed its value over and dropped the
  conditional registrations that went with it. See
  [Registering on arrival](doc/cleanup.md#registering-on-arrival).

### Fixed

- A `ParallelWaitError` whose list of errors throws when its length is read is
  a failure like any other; a job whose body threw it never finished.
- A `whenCancelled` registered from `onFinish` of a job cancelled before its
  start runs; it was dropped.
- A job made by `Job(...)` inside work handed to `ctx.unattended`, or started
  there, runs in the zone the work was started from: in the zone of the work, a
  bare `unawaited` error in it reached the observer of the job that started the
  work.
- A `Cancelled` a hook of the observer throws no longer reaches the zone.
- A job an engine ends while `createContext` builds its context keeps that
  outcome; its body ran anyway, and the job ended twice.
- `ctx.run`, `ctx.runAll` and `ctx.each` refuse, with an `ArgumentError` as
  they promise, a class that implements `JobBase` instead of extending it. It
  threw `NoSuchMethodError`.
- A value that comes to a call of `ctx.abandonable` the cancellation has
  already ended is released as soon as it arrives; held until the children had
  ended, it left a child waiting for the same lock for good.
- An error thrown by `JobBase.started` goes to `onError` and `onUnanswered`,
  and the body runs. It left the job running with no body, forever.
- A child leaves its parent's waiting list by identity: with children equal by
  `==`, the parent finished while one of them still ran.
- A child leaves its parent's waiting list without a search of it: a parent of
  thousands of children took time quadratic in their number.
- Two jobs equal by `==` are no longer taken for one another inside work handed
  to `ctx.unattended`.
- A body that cancels itself with `throw Cancelled(...)` has accepted that
  cancellation there and then: until the job had waited for its children,
  `isCancelled` answered `false`, and a `cancel()` put its own reason over the
  one the body chose.
- A `whenCancelled` registered while the cancellation is still reaching the
  children runs after the ones registered earlier, instead of ahead of them.
- A finished job lets go of its body and of its parent: a kept handle held
  everything the body captured.
- A job made inside work handed to `ctx.unattended` lets go of the job that
  started the work: a kept handle held that job, and everything it held,
  through the zone of the work. A job made there under a zone with a microtask
  queue of its own, such as that of `fakeAsync`, no longer leaves its outcome
  waiting in that queue for good.
- `JobContextBase.startChild` refuses a continuation, the job `then` returns,
  with the same `ArgumentError` whenever it is called; once the source had
  finished it threw a `StateError`.
- `ctx.join` releases the value through `dispose` or `discard` when the
  checkpoint after the action throws anything, not only a `Cancelled`.
- `ctx.join` and `ctx.abandonable` called from work handed to `ctx.unattended`
  no longer hand that work a resource they have already closed.
- A value that comes back after the body has ended no longer completes the same
  wait twice: a cancellation arriving at that moment made the core throw
  `Future already completed`.
- A job that has accepted a cancellation no longer ends with a value: a `Done`
  or `Failed` an engine hands to `finish` after that ends it `Cancelled`.
- A value arriving for a job an engine ended by hand is released instead of
  leaking, and the body hears why: a `StateError` about the job, or the
  cancellation the job was ended with.
- A cancellation that runs out of stack in a deep tree runs the `onCancel`
  callbacks of the jobs it reached as it unwinds; it used to run none of them.
- A call of `ctx.abandonable` the body did not await no longer sends the job's
  cancellation to the zone when the job accepts it after the body has ended.
- A tree of jobs that runs out of stack while it is being built ends with the
  `StackOverflowError`; its root could be left running for good, with nothing
  reported.
- A key whose `toString` throws, or a `describe` that throws, is printed as a
  mark in the job's string representation; its error took the place of the
  core's error message that named the job.
- Thousands of jobs that wake up together, such as children waiting on one
  future, no longer cost about two milliseconds each under JIT (`dart test`,
  `dart run`, a debug build): the VM compiled the routine of a job again for
  every one of them.
- On a running job, a cancellation made from `Job.debug` on the line about
  another cancellation of the same job comes too late, as any later
  cancellation does; the `whenCancelled` callbacks used to hear its reason
  while the outcome carried the other one. Inside `ctx.uncancellable` it no
  longer takes the place of the cancellation the section holds back.
- A continuation `then` attached to a job whose failure has already reached the
  zone no longer sends it to the zone a second time.
- A job that an engine ends by hand while it runs lets go of the cleanups it
  never ran: a kept handle held everything they captured.

### Documentation

- The README is a starting page, and the reference moved to ten pages:
  [Outcomes](doc/outcomes.md), [Cancellation](doc/cancellation.md),
  [Children](doc/children.md), [Groups](doc/groups.md),
  [Chains](doc/chains.md), [Streams](doc/streams.md),
  [Cleanup](doc/cleanup.md), [Observing](doc/observing.md),
  [Testing](doc/testing.md) and [Building on the core](doc/extending.md).
- One recommendation of the `0.2.0` README is replaced:
  `on Cancelled { rethrow; }` in front of the `catch` logs an operation stopped
  by its token as a failure.
  [Asking the job](doc/cancellation.md#asking-the-job) calls `ctx.check()` in
  the `catch` instead and names its price: a real failure that comes after the
  cancellation is lost, unless the `catch` rethrows on a cancelled job.

## 0.2.0

- **Breaking:** `ctx.run(child)` returns `Future<T>` instead of the child's
  handle. Use `await ctx.run(child)` to await its value, children and cleanup;
  successful completion checks the parent's cancellation before continuing.
  Keep the original `child` for cancellation or outcome inspection. Handle the
  returned future's errors, or use `.ignore()` for an intentional concurrent
  start whose result is unused. Start validation still throws synchronously.
  `ctx.each` continues to return its child handle immediately.
- Add protected `JobContextBase.startChild` for domain adoption and start
  checks shared by `run` and `each`, without observing the child's result.

- Add `Job.then` with a separate context per continuation, forward outcome
  propagation and cancellation in both directions. Cancelling the tail waits
  for unfinished predecessors and their cleanup. `ChainCancelReason` retains
  each adjacent cancellation in `cause`. Continuations are core root jobs with
  their own optional observer, independent of domain queues.

- **Breaking:** `ctx.each(stream, (child, event) { ... })` returns a child
  `Job<void>` immediately. Await `.value` for a throwing result, inspect
  `.done` for the outcome, or call `.cancel()` to stop it separately. The
  callback receives the child's context. The parent waits for the child even
  when its body does not await it, and observers see the child.
- Cancelling `each` immediately removes the subscription and stops event
  delivery, then waits for the running callback before child completion and
  cleanup. Use child context checkpoints to respond to cancellation; a plain
  `await` cannot be interrupted. Source cleanup from subscription cancellation
  is still not awaited.
- **Breaking:** `each` is a `JobContext` method; the `JobStream` extension is
  removed. `JobContextBase.createEachJob` is a protected factory for domain
  engines. As with `run`, `each` is rejected from `unattended` and after the
  parent body ends.
- **Breaking:** reasons are extensible classes: `ManualCancelReason`,
  `ParentCancelReason` and `HandlerCancelReason`. Replace named constants with
  constructors and inspect types instead of comparing names. `CancelReason` is
  abstract; subclasses can carry arbitrary data.
- `job.cancel(reason: reason)` accepts a custom reason, preserved by identity
  in callbacks and outcomes. A body throwing `Cancelled.by` now preserves its
  explicit reason as well.
- Parent cancellation and a child's cancellation escaping the body retain the
  source `Cancelled` in `ParentCancelReason.cause` and
  `HandlerCancelReason.cause` respectively.
- **Breaking:** replace the `Job.whenCancelled` future with
  `job.whenCancelled((cancelled) { ... })`. The callback receives the full
  `Cancelled` and runs synchronously; registering after cancellation calls it
  immediately. The returned function unregisters the callback.
- Release unused cancellation listeners when a job finishes without
  cancellation. Registration does not observe a failed outcome.
- Route synchronous listener errors through `onError`, or the creation zone
  without an observer, as for `ctx.onCancel`. Async callbacks are not awaited.

## 0.1.0

Initial release. The job kernel taken out of `solo` before its own first
release.

- `Job<T>`: a cancellable `Future` with an outcome, children and a cooperative
  cancellation. Created by `Job(body)`, which starts on the next microtask, or
  by `Job.deferred(body)`, which waits for `start()`.
- `Outcome<T>`: `Done`, `Failed`, `Cancelled` with an open `CancelReason` and a
  public `Cancelled.by` for engines built on this one.
- A waiting family that says what a cancellation does to a call: `ctx.wait`
  ends the waiting and not the work, `ctx.join` waits for all of the action and
  gives up afterwards, `ctx.uncancellable` holds the cancellation until the
  step is over, `ctx.unattended` does not wait at all and hands the work to the
  engine, `ctx.onCancel` hands the cancellation to whatever can really stop,
  and `ctx.check` gives up where there is no call to wrap. `ctx.each` follows a
  stream for as long as the job lives, waiting for an asynchronous `onData` and
  taking the subscription with it whatever the outcome.
- A cleanup stack: `ctx.onDispose` releases whatever the outcome,
  `ctx.onDiscard` only when the value reaches nobody, and `wait` and `join`
  take the same two as `dispose` and `discard` for the value they hand over.
  The engine unwinds the stack after the children and before the outcome,
  waiting for every disposer; `ctx.disown(value)` takes a registration back
  when the body hands the value over itself.
- Children through `ctx.run`: the parent finishes after them, a cancellation
  cascades, and a child that is not cancellable refuses it.
- `JobObserver` with `onStart`, `onFinish`, `onError` and `onLog`; a child
  inherits the parent's. A `Failed` outcome nobody observed goes to the zone
  that created the job, and so does an error with nowhere else to go when there
  is no observer — but never a `Cancelled`: a cancellation is a decision
  somebody made, not a failure, and the observer is the only place it is heard.
- `ctx.unattended(action)` for work the body starts and does not wait for: it
  runs in an error zone of its own, and whatever it leaves uncaught — now, or
  long after the job is over — reaches `onError` instead of the process.
  `ctx.run` and `ctx.uncancellable` are refused from inside it, and a job
  created in there reports to the zone the body runs in, not to the observer of
  the job that started the work.
- `JobBase<T>` and `JobContextBase` for an engine of a domain to subclass: the
  protected surface, the virtual checkpoint `check()`, and the hooks
  `started()`, `finished()` and `adoptedBy()`. The protected surface also
  carries `reportToZone`, for a domain whose own route for an error with
  nowhere to go ends with nobody — it keeps a `Cancelled` out of the zone
  exactly as the core does, so a domain does not write that rule again — and
  `throwIfUnattended`, for a member of its context that must not be called from
  unattended work.
