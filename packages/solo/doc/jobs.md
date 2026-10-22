# Jobs and the queue

A method of a controller queues a job and returns its handle. This page covers
the handle, the queue and the policies that decide what a second call does to
the first.

## Jobs and results

A `Job<T>` represents one operation and its eventual outcome. A method of a
controller queues the work and hands back the handle; `profile.load()` below is
the one from the
[Quick start](https://github.com/vi-k/solo/blob/main/packages/solo/README.md#quick-start)
in the package README. Awaiting `done` or `value` of the handle reads how the
operation ended, it does not set the operation going. The handle is not a
`Future`: a job can be cancelled, and its failure reaches the controller
whether or not anybody waits for it.

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
| `job.outcome` | Read the outcome synchronously; `null` until the job has finished. |
| `job.cancel()` | Request cancellation and wait for completion. |
| `job.ignoreFailure()` | Keep the failure of a job nobody awaits from being reported as unhandled. |
| `job.whenCancelled(callback)` | Hear the cancellation the moment the job accepts it, running or still queued. |
| `job.whenFinished(callback)` | Hear the end with the outcome, without observing a failure. |

A failed job does not stop the queue. Its error is reported and the next job
can run. Cancellation is a separate outcome: closing the controller, removing a
queued job or a state the job's rules do not accept can all end work
`Cancelled`, and none of them says that anything failed.

Every failure reaches the `onError` hook of the controller and of
`Solo.observer`. A failed job whose outcome nobody has accessed through `done`,
`value` or `ignoreFailure()` by the microtask after it ends is also answered
for. The controller's `onUnanswered` hands the error to
`Solo.unansweredHandler` when one is set, and otherwise reports it as unhandled
to the Dart zone in which the job was created. Use `ignoreFailure()` when error
reporting elsewhere is sufficient: leaving a job unawaited does not by itself
mark the error as handled, and neither does reading `outcome`. See
[Handled and unhandled failures](errors.md#handled-and-unhandled-failures) on
the errors page.

The job decides once whether to answer for its failure, on the microtask after
it ends: `done` read later still returns the `Failed`, but the error has been
answered for by then.

### Creating and scheduling jobs

```dart
enum _Op { load, save, zoom, seek, stop, pause }

// Assembled now, queued after: two steps, for a job to hold on to.
final saving = job<Ready, void>(
  key: _Op.save,
  (ctx) => ctx.join(store.save),
);
enqueueJob(saving);

// Or both at once, which is what a controller method normally does.
Job<void> setZoom(double zoom) => enqueue<Ready, void>(
      key: _Op.zoom,
      // Lazy, and only for diagnostics: built when a log asks for it.
      describe: () => 'zoom: $zoom',
      (ctx) => ctx.join(() => camera.zoom(zoom)),
    );
```

The code of this section and of the ones below belongs to one controller of a
camera, a `Solo<CameraState>`. The two type arguments of `job` and `enqueue`
are the working type — the states the body works in, here `Ready`, one of the
states of the camera — and the type of the result. Left out, the working type
is the whole of `S`, and the result type is what the body returns.
[State and rules](state.md#state-and-rules) on the state page is about the
first.

A `key` is what queue policies match on, and `describe` supplies the label used
by logs, observers and `toString()`: `Job(key: label)`. Without a description
the representation is `Job(key)`.

`job`, `enqueueJob` and `enqueue` all return `SoloJob<T>`, which implements
`Job<T>` and adds `isQueued`. All three are protected, as are `collect` and
`accumulate`: a controller exposes domain methods such as `load()` or
`setZoom()`, and callers see those, not the members they are built from. A
domain method declares `Job<T>`, as `setZoom` above does: that is all its
caller needs to await the result or cancel the job. It declares `SoloJob<T>`
only for a caller that reads `isQueued`. A private method that makes a child
for `ctx.run` declares `SoloJob<T>` as well: `ctx.run` takes a `ChildJob<T>`,
which `SoloJob<T>` is and `Job<T>` is not.

A job the queue starts runs its body in the Dart zone of the call that made the
job: `enqueue`, or `job` for `saving` above, and not `enqueueJob`. What woke
the queue does not change the zone: a job queued just before it from another
zone, the end of the job before, or the timer of an accumulation window. The
body's timers and zone values, the job's deadline, the `onStart` hooks and the
errors of futures the body does not await all stay in that zone. It is also
where the job's failure goes when nobody reads its outcome and nothing else
answers for it. Inside `ctx.unattended` the zone is the one that work was
started from, as in the core. A child is not the queue's to start: it runs
where `ctx.run` starts it, like any `Job.deferred`.

## Queue and policies

A job added to a controller's queue is a root job, and only one root job runs
at a time. When a method is called again while the job of an earlier call is
still queued or running, the policy decides which of the two survives:

```dart
// sequential, the default: one after another, in the order asked for.
Job<void> save() =>
    enqueue<Ready, void>(key: _Op.save, (ctx) => ctx.join(store.save));

// droppable: a second load of the same profile returns the first job.
Job<Profile> load(String id) => enqueue<Ready, Profile>(
      key: (_Op.load, id),
      policy: Policy.droppable,
      (ctx) => ctx.abandonable(() => api.load(id)),
    );

// replace: the queued zoom goes, a running one is left alone.
Job<void> setZoom(double zoom) => enqueue<Ready, void>(
      key: _Op.zoom,
      policy: Policy.replace,
      (ctx) => ctx.join(() => camera.zoom(zoom)),
    );

// restart: the same, and the running one is asked to stop as well.
Job<void> seek(Duration position) => enqueue<Ready, void>(
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
| `Policy.droppable` | Return the existing job, queued or the running root job; discard the new one. |
| `Policy.replace` | Enqueue the new job, then remove cancellable queued jobs with that key: their cancellation already sees the new one queued. |
| `Policy.restart` | Do the same as `replace` and request cancellation of the running root job with that key. |

A root job holds the queue until its body, its children, its cleanup and its
state handler — the `ifFailed` or `ifCancelled` it was given — have finished.
Until then no other root job starts. The children it waits for are its own:
they run inside it and never stand in the queue; they are described on the page
[Children and chains](children.md). A policy does not apply to child jobs.

A job that `replace` or `restart` removes ends `Cancelled(replaced)`, whose
reason is a `ReplacedCancelReason`: the queued zoom that `replace` takes out,
the running seek that `restart` cancels. `droppable` drops the new job, and
that one ends `Cancelled(duplicate)`, as shown below. For `droppable` the
running job is the existing one for as long as it has not been cancelled. One
that has already accepted a cancellation is on its way out and will not do the
work, so a call that finds it queues a job of its own.

`restart` requests cancellation when the new job is submitted. The new job goes
to the tail of the queue like any other, behind what was queued before it, and
it still waits for the current job to finish: their bodies do not overlap. A
job that refuses cancellation, one created with `cancellable: false`, can
therefore delay its replacement. So can one that has nothing to hand the
request to: a `join` around a call the request cannot reach waits that call out
to the end, and the outcome is `Cancelled` all the same. The token above is the
way in; `ctx.abandonable` is the other, for an operation that can be left to
finish on its own. Both are in
[Stopping the underlying operation](cancellation.md#stopping-the-underlying-operation)
on the cancellation page.

Every caller of a `droppable` key may get the same job back. So a plain `then`
on that job throws `StateError`, on the first call as well: a `then` of one
caller would leave the next one nothing to continue with. Each caller continues
it through `shared()` instead, `load('ada').shared().then(...)`: what
`shared()` returns ends with the job, and cancelling it leaves the job alone.
See
[A handle for each branch](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/chains.md#a-handle-for-each-branch).

A key `droppable` shares with another policy hands back that policy's job too,
and from then on a plain `then` on it throws as well. A `then` its own caller
took before stays, and then `shared()` throws for the `droppable` caller, who
is left with `done` and `value`. Give `droppable` a key of its own.

### A key for each request

`load` takes the id of a profile. Two callers that ask for the same profile
while it loads should share one request, and a caller that asks for another
profile should get that one.

#### The first attempt

```dart
// The first attempt: one key for every profile.
Job<Profile> load(String id) => enqueue<Ready, Profile>(
      key: _Op.load,
      policy: Policy.droppable,
      (ctx) => ctx.abandonable(() => api.load(id)),
    );
```

One member of `_Op` for the method, as `save`, `setZoom` and `seek` have it,
and `droppable` to drop the repeated request. A second `load('ada')` while the
first is on its way is handed the first job, as meant. So is `load('grace')`:
the key says `load` and nothing about whose profile, so to the policy that call
is a duplicate as well. Its caller awaits the job it was handed and gets Ada's
profile, and no request for Grace's is made.

#### The record key

```dart
Job<Profile> load(String id) => enqueue<Ready, Profile>(
      key: (_Op.load, id),
      policy: Policy.droppable,
      (ctx) => ctx.abandonable(() => api.load(id)),
    );
```

A key is any object, compared with `==`: the record `(_Op.load, id)` gives the
policy the identity of one request rather than of the operation. `droppable`
drops a second load of the same profile and lets a load of another one through.

The job the second call brought never starts: it ends on the spot with
`Cancelled(duplicate)`, whose reason is a `DuplicateCancelReason`. `enqueue`
returns one handle and does not say whose job it is, so a method that has to
know assembles the job first and compares it with what `enqueueJob` gives back:

```dart
int duplicates = 0;

Job<Profile> load(String id) {
  final mine = job<Ready, Profile>(
    key: (_Op.load, id),
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
  final taken = enqueueJob(mine, policy: Policy.droppable);
  if (!identical(taken, mine)) {
    // `mine` was dropped and has already ended with `Cancelled(duplicate)`;
    // `taken` is the load that was there before this call.
    duplicates++;
  }
  return taken;
}
```

`load` hands back `taken`, and both callers await one profile. A method that
returns `mine` instead tells the second caller that its call was dropped: that
caller gets `Cancelled(duplicate)`, not the result of the first call.

Use a distinct key for each operation and result type. A `Job<int>` handed to
`droppable` under a key a `Job<String>` already holds throws `ArgumentError`.
It throws before the job is taken: nothing was queued and nothing was
cancelled, so the same handle can still be added — under `Policy.sequential`,
or later, once that key is free. A key is fixed when the job is made, so the
collision itself is settled where the two jobs are built. An enum with one
member per method, alone or inside a record, is a convenient way not to have
it. A non-sequential policy with a null key throws `ArgumentError` too, and
both checks work in release builds.

### Working the queue directly

The queue itself is the controller's own, and a method can work it directly:

```dart
Job<void> stop() {
  // What is waiting right now.
  print(queue.length);
  // Drop what this command makes pointless...
  queue.removeWhere((job) => job.key == _Op.zoom);
  // ...and jump the line with the stop itself.
  return enqueueJob(
    job<Ready, void>(key: _Op.stop, (ctx) => ctx.join(camera.stop)),
    first: true,
  );
}
```

`first` passes what is waiting and nothing else. A zoom that is already running
is neither removed by `removeWhere` nor interrupted by `first`: the stop starts
when that zoom finishes. Only cancellation stops a job that has already
started, and the page [Cancellation](cancellation.md) is about it.

`queue` exposes `jobs`, `length`, `isEmpty`, `isNotEmpty`, `remove`,
`removeWhere` and `clear`. `lastJobWhere` on the controller finds the last
queued job that passes its test or, when none does, the running one. The
running root job itself is `current`, or `null` when the controller is idle,
and `current?.cancel()` asks it to stop. Removal methods affect queued jobs
only — the running job is not theirs to touch — and they preserve jobs with
`cancellable: false` unless called with `force: true`. What they remove ends
`Cancelled(manual)`, or with the `reason:` the caller passes; `cancelAll`,
which clears the queue and cancels the running job as well, takes one too.

The order in `jobs` is not the order jobs will run in. A job waiting for an
accumulation window can be passed by a ready one standing behind it, so the
head of the queue is not always what starts next. See
[Choosing when a group is ready](accumulation.md#choosing-when-a-group-is-ready)
on the accumulation page.

### Pausing the queue

The queue has to stand still for a while: nothing starts until the controller
is told to go on, and what was asked for meanwhile runs then, in the order it
was asked for. The queue has no pause of its own, and a job that waits on a
`Completer` holds it as well as any work does. That job, the gate, works in
`CameraState`, the whole state type of the controller, where the other jobs
here work in `Ready`. A job ends `Cancelled` when the state leaves its working
type, and a pause is not the business of one state.

#### The first attempt

```dart
// The first attempt: the gate waits behind the queued jobs.
Completer<void>? _gate;

bool get isPaused => _gate != null;

void pause() {
  if (_gate != null) return;
  final gate = _gate = Completer<void>();
  enqueue<CameraState, void>(
    key: _Op.pause,
    (ctx) => ctx.abandonable(() => gate.future),
  );
}

void resume() {
  _gate?.complete();
  _gate = null;
}
```

`enqueue` is the call a method normally makes, and it puts the gate where it
puts every job: at the tail. Three jobs that were already waiting run before
the pause begins, and only what is submitted after `pause()` waits behind the
gate.

A gate can also leave without a `resume`: `cancelAll` cancels it, and so does
`close`. `resume` is the only thing that clears the field, so after a
`cancelAll` `isPaused` goes on saying `true` while the queue runs, and the next
`pause()` returns at its first line.

#### The second attempt

```dart
// The second attempt: a gate removed before it starts stays set.
void pause() {
  if (_gate != null) return;
  final gate = _gate = Completer<void>();
  enqueueJob(
    job<CameraState, void>(key: _Op.pause, (ctx) async {
      // Cancellation is not a resume, and a cancelled gate is not a pause.
      ctx.onCancel(() => _gate = null);
      await ctx.abandonable(() => gate.future);
    }),
    first: true,
  );
}
```

The field, `isPaused` and `resume()` stay as they were. `first` puts the gate
ahead of everything but the running job, so what is already queued waits along
with what is submitted later. And `ctx.onCancel` clears the field when the gate
is cancelled, as long as the gate is running by then. The body registers that
callback, and the body has not run while the gate waits its turn behind the
running job. A `queue.clear()`, a `cancelAll()` or a `close()` in that window
takes the gate off the queue before it has started. There is no callback, the
field is still set, and `isPaused` is back to saying `true` over a queue that
runs.

#### The handle of the gate

```dart
void pause() {
  if (_gate != null) return;
  final gate = _gate = Completer<void>();
  enqueueJob(
    job<CameraState, void>(
      key: _Op.pause,
      (ctx) => ctx.abandonable(() => gate.future),
    ),
    first: true,
  ).whenCancelled((_) {
    // Cancellation is not a resume, and a cancelled gate is not a pause.
    // After a `resume()` and another `pause()` the field holds a newer
    // gate, and that one stays.
    if (identical(_gate, gate)) _gate = null;
  });
}
```

`whenCancelled` is registered on the handle `enqueueJob` gives back, not by the
body, so it hears the cancellation of a gate that never started as well as of
one that runs. On a job that is already cancelled — what `enqueueJob` hands
back on a closed controller — it is called on the spot. The callback clears the
field only while the field still holds this gate: after a `resume()` and
another `pause()` it holds the newer one, and the end of the old gate must not
clear that. The cases:

| What you do | What happens |
| --- | --- |
| `pause()`, then submit three jobs | The three wait, and no outcome is reached. |
| `pause()` with three already queued | They wait too: the gate goes in ahead of everything but the running job. |
| `resume()` | They run, in the order they were submitted. |
| `queue.clear()` while the gate runs | The queue empties and the pause stands: the gate is the running job, not a queued one. |
| `queue.clear()` while the gate still waits behind the running job | The gate goes with the rest of the queue, and the field is clear: `isPaused` says `false`, and `pause()` works again. |
| `close()` while paused | It comes back without a `resume`: the gate is cancellable, and its `ctx.abandonable` ends the moment the gate is cancelled. |
| `close(mode: SoloCloseMode.drain)` while paused | It waits for the `resume`: a drain runs what is queued instead of cancelling it, the gate included. |
| `cancelAll()` | The gate goes with everything else and the queue moves on, with nobody having opened it; the field is clear, so `pause()` works again. |
| The state leaves `Ready` while paused | The pause stands: the gate works in every state of the camera. |

`pause()` returns nothing on purpose. The handle `enqueueJob` gives back
belongs to the gate, and it ends when the pause ends rather than when it
begins — `Done` on a `resume`, `Cancelled(closed)` on a `close`. Returning it
invites the habit every other method on this page teaches, and an awaited
`pause()` waits for the `resume` its caller was about to make.

What the engine does not know is that this job is a pause. The observer sees an
ordinary job start, and `pending` answers with the gate rather than with work,
so a screen showing what runs shows the gate instead. Whether the controller is
paused is yours to keep, and `isPaused` is where this controller keeps it.

`canStart` is not a pause. A job whose rule does not fit the state is not held
back: it is cancelled when its turn comes, with `Cancelled(rules: canStart)`,
and the queue empties instead of filling up. A pause built on it loses the work
silently.
