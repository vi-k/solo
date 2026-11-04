# solo under bloc

A bloc can hand its work to a `solo` controller and keep the events and the
state a screen reads; its registrations go back to the default of bloc. Each
section below takes one requirement of an app on bloc 9.2.1 with
`bloc_concurrency`, shows the answer of bloc alone and then the same bloc with
a controller under it, and says what the controller takes off the code and what
stays with bloc. The controllers are the ones of the Solo sections of
[solo and bloc, side by side](vs-bloc.md), where each of them stands without
bloc. The code runs in pure Dart, and the states and traces under it are what
that code prints.

The controller costs every bloc a few lines of its own and brings rules, which
[The bridges](#the-bridges) names. The sections take three requirements where
bloc alone needs a workaround. During a drag a new seek stops the one in
flight, and bloc alone keeps the newest seek and the token of the one in flight
in fields and stops it from `onEvent`. A disconnect drops the battery reads
still waiting, and bloc alone stamps every event with the screen it was added
for. A firmware upload that replaces another must wait for the write in flight,
and bloc alone takes a lock that every handler writing to the device shares. An
app with one such problem is best left on bloc alone. The scenarios where bloc
keeps its own answer are listed in
[Where bloc keeps its answer](#where-bloc-keeps-its-answer).

## The bridges

A controller under a bloc needs two bridges: its jobs into the handlers of the
bloc, and its states into the state of the bloc. The states come through the
`stream` of `SoloStream`. Here a counter takes a step every 10 ms:

```dart
final class Counter extends Solo<int> with SoloStream<int> {
  Counter() : super(0);

  Job<void> countTo(int target) => enqueue<int, void>((ctx) async {
    while (ctx.state < target) {
      await ctx.pause(const Duration(milliseconds: 10));
      ctx.emit(ctx.state + 1);
    }
  });

  Job<void> reset() => enqueue<int, void>((ctx) async => ctx.emit(0));
}
```

Two functions of the app carry the bridges, and every bloc of this page with a
controller under it uses them. `follow` publishes the states of a controller in
a bloc, starting from the state the controller has now, and `settle` waits for
a job and throws its failure again:

```dart
/// Publishes the states of [controller] through [emit], starting from the
/// state the controller has now; [state] is the state of the bloc.
Future<void> follow<S extends Object>(
  Emitter<S> emit,
  S state,
  SoloStream<S> controller,
) {
  final following = emit.forEach(controller.stream, onData: (next) => next);
  if (controller.currentState != state) emit(controller.currentState);
  return following;
}

/// Waits for [job] and throws its failure again.
Future<void> settle(Job<Object?> job) async {
  if (await job.done case Failed(:final error, :final stackTrace)) {
    Error.throwWithStackTrace(error, stackTrace);
  }
}
```

The bloc publishes the states from the handler of an event of its own, which
the constructor adds and which runs as long as the bloc lives:

```dart
sealed class CounterEvent {
  const CounterEvent();
}

final class CountTo extends CounterEvent {
  const CountTo(this.target);
  final int target;
}

final class Reset extends CounterEvent {
  const Reset();
}

final class _Started extends CounterEvent {
  const _Started();
}

class CounterBloc extends Bloc<CounterEvent, int> {
  CounterBloc(this._counter) : super(_counter.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _counter));
    on<CountTo>((e, emit) => settle(_counter.countTo(e.target)));
    on<Reset>((e, emit) => settle(_counter.reset()));
    add(const _Started());
  }

  final Counter _counter;

  @override
  Future<void> close() async {
    await _counter.close();
    return super.close();
  }
}
```

`Counter` takes `SoloStream` where it is declared. The sections below take the
controllers of the side-by-side page, declared without the mixin, and add it in
a class of their own, such as
`final class StreamedDevice = DeviceController with SoloStream<DeviceState>;`.
Those controllers are final classes, so such a class compiles only in the
library of the controller. `_Started` extends a sealed family of events, as
`CounterEvent` is, and is declared in the library of the family.

The handlers of `CountTo` and `Reset` wait for the jobs of the controller
through `settle`. `job.done` never throws: it returns the outcome and marks the
job observed, so a handler that only awaits it drops a failure of the job, and
neither `onError` of the bloc nor the zone hears of it. `settle` throws a
`Failed` outcome again, and the error goes the way of any error of a handler,
to `onError` of the bloc and on to the zone. A job the closing controller
cancelled ends `Cancelled`, and `settle` lets the handler end quietly, where
`job.value` would throw `Cancelled`.

The bloc counts to 2, is reset twice and counts to 3, and the screen closes it
35 ms in, after the first step of the last count:

```text
controller [1, 2, 0, 0, 1]
bloc       [1, 2, 0, 1]
close took 0ms, bloc.state 1, counter.isClosed true, bloc.isClosed true
```

The bloc publishes every state of the controller but the second `0`: a bloc
that has emitted once drops a state equal to the one it has, and `SoloStream`
publishes it. `follow` subscribes first and then compares the states, so the
bloc starts from the state the controller has at the subscription, even when
the controller changed it after the constructor of the bloc read
`currentState`. `close()` of the bloc closes the controller, and the controller
cancels the count at `ctx.pause`. The closed controller closes its stream, and
`emit.forEach` ends with it.

`_counter.stream.listen(emit)` in the constructor would be shorter, but `emit`
of a bloc is for bloc itself and tests, and the analyzer reports such a call as
`invalid_use_of_visible_for_testing_member`.

Every bloc pays for the bridges: a class that adds `SoloStream` to its
controller, unless the controller is declared with it, the event `_Started`
with its registration and its `add`, and an override of `close()`; `follow` and
`settle` are written once for the app. The rules above come with them, and
three more.

The state belongs to the controller, and the bloc publishes a copy of it. A
handler that calls `emit` itself parts the bloc from the controller, until the
next state of the controller replaces what it published. A `BlocObserver` sees
every transition on `_Started`, whose handler publishes them all, and not on
the event that asked for the work. `seed` of `blocTest` emits into the bloc,
and `follow` replaces it with the state of the controller: a test starts from
the state its controller has.

`close()` of the bloc has to close the controller. A bloc closed without it
leaves the controller open, and the jobs of the controller go on: the count
goes on after the bloc is closed.

And every event keeps the registration bloc gives it by default. A transformer
such as `sequential()` holds an event until the handler before it has ended, so
the job of the event reaches the controller only then, and the queue of the
controller, which replaces and removes jobs, holds one at a time. The first
attempt of [Removing selected pending work](#removing-selected-pending-work)
keeps `sequential()` and finds nothing to remove.

## Restarting one operation within a shared queue

A player runs `play`, `pause` and `seek` one at a time. During a drag of the
slider, the seeks still waiting are obsolete, and a seek in flight should stop
before the next one starts; `play` and `pause` keep their order. `play` and
`pause` take 30 ms, a seek three steps of 10 ms and watches its token between
them. The events and the states are the ones of
[Restarting one operation within a shared queue](vs-bloc.md#restarting-one-operation-within-a-shared-queue).

### With bloc alone

One registration with `sequential()` keeps the order, and `onEvent` writes down
the newest seek and stops the one in flight:

```dart
class PlayerBloc extends Bloc<PlayerCommand, PlayerState> {
  final Player _player;
  Duration? _newestSeek;
  CancelToken? _seeking;

  PlayerBloc(this._player) : super(const PlayerState()) {
    on<PlayerCommand>((command, emit) async {
      switch (command) {
        case Play():
          await _player.play();
        case Pause():
          await _player.pause();
        case Seek(:final position):
          if (position != _newestSeek) return;
          final token = CancelToken();
          _seeking = token;
          await _player.seek(position, cancelToken: token);
          _seeking = null;
          if (token.cancelled) return;
          emit(PlayerState(position: position));
      }
    }, transformer: sequential());
  }

  @override
  void onEvent(PlayerCommand event) {
    super.onEvent(event);
    if (event is Seek) {
      _newestSeek = event.position;
      _seeking?.cancel();
    }
  }
}
```

In the traces a drag goes through 1, 2 and 3 between a play and a pause,
another comes back to 1, and a seek to 3 comes 15 ms after a seek to 1:

```text
with bloc alone, seeks 1, 2, 3: [play, seek 3, pause]
with bloc alone, seeks 1, 2, 1: [play, seek 1, seek 1, pause]
with bloc alone, seek 3 15 ms after seek 1: [seek 1 start, seek 1 stopped, seek 3 start, seek 3 end]
```

A seek that is not the newest returns. The newest is a position compared by
value, so a drag that comes back to 1 lets its first seek to 1 through, and the
player seeks to 1 twice; a bloc that keeps the newest `Seek` event itself and
compares it with `identical` seeks to 1 once. Either way the bloc keeps two
fields, checks the token after the await and stops the seek in flight from
`onEvent`.

### With a controller under the bloc

The calls go to the controller of that section, which has its `stream` already:

```dart
enum PlayerKey { play, pause, seek }

final class PlayerController extends Solo<PlayerState> with SoloStream {
  final Player _player;

  PlayerController(this._player) : super(Ready());

  Job<void> play() => enqueue<Ready, void>(key: PlayerKey.play, (ctx) async {
    await ctx.join(_player.play);
    ctx.emit(ctx.state.copyWith(playing: true));
  });

  Job<void> pause() => enqueue<Ready, void>(key: PlayerKey.pause, (ctx) async {
    await ctx.join(_player.pause);
    ctx.emit(ctx.state.copyWith(playing: false));
  });

  Job<void> seek(Duration position) => enqueue<Ready, void>(
    key: PlayerKey.seek,
    policy: Policy.restart,
    (ctx) async {
      final token = CancelToken();
      ctx.onCancel(token.cancel);
      await ctx.join(() => _player.seek(position, cancelToken: token));
      ctx.emit(ctx.state.copyWith(position: position));
    },
  );
}
```

Each command gets the registration bloc gives it by default:

```dart
final class _Started extends PlayerCommand {}

class PlayerBloc extends Bloc<PlayerCommand, PlayerState> {
  PlayerBloc(this._player) : super(_player.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _player));
    on<Play>((e, emit) => settle(_player.play()));
    on<Pause>((e, emit) => settle(_player.pause()));
    on<Seek>((e, emit) => settle(_player.seek(e.position)));
    add(_Started());
  }

  final PlayerController _player;

  @override
  Future<void> close() async {
    await _player.close();
    return super.close();
  }
}
```

```text
with a controller, seeks 1, 2, 3: [play, seek 3, pause]
with a controller, seeks 1, 2, 1: [play, seek 1, pause]
with a controller, seek 3 15 ms after seek 1: [seek 1 start, seek 1 stopped, seek 3 start, seek 3 end]
```

`Policy.restart` replaces the seek still waiting and cancels the one in flight,
and `ctx.onCancel` hands the cancellation to the token. What is replaced is a
job, not a position: a drag that comes back to 1 seeks to 1 once.

What stays with bloc: a registration for each command besides the bridges, and
nothing else. No `_newestSeek`, no field for the token, no check after the
await and no `onEvent`. Without the bridges the same controller is the Solo
answer of
[Restarting one operation within a shared queue](vs-bloc.md#restarting-one-operation-within-a-shared-queue).

## Removing selected pending work

A screen of a device queues a connect, a battery read, a rename and a
disconnect. When the screen closes, the read still waiting should be dropped,
while the rename must still complete before the disconnect. A connect takes 30
ms and every other call 10, and the device turns down a battery read or a
rename while it is not connected. The events and the states are the ones of
[Removing selected pending work](vs-bloc.md#removing-selected-pending-work);
`ReadBattery` is const, so two screens can add one instance of it.

### With bloc alone

`onEvent` stamps each event with the screen it was added for, and a read of a
screen that has left returns:

```dart
class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  final Ble _ble;
  final _stampOf = Expando<int>();
  int _screen = 0;

  DeviceBloc(this._ble) : super(const DeviceState()) {
    on<DeviceEvent>((e, emit) async {
      switch (e) {
        case Connect():
          await _ble.connect();
          emit(state.copyWith(online: true));
        case ReadBattery():
          if (_stampOf[e] != _screen) return;
          emit(state.copyWith(battery: await _ble.battery()));
        case Rename(:final name):
          await _ble.rename(name);
        case Disconnect():
          await _ble.disconnect();
          emit(const DeviceState());
      }
    }, transformer: sequential());
  }

  @override
  void onEvent(DeviceEvent event) {
    super.onEvent(event);
    if (event is Disconnect) _screen++;
    _stampOf[event] = _screen;
  }
}
```

In the traces the screen leaves at once (`Connect`, `ReadBattery`, `Rename`,
`Disconnect`); then a screen that opens again adds `Connect` and the same const
`ReadBattery` after them; and a timer adds a read behind the disconnect
(`Connect`, `Disconnect`, `ReadBattery`):

```text
with bloc alone, leaving: [connect, rename kitchen, disconnect]
with bloc alone, a shared const read: [connect, battery, rename kitchen, disconnect, connect, battery]
with bloc alone, a read after disconnect: [connect, disconnect], the zone [Bad state: battery: not connected]
```

The screen that leaves loses its read. Two screens that add one const instance
share its stamp: the second overwrites the first, and the read of the screen
that left reaches the device. A read added after the disconnect carries the new
stamp, reaches a device that is gone, and its error goes to the zone. A check
of `state.online` before the read turns that one away; the shared stamp stays.

### The first attempt

The calls go to the controller of that section, whose `disconnect` removes the
reads still in its queue. The bloc keeps the one registration with
`sequential()` that held the order of the commands:

```dart
// The first attempt: each command waits in the queue of bloc, and the
// disconnect finds no read in the queue of the controller to remove.
class SequentialDeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  SequentialDeviceBloc(this._device) : super(_device.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _device));
    on<DeviceEvent>((e, emit) async {
      switch (e) {
        case Connect():
          await settle(_device.connect());
        case ReadBattery():
          await settle(_device.readBattery());
        case Rename(:final name):
          await settle(_device.rename(name));
        case Disconnect():
          await settle(_device.disconnect());
        case _Started():
      }
    }, transformer: sequential());
    add(const _Started());
  }

  final StreamedDevice _device;

  @override
  Future<void> close() async {
    await _device.close();
    return super.close();
  }
}
```

`StreamedDevice` and `_Started` are declared with the answer below, as in
[The bridges](#the-bridges). The registration for `DeviceEvent` gets `_Started`
as well, and its `switch` takes it in an empty case.

```text
one sequential registration, leaving: [connect, battery, rename kitchen, disconnect]
one sequential registration, a shared const read: [connect, battery, rename kitchen, disconnect, connect, battery]
one sequential registration, a read after disconnect: [connect, disconnect], the zone []
```

`sequential()` holds each command until the one before it has ended, so the
queue of the controller never has more than one job: when the disconnect comes,
the read has run already. The read behind the disconnect is turned away all the
same: `readBattery` runs only on `Connected`, and the rule is checked when its
job starts.

### With a controller under the bloc

The controller of that section:

```dart
enum DeviceKey { connect, readBattery, rename, disconnect }

final class DeviceController extends Solo<DeviceState> {
  final Ble _ble;

  DeviceController(this._ble) : super(const Offline());

  Job<void> connect() => enqueue<Offline, void>(
    key: DeviceKey.connect,
    cancellable: false,
    (ctx) async {
      await ctx.join(_ble.connect);
      ctx.emit(const Connected());
    },
  );

  Job<void> readBattery() =>
      enqueue<Connected, void>(key: DeviceKey.readBattery, (ctx) async {
        final battery = await ctx.join(_ble.battery);
        ctx.emit(ctx.state.copyWith(battery: battery));
      });

  Job<void> rename(String name) => enqueue<Connected, void>(
    key: DeviceKey.rename,
    cancellable: false,
    (ctx) => ctx.join(() => _ble.rename(name)),
  );

  Job<void> disconnect() {
    queue.removeWhere((job) => job.key == DeviceKey.readBattery);
    return enqueue<Connected, void>(
      key: DeviceKey.disconnect,
      cancellable: false,
      (ctx) async {
        await ctx.join(_ble.disconnect);
        ctx.emit(const Offline());
      },
    );
  }
}
```

Each command gets a registration of its own:

```dart
final class StreamedDevice = DeviceController with SoloStream<DeviceState>;

final class _Started extends DeviceEvent {
  const _Started();
}

class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  DeviceBloc(this._device) : super(_device.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _device));
    on<Connect>((e, emit) => settle(_device.connect()));
    on<ReadBattery>((e, emit) => settle(_device.readBattery()));
    on<Rename>((e, emit) => settle(_device.rename(e.name)));
    on<Disconnect>((e, emit) => settle(_device.disconnect()));
    add(const _Started());
  }

  final StreamedDevice _device;

  @override
  Future<void> close() async {
    await _device.close();
    return super.close();
  }
}
```

```text
a registration per command, leaving: [connect, rename kitchen, disconnect]
a registration per command, a shared const read: [connect, rename kitchen, disconnect, connect, battery]
a registration per command, a read after disconnect: [connect, disconnect], the zone []
```

Each handler hands its command to the controller when its event arrives, and
the commands wait in the queue of the controller, where the disconnect removes
the read. The read of the screen that opened again comes after the disconnect
and stays.

What stays with bloc: a registration for each command, since under one
registration with `sequential()` there is nothing in the queue of the
controller to remove. No `Expando`, no stamps and no check in the handler.
Without the bridges the same controller is the Solo answer of
[Removing selected pending work](vs-bloc.md#removing-selected-pending-work).

## Finishing an in-flight write before restarting

A firmware upload writes BLE chunks one after another, 20 ms each. A
replacement upload must stop the old loop and wait for its current write before
sending any chunk of its own: the BLE API cannot abort an accepted write. In
the traces below each upload has four chunks, the second starts 30 ms after the
first, while chunk 1 is being written, and the third 5 ms after the second or
at the same moment. The events and the states are the ones of
[Finishing an in-flight write before restarting](vs-bloc.md#finishing-an-in-flight-write-before-restarting).

### With bloc alone

A lock shared by the handlers orders the writes, and `emit.isDone` stops a
replaced loop both inside the lock and after the write:

```dart
class Lock {
  Future<void> _tail = Future.value();

  Future<T> protect<T>(Future<T> Function() action) {
    final turn = Completer<void>();
    final before = _tail;
    _tail = turn.future;
    return before.then((_) => action()).whenComplete(turn.complete);
  }
}

class LockedFirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  final Ble _ble;
  final _wire = Lock();

  LockedFirmwareBloc(this._ble) : super(Idle()) {
    on<Flash>((e, emit) async {
      var written = 0;
      for (final chunk in e.chunks) {
        await _wire.protect(() async {
          if (emit.isDone) return;
          await _ble.write(chunk);
        });
        if (emit.isDone) return;
        emit(Flashing(++written, e.chunks.length));
      }
    }, transformer: restartable());
  }
}
```

```text
uploads at 0, 30 and 35 ms: written [0, 1, 200, 201, 202, 203], 1 write at a time at most, states [1/4, 1/4, 2/4, 3/4, 4/4]
uploads at 0, 30 and 30 ms: written [0, 1, 200, 201, 202, 203], 1 write at a time at most, states [1/4, 1/4, 2/4, 3/4, 4/4]
```

The second upload is replaced while it waits for the lock, and the check inside
the lock keeps its write off the wire. Every handler that writes to the device
has to take the same lock.

### With a controller under the bloc

The calls go to the controller of that section:

```dart
final class FirmwareController extends Solo<FirmwareState> {
  final Ble _ble;

  FirmwareController(this._ble) : super(const Idle());

  Job<void> flash(List<Chunk> chunks) => enqueue<NotBroken, void>(
    key: 'flash',
    policy: Policy.restart,
    (ctx) async {
      var written = 0;
      for (final chunk in chunks) {
        await ctx.join(() => _ble.write(chunk));
        ctx.emit(Flashing(++written, chunks.length));
      }
    },
  );
}
```

Besides the bridges, the bloc has one registration, with the transformer bloc
gives it by default:

```dart
final class StreamedFirmware = FirmwareController
    with SoloStream<FirmwareState>;

final class _Started extends FirmwareEvent {}

class FirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  FirmwareBloc(this._firmware) : super(_firmware.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _firmware));
    on<Flash>((e, emit) => settle(_firmware.flash(e.chunks)));
    add(_Started());
  }

  final StreamedFirmware _firmware;

  @override
  Future<void> close() async {
    await _firmware.close();
    return super.close();
  }
}
```

The wire and the states are the ones of the locked bloc, line for line, in both
series. `Policy.restart` cancels the upload in flight and starts its
replacement once that job has ended; `ctx.join` lets the current write land and
then throws `Cancelled`, before the next `emit`. The second upload is replaced
before it starts and writes nothing, and both replaced uploads end
`Cancelled(replaced)`.

What stays with bloc: no lock, no check of `emit.isDone` and no
`restartable()`: the replacement is the policy of `flash`. Without the bridges
the same controller is the Solo answer of
[Finishing an in-flight write before restarting](vs-bloc.md#finishing-an-in-flight-write-before-restarting).

## Where bloc keeps its answer

The other scenarios of [solo and bloc, side by side](vs-bloc.md) get no section
here. In each, bloc alone answers in a few lines of its own, and a controller
under the bloc takes off less than the bridges add.

| Scenario | What stays with bloc |
| --- | --- |
| [Ordering updates to shared state](vs-bloc.md#ordering-updates-to-shared-state) | one registration with `sequential()` for the events that update one state: the queue of bloc starts the refresh once the upload has ended |
| [An observer fails during a state update](vs-bloc.md#an-observer-fails-during-a-state-update) | the guard inside the observer: the observer is bloc's, and the states of a controller reach it through the same `emit` |
| [Closing and cancelling in-flight work](vs-bloc.md#closing-and-cancelling-in-flight-work) | the Bloc answer there with a check of `isClosed` before the call as well as after it: `close()` waits for the call in flight alone, the queued message is not sent, and no reply is published or reported read |
| [Leaving a loading state when the work is cancelled](vs-bloc.md#leaving-a-loading-state-when-the-work-is-cancelled) | the reset from the handler of `CancelRefresh`: a controller that restarts the refresh resets the state between two starts as well, and the screen shows `Initial` for a moment |
| [Typed methods with queued execution](vs-bloc.md#typed-methods-with-queued-execution) | function events and methods that return `void`: `add` returns nothing, and the `Job` of the controller stays in the handler |
| [Awaiting a particular request](vs-bloc.md#awaiting-a-particular-request) | the completer on the event: the caller cannot wait for a `Job` that `add` does not return |
| [Reacting to an independent external state change](vs-bloc.md#reacting-to-an-independent-external-state-change) | the revocation as an event with a registration of its own, and a check of the state on both sides of the await of the build |
| [Releasing a resource returned after cancellation](vs-bloc.md#releasing-a-resource-returned-after-cancellation) | the `try`/`finally` around the buffer: a controller declares the release as `dispose` where the buffer is acquired, and the trace is the same |
