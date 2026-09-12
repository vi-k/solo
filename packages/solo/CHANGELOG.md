## Unreleased

- `doc/vs-bloc.md` is rebuilt around the mistake. Every one of the ten
  scenarios now opens with "The first attempt" — the code the requirement
  invites, and the measured proof that it does not hold — before the
  implementation that does. Eight of those attempts are new runnable snippets:
  two registrations with a transformer each, one registration with none, a chat
  handler without its `isClosed` guard, a player with a registration per
  command, a leaving flag instead of a screen generation, `droppable()` with a
  completer that nobody completes, one funnel for a failure that must not wait,
  a restartable loop without `emit.isDone`. Section 1 also quotes the order of
  the run, so that the lost note is explained by what happened rather than
  asserted.

- Two stale snippets in `doc/vs-bloc.md` fixed: the recorder and the telemetry
  observer still overrode `onChange(previous, current)`, which has taken a
  `SoloTransition` since 0.2.0 and no longer compiled.

- `doc/children.md` adds what a chain costs on a controller: inside a body
  `ctx.run` takes jobs of that controller alone, so a continuation is turned
  away there as a job of nobody's; and the queue does not wait for a tail — the
  slot is freed when the root job finishes, and the next queued job starts
  while the continuation still has to run.

- A recipe for `doc/state.md`: a delivery of your own. `publish` is where a
  change leaves the engine, and a `SoloBase` subclass that overrides it
  notifies listeners inside the change — what `SoloListenable` does for
  Flutter, in pure Dart and in forty lines. Three things such an override owes
  stand in a table beside it: a listener's failure must not leave `publish`, or
  the re-evaluation of the rules that follows the call costs a job the
  cancellation the new state owes it; the pass walks a copy and skips what was
  removed on the way; `close` drops the listeners for good. No API was added —
  `publish` was the extension point all along, and it had not been written down
  anywhere outside the package's own records.

- **Breaking:** the controller's synchronous read is `currentState`, not
  `state`. A job body is a closure inside a method of the controller, so every
  member of the controller is in scope there, and a read named `state` looked
  exactly like the checked `ctx.state` while doing none of its work: no
  `Cancelled` for a job that had lost the state, no `keepWhile` check, and the
  whole of `S` instead of the job's working type `W`. Under the new name that
  mistake is a compile error. Reads through the context, the `state` parameters
  of `canStart`, `keepWhile`, `onError` and `onCancel`, and `externalSetState`
  are unchanged. No deprecated alias is kept: one that still compiled inside a
  body would leave the hole open.

- A recipe for `doc/errors.md`: why cancellation was slow. An observer that
  stamps the clock in `Job.whenCancelled` and subtracts in `onFinish` reports
  the wait the caller of `cancel` or `close` sat through — 290 ms against 0 on
  a 300 ms wait cancelled 10 ms in, which is the difference between a bare
  `await` and the same call through `ctx.wait`. `SoloPending` reports while the
  wait is on; this reports once it is over, where nobody is watching. A step
  held by `ctx.uncancellable` is not counted, and a job dropped before it
  started is not reported at all. The stamp lives in an `Expando`, so it goes
  with the job and there is nothing to clean up. No API was added: the hooks it
  needs were already there.

- The README is a starting page again: what the package is, `Install`,
  `Quick start`, `The dozen calls` — one controller holding everything reached
  for day to day — and a map of the guides. The reference material it grew over
  the releases moved to `doc/`, one page per subject: `jobs.md`, `state.md`,
  `cancellation.md`, `resources.md`, `children.md`, `errors.md`, `testing.md`,
  `flutter.md`, `camera.md`. Nothing was dropped; the bloc correspondence table
  now opens `doc/vs-bloc.md` and the accumulation API opens
  `doc/accumulation.md`.
- Every page in `doc/` starts with the code it is about, and the rules that
  lived only in prose became tables: handler eligibility, where a throwing
  state rule is heard, what each waiting method does to the operation behind
  it. The sections that had no code at all — external state, closing a
  controller, protecting a step, background work — have it now, compiled and
  run before it was written down.
- Document what a job key can be: any object compared with `==`, so a record
  gives a policy the identity of one request — `(_Op.load, id)` — rather than
  of the operation.
- Document commands where only the last one counts, in `doc/accumulation.md`: a
  burst that cancels itself out never becomes jobs to take back, and what to do
  when they are separate jobs after all. A recipes table in the README points
  at this and at nine other situations.
- **Breaking:** `SoloBase.close` takes a `SoloCloseMode`. Calls are unchanged —
  the default is `SoloCloseMode.cancel`, which is what `close` always did — but
  an override of `close` has to take the parameter too. `SoloCloseMode.drain`
  closes by running what is already queued instead of dropping it: no new root
  job is taken from the call onwards, and the ones accepted before it go by the
  usual rules, children, cleanup and accumulation windows included. A plain
  `close()` over a running drain stops it where it is. `SoloBase.isDraining`
  says whether one is running. Running the queue is not a promise of delivery:
  a buffer that keeps events until the sending is confirmed is built on top of
  this.
- **Breaking:** the change hooks take a `SoloTransition<S>` instead of a pair
  of states: `SoloBase.onChange(transition)` and
  `SoloObserver.onChange(solo, transition)`. Beside `previous` and `current` it
  carries `job` — whose `emit` made the change, `null` for an
  `externalSetState`, and a child rather than the root it belongs to — and
  `revision`, which grows by one per change and orders two transitions even
  when a hook changed the state again from inside the first. The engine knew
  both and told nobody, and neither can be worked out from outside. Migration:
  `previous` becomes `transition.previous`, `current` becomes
  `transition.current`.
- Add `SoloBase.pending`: a `SoloPending` snapshot of the job the controller is
  waiting for — its phase (body, children, cleanup, or unknown), the
  cancellation it carries, a `ctx.uncancellable` section holding one back, and
  whether it was created `cancellable: false`. For a `close` that has not come
  back. It reports what the engine knows and says `SoloPhase.unknown` where it
  knows nothing, rather than guessing.
- **Breaking:** setting `SoloBase.observer` no longer takes an error with
  nowhere else to go off its default route to the zone. Watching is not
  answering: an observer set for a log used to switch reporting off for the
  whole process without saying so. `SoloBase.errorHandler` is the new seam that
  answers for such an error — one handler for the process, set once at startup
  — and with nobody set there the error reaches the zone the job was created
  in, observer or no observer. An observer that used to rely on the old silence
  now needs `errorHandler` set as well.
- **Breaking:** `Policy.droppable` throws `ArgumentError`, not `TypeError`,
  when the key it finds belongs to a job of another result type — and it throws
  before the new job is taken, so a job refused this way is untouched and can
  be added again under a key of its own. It used to finish the new job as a
  duplicate first and then refuse to hand anything back, leaving the caller
  with an error and no job at all.

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
- `JobContext.onCancel` hands a cancellation to something that can really stop
  — a device's cancel token, an HTTP abort. `wait` ends the waiting, not the
  work.
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
