# State

`Solo<S>` stores one immutable state of type `S`, and a job declares which
states it may start in and which it may keep running in. Four sections below
open with the version this API's own vocabulary leads to — what you write when
you reach for `run` and stop there — and say what it does instead of what it
was meant to do. The version that works follows under its own heading.

## State and rules

A recording needs free space before it starts, and it has to stop when the
camera is paused.

### The first attempt

```dart
Job<void> record() => run<CameraState, void>(
      key: 'record',
      (ctx) async {
        final state = ctx.state;
        if (state is! Ready || state.paused) return;
        await for (final frame in device.frames) {
          await store(frame);
        }
      },
    );
```

The check reads well, and it runs once. Nothing brings it back: by the time
another update sets `paused`, the body is already inside the loop, and a loop
is not a state checkpoint. A frame that arrives before the pause and two that
arrive after it are stored alike.

The job does not end either. `await for` is no checkpoint, so the cancellation
`close` sends never reaches the body, and closing the controller waits until
the stream itself ends.

### The rules

```dart
Job<void> record() => run<Ready, void>(
      key: 'record',
      canStart: (state) => state.free > 0,
      keepWhile: (state) => !state.paused,
      (ctx) => ctx.each(
        device.frames,
        (child, frame) => child.join(() => store(frame)),
      ).value,
    );
```

The rules are parameters, and the engine checks them for the job. The working
type narrows from `CameraState` to `Ready`, so the state the body reads is the
one it needs, and the condition the first attempt checked by hand is now
`keepWhile`.

The first type argument of `run<W, T>` is the job's working state type,
`W extends S`. The engine checks it, so `run<Ready, void>` starts only in
`Ready`; the body reads `ctx.state` as `W` for the same reason. When another
state update sets `paused` to true, `keepWhile` cancels the recording; the body
does not need to repeat that condition. Here `Ready`, `device` and `store`
belong to the application, and `ctx.each` processes the stream — its full
lifecycle is explained under [Children and streams](children.md).

Use separate classes when states allow different operations, and shared base
types when an operation can span several states.

| Rule | Checked when |
| --- | --- |
| Working type `W` | Before start, on other state updates while the body runs, and at state checkpoints. |
| `canStart` | Once, when the job is about to start. |
| `keepWhile` | Before start, on other state updates while the body runs, and at state checkpoints. |

Any of these rules cancels the job with `RulesCancelReason`; what differs is
`started`. A refused start ends the job with `started: false`, and a `W` or
`keepWhile` check that fails while the body runs ends it with `started: true`.
These rules reject unsuitable work; they do not keep it queued until the state
becomes suitable.

### Reading and updating state

```dart
Job<void> zoomIn() => run<Ready, void>(
      (ctx) async {
        // A read is a checkpoint: cancellation and the rules are checked.
        final state = ctx.state;

        // The only write, and it is synchronous.
        ctx.emit(Recording(free: state.free, zoom: state.zoom + 1));
      },
    );
```

`ctx.state`, `ctx.stateAs<T>()` and `ctx.check()` check cancellation and state
rules. The body above is `run<Ready, void>`, so `ctx.state` is a `Ready`
already; `stateAs<T>()` is for a body whose `W` is wider than the state it
needs at that moment, and it requires the state to be `T` rather than returning
null -- a mismatch cancels the job. Waiting methods use state checkpoints too.

`check()` is the same check, minus the value to read. The other members of the
context check themselves; `check()` covers the gaps between them. A plain
`await` and the return from `ctx.uncancellable` check nothing: a job the rules
have already cancelled walks on until something inside asks: can it still go
on? Those gaps are covered in [Cancellation](cancellation.md), where `check()`
stands beside the waiting methods it goes with.

`ctx.emit(next)` allows a job to publish a state outside its own working type:
an initialization job may finish by emitting `Ready`. A later state checkpoint
will reject that state if it does not match `W`, so such a transition should be
the body's last state-dependent step. `canStart` is checked once, at the start,
and nothing brings it back later -- this emit included.

Other running bodies are checked after a state update. A job's own emit is
excluded from that rule check, but still checks cancellation before and after
writing. Both `onChange` (see [Errors](errors.md)) and a listener run
synchronously inside the write, and neither has a `ctx`: the only write open to
either one is [`externalSetState`](#externalsetstate). A hook that corrects a
state this way -- turning one job's `Preparing` straight into `Working` -- can
therefore cancel the emitting job before its own `emit` returns.

Rules stop cancelling a job once its body has ended. Manual cancellation,
controller closing and parent cancellation can still reach it while it waits
for children or cleanup. Jobs with state handlers also keep checking whether
those handlers may update state; see
[State after failure or cancellation](#state-after-failure-or-cancellation).

### Observing state

```dart
// A read at any moment.
print(camera.currentState);

// Every change, synchronously, inside the change itself. The listener
// reads the new state itself, so nothing it reads can be stale.
camera.addListener(() => print(camera.currentState));

// Every update, in order, on a microtask. The initial state is not
// replayed, and an equal state still produces an event. Needs
// `with SoloStream` on the controller -- see the table below.
final subscription = camera.stream.listen(print);
```

Anyone holding the controller can read `currentState`. By the time a stream
event arrives, `currentState` may already contain a newer value. It is
deliberately not called `state`: a job body reaches every member of its
controller unqualified, and an unchecked read there would look exactly like the
checked `ctx.state`.

| Type | Provides |
| --- | --- |
| `Solo<S>` | State, jobs, queue, rules and listeners. |
| `Solo<S> with SoloStream` | All of `Solo` plus a broadcast `stream`. |
| `Solo<S> with SoloListenable` | All of `Solo` plus Flutter's `ValueListenable<S>`. |

`addListener` is the engine's own member, on `Solo` itself, so what follows
holds for every controller -- one with a delivery of its own and one without
any. The listeners run synchronously, in registration order, inside the change
itself: after the state is written, before the rules of the running jobs are
re-evaluated, and before the next line of the code that changed the state.

A change made from inside a listener does not get that order. It goes to the
end of the publication queue rather than ahead of it:

```text
externalSetState(B)
    listeners of B
        externalSetState(C)        // a listener writes again
            rules, against C       // the write of C runs them at once
        next line of the listener
    listeners of C                 // the queue reaches C only here
    rules, against C               // the write of B runs them last, on C
next line of the writer
```

So the nested change is answered for by the rules before its own writer goes
on, and heard by the listeners last. The outer change never reaches the rules
as itself: by the time its re-evaluation runs, the state it asks about is the
nested one.

The second question about C is the only one asked after the listeners of C: a
rule that reads nothing but the state answers it as it answered the first, and
a job that the first answer cancelled is not asked again. A `keepWhile` that
also reads a field of the controller sees what those listeners wrote there only
in the second.

Like `ChangeNotifier`, `removeListener` matches with `==` rather than identity,
so a widget can subscribe in `initState` and unsubscribe in `dispose` with a
method of its own. A listener that throws stops neither the listeners after it
nor the re-evaluation that follows them: its error goes to `onListenerError`,
which hands it to the zone unless a subclass says otherwise.

The engine drops the listeners for good when closing finishes, not when
`close()` is called — the same moment `isFinished` turns true. From then on
`addListener` does nothing: the listener is neither registered nor kept, and
nothing is thrown. The state stops at the same line: `externalSetState` past it
throws a `StateError`.

`SoloListenable` adds Flutter's `ValueListenable` to that and nothing else. It
is a mixin on `Solo`, the way `SoloStream` is: a widget rebuilds from `value`,
and a controller that needs both deliveries mixes in both.

### A delivery of your own

The listeners above are the engine's, and they cover the common case. `publish`
is the seam for delivery of another kind — a stream, a signal, a line in a log:

```dart
/// A controller that writes every change to a log.
class Logged<S extends Object> extends Solo<S> {
  final void Function(String line) write;

  Logged(super.initialState, this.write);

  @override
  void publish(S previous, S current) {
    super.publish(previous, current);
    try {
      write('$previous -> $current');
    } on Object catch (error, stackTrace) {
      // The engine re-evaluates the rules of the running jobs right after
      // this call. An error let out of here would cost a job the
      // cancellation the new state owes it.
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}
```

Two things such an override owes:

| What it owes | Why |
| --- | --- |
| `super.publish` comes first | It is what calls the listeners, so a delivery of your own runs after the engine's rather than instead of it. `@mustCallSuper` says so and the analyzer holds you to it. |
| A failure must not leave `publish` | The rules of the running jobs are re-evaluated right after the call, and an error let out of here costs a job the cancellation the new state owes it. It goes to `Zone.current.handleUncaughtError` from `dart:async`, where a failing hook's error goes. |

`SoloStream` is this override with a broadcast `StreamController` behind it,
and `SoloListenable` is the engine's listeners plus Flutter's
`ValueListenable`, which is what makes builders and `Listenable.merge`
understand a controller.

## External state

An independent source — a device, a socket — changes without waiting for the
controller, and the controller has to show what has already happened there.

### The first attempt

```dart
Camera(this.device) : super(const Ready()) {
  _link = device.connection.listen((connected) {
    if (!connected) {
      // The fact goes in like any other work, ahead of everything waiting.
      add(
        job<Ready, void>(
          key: 'disconnect',
          (ctx) async => ctx.emit(const Disconnected()),
        ),
        first: true,
      );
    }
  });
}
```

`first: true` gets the update ahead of everything that is waiting, not ahead of
the job that is running: the queue runs one job at a time. Until the update
starts, the controller still reports a connected state, and the running job's
rules are asked on every change — but only ever about the state it already
knew. Worse, that job may itself be waiting for a response the device will
never give, so the update that would free it is standing behind the job it
would free.

### externalSetState

```dart
final class Camera extends Solo<CameraState> with SoloStream {
  final Device device;
  late final StreamSubscription<bool> _link;

  Camera(this.device) : super(const Ready()) {
    _link = device.connection.listen((connected) {
      // The device has already disconnected: reflect the fact at once
      // instead of queueing a job that would wait behind the current one.
      // `isFinished` is false for as long as the engine runs, a drain
      // included, and true once the state is final.
      if (!connected && !isFinished) {
        externalSetState(const Disconnected());
      }
    });
  }

  @override
  Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) async {
    await super.close(mode: mode);
    await _link.cancel();
  }
}
```

The method is `@protected` and is called from inside the controller subclass,
typically from a subscription it holds -- the one on the device above, not a
listener of the controller.

`externalSetState` updates state immediately and re-evaluates running jobs, so
a job whose rules require a connection is cancelled by the disconnection
itself. Its waiting method determines when its body resumes and whether the
underlying operation must finish; the queue still waits for the job's body and
cleanup before starting another root job.

What to do with a notification — reflect it with `externalSetState` or queue a
job for it — depends on what it means. If it says that an independent entity
has already changed, reflect that fact immediately. If it asks the controller
to perform work, such as refresh data or save an incoming value, enqueue a
normal job. An event being delivered by a stream does not by itself justify
bypassing the queue.

Stopping the source before `super.close()` is the tidier-looking order, and it
costs nothing only while no running job depends on the fact. With
`SoloCloseMode.drain` it costs the drain: the queue goes on running after the
call, and the jobs in it are the ones that most need to hear that the device is
gone. `SoloCloseMode.cancel` is not safe from it either — a
`cancellable: false` job waiting for an answer the device will never give is
freed by the disconnection, and `close` waits for that job. The `isFinished`
guard is what lets one order serve both modes. The handler above is
synchronous, so its check and its write are one step; a handler that awaits
anything checks after its last `await`, because a suspension in between lets
the engine finish, and the write then throws.

Use job bodies and their state handlers for the controller's own success,
failure and cancellation. `externalSetState` is an exception for external
facts, not a general setter for those operations. It works for as long as the
engine does, a drain included, and throws a `StateError` once closing has
finished: the state a controller stops at is the state it keeps.

## State after failure or cancellation

A load publishes `Loading` before it starts waiting. Something has to take the
controller out of it when the load does not arrive.

### The first attempt

```dart
run<ProfileState, String>(
  (ctx) async {
    ctx.emit(const Loading());
    try {
      final name = await ctx.wait(api.fetchName);
      ctx.emit(Loaded(name));
      return name;
    } on Object {
      ctx.emit(const Initial());
      rethrow;
    }
  },
);
```

The `catch` does run on a cancellation — and that is the trouble, because the
`emit` inside it is a state checkpoint on a job that is already cancelled, so
it throws instead of writing. Cancel the load and the controller stays in
`Loading` for good: the screen shows a spinner for work that is no longer
running.

### The handlers

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
cancelled. They receive the current state of type `S`, plus the error and stack
trace or the `Cancelled` outcome, and return the next state synchronously.

The matching handler runs before the next queued job and before the `onFinish`
hook. Changing state does not turn `Failed` or `Cancelled` into `Done`, and
does not mark the outcome as handled for error reporting.

### Preserving an incompatible external state

The handler above returns `Initial` whenever the load is cancelled. Extend the
profile states from the quick start with `Disconnected` in the same library,
and the connection can now drop while a load is running.

#### The first attempt

```dart
final class Disconnected extends ProfileState {
  const Disconnected();
}

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
```

Nothing here says the load has an opinion about `Disconnected`, so it keeps
running through it. When the load is cancelled after that — by a duplicate, by
a screen closing, by anything — `onCancel` does what it was written to do and
returns `Initial`, over the fact the device reported. The controller now shows
a profile that is merely empty, when what happened is that the connection is
gone.

A `state is Disconnected` check inside the handler would patch this one case.
The job would still be running work that the disconnection made pointless.

#### The rules

```dart
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

The connection drops while the load is running, and the controller publishes
`Disconnected` with `externalSetState`. `keepWhile` rejects that state,
cancelling the load and disabling both final handlers. `Disconnected` therefore
remains visible instead of being replaced by `Initial` or `Failure`.

If the load is cancelled manually while the state is still compatible,
`onCancel` can return `Initial`. The handlers need no extra `state is Loading`
checks: the job's rules express which states permit the operation and its final
correction.

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
without handlers stops checking its rules when its body ends; children then
remain subject to their own rules and any permission the parent already lost.

Keep these functions limited to computing state. Resource release belongs in
the [cleanup API](resources.md).
