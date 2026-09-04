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
`Outcome`, `Policy`, the working type `W` in `run<W, T>`, `ctx.wait`,
`ctx.onCancel` and the queue.

[concepts]: https://github.com/vi-k/solo/blob/main/packages/solo/README.md#concepts

Every snippet below was compiled and run — the bloc ones against bloc 9.2.1
with bloc_concurrency 0.3.0, the `solo` ones against `solo` 1.0.0 — and
every trace quoted is from those runs.

The same package ships `Cubit`: no events, no transformers, methods that
emit. It answers half of item 5 and half of item 6, and it is the same half
twice: a cubit method takes typed arguments and returns a value you can
`await` — felangel points at it in
[#1556](https://github.com/felangel/bloc/issues/1556) itself. The half it
does not answer is the queue the events came with: two calls for one order
charge the card twice (5), and the drag's state is written by whichever
native call returns last (6). The rest it leaves to you too: nothing to
manage because there is no queue (1), no transformers at all (2, 3), no
cancellation (4), and `emit` after `close` throws `Bad state: Cannot emit
new states after calling close` (item 7 below). Items 5 and 6 have the cubit
written out.

## 1. The queue cannot be managed

A BLE device screen. The user opens it — connect — taps to read the battery
and the signal, renames the device, and closes the window: disconnect. The
two reads were for a screen that no longer exists and should be thrown away;
the rename is what the user asked for and must survive.

**On bloc.** To get a queue at all you funnel every command into a single
`on<DeviceEvent>` with `sequential()`; five separate `on<E>` would give five
queues running side by side, which is the next item. The queue is real but
opaque: nothing enumerates what is pending and nothing removes it. The reads
have to be dropped from inside the handler, so the handler has to be told
which of them are stale.

A `bool _leaving`, set when the `Disconnect` is added, is the first answer,
and for one screen it works. It breaks as soon as the screen is reopened
before the queue has drained: the flag is cleared again for the new screen,
and the read that belonged to the old one runs after all
(`[connect, battery, disconnect, connect]`). What survives that is a
generation. Every event is stamped in `onEvent`, which `add` calls
synchronously, and a read runs only if its stamp is still the current one.

```dart
class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  final Ble _ble;
  final _stampOf = Expando<int>();
  int _screen = 0;

  DeviceBloc(this._ble) : super(const DeviceState()) {
    // One handler for the whole type, so `sequential()` makes one queue.
    on<DeviceEvent>((e, emit) async {
      switch (e) {
        case Connect():
          await _ble.connect();
          emit(state.copyWith(online: true));
        case ReadBattery():
          // The reads were only for the screen that asked for them.
          if (_stampOf[e] != _screen) return;
          emit(state.copyWith(battery: await _ble.battery()));
        case ReadSignal():
          if (_stampOf[e] != _screen) return;
          emit(state.copyWith(signal: await _ble.signal()));
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
    // Why here: `add` calls this synchronously, so every event is stamped
    // with the screen that asked for it before the queue reaches any of
    // them. Done inside a handler case instead, the bump would happen when
    // the queue got there, in front of the reads still waiting behind it.
    if (event is Disconnect) _screen++;
    _stampOf[event] = _screen;
    super.onEvent(event);
  }
}
```

It works, and it keeps working when the screen comes back. The hardware
sees `[connect, rename kitchen, disconnect]`; reopen the screen before the
queue has drained and the stale read is dropped while the new one runs:
`[connect, disconnect, connect, battery]`.

What it costs is a second queue. The real one is out of reach, so the bloc
keeps its own record of what is in it — a stamp per event and a counter —
and consults that record from inside the handler. The rule lives in a field
of the bloc rather than at the call site that knows the screen is gone; it
is a condition rather than a removal, so the events still travel the queue
and still reach the handler; and every command that can go stale needs its
own copy of that line. The stamping also holds only while every event is a
distinct object: make the events `const` and the two reads share one stamp,
so the stale one runs again — `[connect, battery, disconnect, connect,
battery]`.

And nothing can tell whoever asked for the battery that the request was
dropped. `add` returns `void`; that is item 5.

**On solo.** The queue is an object the controller owns, and the jobs in it
have keys.

```dart
enum DeviceKey { connect, readBattery, readSignal, rename, disconnect }

final class DeviceController extends Solo<DeviceState> {
  final Ble _ble;

  DeviceController(this._ble) : super(const Offline());

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
        // The radio is not left mid-command: the body waits for it, and
        // the emit throws if the job was cancelled meanwhile.
        await _ble.disconnect();
        ctx.emit(const Offline());
      },
    );
  }
}
```

The hardware trace is the same one. The difference is that the rule is an
expression at the call site, evaluated once against the queue itself, with
no second record to keep in step and nothing to extend as commands are
added; and that the two reads finish with
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

The seek already sent to the device is the hard half. A Dart future cannot
be aborted from outside, so walking away from the wait would leave the
player seeking while the next command was handed to it, and a player asked
to seek twice at once is a player that fails. The native call takes a cancel
token: told to stop, it stops and returns. Both versions below use it; what
differs is who holds it and who waits for the return.

**On bloc.** A transformer is an argument to `on<E>` (or, globally,
`Bloc.transformer`), and it orders only the events of that one handler.
Giving `seek` its own `on<Seek>` with `restartable()` does restart the
emitter, but that handler then runs beside `play` and `pause` instead of in
line with them. So all three go into one funnel with `sequential()`. The
drag is thinned by a newest-position field, and the seek already at the
device is stopped through a second field — the token of the running seek,
cancelled from `onEvent`, which `add` calls synchronously.

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
          // Every drag step but the newest is dropped here.
          if (position != _newestSeek) return;
          final token = CancelToken();
          _seeking = token;
          // The player stops itself and returns, so the command behind
          // this one reaches a device that is no longer seeking.
          await _player.seek(position, cancelToken: token);
          _seeking = null;
          if (token.cancelled) return;
          emit(PlayerState(position: position));
      }
    }, transformer: sequential());
  }

  @override
  void onEvent(PlayerCommand event) {
    // `add` calls this synchronously, so a newer drag step reaches the
    // seek in flight before it reaches the queue behind it.
    if (event is Seek) {
      _newestSeek = event.position;
      _seeking?.cancel();
    }
    super.onEvent(event);
  }
}
```

It delivers what was asked. A whole drag added at once reaches the player as
`[play, seek 3, pause]`: one native seek for the drag, the toggles still in
tap order. Drag one step, let it reach the player, drag again, and the stale
seek is stopped rather than waited out. That claim is about two calls not
overlapping, so this trace pairs each call with its return:
`[seek 1 start, seek 1 stopped, seek 3 start, seek 3 end]` — the first seek
returns early because it was told to, and the second starts only after it
has returned.

The price is that every part of it is assembled by hand. The token is a
field beside the newest-position field: set before the call, cleared after
it, cancelled from an `onEvent` override, and read once more after the await
to decide whether the `emit` still applies — one rule spread over four
places, none of which the compiler ties to the others. The thinning is
written again for every command that needs it. The policy stays the
funnel's: `sequential()` is the transformer for `play` and `pause` as much
as for `seek`, so a command that wants a different one has to leave the
funnel, and leaving the funnel means leaving the queue — which is what sent
`seek` into it in the first place. And whoever called `add` learns none of
this: not that this drag step was dropped as stale, not that this seek was
stopped halfway. `add` returns `void`, which is item 5.

**On solo.** The queue is sequential by construction, a policy belongs to a
job rather than to the queue, and the cancellation goes to the device that
can act on it.

```dart
enum PlayerKey { play, pause, seek }

final class PlayerController extends Solo<PlayerState> {
  final Player _player;

  PlayerController(this._player) : super(Ready());

  // Nothing restarts a toggle, so it just waits for the device; the emit
  // below throws if the job was cancelled while it waited.
  Job<void> pause() => run<Ready, void>(
        key: PlayerKey.pause,
        (ctx) async {
          await _player.pause();
          ctx.emit(ctx.state.copyWith(playing: false));
        },
      );

  Job<void> seek(Duration position) => run<Ready, void>(
        key: PlayerKey.seek,
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          // The player stops on its own, and the job ends only once it
          // has, so the next seek never overlaps this one.
          await _player.seek(position, cancelToken: token);
          ctx.emit(ctx.state.copyWith(position: position));
        },
      );
}
```

`Policy.restart` drops the queued seeks and cancels the running one, all by
the `seek` key; `play()` and `pause()` name no policy, so they stay in the
same one queue and run in the order they were tapped. `ctx.onCancel` fires
the moment the job is marked cancelled, ahead of the body, so the token
reaches the player at once; the body then waits for the call to return, and
the engine starts nothing while a job is running. That pair — cancel now,
start after the return — is what keeps a second seek off a player that is
still seeking.

The device sees what it saw above, `[play, seek 3, pause]` for the drag and
`[seek 1 start, seek 1 stopped, seek 3 start, seek 3 end]` for the restart.
What is different is where the three rules live. The policy is a named
argument on the one job it governs, so `seek` restarts while `play` and
`pause` in the same queue do not — no funnel to leave, and nothing to
rewrite when a fourth command arrives with a fourth answer. The ordering and
the cancelling are the engine's: the token is a local of the body that lives
exactly as long as its job, and no field of the controller points at what is
running. And the outcome reaches the caller — the stale seek's handle
carries `Cancelled(manual)` and completes its `done`, so a slider that wants
to know whether its seek landed can ask.

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
  final Api _api;

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
          final serverNotes = await _api.list();
          emit(state.copyWith(notes: serverNotes));
      }
    }, transformer: sequential());
  }
}
```

It works — the final state is `NotesState([n0, n1], uploading: false)`, the
note kept — and it costs the shape. One handler for the type means one
transformer for every command in it, so item 2's per-command policy is off
the table for good, and the whole controller is one `switch`.

The deeper cost is that the guarantee is a convention, not a rule. A
transformer per handler does not deliver it: with `sequential()` on each of
two separate `on<E>` the note is still lost —
`NotesState([n0], uploading: false)` — because two handlers are two queues.
So the day someone registers a third `on<E>` for a new event type, the state
has two writers again, silently, and no signature changed.

The two lines that read the list are one line in most code:
`emit(state.copyWith(notes: await _api.list()))`. That version is worse than
it looks, because the receiver is evaluated before the awaited argument, so
`state` is the one from before the wait. The upload's write lands inside
that wait and is overwritten wholesale: the note is lost and `uploading`
sticks at `true` — `NotesState([n0], uploading: true)`.

**On solo.** There is one queue and one running root job, so there is
nothing to interleave with.

```dart
final class NotesController extends Solo<NotesState> {
  final Api _api;

  NotesController(this._api) : super(const NotesState());

  Job<void> upload(Note note) => run<NotesState, void>(
        key: 'upload',
        (ctx) async {
          ctx.emit(ctx.state.copyWith(uploading: true));
          await ctx.wait(() => _api.upload(note));
          final merged = [...ctx.state.notes, note];
          ctx.emit(ctx.state.copyWith(notes: merged, uploading: false));
        },
      );

  Job<void> refresh() => run<NotesState, void>(
        key: 'refresh',
        (ctx) async {
          // Runs before upload or after it, never across it.
          final serverNotes = await ctx.wait(_api.list);
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

This device cannot be told to stop. A chunk handed to the stack lands, and
no cancel token takes it back — the ordinary case for a BLE write. So the
only way to keep two firmware images off one wire is to wait for the write
in flight before the next one starts.

**On bloc.** The answer is the maintainer's own, in
[felangel/bloc#3349](https://github.com/felangel/bloc/issues/3349):

> This is because Futures aren't truly cancelable. To get the behavior
> you're describing you can simply check if `emit.isDone` is true before
> performing any expensive computations:

```dart
class FirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  final Ble _ble;

  FirmwareBloc(this._ble) : super(Idle()) {
    on<Flash>((e, emit) async {
      var written = 0;
      for (final chunk in e.chunks) {
        await _ble.write(chunk);
        // Without this line a restarted handler keeps writing chunks to
        // the device: `restartable()` closes the emitter, it does not
        // stop the body. Every loop that touches hardware needs it.
        if (emit.isDone) return;
        emit(Flashing(++written, e.chunks.length));
      }
    }, transformer: restartable());
  }
}
```

Within its reach it works. With the line, a flash restarted mid-file writes
`[0, 1, 100, 101, …]` and stops there. Without it the two flashes interleave
to the end: `[0, 1, 100, 2, 101, 3, 102, 4, 103, 5, 104, 105]`, two firmware
images going to one device at once.

The line has to be repeated after every `await` in every loop that touches
hardware, and nothing checks that it is there. It also arrives too late to
keep the two flashes apart. `restartable()` starts the replacement the
moment the event is added, while the old `_ble.write` is still on the wire,
and `emit.isDone` is not read until that write returns — so the device is
asked for a chunk of the new image while it is still taking one of the old:
`[write 0 start, write 0 end, write 1 start, write 100 start, write 1 end,
write 100 end, …]`.

The transformers have nowhere to put the waiting. They offer "begin the new
handler now" (`restartable()`) and "begin it once the old one has finished
the whole file" (`sequential()`), and not "let the old one come back from
the chunk it is writing, then begin". So the waiting is built beside them,
by hand: the wire goes under a lock. Dart has none in its core, and it is
small enough to write — a chain of futures, each caller holding the turn of
the one behind it:

```dart
/// One at a time. Each caller waits for the one before it and hands the
/// turn on when its own work is done, error or not.
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
        // The replacement handler starts while this write is on the wire
        // and waits here for it to land. Every call to the device, in
        // every handler, has to go through this same lock.
        await _wire.protect(() => _ble.write(chunk));
        if (emit.isDone) return;
        emit(Flashing(++written, e.chunks.length));
      }
    }, transformer: restartable());
  }
}
```

That does it. The same chunks land, `[0, 1, 100, 101, …]`, and now one at a
time: `[write 0 start, write 0 end, write 1 start, write 1 end, write 100
start, write 100 end, …]`.

What it costs is not the lock's length. It is a second ordering standing
next to the transformer's, and the two know nothing of each other.
`restartable()` calls the old handler replaced the moment the event arrives;
the wire says otherwise for another chunk's worth of time, and the lock is
the only thing that knows it. The `emit.isDone` line is still needed — the
lock orders the writes, it does not end the loop. And every call to the
device has to be taken under the same lock, in handlers that have nothing to
do with flashing too; nothing checks that they are, so a single missed one
puts both images back on the wire with no error anywhere.

And the reach of `emit.isDone` is only the emitter. Bring the failure in as
a state rather than as a restart — a `HardwareFailed` event that emits
`Broken`, which is item 8's supported route — and `emit.isDone` never
becomes true: the flash writes `[0, 1, 2, 3, 4, 5]` to broken hardware and
then overwrites `Broken` with `Flashing`. The mirror image is a future
started inside the handler and left unawaited; nothing structured outlives
the handler, so that one is caught by an `assert` in debug only
([#2961](https://github.com/felangel/bloc/issues/2961)) — see item 7.

**On solo.** The waiting is the queue's, and there is nothing to write for
it.

```dart
final class FirmwareController extends Solo<FirmwareState> {
  final Ble _ble;

  FirmwareController(this._ble) : super(const Idle());

  Job<void> flash(List<Chunk> chunks) => run<NotBroken, void>(
        key: 'flash',
        policy: Policy.restart,
        (ctx) async {
          var written = 0;
          for (final chunk in chunks) {
            await _ble.write(chunk);
            // What ends the loop is this emit: it throws the job's
            // Cancelled. The write above has already landed, and the
            // flash that replaces this one is not started until the whole
            // body has come back.
            ctx.emit(Flashing(++written, chunks.length));
          }
        },
      );
}
```

The restart writes the same `[0, 1, 100, 101, …]` as the locked bloc above,
and one at a time in the same way: `[write 0 start, write 0 end, write 1
start, write 1 end, write 100 start, write 100 end, …]`. Nothing in the
controller arranges that, and there is no lock. A job holds the controller
until its body comes back, and `Policy.restart` marks this one cancelled and
queues the replacement behind it, so the second flash cannot reach the
device while the first is still on it.

The same body covers the other cancellation as well, the one the restart
never reaches: a `Broken` written by a hardware listener no longer matches
the working type, so the job is marked, and the flash stops at `[0, 1, 2]`
with `Cancelled(rules: is not NotBroken)` instead of finishing the file —
the case `emit.isDone` cannot see. The cancelled call's own handle carries
`Cancelled(manual)`, where `add` carried nothing. And work that would
otherwise be fire-and-forget goes through `ctx.run(child)`, a child job the
parent waits for.

## 5. You cannot await your own event

Checkout. Something asks the app to pay for an order and has to know
whether *this* payment went through. `add` returns `void`, and the state
stream says only that the state changed. It is a design decision, not an
omission — felangel in
[felangel/bloc#1556](https://github.com/felangel/bloc/issues/1556):

> … a single add can result in multiple state changes so you would never
> know when the event was actually "done" being processed.

The first answer is that nothing should ask. A screen does not await: it
listens, and a `BlocListener` navigates when `Paid` arrives. That is right,
and for a screen it is the end of the discussion — asking a bloc for the
result of one event, from a widget that could simply watch the state, is
working against the library. Most screens never need this item.

It stops being right when the caller is not a screen. A platform-channel
handler answering the system, `WidgetsBindingObserver.didRequestAppExit`
answering the framework with an `AppExitResponse`, an asynchronous router
guard answering with a route — none of them has a `BuildContext`, anything
to rebuild or anyone to listen. Each is a function that has to return an
answer about the request it was handed, with a caller on the other side
holding the line until it does.

It also has to be the controller's payment and not a repository call beside
it. The app's own Pay button runs the same operation; two callers must not
charge the card twice, and the one that arrives second has to be told the
outcome of the run that is already going. Owning that operation is what the
controller is for — item 1 — so the caller has to reach the controller and
wait for it, which is exactly what `add` will not do.

**On bloc.** The answer is a completer carried on the event, and a method on
the bloc that hands its future back to the caller.

```dart
class Pay extends CheckoutEvent {
  final Order order;
  final Completer<Receipt> result;

  Pay(this.order) : result = Completer<Receipt>();
}

class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  final Api _api;
  final _inFlight = <String, Completer<Receipt>>{};

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

and the caller is then `await bloc.pay(order)`, which is what the item
asked for: two calls for one order answer with one receipt, and a second
order gets its own.

The price is the shape. Once this method exists it is the thing `add`
refused to be, and the event class is ceremony around it — item 6. The
completer must be completed on every exit path, error included, or the
caller waits forever with nothing to time it out; the dedupe cannot be
delegated to `droppable()`, because a dropped event never enters the handler
and its completer never completes, so the `_inFlight` map is hand-written
instead. And the exits bloc owns are the ones the completer cannot see:
after `close()`, `pay()` throws `Bad state: Cannot add new events after
calling close`, which is item 7.

**On Cubit.** The same package's other controller has no events: a method
takes arguments and returns a value, so the awaiting half of this item is
answered by the language. `emit(Paying())`, `await _api.pay(order)`,
`emit(Paid(receipt))`, `return receipt`, and the caller has its receipt.

The other half is not answered at all. Nothing owns the operation, so two
calls for one order run their bodies side by side and charge the card
twice, and their `emit`s interleave with no transformer to reach for —
item 3. Getting to what this item asked for means writing both halves by
hand, the in-flight map from the bloc above and a lock like item 4's:

```dart
class CheckoutCubit extends Cubit<CheckoutState> {
  final Api _api;
  final _inFlight = <String, Future<Receipt>>{};
  Future<void> _tail = Future.value();

  CheckoutCubit(this._api) : super(Cart());

  /// One payment at a time, and a second call for an order already on its
  /// way joins that one instead of charging the card again.
  Future<Receipt> pay(Order order) {
    final running = _inFlight[order.id];
    if (running != null) {
      return running;
    }
    final turn = Completer<void>();
    final before = _tail;
    _tail = turn.future;
    final result = before.then((_) => _pay(order)).whenComplete(turn.complete);
    _inFlight[order.id] = result;
    return result;
  }

  Future<Receipt> _pay(Order order) async {
    emit(Paying());
    try {
      final receipt = await _api.pay(order);
      emit(Paid(receipt));
      return receipt;
    } finally {
      _inFlight.remove(order.id);
    }
  }
}
```

That reaches it: three calls for two orders charge twice, and the second
call for an order gets the first one's receipt. What is left over is
`close`. A cubit closing over a payment in flight neither waits for it nor
stops it — `close()` returns at once, the charge goes through behind it,
and the caller waiting for a receipt gets `Bad state: Cannot emit new
states after calling close` instead. The payment happened and there is
nobody left to say so.

**On solo.** A method returns a handle to the job it created.

```dart
final class CheckoutController extends Solo<CheckoutState> {
  final Api _api;

  CheckoutController(this._api) : super(const Cart());

  Job<Receipt> pay(Order order) => run<CheckoutState, Receipt>(
        // The key names the order, so a second call is a duplicate and a
        // different order is a different job.
        key: ('pay', order.id),
        policy: Policy.droppable,
        (ctx) async {
          ctx.emit(const Paying());
          // A charge that has left for the server cannot be taken back, so
          // nothing may cancel this job until it comes back.
          final receipt = await ctx.uncancellable(() => _api.pay(order));
          ctx.emit(Paid(receipt));
          return receipt;
        },
      );
}
```

and the function that owes the answer:

```dart
/// The platform side asked this app to pay and holds the line until it
/// learns whether this payment went through.
Future<Map<String, Object?>> handlePayRequest(
  CheckoutController checkout,
  Order order,
) async {
  switch (await checkout.pay(order).done) {
    case Done(:final value):
      return {'paid': true, 'receipt': value.id};
    case Cancelled(:final reason):
      return {'paid': false, 'cancelled': reason.name};
    case Failed(:final error):
      return {'paid': false, 'error': '$error'};
  }
}
```

`done` carries the outcome of this call and never throws; `value` carries
the value and throws instead. Neither has to guess whose state change it is
looking at. Because the key names the order rather than the method,
`Policy.droppable` treats a second call as the duplicate it is — both
callers get the same handle and the same receipt — while a different order
is a different job. Three calls for two orders reach the API twice, the
same as the map and the lock above, with neither to write.

`ctx.uncancellable` is the rest of it, and it is worth saying what a plain
`await` would do in its place: `close` would wait for the charge, but a
cancelled job's outcome is its cancellation, so the receipt would still be
thrown away. Turning cancellation down for the length of the call is what a
charge already on its way deserves: `cancel` and `close` are refused while
it runs and `close` waits, so the job comes back `Done(receipt)` for a
payment that really happened, the state ends at `Paid`, and the app
finishes closing after that.

The `Paid` line that records the receipt is an ordinary write, and a job
cancelled while the charge was on its way would throw there instead of
recording anything. Nothing can have cancelled it: the actors are turned
down for the length of the step, and the job's own rules cannot reach it
either, because `W` is the base `CheckoutState` and there is no `keepWhile`.
That pairing is deliberate — a narrower working type would let a state
change cancel the payment in the gap between the charge and the line that
records it.

It brackets the charge and nothing else, which is the point: the moments
around it stay ordinary. A payment still waiting its turn in the queue, or
one that has done no more than emit `Paying`, is cancelled by `job.cancel()`
like any other job, because until the card is charged the user is entitled
to change their mind. `cancellable: false` on the job would have covered all
of that too — the place in the queue included — and taken it away. Which is
also why the handler's `Cancelled` branch is not dead. It arrives for a
payment cancelled before the charge left, for one still queued when the
controller closed, and for a call made after `close`, which never starts at
all.

## 6. Methods or a queue, not both

A map. `moveTo` and `setZoom` — two actions on one widget, and a drag fires
`moveTo` on every frame. In bloc-with-events each action is a class, a
registration and an `add`: the argument types live in the event, the work
lives in a handler elsewhere, and the call site says `add`, not what it
wants.

**On bloc.** `Cubit` answers half of this outright: a cubit is methods,
which is another way of saying the ceremony belongs to events, not to the
package.

```dart
class MapCubit extends Cubit<MapState> {
  final MapApi _map;

  MapCubit(this._map) : super(const MapState());

  Future<void> moveTo(Point<double> point) async {
    await _map.moveTo(point);
    emit(state.copyWith(center: point));
  }

  Future<void> setZoom(double value) async {
    await _map.setZoom(value);
    emit(state.copyWith(zoom: value));
  }
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

**On solo.** They are two methods, and the drag keeps a policy.

```dart
enum MapKey { moveTo, setZoom }

final class MapController extends Solo<MapState> {
  final MapApi _map;

  MapController(this._map) : super(const MapState());

  // A drag fires this on every frame; only the newest point matters.
  Job<void> moveTo(Point<double> point) => run<MapState, void>(
        key: MapKey.moveTo,
        policy: Policy.restart,
        (ctx) async {
          // Restartable, so the cancellation goes to the map itself and
          // the body waits for it to come back — item 2's shape.
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await _map.moveTo(point, cancelToken: token);
          ctx.emit(ctx.state.copyWith(center: point));
        },
      );

  Job<void> setZoom(double value) => run<MapState, void>(
        key: MapKey.setZoom,
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await _map.setZoom(value, cancelToken: token);
          ctx.emit(ctx.state.copyWith(zoom: value));
        },
      );
}

void onMapDrag(MapController map, Point<double> point) => map.moveTo(point);
```

The signature carries the arguments and the result, the call site reads as a
call, and the returned `Job<void>` is there when the caller wants to await
it — calling without `await` raises no lint, because a handle is not a
`Future`. The drag is thinned by the same `Policy.restart` as item 2's seek,
and both methods hand the cancellation to the map the same way. On the same
uneven native calls the trace is `[moveTo 1 start, moveTo 1 stopped, moveTo
3 start, moveTo 3 end]`: the middle frame never starts, the first is told to
stop, and the third reaches the map only after it has. The map ends where
the finger did, and so does `MapState(3)`.

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
  final Api _api;

  ChatBloc(this._api) : super(const ChatState()) {
    on<SendMessage>((e, emit) async {
      final reply = await _api.send(e.text);
      // The user went back while the request was in flight. Without
      // this line the reply still reaches the state — `sequential()`
      // makes `close()` wait for this body — and the `add` below throws
      // `Bad state: Cannot add new events after calling close`.
      if (isClosed) return;
      emit(state.withReply(reply));
      // Its own event: an inline `await` would run under this
      // handler's transformer and keep `close()` waiting for it.
      add(const MarkReplyRead());
    }, transformer: sequential());
    on<MarkReplyRead>(
      (e, emit) => _api.markRead(),
      transformer: sequential(),
    );
  }
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
  final Api _api;

  ChatController(this._api) : super(const ChatState());

  Job<void> send(String text) => run<ChatState, void>(
        key: 'send',
        (ctx) async {
          final reply = await ctx.wait(() => _api.send(text));
          ctx.emit(ctx.state.withReply(reply));
          markReplyRead();
        },
      );

  Job<void> markReplyRead() =>
      run<ChatState, void>((ctx) => ctx.wait(_api.markRead));
}

Future<void> onScreenClosed(ChatController chat) async {
  // Cancels the running send and waits for its body to stop; queued
  // jobs finish with Cancelled(closed).
  await chat.close();
  chat.send('bye'); // a job already finished with Cancelled(closed)
}
```

The difference is not the waiting: bloc's `sequential()` waits for the body
too, and a solo body that uses a bare `await` instead of `ctx.wait` makes
`close()` wait just as long. The difference is that a stale write is refused
rather than accepted or swallowed, and that it is refused in release as
well.

In the body above the cancellation arrives at `ctx.wait`, which throws the
job's `Cancelled`, so the `emit` line is never reached. Write the same body
with a bare `await` and it is reached with the job already cancelled, and
`ctx.emit` throws that `Cancelled` instead of writing: the missed `isClosed`
line has no counterpart here, because the check belongs to the engine. The
harder case is the same one — a future the body started and never awaited,
landing after the job is over — and its `ctx.emit` throws `Bad state:
Job(send) has already finished, cannot emit`, a `throw` and not an `assert`,
so it does not vanish when asserts are off. Queued jobs finish with
`Cancelled(closed)` and complete their `done`; and `send` after `close`
returns a job already finished with the same outcome instead of throwing, so
the call site needs no `isClosed` check.

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
  final Sensor _hw;

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
  final Sensor _hw;

  SensorController(this._hw) : super(const Ready()) {
    // The listener writes the state itself. Every running job whose
    // working type or keepWhile no longer holds is cancelled at once.
    _hw.onError = (error) => externalSetState(Broken(error));
  }

  // The precondition is the signature: W is Ready. Nothing to check in
  // the body, and nothing to repeat after each await.
  Job<void> calibrate() => run<Ready, void>(
        key: 'calibrate',
        (ctx) async {
          // Sensor calls are awaited, not abandoned; `check` is where
          // the job gives up if the state stopped matching meanwhile.
          await _hw.zero();
          ctx.check();
          await _hw.sample();
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

The `sample()` already in flight still finishes, on both sides: no library
can abort a Dart future, and a sensor that has just lost its cable has
nothing left to be told. Where a device does take a cancel token, item 2
hands it one through `ctx.onCancel`. What stops here is everything after
the sample.
