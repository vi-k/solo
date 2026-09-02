## 1.0.0

Initial release.

- `SoloBase<S>` engine: one root job at a time, exclusive state ownership.
- `Solo<S>` with a broadcast `stream`, delivered on the next microtask.
- Jobs as `async` bodies with a working type `W`, `canStart` and
  `keepWhile` rules, `cancellable: false`.
- `Job<T>` handle: `done`, `value`, `outcome`, `whenCancelled`, `cancel`.
- `Outcome<T>`: `Done`, `Failed`, `Cancelled` with `CancelReason`.
- `JobContext`: `state`, `stateAs`, `emit`, `check`, `guard`, `run`, `log`.
- Child jobs via `ctx.run`; a parent finishes after its children.
- `SoloQueue` with `remove`, `removeWhere`, `clear`, `lastWhere`;
  policies `sequential`, `droppable`, `replace`, `restart`.
- `externalSetState` for hardware listeners; every change re-evaluates the
  rules of running jobs.
- `SoloObserver` and instance hooks; `SoloBase.debug` engine tracing.
