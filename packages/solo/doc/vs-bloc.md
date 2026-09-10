# solo and bloc, side by side

Part of [solo](https://pub.dev/packages/solo).

bloc fits an ordinary screen well: an event arrives, a handler answers with
a state. The ten items below belong to controllers with a lifecycle —
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
`Outcome`, `Policy`, the working type `W` in `run<W, T>` and the `keepWhile`
beside it, `ctx.wait` and the cleanup registered with a value,
`ctx.onCancel`, `SoloObserver` and the queue.

[concepts]: https://github.com/vi-k/solo/blob/main/packages/solo/README.md#state-and-rules

Every snippet below was compiled and run — the bloc ones against bloc 9.2.1
with bloc_concurrency 0.3.0, the `solo` ones against `solo` 0.2.0 — and
every trace quoted is from those runs.

The same package ships `Cubit`: no events, no transformers, methods that
emit. Item by item, that changes little. It has no transformers to reach
for, so items 1 and 4 are its problem too; item 2 it shares whole, because
the observer runs inside `BlocBase.emit` and that is the same method in
both; `emit` after `close` throws `Bad state: Cannot emit new states after
calling close`, which is item 3; there is no queue to manage, which is
item 6; there is no cancellation, which is item 9; and in item 10 it has no
emitter, so not even `emit.isDone` is there and the staleness check goes
back to a field of its own.

Items 5 and 7 it answers halfway, and it is the same half twice: a cubit
method takes typed arguments and returns a value you can `await` — felangel
points at it in
[#1556](https://github.com/felangel/bloc/issues/1556) itself. The half it
does not answer is the queue the events came with: the drag's state is
written by whichever native call returns last (5), and two calls for one
order charge the card twice (7). Both items have the cubit written out.

## 1. Handlers running in parallel write one state

Notes with sync. `UploadNote` and `RefreshList` change the same state
object, and since bloc 7.2 the default transformer is concurrent: with no
transformer given, both handlers run at once. `RefreshList` asks the server
before the upload lands and emits the answer after it, so a list that
predates the note is written back over the newer one. Reading `state` fresh
after each `await`, as the handlers below do, cures the stale snapshot but
not the interleaving: no snapshot is involved, the two handlers simply take
turns on one object.

**On bloc.** The cure is a funnel — one handler for the whole event type
with `sequential()` — so that only one body is ever between an `await` and
an `emit`. Several of the items below start from that shape and are about
what it costs; item 8 is about a state change that cannot be put into it at
all.

```dart
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final Api _api;

  // One handler for the whole type, so every write to the state is
  // serialized: one queue, one body between an await and an emit.
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
transformer for every command in it, so a policy per command is off the
table for good; and with a class per event, as here, the whole controller
becomes one `switch`. Item 5 shows the other shape the same single handler
can take.

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
          // A write is not walked away from: `join` holds the job, and
          // with it the queue, until the server has answered.
          await ctx.join(() => _api.upload(note));
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
children, started by `ctx.run` inside the same body — item 9 — and
`externalSetState` from outside, which is item 8; both deliberate, both
visible. That is the ownership guarantee, not a discipline the two bodies
have to keep, and adding a tenth method does not put it at risk.

There is a discipline, and it is worth naming next to the guarantee rather
than at the end: every wait inside a body goes through the context. A bare
`await` still runs — nothing stops it — and what it runs is outside
cancellation and outside the working type: no checkpoint is reached, so a
job already cancelled goes on waiting for it. `close()` does wait for it,
because it is still part of the future the body returned; what escapes
`close` as well is work handed to `unawaited(...)`, which outlives the body
that started it. Nothing checks that either is absent, which is the same
kind of unchecked convention the bloc side of these items keeps paying for.
What differs is the price of forgetting: here the call escapes the
guarantees, where a missed `isClosed` writes state that was already
stale.

The write waits with `join` and the read with `wait`, and the difference is
the point: a read can be abandoned, a write cannot. A cancelled `wait`
would end the upload job while `_api.upload` was still on the wire, the
queue would start `refresh`, and the server would be read across a write in
flight — the very interleaving this item is about.

## 2. An observer's error becomes the command's error

A field recorder. `start` asks the native recorder to begin, publishes
`Recording` and arms the level meter. An observer sends every state change
to telemetry, and one day the telemetry call throws — the endpoint is down,
or the change will not serialize. The recorder is already running, so a
failed metric must not leave the screen at `Idle` with the meter off.

**On bloc.** The library says the order itself, in the dartdoc of
`onChange`:

> [onChange] is called before the `state` of the `cubit` is updated.

`BlocBase.emit` — the one `Bloc` and `Cubit` share — wraps that whole
sequence in a single `try` whose `catch` calls `onError` and rethrows. So
the observer runs first, and an observer that throws stops the write it was
only there to watch.

```dart
class RecorderBloc extends Bloc<StartRecording, RecorderState> {
  final Recorder _recorder;
  final Journal _journal;

  RecorderBloc(this._recorder, this._journal) : super(const Idle()) {
    on<StartRecording>((e, emit) async {
      await _recorder.start();
      // Nothing defensive here, and nothing concurrent: one handler, one
      // operation, no transformer involved.
      emit(const Recording());
      _recorder.armMeter();
    });
  }

  // An override of its own is required to call `super.onChange`, and that
  // is the call the global observer rides in on. A global observer that
  // throws therefore takes the line below with it.
  @override
  void onChange(Change<RecorderState> change) {
    super.onChange(change);
    _journal.note('${change.nextState}');
  }
}

class TelemetryObserver extends BlocObserver {
  final Telemetry _telemetry;

  TelemetryObserver(this._telemetry);

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    // The endpoint is down, so this throws.
    _telemetry.send(change.nextState);
  }
}
```

The recorder is running and the screen says otherwise. The state stays
`Idle`; `armMeter` is never reached, so the device trace is `[native start]`
and nothing after it; the journal is `[]`, because the line that writes it
stands after the `super.onChange` that threw — one failing telemetry call
switched off the controller's own bookkeeping as well. The handler itself
ends with `telemetry unavailable`: `onError` is called and then `emit`
rethrows, so the error carries on past the handler into the zone. `Cubit`
is the same code path, and the same run through `RecorderCubit.start()`
hands the telemetry error to whoever called the method.

The fix is a wrapper, and it works:

```dart
class GuardedTelemetryObserver extends BlocObserver {
  final Telemetry _telemetry;
  final Log _fallback;

  GuardedTelemetryObserver(this._telemetry, this._fallback);

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    // Every observation callback that can throw needs this, in every
    // observer, and nothing checks that it is there.
    try {
      _telemetry.send(change.nextState);
    } on Object catch (error, stackTrace) {
      _fallback.write(error, stackTrace);
    }
  }
}
```

With it the state reaches `Recording`, the device trace is `[native start,
arm meter]`, the journal holds `[Recording]` and the telemetry error goes
to the fallback log instead of the zone. The price is the convention: every
callback
of every observer has to be written this way, and the day one is not, a
diagnostic channel decides whether a command runs. `onError` is not the
place to do it either — `emit` calls it and then rethrows anyway.

**On solo.** The hooks are called on their own, one at a time, and what
they throw goes to the zone.

```dart
final class RecorderController extends Solo<RecorderState> {
  final Recorder _recorder;
  final Journal _journal;

  RecorderController(this._recorder, this._journal) : super(const Idle());

  Job<void> start() => run<RecorderState, void>(
        key: 'start',
        (ctx) async {
          await ctx.join(_recorder.start);
          ctx.emit(const Recording());
          _recorder.armMeter();
        },
      );

  // Called on its own, so the global observer standing next to it cannot
  // switch it off.
  @override
  void onChange(RecorderState previous, RecorderState current) =>
      _journal.note('$current');
}

final class TelemetryObserver extends SoloObserver {
  final Telemetry _telemetry;

  TelemetryObserver(this._telemetry);

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      _telemetry.send(current);
}
```

One observer serves every controller of an app, so its hook is handed the
base type they all share, `SoloBase`, rather than the `Solo<S>` the rest of
this document builds on; the instance hook next to it is typed in the
controller's own state.

The observer throws exactly as before, and the body does not notice. The
state reaches `Recording`, the device trace is `[native start, arm meter]`,
the job ends `Done(null)`, and the journal holds `[Recording]` even though
the global observer standing next to it has just failed. The telemetry
error arrives where an unhandled `Future` error would — the zone.

That is isolation of control flow, and it is worth saying what it is not.
The error is not swallowed: in a zone that does not handle it, an unhandled
error is still an unhandled error, and both runs above are under
`runZonedGuarded` for exactly that reason. `solo` does not make an
unreliable logger reliable. What it does is keep the logger's failure out
of the decision about whether the recorder is recording.

## 3. Closing while work is in flight

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
takes, and the state is untouched. The second `on<E>` is a second queue,
which is what item 1 warned about; it is safe here only because
`MarkReplyRead` writes no state. Give it one to write and the two handlers
are two writers again.

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
          // Not a child: `run` always goes through the queue, so this is
          // a root job standing behind the current one.
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
`Cancelled(closed)` and complete their `done` — the future on the handle
that carries the outcome and never throws, item 7 — and `send` after `close`
returns a job already finished with the same `Cancelled(closed)` instead of
throwing, so the call site needs no `isClosed` check.

## 4. One restartable among sequential

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
          // Every drag step whose position is not the newest is
          // dropped here — see below for what that misses.
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

It delivers what was asked, for a drag that keeps moving. A whole one added
at once reaches the player as `[play, seek 3, pause]`: one native seek for
the drag, the toggles still in tap order. What the field compares is the
position, not which event is newest, so a drag that comes back to a
position it already had lets both of those through: `1, 2, 1` in one batch
reaches the device as `[play, seek 1, seek 1, pause]`. A generation counter
per event fixes it, which is item 6's `Expando` written a second time.

Drag one step, let it reach the player, drag again, and the stale
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
stopped halfway. `add` returns `void`, which is item 7.

**On solo.** The queue is sequential by construction, a policy belongs to a
job rather than to the queue, and the cancellation goes to the device that
can act on it. `Ready` as the first type argument is the job's working
type: the engine checks the state against it and cancels the job when it
stops matching, which is item 8. This player has no other state, so nothing
is narrowed away here and `Ready` can be read as the state it is in.

```dart
enum PlayerKey { play, pause, seek }

final class PlayerController extends Solo<PlayerState> {
  final Player _player;

  PlayerController(this._player) : super(Ready());

  // Nothing restarts a toggle, so it just waits the device out.
  Job<void> pause() => run<Ready, void>(
        key: PlayerKey.pause,
        (ctx) async {
          await ctx.join(_player.pause);
          ctx.emit(ctx.state.copyWith(playing: false));
        },
      );

  Job<void> seek(Duration position) => run<Ready, void>(
        key: PlayerKey.seek,
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          // The player stops on its own, and `join` waits for it, so
          // the next seek never overlaps this one.
          await ctx.join(() => _player.seek(position, cancelToken: token));
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

## 5. A method, an event, and one queue

A map. `moveTo` and `setZoom` — two actions on one widget, and a drag fires
`moveTo` on every frame. With a class per event — the shape items 1 and 6
are written in — each action is a class, a registration and an `add`: the
argument types live in the event, the work lives in a handler elsewhere,
and the call site says `add`, not what it wants.

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
drag, `MapState(1, z1)`.

To get the order back you chain futures in a field; to drop the stale frames
you add a newest-point field beside it. That is item 1's queue and item 4's
restart rebuilt by hand, and a cubit's `close()` does not wait for the chain
either.

The queue is not the thing a method costs, though, and `Bloc` has a shorter
answer than the cubit. `Event` is a type parameter with no bound, so the
event can be a function; one handler runs it, and the methods around it are
ordinary typed methods.

```dart
typedef MapCommand = Future<void> Function(Emitter<MapState>);

class CommandMapBloc extends Bloc<MapCommand, MapState> {
  final MapApi _map;

  CommandMapBloc(this._map) : super(const MapState()) {
    on<MapCommand>(
      (command, emit) => command(emit),
      transformer: sequential(),
    );
  }

  void moveTo(Point<double> point) => add((emit) async {
        await _map.moveTo(point);
        emit(state.copyWith(center: point));
      });

  void setZoom(double value) => add((emit) async {
        await _map.setZoom(value);
        emit(state.copyWith(zoom: value));
      });
}
```

That is both halves: typed arguments at the call site and bloc's own queue
behind them. The drag runs in order — `[moveTo 1 start, moveTo 1 end,
moveTo 2 start, moveTo 2 end, moveTo 3 start, moveTo 3 end]`, ending at
`MapState(3, z4)` — and no chain of futures is written by hand.

What it costs is what the type says. The event is
`Function(Emitter<MapState>)`, so the emitter is now part of the public
event type and every command in the bloc is that one type: the transformer
is the funnel's, and a command that wants its own is back at item 4. The
methods return `void`, because `add` does, so nothing here can be awaited
— that is item 7. And the body of each command is a closure over the bloc,
which is where the ceremony went rather than where it stopped.

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
          // `join` waits for it to come back — item 4's shape.
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => _map.moveTo(point, cancelToken: token));
          ctx.emit(ctx.state.copyWith(center: point));
        },
      );

  Job<void> setZoom(double value) => run<MapState, void>(
        key: MapKey.setZoom,
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => _map.setZoom(value, cancelToken: token));
          ctx.emit(ctx.state.copyWith(zoom: value));
        },
      );
}

void onMapDrag(MapController map, Point<double> point) => map.moveTo(point);
```

The signature carries the arguments and the result, the call site reads as a
call, and the returned `Job<void>` is there when the caller wants to await
it — calling without `await` raises no lint, because a handle is not a
`Future`. The drag is thinned by the same `Policy.restart` as item 4's seek,
and both methods hand the cancellation to the map the same way. On the same
uneven native calls the trace is `[moveTo 1 start, moveTo 1 stopped, moveTo
3 start, moveTo 3 end]`: the middle frame never starts, the first is told to
stop, and the third reaches the map only after it has. The map ends where
the finger did, and so does `MapState(3, z4)`.

## 6. The queue cannot be managed

A BLE device screen. The user opens it — connect — taps to read the battery
and the signal, renames the device, and closes the window: disconnect. The
two reads were for a screen that no longer exists and should be thrown away;
the rename is what the user asked for and must survive.

**On bloc.** To get a queue at all you funnel every command into a single
`on<DeviceEvent>` with `sequential()`; five separate `on<E>` would give five
queues running side by side, which is item 1. The queue is real but
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
dropped. `add` returns `void`; that is item 7.

**On solo.** The queue is an object the controller owns, and the jobs in it
have keys.

```dart
enum DeviceKey { connect, readBattery, readSignal, rename, disconnect }

// The state here is two classes rather than one object with flags:
// `Offline` until the radio answers, `Connected` after it. That is what
// lets a job name `Connected` as its working type — the bloc above has to
// carry the same fact in a `bool` and check it by hand.
final class DeviceController extends Solo<DeviceState> {
  final Ble _ble;

  DeviceController(this._ble) : super(const Offline());

  // connect() emits `Connected`; readBattery(), readSignal() and rename()
  // are ordinary jobs standing on it.

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
        // `join` does not leave the radio mid-command: it waits for the
        // call and gives up only once the radio is back.
        await ctx.join(_ble.disconnect);
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

## 7. You cannot await your own event

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
controller is for — its state in item 1, its queue in item 6 — so the
caller has to reach the controller and
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
      try {
        emit(Paying());
        final receipt = await _api.pay(e.order);
        // The result first, the state after it: an `emit` that throws —
        // a failing observer is item 2 — must not be the thing that
        // leaves the caller waiting.
        e.result.complete(receipt);
        emit(Paid(receipt));
      } on Object catch (error, stackTrace) {
        if (!e.result.isCompleted) {
          e.result.completeError(error, stackTrace);
        }
        emit(PaymentFailed(error));
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
    try {
      add(event);
    } on Object {
      // `add` after `close` throws, and this event will never reach the
      // handler that completes it. Without this the entry stays, and the
      // next `pay` for the order hands back a future nobody will ever
      // complete.
      _inFlight.remove(order.id);
      rethrow;
    }
    return event.result.future;
  }
}
```

and the caller is then `await bloc.pay(order)`, which is what the item
asked for: two calls for one order answer with one receipt, and a second
order gets its own.

The price is the shape. Once this method exists it is the thing `add`
refused to be, and the event class is ceremony around it — item 5. The
completer must be completed on every exit path, error included, or the
caller waits forever with nothing to time it out; the dedupe cannot be
delegated to `droppable()`, because a dropped event never enters the handler
and its completer never completes, so the `_inFlight` map is hand-written
instead.

Every exit path is more of them than it looks. Three things in the code
above are there for that alone: the `try` around `add`, because `add` after
`close` throws `Bad state: Cannot add new events after calling close` —
item 3 — and would otherwise leave a dedupe entry nobody can complete; the
`isCompleted` guard, because the `catch` is also reached from a failed
`emit`; and completing the result before writing `Paid` rather than after,
because an observer that throws goes through `emit` — item 2 — and a
charged card must not turn into a caller waiting forever. Each of them is a
line that has to be remembered, and nothing asks for it.

**On Cubit.** The same package's other controller has no events: a method
takes arguments and returns a value, so the awaiting half of this item is
answered by the language. `emit(Paying())`, `await _api.pay(order)`,
`emit(Paid(receipt))`, `return receipt`, and the caller has its receipt.

The other half is not answered at all. Nothing owns the operation, so two
calls for one order run their bodies side by side and charge the card
twice, and their `emit`s interleave with no transformer to reach for —
item 1. Getting to what this item asked for means writing both halves by
hand, the in-flight map from the bloc above and a one-at-a-time chain of
futures of your own:

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
    try {
      emit(Paying());
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
        cancellable: false,
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
same as the map and the chain above, with neither to write.

`cancellable: false` and `ctx.uncancellable` are the rest of it, and they
are not the same thing. The section **holds** a cancellation for the length
of the call — it does not refuse it: `cancel` and `close` are not turned
down, they are made to wait, and the moment the charge comes back the held
cancellation lands. Without `cancellable: false`, the `Paid` line would be an
ordinary write and would throw the held cancellation instead of recording
anything; the job would end `Cancelled(closed)` for a payment that really
happened. Moving the write inside the uncancellable section changes nothing
— the held cancellation still decides the outcome.

What makes the promise good is `cancellable: false` on the job: such a job
refuses every cancellation it may refuse, `close` included. With it the job
comes back `Done(receipt)`, the state ends at `Paid`, and the app finishes
closing after that.

What the flag does not refuse is a rule. A working type or a `keepWhile`
that stops matching cancels the job whatever the flag says, and the section
does not hold that one either: measured, the mark lands while the section
is still open. Nor does any of it spare the card. `_api.pay` has no cancel
token, so by the time a rule can break the call has already left; measured,
the section, a bare `await`, `ctx.wait`, and a `ctx.wait` inside the
section all end `Cancelled(rules: …)` with the card charged. The difference
is only in when the job stops waiting: through `ctx.wait` it stops at the
mark, and a snapshot taken there reads `charged=false` — the charge lands a
moment later all the same. None of the four reaches the `Paid` line either:
recording is a write, and a cancelled job cannot write. This payment has no
such rule, deliberately: `W` is the base `CheckoutState` and there is no
`keepWhile`, because a narrower working type would let a state change
cancel the payment in the gap between the charge and the line that records
it. So on the recipe as shown the section changes nothing — measured,
`cancel`, `close` and a forced clear all end `Done(receipt)` with it and
without it — and what it is for is the job that does not set the flag: it
holds the same cancellations for one step of the body instead of for the
whole job.

What the flag costs is the user's mind. It is refused from the moment the
job is added, its place in the queue included: `job.cancel()` on a payment
that has not started yet is turned down and the card is charged anyway —
measured `Done(receipt)` where the same job without the flag ends
`Cancelled(manual)` and charges nothing. A checkout that wants a Cancel
button before the charge leaves needs a second gate of its own, in front of
the call.

Two cancellations still reach a payment that has not started, because they
do not ask. `close()` takes it out of the queue as `Cancelled(closed)` and
`clear(force: true)` as `Cancelled(manual)`; neither charges anything.
That is where the handler's `Cancelled` branch comes from, together with a
call made after `close`, which never starts at all — and the reason it
reads `reason.name` rather than assuming which of them it was.

Once the job is running, nothing takes it: `close()` waits for the charge
and the app finishes closing after it.

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

And the split is not a choice. Apply item 1's cure and put the failure in
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
          // `join` does not abandon a sensor call: it waits for it and
          // gives up afterwards if the state stopped matching meanwhile.
          await ctx.join(_hw.zero);
          await ctx.join(_hw.sample);
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
place, and a new call in the body inherits it as far as it goes through the
context: `wait`, `join` or `uncancellable`, or an `await` with a read after
it.

One job is exempt from that re-evaluation, and it is the one doing the
writing. `ctx.emit` does not re-check the job it was called on, which is
why the last line above can write a `Calibrated` that its own `Ready` would
otherwise refuse: measured `Done(null)`. The rules catch up on the next
read through the context, so the same write followed by a single
`ctx.wait` ends `Cancelled(rules: is not Ready)` instead. A body whose last
act is a write out of its own working type is therefore ordinary; one that
goes on working after such a write is not.

The `sample()` already in flight still finishes, on both sides: no library
can abort a Dart future, and a sensor that has just lost its cable has
nothing left to be told. Where a device does take a cancel token, item 4
hands it one through `ctx.onCancel`. What stops here is everything after
the sample.

## 9. After cancellation the handler keeps running

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
the one behind it, the same chain item 7's cubit had to write inline:

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
        await _wire.protect(() async {
          // Checked inside the turn, not before it. Waiting for the lock
          // is a second place to go stale, and the lock calls what it is
          // holding whether or not that handler still exists.
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

That does it. The same chunks land, `[0, 1, 100, 101, …]`, and now one at a
time: `[write 0 start, write 0 end, write 1 start, write 1 end, write 100
start, write 100 end, …]`.

The check moved inside the turn because the lock added a second place to
go stale, and the first version of this recipe missed it. A handler that
reaches `protect` while another write holds the wire is parked in the
chain; cancel it there, and the chain still calls what it is holding when
its turn comes. Measured on the version that checks before the lock: three
flashes started in a row put `[0, 100, 200, 201]` on the wire, a chunk of
the middle image going to the device although that flash was replaced
before it ever reached the radio; and a write can start after `close()` has
already returned.

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
([#2961](https://github.com/felangel/bloc/issues/2961)) — see item 3.

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
            // What ends the loop is `join`: the write it waits for
            // lands, and then it throws the job's Cancelled. The flash
            // that replaces this one is not started until the whole body
            // has come back.
            await ctx.join(() => _ble.write(chunk));
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
otherwise be fire-and-forget goes through one of two members. Work with an
outcome of its own goes through `ctx.run(child)`, a child job the parent
waits for; work with none — a metric, a best-effort stop — goes through
`ctx.unattended`, which the parent does not wait for but whose failure it
still hears.

## 10. A cancelled operation still brings back a resource

An audio editing screen draws the waveform of the selected clip. The
decoder allocates a native PCM buffer, the controller samples the waveform
out of it and hands the buffer back. The user picks another clip while the
first buffer is still being built. The first waveform is not wanted any
more; giving the memory back is not optional. The two decodes are
independent — separate buffers, and starting the second does not spoil the
first; a decoder that forbids the overlap is item 9's problem, not this one.

**On bloc.** `restartable()` cancels the old handler's emitter, and
`await _decoder.open(...)` goes on regardless. Item 9's line does its job
and, in doing it, loses the buffer.

```dart
class PreviewBloc extends Bloc<OpenPreview, PreviewState> {
  final Decoder _decoder;

  PreviewBloc(this._decoder) : super(const NoPreview()) {
    on<OpenPreview>((e, emit) async {
      final buffer = await _decoder.open(e.clip);
      // Right about the screen, wrong about the buffer: the decoder has
      // answered a handler nobody listens to any more, and the native
      // memory it allocated is never handed back.
      if (emit.isDone) return;
      emit(Preview(buffer.waveform()));
      await buffer.release();
    }, transformer: restartable());
  }
}
```

The emitter has no public place to put the release: its disposables serve
the `onEach` and `forEach` subscriptions, not a resource of yours. But the
answer is short, and it works — acquire, then bracket the use, with the
staleness check moved inside the bracket:

```dart
class GuardedPreviewBloc extends Bloc<OpenPreview, PreviewState> {
  final Decoder _decoder;

  GuardedPreviewBloc(this._decoder) : super(const NoPreview()) {
    on<OpenPreview>((e, emit) async {
      final buffer = await _decoder.open(e.clip);
      try {
        if (emit.isDone) return;
        emit(Preview(buffer.waveform()));
      } finally {
        await buffer.release();
      }
    }, transformer: restartable());
  }
}
```

Both buffers come back — `stale releases 1, current releases 1`, where the
version above leaves `stale releases 0`. What it costs is where the
obligation lives: in the body, which goes on waiting after its emitter has
been cancelled and is the only thing that knows a buffer exists. Move the
check one line up, in front of the `try`, and the leak is back; take a
second resource and the brackets nest; hand the buffer out to the state and
the ownership question starts over. None of that is a cost of event classes
or of style — the handler simply is the only holder of the obligation.

And the state cannot be used to check the work. Both runs above end at
`Preview(2)`: the right state with a leak and the right state without one
are the same state.

**On solo.** The obligation is attached to the acquisition, not to the
body.

```dart
final class PreviewController extends Solo<PreviewState> {
  final Decoder _decoder;

  PreviewController(this._decoder) : super(const NoPreview());

  Job<void> open(Clip clip) => run<PreviewState, void>(
        key: 'preview',
        policy: Policy.restart,
        (ctx) async {
          // One registration, two windows: a buffer that arrives after
          // this job is over goes straight to the disposer, and one that
          // arrives in time is released after the body.
          final buffer = await ctx.wait(
            () => _decoder.open(clip),
            dispose: (buffer) => buffer.release(),
          );
          ctx.emit(Preview(buffer.waveform()));
        },
      );
}
```

`ctx.wait` can end the cancelled job without waiting for the decoder — the
restarted preview does not sit behind a decode nobody wants — and the value
that arrives afterwards still goes to the callback registered for it. The
same callback covers the ordinary path: the buffer that arrives in time is
released when the body is done with it. There is no `isDone` to remember
and no branch for the late value to write.

`dispose` and not `discard` is the choice here, and the two differ: a
`discard` runs only when the job does not hand its value out, and a job
that succeeds here hands out nothing but a state. The buffer is a temporary
of the body either way, so it has to be released on the successful path
too, which is what `dispose` means.

The decoder sees the same thing either way — `[open 1, open 2, ready 2,
sample 2, release 2, ready 1, release 1]`, the stale buffer handed back
last — and the state ends at `Preview(2)`.

The boundary is worth naming as plainly as the guarantee. `close()` does
not wait for a resource that only appears after the job is already over. In
the measured run the controller is closed first — `closed true`, with the
stale job long since `Cancelled(manual)` — and the buffer arrives after
that and is released then: late, but released. What the registration
promises is that the release happens, not that it happens before `close()`
returns. An operation that may not be left in flight at all is what
`ctx.join` is for, and that is item 9.
