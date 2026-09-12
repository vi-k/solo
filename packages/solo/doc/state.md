# State

## State and rules

`Solo<S>` stores one immutable state of type `S`. A job declares which
states it may start in and which it may keep running in, and the engine
checks those rules for it:

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

The first type argument of `run<W, T>` is the job's working state type,
`W extends S`. The body reads `ctx.state` as `W`, so `run<Ready, void>`
can start only in `Ready`. When another state update sets `paused` to
true, `keepWhile` cancels the recording; the callback does not need to
repeat that condition. Here `Ready`, `camera` and `store` belong to the
application, and `ctx.each` processes the stream — its full lifecycle is
explained under [Children and streams](children.md).

Use separate classes when states allow different operations, and shared
base types when an operation can span several states.

| Rule | Checked when |
| --- | --- |
| Working type `W` | Before start, on other state updates while the body runs, and at state checkpoints. |
| `canStart` | Once, when the job is about to start. |
| `keepWhile` | Before start, on other state updates while the body runs, and at state checkpoints. |

If a start check fails, the job ends with `Cancelled` and `started: false`.
A failing `W` or `keepWhile` check during execution cancels the job with
`RulesCancelReason`. These rules reject unsuitable work; they do not keep
it queued until the state becomes suitable.

### Reading and updating state

```dart
(ctx) async {
  // Reads are checkpoints: cancellation and the rules are checked.
  final free = ctx.state.free;
  final ready = ctx.stateAs<Ready>();
  ctx.check();

  // The only write, and it is synchronous.
  ctx.emit(Recording(free: free, zoom: ready.zoom));
}
```

`ctx.state`, `ctx.stateAs<T>()` and `ctx.check()` check cancellation and
state rules. `stateAs<T>()` additionally requires the state to be `T`;
a mismatch cancels the job. Waiting methods use state checkpoints too.

`ctx.emit(next)` allows a job to publish a state outside its own working
type: an initialization job may finish by emitting `Ready`. A later state
checkpoint will reject that state if it does not match `W`, so such a
transition should be the body's last state-dependent step. `canStart` is
never repeated after an emit.

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

```dart
// A read at any moment.
print(camera.currentState);

// Every update, in order, on a microtask. The initial state is not
// replayed, and an equal state still produces an event.
final subscription = camera.stream.listen(print);
```

Anyone holding the controller can read `currentState`. By the time a
stream event arrives, `currentState` may already contain a newer value.
It is deliberately not called `state`: a job body reaches every member of
its controller unqualified, and an unchecked read there would look
exactly like the checked `ctx.state`.

| Type | Provides |
| --- | --- |
| `SoloBase<S>` | State, jobs, queue and rules. |
| `Solo<S>` | All of `SoloBase` plus a broadcast `stream`. |
| `SoloListenable<S>` | All of `Solo` plus Flutter's `ValueListenable<S>`. |

`SoloListenable` listeners run synchronously, in subscription order.
Its stream remains asynchronous.

## External state

An independent source — a device, a socket — changes without waiting for
the controller. `externalSetState(next)` reflects a change that has
already happened there:

```dart
final class Camera extends Solo<CameraState> {
  final Device device;
  late final StreamSubscription<bool> _link;

  Camera(this.device) : super(const Ready()) {
    _link = device.connection.listen((connected) {
      // The device has already disconnected: reflect the fact at once
      // instead of queueing a job that would wait behind the current one.
      if (!connected) {
        externalSetState(const Disconnected());
      }
    });
  }

  @override
  Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) async {
    // Stop the external listener first: it can still change state.
    await _link.cancel();
    await super.close(mode: mode);
  }
}
```

The method is `@protected` and is called from inside the controller
subclass, typically by a listener registered there.

Consider what the alternative costs. If the listener queued a separate job
to publish `Disconnected`, that update would wait behind the current job.
Until then the controller still reports a connected state, the current
job's rules cannot react to the disconnection, and that job may itself be
waiting for a response that will never arrive. Calling `externalSetState`
updates state immediately and re-evaluates running jobs, so a job whose
rules require a connection is cancelled. Its waiting method determines
when its body resumes and whether the underlying operation must finish;
the queue still waits for the job's body and cleanup before starting
another root job.

The distinction is what the notification represents. If it says that an
independent entity has already changed, reflect that fact immediately.
If it asks the controller to perform work, such as refresh data or save an
incoming value, enqueue a normal job. An event being delivered by a stream
does not by itself justify bypassing the queue.

Use job bodies and their state handlers for the controller's own success,
failure and cancellation. `externalSetState` is an exception for external
facts, not a general setter for those operations. It still changes
`currentState` and calls change hooks after `close()`, while `Solo`'s
closed stream no
longer delivers updates — which is why the listener is stopped first.

## State after failure or cancellation

```dart
run<ProfileState, String>(
  // Both compute a state and nothing else. They run after the body,
  // children and cleanup, and the outcome is already fixed.
  onError: (state, error, stackTrace) => Failure(error),
  onCancel: (state, cancelled) => const Initial(),
  (ctx) async {
    ctx.emit(const Loading());
    return ctx.wait(api.fetchName);
  },
);
```

The `onError` and `onCancel` parameters of `run` and `job` let a controller
leave a temporary state such as `Loading` when an operation fails or is
cancelled. They receive the current state of type `S`, plus the error and
stack trace or the `Cancelled` outcome, and return the next state
synchronously.

The matching handler runs before the next queued job and before the
`onFinish` hook. Changing state does not turn `Failed` or `Cancelled` into
`Done`, and does not mark the outcome as handled for error reporting.

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

| What happens | What becomes of the handlers |
| --- | --- |
| An incompatible external update, whenever it arrives | Disabled for good; a later compatible update does not bring them back. |
| A parent loses its permission | Its children's handlers are blocked as well. |
| Success, a discarded duplicate, a body that never started | Not run at all. |
| The job's own `emit` | Nothing; it does not disable its own handlers. |
| A handler throws | The error is reported; the outcome and the queue are untouched. |
| A rule throws while eligibility is checked | Handlers disabled and the error reported. Resource cleanup still runs. |

These extra checks apply to jobs with their own state handlers. A parent
without handlers stops checking its rules when its body ends; children
then remain subject to their own rules and any permission the parent
already lost. `canStart` is checked only at entry.

Keep these functions limited to computing state. Resource release belongs
in the [cleanup API](resources.md).
