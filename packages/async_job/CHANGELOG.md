## Unreleased

- The README is a starting page: what a job is, why a plain `Future` does
  not cover it — now shown as the flag that asks and the job that answers
  — `Install`, `Quick start` and a map of the guides. The reference
  material moved to `doc/`: `outcomes.md`, `cancellation.md`,
  `children.md`, `cleanup.md`, `observing.md`, `extending.md`. Nothing was
  dropped, and every section now starts with the code it is about.
- **Fix:** `ctx.join` releases the value through `dispose` or `discard`
  when the checkpoint after the action throws anything, not only a
  `Cancelled`. A rule of a domain that threw instead of answering used to
  cost the job the resource it already held: the value reached no body and
  was registered on no cleanup stack.
- **Breaking:** add the protected `JobBase.inUncancellableSection`, for an
  engine that waits for a job and wants to say why. Adding a member to a
  class meant to be extended is breaking on its own: a subclass with a
  member of that name stops compiling.

## 0.2.0

- **Breaking:** `ctx.run(child)` returns `Future<T>` instead of the child's
  handle. Use `await ctx.run(child)` to await its value, children and cleanup;
  successful completion checks the parent's cancellation before continuing.
  Keep the original `child` for cancellation or outcome inspection. Handle
  the returned future's errors, or use `.ignore()` for an intentional
  concurrent start whose result is unused. Start validation still throws
  synchronously. `ctx.each` continues to return its child handle immediately.
- Add protected `JobContextBase.startChild` for domain adoption and start
  checks shared by `run` and `each`, without observing the child's result.

- Add `Job.then` with a separate context per continuation, forward outcome
  propagation and cancellation in both directions. Cancelling the tail
  waits for unfinished predecessors and their cleanup. `ChainCancelReason`
  retains each adjacent cancellation in `cause`. Continuations are core
  root jobs with their own optional observer, independent of domain queues.

- **Breaking:** `ctx.each(stream, (child, event) { ... })` returns a child
  `Job<void>` immediately. Await `.value` for a throwing result, inspect
  `.done` for the outcome, or call `.cancel()` to stop it separately.
  The callback receives the child's context. The parent waits for the
  child even when its body does not await it, and observers see the child.
- Cancelling `each` immediately removes the subscription and stops event
  delivery, then waits for the running callback before child completion
  and cleanup. Use child context checkpoints to respond to cancellation;
  a plain `await` cannot be interrupted. Source cleanup from subscription
  cancellation is still not awaited.
- **Breaking:** `each` is a `JobContext` method; the `JobStream` extension
  is removed. `JobContextBase.createEachJob` is a protected factory for
  domain engines. As with `run`, `each` is rejected from `unattended`
  and after the parent body ends.
- **Breaking:** reasons are extensible classes: `ManualCancelReason`,
  `ParentCancelReason` and `HandlerCancelReason`. Replace named constants
  with constructors and inspect types instead of comparing names.
  `CancelReason` is abstract; subclasses can carry arbitrary data.
- `job.cancel(reason: reason)` accepts a custom reason, preserved by
  identity in callbacks and outcomes. A body throwing `Cancelled.by` now
  preserves its explicit reason as well.
- Parent cancellation and a child's cancellation escaping the body retain
  the source `Cancelled` in `ParentCancelReason.cause` and
  `HandlerCancelReason.cause` respectively.
- **Breaking:** replace the `Job.whenCancelled` future with
  `job.whenCancelled((cancelled) { ... })`. The callback receives the full
  `Cancelled` and runs synchronously; registering after cancellation calls
  it immediately. The returned function unregisters the callback.
- Release unused cancellation listeners when a job finishes without
  cancellation. Registration does not observe a failed outcome.
- Route synchronous listener errors through `onError`, or the creation
  zone without an observer, as for `ctx.onCancel`. Async callbacks are not
  awaited.

## 0.1.0

Initial release. The job kernel taken out of `solo` before its own
first release.

- `Job<T>`: a cancellable `Future` with an outcome, children and a
  cooperative cancellation. Created by `Job(body)`, which starts on the
  next microtask, or by `Job.deferred(body)`, which waits for `start()`.
- `Outcome<T>`: `Done`, `Failed`, `Cancelled` with an open `CancelReason`
  and a public `Cancelled.by` for engines built on this one.
- A waiting family that says what a cancellation does to a call:
  `ctx.wait` ends the waiting and not the work, `ctx.join` waits for all
  of the action and gives up afterwards, `ctx.uncancellable` holds the
  cancellation until the step is over,
  `ctx.unattended` does not wait at all and hands the work to the engine,
  `ctx.onCancel` hands the cancellation to whatever can really stop, and
  `ctx.check` gives up where there is no call to wrap. `ctx.each` follows
  a stream for as long as the job lives, waiting for an asynchronous
  `onData` and taking the subscription with it whatever the outcome.
- A cleanup stack: `ctx.onDispose` releases whatever the outcome,
  `ctx.onDiscard` only when the value reaches nobody, and `wait` and
  `join` take the same two as `dispose` and `discard` for the value they
  hand over. The engine unwinds the stack after the children and before
  the outcome, waiting for every disposer; `ctx.disown(value)` takes a
  registration back when the body hands the value over itself.
- Children through `ctx.run`: the parent finishes after them, a
  cancellation cascades, and a child that is not cancellable refuses it.
- `JobObserver` with `onStart`, `onFinish`, `onError` and `onLog`; a
  child inherits the parent's. A `Failed` outcome nobody observed goes to
  the zone that created the job, and so does an error with nowhere else to
  go when there is no observer — but never a `Cancelled`: a cancellation
  is a decision somebody made, not a failure, and the observer is the only
  place it is heard.
- `ctx.unattended(action)` for work the body starts and does not wait
  for: it runs in an error zone of its own, and whatever it leaves
  uncaught — now, or long after the job is over — reaches `onError`
  instead of the process. `ctx.run` and `ctx.uncancellable` are refused
  from inside it, and a job created in there reports to the zone the body
  runs in, not to the observer of the job that started the work.
- `JobBase<T>` and `JobContextBase` for an engine of a domain to
  subclass: the protected surface, the virtual checkpoint `check()`, and
  the hooks `started()`, `finished()` and `adoptedBy()`. The protected
  surface also carries `reportToZone`, for a domain whose own route for an
  error with nowhere to go ends with nobody — it keeps a `Cancelled` out of
  the zone exactly as the core does, so a domain does not write that rule
  again — and `throwIfUnattended`, for a member of its context that must
  not be called from unattended work.
