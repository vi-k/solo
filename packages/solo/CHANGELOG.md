## 0.2.0

- Add `AccumulationTiming.debounce` and `.throttle` to `collect` and
  `accumulate`. Debounce seals a group after a pause between events;
  throttle spaces actual group starts. Waiting groups let ready jobs
  pass, while handlers, children and cleanup remain sequential.
  `collect` retains every event; `accumulate` retains the `merge` result.
  Closing cancels timing timers and queued groups without a final batch.

- **Breaking:** `ctx.run(child)` returns the child's result as `Future<T>`.
  Replace `await ctx.run(child).value` with `await ctx.run(child)`; keep the
  original child handle to cancel it or inspect its outcome. After success,
  `run` checks the parent's cancellation and state rules before returning.
  Concurrent starts must handle or explicitly ignore the returned future.
  Controller `run` and `ctx.each` still return job handles immediately.

- Add `collect` and `accumulate` factories returning `SoloAccumulator`:
  gather events in a list or merge them into one value before execution.
  `AccumulationPolicy` selects adjacent grouping, replacement at the
  queue's tail with data transfer, or joining an existing queued group.
  Groups use ordinary `SoloJob` lifecycle, state rules and cancellation.
- Re-export `Job.then` and `ChainCancelReason` from the core. Continuations
  support cancellation chains and have their own `JobContext`; they do not
  inherit controller state, rules, observers or a queue slot.

The first published release. 0.1.0 never left the tree, so nothing below
is a migration anybody has to make; what changed since it is at the end,
for a tree that followed the package before it went out.

- `SoloBase<S>` engine: one root job at a time, exclusive state ownership.
- `Solo<S>` with a broadcast `stream`, delivered on the next microtask.
- Jobs as `async` bodies with a working type `W`, `canStart` and
  `keepWhile` rules, `cancellable: false`.
- Keep a replacement cancelled by a synchronous listener out of the queue,
  so it cannot absorb a later `droppable` job.
- Requires `async_job: ^0.2.0`: `job.whenCancelled(callback)` registers a
  synchronous listener receiving `Cancelled` and returns an unregister
  function.
- `Job<T>` handle: `done`, `value`, `outcome`, `whenCancelled`, `cancel`,
  `ignore`.
- `Outcome<T>`: `Done`, `Failed`, `Cancelled` with `CancelReason`.
- A `Failed` outcome nobody observed goes to the zone that created the job,
  the way Dart reports an unhandled `Future` error. Reading `done` or
  `value`, or calling `ignore`, counts as observing it; `Cancelled` never
  reaches the zone.
- `JobContext` of the kernel: `check`, `wait`, `join`, `uncancellable`,
  `unattended`, `onCancel`, `run`, `each`, `log`.
- `SoloContext<S, W>` on top of it, where the state lives: `state`,
  `stateAs`, `emit`.
- A body does not `await` on its own: every call goes through the context,
  and the member it picks says what a cancellation does to that call.
  `wait` ends the waiting and lets the action run on; `join` waits for all
  of the action and gives up afterwards, so a device call is never left
  mid-flight; `uncancellable` holds the cancellation for the length of
  the call and gives up once the step is over; `unattended` does not wait
  at all and hands the work to the engine, which hears it fail even after
  the job is over.
- `ctx.unattended(action)` for work a body starts and does not wait for.
  It runs in an error zone of its own, and whatever it leaves uncaught —
  now, or long after the job is over — reaches `onError` instead of the
  process.
- **Behaviour change.** With no `SoloBase.observer` and no override of
  `SoloBase.onError`, an error with nowhere else to go no longer stops in
  the empty hook: it goes to the zone the job was created in, the way the
  core reports one when a job has no observer. That covers a disposer, an
  `onCancel` callback, a late failure of an abandoned call or of
  unattended work, and a `canStart` or `keepWhile` that threw instead of
  answering while the job runs. A `Cancelled` is the one exception and
  never goes there. Install an observer, or override the hook, and the
  route is yours again; call `super.onError(...)` from the override to
  keep it. A rule that throws *before* the job starts is not on this
  route at all: it becomes a `Failed` outcome and reaches the zone as any
  unobserved failure does, whatever the observer.
- A cleanup stack instead of a `finally` in the body: `ctx.onDispose`
  releases whatever the outcome, `ctx.onDiscard` only when the value
  reaches nobody, and `wait` and `join` take the same two as `dispose` and
  `discard` for the value they hand over — a connection or a file an
  abandoned action opened is still closed. The engine unwinds the stack
  after the children and before the outcome, and `close` waits for it;
  `ctx.disown(value)` takes a registration back when the body hands the
  value over itself.
- `JobContext.uncancellable` is `wait`'s counterpart: it runs a step that
  cannot be taken back — a payment on its way to the server — with the
  cancellation held until the step is over, and `close` waits for it.
- **Breaking:** `ctx.each(stream, (child, event) { ... })` returns a child
  `Job<void>` immediately. Await `.value` for a throwing result, inspect
  `.done`, or cancel the subscription separately through `.cancel()`.
  The callback receives a `SoloContext<S, W>` retaining the parent's
  working type and `keepWhile`, without inheriting `canStart`.
  The parent waits for this child even without an explicit await, and
  observers see the child. Parent cancellation cascades to it.
- Cancelling `each` removes the subscription immediately, then waits for
  the running callback before child completion and cleanup. Use child
  context checkpoints to respond to cancellation; a plain `await` can
  delay cancellation and `close()`. Source cleanup from subscription
  cancellation is still not awaited. `each` is now a context method and
  follows `run`'s restrictions on when and where children can start.
- `JobContext.onCancel` hands a cancellation to something that can really
  stop — a device's cancel token, an HTTP abort. `wait` ends the waiting,
  not the work.
- Child jobs via `ctx.run`; a parent finishes after its children.
- `SoloQueue` with `remove`, `removeWhere`, `clear`, `lastWhere`;
  policies `sequential`, `droppable`, `replace`, `restart`.
- `externalSetState` for hardware listeners; every change re-evaluates the
  rules of running jobs.
- `SoloObserver` and instance hooks; `SoloBase.debug` engine tracing.
- A hook that throws changes nothing: the engine hands its error to the
  current zone and carries on, and the hook next to it is still called.

### Since 0.1.0

- The job kernel now lives in `package:async_job` and is re-exported whole:
  `package:solo/solo.dart` stays the only import. Code using the old reason
  API must migrate to the reason classes. The job's lifecycle, context,
  outcomes and observer moved to the kernel; the state, queue and rules
  stay in `solo`.
- `CancelReason` is an extensible class hierarchy: `ManualCancelReason`,
  `ParentCancelReason` and `HandlerCancelReason` from the core, plus
  `RulesCancelReason` and `ClosedCancelReason` from `solo`. Inspect types;
  `name` is only a log label, with no equality by name. Custom subclasses
  can carry arbitrary data through `job.cancel(reason: reason)`.
  Parent and child propagation retain the original cancellation in `cause`.
- `Cancelled.by({reason, started, description, stackTrace})` is public:
  an engine of a domain builds cancellations with a reason of its own.
- `JobContext<S, W>` is renamed to `SoloContext<S, W>`, and the name
  `JobContext` now belongs to the interface of the kernel: cancellation,
  the waiting family and children, without the state. `SoloContext`
  implements it and adds `state`, `stateAs` and `emit`. Job bodies do not
  write the name, so code written against the README keeps compiling.
- The job and its context are split along the seam the kernel will be
  taken out at: `JobBase<T>` and `JobContextBase` carry the lifecycle, the
  waiting family, the children and the outcome, and the solo subclasses add
  the state, the rules and the queue. Nothing moves in the public API of a
  controller.
- The list of children a job waits for now shrinks as they finish: a
  long-lived job starting children in a loop no longer grows one entry per
  child. The description of a parent's own outcome is unchanged — the link
  from an outcome to the child that carried it lives in an `Expando`, so a
  child without a key still shows in it.
- A value a body returned after its cancellation had already arrived is
  released rather than dropped: the body registers it on the cleanup
  stack, the outcome stays the cancellation, and `close` waits for the
  release.
- A job says who may adopt it: `ctx.run(child)` refuses a job of another
  controller with `ArgumentError` and a job still waiting in the queue with
  `StateError`, and a job of `solo` is refused by a context of the bare
  kernel. A child without an observer of its own inherits the parent's.
- `JobBase.debug` traces the life of a job, `SoloBase.debug` the queue, the
  state and the closing. Set both to follow both.
- `JobObserver` is the observer of a single job: `onStart`, `onFinish`,
  `onError` and `onLog`, without the controller in the signatures. A
  controller feeds its own `SoloObserver` and its instance hooks from it,
  so nothing changes for a user of `solo`.
- `isQueued` moves from `Job<T>` to the new `SoloJob<T>`, returned by
  `job`, `add` and `run`. The queue is the controller's, not the job's.
  `JobStatus` is public and has three values: a queued job is `created`
  until it starts, and `isQueued` is computed from the queue itself —
  inside `canStart` a job taken from the queue is no longer queued.

## 0.1.0

Never published.
