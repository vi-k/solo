# State

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
[Children and streams](children.md).

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
