## Unreleased

### Breaking changes

- **Dart 3.10.0 is the lowest SDK the package supports, up from 3.6.0.**
- **`Solo.job`, `Solo.enqueue`, `Solo.collect` and `Solo.accumulate` take the
  named `isExpectedError`.** A subclass that overrides one of them must accept
  it.

### Added

- `isExpectedError` names the errors a job expects: `onError` hears them with
  `JobErrorAnswer.never`, and nobody is asked to answer for them, while a bug
  still goes to the answerers and the zone. See
  [Naming the expected errors](doc/errors.md#naming-the-expected-errors).

## 0.5.0

### Breaking changes

- **`Solo.onError` and `SoloObserver.onError` take
  `{required JobErrorAnswer answer}`, as `JobObserver.onError` of the core
  does.** See [Reporting an error](doc/errors.md#reporting-an-error).
- **`SoloContext` gains `child`, the `ctx.child` of the core: it makes a job of
  the same controller with the working type and `keepWhile` of the job that
  made it.** Code that holds only a `JobContext` makes with it a child the
  controller accepts, where a `Job.deferred` is refused. A class that
  implements `SoloContext` itself adds it. See
  [Children and chains](doc/children.md) and
  [the `async_job` changelog](https://github.com/vi-k/solo/blob/main/packages/async_job/CHANGELOG.md).

### Documentation

- [A delayed start](doc/jobs.md#a-delayed-start) shows how to start a job later
  without holding the queue, with a wait that `cancelAll` and `close` take
  back.
- [A notice the screen accepts](doc/state.md#a-notice-the-screen-accepts) shows
  news that waits on the screen until the user closes it, without holding the
  work of the controller.

## 0.4.0

This package re-exports `async_job` whole, so the changes of the core are this
package's too: see
[the `async_job` changelog](https://github.com/vi-k/solo/blob/main/packages/async_job/CHANGELOG.md).

### Documentation

- When a group is ready, which group an event joins, and how a group's job
  starts, is cancelled, fails and ends on `close()` left
  [Event accumulation](doc/accumulation.md) for
  [Accumulation rules](doc/accumulation-rules.md).

## 0.3.0

This package re-exports `async_job` whole, so the changes of the core are this
package's too: see
[the `async_job` changelog](https://github.com/vi-k/solo/blob/main/packages/async_job/CHANGELOG.md).

### Breaking changes

What to write instead, with the `0.2.0` name on the left; each has its entry
below.

| `0.2.0` | `0.3.0` |
|---|---|
| `SoloBase<S>` | `Solo<S>` |
| `Solo<S>`, the class with `stream` | `Solo<S> with SoloStream` |
| `controller.state` | `controller.currentState` |
| `onError:` of `run` and `job` | `ifFailed:` |
| `onCancel:` of `run` and `job` | `ifCancelled:` |
| `run(body)` | `enqueue(body)` |
| `add(job)` | `enqueueJob(job)` |
| `Job<T>` of a helper handed to `ctx.run` | `SoloJob<T>` |
| `onChange(previous, current)` | `onChange(transition)` |
| `SoloObserver.onChange(solo, previous, current)` | `SoloObserver.onChange(solo, transition)` |
| `SoloQueue.lastWhere` | `Solo.lastJobWhere` |
| `Job.ignore()` | `Job.ignoreFailure()` |
| `JobBase.debug` | `Job.debug` |

- **`Solo.onError` is a notice, and the new `Solo.onUnanswered` answers for an
  error nobody else has: one no outcome carries, and a `Failed` nobody
  observes.** To keep such an error out of the zone, set
  `Solo.unansweredHandler`, a `SoloUnansweredHandler`, or override
  `onUnanswered`: setting `Solo.observer`, or overriding `onError` without
  calling `super`, no longer does it. A `Failed` nobody observes goes to the
  handler or to the overridden `onUnanswered`, a microtask after the job ends,
  and reaches the zone, as in `0.2.0`, only when neither is set. So does the
  failure of a `canStart` that threw. See
  [Answering for an error](doc/errors.md#answering-for-an-error).
- **`Job.ignore()` is renamed to `Job.ignoreFailure()`** in `async_job`.
- **`JobBase.debug` is `Job.debug`** in `async_job`, which no longer exports
  `JobBase` from its main library.
- **A job is continued once, by one `then` or by handles of `shared()`,** in
  `async_job`: a second `then` on a job of `enqueue` throws a `StateError`. A
  job `Policy.droppable` may hand to another caller, and the job of an
  accumulator group, refuse a plain `then` from the first call: every caller
  continues it through a handle of `shared()`. See
  [Queue and policies](doc/jobs.md#queue-and-policies) and
  [Start, cancellation and errors](doc/accumulation-rules.md#start-cancellation-and-errors).
- **The state handlers of `enqueue` and `job` are renamed: `onError` to
  `ifFailed`, `onCancel` to `ifCancelled`.**
- **`SoloBase` is renamed to `Solo`, and the former `Solo` — the class that
  carried the broadcast stream — becomes the mixin `SoloStream`.** A controller
  whose `.stream` is read adds `with SoloStream`. See
  [Observing state](doc/state.md#observing-state).
- **`Solo.run` is renamed to `enqueue`, and `Solo.add` to `enqueueJob`.** `run`
  of the controller put a job at the tail of the queue, while `ctx.run` starts
  a child at once, past the queue; `add` shared its name with the `add` of an
  accumulator, which takes an event. See
  [Creating and scheduling jobs](doc/jobs.md#creating-and-scheduling-jobs).
- **`job`, `enqueueJob`, `enqueue`, `collect` and `accumulate` are
  `@protected`.** Give the controller a method for each operation called from
  outside. See
  [Creating and scheduling jobs](doc/jobs.md#creating-and-scheduling-jobs).
- **`SoloStream.publish` is `@protected`.**
- **The hooks `onStart`, `onFinish`, `onError`, `onUnanswered`, `onLog`,
  `onChange` and `onClose` are `@protected`.**
- **`SoloJob` is a `ChildJob`, the type `ctx.run` and `ctx.runAll` of
  `async_job` take now.** A job of `job(...)` held as a `Job` no longer
  compiles there: type the helper that makes it `SoloJob`, as
  `SoloJob<void> _recordPath(String path) => job(...)`. A continuation of
  `then`, which `ctx.run` refused with an `ArgumentError`, no longer compiles
  there either. See
  [Chaining completed work](doc/children.md#chaining-completed-work).
- **The controller's synchronous read is `currentState`, not `state`.** A body
  reads `ctx.state`. See
  [Why `currentState` and not `state`](README.md#why-currentstate-and-not-state).
- **The state of a closed controller is final.** Once the engine has finished
  closing, `externalSetState` throws a `StateError`: the new `Solo.isFinished`
  is the guard, and the new hook `Solo.onClose` is the last place a write goes
  through. See [externalSetState](doc/state.md#externalsetstate).
- **`Solo.close` takes a `SoloCloseMode`.** The default,
  `SoloCloseMode.cancel`, is what `close` always did; `SoloCloseMode.drain`
  runs what is already queued instead of dropping it. See
  [Three ways to stop](doc/cancellation.md#three-ways-to-stop).
- **The change hooks take a `SoloTransition<S>` instead of a pair of states:**
  `Solo.onChange(transition)` and `SoloObserver.onChange(solo, transition)`.
- **A subclass with a member named like a new member of `Solo` stops compiling,
  or overrides it.** The new instance members are `currentState`, `isFinished`,
  `isDraining`, `pending`, `enqueue`, `enqueueJob`, `onClose`, `onUnanswered`,
  `addListener`, `removeListener`, `hasListeners` and `onListenerError`.
- **A class that implements `SoloContext` itself adds `abandonable`,
  `heldCancellation`, `pause`, `runAll` and `start`,** the new members of
  `JobContext` in `async_job`, its `run` takes `dispose` and `discard`, and its
  `each` takes `key` and `describe`.
- **`Policy.droppable` refuses a key held by a job of another result type with
  an `ArgumentError`, and refuses before it takes the new job.** See
  [A key for each request](doc/jobs.md#a-key-for-each-request).
- **A job dropped by `Policy.droppable` ends with the new
  `DuplicateCancelReason`, not a `ManualCancelReason`.**
- **A job that `Policy.replace` or `Policy.restart` puts a newer one in place
  of ends with the new `ReplacedCancelReason`, not a `ManualCancelReason`.**
- **`collect` and `accumulate` default to `AccumulationPolicy.join`, not
  `adjacent`.** A job of another kind queued between two events is no longer a
  boundary; name `adjacent` where it has to be one. See
  [Commands where only the last one counts](doc/accumulation.md#commands-where-only-the-last-one-counts).
- **`AccumulationPolicy.replace` moves the waiting group's job to the tail
  instead of building a new job and cancelling the old one.** Every event of
  one group now shares its handle and outcome under every policy.
- **`SoloQueue.lastWhere` is gone.** `Solo.lastJobWhere` finds the same job and
  looks at the running one as well.
- **`cancelAll` and `SoloQueue.remove`, `removeWhere` and `clear` take a
  `reason`.**
- **`SoloQueue.jobs` and `Solo.current` hand out `SoloJob<Object?>`, and the
  predicates of `SoloQueue.removeWhere` and `Solo.lastJobWhere` take one.** A
  predicate written for `Job<Object?>` compiles as it did; an override of
  `current` or `lastJobWhere` and a class that implements `SoloQueue` take the
  new types.
- **`job`, `enqueue`, `collect` and `accumulate` take `timeout`.** An override
  passes it on to `super`, or `enqueue(timeout: ...)` loses its deadline
  without a word.
- **`collect` and `accumulate` take `ifFailed` and `ifCancelled`.** An override
  passes them on to `super`, or the groups of its accumulators lose their state
  handlers without a word.

### Deprecated

- `ctx.wait` in `async_job` is deprecated in favour of `ctx.abandonable` and
  goes away in the next release.

### Changes you will see on upgrade

Errors that `0.2.0` lost, or kept to the hooks, now reach
`Solo.unansweredHandler`, or, with no handler set, the zone the job was created
in. In a test that zone is the test's, and the test fails:

- an error no outcome carries, in an application that sets `Solo.observer` or
  overrides `onError` without calling `super`;
- the failure of the body of a job that ends `Cancelled`: an operation that
  stops at a token the job cancels through `ctx.onCancel` throws one on every
  cancellation. `Job.isCancellationError` names the errors a cancellation
  causes, once, in `main`, and they reach `onError` and go no further;
  `job.ignoreFailure()` silences the failure of that job alone;
- the late failure of an action the body walked away from through `.timeout` or
  `Future.any`, arriving once the job is over;
- the failure of a source's own cleanup when `ctx.each` lets go of a stream.

A job that gives up through `ctx.check()` inside a call `ctx.abandonable` has
let go of no longer reaches `onError` as a failure.

`onError` of the controller and of the observer hears each failure and each
`Cancelled` inside a `ParallelWaitError` in a call of its own, where `0.2.0`
handed it the whole error once. A `Failed` with such an error that nobody
observes reaches `Solo.unansweredHandler`, or the zone, failure by failure and
without its cancellations, where `0.2.0` passed the zone the whole error. See
[Answering for an error](doc/errors.md#answering-for-an-error).

A dropped duplicate prints `Cancelled(duplicate)`, a job replaced under
`Policy.replace` or `Policy.restart` prints `Cancelled(replaced)`, and several
error messages are reworded.

The stack trace of a job its rules cancelled is taken where the rules noticed.

`ctx.each` asks the rules of the job before it starts the child, as `ctx.state`
does. After the job's own `emit` of a state they refuse, it ends the job
`Cancelled` by the rules, and `ifCancelled` does not run, as at any checkpoint
of the rules. `0.2.0` handed back a child the same rules had refused to start:
the stream was never listened to, a job that did not read the child ended
`Done`, and one that read its `.value` ended cancelled by the child, with
`ifCancelled` run. See
[Processing a stream](doc/streams.md#processing-a-stream).

The body of a queued job runs in the zone the job was created in, with its
deadline and its `onStart` hooks, where `0.2.0` ran them in the zone of
whatever woke the queue, often another call's: a body awaiting a future of its
own zone waited for good when the future failed while the body ran under a
different `runZonedGuarded`. See
[Creating and scheduling jobs](doc/jobs.md#creating-and-scheduling-jobs).

`keepWhile` may not set the state: a write while it answers throws a
`StateError`, and the rule throws with it, as any rule that throws. `0.2.0` let
the write through and asked the rule again about the new state, and a rule that
wrote every time it was asked ran out of stack. `canStart` may still write: it
is asked once.

An `ifFailed` or `ifCancelled` handler that hands back the state it was given,
or a `const` the state already holds, publishes nothing and leaves in place a
write it made itself, where `0.2.0` published that state again as a change.

The lines of `Solo.debug` about a job being queued begin with `enqueue`, not
`add`.

### Added

- **`ctx.start` of `async_job` starts a child the body does not wait for.** The
  rules of the controller decide as they do for `ctx.run`: a child they turn
  away ends `Cancelled(rules)`, and `start` returns as usual; a `canStart` that
  throws throws from `start`. A failure of the child goes to `onUnanswered`.
- **`timeout` gives a job of the controller a deadline of its own.** `job`,
  `enqueue`, `collect` and `accumulate` take it; when it runs out, the job ends
  `Cancelled(timeout)` with the new `TimeoutCancelReason` of `async_job`. See
  [A deadline of a job](doc/cancellation.md#a-deadline-of-a-job).
- **`collect` and `accumulate` take `ifFailed` and `ifCancelled`, the state
  handlers of `job`.** A group that wrote a state of its own while it ran takes
  it back through them when it fails or is cancelled; it calls one of them at
  most once, however many events it holds. See
  [Start, cancellation and errors](doc/accumulation-rules.md#start-cancellation-and-errors).
- **`Job.isCancellationError` of `async_job` names the errors a cancellation
  causes.** A failure of a cancelled job that it names reaches `onError` and
  goes no further: neither `onUnanswered` nor `Solo.unansweredHandler` hears
  it. See [The token](doc/cancellation.md#the-token).
- **`Job.whenFinished` of `async_job` hears the end of a job without observing
  its outcome.** A listener gets the outcome, and a failure nobody observes is
  still answered for. See [Jobs and results](doc/jobs.md#jobs-and-results).
- **`ctx.each` of a controller takes the `key` and `describe` of `async_job`**
  to name its child. The `key` is a name only: queue policies govern root jobs,
  and the child is not one.
- **`SoloObserver.all` makes one observer of several** for `Solo.observer`. See
  [A cancellation that never lands](doc/diagnostics.md#a-cancellation-that-never-lands).
- `Solo` carries its own listeners: `addListener` and `removeListener`, and the
  protected `hasListeners` and `onListenerError` beside them. See
  [Observing state](doc/state.md#observing-state).
- `Solo.pending`: what is holding the controller, for a `close` that has not
  come back, or `null` when nothing does. It is a `SoloPending`, one of three:
  a `SoloPendingJob` with its `SoloPhase`, a `SoloPendingQueue` or a
  `SoloPendingStream`. See
  [What is holding the controller](doc/diagnostics.md#what-is-holding-the-controller).
- `AccumulationTiming.throttle` takes `startAtOnce`. With `startAtOnce: false`
  the interval is counted before the first group as well.
- `AccumulationTiming` has `==`, `hashCode` and a `toString` that prints the
  kind, the duration and `startAtOnce` in the shape of the constructor.
- `package:solo/listeners.dart`: `Listeners`, the list of listeners a notifier
  walks, for a package that builds a delivery of its own on top of `solo`.
- `Solo.debug` names the running job on the line of a job queued while it runs:
  `while Job(outer) is running: it starts after Job(outer) ends`; the line of a
  duplicate that `Policy.droppable` hands back says so too, and a duplicate of
  the running job ends
  `which is running: if awaited from inside Job(x), it waits for itself`.

### Fixed

- A state `canStart` writes while it answers is held to `W` and `keepWhile`:
  the job started under it even when it no longer matched them.
- `Policy.replace` and `Policy.restart` queue the new job before they cancel
  the jobs it replaces. A job of the same key that `onFinish` or
  `whenCancelled` queued as a replaced job ended came in ahead of the new job,
  and both ran: the last request lost to the one before it.
- A child that its own `canStart` cancels while it answers yes reaches its
  parent as its cancellation, as a refusal does: the parent ended `Failed` with
  a `StateError` that the child had already finished.
- A child that a start rule of its own runs again is refused with a
  `StateError`: the parent stopped waiting for the child, whose body went on
  running, and the child's `onDispose` never ran.
- `Policy.droppable` and `Solo.lastJobWhere` no longer hand back a job that is
  not going to do the work: `cancelAll()` and a fresh request a line later
  answered the second call with the handle the first had just cancelled.
- `cancelAll` and the removals of `SoloQueue` reach the job the engine is about
  to start: called from that job's start rules, they missed the job, which
  started anyway.
- `Policy.droppable`, `replace` and `restart` reach the job the engine is about
  to start: called from that job's start rules with its key, they missed it,
  and two jobs of one key ran one after the other.
- A `publish` that throws no longer holds back the changes queued behind it,
  and the rules of the running jobs are asked all the same: a job the new state
  rejects is cancelled.
- A predicate of `SoloQueue.removeWhere` or `Solo.lastJobWhere` that removes a
  job no longer walks into a `ConcurrentModificationError`.
- A finished job lets go of its body, of its state handlers and of the job that
  ran it: one kept handle held the whole tree of finished jobs it came out of.
- A job one controller's `ctx.unattended` work starts on another controller
  starts in the zone the work was started from: a bare `unawaited` error in its
  body reached the `onError` of the controller whose job started the work.
- A `Cancelled` a hook of the controller or of the observer throws no longer
  reaches the zone.

### Documentation

- The README is a starting page, and the reference moved to `doc/`, one page
  per subject: [Jobs and the queue](doc/jobs.md), [State](doc/state.md),
  [Cancellation](doc/cancellation.md),
  [Resources and cleanup](doc/resources.md),
  [Children and chains](doc/children.md), [Streams](doc/streams.md),
  [Diagnostics](doc/diagnostics.md), [Errors](doc/errors.md),
  [Testing](doc/testing.md) and [Camera example](doc/camera.md). The Flutter
  section went to `flutter_solo`.
- Two pages to look things up: [Reference](doc/reference.md), every member of
  `Solo`, its context, jobs, queue and accumulators and every parameter of
  `enqueue`, `job`, `collect` and `accumulate` with the section that explains
  it, and [Common mistakes](doc/mistakes.md), seven mistakes and the right way
  for each.
- One recommendation of `0.2.0` is replaced: a source of external states is
  stopped in `onClose`, not before `close`, and a callback that can still
  arrive after that guards its write with `isFinished`.
- The camera example no longer sticks in `Preparing` when an opening is
  cancelled half way.
- The camera example no longer publishes `Ready` over a failure the hardware
  reports while the camera opens.
- Each scenario of [solo and bloc, side by side](doc/vs-bloc.md) ends with a
  line of what solo gives.

## 0.2.0

The first published release. 0.1.0 never left the tree, so nothing below is a
migration anybody has to make; what changed since it is at the end, for a tree
that followed the package before it went out.

- Add `onError` and `onCancel` state handlers to `run` and `job`. They apply
  state after children and cleanup, before the next queued job, while
  preserving the failed or cancelled outcome. Incompatible external state
  changes suppress correction, including during cleanup and for descendants.
  The quick start now uses sealed loading/result/error states.

- Add `AccumulationTiming.debounce` and `.throttle` to `collect` and
  `accumulate`. Debounce seals a group after a pause between events; throttle
  spaces actual group starts. Waiting groups let ready jobs pass, while
  handlers, children and cleanup remain sequential. `collect` retains every
  event; `accumulate` retains the `merge` result. Closing cancels timing timers
  and queued groups without a final batch.

- **Breaking:** `ctx.run(child)` returns the child's result as `Future<T>`.
  Replace `await ctx.run(child).value` with `await ctx.run(child)`; keep the
  original child handle to cancel it or inspect its outcome. After success,
  `run` checks the parent's cancellation and state rules before returning.
  Concurrent starts must handle or explicitly ignore the returned future.
  Controller `run` and `ctx.each` still return job handles immediately.

- Add `collect` and `accumulate` factories returning `SoloAccumulator`: gather
  events in a list or merge them into one value before execution.
  `AccumulationPolicy` selects adjacent grouping, replacement at the queue's
  tail with data transfer, or joining an existing queued group. Groups use
  ordinary `SoloJob` lifecycle, state rules and cancellation.
- Re-export `Job.then` and `ChainCancelReason` from the core. Continuations
  support cancellation chains and have their own `JobContext`; they do not
  inherit controller state, rules, observers or a queue slot.

- `SoloBase<S>` engine: one root job at a time, exclusive state ownership.
- `Solo<S>` with a broadcast `stream`, delivered on the next microtask.
- Jobs as `async` bodies with a working type `W`, `canStart` and `keepWhile`
  rules, `cancellable: false`.
- Keep a replacement cancelled by a synchronous listener out of the queue, so
  it cannot absorb a later `droppable` job.
- Requires `async_job: ^0.2.0`: `job.whenCancelled(callback)` registers a
  synchronous listener receiving `Cancelled` and returns an unregister
  function.
- `Job<T>` handle: `done`, `value`, `outcome`, `whenCancelled`, `cancel`,
  `ignore`.
- `Outcome<T>`: `Done`, `Failed`, `Cancelled` with `CancelReason`.
- A `Failed` outcome nobody observed goes to the zone that created the job, the
  way Dart reports an unhandled `Future` error. Reading `done` or `value`, or
  calling `ignore`, counts as observing it; `Cancelled` never reaches the zone.
- `JobContext` of the kernel: `check`, `wait`, `join`, `uncancellable`,
  `unattended`, `onCancel`, `run`, `each`, `log`.
- `SoloContext<S, W>` on top of it, where the state lives: `state`, `stateAs`,
  `emit`.
- A body does not `await` on its own: every call goes through the context, and
  the member it picks says what a cancellation does to that call. `wait` ends
  the waiting and lets the action run on; `join` waits for all of the action
  and gives up afterwards, so a device call is never left mid-flight;
  `uncancellable` holds the cancellation for the length of the call and gives
  up once the step is over; `unattended` does not wait at all and hands the
  work to the engine, which hears it fail even after the job is over.
- `ctx.unattended(action)` for work a body starts and does not wait for. It
  runs in an error zone of its own, and whatever it leaves uncaught — now, or
  long after the job is over — reaches `onError` instead of the process.
- **Behaviour change.** With no `SoloBase.observer` and no override of
  `SoloBase.onError`, an error with nowhere else to go no longer stops in the
  empty hook: it goes to the zone the job was created in, the way the core
  reports one when a job has no observer. That covers a disposer, an `onCancel`
  callback, a late failure of an abandoned call or of unattended work, and a
  `canStart` or `keepWhile` that threw instead of answering while the job runs.
  A `Cancelled` is the one exception and never goes there. Install an observer,
  or override the hook, and the route is yours again; call `super.onError(...)`
  from the override to keep it. A rule that throws *before* the job starts is
  not on this route at all: it becomes a `Failed` outcome and reaches the zone
  as any unobserved failure does, whatever the observer.
- A cleanup stack instead of a `finally` in the body: `ctx.onDispose` releases
  whatever the outcome, `ctx.onDiscard` only when the job does not end `Done`,
  and `wait` and `join` take the same two as `dispose` and `discard` for the
  value they hand over — a connection or a file an abandoned action opened is
  still closed. The engine unwinds the stack after the children and before the
  outcome, and `close` waits for it; `ctx.disown(value)` takes a registration
  back when the body hands the value over itself.
- `JobContext.uncancellable` is `wait`'s counterpart: it runs a step that
  cannot be taken back — a payment on its way to the server — with the
  cancellation held until the step is over, and `close` waits for it.
- **Breaking:** `ctx.each(stream, (child, event) { ... })` returns a child
  `Job<void>` immediately. Await `.value` for a throwing result, inspect
  `.done`, or cancel the subscription separately through `.cancel()`. The
  callback receives a `SoloContext<S, W>` retaining the parent's working type
  and `keepWhile`, without inheriting `canStart`. The parent waits for this
  child even without an explicit await, and observers see the child. Parent
  cancellation cascades to it.
- Cancelling `each` removes the subscription immediately, then waits for the
  running callback before child completion and cleanup. Use child context
  checkpoints to respond to cancellation; a plain `await` can delay
  cancellation and `close()`. Source cleanup from subscription cancellation is
  still not awaited. `each` is now a context method and follows `run`'s
  restrictions on when and where children can start.
- `JobContext.onCancel` hands a cancellation to something that can really
  stop — a device's cancel token, an HTTP abort. `wait` ends the waiting, not
  the work.
- Child jobs via `ctx.run`; a parent finishes after its children.
- `SoloQueue` with `remove`, `removeWhere`, `clear`, `lastWhere`; policies
  `sequential`, `droppable`, `replace`, `restart`.
- `externalSetState` for hardware listeners; every change re-evaluates the
  rules of running jobs.
- `SoloObserver` and instance hooks; `SoloBase.debug` engine tracing.
- A hook that throws changes nothing: the engine hands its error to the current
  zone and carries on, and the hook next to it is still called.

### Since 0.1.0

- The job kernel now lives in `package:async_job` and is re-exported whole:
  `package:solo/solo.dart` stays the only import. Code using the old reason API
  must migrate to the reason classes. The job's lifecycle, context, outcomes
  and observer moved to the kernel; the state, queue and rules stay in `solo`.
- `CancelReason` is an extensible class hierarchy: `ManualCancelReason`,
  `ParentCancelReason` and `HandlerCancelReason` from the core, plus
  `RulesCancelReason` and `ClosedCancelReason` from `solo`. Inspect types;
  `name` is only a log label, with no equality by name. Custom subclasses can
  carry arbitrary data through `job.cancel(reason: reason)`. Parent and child
  propagation retain the original cancellation in `cause`.
- `Cancelled.by({reason, started, description, stackTrace})` is public: an
  engine of a domain builds cancellations with a reason of its own.
- `JobContext<S, W>` is renamed to `SoloContext<S, W>`, and the name
  `JobContext` now belongs to the interface of the kernel: cancellation, the
  waiting family and children, without the state. `SoloContext` implements it
  and adds `state`, `stateAs` and `emit`. Job bodies do not write the name, so
  code written against the README keeps compiling.
- The job and its context are split along the seam the kernel will be taken out
  at: `JobBase<T>` and `JobContextBase` carry the lifecycle, the waiting
  family, the children and the outcome, and the solo subclasses add the state,
  the rules and the queue. Nothing moves in the public API of a controller.
- The list of children a job waits for now shrinks as they finish: a long-lived
  job starting children in a loop no longer grows one entry per child. The
  description of a parent's own outcome is unchanged — the link from an outcome
  to the child that carried it lives in an `Expando`, so a child without a key
  still shows in it.
- A value a body returned after its cancellation had already arrived is
  released rather than dropped: the body registers it on the cleanup stack, the
  outcome stays the cancellation, and `close` waits for the release.
- A job says who may adopt it: `ctx.run(child)` refuses a job of another
  controller with `ArgumentError` and a job still waiting in the queue with
  `StateError`, and a job of `solo` is refused by a context of the bare kernel.
  A child without an observer of its own inherits the parent's.
- `JobBase.debug` traces the life of a job, `SoloBase.debug` the queue, the
  state and the closing. Set both to follow both.
- `JobObserver` is the observer of a single job: `onStart`, `onFinish`,
  `onError` and `onLog`, without the controller in the signatures. A controller
  feeds its own `SoloObserver` and its instance hooks from it, so nothing
  changes for a user of `solo`.
- `isQueued` moves from `Job<T>` to the new `SoloJob<T>`, returned by `job`,
  `add` and `run`. The queue is the controller's, not the job's. `JobStatus` is
  public and has three values: a queued job is `created` until it starts, and
  `isQueued` is computed from the queue itself — inside `canStart` a job taken
  from the queue is no longer queued.

## 0.1.0

Never published.
