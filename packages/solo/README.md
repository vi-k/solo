# solo

Русская версия: [README.ru.md](https://github.com/vi-k/solo/blob/main/README.ru.md)

One job at a time: sequential jobs with exclusive state ownership,
declarative rules and cooperative cancellation. Pure Dart, no Flutter
dependency; [`flutter_solo`](https://pub.dev/packages/flutter_solo) adds the
`ValueListenable` face.

## Why

`solo` grew out of six complaints about bloc:

1. the event queue cannot be managed;
2. when every event is `sequential`, a single one of them cannot be made
   `restartable` without moving it to a separate queue;
3. events running in parallel write to one and the same state;
4. after cancellation the handler keeps running until it checks
   `emit.isDone` itself;
5. you cannot await your own event: the `stream` tells you the state
   changed, not who changed it;
6. from the outside you want to call a method, not build an event and
   `add` it.

[Where bloc falls short](#where-bloc-falls-short) shows all six in code, on
eight scenarios from different domains.

## Where bloc falls short

bloc fits an ordinary screen well: an event arrives, a handler answers with
a state. The traps below belong to controllers with a lifecycle — hardware,
devices, players, background sync — where several things happen to one state
and the order matters. Each item names a domain, shows the shape of the trap
in bloc, and then the same thing in `solo`. None of them is a bug: they
follow from bloc's design — a transformer per handler, `emit` valid only
inside its handler, `add` returning `void` — and where the point has been
argued in the tracker, the issue is linked.

The same package ships `Cubit`: no events, no transformers, methods that
emit. It answers items 5 and 6 outright — a cubit method takes typed
arguments and returns a value you can `await` — and felangel points at it in
[#1556](https://github.com/felangel/bloc/issues/1556) itself. For the rest
it offers nothing: there is no queue to manage (1), no transformers at all
(2, 3), no cancellation (4), and `emit` after `close` throws `Bad state:
Cannot emit new states after calling close` (item 7 below).

### 1. The queue cannot be managed

A BLE device screen. The user opens it — connect — taps to read the battery
and the signal, renames the device, and closes the window: disconnect. To
get a queue at all you funnel every command into a single `on<DeviceEvent>`
with `sequential()`; five separate `on<E>` would give five queues running
side by side, which is the next item. Now the queue is real, and
`Disconnect` is appended behind the two reads and the rename. Both reads
run before the disconnect, each emitting a state for a window that is
already closed — and nothing lets you drop them: the queue exists, but it
is opaque. There is nothing to look at it with, and nothing to remove a
pending event with.

```dart
class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  DeviceBloc(this._ble) : super(const DeviceState()) {
    // One handler for the whole type, so `sequential()` makes one queue.
    on<DeviceEvent>((e, emit) async {
      switch (e) {
        case Connect():
          await _ble.connect();
          emit(const DeviceState(online: true));
        case ReadBattery():
          emit(state.copyWith(battery: await _ble.battery()));
        case ReadSignal():
          emit(state.copyWith(signal: await _ble.signal()));
        case Rename(:final name):
          await _ble.rename(name);
        case Disconnect():
          // Both reads are queued ahead of this and run first, each
          // emitting a state into a window that is already closed.
          await _ble.disconnect();
          emit(const DeviceState());
      }
    }, transformer: sequential());
  }

  final Ble _ble;
}
```

In `solo` the queue is an object the controller owns, and the jobs in it
have keys.

```dart
enum DeviceKey { connect, readBattery, readSignal, rename, disconnect }

final class DeviceController extends Solo<DeviceState> {
  DeviceController(this._ble) : super(const Offline());

  final Ble _ble;

  // connect(), readBattery(), readSignal() and rename() are ordinary jobs.

  Job<void> disconnect() {
    // The reads were only for the screen the user has just closed; the
    // rename is what the user asked for, so it stays in the queue.
    queue.removeWhere(
      (job) =>
          job.key == DeviceKey.readBattery || job.key == DeviceKey.readSignal,
    );
    return run<Connected, void>(
      key: DeviceKey.disconnect,
      (ctx) async {
        await ctx.guard(_ble.disconnect);
        ctx.emit(const Offline());
      },
    );
  }
}
```

`removeWhere` finishes the two reads with `Cancelled(manual)` and completes
their `done`, so their callers learn what happened. The rename survives —
the user asked for it and never took it back — runs, and only then does the
disconnect, because the queue is sequential and the disconnect was added
last. `removeWhere` touches only the queue: a `connect` already in flight
finishes first. The queue is
an object you can look at and prune, so "throw away what only the closed
screen needed" is one expression, not a redesign.

### 2. One restartable among sequential

A media player. `play`, `pause` and `seek` all talk to one native player, so
they must run one at a time; but a `seek` fired while the user drags the
slider must restart, not queue — only the last position matters, while the
two toggles must run in the order they were tapped. In bloc a transformer is
an argument to `on<E>`, and `sequential()` orders only the events of that one
type — handlers of different types still overlap. To serialize all three you
funnel them into a single `on<PlayerCommand>`, and from there `seek` can no
longer be `restartable()`: one handler has one transformer. Give `seek` its
own `on<Seek>` with `restartable()` and it does restart, but that handler now
runs beside `play` and `pause` instead of in line with them — the same trap
from the other side. The escape hatch is to write an `EventTransformer` by
hand — it sees the events and could branch on their type — at the cost of
writing it.

```dart
class PlayerBloc extends Bloc<PlayerCommand, PlayerState> {
  PlayerBloc(this._player) : super(const PlayerState()) {
    // One handler for every command: a transformer applies per `on<E>`,
    // so three handlers with `sequential()` would still overlap. Seek is
    // sequential now too — a drag queues every step of the slider.
    on<PlayerCommand>((command, emit) async {
      switch (command) {
        case Play():
          await _player.play();
        case Pause():
          await _player.pause();
        case Seek(:final position):
          await _player.seek(position);
          emit(PlayerState(position: position));
      }
    }, transformer: sequential());
  }

  final Player _player;
}
```

In `solo` the queue is sequential by construction, and a policy belongs to a
job, not to the queue.

```dart
enum PlayerKey { play, pause, seek }

final class PlayerController extends Solo<PlayerState> {
  PlayerController(this._player) : super(const Idle());

  final Player _player;

  // play() and pause() run in the order they were tapped.
  Job<void> pause() => run<Ready, void>(
        key: PlayerKey.pause,
        (ctx) async {
          await ctx.guard(_player.pause);
          ctx.emit(ctx.state.copyWith(playing: false));
        },
      );

  Job<void> seek(Duration position) => run<Ready, void>(
        key: PlayerKey.seek,
        policy: Policy.restart,
        (ctx) async {
          await ctx.guard(() => _player.seek(position));
          ctx.emit(ctx.state.copyWith(position: position));
        },
      );
}
```

`Policy.restart` cancels the seek in flight and drops the queued ones, all by
the `seek` key; nothing else in the controller changes, because the policy
names a key rather than a lane. `play()` and `pause()` name no policy, so
they stay in the same one queue and run in the order they were tapped: the
restart reaches seeks and nothing else.

### 3. Handlers running in parallel write one state

Notes with sync. `UploadNote` and `RefreshList` change the same state
object, and since bloc 7.2 the default transformer is concurrent: with no
transformer given, both handlers run at once. The stale-snapshot version of
this bug has a one-line cure — read `state` after the await instead of
before it — and both handlers below do. What that does not cure is the
interleaving: `RefreshList` asks the server before the upload lands and
emits the answer after it, so a list that predates the note `UploadNote` has
just merged is written back over the newer one. No snapshot is involved; the two
handlers simply take turns on one object.

```dart
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  // No transformer: since bloc 7.2 the default is concurrent, so the two
  // handlers run at the same time.
  NotesBloc(this._api) : super(const NotesState()) {
    on<UploadNote>((e, emit) async {
      emit(state.copyWith(uploading: true));
      await _api.upload(e.note);
      // `state` read fresh after the await, as it should be.
      final merged = [...state.notes, e.note];
      emit(state.copyWith(notes: merged, uploading: false));
    });
    on<RefreshList>((e, emit) async {
      // Asked before the upload finished, answered after it: this list
      // predates the note merged above, so writing it into the state
      // drops that note. Fresh reads do not cure interleaving.
      final serverNotes = await _api.list();
      emit(state.copyWith(notes: serverNotes));
    });
  }

  final Api _api;
}
```

In `solo` there is one queue and one running root job, so there is nothing
to interleave with.

```dart
final class NotesController extends Solo<NotesState> {
  NotesController(this._api) : super(const NotesState());

  final Api _api;

  Job<void> upload(Note note) => run<NotesState, void>(
        key: 'upload',
        (ctx) async {
          ctx.emit(ctx.state.copyWith(uploading: true));
          await ctx.guard(() => _api.upload(note));
          final merged = [...ctx.state.notes, note];
          ctx.emit(ctx.state.copyWith(notes: merged, uploading: false));
        },
      );

  Job<void> refresh() => run<NotesState, void>(
        key: 'refresh',
        (ctx) async {
          // Runs before upload or after it, never across it.
          final serverNotes = await ctx.guard(_api.list);
          ctx.emit(ctx.state.copyWith(notes: serverNotes));
        },
      );
}
```

`ctx.state` is read at emit time, and while a root job runs no other root
job of this controller writes the state. The two ways in are its own
children, started by `ctx.run` inside the same body, and `externalSetState`
from outside — both deliberate, both visible. That is the ownership
guarantee, not a discipline the two bodies have to keep.

### 4. After cancellation the handler keeps running

A firmware update over BLE, written chunk by chunk. `restartable()` closes
the emitter, and that is all it does: the loop goes on writing chunks to the
device. The maintainer's answer in
[felangel/bloc#3349](https://github.com/felangel/bloc/issues/3349) is
exactly that:

> This is because Futures aren't truly cancelable. To get the behavior
> you're describing you can simply check if `emit.isDone` is true before
> performing any expensive computations:

The mirror image is a future started inside the handler and left unawaited:
it cannot emit later either. An `assert` catches that one in debug builds —
`emit was called after an event handler completed normally`
([#2961](https://github.com/felangel/bloc/issues/2961)) — because nothing
structured outlives the handler.

```dart
class FirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  FirmwareBloc(this._ble) : super(Idle()) {
    on<Flash>((e, emit) async {
      for (final chunk in e.chunks) {
        await _ble.write(chunk);
        // Without this line a restarted handler keeps writing chunks to
        // the device: `restartable()` closes the emitter, it does not
        // stop the body. Every loop that touches hardware needs it.
        if (emit.isDone) return;
        emit(Flashing(chunk.index));
      }
    }, transformer: restartable());
  }

  final Ble _ble;
}
```

In `solo` cancellation is cooperative too, but the waiting ends by itself.

```dart
final class FirmwareController extends Solo<FirmwareState> {
  FirmwareController(this._ble) : super(const Idle());

  final Ble _ble;

  Job<void> flash(List<Chunk> chunks) => run<NotBroken, void>(
        key: 'flash',
        policy: Policy.restart,
        canStart: (state) => state is Idle,
        (ctx) async {
          for (final chunk in chunks) {
            // guard returns the moment the job is cancelled, so the
            // next write never starts. A hardware failure that emits
            // Broken from outside ends the job on the same await.
            await ctx.guard(() => _ble.write(chunk));
            ctx.emit(Flashing(chunk.index));
          }
        },
      );
}
```

`ctx.guard` returns as soon as the cancellation arrives, so the next write
never starts; the next `ctx.state` or `ctx.emit` throws the job's
`Cancelled`; and work that would otherwise be fire-and-forget goes through
`ctx.run(child)`, a child job the parent waits for.

### 5. You cannot await your own event

Checkout. After the user taps Pay, the screen has to know that *this*
payment succeeded before it navigates. `add` returns `void`, and the state
stream says only that the state changed. It is a design decision, not an
omission — felangel in
[felangel/bloc#1556](https://github.com/felangel/bloc/issues/1556):

> … a single add can result in multiple state changes so you would never
> know when the event was actually "done" being processed.

```dart
class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  CheckoutBloc(this._api) : super(Cart()) {
    on<Pay>((e, emit) async {
      emit(Paying());
      try {
        emit(Paid(await _api.pay(e.order)));
      } on Object catch (error) {
        emit(PaymentFailed(error));
      }
    }, transformer: droppable());
  }

  final Api _api;
}
```

and the screen:

```dart
Future<void> onPayPressed(CheckoutBloc bloc, Order order) async {
  bloc.add(Pay(order)); // returns void
  // The stream says the state changed, not who changed it: a retry
  // from another screen produces the same Paid.
  final state = await bloc.stream.firstWhere((s) => s is! Paying);
  if (state is Paid) {
    navigateToReceipt(state.receipt);
  }
}
```

A `solo` method returns a handle to the job it created.

```dart
final class CheckoutController extends Solo<CheckoutState> {
  CheckoutController(this._api) : super(const Cart());

  final Api _api;

  Job<Receipt> pay(Order order) => run<CheckoutState, Receipt>(
        key: 'pay',
        policy: Policy.droppable,
        canStart: (state) => state is Cart,
        (ctx) async {
          ctx.emit(const Paying());
          final receipt = await ctx.guard(() => _api.pay(order));
          ctx.emit(Paid(receipt));
          return receipt;
        },
      );
}
```

and the screen:

```dart
Future<void> onPayPressed(CheckoutController checkout, Order order) async {
  switch (await checkout.pay(order).done) {
    case Done(:final value):
      navigateToReceipt(value);
    case Cancelled():
      showCancelled();
    case Failed(:final error):
      showError(error);
  }
}
```

`done` carries the outcome of this call and never throws; `value` carries
the value and throws instead. Neither has to guess whose state change it is
looking at. Later in the same thread felangel points at `Cubit`, whose
methods are plain `async` methods you can await — the answer to this item,
at the price of the event queue and the transformers of items 1 to 4.

### 6. A method, not an event

A map. `moveTo`, `setZoom`, `follow` — three actions on one widget. In bloc
each is a class, a registration and an `add`: the argument types live in the
event, the work lives in a handler elsewhere, and the call site says `add`,
not what it wants. `Cubit` answers this one as well — a cubit is methods —
which is another way of saying the ceremony belongs to events, not to the
package.

```dart
sealed class MapEvent {}

class MoveTo extends MapEvent {
  MoveTo(this.point);
  final Point<double> point;
}

class SetZoom extends MapEvent {
  SetZoom(this.value);
  final double value;
}

class Follow extends MapEvent {
  Follow(this.track);
  final Track track;
}
```

and the bloc:

```dart
class MapBloc extends Bloc<MapEvent, MapState> {
  MapBloc(this._map) : super(const MapState()) {
    on<MoveTo>((e, emit) => _map.moveTo(e.point), transformer: sequential());
    on<SetZoom>((e, emit) => _map.setZoom(e.value), transformer: sequential());
    on<Follow>((e, emit) => _map.follow(e.track), transformer: sequential());
  }

  final MapApi _map;
}

void onMapDrag(MapBloc bloc, Point<double> point) => bloc.add(MoveTo(point));
```

In `solo` they are three methods.

```dart
final class MapController extends Solo<MapState> {
  MapController(this._map) : super(const MapState());

  final MapApi _map;

  Job<void> moveTo(Point<double> point) =>
      run<MapState, void>((ctx) => ctx.guard(() => _map.moveTo(point)));

  Job<void> setZoom(double value) =>
      run<MapState, void>((ctx) => ctx.guard(() => _map.setZoom(value)));

  Job<void> follow(Track track) =>
      run<MapState, void>((ctx) => ctx.guard(() => _map.follow(track)));
}

void onMapDrag(MapController map, Point<double> point) => map.moveTo(point);
```

The signature carries the arguments and the result, the call site reads as a
call, and the returned `Job<void>` is there when the caller wants to await
it — calling without `await` raises no lint, because a handle is not a
`Future`.

### 7. Closing while work is in flight

A chat or feed screen. The user sends a message, goes back, and the reply
arrives into a controller that is already closed. What happens next depends
on the transformer. With `sequential()` — the one below — `close()` waits
for the running handler, and the late `emit` lands: the state changes after
`close`, and stream listeners still receive it. With the default
transformer, `concurrent()`, `droppable()` or `restartable()`, `close()`
returns at once, the emitter is cancelled and the late `emit` is dropped
without a word. Either way the body keeps running, and the `add` that
follows throws `Bad state: Cannot add new events after calling close`
([#52](https://github.com/felangel/bloc/issues/52),
[#120](https://github.com/felangel/bloc/issues/120); cancelable operations
are still an open proposal,
[#3069](https://github.com/felangel/bloc/issues/3069)). The usual workaround
is an `isClosed` check after every `await`.

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._api) : super(const ChatState()) {
    on<SendMessage>((e, emit) async {
      final reply = await _api.send(e.text);
      // The user went back while the request was in flight. Without
      // this line the reply still reaches the state — `sequential()`
      // makes `close()` wait for this body — and the `add` below throws
      // `Bad state: Cannot add new events after calling close`.
      if (isClosed) return;
      emit(state.withReply(reply));
      add(const MarkRead());
    }, transformer: sequential());
    on<MarkRead>((e, emit) => _api.markRead(), transformer: sequential());
  }

  final Api _api;
}
```

In `solo` closing is part of the same queue discipline.

```dart
final class ChatController extends Solo<ChatState> {
  ChatController(this._api) : super(const ChatState());

  final Api _api;

  Job<void> send(String text) => run<ChatState, void>(
        key: 'send',
        (ctx) async {
          final reply = await ctx.guard(() => _api.send(text));
          ctx.emit(ctx.state.withReply(reply));
          markRead();
        },
      );

  Job<void> markRead() =>
      run<ChatState, void>((ctx) => ctx.guard(_api.markRead));
}

Future<void> onScreenClosed(ChatController chat) async {
  // Cancels the running send and waits for its body to stop; queued
  // jobs finish with Cancelled(closed).
  await chat.close();
  chat.send('bye'); // a job already finished with Cancelled(closed)
}
```

`close()` marks the running job cancelled and waits for it to actually stop,
queued jobs finish with `Cancelled(closed)`, and `add` after `close` returns
a job already finished with the same outcome — so the call site needs no
`isClosed` check.

### 8. The state changes from outside

A camera, or a BLE sensor. The hardware reports a failure through a listener
while a calibration handler is halfway through. A bloc's own `emit` is
`@visibleForTesting` and documented as internal — "only for internal use and
should never be called directly outside of tests" — so the supported way in
from a listener is `add(HardwareFailed(error))`. That event gets its own
handler, which runs next to the calibration one, which goes on talking to
broken hardware. So every handler opens with `if (state is! Ready) return;`
and repeats it after each `await`.

```dart
class SensorBloc extends Bloc<SensorEvent, SensorState> {
  SensorBloc(this._hw) : super(Idle()) {
    // The supported way in is an event, and that event gets its own
    // handler, running next to whatever is already running.
    _hw.onError = (error) => add(HardwareFailed(error));
    on<HardwareFailed>((e, emit) => emit(Broken(e.error)));
    on<Calibrate>((e, emit) async {
      if (state is! Ready) return;
      await _hw.zero();
      // Broken may have arrived during the await; nothing cancelled
      // this handler, so the precondition is repeated by hand after
      // every step, forever.
      if (state is! Ready || emit.isDone) return;
      await _hw.sample();
      if (state is! Ready || emit.isDone) return;
      emit(Calibrated());
    }, transformer: sequential());
  }

  final Sensor _hw;
}
```

In `solo` the listener writes the state, and the rules stay in the
declaration.

```dart
final class SensorController extends Solo<SensorState> {
  SensorController(this._hw) : super(const Idle()) {
    // The listener writes the state itself. Every running job whose
    // working type or keepWhile no longer holds is cancelled at once.
    _hw.onError = (error) => externalSetState(Broken(error));
  }

  final Sensor _hw;

  // The precondition is the signature: W is Ready. Nothing to check in
  // the body, and nothing to repeat after each await.
  Job<void> calibrate() => run<Ready, void>(
        key: 'calibrate',
        (ctx) async {
          await ctx.guard(_hw.zero);
          await ctx.guard(_hw.sample);
          ctx.emit(const Calibrated());
        },
      );
}
```

`externalSetState` re-evaluates every running job against the new state and
cancels the ones whose working type or `keepWhile` no longer holds. The
precondition lives in `run<Ready, void>`, where the engine checks it before
the start, on every state change, and on every read.

## Install

```sh
dart pub add solo
```

For Flutter, take `flutter_solo` instead — it re-exports all of `solo`:

```sh
flutter pub add flutter_solo
```

## Quick start

A camera controller. The state is a sealed hierarchy; `NotDisposed` is a
union interface that jobs can declare as their working type:

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

The controller is a plain class with plain methods. Each method builds a
job and hands it to the queue; the handle it returns is not a `Future`, so
calling the method without `await` is legal and raises no lint:

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
          await ctx.guard(hw.open);
          ctx.emit(const Ready());
        },
      );

  Job<void> setZoom(double zoom) => run<Ready, void>(
        key: CameraKey.setZoom,
        policy: Policy.replace,
        describe: () => 'zoom: $zoom',
        canStart: (state) => !state.paused,
        (ctx) async {
          await ctx.guard(() => hw.setZoom(zoom));
          ctx.emit(ctx.state.copyWith(zoom: zoom));
        },
      );

  Job<Photo> takePhoto() => run<Ready, Photo>(
        key: CameraKey.takePhoto,
        policy: Policy.droppable,
        canStart: (state) => !state.paused,
        (ctx) async {
          final photo = await ctx.guard(hw.capture);
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
          await ctx.run(_closeCameraJob()).done;
        }
        ctx.emit(const Disposed());
      },
    );
  }
}
```

From the outside:

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

Jobs run one after another, in queue order, and never overlap. A `setZoom`
added while an earlier `setZoom` still waits in the queue throws that queued
one away and takes its place; a `setZoom` that already started is left to
finish — that is `Policy.replace`. A `takePhoto` added while a shot is in
flight returns the shot already running instead of queueing a second one —
that is `Policy.droppable`. `dispose` clears the queue, cancels whatever
runs, and then runs itself as a job that nothing can cancel.

## Concepts

**State.** One immutable object of type `S`, usually a sealed hierarchy
with union interfaces (`NotDisposed`, `Initialized`) so that jobs can
declare a working type wider than a single class. `solo.state` is readable
by anyone at any time; only jobs write.

**Controller.** The owner of the state and of the queue. The hierarchy is
linear: `SoloBase<S>` is the engine and `state`; `Solo<S>` adds a broadcast
`stream`; `SoloListenable<S>` in `flutter_solo` adds `ValueListenable`.
They differ only in how a change is delivered.

**Job.** A unit of work: an `async` body `Future<T> Function(JobContext)`,
an optional `key`, rules, and a handle `Job<T>`. `job(...)` builds one
without queueing it, `add(job, policy: ...)` queues it, `run(...)` does
both in one call. At most one root job runs at a time, and while it runs no
other job of this controller touches the state.

**Working type `W`.** The subtype of `S` a job agrees to work with. The
body sees `ctx.state` already narrowed to `W`. The type is checked before
the job starts, on every state change while it runs, and on every read
through the context.

**Rules.** `canStart` is checked once, when the job is taken from the
queue; failing it drops the job with `Cancelled(rules, 'canStart')` and
`started: false`. `keepWhile` is checked continuously — and also before the
start, together with `canStart`: a job whose invariant is already broken
never starts, instead of starting and dying on its first read.

**Cancellation.** Cooperative: Dart cannot interrupt somebody else's
`await`. A cancelled job learns about it the next time it touches the
context — every `JobContext` member except `log` and `job` throws the job's
`Cancelled` once the job is marked. After a bare `await`, call
`ctx.check()`. To wait for something and give up on cancellation at once,
wrap it in `ctx.guard(() => ...)`: the guard returns as soon as either the
action or the cancellation arrives.

**Children.** `ctx.run(child)` starts a job right now, bypassing the queue,
as a child of the current one. The parent finishes only after all of its
children. `ctx.run(child).done` gives the outcome and never throws;
`ctx.run(child).value` gives the value and throws the child's `Cancelled`
or error into the parent's body.

**External state.** `externalSetState(next)` sets the state from outside
any job: a hardware listener, a forced transition. Every running job except
the one that emitted is re-evaluated against the new state immediately; the
emitting job is checked lazily, on its next read.

**Outcomes.** `Outcome<T>` is sealed, so a `switch` over its three cases is
exhaustive: `Done` carries the returned `value`, `Failed` carries `error`
and `stackTrace`, `Cancelled` carries a `reason`, a `started` flag, an
optional `description` and the stack trace of the cancellation itself. The
reason is a `CancelReason`: `manual`, `rules`, `closed`, `parent`,
`handler`. `job.done` completes with the outcome and never throws;
`job.value` completes with the value or throws; `job.whenCancelled`
completes the moment the job is marked cancelled, before the body finishes;
`job.cancel()` cancels and waits for the job to actually finish.

**Queue and policies.** `queue` is a first-class object visible to
subclasses: `jobs`, `remove`, `removeWhere`, `clear`, `lastWhere`. The three
removing methods skip `cancellable: false` jobs unless given `force: true`,
and none of them touches the running job. Policies are sugar over the common
case of one key: `sequential` appends; `droppable` returns the queued or
running job with the same key and drops the new one; `replace` removes
queued jobs with the same key; `restart` additionally cancels the running
one without waiting for it. `add(job, first: true)` puts a job at the head.

**Stream.** `Solo.stream` is a broadcast stream of every state change, in
order, delivered on the next microtask — the stream is asynchronous. The
source of truth is `state`: by the time an event arrives, `state` may
already be newer. Equality is not checked; each change is one event. In
`flutter_solo`, `SoloListenable` listeners are called synchronously,
in subscription order, while the stream event is still on its way.

## Rules that are not visible in signatures

`cancellable: false` protects a job from actors: a manual `cancel`, a
`clear` without `force`, the cancellation of its parent, `close`. It does
not protect it from reality: if the state stopped matching `W` or
`keepWhile`, the job is cancelled anyway, because there is nothing left for
it to read. A non-cancellable job that must survive any state needs the
base type `S` and no `keepWhile`.

`emit` is trusted, reads are checked. The emitted state is not verified
against the rules of the job that emitted it — otherwise a `close` job
declared as `run<NotClosed, void>` would cancel itself the moment it
emitted `Closed()`.

`ctx.run(child)` returns a handle, not a value. `await ctx.run(child).value`
throws into the parent; `switch (await ctx.run(child).done)` does not. A
forgotten `await` breaks nothing: the parent waits for its children in any
case.

A job handed to `ctx.run` becomes a child even if it is dropped before it
starts. It is registered as a child first, and only then checked against
the rules, so a parent always accounts for every job it tried to run.

`add` on a closed controller does not throw. It returns a job that is
already finished with `Cancelled(closed)`, so call sites need no
`isClosed` check.

Any policy other than `sequential` with `key == null` throws
`ArgumentError`, not an `assert`: in release mode `null == null` is true
and `replace` would wipe every keyless job in the queue.

`ctx.emit` and `ctx.run` after the job has finished throw `StateError`. A
context that leaked out of its job — captured by a closure nobody awaited —
must not write the state outside the critical section. Reads (`state`,
`stateAs`, `check`, `guard`, `log`) after the job finished are allowed.

`close()` awaited from inside the current job's body never completes: it
waits for that very body. The same holds for `cancelAll()`. Cancel from the
inside by returning or by throwing `Cancelled('why')`.

From inside a job body the whole surface of the `Solo` subclass is visible,
so there is no `ctx.solo`.

## Recipes

**Timeout.** The engine knows nothing about timeouts; `guard` plus
`Future.timeout` is the whole recipe. On a timeout the body throws, and the
job ends up `Failed`:

```dart
Job<void> connect() => run<Idle, void>(
      key: 'connect',
      (ctx) async {
        await ctx.guard(
          () => hw.open().timeout(const Duration(seconds: 5)),
        );
        ctx.emit(const Connected());
      },
    );
```

**Debounce.** Also outside the engine: hold a `Timer` in the controller and
start the job when it fires. Combine it with `Policy.restart`, so that a job
still running for the previous input is cancelled rather than awaited:

```dart
import 'dart:async';

final class Search extends Solo<SearchState> {
  Timer? _debounce;

  Search() : super(const SearchState.idle());

  void query(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      run<SearchState, void>(
        key: 'query',
        policy: Policy.restart,
        describe: () => text,
        (ctx) async {
          final results = await ctx.guard(() => api.search(text));
          ctx.emit(SearchState.results(results));
        },
      );
    });
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
```

**Hooks.** A controller can override `onStart`, `onFinish`, `onError`,
`onLog` and `onChange` to react to its own jobs:

```dart
final class CameraController extends Solo<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

  // ...the jobs above...

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    reportCrash(error, stackTrace);
  }
}
```

**Observer.** `SoloObserver` is the cross-cutting version of the same five
hooks plus `onCreate` and `onClose`: analytics, error reporting, one log for
every controller in the process. The engine calls the observer before the
controller's own hook, and independently of it — a subclass that forgets
`super` does not switch the observer off:

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

To trace the engine itself rather than the jobs, set
`SoloBase.debug = print`.

## Flutter

`flutter_solo` adds `SoloListenable<S> extends Solo<S> implements
ValueListenable<S>`, and re-exports all of `solo`. The only change to the
controller is its base class — the jobs above stay exactly as they are, and
the controller then goes straight into `ValueListenableBuilder`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

final class CameraController extends SoloListenable<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

  // ...the jobs above...
}

class CameraView extends StatelessWidget {
  const CameraView({super.key, required this.camera});

  final CameraController camera;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<CameraState>(
        valueListenable: camera,
        builder: (context, state, _) => switch (state) {
          Ready(:final zoom) => Text('zoom $zoom'),
          _ => const CircularProgressIndicator(),
        },
      );
}
```

`value` and `state` are the same object. There is no setter on purpose: a
`ValueNotifier` face would be a hole in the ownership guarantee.

## Example

[`example/`](example) is a runnable package: a fake camera whose hardware
answers late and may break on its own, the controller above in full, four
tests over an ordered journal, and `bin/main.dart` that prints the same
journal in real time.

```sh
cd example
dart run bin/main.dart
dart test
```
