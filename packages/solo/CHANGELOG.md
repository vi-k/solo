## Unreleased

Moving from `0.2.0`: read "Breaking changes" for what stops compiling or
behaves differently, and "Changes you will see on upgrade" for what a test or a
log shows with no change to the code — errors that now reach the zone, and text
that reads differently. This package re-exports `async_job` whole, so the
breaking changes of the core are this package's too; the last entry of the
first group names them.

### Breaking changes

- **`SoloBase` is renamed to `Solo`, and the former `Solo` — the class that
  carried the broadcast stream — becomes the mixin `SoloStream`.** `Solo` is
  the class every controller extends, and a stream is part of the controllers
  that add `with SoloStream` and of no others. `Solo` is `abstract`, as
  `SoloBase` was, so a bare `Solo<T>(value)` no longer compiles: there is no
  concrete class left that carries a stream on its own. The statics move with
  the name — `Solo.observer`, `Solo.debug` — and the hooks of `SoloObserver`
  take a `Solo<Object>`. **Migrating.** `extends SoloBase<S>` becomes
  `extends Solo<S>`. A controller that read `.stream` adds `with SoloStream`,
  the type argument inferred from the superclass; one that never read it needs
  no change. A field or parameter typed `Solo<S>` that reads `.stream` becomes
  `SoloStream<S>`, and there the argument is written out: the analyzer does not
  ask for it, and a bare `SoloStream` is a `SoloStream<Object>`. In place of
  `Solo<T>(value)` write a one-line class, which takes the constructor of
  `Solo` as it is: `class C<T extends Object> = Solo<T> with SoloStream;`. A
  subclass of `SoloObserver` renames the type of the first parameter of its
  hooks. See [Observing state](doc/state.md#observing-state).

- **`job`, `add`, `run`, `collect` and `accumulate` are `@protected`.** A
  controller's operations are its own methods, such as `load()` or `setZoom()`,
  and those are what a caller sees; the five members they are built from belong
  to the controller, as `externalSetState` and `queue` already did. The
  analyzer reports a call from outside the class as
  `invalid_use_of_protected_member`; the code still compiles and runs as
  before. **Migrating.** Give the controller a method for each operation called
  from outside, and call that. A controller that is a queue for jobs somebody
  else writes reopens what that code calls with an override that forwards to
  `super` and leaves the annotation off: `@protected` does not carry over to an
  override. See
  [Creating and scheduling jobs](doc/jobs.md#creating-and-scheduling-jobs).

- **The controller's synchronous read is `currentState`, not `state`.** A job
  body is a closure inside a method of the controller, so every member of the
  controller is in scope there, and a read named `state` looked exactly like
  the checked `ctx.state` while doing none of its work: no `Cancelled` for a
  job that had lost the state, no `keepWhile` check, and the whole of `S`
  instead of the job's working type `W`. Under the new name that mistake is a
  compile error. Reads through the context, the `state` parameters of
  `canStart`, `keepWhile`, `onError` and `onCancel`, and `externalSetState` are
  unchanged. No deprecated alias is kept: one that still compiled inside a body
  would leave the hole open. **Migrating.** Outside a body, `controller.state`
  becomes `controller.currentState`; inside one, read `ctx.state`. See
  [Why `currentState` and not `state`](README.md#why-currentstate-and-not-state).

- **`Solo.onError` is a notice, and the new `Solo.onUnanswered` answers for an
  error no outcome carries.** Such an error — an operation abandoned by
  `ctx.wait` failing later, a disposer, an `onCancel` callback, work handed to
  `ctx.unattended` — went to the zone the job was created in only while nobody
  was listening. Setting `Solo.observer` kept it out of the zone, so an
  observer set for a log switched reporting off for the whole process, and so
  did an override of `onError` that did not call `super`. Now watching is not
  answering. `onError` and the observer's `onError` are told about every error
  of the controller, once, and move it nowhere. The answer is asked of
  `onUnanswered`, whose default body calls the new `Solo.errorHandler` — one
  handler for the process, set once at startup — and, with no handler set,
  sends the error to the zone the job was created in. A `Cancelled` still never
  goes to the zone. **Migrating.** An application that set an observer and
  relied on the silence sets `Solo.errorHandler` as well. An override of
  `onError` that called `super` keeps working: the call runs an empty body, and
  the route stands without it. One that did not call `super` no longer keeps
  these errors anywhere: move its body to `onUnanswered`, where an override
  answers for them and stops them, and
  `super.onUnanswered(job, error, stackTrace)` keeps the default route as well.
  See [Answering for an error](doc/errors.md#answering-for-an-error).

- **The state of a closed controller is final.** Once the engine has finished
  closing, `externalSetState` throws a `StateError`, where it used to change
  the state and call the change hooks with nobody left to hear them: the stream
  was closed, so the state moved in silence and every reader had to choose for
  itself between the last thing it was told and what the controller holds now.
  The new `Solo.isFinished` is the guard, and the new hook `Solo.onClose` is
  the last place a write goes through: the engine calls it once, after the last
  job and after the observer's `onClose`, while `isFinished` is still false.
  `isClosed` will not do as the guard: it is true from the first line of
  `close`, and under `SoloCloseMode.drain` the queue is still running then and
  needs the facts. **Migrating.** `0.2.0` said to stop the source of external
  states before closing the controller. Cancel its subscription in an override
  of `onClose` instead, and in a callback that can arrive late check
  `isFinished` right before the write, after the last `await`. A terminal state
  that a subclass set after `await super.close()` has nowhere to go there:
  write it in `onClose`. See [externalSetState](doc/state.md#externalsetstate).

- **`Solo.close` takes a `SoloCloseMode`.** Calls are unchanged — the default
  is `SoloCloseMode.cancel`, which is what `close` always did — but an override
  of `close` has to take the parameter too. `SoloCloseMode.drain` closes by
  running what is already queued instead of dropping it: no new root job is
  taken from the call onwards, and the ones accepted before it go by the usual
  rules, children, cleanup and accumulation windows included. A plain `close()`
  over a running drain stops it where it is, and `Solo.isDraining` says whether
  one is running. Running the queue is not a promise of delivery: a buffer that
  keeps events until the sending is confirmed is built on top of this.
  **Migrating.** Add `{SoloCloseMode mode = SoloCloseMode.cancel}` to an
  override of `close` and pass it to `super.close(mode: mode)`. What the
  override did once the controller had closed belongs in `onClose` now: it runs
  once, whatever mode closed the controller and however many times `close` was
  called. See [Three ways to stop](doc/cancellation.md#three-ways-to-stop).

- **The change hooks take a `SoloTransition<S>` instead of a pair of states:**
  `Solo.onChange(transition)` and `SoloObserver.onChange(solo, transition)`.
  Beside `previous` and `current` it carries `job` — the job the change belongs
  to, `null` for an `externalSetState`, and a child rather than the root it
  belongs to — and `revision`, which grows by one per change and orders two
  transitions even when a hook changed the state again from inside the first. A
  state returned by a job's `onError` or `onCancel` handler is that job's
  change as well. **Migrating.** `previous` becomes `transition.previous`,
  `current` becomes `transition.current`.

- **A subclass with a member named like a new member of `Solo` stops compiling,
  or overrides it.** The new instance members are `currentState`, `isFinished`,
  `isDraining`, `pending`, `onClose`, `onUnanswered`, `addListener`,
  `removeListener`, `hasListeners` and `onListenerError`. The dangerous one is
  `isFinished`: `Job` already has a member of that name, and a controller that
  drives a download or a sync is where a subclass would most likely have
  spelled a `bool` of its own the same way. It keeps compiling and overrides
  the engine's: every `if (!isFinished)` in the subclass answers from the
  domain flag, while the engine checks its own private state and goes on
  refusing the write. **Migrating.** Rename the member of the subclass.

- **`Policy.droppable` refuses a key held by a job of another result type with
  an `ArgumentError`, and refuses before it takes the new job.** It used to
  finish the new job as a duplicate first and then cast the job it found to the
  type argument of the call: a `TypeError`, and no job left to add. Where the
  cast passed, the caller got somebody else's job. `void` is a top type, so a
  `Job<void>` added under a key a `Job<String>` held was dropped and `add`
  handed back the `Job<String>` typed as `SoloJob<void>`: the work the caller
  asked for never ran. A supertype was waved through the same way, a
  `Job<Object>` on a key held by a `Job<String>`. Now the two jobs are compared
  with each other, and by the types as written, so a key shared by two
  spellings of one thing throws as well: `Job<dynamic>`, `Job<Object?>` and
  `Job<void>` against each other, the same inside an argument — `List<Object?>`
  against `List<dynamic>` — and `Job<int>` against `Job<int?>` or
  `Job<FutureOr<int>>`. A refused job is untouched and can still be added. A
  closed controller never reaches the check: there the job finishes with
  `Cancelled(closed)`, as before. **Migrating.** Give every result type a key
  of its own. Watch for the pair inference makes by itself: a body that returns
  nothing gives `Job<Null>` where the call writes no types and `Job<void>`
  where the method's return type says so. Writing the arguments out —
  `run<Ready, void>` — keeps the answer from depending on how a call was
  spelled. See [Queue and policies](doc/jobs.md#queue-and-policies).

- **A job dropped by `Policy.droppable` ends with a reason of its own.** Its
  outcome is `Cancelled(duplicate)` and the reason a new
  `DuplicateCancelReason`, where it used to be `Cancelled(manual: duplicate)` —
  the `ManualCancelReason` of a `cancel()`, with the difference written into
  `description`. **Migrating.** Code that told a duplicate by that text checks
  the type of the reason instead, `DuplicateCancelReason`, and code that took
  every `ManualCancelReason` for a cancellation somebody asked for no longer
  counts duplicates among them.

- **`collect` and `accumulate` default to `AccumulationPolicy.join`, not
  `adjacent`.** A job of another kind queued between two events is no longer a
  boundary: the events are one group, where the group already stands in the
  queue. The old default made the same two events one group or two depending on
  what else the controller happened to be doing at that moment, which is a
  decision no caller made, and under a `timing` it also cost the second group a
  whole interval. **Migrating.** A call that names a policy is unaffected. Name
  `adjacent` explicitly where the boundary is the point: where `merge` throws
  away what it replaces and a job queued between two events has to run between
  them — a transport control that keeps only the last command is the case — or
  where such a job changes what the accumulated input means. See
  [Commands where only the last one counts](doc/accumulation.md#commands-where-only-the-last-one-counts).

- **`AccumulationPolicy.replace` moves the waiting group's job to the tail
  instead of building a new job and cancelling the old one.** Every event of
  one group now shares its handle and outcome under every policy: five events
  into a busy queue give one handle and one `Done`, where they used to give
  five handles and four `Cancelled(manual: replaced by accumulated group)`. The
  grouping and the moments a group starts are unchanged. `cancellable: false`
  has nothing to refuse here — a move is not a removal — where `0.2.0`
  cancelled the replaced job in spite of it, and the cancellation callbacks
  that used to run in the middle of a replacement do not run at all.
  **Migrating.** Code that waits on the handle an `add` returned keeps working
  and now sees the group's real outcome. Code that treated that `Cancelled` as
  "mine was pushed out" has nothing to react to: the event was not pushed out,
  it is in the group. Code that compared an earlier handle with a later one to
  detect a replacement has nothing left to compare.

- **`SoloQueue.lastWhere` is gone.** `Solo.lastJobWhere` finds the same job and
  looks at the running one as well, so the queue had a second way to ask one
  question. **Migrating.** `queue.lastWhere(test)` becomes
  `lastJobWhere(test)`, or `queue.jobs.where(test).lastOrNull` where only the
  queue should answer. `queue.jobs.lastWhere(test)` is not the same thing: it
  throws a `StateError` when nothing matches, where the old method returned
  `null`.

- **`cancelAll` and `SoloQueue.remove`, `removeWhere` and `clear` take a
  `reason`.** Every job they end carries it, so a policy of the domain that
  clears the controller can tell its cancellations from a user's; without one
  it is `ManualCancelReason`, as before. Calls are unchanged. **Migrating.** An
  override of `cancelAll` and an implementation of `SoloQueue` of its own take
  the parameter too.

- **Inherited from `async_job`.** Four of the core's breaking changes reach an
  ordinary job body. A cancellation that travels inside a `ParallelWaitError`
  is a cancellation again: a child cancelled under
  `[ctx.run(a), ctx.run(b)].wait` ends the job `Cancelled` where it used to end
  it `Failed`, so the job's `onCancel` handler takes the outcome instead of
  `onError`, `job.value` throws the `Cancelled`, and a
  `catch (ParallelWaitError)` around it no longer runs. `JobContext` gains
  `runAll`, and an extension of that name on `JobContext` is shadowed by it.
  `ctx.run` takes `dispose` and `discard`: no call site breaks, but a
  registration written on the line after `await ctx.run(child)` belongs in the
  call now. A class that implements `JobContext` or `SoloContext` by hand, a
  test fake for one, needs both. A body that throws `Cancelled`, or lets out
  the cancellation of a child, runs its `ctx.onCancel` callbacks, and
  `whenCancelled` fires as it throws rather than once its children have ended.
  One more reaches code that gives a job of the core an observer of its own:
  `JobObserver.onError` is a notice, and the new `JobObserver.onUnanswered`
  answers for an error no outcome carries, so such an observer no longer keeps
  those errors out of the zone, and a class that implements `JobObserver` needs
  an `onUnanswered`. The switch of the core's debug channel, the one set next
  to `Solo.debug`, is `Job.debug`, where it was `JobBase.debug`. The rest
  concern an engine built on the core: `JobBase`, `JobContextBase` and
  `JobStatus` moved to `package:async_job/engine.dart`, which also takes them
  out of what an app sees through this package, and the protected surface of
  `JobBase` changed. **Migrating.** Read the core's own entries:
  [the `async_job` changelog](https://github.com/vi-k/solo/blob/main/packages/async_job/CHANGELOG.md).

### Changes you will see on upgrade

Errors that `0.2.0` lost, or kept to the hooks, now reach `Solo.errorHandler`,
or, with no handler set, the zone the job was created in. In a test that zone
is the test's, and the test fails:

- an error no outcome carries, in an application that sets `Solo.observer` or
  overrides `onError` without calling `super`: the entry on `onUnanswered`
  above;
- the failure of a body when a cancellation reaches the job afterwards, while
  the job waits for children of its own or runs its cleanup. Whoever reads the
  outcome gets the cancellation. In `0.2.0` reading it kept the failure to
  `onError`; now it reaches the zone read or not. `job.ignore()` on that job
  silences it, and `onError` still hears it;
- the failure of a step of `ctx.uncancellable` while the section held a
  cancellation back, the same way: `0.2.0` told `onError` and nobody else;
- the late failure of an action the body walked away from, through `.timeout`
  or `Future.any`, arriving once the job is over: `0.2.0` told nobody at all;
- the failure of a source's own cleanup, the future of the subscription's
  `cancel()`, when `ctx.each` lets go of a stream: `0.2.0` dropped it.

One report is gone: a job that gives up through `ctx.check()` inside a call
`ctx.wait` has let go of no longer reaches `onError` as a failure.

Text that reads differently, for a test that matches it:

- a dropped duplicate prints `Cancelled(duplicate)`;
- some error messages: a job cleaning up after its body says
  `is cleaning up after its body` where it said `is disposing`, and a job of
  another controller refused by `add` is named as `Job(key)`, not by its class.

And one trace is taken elsewhere in a release build. A change of state records
its stack trace only where assertions are on, so the trace of a job its rules
cancelled is taken where the rules noticed; `Solo.traceStateChanges`, under
"Added", turns the record back on.

### Added

- `Solo` carries its own listeners: `addListener` and `removeListener`, and the
  protected `hasListeners` and `onListenerError` beside them. A controller is
  observable without a delivery of its own, which is what a widget or another
  package's binding needs; `SoloStream` keeps its stream and feeds it after the
  listeners. Notification is synchronous and in subscription order, one call
  per registration. A listener that throws is reported through
  `onListenerError` — the zone by default — and the pass goes on. Listeners are
  dropped when the engine finishes closing, right after `onClose`, and a
  registration made after that is ignored rather than retained. See
  [Observing state](doc/state.md#observing-state).

- `Solo.pending`: what is holding the controller, for a `close` that has not
  come back, as one of three. A `SoloPendingJob` is the job the controller is
  waiting for — its phase (body, children or cleanup), the cancellation it
  carries, the one a `ctx.uncancellable` section is holding back, whether such
  a section is open, whether it was created `cancellable: false`, and whether
  the close is a drain. A `SoloPendingQueue` is a drain with no job running and
  the queue it has still to run, where a group of `collect` or `accumulate`
  waits for its timing. A `SoloPendingStream` is the stream of `SoloStream`,
  closing after the engine and held by a subscription left paused.
  `SoloPending` is sealed, so a `switch` over the three is exhaustive; `null`
  means that nothing the controller knows of holds the close. It reports what
  the engine knows: a body waiting on a bare `await` is in its body, and the
  snapshot does not guess at why. See
  [What is holding the controller](doc/errors.md#what-is-holding-the-controller).

- `AccumulationTiming.throttle` takes `startAtOnce`. With `startAtOnce: false`
  the interval is counted before the first group as well: an accumulator with
  nothing of its own queued or running starts its interval where the group
  appears, and the group runs when the interval ends, carrying everything
  written meanwhile. The default is unchanged. Take it where the rate matters
  more than the latency of the first event; the cost is that a single event
  waits the whole interval, and a draining `close` waits with it.

- `Solo.traceStateChanges`. A change of state recorded its stack trace every
  time, which cost most of what the change costs, for one reader: the trace of
  a job its rules cancel. The record is now taken where assertions are on — in
  development and in tests — and the flag turns it on in a release build or off
  everywhere.

- `package:solo/listeners.dart`: `Listeners`, the list of listeners a notifier
  walks, for a package that builds a delivery of its own on top of `solo`. An
  application does not need it: a controller's listeners are behind
  `addListener`.

### Fixed

- `Policy.droppable` no longer hands back a job that is not going to do the
  work. The current job stays current for the whole of its unwinding and for
  the state handlers after that, so `cancelAll()` and a fresh request a line
  later — a screen left and opened again, a pull-to-refresh — answered the
  second call with the handle the first had just cancelled: a `Cancelled`
  outcome for a request made a moment ago, and the operation never ran.
  `lastJobWhere`, the protected form of the same search, answers by the same
  rule.

- `cancelAll` reaches the job the engine is about to start. Between taking a
  job off the queue and launching it the engine asks that job's start rules,
  which are the caller's code, and a rule that cancelled everything was
  answered with the very job it had just stopped: the queue no longer held it
  and nothing else did yet, so it started anyway. It is queued work until it is
  launched, and a `cancellable: false` one turns down a `cancelAll` without
  `force` exactly as it does in the queue.

- A `publish` that throws no longer holds back the changes queued behind it.
  They are the state `currentState` already holds, and they stayed unpublished
  until the next change of state, or for good when there was none. The queue is
  drained to the end now, the first failure leaves once it is, and the ones
  after it go to the zone.

- `SoloQueue.removeWhere` and `Solo.lastJobWhere` take their snapshot of the
  queue before asking the predicate rather than while asking it. The predicate
  is the caller's code, and one that removed a job walked into a
  `ConcurrentModificationError`.

- A finished job lets go of its body, of its state handlers and of the job that
  ran it, the way the core lets go of its own. One handle kept in a field —
  what `ctx.each` hands back, what `Policy.droppable` hands back, what a widget
  keeps to read an outcome later — held the whole tree of finished jobs it came
  out of and everything that tree had captured.

- A job one controller's `ctx.unattended` work starts on another controller is
  its own. The queue started it in the zone of that work, so a bare `unawaited`
  error in its body, and a `Solo.onStart` that threw, reached the `onError` of
  the controller whose job started the work. It starts in the zone the work was
  started from now. Inherited from `async_job`.

### Documentation

- The README is a starting page: what the package is, `Install`, `Quick start`,
  `The dozen calls` — one controller holding everything reached for day to
  day — a map of the guides and a table of recipes. The reference it had grown
  moved to `doc/`, one page per subject: [Jobs and the queue](doc/jobs.md),
  [State](doc/state.md), [Cancellation](doc/cancellation.md),
  [Resources and cleanup](doc/resources.md),
  [Children and streams](doc/children.md),
  [Errors and observation](doc/errors.md), [Testing](doc/testing.md) and
  [Camera example](doc/camera.md). The Flutter section went to the package it
  is about, `flutter_solo`.
- Where there is a trap, a section of those pages opens with the version the
  vocabulary of the API leads to and shows what it does, then the one that
  holds. [solo and bloc, side by side](doc/vs-bloc.md) is rebuilt the same way,
  its eleven scenarios each opening with the first attempt, and
  [Accumulating events before a job starts](doc/accumulation.md) gained the
  recipe for commands where only the last one counts.
- One recommendation of `0.2.0` is replaced: a source of external states is no
  longer stopped before `close`. It is guarded with `isFinished` and stopped in
  `onClose`, which serves both close modes.
- The runnable camera example lands a failed or cancelled opening in `Broken`
  through the `onError` and `onCancel` of `run`. `init` and `reopen` used to
  land a failure from a `catch` in the body, which a cancellation never
  reaches: an opening cancelled half way left the camera in `Preparing`, where
  neither of them could start again.

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
  whatever the outcome, `ctx.onDiscard` only when the value reaches nobody, and
  `wait` and `join` take the same two as `dispose` and `discard` for the value
  they hand over — a connection or a file an abandoned action opened is still
  closed. The engine unwinds the stack after the children and before the
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
