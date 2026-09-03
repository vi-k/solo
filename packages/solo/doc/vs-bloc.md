# solo and bloc, side by side

Part of [solo](https://pub.dev/packages/solo).

bloc fits an ordinary screen well: an event arrives, a handler answers with
a state. The eight items below belong to controllers with a lifecycle —
hardware, devices, players, background sync — where several things happen
to one state and the order matters.

Each item names a domain, then shows what an experienced bloc team writes
for it and what that code costs, then the same thing in `solo`. Where bloc
has a working answer it is here, running; where it has none the item says
so. None of the traps is a bug: they follow from bloc's design — a
transformer per handler, `emit` valid only inside its handler, `add`
returning `void` — and where the point has been argued in the tracker, the
issue is linked.

This document assumes the [README's Concepts][concepts]: `Job` and
`Outcome`, `Policy`, the working type `W` in `run<W, T>`, `ctx.guard` and
the queue.

[concepts]: https://github.com/vi-k/solo/blob/main/packages/solo/README.md#concepts

Every snippet below was compiled and run — the bloc ones against bloc 9.2.1
with bloc_concurrency 0.3.0, the `solo` ones against `solo` 1.0.0 — and
every trace quoted is from those runs.

The same package ships `Cubit`: no events, no transformers, methods that
emit. It answers items 5 and 6 outright — a cubit method takes typed
arguments and returns a value you can `await` — and felangel points at it in
[#1556](https://github.com/felangel/bloc/issues/1556) itself. For the rest
it offers nothing: there is no queue to manage (1), no transformers at all
(2, 3), no cancellation (4), and `emit` after `close` throws `Bad state:
Cannot emit new states after calling close` (item 7 below).

## 1. The queue cannot be managed

A BLE device screen. The user opens it — connect — taps to read the battery
and the signal, renames the device, and closes the window: disconnect. The
two reads were for a screen that no longer exists and should be thrown away;
the rename is what the user asked for and must survive.

**On bloc.** To get a queue at all you funnel every command into a single
`on<DeviceEvent>` with `sequential()`; five separate `on<E>` would give five
queues running side by side, which is the next item. The queue is real but
opaque — there is no API to enumerate what is pending or to remove it — so
the reads are dropped by a flag instead, set in `onEvent`, which `add` calls
synchronously and therefore before the queue reaches them.

```dart
class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  DeviceBloc(this._ble) : super(const DeviceState()) {
    // One handler for the whole type, so `sequential()` makes one queue.
    on<DeviceEvent>((e, emit) async {
      // The reads were only for the screen the user has just closed.
      if (_leaving && (e is ReadBattery || e is ReadSignal)) return;
      switch (e) {
        case Connect():
          await _ble.connect();
          emit(state.copyWith(online: true));
        case ReadBattery():
          emit(state.copyWith(battery: await _ble.battery()));
        case ReadSignal():
          emit(state.copyWith(signal: await _ble.signal()));
        case Rename(:final name):
          await _ble.rename(name);
        case Disconnect():
          await _ble.disconnect();
          emit(const DeviceState());
      }
    }, transformer: sequential());
  }

  final Ble _ble;
  bool _leaving = false;

  @override
  void onEvent(DeviceEvent event) {
    // `add` calls this synchronously, so the flag is already set when the
    // queue reaches the two reads behind the `Disconnect`.
    if (event is Disconnect) _leaving = true;
    super.onEvent(event);
  }
}
```

It works: the hardware sees `[connect, rename kitchen, disconnect]` and the
two reads never happen. What it costs is that the rule now lives in a field
of the bloc rather than at the call site that knows the screen is gone, and
it is a condition rather than a removal — the events still travel the queue
and still reach the handler, every command that can go stale adds a term to
that condition, and the flag has to be reset somewhere. Forget the reset and
a reopened screen swallows its own reads in silence: `[connect, disconnect,
connect]`, with no battery read anywhere.

And nothing can tell whoever asked for the battery that the request was
dropped. `add` returns `void`; that is item 5.

**On solo.** The queue is an object the controller owns, and the jobs in it
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

The hardware trace is the same one. The difference is that the rule is an
expression at the call site, evaluated once, with nothing to reset and
nothing to extend as commands are added; and that the two reads finish with
`Cancelled(manual)` and complete their `done`, so their callers learn what
happened. The rename survives — the user asked for it and never took it
back — and the disconnect follows it, because the queue is sequential and
the disconnect was added last. `removeWhere` touches only the queue: a
`connect` already in flight finishes first.

## 2. One restartable among sequential

A media player. `play`, `pause` and `seek` all talk to one native player, so
they must run one at a time; but a `seek` fired while the user drags the
slider must not queue behind the earlier steps of the drag — only the last
position matters — while the two toggles must run in the order they were
tapped.

**On bloc.** A transformer is an argument to `on<E>` (or, globally,
`Bloc.transformer`), and it orders only the events of that one handler.
Giving `seek` its own `on<Seek>` with `restartable()` does restart the
emitter, but that handler then runs beside `play` and `pause` instead of in
line with them. So all three go into one funnel with `sequential()`, and the
drag is thinned by a newest-seek field: one field, one `onEvent` override
and one early return, with no custom `EventTransformer` to write.

```dart
class PlayerBloc extends Bloc<PlayerCommand, PlayerState> {
  PlayerBloc(this._player) : super(const PlayerState()) {
    on<PlayerCommand>((command, emit) async {
      switch (command) {
        case Play():
          await _player.play();
        case Pause():
          await _player.pause();
        case Seek(:final position):
          // Every drag step but the newest is dropped here.
          if (position != _newestSeek) return;
          await _player.seek(position);
          emit(PlayerState(position: position));
      }
    }, transformer: sequential());
  }

  final Player _player;
  Duration? _newestSeek;

  @override
  void onEvent(PlayerCommand event) {
    if (event is Seek) _newestSeek = event.position;
    super.onEvent(event);
  }
}
```

It delivers what was asked: `[play start, play end, seek 3 start, seek 3
end, pause start, pause end]` — one native seek for the whole drag, the
toggles still in tap order.

What it cannot do is stop a seek that has already started. Drag one step,
wait until it reaches the player, drag again, and the trace is `[seek 1
start, seek 1 end, seek 2 start, seek 2 end]`: the stale step talks to the
device to the end and the newer one waits behind it. This is
`Policy.replace`, not `Policy.restart` — bloc can get the dropping, not the
cancelling; that half is item 4. And the rule is hand-written per command,
once for every command that needs thinning.

**On solo.** The queue is sequential by construction, and a policy belongs
to a job, not to the queue.

```dart
enum PlayerKey { play, pause, seek }

final class PlayerController extends Solo<PlayerState> {
  PlayerController(this._player) : super(Ready());

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

`Policy.restart` drops the queued seeks and cancels the running one, all by
the `seek` key; `play()` and `pause()` name no policy, so they stay in the
same one queue and run in the order they were tapped. The restart reaches
seeks and nothing else, and the policy is a named argument rather than a
field and a branch.

The native `seek` already in flight cannot be aborted — no Dart future can
be — and the trace shows it: `[seek 1 start, seek 2 start, seek 1 end, seek
2 end]`. What changes is that its job is cancelled at once, so the newer
seek starts without waiting for it, and the stale `emit` is refused. The
listeners see `[Ready(2ms)]` where the bloc above published
`[PlayerState(1ms), PlayerState(2ms)]` — the slider does not jump back to a
position the user has already left — and the stale job's handle carries
`Cancelled(manual)`.

## 3. Handlers running in parallel write one state

Notes with sync. `UploadNote` and `RefreshList` change the same state
object, and since bloc 7.2 the default transformer is concurrent: with no
transformer given, both handlers run at once. `RefreshList` asks the server
before the upload lands and emits the answer after it, so a list that
predates the note is written back over the newer one. Reading `state` fresh
after each `await`, as the handlers below do, cures the stale snapshot but
not the interleaving: no snapshot is involved, the two handlers simply take
turns on one object.

**On bloc.** The cure is item 1's shape, applied to the whole controller:
one handler for the event type with `sequential()`, so that only one body is
ever between an `await` and an `emit`.

```dart
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  // One handler for the whole type, so every write to the state is
  // serialized — the shape item 1 was forced into.
  NotesBloc(this._api) : super(const NotesState()) {
    on<NotesEvent>((e, emit) async {
      switch (e) {
        case UploadNote(:final note):
          emit(state.copyWith(uploading: true));
          await _api.upload(note);
          emit(
            state.copyWith(notes: [...state.notes, note], uploading: false),
          );
        case RefreshList():
          emit(state.copyWith(notes: await _api.list()));
      }
    }, transformer: sequential());
  }

  final Api _api;
}
```

It works — the final state is `NotesState([n0, n1], uploading: false)`, the
note kept — and it costs the shape. One handler for the type means one
transformer for every command in it, so item 2's per-command policy is off
the table for good, and the whole controller is one `switch`.

The deeper cost is that the guarantee is a convention, not a rule. A
transformer per handler does not deliver it: with `sequential()` on each of
two separate `on<E>` the note is still lost —
`NotesState([n0], uploading: true)` — because two handlers are two queues.
So the day someone registers a third `on<E>` for a new event type, the state
has two writers again, silently, and no signature changed.

**On solo.** There is one queue and one running root job, so there is
nothing to interleave with.

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
guarantee, not a discipline the two bodies have to keep, and adding a
tenth method does not put it at risk.

## 4. After cancellation the handler keeps running

A firmware update over BLE, written chunk by chunk. A restarted flash must
stop writing to the device; `restartable()` closes the emitter, and that is
all it does — the loop goes on writing.

**On bloc.** The answer is the maintainer's own, in
[felangel/bloc#3349](https://github.com/felangel/bloc/issues/3349):

> This is because Futures aren't truly cancelable. To get the behavior
> you're describing you can simply check if `emit.isDone` is true before
> performing any expensive computations:

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

Within its reach it works. With the line, a flash restarted mid-file writes
`[0, 1, 100, 101, …]` and stops there. Without it the two flashes interleave
to the end: `[0, 1, 2, 100, 3, 101, 4, 102, 5, 103, 104, 105]`, two firmware
images going to one device at once.

The line has to be repeated after every `await` in every loop that touches
hardware, and nothing checks that it is there. And its reach is only the
emitter. Bring the failure in as a state rather than as a restart — a
`HardwareFailed` event that emits `Broken`, which is item 8's supported
route — and `emit.isDone` never becomes true: the flash writes
`[0, 1, 2, 3, 4, 5]` to broken hardware and then overwrites `Broken` with
`Flashing`. The mirror image is a future started inside the handler and left
unawaited; nothing structured outlives the handler, so that one is caught by
an `assert` in debug only
([#2961](https://github.com/felangel/bloc/issues/2961)) — see item 7.

**On solo.** Cancellation is cooperative too, but the waiting ends by
itself.

```dart
final class FirmwareController extends Solo<FirmwareState> {
  FirmwareController(this._ble) : super(const Idle());

  final Ble _ble;

  Job<void> flash(List<Chunk> chunks) => run<NotBroken, void>(
        key: 'flash',
        policy: Policy.restart,
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

The restart writes the same `[0, 1, 100, 101, …]`: `ctx.guard` returns the
moment the cancellation arrives, so the next write never starts. What
differs is reach and reporting.

The same `guard` also ends the job when the state stops matching the working
type, so a `Broken` written by a hardware listener stops the flash at
`[0, 1, 2]` with `Cancelled(rules: is not NotBroken)` instead of finishing
the file — the case `emit.isDone` cannot see. The cancelled call's own
handle carries `Cancelled(manual)`, where `add` carried nothing. And work
that would otherwise be fire-and-forget goes through `ctx.run(child)`, a
child job the parent waits for.

## 5. You cannot await your own event

Checkout. After the user taps Pay, the screen has to know that *this*
payment succeeded before it navigates. `add` returns `void`, and the state
stream says only that the state changed. It is a design decision, not an
omission — felangel in
[felangel/bloc#1556](https://github.com/felangel/bloc/issues/1556):

> … a single add can result in multiple state changes so you would never
> know when the event was actually "done" being processed.

**On bloc.** The answer is a completer carried on the event, and a method on
the bloc that hands its future back to the screen.

```dart
class Pay extends CheckoutEvent {
  Pay(this.order) : result = Completer<Receipt>();
  final Order order;
  final Completer<Receipt> result;
}

class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  CheckoutBloc(this._api) : super(Cart()) {
    on<Pay>((e, emit) async {
      emit(Paying());
      try {
        final receipt = await _api.pay(e.order);
        emit(Paid(receipt));
        e.result.complete(receipt);
      } on Object catch (error, stackTrace) {
        emit(PaymentFailed(error));
        e.result.completeError(error, stackTrace);
      } finally {
        _inFlight.remove(e.order.id);
      }
      // `droppable()` is off the table: it would drop the duplicate
      // without ever entering this handler, and its completer would
      // never complete.
    }, transformer: sequential());
  }

  final Api _api;
  final _inFlight = <String, Completer<Receipt>>{};

  /// What the call site uses instead of `add`.
  Future<Receipt> pay(Order order) {
    final running = _inFlight[order.id];
    if (running != null) return running.future;
    final event = Pay(order);
    _inFlight[order.id] = event.result;
    add(event);
    return event.result.future;
  }
}
```

and the screen is then `navigateToReceipt(await bloc.pay(order))`, which is
what the item asked for: two taps on one order navigate to one receipt, and
a second order gets its own.

The price is the shape. Once this method exists it is the thing `add`
refused to be, and the event class is ceremony around it — item 6. The
completer must be completed on every exit path, error included, or the
screen waits forever; the dedupe cannot be delegated to `droppable()`,
because a dropped event never enters the handler and its completer never
completes, so the `_inFlight` map is hand-written instead. And the exits
bloc owns are the ones the completer cannot see: after `close()`, `pay()`
throws `Bad state: Cannot add new events after calling close`, which is item
7.

**On solo.** A method returns a handle to the job it created.

```dart
final class CheckoutController extends Solo<CheckoutState> {
  CheckoutController(this._api) : super(const Cart());

  final Api _api;

  Job<Receipt> pay(Order order) => run<CheckoutState, Receipt>(
        // The key names the order, so a double tap is a duplicate and a
        // different order is a different job.
        key: ('pay', order.id),
        policy: Policy.droppable,
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
looking at. Because the key names the order rather than the method,
`Policy.droppable` treats a double tap as the duplicate it is — both taps
get the same handle and the same receipt — while a different order is a
different job. Three taps on two orders reach the API twice, the same as the
hand-written `_inFlight` map above, with no map to write. The cancelled and
failed paths arrive as outcomes rather than as a future that never
completes, and after `close` the call returns a job already finished with
`Cancelled(closed)` rather than throwing.

Later in the same thread felangel points at `Cubit`, whose methods are plain
`async` methods you can await — the answer to this item, at the price of the
event queue and the transformers of items 1 to 4.

## 6. A method, not an event

A map. `moveTo`, `setZoom`, `follow` — three actions on one widget, and a
drag fires `moveTo` on every frame. In bloc-with-events each action is a
class, a registration and an `add`: the argument types live in the event,
the work lives in a handler elsewhere, and the call site says `add`, not
what it wants.

**On bloc.** `Cubit` answers this outright: a cubit is methods, which is
another way of saying the ceremony belongs to events, not to the package.

```dart
class MapCubit extends Cubit<MapState> {
  MapCubit(this._map) : super(const MapState());

  final MapApi _map;

  Future<void> moveTo(Point<double> point) async {
    await _map.moveTo(point);
    emit(state.copyWith(center: point));
  }

  Future<void> setZoom(double value) async {
    await _map.setZoom(value);
    emit(state.copyWith(zoom: value));
  }

  Future<void> follow(Track track) => _map.follow(track);
}
```

The ceremony is gone and the arguments are typed. What is gone with it is
the queue: a cubit has none. The drag's frames all run at once against one
native map, and the state is written by whichever call returns last rather
than by the one the finger ended on. Give the native calls uneven durations
and the trace is `[moveTo 1 start, moveTo 2 start, moveTo 3 start, moveTo 3
end, moveTo 2 end, moveTo 1 end]`: the map settles at the first frame of the
drag, `MapState(1)`.

To get the order back you chain futures in a field; to drop the stale frames
you add a newest-point field beside it. That is items 1 and 2 rebuilt by
hand, and a cubit's `close()` does not wait for the chain either.

**On solo.** They are three methods, and the drag keeps a policy.

```dart
enum MapKey { moveTo, setZoom, follow }

final class MapController extends Solo<MapState> {
  MapController(this._map) : super(const MapState());

  final MapApi _map;

  // A drag fires this on every frame; only the newest point matters.
  Job<void> moveTo(Point<double> point) => run<MapState, void>(
        key: MapKey.moveTo,
        policy: Policy.restart,
        (ctx) async {
          await ctx.guard(() => _map.moveTo(point));
          ctx.emit(ctx.state.copyWith(center: point));
        },
      );

  Job<void> setZoom(double value) => run<MapState, void>(
        key: MapKey.setZoom,
        policy: Policy.restart,
        (ctx) async {
          await ctx.guard(() => _map.setZoom(value));
          ctx.emit(ctx.state.copyWith(zoom: value));
        },
      );

  Job<void> follow(Track track) => run<MapState, void>(
        key: MapKey.follow,
        (ctx) => ctx.guard(() => _map.follow(track)),
      );
}

void onMapDrag(MapController map, Point<double> point) => map.moveTo(point);
```

The signature carries the arguments and the result, the call site reads as a
call, and the returned `Job<void>` is there when the caller wants to await
it — calling without `await` raises no lint, because a handle is not a
`Future`. The drag is thinned by the same `Policy.restart` as item 2's seek.
On the same uneven native calls the trace is `[moveTo 1 start, moveTo 3
start, moveTo 3 end, moveTo 1 end]`: the middle frame never starts, and the
first frame's job is cancelled, so its late return writes nothing. The map
ends at `MapState(3)`, where the finger did.

## 7. Closing while work is in flight

A chat or feed screen. The user sends a message, goes back, and the reply
arrives into a controller that is already closed. What happens then depends
on the transformer. With `sequential()`, `close()` waits for the running
handler and the late `emit` lands: the state changes after `close`, and
stream listeners still receive it. With the default transformer,
`concurrent()`, `droppable()` or `restartable()`, `close()` returns at once,
the emitter is cancelled and the late `emit` is dropped without a word.
Either way the body keeps running.

**On bloc.** The usual workaround is an `isClosed` check after every
`await`.

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

It works: `close()` returns only after the body does, however long that
takes, and the state is untouched.

One missed line and, under `sequential()`, the state changes after `close`
and listeners see it; under any other transformer the same missed line is
silent instead. The `add` after `close` throws `Bad state: Cannot add new
events after calling close`
([#52](https://github.com/felangel/bloc/issues/52),
[#120](https://github.com/felangel/bloc/issues/120) — both from the
`mapEventToState` era, several major versions before `on<Event>`; cancelable
operations are still an open proposal,
[#3069](https://github.com/felangel/bloc/issues/3069)), so every call site
that can run after close needs a guard of its own as well.

A future that outlived its handler is the harder case. `emit` from it trips
an `assert` in debug ([#2961](https://github.com/felangel/bloc/issues/2961))
and, with asserts off, simply writes the state: the same run that leaves
`ChatState(null)` under `dart run --enable-asserts` leaves
`ChatState(reply to hi)` without it — a handler that returned long ago still
moving the screen underneath the user.

**On solo.** Closing is part of the same queue discipline.

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

The difference is not the waiting: bloc's `sequential()` waits for the body
too, and a solo body that uses a bare `await` instead of `ctx.guard` makes
`close()` wait just as long. The difference is that a stale write is refused
rather than accepted or swallowed, and that it is refused in release as
well.

A cancelled job's `ctx.emit` throws its `Cancelled`; an `emit` from a future
that outlived the job throws `Bad state: Job(send) has already finished,
cannot emit` — a `throw`, not an `assert`, so it does not vanish when
asserts are off. Queued jobs finish with `Cancelled(closed)` and complete
their `done`; and `send` after `close` returns a job already finished with
the same outcome instead of throwing, so the call site needs no `isClosed`
check.

## 8. The state changes from outside

A camera, or a BLE sensor. The hardware reports a failure through a listener
while a calibration handler is halfway through, and everything after that
point is talking to broken hardware.

**On bloc.** A bloc's own `emit` is `@visibleForTesting` and documented as
internal — "only for internal use and should never be called directly
outside of tests" — so the supported way in from a listener is
`add(HardwareFailed(error))`. That event needs a handler of its own, outside
the calibration's queue, so that it can run beside the calibration rather
than behind it; and the calibration repeats its precondition after every
`await`.

```dart
class SensorBloc extends Bloc<SensorEvent, SensorState> {
  SensorBloc(this._hw) : super(Ready()) {
    // The supported way in is an event. It gets its own handler, so that
    // it can run *beside* the calibration instead of behind it.
    _hw.onError = (error) => add(HardwareFailed(error));
    on<HardwareFailed>((e, emit) => emit(Broken(e.error)));
    on<Calibrate>((e, emit) async {
      if (state is! Ready) return;
      await _hw.zero();
      // Broken may have arrived during the await; nothing cancelled this
      // handler, so the precondition is repeated by hand after every step.
      if (state is! Ready) return;
      await _hw.sample();
      if (state is! Ready) return;
      emit(Calibrated());
    }, transformer: sequential());
  }

  final Sensor _hw;
}
```

It works: the state ends at `Broken(cable unplugged)` and `Calibrated` never
appears.

It costs a line per `await`, in every handler, forever. The precondition is
invisible in the signature, so adding a state or an `await` means auditing
every body again; miss one and the calibration writes `Calibrated` over
`Broken` — a sensor screen reporting success on unplugged hardware.

And the split is not a choice. Apply item 3's cure and put the failure in
the same funnel, and it queues behind the calibration:
`[Calibrated, Broken(cable unplugged)]`, with `Calibrated` published to
listeners on the way past. Serialized state writes or a failure that can
preempt — the transformers give one or the other, not both.

**On solo.** The listener writes the state, and the rules stay in the
declaration.

```dart
final class SensorController extends Solo<SensorState> {
  SensorController(this._hw) : super(const Ready()) {
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
cancels the ones whose working type or `keepWhile` no longer holds: the
calibration ends with `Cancelled(rules: is not Ready)`, and its caller can
read that. The precondition lives in `run<Ready, void>`, where the engine
checks it before the start, on every state change, and on every read — one
place, and a new `await` in the body inherits it.

The `sample()` already in flight still finishes, on both sides; no library
can abort a Dart future. What stops is everything after it.
