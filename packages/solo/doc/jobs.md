# Jobs and the queue

## Jobs and results

A `Job<T>` represents one operation and its eventual outcome. It is not a
`Future`: calling `profile.load()` without `await` is allowed. Choose how
to handle its result at the call site:

| Member | Use |
| --- | --- |
| `job.value` | Await `T`; throws on failure or cancellation. |
| `job.done` | Await an `Outcome<T>` without throwing. |
| `job.outcome` | Read the outcome synchronously after completion. |
| `job.cancel()` | Request cancellation and wait for completion. |
| `job.ignore()` | Mark the outcome as handled without waiting. |

`Outcome<T>` has three cases. `Done` carries the value, `Failed` carries
the error and stack trace, and `Cancelled` carries the cancellation reason:

```dart
switch (await profile.load().done) {
  case Done(:final value):
    print('loaded $value');
  case Failed(:final error):
    print('not loaded: $error');
  case Cancelled(:final reason):
    print('gave up: $reason');
}
```

A failed job does not stop the queue. Its error is reported and the next
job can run. Cancellation is a separate outcome: closing a controller,
removing a queued job or invalidating its state rules can all cancel work
without indicating an application failure.

Every failure reaches the controller's error hook and observer. A failed
job whose outcome is never accessed through `done`, `value` or `ignore()`
also reports an unhandled error to the Dart zone in which it was created.
Use `ignore()` when error reporting elsewhere is sufficient; leaving a
job unawaited does not by itself mark the error as handled. See
[Error reporting and observation](errors.md).

### Creating and scheduling jobs

Within a controller, `job(...)` creates a job without scheduling it,
`add(job, policy: ...)` queues a job, and `run(...)` combines both steps.
All three return `SoloJob<T>`, which implements `Job<T>` and adds
`isQueued`. A controller normally exposes domain methods such as `load()`
or `setZoom()` so callers do not need to assemble jobs themselves.

A job can have a `key` for queue policies and a lazy `describe` callback
for diagnostics. For example, `describe: () => 'zoom: $zoom'` supplies the
label used by logs, observers and `toString()`: `Job(key: label)`.
Without a description, the representation is `Job(key)`.

## Queue and policies

A job added to a controller's queue is a root job. Only one root job runs
at a time. It holds the queue until its body, children, cleanup and final
state handler finish. Child jobs can run within that interval; they are
described in [Children and streams](children.md).

Each call chooses a policy. Policies other than `sequential` use the job's
key to find related work:

| Policy | When a job with the same key already exists |
| --- | --- |
| `Policy.sequential` | Add the new job to the queue. |
| `Policy.droppable` | Return the existing queued or running job; discard the new one. |
| `Policy.replace` | Remove cancellable queued jobs with that key, then enqueue the new job. |
| `Policy.restart` | Do the same as `replace` and request cancellation of the running job with that key. |

`restart` requests cancellation when the new job is submitted. The new
job still waits for the current job to finish; their bodies do not overlap.
A job that refuses cancellation can therefore delay its replacement.

Use a distinct key for each operation and result type. Reusing a key for
both `Job<String>` and `Job<void>` makes `droppable` throw
`ArgumentError`, before the new job is touched, so it can be added again
under a key of its own. An enum with one key per method is a convenient
way to avoid this. A non-sequential policy with a null key throws
`ArgumentError` too, and both checks work in release builds.

A key is any object, compared with `==`, so a record gives a policy the
identity of one request rather than of the operation. `droppable` on
`(_Op.load, id)` drops a second load of the same profile and lets a load
of another one through, where a bare `_Op.load` would have dropped both:

```dart
SoloJob<Profile> load(String id) => run<Loaded, Profile>(
      key: (_Op.load, id),
      policy: Policy.droppable,
      (ctx) async => ctx.wait(() => api.load(id)),
    );
```

The controller's `queue` exposes `jobs`, `remove`, `removeWhere`, `clear`
and `lastWhere`. Removal methods affect queued jobs only. They preserve
jobs with `cancellable: false` unless called with `force: true`.
`add(job, first: true)` inserts at the front. Time-delayed accumulator
groups can let ready jobs pass; see [Event accumulation](accumulation.md).
