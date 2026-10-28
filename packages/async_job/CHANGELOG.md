## 0.6.0

### Breaking changes

- **Dart 3.10.0 is the lowest SDK the package supports, up from 3.6.0.**

## 0.5.0

### Breaking changes

- **`JobContext` gains `child`, and `JobContextBase` implements it.** A class
  that implements `JobContext` itself adds it, a subclass of `JobContextBase`
  with a member of that name renames it or makes it an override, and an
  extension on `JobContext` with a member named `child` is shadowed without a
  warning. An engine that makes children of its own, in `createEachJob` or
  elsewhere, or keeps rules in `check()`, overrides `child` with `@useResult`:
  the default is a `Job.deferred`, which such an engine refuses or which does
  not ask its rules.

### Added

- **`ctx.child(body, key:, describe:, timeout:)` makes an unstarted child that
  the engine of the job accepts,** for code that holds the context and does not
  know the engine. In `JobContextBase` it is a `Job.deferred`. An engine whose
  children are jobs of its own overrides it, and `ctx.each` takes its child
  from there. `ctx.child` starts and checks nothing: `ctx.run`, `ctx.start` and
  `ctx.runAll` do the refusing. See
  [Running a child](doc/children.md#running-a-child); the step of
  [A deadline for one step](doc/time.md#a-deadline-for-one-step) is made this
  way.

### Documentation

- [Time moved by the test](doc/testing.md#time-moved-by-the-test) says how to
  test a job that does real input and output: fake the timers alone.
- [Work in an isolate](doc/cancellation.md#work-in-an-isolate) shows how to run
  work in an isolate that the job's cancellation kills in the middle of a step.

## 0.4.0

### Breaking changes

- **`JobObserver.onError` takes `{required JobErrorAnswer answer}`: what the
  job does about the error.** `answered`: it asks for an answer, through
  `JobAnswerer.onUnanswered` or the zone. `cancellation`: it never does,
  because the error is a cancellation. `never`: it never does for another
  reason, such as `ignoreFailure()`. `later`: the outcome that carries the
  error may still be read, and nothing is promised. For an error no outcome
  carries, and for the failure of the body of a job that has accepted a
  cancellation by the time the body throws, `Job.isCancellationError` is now
  asked before `onError`, not after it: an `onError` that cancels its own job
  no longer sends that error under the filter, a filter set once `onError` has
  heard the failure is not asked about it, and the error of a filter that
  throws reaches the zone before `onError` hears the error the filter was asked
  about. The core no longer announces through the `@protected`
  `notifyObserver`: an override of it hears only what the engine itself sends,
  and `onError` is told `later` about each of those, even after
  `ignoreFailure()`. See
  [Where each error goes](doc/error-rules.md#where-each-error-goes).

### Documentation

- The queue and the rule left [Building on the core](doc/extending.md) for a
  page of their own, [An engine of your own](doc/engine.md).
- A resource handed to another job, cleanup without a call and the order of
  cleanup left [Cleanup](doc/cleanup.md) for
  [Cleanup rules](doc/cleanup-rules.md).
- The way of each kind of error, the debug channel, an error that holds several
  failures and the rare cases left [Errors](doc/errors.md) for
  [Error rules](doc/error-rules.md).

## 0.3.0

### Breaking changes

What to write instead, with the `0.2.0` name on the left; each has its entry
below.

| `0.2.0` | `0.3.0` |
|---|---|
| `Job.ignore()` | `Job.ignoreFailure()` |
| `JobBase.whenDone` | `JobBase.untilFinished` |
| `JobBase.debug` | `Job.debug` |
| `JobBase`, `JobContextBase`, `JobStatus` from `package:async_job/async_job.dart` | from `package:async_job/engine.dart` |
| `Job<T>` handed to `ctx.run` | `ChildJob<T>`, or `DeferredJob<T>` for `start()` |
| `ctx.wait` | `ctx.abandonable` |

- **`JobObserver.onError` is a notice, and the new `JobAnswerer` answers for an
  error nobody else has: one no outcome carries, and a `Failed` nobody
  observes.** An observer from `0.2.0` compiles unchanged, and the errors it
  used to swallow reach the zone; see
  [Answering for errors](doc/errors.md#answering-for-errors).
- **`Job.ignore()` is renamed to `Job.ignoreFailure()`, and `JobBase.whenDone`
  to `JobBase.untilFinished`.**
- **A job is continued once: by one `then`, or by handles of the new
  `Job.shared`.** A second `then`, a `then` on a job with a handle and `shared`
  on a job with a `then` throw a `StateError`: give each branch a handle of
  `shared()`, see
  [A handle for each branch](doc/chains.md#a-handle-for-each-branch).
- **`ctx.run` takes a `ChildJob`.** A handle declared `Job<T>` no longer
  compiles there: declare it `ChildJob<T>`, or `DeferredJob<T>` where the code
  calls `start()`, and give the jobs of an engine `implements ChildJob<T>`.
- **A class that implements `Job` or `JobContext` itself adds the new members,
  and a subclass of `JobBase` renames its own member whose name a new one now
  takes.** `Job` gains `whenFinished` and `shared`, `JobBase` gains
  `untilFinished`, and `JobContext` gains `abandonable`, `heldCancellation`,
  `pause`, `runAll`, `start` and the `dispose` and `discard` of `run`; `then`,
  `shared` and `each` take `key` and `describe`, in an override too; an
  extension on `Job` or `JobContext` with the name of a new member is shadowed
  without a warning.
- **`JobBase`, `JobContextBase` and `JobStatus` moved to
  `package:async_job/engine.dart`, and `JobBase.debug` is `Job.debug`.** See
  [Building on the core](doc/extending.md).
- **The protected surface of an engine changed.** `JobContextBase.check`,
  `JobBase.finish` and `JobContextBase.startChild` are `@mustCallSuper`;
  `started`, `finished`, `adoptedBy`, `createContext`, `execute`,
  `createEachJob` and `beforeChildStart` are `@visibleForOverriding`;
  `cascadeToChildren` and the `level` setter are gone in favour of
  `cancelWith`, `cancelOwnJob` and `startChild`; `inUncancellableSection`,
  `heldCancel`, `creationZone` and `requireShared` are new; `createEachJob`
  takes the `key` and `describe` of `ctx.each`, and an override hands them to
  the job it makes.
- **The core announces a `Failed` an engine hands to `finish`:** an engine that
  called `notifyObserver` before `finish` drops that call, or the observer
  hears the error twice.
- **A cancellation inside a `ParallelWaitError` is a cancellation again:** a
  child cancelled under `[ctx.run(a), ctx.run(b)].wait` ends the parent
  `Cancelled`, where it ended it `Failed`.
- **A body that cancels itself is cancelled the way a cancelled job is:** its
  children are asked to stop, then its `ctx.onCancel` callbacks run and
  `whenCancelled` fires.

### Deprecated

- `ctx.wait` is deprecated in favour of `ctx.abandonable` and goes away in the
  next release.

### Changes you will see on upgrade

Errors that `0.2.0` lost, or told only to the observer, now reach the zone the
job was created in, and a test fails on them:

- the failure of the body of a job that ends `Cancelled`, such as an operation
  stopping at a token the job cancels;
- the failure of the body of a job an engine ends by hand;
- the late failure of an action the body left under `ctx.abandonable` through
  `.timeout` or `Future.any`;
- an error no outcome carries, of a job that has an observer;
- the failure of a source's own cleanup when `ctx.each` lets go of a stream.

`Job.isCancellationError`, set once in `main`, stops the errors a cancellation
causes at `onError`, `job.ignoreFailure()` silences the first two for one job,
and an observer that mixes in `JobAnswerer` answers for the rest; see
[Where errors go](doc/errors.md#where-errors-go).

A job that gives up inside a call it walked away from no longer reaches
`onError` as a failure.

`ctx.check()` throws the job's `Cancelled` in the cleanup of a cancelled job,
where `0.2.0` threw a `StateError`.

`onError` hears each failure and each cancellation inside a `ParallelWaitError`
in a call of its own, and the zone gets each failure of one nobody observes on
its own, where `0.2.0` passed on the whole error once.

A child's cancellation that the body lets out prints as
`Cancelled(handler: Job(thumbnail): Cancelled(timeout))`, where `0.2.0` printed
`child thumbnail`.

`JobBase.children` is a copy taken at the call, where `0.2.0` returned a live
view.

With asserts on, an `AssertionError` reaches the zone when an engine ends two
children of one job with one `Cancelled` instance.

A `Job<void>` or a `then<void>` continuation whose body or callback returns a
job of `Job.deferred` nobody has started, and a child of `ctx.each` whose
callback does it for an event, end `Failed` with an `ArgumentError`, where
`0.2.0` ended them `Done`.

Several error messages are reworded: a test that matches them by text needs the
new wording.

### Added

- **`ctx.start` starts a child the body does not wait for;** its outcome stays
  with whoever holds the child and leaves the parent's alone.
- **`ctx.runAll` runs children side by side and asks the rest to stop as soon
  as one of them goes wrong,** with the new `SiblingCancelReason`. See
  [When one failure makes the rest pointless](doc/groups.md#when-one-failure-makes-the-rest-pointless).
- **`ctx.pause` is a delay a cancellation ends.**
- **`ctx.heldCancellation` names the cancellation an `uncancellable` section
  holds back** at the moment it is read. See
  [Holding the cancellation back](doc/cancellation.md#holding-the-cancellation-back).
- **`ctx.run` takes `dispose` and `discard`,** as `ctx.abandonable` does.
- **`Job.whenFinished` hears the end of a job without observing its outcome.**
- **`timeout` gives a job a deadline of its own,** after which it ends
  `Cancelled(timeout)` with the new `TimeoutCancelReason`.
- **`Job.each` makes a root job that follows a stream.**
- **`then`, `shared` and `ctx.each` take `key` and `describe`** and name the
  job they make as any job is named; without a `describe` it is described
  `then`, `shared` or `each`. See [A job's name](doc/observing.md#a-jobs-name).
- **`JobObserver.all` makes one observer of several.**
- **`JobObserver` is an `abstract mixin class`,** so that an observer that
  extends another class mixes it in.
- **`Job.isCancellationError` names the errors a cancellation causes:**
  `onError` hears them, and nobody is asked to answer for them. See
  [Errors of a cancellation](doc/errors.md#errors-of-a-cancellation).
- **`Job.visitErrors` hands each failure and each cancellation inside an error
  to a callback of its own.**
- **`started` of `Cancelled.by` is optional and defaults to `true`.**
- The debug channel names a job that dropped the conditional registrations of a
  value it handed over, and a job that ended `Done` without handing over such a
  value: unless the value is inside the result, nothing will dispose of it.

### Fixed

- `ctx.run` and `ctx.each` refuse a class that implements `JobBase` instead of
  extending it with the `ArgumentError` they promise, not a
  `NoSuchMethodError`.
- A value that comes to a call of `ctx.abandonable` the cancellation has
  already ended is released at once; held until the children had ended, it left
  a child waiting for the same lock for good.
- An error thrown by `JobBase.started` goes to `onError`, and the body runs;
  the job was left running with no body, forever.
- Jobs equal by `==` are no longer taken for one another: a parent of two such
  children finished while one of them still ran.
- A key or a `describe` that throws prints as a mark in the job's name instead
  of replacing the core's error message.
- A child, a cancel callback or a listener leaves its list without a search:
  thousands of them in one job took time quadratic in their number.
- A body that throws `Cancelled` accepts that cancellation at once: until the
  children were done, `isCancelled` answered `false`, and a `cancel()` put its
  own reason over the one the body chose.
- A finished job lets go of its body, its parent and the cleanups it never ran,
  and a job made inside work handed to `ctx.unattended` lets go of the job that
  started the work: a kept handle held everything they captured.
- The remover that `whenCancelled` or `ctx.onCancel` returns lets go of the
  callback once called or once the job ends: an owner that kept its removers
  until its own end kept everything the callbacks captured.
- The remover that `ctx.onDispose` or `ctx.onDiscard` returns lets go of the
  cleanup and of the job once called, once the cleanup has run and once the job
  has ended without running it: an owner that kept its removers until its own
  end kept the job and everything the disposers captured.
- A job made by `Job(...)` inside work handed to `ctx.unattended` runs in the
  zone the work was started from, so a bare `unawaited` error in it no longer
  reaches the observer of the job that started the work.
- `ctx.join` releases the value through `dispose` or `discard` when the
  checkpoint after the action throws anything, not only a `Cancelled`.
- `ctx.join` and `ctx.abandonable` called from work handed to `ctx.unattended`
  no longer hand that work a resource they have already closed.
- A value that comes back after the body has ended no longer makes the core
  throw `Future already completed`.
- A value arriving for a job an engine ended by hand is released instead of
  leaking.
- A tree of jobs that runs out of stack while it is being built ends with the
  `StackOverflowError`, where its root could be left running for good, and a
  cancellation that runs out of stack in a deep tree still runs the `onCancel`
  callbacks of the jobs it reached.
- A call of `ctx.abandonable` the body did not await no longer sends the job's
  cancellation to the zone when the job accepts it after the body has ended.
- Thousands of jobs that wake up together no longer cost about two milliseconds
  each under JIT.
- A `then` attached to a job whose failure has already been answered for no
  longer answers for it a second time.

### Documentation

- The README is a starting page, and the reference moved to twelve pages:
  [Outcomes](doc/outcomes.md), [Cancellation](doc/cancellation.md),
  [Time](doc/time.md), [Children](doc/children.md), [Groups](doc/groups.md),
  [Chains](doc/chains.md), [Streams](doc/streams.md),
  [Cleanup](doc/cleanup.md), [Observing](doc/observing.md),
  [Errors](doc/errors.md), [Testing](doc/testing.md) and
  [Building on the core](doc/extending.md).
- `on Cancelled { rethrow; }` in front of the `catch`, which the `0.2.0` README
  recommended, logs an operation stopped by its token as a failure;
  [Asking the job](doc/cancellation.md#asking-the-job) calls `ctx.check()` in
  the `catch` instead.

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

- `Job<T>`: a cancellable piece of asynchronous work with an outcome, children
  and a cooperative cancellation. Created by `Job(body)`, which starts on the
  next microtask, or by `Job.deferred(body)`, which waits for `start()`.
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
  `ctx.onDiscard` only when the job does not end `Done`, and `wait` and `join`
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
