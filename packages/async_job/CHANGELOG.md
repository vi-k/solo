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
