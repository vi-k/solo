# Jobs and the queue

## Jobs and results

A `Job<T>` represents one operation and its eventual outcome. The call queues
the work and hands back the handle: `await` reads how the operation ended, it
does not set it going. It is not a `Future` — a job can be cancelled, and its
failure reaches the controller whether or not anybody waits for it.

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

`Outcome<T>` has those three cases: `Done` carries the value, `Failed` the
error and stack trace, `Cancelled` the cancellation reason.

| Member | Use |
| --- | --- |
| `job.value` | Await `T`; throws on failure or cancellation. |
| `job.done` | Await an `Outcome<T>` without throwing. |
| `job.outcome` | Read the outcome synchronously after completion. |
| `job.cancel()` | Request cancellation and wait for completion. |
| `job.ignore()` | Mark the outcome as handled without waiting. |

A failed job does not stop the queue. Its error is reported and the next job
can run. Cancellation is a separate outcome: closing a controller, removing a
queued job or invalidating its state rules can all cancel work without
indicating an application failure.

Every failure reaches the controller's error hook and observer. A failed job
whose outcome is never accessed through `done`, `value` or `ignore()` also
reports an unhandled error to the Dart zone in which it was created. Use
`ignore()` when error reporting elsewhere is sufficient; leaving a job
unawaited does not by itself mark the error as handled. See
[Error reporting and observation](errors.md).

### Creating and scheduling jobs

```dart
// Assembled now, queued after: two steps, for a job to hold on to.
final saving = job<Ready, void>(key: _Op.save, (ctx) => ctx.join(store.save));
add(saving, policy: Policy.droppable);

// Or both at once, which is what a controller method normally does.
SoloJob<void> setZoom(double zoom) => run<Ready, void>(
      key: _Op.zoom,
      // Lazy, and only for diagnostics: built when a log asks for it.
      describe: () => 'zoom: $zoom',
      (ctx) => ctx.join(() => camera.zoom(zoom)),
    );
```

All three return `SoloJob<T>`, which implements `Job<T>` and adds `isQueued`. A
controller normally exposes domain methods such as `load()` or `setZoom()` so
callers do not need to assemble jobs themselves.

A `key` is what queue policies match on, and `describe` supplies the label used
by logs, observers and `toString()`: `Job(key: label)`. Without a description
the representation is `Job(key)`.

## Queue and policies

A job added to a controller's queue is a root job. Only one runs at a time.
Which of them survives a second call is the policy's decision:

```dart
enum _Op { load, save, zoom, seek, stop, pause }

// sequential, the default: one after another, in the order asked for.
SoloJob<void> save() =>
    run<Ready, void>(key: _Op.save, (ctx) => ctx.join(store.save));

// droppable: a second load of the same profile returns the first job.
SoloJob<Profile> load(String id) => run<Ready, Profile>(
      key: (_Op.load, id),
      policy: Policy.droppable,
      (ctx) => ctx.wait(() => api.load(id)),
    );

// replace: the queued zoom goes, a running one is left alone.
SoloJob<void> setZoom(double zoom) => run<Ready, void>(
      key: _Op.zoom,
      policy: Policy.replace,
      (ctx) => ctx.join(() => camera.zoom(zoom)),
    );

// restart: the same, and the running one is asked to stop as well.
SoloJob<void> seek(Duration position) => run<Ready, void>(
      key: _Op.seek,
      policy: Policy.restart,
      (ctx) async {
        final token = CancelToken();
        ctx.onCancel(token.cancel);
        // Wait for the device to stop before the next seek starts.
        await ctx.join(() => camera.seek(position, cancelToken: token));
      },
    );
```

| Policy | When a job with the same key already exists |
| --- | --- |
| `Policy.sequential` | Add the new job to the queue. |
| `Policy.droppable` | Return the existing queued or running job; discard the new one. |
| `Policy.replace` | Remove cancellable queued jobs with that key, then enqueue the new job. |
| `Policy.restart` | Do the same as `replace` and request cancellation of the running job with that key. |

A root job holds the queue until its body, children, cleanup and final state
handler finish. Child jobs can run within that interval; they are described in
[Children and streams](children.md).

`restart` requests cancellation when the new job is submitted. The new job
still waits for the current job to finish; their bodies do not overlap. A job
that refuses cancellation can therefore delay its replacement — and so can one
that has nothing to hand the request to: a `join` around a call the request
cannot reach waits that call out to the end, and the outcome is `Cancelled` all
the same. The token above is the way in; `ctx.wait` is the other, for an
operation that can be left to finish on its own. Both are on
[Cancellation](cancellation.md).

A key is any object, compared with `==`, so the record `(_Op.load, id)` above
gives the policy the identity of one request rather than of the operation:
`droppable` drops a second load of the same profile and lets a load of another
one through, where a bare `_Op.load` would have dropped both.

Use a distinct key for each operation and result type. A `Job<int>` handed to
`droppable` under a key a `Job<String>` already holds throws `ArgumentError`,
and it throws before the job is taken: nothing was queued and nothing was
cancelled, so the same handle can still be added — under `Policy.sequential`,
or later, once that key is free. A key is fixed when the job is made, so the
collision itself is settled where the two jobs are built; an enum with one key
per method is a convenient way not to have it. A non-sequential policy with a
null key throws `ArgumentError` too, and both checks work in release builds.

The queue itself is the controller's own, and a method can work it directly:

```dart
SoloJob<void> stop() {
  // What is waiting right now.
  print(queue.length);
  // Drop what this command makes pointless...
  queue.removeWhere((job) => job.key == _Op.zoom);
  // ...and jump the line with the stop itself.
  return add(
    job<Ready, void>(key: _Op.stop, (ctx) => ctx.join(camera.stop)),
    first: true,
  );
}
```

`first` passes what is waiting and nothing else. A zoom that is already running
is neither removed by `removeWhere` nor interrupted by `first`: the stop starts
when that zoom finishes. Reaching a running job is cancellation —
[Cancellation](cancellation.md).

`queue` exposes `jobs`, `length`, `isEmpty`, `isNotEmpty`, `remove`,
`removeWhere`, `clear` and `lastWhere`. Removal methods affect queued jobs only
— the running job is not theirs to touch — and they preserve jobs with
`cancellable: false` unless called with `force: true`.

The order in `jobs` is not the order jobs will run in: a job waiting for an
accumulation window can be passed by a ready one standing behind it, so the
head of the queue is not always what starts next. See
[Event accumulation](accumulation.md).

### Pausing the queue

```dart
Completer<void>? _gate;

void pause() {
  if (_gate != null) return;
  final gate = _gate = Completer<void>();
  run<Ready, void>(key: _Op.pause, (ctx) => ctx.wait(() => gate.future));
}

void resume() {
  _gate?.complete();
  _gate = null;
}
```

There is no pause in the API, and a job waiting on a `Completer` is one. It
holds the head of the queue; everything submitted behind it waits, and
completing the `Completer` lets the queue run in the order it was asked for.
The cases:

| What you do | What happens |
| --- | --- |
| `pause()`, then submit three jobs | The three wait, and no outcome is reached. |
| `resume()` | They run, in the order they were submitted. |
| `queue.clear()` while paused | The queue empties and the pause stands: the gate is the running job, not a queued one. |
| `close()` while paused | It comes back without a `resume`: the gate is cancellable, and `ctx.wait` hands it the cancellation. |
| `cancelAll(force: true)` | The gate goes with everything else and the queue moves on, with nobody having opened it. |

What the gate does not give you is a name. The observer sees an ordinary job
start, and `pending` answers with the gate rather than with work, so a screen
showing what runs shows the pause instead. Whether the controller is paused is
yours to keep.

`canStart` is not a pause. A job whose rule does not fit the state is not held
back: it is cancelled where it stands, with `Cancelled(rules: canStart)`, and
the queue empties instead of filling up. A pause built on it loses the work
silently.
