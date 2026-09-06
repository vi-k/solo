## 0.2.0

The first published release. 0.1.0 never left the tree, so nothing below
is a migration anybody has to make; what changed since it is at the end,
for a tree that followed the package before it went out.

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
  mid-flight; `uncancellable` holds the cancellation for the length of
  the call and gives up once the step is over.
- `wait` and `join` take `ifCancelled`: the value of an action the job gave
  up on goes there instead of on the floor, so a connection or a file that
  action opened is still closed.
- `JobContext.uncancellable` is `wait`'s counterpart: it runs a step that
  cannot be taken back — a payment on its way to the server — with the
  cancellation held until the step is over, and `close` waits for it.
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

### Since 0.1.0

- The job kernel now lives in `package:jobs` and is re-exported whole:
  `package:solo/solo.dart` stays the only import, and no code written
  against the README needs to change. What moved is the job itself — its
  lifecycle, its context, the outcomes and the observer; what stayed is
  the state, the queue and the rules.
- `CancelReason` is a class, not an enum: an engine built on the job
  kernel declares reasons of its own, and reasons are equal by name.
  `CancelReason.rules` and `CancelReason.closed` move to
  `SoloCancelReason`; `values` and `index` are gone, and
  `CancelReason.manual.toString()` is now `manual`, not
  `CancelReason.manual`. `Cancelled.toString()` is unchanged.
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
- `job(...)` and `run(...)` take `ifCancelled`: the value a body returned
  after its cancellation had already arrived goes there instead of being
  dropped. The outcome stays the cancellation, and `close` waits for the
  disposer.
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
