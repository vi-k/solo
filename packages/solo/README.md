# solo

`solo` manages state and asynchronous work in Dart. A controller holds
the current state and processes jobs one at a time. Each job can declare
which states allow it to start and continue, and callers can await its
result or request cancellation.

Use it for screens, sessions and devices where operations share state
and need an explicit order. The package has no Flutter dependency.
[`flutter_solo`](https://pub.dev/packages/flutter_solo) adds a controller
that implements `ValueListenable` for Flutter widgets.

## Install

```sh
dart pub add solo
```

For Flutter, install `flutter_solo`. It re-exports `solo`:

```sh
flutter pub add flutter_solo
```

`solo` re-exports [async_job](https://pub.dev/packages/async_job), which
provides jobs, cancellation and resource cleanup. One import,
`package:solo/solo.dart`, gives access to both APIs. You do not need to
learn the underlying package before using the examples below.

## Quick start

A controller exposes methods for application operations. Here, `load()`
loads a profile name and reports progress through four immutable states:

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
```

The example API returns a name after a short delay. Replace it with your
application's API client:

```dart
class ProfileApi {
  Future<String> fetchName() => Future.delayed(
        const Duration(milliseconds: 20),
        () => 'Ada Lovelace',
      );
}

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        onError: (state, error, stackTrace) => Failure(error),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}
```

`run<ProfileState, String>` creates and queues a job. `ProfileState` is
the state type its body can work with; `String` is its result type.
The body receives a context, `ctx`, which provides state updates and
cancellation-aware waiting:

- `ctx.emit` updates the controller's state.
- `ctx.wait` waits for the API response, or throws `Cancelled` if the job
  accepts cancellation while waiting.
- `onError` returns the state to publish if the job fails.
- `onCancel` returns the state to publish if a started job is cancelled.

The state handlers run after the body and its cleanup. In this example,
the state becomes `Loaded` on success, `Failure` on error, or `Initial`
on cancellation. Failure and cancellation remain the job's outcome even
when a handler updates the state.

`Policy.droppable` and `key: 'load'` make repeated calls share the queued
or running load. A second call returns the existing job. Once that job
finishes, another call can start a new load.

The caller uses the returned `Job<String>` to await this particular load:

```dart
Future<void> main() async {
  final profile = ProfileController(ProfileApi());
  final subscription = profile.stream.listen(print);
  try {
    final job = profile.load();
    profile.load(); // the existing job is returned

    print(await job.value);
    if (profile.state case Loaded(:final name)) {
      print(name);
    }
  } finally {
    await subscription.cancel();
    await profile.close();
  }
}
```

`profile.state` is available synchronously. `profile.stream` broadcasts
changes asynchronously. `job.value` returns the loaded name, or throws
the job's error or `Cancelled`. The `finally` block releases the listener
and closes the controller even if loading fails.

Cancellation uses the same job object. This separate example requests
cancellation immediately, so the job may still be in the queue:

```dart
Future<void> cancelLoading() async {
  final profile = ProfileController(ProfileApi());
  final job = profile.load();

  await job.cancel();
  print(job.outcome); // Cancelled(manual)
  await profile.close();
}
```

`cancel()` waits for the job to finish, including cleanup if it started.
A job cancelled before its body starts does not call `onCancel`.
Jobs can start child jobs as part of their work; the starting job is
their parent and waits for them before finishing.
The next queued job starts only after the previous job finishes its body,
children, cleanup and state handler.

The sections below explain results, queue policies and cancellation in
more detail. In particular, cancellation of a job does not automatically
stop an API request that has already been sent.

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
[Error reporting and observation](#error-reporting-and-observation).

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
described in [Children and streams](#children-and-streams).

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

The controller's `queue` exposes `jobs`, `remove`, `removeWhere`, `clear`
and `lastWhere`. Removal methods affect queued jobs only. They preserve
jobs with `cancellable: false` unless called with `force: true`.
`add(job, first: true)` inserts at the front. Time-delayed accumulator
groups can let ready jobs pass; see [Event accumulation](#event-accumulation).

### Cancelling and closing a controller

`cancelAll()` clears cancellable queued jobs, requests cancellation of the
running job and waits for it to finish. The controller continues accepting
work. `cancelAll(force: true)` also removes non-cancellable queued jobs;
`force` does not change whether the running job accepts cancellation.

`close()` stops accepting work, cancels every queued job with
`Cancelled(closed)` and requests cancellation of the running job. It waits
for that job, including children and cleanup, even if cancellation is
refused. Repeated calls return the same future. Later submissions return
already cancelled jobs rather than throwing, so callers do not need an
`isClosed` check before submitting.

Closing does not itself release resources owned by your application or
select a final application state. Put that work in a controller method
and await it before `close()`, as in the camera example below. A state
handler of the cancelled job may still update state while closing.

Do not await `close()` or `cancelAll()` from the current job's body or
cleanup: either would wait for the very job making the call. A body can
finish by returning or cancel itself by throwing `Cancelled('reason')`.

## State and rules

`Solo<S>` stores one immutable state of type `S`. Use separate classes
when states allow different operations, and shared base types when an
operation can span several states.

The first type argument of `run<W, T>` is the job's working state type,
`W extends S`. The body reads `ctx.state` as `W`. For example, a camera
operation declared with `run<Ready, void>` can start only in `Ready`.

Three rules govern state access:

| Rule | Checked when |
| --- | --- |
| Working type `W` | Before start, on other state updates while the body runs, and at state checkpoints. |
| `canStart` | Once, when the job is about to start. |
| `keepWhile` | Before start, on other state updates while the body runs, and at state checkpoints. |

If a start check fails, the job ends with `Cancelled` and `started: false`.
A failing `W` or `keepWhile` check during execution cancels the job with
`RulesCancelReason`. These rules reject unsuitable work; they do not keep
it queued until the state becomes suitable.

For example, recording can require available storage at start and an
unpaused camera throughout execution. In this fragment, `Ready`, `camera`
and `store` belong to the application. `ctx.each` processes the stream;
its full lifecycle is explained under
[Children and streams](#children-and-streams).

```dart
Job<void> record() => run<Ready, void>(
      key: 'record',
      canStart: (state) => state.free > 0,
      keepWhile: (state) => !state.paused,
      (ctx) => ctx.each(
        camera.frames,
        (child, frame) => child.join(() => store(frame)),
      ).value,
    );
```

When another state update sets `paused` to true, `keepWhile` cancels the
recording. The callback does not need to repeat that condition.

### Reading and updating state

`ctx.state`, `ctx.stateAs<T>()` and `ctx.check()` check cancellation and
state rules. `stateAs<T>()` additionally requires the state to be `T`;
a mismatch cancels the job. Waiting methods use state checkpoints too.

`ctx.emit(next)` updates the state synchronously. It allows a job to
publish a state outside its own working type: an initialization job may
finish by emitting `Ready`. A later state checkpoint will reject that
state if it does not match `W`, so such a transition should be the body's
last state-dependent step. `canStart` is never repeated after an emit.

Other running bodies are checked after a state update. A job's own emit
is excluded from that rule check, but still checks cancellation before
and after writing. A synchronous hook or listener that causes another
state change can therefore cancel the emitting job before `emit` returns.

Rules stop cancelling a job once its body has ended. Manual cancellation,
controller closing and parent cancellation can still reach it while it
waits for children or cleanup. Jobs with state handlers also keep checking
whether those handlers may update state; see
[State after failure or cancellation](#state-after-failure-or-cancellation).

### Observing state

Anyone holding the controller can read `state`. `Solo.stream` is a
broadcast stream of every update, in order, delivered asynchronously on
a microtask. It does not replay the initial state. By the time an event
arrives, `state` may already contain a newer value. Equality is not checked;
emitting an equal state still produces an event.

The controller types differ in how they deliver updates:

| Type | Provides |
| --- | --- |
| `SoloBase<S>` | State, jobs, queue and rules. |
| `Solo<S>` | All of `SoloBase` plus a broadcast `stream`. |
| `SoloListenable<S>` | All of `Solo` plus Flutter's `ValueListenable<S>`. |

`SoloListenable` listeners run synchronously, in subscription order.
Its stream remains asynchronous.

## Cancellation and waiting

Cancellation is cooperative. Dart cannot interrupt an arbitrary `await`,
and marking a job cancelled does not stop its underlying I/O. Context
methods provide checkpoints so the body can respond to cancellation.

`ctx.join(action)` calls the operation and waits for its result. Before
starting it and before returning a successful result, it checks the job's
cancellation and state rules. For example, `ctx.join(Database.open)`
opens the database and returns it only after those checks succeed.

Use `ctx.wait(action)` when cancellation should end the wait immediately.
It also calls the operation and returns its result on success. Choose the
method according to what may happen to that operation:

| Method | If the job accepts cancellation while waiting |
| --- | --- |
| `ctx.wait(action)` | Throws `Cancelled` without waiting for the operation to finish. |
| `ctx.join(action)` | Waits for the operation; checks cancellation before returning a successful result. |
| `ctx.uncancellable(action)` | Holds ordinary cancellation until the action finishes; the next checkpoint throws it. |

If an operation awaited by `join` fails, its error is thrown into the
body even if the job has accepted cancellation. The job's final outcome
still remains `Cancelled`. The cancellation check after `join` applies
to successful operation results.

`wait` suits a request whose result can be abandoned. The request can
continue after the job has finished and the next job has started.
`join` suits work that must finish before the queue proceeds, such as a
device command or resource release. Neither method stops the operation
itself.

### Stopping the underlying operation

Use `ctx.onCancel(callback)` to connect job cancellation to an operation's
own cancellation mechanism. This callback runs synchronously when the job
is marked cancelled. Combine it with `join` when the next job must wait
for the operation to stop.

For a player whose API accepts a cancellation token:

```dart
Job<void> seek(Duration position) => run<Ready, void>(
      key: 'seek',
      policy: Policy.restart,
      (ctx) async {
        final token = CancelToken();
        ctx.onCancel(token.cancel);
        // Wait for the device to stop before another seek starts.
        await ctx.join(() => _player.seek(position, cancelToken: token));
        ctx.emit(ctx.state.copyWith(position: position));
      },
    );
```

The token requests that the player stop seeking. `join` waits for that
request to finish, so a replacement seek starts only afterwards. This
depends on the player's API actually responding to the token.

`ctx.onCancel` returns a function that unregisters the callback. It is a
cancellation signal for the operation, whereas the `onCancel` parameter
of `run` computes a final controller state after the job's cleanup.

### Protecting a step or a whole job

Use `ctx.uncancellable(action)` for a step that must complete once started,
such as committing a transaction. Manual cancellation, parent cancellation
and closing are held while the action runs. The job is not marked by
those requests yet, so its cancellation callbacks and child cancellation
cascade are also delayed.

When the outermost section finishes, a held request is applied. The next
checkpoint throws `Cancelled`; ordinary code immediately after the call
can still execute. Keep all required work inside the section and always
await it. An unawaited section can outlive the job and lose a held request.
Sections can nest.

`cancellable: false` on a job refuses these requests altogether. Queue
removal normally preserves such jobs, but `force: true` and `close()`
can discard them before they start. `close()` waits for a running
non-cancellable job.

Neither mechanism disables state rules. A job whose `W` or `keepWhile`
no longer matches is still cancelled. A job that must work in every state
needs the base type `S` and no `keepWhile` restriction.

### Ordinary await and context lifetime

Use context waiting methods for operations during the body, and
`ctx.check()` between steps of a loop that has no asynchronous operation
to wrap. A plain `await` does not respond to job cancellation and can
delay completion and `close()` indefinitely.

Plain `await` is appropriate when intentionally waiting through
cancellation, including inside cleanup or inside an `uncancellable`
section. Cancellation-aware waiting methods reject a job that is already
cancelled, so they cannot perform its cleanup.

Do not retain a context to start work after its job ends. Methods such as
`emit`, `run`, `each`, `wait`, `join` and `uncancellable` then throw
`StateError`. Reads and `check` remain available after normal completion;
after cancellation they still throw `Cancelled`. During registered cleanup,
state reads and body operations are unavailable. Capture the resources
needed for cleanup in its closure. `log`, `job`, cleanup registration,
`disown` and `unattended` remain available during cleanup. `log` itself
does not throw on cancellation or completion.

### Cancellation details

`Cancelled` includes `reason`, `started`, an optional `description` and
the cancellation stack trace. `started: false` means the body never ran.
Reasons extend `CancelReason`. The built-in types include
`ManualCancelReason`, `ParentCancelReason`, `HandlerCancelReason`,
`ChainCancelReason`, `RulesCancelReason` and `ClosedCancelReason`.
Inspect the type; `name` is a display label, not an equality key.

You can extend `CancelReason` to carry application data, then pass it to
`job.cancel(reason: reason)` or throw
`Cancelled.by(reason: reason, started: true)` inside a body. Propagation
between jobs retains the original cancellation in the reason's `cause`.

`job.whenCancelled(callback)` registers a synchronous listener and returns
a function to unregister it. It fires when a running job accepts
cancellation or a job is dropped before starting. If a body cancels itself,
it fires after the body and children finish, before cleanup. Registration
after cancellation calls the listener immediately. Successful and failed
jobs release these listeners without calling them. An asynchronous
callback is not awaited; callback errors use the same reporting path as
`ctx.onCancel` errors.

## External state

Most updates result from the controller's own jobs. An independent source,
such as a device or socket, can also change without waiting for the
controller. `externalSetState(next)` reflects a change that has already
happened in that source. It is marked `@protected` and is called from
inside the controller subclass, typically by a listener registered there.

Consider a device that disconnects while a job waits for its response.
If the listener queues a separate job to publish `Disconnected`, that
update must wait behind the current job. Until then, the controller still
reports a connected state, and the current job's rules cannot react to
the disconnection. The current job may itself be waiting for a response
that will never arrive.

Calling `externalSetState(const Disconnected())` in the listener updates
state immediately and re-evaluates running jobs. A job whose rules require
a connection is cancelled. Its waiting method determines when its body
resumes and whether the underlying operation must finish. The queue still
waits for the job's body and cleanup before starting another root job.

The distinction is what the notification represents. If it says that an
independent entity has already changed, reflect that fact immediately.
If it asks the controller to perform work, such as refresh data or save an
incoming value, enqueue a normal job. An event being delivered by a stream
does not by itself justify bypassing the queue.

Use job bodies and their state handlers for the controller's own success,
failure and cancellation. `externalSetState` is an exception for external
facts, not a general setter for those operations. Stop the external
listener before closing the controller: this method still changes `state`
and calls change hooks after `close()`, but `Solo`'s closed stream no
longer delivers updates.

## State after failure or cancellation

The `onError` and `onCancel` parameters of `run` and `job` let a controller
leave a temporary state such as `Loading` when an operation fails or is
cancelled. They receive the current state of type `S`, plus the error and
stack trace or the `Cancelled` outcome, and return the next state
synchronously.

The matching handler runs after the body, children and cleanup, before
the next queued job and before the `onFinish` hook. The outcome is already
fixed: changing state does not turn `Failed` or `Cancelled` into `Done`,
and does not mark the outcome as handled for error reporting.

### Preserving an incompatible external state

A final handler must not overwrite a state that makes its job invalid.
For example, extend the profile states from the quick start with
`Disconnected` in the same library, and replace the controller's `load`
method with this version:

```dart
final class Disconnected extends ProfileState {
  const Disconnected();
}

Job<String> load() => run<ProfileState, String>(
      key: 'load',
      policy: Policy.droppable,
      keepWhile: (state) => state is! Disconnected,
      onError: (state, error, stackTrace) => Failure(error),
      onCancel: (state, cancelled) => const Initial(),
      (ctx) async {
        ctx.emit(const Loading());
        final name = await ctx.wait(api.fetchName);
        ctx.emit(Loaded(name));
        return name;
      },
    );
```

The device listener calls `externalSetState(const Disconnected())` inside
the controller. `keepWhile` rejects that state, cancelling the load and
disabling both final handlers. `Disconnected` therefore remains visible
instead of being replaced by `Initial` or `Failure`.

If the load is cancelled manually while the state is still compatible,
`onCancel` can return `Initial`. The handlers need no extra
`state is Loading` checks: the job's rules express which states permit
the operation and its final correction.

### Handler eligibility and errors

An incompatible external update permanently disables both handlers, even
if it arrives after manual cancellation, while waiting for children, or
during cleanup. A later compatible update does not enable them again.
Loss of a parent's permission also blocks its children's handlers.

These extra checks apply to jobs with their own state handlers. A parent
without handlers stops checking its rules when its body ends; children
then remain subject to their own rules and any permission the parent
already lost. `canStart` is checked only at entry. A job's own `emit`
does not disable its handlers.

Handlers do not run for success, a discarded duplicate or any job whose
body never started. If a handler throws, the error is reported without
replacing the outcome or blocking the queue. If a rule throws while
checking handler eligibility, the handlers are disabled and the error
is reported. Resource cleanup still runs.

Keep these functions limited to computing state. Resource release belongs
in the cleanup API described next.

## Resources and cleanup

A job may acquire a database, subscription or another resource. Register
its release when acquiring it so cancellation cannot leave a resource
without cleanup. `wait` and `join` accept a `dispose` callback for a
resource that belongs to the job. In this separate database example,
`Database`, `Idle` and `Loaded(rows)` are types from that application's
model:

```dart
Job<void> load() => run<Idle, void>(
      key: 'load',
      (ctx) async {
        final db = await ctx.join(
          Database.open,
          dispose: (db) => db.close(),
        );

        final rows = await ctx.join(db.readAll);
        ctx.emit(Loaded(rows));
      },
    );
```

Here, the database belongs to the load operation; only its rows become
controller state. `dispose` closes the database on success, failure or
cancellation, including when cancellation prevents the acquired value
from reaching the body.

For resources obtained elsewhere, `ctx.onDispose(cursor.close)` registers
a cleanup callback. It returns a function you can keep as
`removeDisposer` to unregister the callback without running it. Register
each release once: adding `ctx.onDispose(db.close)` to the example would
close the same database twice.

The job waits for children, then runs registered cleanup in reverse
registration order, awaiting each callback. Cleanup finishes before the
final state handler, outcome delivery and release of the queue. An ordinary
`try`/`finally` remains useful for local work; registered cleanup also
covers the period after the body returns and while its children finish.

### Returning or transferring a resource

Use `discard` instead of `dispose` when the resource is the job's result
and its recipient will own it on success. The corresponding registration
method is `ctx.onDiscard`. These callbacks run when the job ends without
successfully handing out its result. They do not release a resource kept
only inside a successful body; use `dispose` for that case. A waiting call
accepts either `dispose` or `discard`, never both.

For example, a body may return a resource while a child is still running.
The job is not complete yet. If cancellation arrives during that wait,
the caller receives `Cancelled` instead of the resource, and its `discard`
callback releases the resource.

When transferring a registered resource directly to state, first check
the job and remove the resource's registration with `disown`. Given a
database acquired with `dispose` and a state that will own it:

```dart
ctx
  ..check()
  ..disown(db)
  ..emit(Ready(db));
```

These calls are synchronous. If `check` throws, cleanup still owns the
database. If `emit` writes the state and then throws because a synchronous
listener cancelled the job, the database is already owned by the state
and no longer registered for job cleanup.

For an asynchronous transfer, put the transfer and `disown` inside one
awaited `ctx.uncancellable` section. Use a plain `await` for the transfer
inside that section, followed immediately by `disown`. A context checkpoint
between the two could throw cancellation by state rules after ownership
has changed but before its cleanup registration is removed.

### Cleanup ordering and late results

Cancellation can arrive after the body returns, including during cleanup.
If a `discard` registration was skipped on the success path, it is run in
a second pass when cancellation makes it necessary. In that case it runs
after later-processed disposers rather than in strict reverse order.

With `wait`, an abandoned operation can produce its resource after the
job has already finished. The supplied cleanup still releases it, but the
finished job and `close()` cannot wait for that late release. Use `join`
when resource release must precede the next job or controller closure.

Cleanup errors go to error hooks and observers, with a zone fallback
when no handler is installed. A `Cancelled` from cleanup is not reported
as an error. Never await the same job's `done`, `value` or `cancel()` from
its cleanup, or wait for a later job in the same queue: all of them depend
on the current cleanup finishing.

## Children and streams

A root job can split its work into child jobs. Create a child with the
controller's `job(...)` method, then call `await ctx.run(child)` from the
parent body. The child starts immediately, bypassing the queue, subject to
its own start rules. The parent keeps the queue occupied until all its
children finish, even if its body returns earlier.

`ctx.run(child)` returns `Future<T>`. It waits for the child, the child's
children and cleanup. On success, it checks the parent's cancellation and
state rules before returning the value. A child error or cancellation is
thrown into the parent body with its stack trace.

Keep the original `child` to cancel it or inspect `child.done`. To work
concurrently in parent and child, handle the returned future separately.
Their state writes can then interleave. `ctx.run(child).ignore()` explicitly
ignores that future's result while the parent still waits for its children.
`child.ignore()` alone does not handle errors of the future returned by
`run`.

Accepted parent cancellation propagates to children. This also applies
when the parent throws `Cancelled`, including an uncaught cancellation
from `await ctx.run(child)`. A parent body that fails instead lets its
children finish and waits for them. A child can refuse cancellation;
`ctx.run` still waits for it and checks the parent after child success.

A child rejected by its start rules still receives its parent, level and
observer, but requires no further waiting. A throwing start rule fails
the child and propagates that error through `ctx.run`.

### Processing a stream

`ctx.each(stream, onData)` creates and returns a child `Job<void>` that
owns the subscription. Each event callback receives that child's context.
Use it for state access and cancellation-aware operations:

```dart
Job<void> track() => run<Ready, void>(
      key: 'track',
      (ctx) => ctx.each(
        hw.positions,
        (child, p) => child.emit(child.state.copyWith(position: p)),
      ).value,
    );
```

This application-specific example copies hardware positions into a
`Ready` state. Returning the child's `.value` makes stream and callback
errors propagate into the parent body. Use `.done` to inspect the outcome,
or retain the returned job and call its `cancel()` to stop only this
subscription.

Events are processed in order. An asynchronous callback finishes before
the next callback starts; the first stream or callback error stops
processing. Cancellation removes the subscription immediately, prevents
further delivery, and waits for the current callback before completing
the child. Use the callback's context for waits; a plain `await` can keep
the child and parent alive indefinitely.

The parent waits for this child even without an explicit await, so an open
stream with no events still keeps the parent running. Accepted parent
cancellation, including during `close()`, cancels the child. The child is
cancellable even if the parent is not. It retains the parent's `W` and
`keepWhile` after the parent body returns, but does not repeat `canStart`.
Observers see it as a separate job.

Cancelling only the child does not directly cancel the parent. An uncaught
`Cancelled` from the child's `.value` does cancel the parent through its
body. Do not await the child's own completion or `cancel()` inside its
event callback, because the child is already waiting for that callback.

The future returned by the underlying stream subscription's `cancel()`
is not awaited. Await asynchronous source cleanup separately if needed.
Normal completion requires the source to send `onDone`. Like `ctx.run`,
`each` cannot start a child after the parent body ends, during cleanup,
or from `unattended` work.

### Following another controller

A controller dedicated to following another controller can keep a job
running over its stream. Read the current state first because the stream
only carries later updates:

```dart
final class ScreenController extends Solo<Screen> {
  final Solo<Session> session;

  ScreenController(this.session) : super(const Screen());

  Job<void> follow() => run<Screen, void>(
        key: 'follow',
        (ctx) async {
          void take(SoloContext<Screen, Screen> target, Session next) =>
              target.emit(target.state.copyWith(signedIn: next.signedIn));

          take(ctx, session.state); // what has already happened
          await ctx.each(session.stream, take).value; // what happens next
        },
      );
}
```

Here, `Screen` and `Session` are application states with a `signedIn`
property. The subscription keeps the following controller's queue
occupied until it ends. If that controller must also process other jobs,
use an external listener that queues a short job for each update instead.
When the update represents an immediate change to the validity of current
work, consider the [External state](#external-state) rules instead.

### Chaining completed work

`job.then((ctx, value) => ...)` creates a job that runs after its source
succeeds, including children and cleanup. Its callback receives the result
and a new core `JobContext`, and may return a value or future. A source
failure propagates without calling the callback.

The continuation does not inherit the controller's state context, rules,
observer or queue position. It has its own optional observer. To change
controller state, call a method that enqueues another job; other queued
jobs may run between the two operations. Use children within one parent
when the whole sequence must occupy the queue without another root job
running between its steps.

Cancellation propagates forward to continuations and backward to
unfinished sources, subject to each job's cancellation rules. Cancelling
the tail waits for those sources and their cleanup, including a source
that refuses cancellation. `close()` reaches a continuation through an
unfinished source, but does not own a continuation already running after
the source finished.

## Event accumulation

An accumulator groups incoming values into queued jobs. Create it once
and call its `add(event)` method for each input:

- `collect` keeps accepted events in a list.
- `accumulate` combines them with a synchronous `merge` function. The
  function decides what to retain; keeping only the latest value is one
  possible choice.

Only the queued job's handler updates controller state. A running group
does not accept new input. Groups can combine only when they belong to
the same accumulator.

| Accumulation policy | How input joins queued work |
| --- | --- |
| `AccumulationPolicy.adjacent` | Join a compatible group only at the queue's tail. |
| `AccumulationPolicy.join` | Join an existing queued group at its current position. |
| `AccumulationPolicy.replace` | Transfer input to a new job at the tail and cancel the old group. |

### Debounce and throttle

Set `timing` to delay a group's eligibility to start:

- `AccumulationTiming.debounce(duration)` waits for a pause in input.
- `AccumulationTiming.throttle(duration)` limits how often groups start,
  measuring the interval from the previous group's actual start.

These delays do not occupy the running job's position. Waiting groups
remain in `queue` and let other ready jobs pass. The handlers themselves
still run one at a time. Timing does not discard input: `collect` keeps
accepted events and `accumulate` keeps what `merge` returns. Without
`timing`, or with `Duration.zero`, groups are ready immediately.

This search controller retains the latest query and waits for 300 ms
without new input before starting it. `SearchApi` and `SearchState` are
application types:

```dart
final class Search extends Solo<SearchState> {
  final SearchApi api;
  late final _queries = accumulate<SearchState, String, void>(
    (ctx, text) async {
      final results = await ctx.wait(() => api.search(text));
      ctx.emit(SearchState.results(results));
    },
    merge: (previous, incoming) => incoming,
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 300)),
    policy: AccumulationPolicy.join,
    key: 'query',
  );

  Search(this.api) : super(const SearchState.idle());

  SoloJob<void> query(String text) => _queries.add(text);
}
```

A search that has already started finishes before the next one starts.
The returned job exposes the outcome and cancellation, like other jobs.
Closing cancels waiting groups rather than flushing them. See the
[settings and logs recipe](doc/accumulation.md) for grouping examples,
ordering and the outcomes returned to individual callers.

## Error reporting and observation

State handlers and reporting hooks have different responsibilities.
`run(onError: ...)` computes a state after a job fails. The controller's
`onError` method and `SoloObserver.onError` receive errors for logging or
reporting, including errors from cleanup and abandoned operations.

A controller can override `onStart`, `onFinish`, `onError`, `onLog` and
`onChange`. For example, add an error hook to the profile controller:

```dart
final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  // ...the jobs above...

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    reportCrash(error, stackTrace);
  }
}
```

`SoloObserver` receives the same events across controllers, plus
`onCreate` and `onClose`. Install one at application startup:

```dart
final class LoggingObserver extends SoloObserver {
  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job finished ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      print('state: $current');
}

void main() {
  SoloBase.observer = LoggingObserver();
}
```

The observer is called before the controller's corresponding hook.
Each call is independent; omitting `super` in a controller hook does not
disable the observer. An error thrown by either hook is sent to the
current Dart zone without changing the job's outcome, stopping the queue,
or preventing the other hook from running.

### Handled and unhandled failures

Accessing `job.done` or `job.value`, or calling `job.ignore()`, marks the
outcome as observed. A `Failed` outcome that nobody observes goes to the
job's creation zone through `Zone.handleUncaughtError`, in addition to
the error hooks. An installed observer alone does not mark outcomes as
observed. If the observer handles reporting and the caller needs no result:

```dart
profile.load().ignore(); // the counterpart of Future.ignore
```

Errors from cleanup, cancellation callbacks and operations abandoned by
`wait` go to the reporting hooks. Without an overridden error hook or an
installed observer, they fall back to the job's creation zone. Such an
error can arrive after the job has already completed. It does not replace
an existing cancellation outcome. These reporting paths exclude
`Cancelled` itself.

An unhandled error of `job.value` or `ctx.run(child)` is still an unhandled
Future error under Dart's rules, even if that error is `Cancelled`.
Handle those futures with `await`, `catchError` or `ignore()` as appropriate.

### Catching errors inside a body

`Cancelled` implements `Exception`, so a broad `catch` also catches
cancellation. If a body needs its own error handling, pass cancellation
through first. This fragment handles a camera failure while preserving
cancellation:

```dart
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Cancelled {
  rethrow;
} on Object catch (error) {
  ctx.emit(Broken(error));
  rethrow;
}
```

Once a job has accepted cancellation, its outcome remains `Cancelled`
even if the body catches it. A catch block can still execute unwanted
work, such as retrying the operation. For a final failure state, prefer
the `onError` parameter of `run` rather than writing that correction
inside a broad catch.

### Errors in state rules

Rules should return a boolean. If a start rule throws, the job fails and
the queue continues. If a rule throws at a context checkpoint, the body
receives the error. During re-evaluation after a state update, a throwing
rule is reported but does not itself cancel the running body. If that
check also controls a final state handler, the handler is disabled.

Re-evaluation errors fall back to the controller's creation zone when no
error hook or observer handles them. In the root Dart zone, an unhandled
error can terminate the application. Install error reporting and observe
job outcomes according to your application's needs.

### Background work and logs

`ctx.unattended(action)` starts work that the job does not wait for or
cancel. Its errors are reported through the job's error hooks, even after
the job finishes, with the same zone fallback when no handler is installed.
Use it for work with an independent lifetime. Starting children from
this work is prohibited. A captured context still belongs to the original
job: `emit` can work while that job is active, but is rejected after
cancellation or completion. The background operation does not extend
the context's lifetime. A bare `unawaited(future)` does not provide
the error routing of `unattended`.

`ctx.log(data)` forwards application data to log hooks and observers.
`SoloBase.debug = print` additionally traces the controller's internal
queue and lifecycle operations.

## Testing

Await a job's outcome to synchronize a test before asserting state. The
following example uses `package:test`; `FakeProfileApi` is a test
implementation that returns `'Ada Lovelace'`:

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;

  expect(outcome, isA<Done<String>>());
  expect(
    profile.state,
    isA<Loaded>().having((state) => state.name, 'name', 'Ada Lovelace'),
  );

  await profile.close();
});
```

Use `job.value` when testing the returned value, or
`await expectLater(profile.load().value, throwsA(...))` for a failure.

For timing and ordering, use `package:fake_async`. In the following test,
the fake API completes after 20 ms. An observer records state changes and
job completion in one ordered list:

```dart
final class Journal extends SoloObserver {
  final lines = <String>[];

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      lines.add('state: ${current.runtimeType}');
}

test('a second load while the first one runs is dropped', () {
  fakeAsync((async) {
    final journal = Journal();
    SoloBase.observer = journal;
    addTearDown(() => SoloBase.observer = null);
    final profile = ProfileController(FakeProfileApi());

    final first = profile.load();
    async.flushMicrotasks();
    final second = profile.load();
    expect(identical(first, second), isTrue);

    async.elapse(const Duration(milliseconds: 20));
    expect(journal.lines, [
      'load started',
      'state: Loading',
      'load Cancelled(manual: duplicate)',
      'state: Loaded',
      'load Done(Ada Lovelace)',
    ]);

    profile.close();
    async.flushTimers();
  });
});
```

The cancelled duplicate in the journal is the newly created job that
`droppable` discarded. Both method calls returned the original job.
Reset the global observer with `addTearDown` so a failed test cannot leave
it installed for later tests.

Inside `fakeAsync`, request cancellation with `job.cancel().ignore()` and
advance pending work before asserting. `flushMicrotasks()` runs microtasks;
`Future(...)` and `Future.delayed(...)` use timers and require `elapse(...)`
or `flushTimers()`. Use `emitsInOrder` when the stream itself matters;
for final state, reading `state` after `job.done` is usually sufficient.

## Timeouts

`Future.timeout` limits waiting for a future; it does not stop the
underlying operation. For a request whose result may be abandoned,
`ctx.wait(() => api.fetch().timeout(...))` can be sufficient.

For a device operation that must stop before the next job, connect a timer
to the device's cancellation mechanism and await the operation with
`join`. In this example, the hardware API completes with an error when
its token is cancelled, so a timeout fails the job:

```dart
Job<void> connect() => run<Idle, void>(
      key: 'connect',
      (ctx) async {
        final token = CancelToken();
        final timer = Timer(const Duration(seconds: 5), token.cancel);
        ctx.onCancel(token.cancel);
        try {
          await ctx.join(() => hw.open(cancelToken: token));
        } finally {
          timer.cancel();
        }
        ctx.emit(const Connected());
      },
    );
```

The `finally` block cancels the timer on every exit. Whether the device
actually stops, and which error it returns, depends on that device's API.

## Flutter

Use `SoloListenable<S>` from `flutter_solo` as the controller base class.
It extends `Solo<S>` and implements `ValueListenable<S>`. The profile
controller keeps the same states and `load` method:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

final class ProfileController extends SoloListenable<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  // ...the jobs above...
}
```

A screen can own its controller: create it in `initState` and close it
in `dispose`. A shared controller can instead live in your existing
dependency container, such as `provider`, `get_it` or an `InheritedWidget`.
The code that owns it is responsible for closing it; `flutter_solo` does
not provide a `SoloProvider` or close controllers automatically.

`ValueListenableBuilder` rebuilds when state changes. To navigate or show
a message after a particular operation, await that job's outcome at the
call site. Check `mounted` after waiting before using the widget's context.
Here, `ProfilePage` is the destination screen in the application:

```dart
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController profile;

  @override
  void initState() {
    super.initState();
    profile = ProfileController(ProfileApi());
  }

  @override
  void dispose() {
    unawaited(profile.close());
    super.dispose();
  }

  Future<void> _open() async {
    final outcome = await profile.load().done;
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case Done():
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
        );
      case Failed(:final error):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      case Cancelled():
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ValueListenableBuilder<ProfileState>(
            valueListenable: profile,
            builder: (context, state, _) => state is Loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _open,
                    child: const Text('Open profile'),
                  ),
          ),
        ),
      );
}
```

`value` and `state` refer to the same object. There is no value setter;
controller jobs perform updates through their context. `ListenableBuilder`
and `AnimatedBuilder` also accept the controller when the builder does
not need the state value itself.

## Coming from bloc

Callers invoke controller methods and receive a job for each operation.
Queue policy is selected per call, and all root jobs share one queue.
These are the main API correspondences:

| bloc | solo |
| --- | --- |
| `Bloc<E, S>`, `Cubit<S>` | `Solo<S>`, `SoloListenable<S>` |
| Event class, `on<E>`, `add(E())` | Method returning `Job<T>` |
| `EventTransformer` | `Policy` on a job submission |
| `emit(next)` | `ctx.emit(next)` |
| `if (emit.isDone) return;` | Cancellation checkpoints such as `ctx.wait` and `ctx.check` |
| `emit.onEach`, `emit.forEach` | `ctx.each(stream, onData)` |
| `state`, `stream` | `state`, `stream` |
| `BlocObserver` | `SoloObserver` |
| `BlocBuilder`, `BlocSelector` | `ValueListenableBuilder`; selection is application code |
| `BlocListener` for an operation's result | Await that operation's `job.done` |
| `BlocProvider` | Your chosen ownership or dependency mechanism |
| `close()` | `close()` |
| `blocTest` | `test` and an awaited job outcome |

`sequential`, `droppable` and `restartable` correspond to
`Policy.sequential`, `Policy.droppable` and `Policy.restart`.
`Policy.replace` removes queued work while leaving the running job alone.
There is no concurrent root-job policy; use children or separate
controllers for independent concurrent work.

The package does not include retry policies, built-in timeouts, worker
pools, dependency injection, persistence or state equality filtering.
If work needs cancellation and cleanup but no state rules or controller
queue, [async_job](https://pub.dev/packages/async_job) can be used directly.
For a value with no asynchronous lifecycle, a `ValueNotifier` may suffice.

[solo and bloc, side by side](https://github.com/vi-k/solo/blob/main/packages/solo/doc/vs-bloc.md)
compares ten application scenarios with implementations in both packages.

## Camera example

The following example combines state rules, queue policies and explicit
device cleanup. It uses a separate state hierarchy from the profile
example. `NotDisposed` groups every state in which hardware operations
may still be performed:

```dart
sealed class CameraState {
  const CameraState();
}

sealed class NotDisposed extends CameraState {
  const NotDisposed();
}

final class Initial extends NotDisposed {
  const Initial();
}

final class Preparing extends NotDisposed {
  const Preparing();
}

final class Ready extends NotDisposed {
  final double zoom;
  final bool paused;

  const Ready({this.zoom = 1, this.paused = false});

  Ready copyWith({double? zoom, bool? paused}) =>
      Ready(zoom: zoom ?? this.zoom, paused: paused ?? this.paused);
}

final class Disposed extends CameraState {
  const Disposed();
}
```

`FakeCameraHardware` and `Photo` are supplied by the runnable
[`example/`](example) package. The controller below shows its main
operations:

```dart
enum CameraKey { init, closeCamera, setZoom, takePhoto, dispose }

final class CameraController extends Solo<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

  Job<void> init() => run<NotDisposed, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        canStart: (state) => state is Initial,
        (ctx) async {
          ctx.emit(const Preparing());
          await ctx.join(hw.open);
          ctx.emit(const Ready());
        },
      );

  Job<void> setZoom(double zoom) => run<Ready, void>(
        key: CameraKey.setZoom,
        policy: Policy.replace,
        describe: () => 'zoom: $zoom',
        canStart: (state) => !state.paused,
        (ctx) async {
          await ctx.join(() => hw.setZoom(zoom));
          ctx.emit(ctx.state.copyWith(zoom: zoom));
        },
      );

  Job<Photo> takePhoto() => run<Ready, Photo>(
        key: CameraKey.takePhoto,
        policy: Policy.droppable,
        canStart: (state) => !state.paused,
        (ctx) async {
          final photo = await ctx.join(hw.capture);
          queue.clear();
          ctx.log('captured $photo');
          return photo;
        },
      );

  Job<void> _closeCameraJob() => job<NotDisposed, void>(
        key: CameraKey.closeCamera,
        cancellable: false,
        (ctx) async => hw.close(),
      );

  Job<void> dispose() {
    queue.clear(force: true);
    current?.cancel();
    return run<CameraState, void>(
      key: CameraKey.dispose,
      policy: Policy.droppable,
      cancellable: false,
      (ctx) async {
        if (ctx.state is Disposed) {
          return;
        }
        if (ctx.state is! Initial) {
          await ctx.run(_closeCameraJob());
        }
        ctx.emit(const Disposed());
      },
    );
  }
}
```

`init` starts only from `Initial`, but uses `NotDisposed` as its working
type so it can continue after emitting `Preparing`. `setZoom` replaces
queued zoom requests while allowing the running request to finish.

After taking a photo, `takePhoto` clears cancellable queued commands. This
example treats commands accumulated during capture as belonging to that
capture; clearing prevents them from affecting the next one. The running
job is unaffected by `queue.clear()`.

`dispose()` is an application operation that closes the hardware and
publishes `Disposed`. It clears pending work and requests cancellation of
the running job before queuing its own non-cancellable teardown. The
child `_closeCameraJob` also refuses ordinary cancellation. The controller's
`close()` is a separate lifecycle operation, so await device disposal
before closing the controller:

```dart
final camera = CameraController(FakeCameraHardware());
await camera.init().done;

camera.setZoom(2); // no await needed, and no lint about it

final photo = await camera.takePhoto().value;

switch (await camera.dispose().done) {
  case Done():
    print('disposed');
  case Cancelled(:final reason):
    print('cancelled: $reason');
  case Failed(:final error):
    print('failed: $error');
}

await camera.close();
```

The runnable example extends this controller with a `Broken` state,
reopening, pause, resume and focus operations. Its fake hardware responds
with delays and can fail independently. Tests check ordered event journals,
and `bin/main.dart` prints one while the scenario runs:

```sh
cd example
dart pub get
dart run bin/main.dart
dart test
```
