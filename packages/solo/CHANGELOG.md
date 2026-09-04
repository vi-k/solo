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
- `JobContext`: `state`, `stateAs`, `emit`, `check`, `guard`,
  `uncancellable`, `onCancel`, `run`, `log`.
- `JobContext.uncancellable` is `guard`'s counterpart: it runs a step that
  cannot be taken back — a payment on its way to the server — with
  cancellation refused, and `close` waits for it.
- `JobContext.onCancel` hands a cancellation to something that can really
  stop — a device's cancel token, an HTTP abort. `guard` ends the waiting,
  not the work.
- Child jobs via `ctx.run`; a parent finishes after its children.
- `SoloQueue` with `remove`, `removeWhere`, `clear`, `lastWhere`;
  policies `sequential`, `droppable`, `replace`, `restart`.
- `externalSetState` for hardware listeners; every change re-evaluates the
  rules of running jobs.
- `SoloObserver` and instance hooks; `SoloBase.debug` engine tracing.
- A hook that throws changes nothing: the engine hands its error to the
  current zone and carries on, and the hook next to it is still called.
