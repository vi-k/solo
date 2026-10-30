# Jobs and the queue

A method of a controller queues a job and returns its handle. This page covers
the handle, the queue and the policies that decide what a second call does to
the first. It opens with the profile controller and ends with a screen whose
taps need a queue of their own.

## The profile controller

The pages of this package build on one controller: the profile controller of
the
[Quick start](https://github.com/vi-k/solo/blob/main/packages/solo/README.md#quick-start)
in the package README, with what a controller in an application adds to it.
`ProfileApi` returns a name after a short delay; a real client throws an
`ApiException` when the call fails:

```dart
import 'package:solo/solo.dart';

sealed class ProfileState {
  const ProfileState();
}

final class Initial extends ProfileState {
  const Initial();
}

final class Loading extends ProfileState {
  const Loading();
}

final class Loaded extends ProfileState {
  final String name;

  const Loaded(this.name);
}

final class Failure extends ProfileState {
  final Object error;

  const Failure(this.error);
}

final class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}

class ProfileApi {
  Future<String> fetchName() =>
      Future.delayed(const Duration(milliseconds: 20), () => 'Ada Lovelace');
}

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => enqueue<ProfileState, String>(
    key: 'load',
    policy: Policy.droppable,
    ifFailed: (state, error, stackTrace) => Failure(error),
    isExpectedError: (error) => error is ApiException,
    ifCancelled: (state, cancelled) => const Initial(),
    (ctx) async {
      ctx.emit(const Loading());
      final name = await ctx.abandonable(api.fetchName);
      ctx.emit(Loaded(name));
      return name;
    },
  );
}
```

`enqueue<ProfileState, String>` names two types. `ProfileState` is the job's
working type `W`: the states its body works with, which may be narrower than
the controller's state type `S`. `String` is the job's result type. Left to
inference, as in the quick start, `W` is the whole of `S` and the result type
is what the body returns. The rest is what the quick start does not have:

| Parameter | What it does | Where it is explained |
| --- | --- | --- |
| `key: 'load'`, `policy: Policy.droppable` | A second `load()` while one is queued or running gets that job back | [Queue and policies](#queue-and-policies) |
| `ifFailed`, `ifCancelled` | The state to publish when the job fails, `Failure`, or a started job is cancelled, `Initial` | [State after failure or cancellation](state.md#state-after-failure-or-cancellation) |
| `isExpectedError` | A failure with an `ApiException` that nobody reads ends at `Failure`; any other error that nobody reads goes on to the zone | [Naming the expected errors](errors.md#naming-the-expected-errors) |

## Jobs and results

A `Job<T>` represents one operation and its eventual outcome. A method of a
controller queues the work and hands back the handle; `profile.load()` below is
the one from [The profile controller](#the-profile-controller). Awaiting `done`
or `value` of the handle reads how the operation ended, it does not set the
operation going. The handle is not a `Future`: a job can be cancelled, and its
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
| `job.outcome` | Read the outcome synchronously; `null` until the job has finished. |
| `job.cancel()` | Request cancellation and wait for completion. |
| `job.ignoreFailure()` | Keep the failure of a job nobody awaits from being reported as unhandled; the errors a job expects are named in its `isExpectedError` instead. |
| `job.whenCancelled(callback)` | Hear the cancellation the moment the job accepts it, running or still queued. |
| `job.whenFinished(callback)` | Hear the end with the outcome, without observing a failure. |

A failed job does not stop the queue. Its error is reported and the next job
can run. Cancellation is a separate outcome: closing the controller, removing a
queued job or a state the job's rules do not accept can all end work
`Cancelled`, and none of them says that anything failed.

Every failure reaches the `onError` hook of the controller and of
`Solo.observer`. A failed job whose outcome nobody has accessed through `done`,
`value` or `ignoreFailure()` by the microtask after it ends is also answered
for, unless the job names the error in `isExpectedError`. The controller's
`onUnanswered` hands the error to `Solo.unansweredHandler` when one is set, and
otherwise reports it as unhandled to the Dart zone in which the job was
created. Use `ignoreFailure()` when error reporting elsewhere is sufficient:
leaving a job unawaited does not by itself mark the error as handled, and
neither does reading `outcome`. See
[Handled and unhandled failures](errors.md#handled-and-unhandled-failures) and
[Naming the expected errors](errors.md#naming-the-expected-errors) on the
errors page.

The job decides once whether to answer for its failure, on the microtask after
it ends: `done` read later still returns the `Failed`, but the error has been
answered for by then.

### Creating and scheduling jobs

```dart
enum _Op { load, save, zoom, seek, stop, pause, shoot }

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
are the working type and the type of the result, as in
[The profile controller](#the-profile-controller); the working type here is
`Ready`, one of the states of the camera.
[State and rules](state.md#state-and-rules) on the state page is about the
working type.

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

A job in a controller's queue is a root job, and only one root job runs at a
time. When a method is called again while the job of an earlier call is still
queued or running, the policy decides which of the two survives:

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
Job<void> seek(Duration position) =>
    enqueue<Ready, void>(key: _Op.seek, policy: Policy.restart, (ctx) async {
      final token = CancelToken();
      ctx.onCancel(token.cancel);
      // Wait for the device to stop before the next seek starts.
      await ctx.join(() => camera.seek(position, cancelToken: token));
    });
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
cancelled, so the same handle can still be enqueued — under
`Policy.sequential`, or later, once that key is free. A key is fixed when the
job is made, so the collision itself is settled where the two jobs are built.
An enum with one member per method, alone or inside a record, is a convenient
way not to have it. A non-sequential policy with a null key throws
`ArgumentError` too, and both checks work in release builds.

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
[Choosing when a group is ready](accumulation-rules.md#choosing-when-a-group-is-ready)
on the accumulation rules page.

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

### A delayed start

The camera has a self-timer: `shootIn(delay)` takes the shot when the delay is
over, and the camera goes on taking commands meanwhile — a zoom set during the
countdown is set at once. `cancelAll()` stops the countdown as it stops the
rest of the work, and so does closing the controller.

#### The first attempt

```dart
// The first attempt: the countdown holds the queue.
Job<void> shootIn(Duration delay) =>
    enqueue<Ready, void>(key: _Op.shoot, (ctx) async {
      await ctx.pause(delay);
      await ctx.join(camera.shoot);
    });
```

`ctx.pause` is the wait the core gives a job, and both `cancelAll()` and
`close()` end it. But a job that waits holds the queue as well as one that
works, which is what the gate of [Pausing the queue](#pausing-the-queue) is
for. With a ten-second delay, a zoom asked for one second into the countdown
starts only after the shot, nine seconds late.

#### The second attempt

```dart
// The second attempt: the countdown belongs to no job.
void shootIn(Duration delay) => Timer(delay, shoot);

Job<void> shoot() =>
    enqueue<Ready, void>(key: _Op.shoot, (ctx) => ctx.join(camera.shoot));
```

The timer stands outside the queue, and the zoom goes at once. Nothing but the
timer knows of the countdown, though. `cancelAll()` five seconds in clears the
queue and cancels the running job, and five seconds later the shot is taken all
the same. `close()` does not stop the timer either: it outlives the closed
controller, and when it fires, `shoot()` is refused with `Cancelled(closed)`. A
widget test that disposes the camera during the countdown fails on that pending
timer.

#### A countdown the controller owns

```dart
Job<void>? _countdown;

void shootIn(Duration delay) {
  if (isClosed) return;
  _countdown?.cancel().ignore();
  final countdown = _countdown = Job<void>((ctx) => ctx.pause(delay));
  countdown.whenFinished((outcome) {
    if (identical(_countdown, countdown)) _countdown = null;
    if (outcome is Done) shoot();
  });
}

@override
Future<void> cancelAll({
  bool force = false,
  CancelReason reason = const ManualCancelReason(),
}) async {
  final countdown = _countdown?.cancel(reason: reason);
  await super.cancelAll(force: force, reason: reason);
  await countdown;
}

@override
void onClose() => _countdown?.cancel().ignore();
```

The countdown is a `Job` of its own, made with the constructor of the core
rather than by `enqueue`: it waits for no turn and holds no queue. `ctx.pause`
is the same wait as in the first attempt. A start on a signal rather than after
a delay changes the body of the countdown alone: it waits for the signal in
place of `ctx.pause`, as in
`Job<void>((ctx) => ctx.abandonable(() => flash.ready))`, where `flash.ready`
is a future that completes once the flash has charged. When the countdown ends
`Done`, `whenFinished` queues the shot, and a cancelled countdown queues
nothing. `shoot()` is the method of the second attempt.

The controller does not know of the countdown, so the class tells it in two
places. The override of `cancelAll` cancels the countdown with the reason it
was given and then does its own work through `super`, which clears the queue
and cancels the running job; the future it returns completes once the countdown
has ended as well. `onClose` cancels the countdown once the controller has
closed, whatever mode closed it. After that no hook is left to cancel a new
countdown, and the guard at the top of `shootIn` keeps one from starting.

The field is cleared only while it holds this countdown: a second `shootIn`
cancels the first and puts its own in the field, and the end of the first must
not clear that. `whenFinished` hears the end without observing a failure.
`ctx.pause` does not fail, but `flash.ready` can, and an error that comes after
the countdown is cancelled goes to the zone past `ignoreFailure()`. So a signal
that can fail has its error caught inside `ctx.abandonable` and turned into a
value, and the shot is taken on that value alone. The cases:

| What you do | What happens |
| --- | --- |
| `shootIn` with ten seconds, then a zoom one second in | The zoom is set at once, and the shot is taken at ten seconds. |
| `shootIn` again during the countdown | The countdown starts over: one shot, ten seconds after the second call. |
| `cancelAll()` during the countdown | No shot, and no timer is left. |
| `queue.clear()` during the countdown | The shot is taken: the countdown does not stand in the queue. |
| `close()` during the countdown | No shot, and no timer outlives the controller. |
| `close(mode: SoloCloseMode.drain)` during the countdown | The queue runs out, and no shot is taken. |
| `shootIn` after `close()` | Nothing starts. |

When the delay is the same on every call, an accumulator gives nearly all of
this, and there is no countdown to keep: `accumulate` with
`AccumulationTiming.debounce(delay)`. Its group waits out the window without
holding the queue, another `add` starts the window over, and `cancelAll()` and
`close()` drop the group. It parts from the table in two rows: `queue.clear()`
drops the group, and a draining `close()` waits the window out and takes the
shot. A countdown of its own is for a delay that changes from call to call, for
a start on a signal, and for a wait `queue.clear()` must not touch. See
[Choosing when a group is ready](accumulation-rules.md#choosing-when-a-group-is-ready)
on the accumulation rules page for the window.

## A tap that does not wait for a reload

A feed screen reloads its posts, which takes the server two seconds, and the
user likes a post meanwhile. The heart should light at once and the like should
reach the server at once, and a like and an unlike of one post should reach it
in the order they were tapped. `Feed` holds the posts, each `Post` has an `id`
and `liked`, and `withLiked` copies the feed with one post changed. `api` is a
`FeedApi`: its `fetchFeed()` answers two seconds after the request, with the
likes the server held when the request came, and its `setLiked` answers a
twentieth of a second after the request, or throws an `ApiException` when the
request fails.

### The first attempt

```dart
// The first attempt: the like waits for the reload.
Job<Feed> reload() =>
    enqueue<Feed, Feed>(key: 'reload', policy: Policy.droppable, (ctx) async {
      final feed = await ctx.abandonable(api.fetchFeed);
      ctx.emit(feed);
      return feed;
    });

Job<void> like(String postId, {required bool liked}) =>
    enqueue<Feed, void>(key: ('like', postId), (ctx) async {
      ctx.emit(ctx.state.withLiked(postId, liked: liked));
      await ctx.join(() => api.setLiked(postId, liked: liked));
    });
```

Each method has a key of its own, and `droppable` drops a second reload while
one is on its way. But a key decides only what a second call does to a job with
the same key, and it lets no job pass another: one root job runs at a time. A
like tapped 100 ms into the reload starts when the reload has ended. The heart
lights at 2000 ms, and the like reaches the server then.

### The second attempt

```dart
// The second attempt: the like goes around the queue.
Future<void> like(String postId, {required bool liked}) async {
  externalSetState(currentState.withLiked(postId, liked: liked));
  await api.setLiked(postId, liked: liked);
}
```

`externalSetState` writes the state without waiting for a turn, and the request
goes at once: the heart lights at 100 ms, and the server confirms the like at
150 ms. But the reload asked the server at 0 ms, before the like, and at 2000
ms it publishes what it was told: the heart goes out while the server holds the
like, and only the next reload lights it again. The same race is
[Ordering updates to shared state](vs-bloc.md#ordering-updates-to-shared-state)
on the page comparing the package with bloc.

### A controller for the likes

```dart
/// A like the screen shows over the feed.
final class Mark {
  final bool liked;

  /// The number of the confirmation, or `null` while the like is on its way.
  final int? confirmation;

  const Mark(this.liked, [this.confirmation]);
}

final class Marks {
  final Map<String, Mark> byPost;

  const Marks([this.byPost = const {}]);

  Marks put(String postId, Mark? mark) => Marks({
    for (final MapEntry(:key, :value) in byPost.entries)
      if (key != postId) key: value,
    postId: ?mark,
  });
}

final class LikesController extends Solo<Marks> {
  final FeedApi api;
  int _confirmations = 0;

  LikesController(this.api) : super(const Marks());

  /// How many likes the server has confirmed so far.
  int get confirmations => _confirmations;

  Job<void> setLiked(String postId, {required bool liked}) {
    Mark? before;
    return enqueue<Marks, void>(
      // No confirmation: the post shows what it showed before the tap.
      ifFailed: (marks, error, stackTrace) => marks.put(postId, before),
      ifCancelled: (marks, cancelled) => marks.put(postId, before),
      isExpectedError: (error) => error is ApiException,
      (ctx) async {
        before = ctx.state.byPost[postId];
        ctx.emit(ctx.state.put(postId, Mark(liked)));
        await ctx.join(() => api.setLiked(postId, liked: liked));
        ctx.emit(ctx.state.put(postId, Mark(liked, ++_confirmations)));
      },
    );
  }

  /// Drops the marks that a reload sent after [seen] confirmations brings.
  Job<void> settle(int seen) => enqueue<Marks, void>((ctx) async {
    final kept = {
      for (final MapEntry(key: postId, value: mark) in ctx.state.byPost.entries)
        if (mark.confirmation! > seen) postId: mark,
    };
    if (kept.length < ctx.state.byPost.length) ctx.emit(Marks(kept));
  });
}
```

The likes get a controller of their own, and its queue holds only short jobs,
the likes and `settle`, so a like never waits for a reload: the principle of
[A board of its own](state.md#a-board-of-its-own) on the state page. Its state
is a mark for each post the user has tapped, and the screen shows the mark over
what the feed says. The feed tells the likes when a reload has brought the
server's word:

```dart
final class FeedController extends Solo<Feed> {
  final FeedApi api;
  final LikesController likes;

  FeedController(this.api, this.likes) : super(const Feed([]));

  Job<Feed> reload() =>
      enqueue<Feed, Feed>(key: 'reload', policy: Policy.droppable, (ctx) async {
        final seen = likes.confirmations;
        final feed = await ctx.abandonable(api.fetchFeed);
        ctx.emit(feed);
        likes.settle(seen);
        return feed;
      });
}

/// Whether the screen shows [post] liked.
bool shownLiked(Post post, Marks marks) =>
    marks.byPost[post.id]?.liked ?? post.liked;
```

`setLiked` publishes the mark as it starts and then sends the like. A mark
stays until a reload sent after its confirmation has published: a reload sent
before brings what the server held before the like. So the feed takes the count
of confirmations as it sends the reload and hands it to `settle` once the
reload has published. `settle` stands in the same queue behind the likes, so
every mark it meets has its number: a like that ends without one puts back the
mark it found.

`before` is the mark the post had when the like started. When the like fails or
is cancelled, `ifFailed` or `ifCancelled` puts it back, and the post shows what
it showed before the tap: a failed unlike brings back a confirmed like. Nobody
reads the outcome of a tap, so `isExpectedError` names the `ApiException` of a
failed request, and it does not go on to the zone.

One queue keeps a like and an unlike of one post in order, and the likes of
different posts as well: a like of a second post waits while the first is on
its way. For a request of a twentieth of a second that is acceptable; work that
runs long needs a queue of its own. A second tap on the same post waits the
same way, and so does its mark: the heart answers the tap once the first like
is confirmed. So a screen that flips the heart takes the new value from its own
last tap rather than from `shownLiked`: a third tap during the wait would read
the heart the second tap has not turned yet and repeat the second tap. The
screen listens to both controllers. In Flutter, one widget over both takes
`Listenable.merge` in a `ListenableBuilder`, with `SoloListenable` of
`flutter_solo` mixed in to each.

The countdown of [A delayed start](#a-delayed-start) suggests another way: the
wait for the server in a `Job` outside the queue, and only the step that
publishes the feed in the queue. A like in the same controller then goes at
once, but the reload still publishes what the server held before the like, and
the marks are needed all the same. `ctx.unattended` does not help: a like that
calls it waits in the queue first. Nor does a child, which runs inside the body
of a job that is already running. The cases:

| What you do | What happens |
| --- | --- |
| A like during a reload | The heart lights at once, and the like reaches the server at once. The reload publishes the feed without the like, and the mark stays over it. |
| The next reload | The feed brings the like, and the mark goes. |
| A like confirmed, then a reload sent | That reload settles the mark. |
| A like and an unlike of one post | The server gets them in that order. |
| The like fails | The post shows what it showed before the tap, and nothing reaches the zone. |
| The like is cancelled | Once its request has answered, the post shows what it showed before the tap, until a reload brings the server's word. |
| A second tap on the post while its like is on its way | It waits for the first like to be confirmed, and the heart answers it then. |
| A like of another post during a slow one | It waits for the first to be confirmed. |
