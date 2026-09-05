## 1.0.0

Initial release.

- `SoloBase<S>` engine: one root job at a time, exclusive state ownership.
- `Solo<S>` with a broadcast `stream`, delivered on the next microtask.
- Jobs as `async` bodies with a working type `W`, `canStart` and
  `keepWhile` rules, `cancellable: false`.
- `Job<T>` handle: `done`, `value`, `outcome`, `whenCancelled`, `cancel`,
  `ignore`.
- `Outcome<T>`: `Done`, `Failed`, `Cancelled` with `CancelReason`.
- A `Failed` outcome nobody observed goes to the zone that created the job,
  the way Dart reports an unhandled `Future` error. Reading `done` or
  `value`, or calling `ignore`, counts as observing it; `Cancelled` never
  reaches the zone.
- `JobContext`: `state`, `stateAs`, `emit`, `check`, `wait`, `join`,
  `uncancellable`, `onCancel`, `run`, `log`.
- A body does not `await` on its own: every call goes through the context,
  and the member it picks says what a cancellation does to that call.
  `wait` ends the waiting and lets the action run on; `join` waits for all
  of the action and gives up afterwards, so a device call is never left
  mid-flight; `uncancellable` turns the cancellation down for the length of
  the call.
- `wait` and `join` take `ifCancelled`: the value of an action the job gave
  up on goes there instead of on the floor, so a connection or a file that
  action opened is still closed.
- `JobContext.uncancellable` is `wait`'s counterpart: it runs a step that
  cannot be taken back — a payment on its way to the server — with
  cancellation refused, and `close` waits for it.
- `ctx.each(stream, onData)` follows a stream for as long as the job lives:
  an extension on `JobContext`, built out of `wait` and `onCancel`. The
  subscription goes with the job, including the moment it is cancelled.
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
