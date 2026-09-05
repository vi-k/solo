## 0.1.0

Initial release. The job kernel taken out of `solo` 0.1.0.

- `Job<T>`: a cancellable `Future` with an outcome, children and a
  cooperative cancellation. Created by `Job(body)`, which starts on the
  next microtask, or by `Job.deferred(body)`, which waits for `start()`.
- `Outcome<T>`: `Done`, `Failed`, `Cancelled` with an open `CancelReason`
  and a public `Cancelled.by` for engines built on this one.
- A waiting family that says what a cancellation does to a call:
  `ctx.wait` ends the waiting and not the work, `ctx.join` waits for all
  of the action and gives up afterwards, `ctx.uncancellable` refuses,
  `ctx.onCancel` hands the cancellation to whatever can really stop, and
  `ctx.check` gives up where there is no call to wrap. `ctx.each` follows
  a stream for as long as the job lives.
- `ifCancelled` on the job catches a value the body returned after its
  cancellation had already arrived.
- Children through `ctx.run`: the parent finishes after them, a
  cancellation cascades, and a child that is not cancellable refuses it.
- `JobObserver` with `onStart`, `onFinish`, `onError` and `onLog`; a
  child inherits the parent's. A `Failed` outcome nobody observed goes to
  the zone that created the job.
- `JobBase<T>` and `JobContextBase` for an engine of a domain to
  subclass: the protected surface, the virtual checkpoint `check()`, and
  the hooks `started()`, `finished()` and `adoptedBy()`.
