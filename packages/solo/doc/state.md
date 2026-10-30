# State

`Solo<S>` stores one immutable state of type `S`, and a job declares which
states it may start in and which it may keep running in.

The rules of a job are asked by the engine, not by its body:

| Rule | When it is asked | What a refusal does |
| --- | --- | --- |
| Working type `W` of `enqueue<W, T>` | Before start, on other state updates while the body runs, and at state checkpoints | Cancels the job with `RulesCancelReason`: `started: false` before start, `started: true` while the body runs |
| `canStart` | Once, when the job is about to start | Cancels the job with `RulesCancelReason` and `started: false`: the body never runs |
| `keepWhile` | Before start, on other state updates while the body runs, and at state checkpoints | Cancels the job with `RulesCancelReason`: `started: false` before start, `started: true` while the body runs |

A refusal does not keep the job queued until the state suits it, and the job's
`ifFailed` and `ifCancelled` do not run after it. The rules are in
[The rules](#the-rules), the checkpoints in
[Reading and updating state](#reading-and-updating-state), and the handlers in
[Handler eligibility and errors](#handler-eligibility-and-errors).

## State and rules

A recording needs free space before it starts, and it has to stop when the
device reports a pause.

### The first attempt

```dart
// The first attempt: the state is checked once, at the start.
Job<void> record() => enqueue<CameraState, void>(key: 'record', (ctx) async {
  final state = ctx.state;
  if (state is! Ready || state.free == 0 || state.paused) return;
  await for (final frame in device.frames) {
    await store(frame);
  }
});
```

This is what happens:

1. The check runs once, when the body starts.
2. The pause is reported later, when the body is already inside the loop.
3. The loop never looks at the state again, so a frame that arrives before the
   pause and two that arrive after it are stored alike.
4. The job does not end either. `await for` is no checkpoint, so the
   cancellation `close` sends never reaches the body, and closing the
   controller waits until the stream itself ends.

### The rules

```dart
Job<void> record() => enqueue<Ready, void>(
  key: 'record',
  canStart: (state) => state.free > 0,
  keepWhile: (state) => !state.paused,
  (ctx) => ctx.each(device.frames, (child, frame) async {
    await child.join(() => store(frame));
  }).value,
);
```

The rules are parameters, and the engine checks them for the job. Because the
working type narrows from `CameraState` to `Ready`, the rules read `state.free`
and `state.paused` with no check of the type, and the conditions the first
attempt checked by hand are now `canStart` and `keepWhile`.

The first type argument of `enqueue<W, T>` is the job's working state type,
`W extends S`. The engine checks it, so `enqueue<Ready, void>` starts only in
`Ready`, and for the same reason the body reads `ctx.state` as `W`. Here
`Ready`, `device` and `store` belong to the application. `ctx.each` processes
the stream; its full lifecycle is explained in
[Processing a stream](streams.md#processing-a-stream) on the streams page.

When a state update sets `paused` to true, `keepWhile` cancels the recording,
and the body does not need to repeat that condition. That update does not come
from another job of the queue. Root jobs run one at a time, so a `pause()`
written as a job would wait for the recording to end before it could set
`paused`. While the recording runs, an update its rules are asked about comes
from one of two places:

- [`externalSetState`](#externalsetstate), where the controller reflects what
  the device reports;
- a child of the recording.

Use separate classes when states allow different operations, and shared base
types when an operation can span several states.

| Rule | Checked when |
| --- | --- |
| Working type `W` | Before start, on other state updates while the body runs, and at state checkpoints. |
| `canStart` | Once, when the job is about to start. |
| `keepWhile` | Before start, on other state updates while the body runs, and at state checkpoints. |

Any of these rules cancels the job with `RulesCancelReason`, and what differs
is `started`. A refused start ends the job with `started: false`. A `W` or
`keepWhile` check that fails while the body runs ends it with `started: true`.
These rules reject unsuitable work; they do not keep it queued until the state
becomes suitable.

A rule answers and does not write: a write from inside `keepWhile` throws a
`StateError`, and the rule throws with it.

### Reading and updating state

```dart
Job<void> zoomIn() => enqueue<Ready, void>((ctx) async {
  // A read is a checkpoint: cancellation and the rules are checked.
  final state = ctx.state;

  // The body's only way to write, and it is synchronous.
  ctx.emit(state.copyWith(zoom: state.zoom + 1));
});
```

`ctx.state`, `ctx.stateAs<T>()` and `ctx.check()` check cancellation and state
rules. Waiting methods use state checkpoints too. So does `ctx.each`, whose
child would keep the job's rules. The body above is `enqueue<Ready, void>`, so
`ctx.state` is a `Ready` already. `stateAs<T>()` is for a body whose `W` is
wider than the state it needs at that moment. It requires the state to be `T`
rather than returning null: a mismatch cancels the job.

```dart
Job<void> switchOn(int zoom) => enqueue<CameraState, void>(
  canStart: (state) => state is Off,
  (ctx) async {
    // W is every state, so after each wait the body names the one
    // it needs.
    await ctx.join(device.powerUp);
    ctx.stateAs<Off>();
    ctx.emit(const Ready());

    await ctx.join(() => device.setZoom(zoom));
    ctx.emit(ctx.stateAs<Ready>().copyWith(zoom: zoom));
  },
);
```

`switchOn` starts in `Off` and goes on in the `Ready` it writes. Its `W` is
therefore the whole `CameraState`, and `ctx.state` there is a `CameraState`,
which has no `copyWith`. While the device powers up and the lens moves, the
controller may reflect other facts, so after each wait the body reads the state
it needs. The `Ready` it copies at the end is the one it reads, with whatever
the device reported during the zoom.

If the connection drops, the controller reflects `Disconnected` through
[`externalSetState`](#externalsetstate). No rule of this job refuses that
state, so the wait returns as usual. The `stateAs` after the wait ends the job
before the `emit`, with `Cancelled(rules: is not Off)` after the power-up and
`Cancelled(rules: is not Ready)` after the zoom. The state stays
`Disconnected`. `emit` asks none of the job's rules, so it is the read before
it that keeps `Ready` off a camera that is gone.

`check()` is the check `ctx.state` makes, minus the value to read. The reads
and the waiting methods make it themselves, and `check()` covers the gaps
between them. A plain `await` and the return from `ctx.uncancellable` check
nothing. Across such a gap, a job the rules have already cancelled walks on
until something inside asks whether it can still go on. Those gaps are covered
in
[Ordinary await and context lifetime](cancellation.md#ordinary-await-and-context-lifetime)
on the cancellation page. The table at the top of that page puts `check()`
beside the waiting methods it goes with.

`ctx.emit(next)` allows a job to publish a state outside its own working type:
an initialization job may finish by emitting `Ready`. A later state checkpoint
will reject that state if it does not match `W`. A waiting method is such a
checkpoint as much as a read is. After that emit:

- `ctx.abandonable` or `ctx.join` ends the job `Cancelled` before its action
  starts;
- `ctx.each` ends the job instead of starting a child the same rules would
  refuse.

So put such a transition last in the body, with no read, no wait and no
`ctx.each` through the context after it. `canStart` is checked once, at the
start, and is not used again, after this emit either.

Other running bodies are checked after a state update: a job's children run
beside it, and each body answers to its own rules. A job's own emit is excluded
from that rule check, but still checks cancellation before and after writing.
Both `onChange` (see
[Watching every controller](diagnostics.md#watching-every-controller) on the
diagnostics page) and a listener run synchronously inside the write. Neither
has a `ctx`, so the only write open to either one is
[`externalSetState`](#externalsetstate). A hook that corrects a state this way,
turning one job's `Preparing` straight into `Working`, can therefore cancel the
emitting job before its own `emit` returns.

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
// `with SoloStream` on the controller — see the table below.
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
| `Solo<S> with SoloListenable` | All of `Solo` plus Flutter's `ValueListenable<S>`. The mixin comes from [`flutter_solo`](https://pub.dev/packages/flutter_solo). |

`addListener` is the engine's own member, on `Solo` itself. So what follows
holds for every controller, with a delivery of its own or without any. The
listeners run synchronously, in registration order, inside the change itself:

- after the state is written;
- before the rules of the running jobs are re-evaluated;
- before the next line of the code that changed the state.

Like `ChangeNotifier`, `removeListener` matches with `==` rather than identity,
so a widget can subscribe in `initState` and unsubscribe in `dispose` with a
method of its own. `hasListeners` is protected, as in `ChangeNotifier`: it
tells the subclass whether anyone listens. A listener that throws stops neither
the listeners after it nor the re-evaluation that follows them. Its error goes
to `onListenerError`, which hands it to the zone unless a subclass says
otherwise.

The engine drops the listeners for good when closing finishes, the moment
`isFinished` turns true, and not when `close()` is called. From then on
`addListener` does nothing: the listener is neither registered nor kept, and
nothing is thrown. The state stops at the same moment, and from then on
`externalSetState` throws a `StateError`.

`SoloListenable` adds Flutter's `ValueListenable` on top of `addListener`, and
reports a listener's error to `FlutterError` instead of the zone. It is a mixin
on `Solo`, the way `SoloStream` is: a widget rebuilds from `value`, and a
controller that needs both deliveries mixes in both.

A change made from inside a listener does not get the order of the list above.
It goes to the end of the publication queue rather than ahead of it:

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
on, and heard by the listeners last. The outer change never reaches the
re-evaluation as itself: by the time that runs, the state it asks about is the
nested one.

A job with state handlers of its own is still asked about B. It is asked at the
write itself, before any listener, and not to cancel the job but to decide
whether its handlers may still correct the state. If its rules refuse B, the
handlers are disabled for good, like any incompatible external update in
[Handler eligibility and errors](#handler-eligibility-and-errors).

The second question about C is the only one asked after the listeners of C. A
rule that reads nothing but the state answers it as it answered the first, and
a job that the first answer cancelled is not asked again. A `keepWhile` that
also reads a field of the controller sees what those listeners wrote there only
in the second.

### A delivery of your own

The listeners above are the engine's, and they cover the common case. `publish`
is the seam for delivery of another kind, such as a stream or a line in a log:

```dart
/// A controller that writes every change to a log.
class Logged<S extends Object> extends Solo<S> {
  final void Function(String line) write;

  Logged(super.initialState, this.write);

  @protected
  @override
  void publish(S previous, S current) {
    super.publish(previous, current);
    try {
      write('$previous -> $current');
    } on Object catch (error, stackTrace) {
      // The state has changed by now, and the rules of the running jobs
      // are asked about it all the same. An error let out of here would
      // reach whoever wrote the state, as if the write had failed.
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}
```

What such an override owes, and what the engine owes it back:

- **`super.publish` comes first.** It is what calls the listeners, so a
  delivery of your own runs after the engine's rather than instead of it.
  `@mustCallSuper` says so and the analyzer holds you to it.
- **`@protected` is repeated.** Dart does not carry the annotation over to an
  override. Without it `publish` is a public member of the controller. Code
  that holds the controller can then publish a state nobody wrote: the
  listeners are called and the delivery runs, while `currentState` stays what
  it was. The annotation is in `package:meta`.
- **A failure should stay in `publish`.** By the time a delivery fails, the
  write has gone through: the state has changed, and the rules of the running
  jobs have been asked about it. Whoever wrote the state hears of a failed
  delivery as if the write had failed.
- **The changes queued behind a failed one are published all the same.** The
  failed change is gone: it left the publication queue before the call, and
  nothing publishes a change twice. Yet the ones queued behind it are the state
  the controller now holds, and they go out before the failure leaves. Of
  several failures only the first is thrown; the rest go to the zone.

An error let out of `publish` goes back the way the write came:

- a write through `ctx.emit` throws it into the body that called `ctx.emit`;
- a write through `externalSetState` throws it to the caller of
  `externalSetState`;
- a write by a state handler hands it to the controller's `onError` and
  `onUnanswered`.

When the caller of `externalSetState` is a hook of the engine, the error goes
on to `Zone.current.handleUncaughtError` from `dart:async`, where a failing
hook's error goes anyway.

`SoloStream` is this override with a broadcast `StreamController` behind it,
and `SoloListenable` is the engine's listeners plus Flutter's
`ValueListenable`, which is what makes builders and `Listenable.merge`
understand a controller.

`SoloStream` closes the stream after the engine, and the stream waits for every
subscription to take its done event. One left paused holds `close()` after the
engine has finished, and `pending` then says `SoloPendingStream`.

## External state

An independent source, such as a device or a socket, changes without waiting
for the controller, and the controller has to show what has already happened
there.

### The first attempt

```dart
// The first attempt: the update waits behind the running job.
Camera(this.device) : super(const Ready()) {
  _link = device.connection.listen((connected) {
    if (!connected) {
      // The fact goes in like any other work, ahead of everything waiting.
      enqueueJob(
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

This is what happens:

1. `first: true` gets the update ahead of everything that is waiting, not ahead
   of the job that is running: the queue runs one job at a time.
2. Until the update starts, the controller still reports a connected state.
3. The rules of the running job hear nothing of the disconnection. They are
   asked when the state changes, and it has not.
4. Worse, that job may itself be waiting for a response the device will never
   give. Then the update that would free it stands behind the job it would
   free.

### externalSetState

```dart
final class Camera extends Solo<CameraState> with SoloStream {
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

  // Called once, when the last job is over: nothing in the queue needs
  // to hear the device any more.
  @override
  void onClose() => unawaited(_link.cancel());
}
```

`externalSetState` is `@protected` and is called from inside the controller
subclass, typically from a subscription it holds: the one on the device above,
not a listener of the controller.

`externalSetState` updates state immediately and re-evaluates running jobs. So
a job whose rules require a connection is cancelled by the disconnection
itself. Its waiting method determines when its body resumes and whether the
underlying operation must finish. The queue still waits for the job's body and
cleanup before starting another root job.

What to do with a notification depends on what it means:

- if it says that an independent entity has already changed, reflect that fact
  immediately with `externalSetState`;
- if it asks the controller to perform work, such as refresh data or save an
  incoming value, enqueue a normal job.

An event being delivered by a stream does not by itself justify bypassing the
queue.

Use job bodies and their state handlers for the controller's own success,
failure and cancellation. `externalSetState` is an exception for external
facts, not a general setter for those operations. It works for as long as the
engine does, a drain included, and throws a `StateError` once closing has
finished: the state a controller stops at is the state it keeps.

The subscription is cancelled in `onClose`, not when `close` is called. The
engine calls `onClose` once and later, when every job is over and the state is
not final yet, whichever mode closed the controller. Stopping the source when
`close` is called looks tidier, but it has a cost as soon as a running job
depends on the fact:

- with `close(mode: SoloCloseMode.drain)` it costs the drain. The queue goes on
  running after the call, and the jobs in it are the ones that most need to
  hear that the device is gone;
- `SoloCloseMode.cancel` is not safe from it either: a `cancellable: false` job
  waiting for an answer the device will never give is freed by the
  disconnection, and `close` waits for that job.

Once `onClose` has run, the subscription callback above is not called at all,
so its write cannot arrive after the end. A callback that has to await
something before writing is another matter. It starts while the subscription is
alive, and the engine may finish while it waits. Such a callback checks
`isFinished` after its last `await`, right before `externalSetState`. A check
made earlier can go stale, and the write then throws a `StateError`.
`isFinished` is false for as long as the engine runs, a drain included, and
true once the state is final.

## A notice the screen accepts

When a photo is stored, the screen shows a notice, "Photo 7 saved", until the
user closes it. A screen built again, after a rotation or on coming back to it,
shows the notice again while it is open, and a closed one does not come back.
The camera works on meanwhile: a recording started after the shot runs. A
cancelled shot gives no notice.

A screen that started the work and shows how it ended awaits `job.done`, as in
[Jobs and results](jobs.md#jobs-and-results). A notice is for news that
outlives the screen: the screen that shows it may not be the one that took the
shot.

### The first attempt

```dart
// The first attempt: the notice holds the camera until it is closed.
final class Saved extends CameraState {
  final int photo;

  const Saved(this.photo);
}

Job<void> shoot() => enqueue<Ready, void>((ctx) async {
  final photo = await ctx.join(device.shoot);
  ctx.emit(Saved(photo));
});

Job<void> accept() =>
    enqueue<Saved, void>((ctx) async => ctx.emit(const Ready()));
```

The notice is a state of the camera, and the screen shows it while the camera
is in it. But while the notice is on the screen the camera is not `Ready`, and
every job that starts in `Ready` is turned down by its rules. A `record()`
asked for after the shot ends `Cancelled(rules: is not Ready)` with
`started: false`, and so does the next `shoot()`: the commands are lost rather
than kept waiting. The camera stands still until the user closes the notice,
and `accept` brings it back to `const Ready()`, without the zoom it had before.

Writing `Saved` and then `Ready` at once does not hold the camera, but the
notice then lasts for one change. A listener added with `addListener` hears it,
inside the change. A screen built later, and a builder that rebuilds on the
next frame, see `Ready`.

### The second attempt

```dart
// The second attempt: the acceptance waits behind the recording.
Job<void> shoot() => enqueue<Ready, void>((ctx) async {
  final photo = await ctx.join(device.shoot);
  ctx.emit(ctx.state.withNotice(photo));
});

Job<void> accept() =>
    enqueue<Ready, void>((ctx) async => ctx.emit(ctx.state.withNotice(null)));
```

`Ready` has a field here, `int? notice`, and `withNotice` copies the state with
another notice. The camera no longer stands still: the recording starts after
the shot. But the acceptance is a job of the same queue, and it waits for the
recording to end, which runs for as long as the frames come. All that time the
field holds the notice, and a screen built again shows it a second time.
`first: true` of `enqueueJob` does not help: it puts the acceptance ahead of
the jobs that wait, not ahead of the one that runs, as the first attempt of
[External state](#external-state) shows.

The field lives only in `Ready`, so a `Disconnected` written over it wipes the
notice of a photo that has been stored. Accepting with `externalSetState`
clears the field at once, but it goes around the queue: a body that read the
state before a wait and writes a copy of it after brings a closed notice back.

### A board of its own

```dart
final class Notice {
  final int photo;

  Notice(this.photo);
}

final class NoticeBoard {
  final Notice? notice;

  const NoticeBoard([this.notice]);
}

final class Notices extends Solo<NoticeBoard> {
  Notices() : super(const NoticeBoard());

  Job<void> post(Notice notice) =>
      enqueue<NoticeBoard, void>((ctx) async => ctx.emit(NoticeBoard(notice)));

  Job<void> accept(Notice notice) => enqueue<NoticeBoard, void>((ctx) async {
    // Only the notice the screen showed: a newer one stays.
    if (identical(ctx.state.notice, notice)) ctx.emit(const NoticeBoard());
  });
}
```

The camera is handed the board as `notices`, and its shot posts there:

```dart
Job<void> shoot() => enqueue<Ready, void>((ctx) async {
  final photo = await ctx.join(device.shoot);
  notices.post(Notice(photo));
});
```

The notices live in a controller of their own. Its queue holds only short jobs,
so an acceptance does not wait for a recording. The state of the camera knows
nothing of notices: no rule of its jobs is asked about one, and no write of the
camera takes one away. The notice is a field of `NoticeBoard` rather than the
state itself because a state cannot be `null`: `Solo<S extends Object>`. The
board holds one notice at a time, and a second `post` replaces one nobody has
closed. A field and its listeners would do the same work; a controller lets the
screen listen to the board the way it listens to the camera.

The acceptance names the notice it closes. A notice posted while the screen was
closing the one before stays, where an `accept` without an address would wipe
it before anybody saw it. `identical` tells them apart because `Notice` has no
`const` constructor, so every `post` brings a new object. A notice made again
from data, such as one read back from storage, needs an id to compare instead.

`post` comes after the work, so a cancelled shot posts nothing. The device may
have stored the photo all the same, since `ctx.join` lets the call run to its
end, but the notice tells how the job ended, and the job was cancelled.

The screen listens to `notices` with `addListener`, or, with `SoloListenable`
mixed in, with `listen` from `flutter_solo`. It shows `currentState.notice`
and, when the user closes it, calls `accept` with that notice. Two screens that
listen show the same notice, and an acceptance on one takes it off both.

Whoever made the two controllers closes the board once the close of the camera
has completed: `await camera.close(...)`, then `notices.close()`. A camera
closed with `SoloCloseMode.drain` may still post the notice of the shot it
finishes, and a board closed before that turns the `post` down with
`Cancelled(closed)`. A closed board keeps its last state, and a screen that
still listens shows a notice it can no longer close: `accept` ends
`Cancelled(closed)` as well. The cases:

| What you do | What happens |
| --- | --- |
| A shot, then a recording | The recording runs, and the notice is on the board. |
| `accept` during the recording | The board is empty a microtask later, and a screen built again shows nothing. |
| A second shot posts while the first notice is being accepted | The second notice stays. |
| Two shots, and nobody closes the notice | The second notice replaces the first. |
| The shot is cancelled | No notice, though the photo may be stored. |
| The board closed before the drain of the camera has finished | The notice of the shot the drain finishes is lost. |

## State after failure or cancellation

The profile controller of the
[Quick start](https://github.com/vi-k/solo/blob/main/packages/solo/README.md#quick-start)
in the package README publishes `Loading` before its load starts waiting.
Something has to take the controller out of it when the load does not arrive.
The handlers below publish `Failure`, the state that holds the error in
[The profile controller](jobs.md#the-profile-controller).

### The first attempt

```dart
// The first attempt: a cancellation leaves the state at Loading.
enqueue<ProfileState, String>((ctx) async {
  ctx.emit(const Loading());
  try {
    final name = await ctx.abandonable(api.fetchName);
    ctx.emit(Loaded(name));
    return name;
  } on Object {
    ctx.emit(const Initial());
    rethrow;
  }
});
```

This is what happens:

1. On a failure it works: the `catch` writes `Initial` and passes the error on.
2. The `catch` runs on a cancellation too. There the `emit` inside it checks
   the cancellation before it writes, and on a job that is already cancelled it
   throws instead of writing.
3. Cancel the load, and the controller stays in `Loading` for good: the screen
   shows a spinner for work that is no longer running.

### The handlers

```dart
enqueue<ProfileState, String>(
  // Both compute a state and nothing else. They run after the body,
  // children and cleanup, and the outcome is already fixed.
  ifFailed: (state, error, stackTrace) => Failure(error),
  ifCancelled: (state, cancelled) => const Initial(),
  (ctx) async {
    ctx.emit(const Loading());
    final name = await ctx.abandonable(api.fetchName);
    ctx.emit(Loaded(name));
    return name;
  },
);
```

The `ifFailed` and `ifCancelled` parameters of `enqueue`, `job`, `collect` and
`accumulate` let a controller leave a temporary state such as `Loading` when an
operation fails or is cancelled. They receive the current state of type `S`,
plus the error and stack trace or the `Cancelled` outcome, and return the next
state synchronously. A handler that hands back the state it was given, the same
object, leaves the state as it is, and nothing is published; a `const` value
the state already holds is that same object. An equal state that is another
object is published, as an `emit` of it would be.

The matching handler runs before the next queued job and before the `onFinish`
hook. Changing state does not turn `Failed` or `Cancelled` into `Done`, and
does not mark the outcome as handled for error reporting. A job that knows
which of its errors are expected names them in `isExpectedError`, and nobody is
asked to answer for those:
[Naming the expected errors](errors.md#naming-the-expected-errors) on the
errors page. `ifCancelled` runs at completion, so the signal to stop the
operation belongs in `ctx.onCancel`, which delivers it at once.

### Preserving an incompatible external state

The handler above returns `Initial` whenever the load is cancelled. Extend the
profile states from [The profile controller](jobs.md#the-profile-controller)
with `Disconnected` in the same library, and the connection can now drop while
a load is running.

#### The first attempt

```dart
// The first attempt: ifCancelled writes over Disconnected.
final class Disconnected extends ProfileState {
  const Disconnected();
}

Job<String> load() => enqueue<ProfileState, String>(
  key: 'load',
  policy: Policy.droppable,
  ifFailed: (state, error, stackTrace) => Failure(error),
  ifCancelled: (state, cancelled) => const Initial(),
  (ctx) async {
    ctx.emit(const Loading());
    final name = await ctx.abandonable(api.fetchName);
    ctx.emit(Loaded(name));
    return name;
  },
);
```

Nothing here says the load has an opinion about `Disconnected`, so it keeps
running through it. When the load is cancelled after that, by the user, by a
screen closing or by anything else, `ifCancelled` does what it was written to
do. It returns `Initial`, over the fact the device reported. The controller now
shows a profile that is merely empty, when what happened is that the connection
is gone.

A `state is Disconnected` check inside the handler would patch this one case.
The job would still be running work that the disconnection made pointless.

#### The rules

```dart
Job<String> load() => enqueue<ProfileState, String>(
  key: 'load',
  policy: Policy.droppable,
  keepWhile: (state) => state is! Disconnected,
  ifFailed: (state, error, stackTrace) => Failure(error),
  ifCancelled: (state, cancelled) => const Initial(),
  (ctx) async {
    ctx.emit(const Loading());
    final name = await ctx.abandonable(api.fetchName);
    ctx.emit(Loaded(name));
    return name;
  },
);
```

The connection drops while the load is running, and the controller publishes
`Disconnected` with `externalSetState`. `keepWhile` rejects that state,
cancelling the load and disabling both handlers. `Disconnected` therefore
remains visible instead of being replaced by `Initial` or `Failure`.

If the load is cancelled manually while the state is still compatible,
`ifCancelled` still returns `Initial`. The handlers need no
`state is Disconnected` check of their own: the job's rules say which states
permit the operation and the correction after it.

### Handler eligibility and errors

| What happens | What becomes of the handlers |
| --- | --- |
| An incompatible update the job did not make (`externalSetState`, or the `emit` of its parent, of its child or of another child of the same parent), whenever it arrives | Disabled for good; a later compatible update does not bring them back. |
| A parent loses its permission | Its children's handlers are blocked as well. |
| Success, a discarded duplicate, a body that never started | Not run at all. |
| The job's own `emit` | Stay enabled: the job's own `emit` does not disable them. |
| The job's rules cancel it at a checkpoint of its own: after its own `emit` of a state they refuse, or on a `stateAs` mismatch | Not run: a job its rules cancelled leaves the state as it is. |
| `Policy.restart` cancels the running job for a newer one with its key | `ifCancelled` runs, as for any cancellation, and its state is published before the newer job starts. |
| A handler throws | The error is reported; the outcome and the queue are untouched. |
| A rule throws while eligibility is checked | Handlers disabled and the error reported. Resource cleanup still runs. |
| A rule throws at a checkpoint of the body, `ctx.state` or `ctx.check()` | The body receives the error, and `ifFailed` corrects a `Failed` it leaves like any other. |

These extra checks apply to jobs with their own state handlers. A parent
without handlers stops checking its rules when its body ends; children then
remain subject to their own rules and any permission the parent already lost.

Keep these functions limited to computing state: the value they return is their
write. A state write made from inside one, through `externalSetState` or a
source that calls it synchronously, does not combine with that value. If the
job's rules accept the write, any other result of the handler lands on top of
it, computed from the state before it, and the fact is lost. The state it was
given, handed back, leaves the write in place. If they refuse it, the handler's
result is dropped. Resource release belongs in the cleanup API, on the page
[Resources and cleanup](resources.md).

A reload under `Policy.restart` shows the row about replacement. The second
call cancels the first load while it waits for the name, and a handler that
returns `Initial` publishes it between the two: listeners hear `Loading`,
`Initial`, `Loading`, `Loaded`. The reason of the cancellation tells the
replacement from the rest. A handler that hands back the state it was given
publishes nothing, and listeners hear `Loading`, `Loading`, `Loaded`:

```dart
Job<String> reload() => enqueue<ProfileState, String>(
  key: 'load',
  policy: Policy.restart,
  ifFailed: (state, error, stackTrace) => Failure(error),
  // The newer reload publishes its own state.
  ifCancelled: (state, cancelled) =>
      cancelled.reason is ReplacedCancelReason ? state : const Initial(),
  (ctx) async {
    ctx.emit(const Loading());
    final name = await ctx.abandonable(api.fetchName);
    ctx.emit(Loaded(name));
    return name;
  },
);
```

Cancelled any other way, by hand or by `close()`, the reload still returns
`Initial`.
