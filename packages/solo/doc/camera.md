# Camera example

A camera is a controller over hardware: every operation takes time, the device
can fail on its own, and it has to be closed on purpose. This page builds that
controller one decision at a time — state rules, queue policies, the cleanup of
the device — and ends on the code of the runnable [`example/`](../example)
package: the last fragment of each method below is its code in
`example/lib/src/camera_controller.dart`, comments aside.

The states:

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
  final Point<double>? focusPoint;
  final bool paused;

  const Ready({this.zoom = 1, this.focusPoint, this.paused = false});

  Ready copyWith({double? zoom, Point<double>? focusPoint, bool? paused}) =>
      Ready(
        zoom: zoom ?? this.zoom,
        focusPoint: focusPoint ?? this.focusPoint,
        paused: paused ?? this.paused,
      );
}

final class Broken extends NotDisposed {
  final Object error;

  const Broken(this.error);
}

final class Disposed extends CameraState {
  const Disposed();
}
```

`NotDisposed` groups every state in which the hardware can still be talked to,
and `Disposed` is the one where it cannot. `Broken` is where a failure of the
hardware lands; it is not called `Failed`, which is the name of an outcome. In
the example every state also prints itself, and that text is what the journals
below show.

A `null` passed to `copyWith` keeps the old value, so `copyWith` cannot clear
`focusPoint`, where `null` means automatic focus. The example's
`resetFocusPoint` publishes a fresh `Ready` that keeps the current zoom.

The hardware is `FakeCameraHardware` from the example. Every operation takes
ten milliseconds and a capture thirty; `failures` makes a named operation fail
after its delay, `onError` reports a failure from outside any job, and `log`
records where each operation begins and ends. The journals below are what the
example's observer prints for this code: a job `started`, `finished` with its
outcome or `dropped` before it started, an `error` it reported, a `log` line,
and every change of `state:`. A child job's lines begin with `>`.

Sections open with the version the API's vocabulary leads to — the working type
named after the state a job starts from, the default policy, a disposal queued
like any other job — show what that code does, and then give the version the
example uses. The section on commands that arrive during a shot has nothing to
trip over and opens with the answer.

## Opening the camera

`init` publishes `Preparing`, opens the hardware and publishes `Ready`. It may
start only from `Initial`.

### The first attempt

```dart
Job<void> init() => run<Initial, void>(
      key: CameraKey.init,
      policy: Policy.droppable,
      (ctx) async {
        ctx.emit(const Preparing());
        await ctx.join(hw.open);
        ctx.emit(const Ready());
      },
    );
```

```text
[init] started
state: Preparing()
[init] finished Cancelled(rules: is not Initial)
```

The working type is the state the job's rules require for as long as it runs,
and `run<Initial, void>` requires `Initial`. The body's first `emit` leaves it,
and the job ends `Cancelled` before `hw.open` is ever called: the hardware log
stays empty. The controller is left in `Preparing`, and the next `init()` is
dropped at its start for the same reason — the camera can no longer be opened
at all.

### A working type wide enough

```dart
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
```

`NotDisposed` is what the body needs for all its length: `Preparing` and
`Ready` both belong to it, and the emits stay inside the rules. Where the job
may start is a separate question, and `canStart` answers it. Without it, a
second `init()` on a camera that is already open runs again and opens the
hardware a second time. With it, the call ends before it starts:

```text
[init] dropped Cancelled(rules: canStart)
```

A second `init()` made while the first one still runs never gets that far:
`Policy.droppable` hands it the job already in flight, and the hardware is
opened once.

## An opening that fails

The hardware can refuse to open while another app holds the camera, and a job
can be cancelled while it opens. Either way the controller has to end in a
state something can start from, so that the camera can be opened later.

### The first attempt

```dart
(ctx) async {
  ctx.emit(const Preparing());
  try {
    await ctx.join(hw.open);
  } on Object catch (error) {
    ctx.emit(Broken(error));
    rethrow;
  }
  ctx.emit(const Ready());
},
```

A failure lands where it should: the catch publishes `Broken`, and the job ends
`Failed`. A cancellation passes through the same catch, and there the `emit`
does not publish. On a job that is already cancelled it is a checkpoint, and it
throws `Cancelled` instead:

```text
[init] started
state: Preparing()
[init] finished Cancelled(manual)
```

`join` has waited for the opening, so the hardware is open, and the state says
it is still opening. Nothing starts from `Preparing`: `init` wants `Initial`,
and `reopen`, the example's way back, wants `Ready` or `Broken`. It is the trap
of
[State after failure or cancellation](state.md#state-after-failure-or-cancellation),
with a device behind the spinner.

### The handlers of run

```dart
Job<void> init() => run<NotDisposed, void>(
      key: CameraKey.init,
      policy: Policy.droppable,
      canStart: (state) => state is Initial,
      onError: (state, error, stackTrace) => Broken(error),
      onCancel: (state, cancelled) => Broken(cancelled),
      (ctx) async {
        ctx.emit(const Preparing());
        await ctx.join(hw.open);
        ctx.emit(const Ready());
      },
    );
```

The handlers compute the state after the body is over, so a cancellation
reaches its own handler instead of a refused `emit`. A failure and a
cancellation both land in `Broken`, and `reopen` starts from there:

```text
[init] started
state: Preparing()
[init] error Bad state: camera in use
state: Broken(Bad state: camera in use)
[init] finished Failed(Bad state: camera in use)
```

```text
[init] started
state: Preparing()
state: Broken(Cancelled(manual))
[init] finished Cancelled(manual)
```

A job dropped before its start reaches neither handler, so the second `init()`
of the section above still ends in its one `dropped` line. `reopen` lands the
same way.

## Only the last zoom

A pinch asks for a zoom on every frame, and only the last request matters.

### The first attempt

```dart
Job<void> setZoom(double zoom) => run<Ready, void>(
      key: CameraKey.setZoom,
      describe: () => 'zoom: $zoom',
      (ctx) async {
        await ctx.join(() => hw.setZoom(zoom));
        ctx.emit(ctx.state.copyWith(zoom: zoom));
      },
    );
```

Three calls in one turn, `setZoom(2)`, `setZoom(3)` and `setZoom(4)`, end on
`Ready(zoom: 4.0, focusPoint: null, paused: false)`, and so does the version
below: by the state the two cannot be told apart. The hardware can. Every
request waits its turn and reaches the lens:

```text
zoom 2.0: begin
zoom 2.0: end
zoom 3.0: begin
zoom 3.0: end
zoom 4.0: begin
zoom 4.0: end
```

### Policy.replace

```dart
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
```

`replace` drops the queued job with the same key and takes its place, so the
same three calls reach the hardware once:

```text
[setZoom: zoom: 2.0] dropped Cancelled(manual)
[setZoom: zoom: 3.0] dropped Cancelled(manual)
[setZoom: zoom: 4.0] started
state: Ready(zoom: 4.0, focusPoint: null, paused: false)
[setZoom: zoom: 4.0] finished Done(null)
```

The job that is already running is left to finish. When `setZoom(3)` and
`setZoom(4)` arrive while the zoom to 2 is in flight, the lens still goes to 2,
the request for 3 is dropped, and then it goes to 4. `canStart` keeps a paused
camera from taking the command at all.

## Commands that arrive during a shot

```dart
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
```

A capture takes three times as long as the other operations, and the commands
asked for meanwhile wait in the queue. This example counts them as part of the
shot: once the photo is taken, `queue.clear()` drops them. A zoom requested
five milliseconds into the capture:

```text
[takePhoto] started
[setZoom: zoom: 3.0] dropped Cancelled(manual)
[takePhoto] log captured Photo#1
[takePhoto] finished Done(Photo#1)
```

Without the clear that zoom runs once the shot is over. `queue.clear()` leaves
the running job alone, and the running job here is the shot itself. It also
leaves the jobs that are not cancellable, and this controller queues only one
kind of those: a disposal.

## Disposing of the camera

`dispose()` closes the hardware and publishes `Disposed`, whatever the camera
was doing when it was called.

### The first attempt

```dart
Job<void> dispose() => run<CameraState, void>(
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

Job<void> _closeCameraJob() => job<NotDisposed, void>(
      key: CameraKey.closeCamera,
      cancellable: false,
      (ctx) async => hw.close(),
    );
```

Called with a zoom in flight and a shot waiting behind it, this disposal takes
its place at the end of the queue:

```text
[setZoom: zoom: 2.0] started
state: Ready(zoom: 2.0, focusPoint: null, paused: false)
[setZoom: zoom: 2.0] finished Done(null)
[takePhoto] started
[takePhoto] log captured Photo#1
[takePhoto] finished Done(Photo#1)
[dispose] started
> [closeCamera] started
> [closeCamera] finished Done(null)
state: Disposed()
[dispose] finished Done(null)
```

Everything in front of it still runs, and the camera takes a photo after it was
told to shut down. The job itself is right: it may not be cancelled once
started, and its child that closes the hardware may not be either, so the
device is never left half closed.

### Clearing the way

```dart
Job<void> dispose() {
  queue.clear();
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
```

```text
[setZoom: zoom: 2.0] started
[takePhoto] dropped Cancelled(manual)
[setZoom: zoom: 2.0] finished Cancelled(manual)
[dispose] started
> [closeCamera] started
> [closeCamera] finished Done(null)
state: Disposed()
[dispose] finished Done(null)
```

`queue.clear()` drops what has not started, and the shot never reaches the
hardware. `current?.cancel()` asks the running zoom to stop, and the lens moves
to 2 all the same: the zoom waits with `join`, which lets the job leave only
once the operation it started is over — the table at the top of
[Cancellation](cancellation.md) has each waiting method. What the cancellation
saves is the rest of the body: the zoom publishes no state for a camera about
to close, and the disposal starts as soon as the hardware is free.

The clear is not forced. A disposal that is still in the queue survives it,
because it is not cancellable, and `Policy.droppable` hands it to the second
call: two `dispose()` calls in a row get the same job, and both callers see
`Done`. `queue.clear(force: true)` would drop that job instead, and its caller
would get `Cancelled(manual)` for a camera that was disposed after all.

For the same reason `Disposed` is checked in the body rather than by
`canStart`. A call made after the disposal is over starts a job of its own, and
the check ends it `Done` at once. `canStart: (state) => state is! Disposed`
would drop that job before it starts, and its caller would get
`Cancelled(rules: canStart)`.

## Closing the controller

After the disposal the controller itself is released with `close()`.

### The first attempt

```dart
camera.dispose();
await camera.close();
```

```text
[dispose] dropped Cancelled(closed)
closed
```

`cancellable: false` refuses `cancel()`. It does not keep a job in a controller
that closes before the job has started: `dispose()` queued the job, `close()`
came in the same turn and ended every queued job with `Cancelled(closed)`, as
[Cancelling and closing a controller](cancellation.md#cancelling-and-closing-a-controller)
describes. The hardware log has no `close` in it. The camera stays open, the
state still says `Ready`, and the controller that could close the camera is
closed itself.

### Awaiting the disposal

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

The disposal is over before `close()` is called, and `close()` finds nothing to
cancel. A disposal that has already started is safe from `close()` as well:
`close()` waits for the running job, and a job that is not cancellable runs to
its end.

`Failed` is the case that needs handling: a close that fails is not a disposal.
`ctx.run` throws what the child threw, the body never reaches
`emit(Disposed())`, and the state stays where it was. `Cancelled` comes back
from a controller that was closed before `dispose()` was called.

`setZoom(2)` is not awaited: a `Job` is not a `Future`, and `unawaited_futures`
has nothing to say about it. The shot waits behind the zoom in the queue, and
`value` hands over its photo — or throws, if the shot fails or is cancelled.

## A failure after the disposal

The hardware reports a failure on its own, and the controller turns it into
`Broken`:

```dart
CameraController(this.hw) : super(const Initial()) {
  hw.onError = (error) => externalSetState(Broken(error));
}
```

### The first attempt

The disposal of the section above, with the listener left in place. The
hardware reports a failure after `Disposed` and before `close()`:

```text
[dispose] started
> [closeCamera] started
> [closeCamera] finished Done(null)
state: Disposed()
[dispose] finished Done(null)
state: Broken(Bad state: cable pulled)
```

The disposal decided the final state, and the next report of the hardware
replaced it. After `close()` the same report does not change the state: the
state of a closed controller is final, so `externalSetState` throws a
`StateError`, and it throws into the hardware's own callback.

### Detaching the source first

```dart
Job<void> dispose() {
  hw.onError = null;
  queue.clear();
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
```

The listener goes before anything else, so the disposal decides the final state
alone, and a failure reported after it — or after `close()` — has nobody to
tell. The camera stays `Disposed`.

## Running the example

```sh
cd example
dart pub get
dart run bin/main.dart
dart test
```

`bin/main.dart` opens the camera, zooms, sets a focus point, starts a shot and
disposes of the camera in the middle of it, printing the journal as it goes.
The example also has `reopen`, `pause`, `resume` and the focus operations, and
its tests exercise each of them.
