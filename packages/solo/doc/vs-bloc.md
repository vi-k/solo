# solo and bloc, side by side

This guide compares [solo](https://pub.dev/packages/solo) with `Bloc` and
`Cubit` through ten controller scenarios. Each section states the required
behavior, starts from the code that behavior invites, says what that code
actually does, and only then shows the implementations that meet it — bloc's
and solo's — with what the library handles and what remains application code.

A first attempt here is not a strawman: it is the version the API's own
vocabulary suggests, and the states and traces quoted under it are what running
that code produces. Reading it before the answer is the point of the section; a
reader who already knows the trap can skip to `### Bloc` and `### Solo`.

`Bloc` processes events registered with `on<E>`. A transformer determines how
events in that registration are scheduled. `Cubit` exposes methods that update
state directly; it does not provide an event queue.

In `solo`, a controller method normally creates a `Job<T>` and adds it to the
controller's queue. Root jobs run one at a time. The caller can await
`job.value` for a value or exception, or `job.done` for a `Done`, `Failed` or
`Cancelled` outcome. Queue policies apply to individual submissions.

The examples introduce other solo APIs where they are used. The
[README](https://github.com/vi-k/solo/blob/main/packages/solo/README.md)
provides a complete introduction and the detailed contracts.

Examples use separate application models: a `Ready` state in the player example
is not the sensor's `Ready`. Supporting state classes, event classes and fake
APIs are not shown here: they live with the code that extracts these examples
from the document, `tool/doc_snippets.py` in the repository. The examples were
checked with bloc 9.2.1, bloc_concurrency 0.3.0 and the local solo 0.2.0
source. Traces describe those runs, not timing guarantees for arbitrary
devices.

## Correspondences

The main API correspondences, for a reader who knows bloc:

| bloc | solo |
| --- | --- |
| `Bloc<E, S>`, `Cubit<S>` | `Solo<S>`, `SoloListenable<S>` |
| Event class, `on<E>`, `add(E())` | Method returning `Job<T>` |
| `EventTransformer` | `Policy` on a job submission |
| `emit(next)` | `ctx.emit(next)` |
| `if (emit.isDone) return;` | Cancellation checkpoints such as `ctx.wait` and `ctx.check` |
| `emit.onEach`, `emit.forEach` | `ctx.each(stream, onData)` |
| `state`, `stream` | `currentState`, `stream` |
| `BlocObserver` | `SoloObserver` |
| `BlocBuilder`, `BlocSelector` | `ValueListenableBuilder`; selection is application code |
| `BlocListener` for an operation's result | Await that operation's `job.done` |
| `BlocProvider` | Your chosen ownership or dependency mechanism |
| `close()` | `close()` |
| `blocTest` | `test` and an awaited job outcome |

`sequential`, `droppable` and `restartable` correspond to `Policy.sequential`,
`Policy.droppable` and `Policy.restart`. `Policy.replace` removes queued work
while leaving the running job alone. There is no concurrent root-job policy;
use children or separate controllers for independent concurrent work.

## 1. Ordering updates to shared state

A notes controller uploads a note and refreshes the list from the server. If
refresh starts before upload completes, its response can contain the old list.
Publishing that response after upload would remove the new note from local
state, even if both handlers read the latest local state. The requirement is to
serialize the complete operations, including I/O.

### The first attempt

An event type per command, a handler per event, and on both of them the
transformer whose name is the requirement:

```dart
class SplitNotesBloc extends Bloc<NotesEvent, NotesState> {
  final Api _api;

  SplitNotesBloc(this._api) : super(const NotesState()) {
    on<UploadNote>((e, emit) async {
      emit(state.copyWith(uploading: true));
      await _api.upload(e.note);
      emit(
        state.copyWith(notes: [...state.notes, e.note], uploading: false),
      );
    }, transformer: sequential());
    on<RefreshList>((e, emit) async {
      final serverNotes = await _api.list();
      emit(state.copyWith(notes: serverNotes));
    }, transformer: sequential());
  }
}
```

The final state is `NotesState([n0], uploading: false)`: the uploaded note is
not in it. The order of execution says why. Below are the server's own entries
and every publication, each with the event that made it; the local list starts
empty because nothing has been read yet:

```text
UploadNote emits [], uploading: true
upload n1 starts
list reads [n0]
server receives n1 and holds [n0, n1]
UploadNote emits [n1], uploading: false
RefreshList emits [n0]
```

Refresh reads the server on line three, before the upload reaches it on line
four, and publishes that answer on line six, after the upload has published its
own. The response is older than the state it replaces, and no reading of the
local `state` inside either handler can tell: the obsolete list is in the
response, not in the state.

A transformer schedules the events of its own registration, and here there are
two registrations, so the two handlers still run at the same time. The
[per-handler ordering discussion](https://github.com/felangel/bloc/issues/2790)
describes that distinction.

The same two registrations have another way to lose the note, and this one
involves no transformer at all. Written in a single line,
`emit(state.copyWith(notes: await _api.list()))` evaluates the receiver `state`
before it awaits the argument, so it publishes a state assembled before the
upload. That variant ends at `NotesState([n0], uploading: true)` and overwrites
the upload flag as well.

### The second attempt

The missing half is one registration for both commands. By itself it is not
enough either, because the default scheduling is concurrent:

```dart
class ConcurrentNotesBloc extends Bloc<NotesEvent, NotesState> {
  final Api _api;

  ConcurrentNotesBloc(this._api) : super(const NotesState()) {
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
    });
  }
}
```

The state is `NotesState([n0], uploading: false)` again, from an order
identical to the one above, line for line. The two attempts fail for different
reasons — two queues there, no queue here — but the result does not tell them
apart.

### Bloc

Both halves together: one registration for the common supertype, with
`sequential()` on it:

```dart
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final Api _api;

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

The final state is `NotesState([n0, n1], uploading: false)`, and one line of
the order has moved:

```text
UploadNote emits [], uploading: true
upload n1 starts
server receives n1 and holds [n0, n1]
UploadNote emits [n1], uploading: false
list reads [n0, n1]
RefreshList emits [n0, n1]
```

Refresh now reads a server that already holds the note, so the answer it
publishes is not obsolete. The ordering is what makes the response current;
checking the local state on arrival would not have.

One registration also means one transformer for every command handled there, so
each operation that needs this ordering has to be handled in it.

### Solo

Methods submitted to the same controller share its root-job queue:

```dart
final class NotesController extends Solo<NotesState> {
  final Api _api;

  NotesController(this._api) : super(const NotesState());

  Job<void> upload(Note note) => run<NotesState, void>(
        key: 'upload',
        (ctx) async {
          ctx.emit(ctx.state.copyWith(uploading: true));
          await ctx.join(() => _api.upload(note));
          final merged = [...ctx.state.notes, note];
          ctx.emit(ctx.state.copyWith(notes: merged, uploading: false));
        },
      );

  Job<void> refresh() => run<NotesState, void>(
        key: 'refresh',
        (ctx) async {
          final serverNotes = await ctx.wait(_api.list);
          ctx.emit(ctx.state.copyWith(notes: serverNotes));
        },
      );
}
```

`ctx.join(action)` calls the operation and waits for it. After a successful
response it checks cancellation before returning the result. Upload uses `join`
so the next root job cannot read the server while the upload is still in
progress. Refresh uses `ctx.wait`, which can stop waiting on cancellation
because this example allows its read result to be abandoned.

The final state is also `NotesState([n0, n1], uploading: false)`, from the same
order as the bloc funnel above — `list reads [n0, n1]` after
`server receives n1` — with job keys where that run has event types.

There is nothing to remember here about transformers or the order events are
processed in: there is no transformer to pass and no scheduling to choose. The
root jobs of a controller run one at a time, in the order they were added, and
that is the only way they run. Adding another queued method preserves the
ordering, because the queue is one per controller rather than one per command;
no arrangement of the methods can give two of them a queue each. This guarantee
covers root jobs; child jobs can run inside a parent, and independent device
changes have a separate path described in section 8.

Use context waiting methods inside job bodies to check cancellation and state
rules. A plain `await` still keeps the body and queue occupied but does not
react to cancellation. Work started without awaiting it can outlive the job; it
must not be assumed to finish before `close()`.

## 2. An observer fails during a state update

A recorder starts its native recording, publishes `Recording`, then arms a
level meter. A telemetry observer throws while processing the update. The
recorder operation should finish independently of telemetry reporting.

### The first attempt

An observer that reports every change, and a controller that keeps a local
journal of them. Both are written the way the hooks invite, calling `super`
first:

```dart
class RecorderBloc extends Bloc<StartRecording, RecorderState> {
  final Recorder _recorder;
  final Journal _journal;

  RecorderBloc(this._recorder, this._journal) : super(const Idle()) {
    on<StartRecording>((e, emit) async {
      await _recorder.start();
      emit(const Recording());
      _recorder.armMeter();
    });
  }

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
    _telemetry.send(change.nextState);
  }
}
```

In this run the device starts, but the state remains `Idle`. The level meter is
never armed. The local journal is empty too, and not through an unlucky line
order: `onChange`'s own documentation asks for `super.onChange` to be called
first, which puts the global observer ahead of the controller's own note.
Writing that note before `super` saves the journal — it then holds
`[Recording]` — and saves nothing else: the state is still `Idle` and the meter
still unarmed. The handler reports `telemetry unavailable`, and the same
observer failure in a Cubit method reaches the method's caller.

Both `Bloc` and `Cubit` publish through `BlocBase.emit`. It calls `onChange`
before updating the state, and an exception from that call is passed to
`onError` and rethrown — into the handler that was publishing. The reporting an
observer exists for is therefore on the same path as the operation it reports
on.

### Bloc and Cubit

Catch telemetry errors within the observer, so that they cannot interrupt the
update:

```dart
class GuardedTelemetryObserver extends BlocObserver {
  final Telemetry _telemetry;
  final Log _fallback;

  GuardedTelemetryObserver(this._telemetry, this._fallback);

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    try {
      _telemetry.send(change.nextState);
    } on Object catch (error, stackTrace) {
      _fallback.write(error, stackTrace);
    }
  }
}
```

The guarded run reaches `Recording`, records `[native start, arm meter]` and
writes `[Recording]` to the journal. The fallback logger receives the telemetry
error. This approach works when every relevant observation callback handles its
failures and its fallback does not throw.

`onError` is not a second place to put that guard. `emit` catches the
exception, hands it to `onError` and rethrows it, so an override there reports
the failure without preventing it. With `onError` overridden and the observer
still throwing, the run ends at `Idle` with the meter unarmed, exactly as the
unguarded one did, and the failure is reported twice: once by `emit`, once by
the handler it broke.

### Solo

The observer and controller hooks are invoked independently. Each hook's
exception is reported to the current Dart zone:

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

  @override
  void onChange(SoloTransition<RecorderState> transition) =>
      _journal.note('${transition.current}');
}

final class TelemetryObserver extends SoloObserver {
  final Telemetry _telemetry;

  TelemetryObserver(this._telemetry);

  @override
  void onChange(SoloBase<Object> solo, SoloTransition<Object> transition) =>
      _telemetry.send(transition.current);
}
```

`SoloObserver` receives `SoloBase<Object>` because it observes controllers with
different state types. The controller's own hook uses its specific state type.

With the throwing observer, the run still reaches `Recording`, arms the meter,
records `[Recording]` locally and finishes with `Done(null)`: the failing hook
changes neither the job's outcome nor the queue. The telemetry error goes to
`Zone.current.handleUncaughtError` — to whatever the application already does
with uncaught asynchronous errors, and nowhere else. Left unhandled there it
can still terminate the application: hook isolation keeps the operation's
control flow, it does not take over the reporting.

## 3. Closing and cancelling in-flight work

A user sends a chat message and leaves the screen before the reply arrives. The
controller must prevent the old operation from updating a closed screen or
scheduling follow-up work after closure: the user never saw the reply, and
marking it read would tell the server that they did.

### The first attempt

The screen is gone and the controller is closed, so the handler is written as
though closing had ended it:

```dart
class UnguardedChatBloc extends Bloc<ChatEvent, ChatState> {
  final Api _api;

  UnguardedChatBloc(this._api) : super(const ChatState()) {
    on<SendMessage>((e, emit) async {
      final reply = await _api.send(e.text);
      emit(state.withReply(reply));
      add(const MarkReplyRead());
    }, transformer: sequential());
    on<MarkReplyRead>(
      (e, emit) => _api.markRead(),
      transformer: sequential(),
    );
  }
}
```

With `sequential()`, `close()` waits for the API call still in flight, and the
state after it is `ChatState(reply to hi)`: the reply was published into a
controller that was already closing. The follow-up `add` then throws
`Bad state: Cannot add new events after calling close`, and that error arrives
in the zone while `close()` is still being awaited, not at the caller of the
handler. No read is reported to the server — but only because the `add` that
would have reported it is the call that threw. Half the requirement holds by
the accident that broke the other half.

Closing behavior depends on the transformer in these versions. With
`sequential()`, `close()` waits for the running handler, which can still emit
while closure is pending. With the default transformer, `concurrent`,
`droppable` or `restartable`, `close()` returns before the body finishes and
the cancelled emitter ignores subsequent writes. Neither case interrupts the
API call or the rest of the handler body.

### Bloc

This sequential handler checks closure after its await:

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final Api _api;

  ChatBloc(this._api) : super(const ChatState()) {
    on<SendMessage>((e, emit) async {
      final reply = await _api.send(e.text);
      if (isClosed) return;
      emit(state.withReply(reply));
      add(const MarkReplyRead());
    }, transformer: sequential());
    on<MarkReplyRead>(
      (e, emit) => _api.markRead(),
      transformer: sequential(),
    );
  }
}
```

The guard prevents both the reply update and the `MarkReplyRead` event. Closing
still waits for the API call and handler to return. The separate
`MarkReplyRead` registration is safe for this example because it does not write
shared state; otherwise section 1's ordering concern would apply.

`add` after close throws `StateError`, so callers that can submit late events
need their own handling. A Cubit method also continues after closure, but its
direct `emit` then throws rather than using a cancelled handler emitter.

Another case is an unawaited future that emits after its handler completed
normally, while the Bloc is still open. This triggers a debug assertion; with
assertions disabled, the late write changes state. The
[completed-handler issue](https://github.com/felangel/bloc/issues/2961)
discusses this lifetime constraint. Cancellation support is also discussed in
[the async-operation proposal](https://github.com/felangel/bloc/issues/3069).

### Solo

`close()` stops accepting jobs, cancels queued jobs, requests cancellation of
the running job and waits for its completion, including cleanup:

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
  await chat.close();
  chat.send('bye'); // a job already finished with Cancelled(closed)
}
```

In this body, `ctx.wait` throws `Cancelled` when closing cancels the job. The
reply update and `markReplyRead()` call are not reached. That method would
submit a separate root job through the controller's `run`; it is not a child of
`send`.

With a plain await instead, closing would wait for the API response. The later
`ctx.emit` would still reject the cancelled job. A captured context used after
job completion throws `StateError` in both debug and release builds. Calls made
after closure return jobs already completed with `Cancelled(closed)`, so the
call site needs no `isClosed` guard.

### Returning from Loading after cancellation

Cancellation can also happen while the controller remains open. Consider a
refresh indicator with two states, `Initial` and `Loading`. A `StartRefresh`
event begins work; `CancelRefresh` cancels that handler through the same
`restartable()` registration. This example tracks only whether refresh is
active; the API returns no data to display.

In Bloc, putting the reset in the old handler's `finally` is insufficient:

```dart
class RefreshBloc extends Bloc<RefreshEvent, RefreshState> {
  final RefreshApi _api;

  RefreshBloc(this._api) : super(const Initial()) {
    on<RefreshEvent>((event, emit) async {
      if (event is CancelRefresh) return;
      emit(const Loading());
      try {
        await _api.refresh();
      } finally {
        emit(const Initial());
      }
    }, transformer: restartable());
  }
}
```

After `StartRefresh`, state is `Loading`. `CancelRefresh` replaces that handler
but publishes no new state. The API future continues running. When it
eventually completes, `finally` calls the old, cancelled emitter, which ignores
`Initial`. The state therefore remains `Loading` even after the API call ends.
Cancellation itself did not throw into the old body.

The Bloc solution is to publish the reset from the active cancellation handler.
Replace the `CancelRefresh` branch with:

```dart
if (event is CancelRefresh) {
  emit(const Initial());
  return;
}
```

Now state becomes `Initial` when the cancel event is handled. The old handler's
later emit is still ignored and cannot overwrite a newer refresh. With
`restartable`, all event types in this registration can replace the current
handler; a separate `on<CancelRefresh>` registration would not cancel
`StartRefresh` by itself.

In solo, attach the reset to the operation's final outcome:

```dart
final class RefreshController extends Solo<RefreshState> {
  final RefreshApi _api;

  RefreshController(this._api) : super(const Initial());

  Job<void> refresh() => run<RefreshState, void>(
        key: 'refresh',
        policy: Policy.restart,
        onError: (state, error, stackTrace) => const Initial(),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          await ctx.wait(_api.refresh);
          ctx.emit(const Initial());
        },
      );
}
```

Call `controller.refresh()` and retain its job; `await job.cancel()` waits for
cancellation and cleanup. `ctx.wait` ends the wait for the API, and `onCancel`
returns `Initial` before the queue proceeds. A successful refresh publishes
`Initial` from the body; `onError` resets the indicator on failure while the
job still reports `Failed`.

The timing differs: Bloc's cancel-event handler updates state when it runs,
while solo's state handler runs after the cancelled job's cleanup. Neither
example stops the API operation itself. If an independent external state makes
the solo job invalid, its final state handlers are skipped; section 8 explains
external state and the README describes handler rules.

## 4. Restarting one operation within a shared queue

A player must run `play`, `pause` and `seek` one at a time. During a slider
drag, queued seek positions become obsolete and an active seek should stop
before its replacement starts. Play and pause retain their order. The player
API in this example accepts a token and returns when cancelled.

### The first attempt

One registration per command, and on the one that must be replaceable, the
transformer named after the requirement:

```dart
class SplitPlayerBloc extends Bloc<PlayerCommand, PlayerState> {
  final Player _player;

  SplitPlayerBloc(this._player) : super(const PlayerState()) {
    on<Play>((e, emit) => _player.play(), transformer: sequential());
    on<Pause>((e, emit) => _player.pause(), transformer: sequential());
    on<Seek>((e, emit) async {
      await _player.seek(e.position);
      emit(PlayerState(position: e.position));
    }, transformer: restartable());
  }
}
```

The device trace is `[play start, seek 1 start, seek 2 start, pause start, seek
3 start, play end, pause end, seek 1 end, seek 2 end, seek 3 end]`, and the
final state is `PlayerState(3ms)` — the position the user asked for. The state
is right and the device is not.

Two things went wrong at once. A transformer orders the events of its own
registration, so pause no longer waits for play. And `restartable()` cancels
the replaced handler's emitter without stopping the native call it is awaiting:
all three seeks ran on the device, the third of them after pause. Only the last
emit reached the state, which is why the state alone shows none of this.

### Bloc

To keep all commands serialized, this implementation uses one `sequential()`
registration and tracks the latest seek and active token:

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
    if (event is Seek) {
      _newestSeek = event.position;
      _seeking?.cancel();
    }
    super.onEvent(event);
  }
}
```

For positions `1, 2, 3` queued together, the device receives
`[play, seek 3, pause]`. If seek 1 is already active when seek 3 arrives, the
trace is `[seek 1 start, seek 1 stopped, seek 3 start, seek 3 end]`. `onEvent`
receives the new request synchronously and cancels the token; the sequential
handler waits for the player to return before proceeding.

Comparing position values is insufficient when the drag repeats a value. Input
`1, 2, 1` produces `[play, seek 1, seek 1, pause]`. Identifying the latest
event with a generation counter instead of its position fixes that case.

The application maintains the latest-request identity, active token and
post-await check. Each command requiring different replacement behavior needs
corresponding logic within the shared handler. `add` does not return the
outcome of a skipped or interrupted seek.

### Solo

Queue policy belongs to each job submission. The fragment shows pause and seek;
play follows the same sequential pattern as pause. `Ready` is the working state
type accepted by these player jobs:

```dart
enum PlayerKey { play, pause, seek }

final class PlayerController extends Solo<PlayerState> {
  final Player _player;

  PlayerController(this._player) : super(Ready());

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
          await ctx.join(() => _player.seek(position, cancelToken: token));
          ctx.emit(ctx.state.copyWith(position: position));
        },
      );
}
```

`Policy.restart` removes cancellable queued seeks with the same key and
requests cancellation of the active seek. `ctx.onCancel` forwards that request
to the player immediately. `ctx.join` waits for the operation to return before
the current job can finish and the replacement can start. If the operation
fails after cancellation, its error reaches the body; the job's outcome still
remains cancelled.

The observed traces match the successful Bloc cases above. Pause and play
remain in the same queue with their default sequential policy. The token is
local to the seek body, and callers can inspect each seek's outcome, including
`Cancelled(manual)` for a replaced request.

## 5. Typed methods with queued execution

A map exposes `moveTo` and `setZoom`. Callers need typed arguments, and rapid
drag updates should not make the map finish at an older position.

### The first attempt

Cubit supports methods that return futures directly, so the typed call
interface costs nothing:

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

These methods do not serialize calls. With unequal native-call durations, the
trace is `[moveTo 1 start, moveTo 2 start, moveTo 3 start, moveTo 3 end, moveTo
2 end, moveTo 1 end]`. State ends at `MapState(1, z1)`, reflecting the oldest
request because it finished last.

A future chain can serialize calls, with additional tracking to discard
obsolete requests. The application must also decide how closure waits for or
invalidates that chain; Cubit does not manage it automatically.

### Bloc with function events

An event can itself be a function. One sequential registration runs those
functions, while public methods provide the typed call interface:

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

The calls now run in order and end at `MapState(3, z4)`. This provides typed
methods and shared ordering without a separate event class per method. All
commands still use one transformer, and the shown methods return `void`.
Returning a result requires an additional mechanism, as in section 7.

### Solo

Each method returns a job and specifies its replacement policy:

```dart
enum MapKey { moveTo, setZoom }

final class MapController extends Solo<MapState> {
  final MapApi _map;

  MapController(this._map) : super(const MapState());

  Job<void> moveTo(Point<double> point) => run<MapState, void>(
        key: MapKey.moveTo,
        policy: Policy.restart,
        (ctx) async {
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

The restart trace is
`[moveTo 1 start, moveTo 1 stopped, moveTo 3 start, moveTo 3 end]`. The middle
request does not start; the first stops before the latest one begins. Both the
map and `MapState(3, z4)` reflect the latest request. Callers may await
`job.value` or `job.done` to wait for the operation, or omit waiting. The
returned job itself is not a Future; its error-handling rules are described in
the README.

## 6. Removing selected pending work

A BLE screen queues connect, battery and signal reads, rename and disconnect.
When the screen closes, pending reads should be discarded, while the requested
rename must still complete before disconnect.

### The first attempt

One `sequential()` registration orders all device commands. Its pending events
cannot be enumerated or removed through the Bloc API, so the handler has to
check whether a read is still relevant, and a leaving flag is the obvious thing
to check: the screen sets it when it goes and clears it when it comes back.

```dart
class FlagDeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  final Ble _ble;
  var _leaving = false;

  FlagDeviceBloc(this._ble) : super(const DeviceState()) {
    on<DeviceEvent>((e, emit) async {
      switch (e) {
        case Connect():
          await _ble.connect();
          emit(state.copyWith(online: true));
        case ReadBattery():
          if (_leaving) return;
          emit(state.copyWith(battery: await _ble.battery()));
        case ReadSignal():
          if (_leaving) return;
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
    if (event is Disconnect) _leaving = true;
    if (event is Connect) _leaving = false;
    super.onEvent(event);
  }
}
```

On the way out the flag works: the device receives
`[connect, rename kitchen, disconnect]`, and the queued reads are skipped. What
it cannot express is a screen that comes back before the old events drain.
Adding the new `Connect` clears the flag while the previous screen's read is
still queued, so that read becomes valid again and runs:
`[connect, battery, disconnect, connect, battery]`. The battery it reports
belongs to the screen that is gone.

### Bloc

A flag says where the screen is now; what the queue needs to know is which
screen each event belongs to. This version records the screen generation on
each event:

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
    if (event is Disconnect) _screen++;
    _stampOf[event] = _screen;
    super.onEvent(event);
  }
}
```

The device receives `[connect, rename kitchen, disconnect]`. If the screen
reopens before pending work drains, the old read is skipped and the new one
runs: `[connect, disconnect, connect, battery]`.

The generation records are application state associated with the queue. Events
still reach the handler, which must check each discardable command. The
`Expando` scheme also requires distinct event objects. Reusing a canonical
const event overwrites its earlier stamp; the sequence then includes the stale
read: `[connect, battery, disconnect, connect, battery]`. `add` provides no
result indicating that a read was skipped.

### Solo

The controller can remove matching jobs directly from its queue:

```dart
enum DeviceKey { connect, readBattery, readSignal, rename, disconnect }

final class DeviceController extends Solo<DeviceState> {
  final Ble _ble;

  DeviceController(this._ble) : super(const Offline());

  Job<void> disconnect() {
    queue.removeWhere(
      (job) =>
          job.key == DeviceKey.readBattery || job.key == DeviceKey.readSignal,
    );
    return run<Connected, void>(
      key: DeviceKey.disconnect,
      (ctx) async {
        await ctx.join(_ble.disconnect);
        ctx.emit(const Offline());
      },
    );
  }
}
```

The hardware trace is the same, but the removal happens when `disconnect` is
called. The removed read jobs complete with `Cancelled(manual)`; their callers
can observe that result. Rename stays queued, and disconnect runs after it.
`removeWhere` does not affect an already running connect. Jobs marked
`cancellable: false` require `force: true` for queue removal.

## 7. Awaiting a particular request

A checkout can be called by both a Pay button and a platform request. The
platform handler must return the result of its order. Concurrent requests for
the same order should share one payment; distinct orders should execute
sequentially.

Watching `Paid` through a `BlocListener` can serve a screen's navigation, but a
function answering a platform request needs a result associated with that
request. `Bloc.add` returns `void`; the
[awaiting-events discussion](https://github.com/felangel/bloc/issues/1556)
covers this use case.

### The first attempt

The result has to travel on the event itself, as a completer the caller awaits.
`droppable()` reads like the policy for sharing one payment: while a charge is
running, another request for it should not start a second one.

```dart
class Pay extends CheckoutEvent {
  final Order order;
  final Completer<Receipt> result;

  Pay(this.order) : result = Completer<Receipt>();
}

class DroppableCheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  final Api _api;

  DroppableCheckoutBloc(this._api) : super(Cart()) {
    on<Pay>((e, emit) async {
      emit(Paying());
      final receipt = await _api.pay(e.order);
      e.result.complete(receipt);
      emit(Paid(receipt));
    }, transformer: droppable());
  }

  Future<Receipt> pay(Order order) {
    final event = Pay(order);
    add(event);
    return event.result.future;
  }
}
```

Three requests make one API call, and one caller in three is answered:
`[Receipt(for A), never answered, never answered]`. The other two are still
waiting after everything else has finished, and would wait for as long as the
process lives — `droppable()` dropped their events, and a dropped event's
completer is completed by nobody.

The second of those two shows what the policy actually does: order B is a
different payment, and it was dropped as well. `droppable()` drops what arrives
while a handler is running, not what duplicates it.

### Bloc

The event carries its completer as above. What the sharing needs is a map of
the payments in flight, so that a caller of an order already running is given
the completer of that payment instead of a dropped event of its own:

```dart
class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  final Api _api;
  final _inFlight = <String, Completer<Receipt>>{};

  CheckoutBloc(this._api) : super(Cart()) {
    on<Pay>((e, emit) async {
      try {
        emit(Paying());
        final receipt = await _api.pay(e.order);
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
    }, transformer: sequential());
  }

  Future<Receipt> pay(Order order) {
    final running = _inFlight[order.id];
    if (running != null) return running.future;
    final event = Pay(order);
    _inFlight[order.id] = event.result;
    try {
      add(event);
    } on Object {
      _inFlight.remove(order.id);
      rethrow;
    }
    return event.result.future;
  }
}
```

`await bloc.pay(order)` now returns a receipt. Three calls for two orders make
two API calls, and both callers for one order receive its receipt.

The completer must finish on every path. The `add` catch removes the map entry
when a closed Bloc refuses the event. `isCompleted` prevents double completion
if an emit throws after the receipt has been delivered. Completing the receipt
before publishing `Paid` prevents an observer error from replacing an already
obtained receipt. The transformer stays `sequential()`: the map is what shares
a payment, and what reaches the queue after it are distinct orders, which
should run in order rather than drop one another.

### Cubit

A Cubit method can return a receipt directly, but overlapping calls are not
deduplicated or serialized automatically. This version adds an in-flight map
and a future chain:

```dart
class CheckoutCubit extends Cubit<CheckoutState> {
  final Api _api;
  final _inFlight = <String, Future<Receipt>>{};
  Future<void> _tail = Future.value();

  CheckoutCubit(this._api) : super(Cart());

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

It also makes two API calls for three requests covering two orders. Its closure
handling remains incomplete: Cubit does not wait for this custom chain. In the
case where closure happens during payment, the charge succeeds, but the later
`emit(Paid(...))` throws
`Bad state: Cannot emit new states after calling close`, so the caller receives
that error instead of the receipt. A production implementation must coordinate
closure with its payment chain and result delivery.

### Solo

Use the order identity as the key and return the job directly:

```dart
final class CheckoutController extends Solo<CheckoutState> {
  final Api _api;

  CheckoutController(this._api) : super(const Cart());

  Job<Receipt> pay(Order order) => run<CheckoutState, Receipt>(
        key: ('pay', order.id),
        policy: Policy.droppable,
        cancellable: false,
        (ctx) async {
          ctx.emit(const Paying());
          final receipt = await ctx.join(() => _api.pay(order));
          ctx.emit(Paid(receipt));
          return receipt;
        },
      );
}
```

The platform handler can inspect that job's outcome:

```dart
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

`Policy.droppable` returns the existing queued or running job for the same
order key. Both callers share its receipt, while another order creates another
job. The three requests again make two API calls.

`cancellable: false` protects the complete payment operation from ordinary
cancellation, including controller closure once it is running. `join` waits for
the API result, and the body publishes `Paid` before completing with the
receipt. `close()` waits for that completion. API failures still produce
`Failed`; a failure state can be supplied with `run(onError: ...)`.

This job accepts the base `CheckoutState` and has no `keepWhile` restriction.
State rules can cancel even a non-cancellable job, so a narrower type would
allow cancellation after a charge was sent but before it was recorded. No
waiting method can retract a charge from an API that provides no cancellation
mechanism.

`ctx.uncancellable` has a different purpose: it holds ordinary cancellation for
one step, then applies the request afterwards. It does not guarantee a
successful job outcome for a payment that completed during that step. It is
unnecessary for the non-cancellable job shown here.

The flag also refuses manual cancellation while the payment is queued. If users
must be able to cancel before charging starts, model that admission decision
separately. `close()` and `queue.clear(force: true)` can still discard a queued
payment without charging, and a submission after close also never starts. These
cases explain the platform handler's `Cancelled` branch.

Sharing an in-memory job only deduplicates concurrent calls to this controller.
Payment retries across process restarts or network failures also require an
idempotent payment API; neither example provides that.

## 8. Reacting to an independent external state change

A sensor reports a hardware failure while calibration is waiting for a sample.
The controller must reflect `Broken` promptly and prevent the calibration from
later publishing `Calibrated` over it.

### The first attempt

Bloc's direct `emit` is marked `@visibleForTesting` and documented for internal
use, so the listener adds a `HardwareFailed` event instead. One registration
for both events is what section 1 asks for, and it is what a reader who has
just learned that lesson writes:

```dart
class FunnelSensorBloc extends Bloc<SensorEvent, SensorState> {
  final Sensor _hw;

  FunnelSensorBloc(this._hw) : super(Ready()) {
    _hw.onError = (error) => add(HardwareFailed(error));
    on<SensorEvent>((e, emit) async {
      switch (e) {
        case HardwareFailed(:final error):
          emit(Broken(error));
        case Calibrate():
          if (state is! Ready) return;
          await _hw.zero();
          if (state is! Ready) return;
          await _hw.sample();
          if (state is! Ready) return;
          emit(Calibrated());
      }
    }, transformer: sequential());
  }
}
```

The published states are `[Calibrated, Broken(cable unplugged)]`. The cable was
already unplugged when `Calibrated` was published: the failure event waited its
turn behind the calibration it invalidates, and every check in that handler
read a state that nothing had been allowed to change yet. A screen watching
this controller reports success after the device has failed.

The ordering of section 1 and the promptness needed here pull in opposite
directions, and one registration cannot do both.

### Bloc

Give the failure its own registration, so that it does not wait behind
calibration:

```dart
class SensorBloc extends Bloc<SensorEvent, SensorState> {
  final Sensor _hw;

  SensorBloc(this._hw) : super(Ready()) {
    _hw.onError = (error) => add(HardwareFailed(error));
    on<HardwareFailed>((e, emit) => emit(Broken(e.error)));
    on<Calibrate>((e, emit) async {
      if (state is! Ready) return;
      await _hw.zero();
      if (state is! Ready) return;
      await _hw.sample();
      if (state is! Ready) return;
      emit(Calibrated());
    }, transformer: sequential());
  }
}
```

The run ends at `Broken(cable unplugged)` without publishing `Calibrated`.
Calibration checks state after each await because the failure event does not
cancel its handler or emitter; the checks are what the second registration
buys, not something it replaces.

Cubit can reflect the notification directly from a subclass method, but its
asynchronous operations still need equivalent validity checks.

### Solo

`externalSetState` is a protected method for reflecting an independent source's
already completed state change. The listener belongs inside the controller
subclass:

```dart
final class SensorController extends Solo<SensorState> {
  final Sensor _hw;

  SensorController(this._hw) : super(const Ready()) {
    _hw.onError = (error) => externalSetState(Broken(error));
  }

  Job<void> calibrate() => run<Ready, void>(
        key: 'calibrate',
        (ctx) async {
          await ctx.join(_hw.zero);
          await ctx.join(_hw.sample);
          ctx.emit(const Calibrated());
        },
      );
}
```

Queuing a normal job to publish `Broken` would delay the fact behind the
calibration that it invalidates. `externalSetState` updates state immediately
and checks running bodies against their rules. Here, `run<Ready, void>` permits
calibration only while state is `Ready`, so the external failure cancels it
with `Cancelled(rules: is not Ready)`.

This exception applies to facts such as an unplugged cable. A notification
asking the controller to perform future work should enqueue an ordinary job.
The source being a stream does not itself justify bypassing the queue. Stop the
hardware listener before closing either controller; the snippets show
registration, not application-specific listener teardown.

On the success path, the job may finish by emitting `Calibrated`, even though
that state is outside `Ready`. Its own emit is excluded from the rule check; a
later state checkpoint would cancel it. This allows a final transition while
requiring the working type to cover continued work.

The sensor call already in progress still finishes in both examples. `join`
waits for it before allowing another root job to start. A device with a
cancellation token can additionally be stopped through `ctx.onCancel`, as in
section 4. Final `onError` and `onCancel` state handlers, if supplied, are
disabled by an incompatible external update, so they do not overwrite `Broken`
during cleanup.

## 9. Finishing an in-flight write before restarting

A firmware upload writes BLE chunks sequentially. A replacement upload must
stop the old loop and wait for its current write before sending any new chunk.
This example's BLE API cannot abort an accepted write.

### The first attempt

`restartable()` is the policy the requirement names: a new upload replaces the
one running. The loop is written as though the replacement stopped it:

```dart
class UnguardedFirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  final Ble _ble;

  UnguardedFirmwareBloc(this._ble) : super(Idle()) {
    on<Flash>((e, emit) async {
      var written = 0;
      for (final chunk in e.chunks) {
        await _ble.write(chunk);
        emit(Flashing(++written, e.chunks.length));
      }
    }, transformer: restartable());
  }
}
```

The device receives `[0, 1, 100, 2, 101, 3, 102, 4, 103, 5, 104, 105]`: both
loops went on writing, and the two uploads interleave on the wire.
`restartable()` cancels the replaced handler's emitter, and a cancelled emitter
ignores writes — but the Dart body awaiting `_ble.write` is not interrupted by
that. The
[restartable-handler discussion](https://github.com/felangel/bloc/issues/3349)
describes why cancellation does not interrupt awaited futures.

### The second attempt

Since the body is not interrupted, it has to notice: `emit.isDone` is true once
the emitter has been cancelled.

```dart
class FirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  final Ble _ble;

  FirmwareBloc(this._ble) : super(Idle()) {
    on<Flash>((e, emit) async {
      var written = 0;
      for (final chunk in e.chunks) {
        await _ble.write(chunk);
        if (emit.isDone) return;
        emit(Flashing(++written, e.chunks.length));
      }
    }, transformer: restartable());
  }
}
```

The chunks now belong to one upload: a mid-upload restart writes
`[0, 1, 100, 101, …]`. The device still sees two writers, though. The
replacement handler starts while the old write is pending, and the trace is
`[write 0 start, write 0 end, write 1 start, write 100 start, write 1 end,
write 100 end, …]` — the check governs what is published, not what the wire is
doing.

### Bloc

A shared lock serializes the device calls:

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

The trace now orders each write's completion before the next start: `[write 0
start, write 0 end, write 1 start, write 1 end, write 100 start, write 100 end,
…]`.

Check `emit.isDone` inside the lock as well as after the write. An event may be
replaced while waiting for the lock; checking only before entry would let its
obsolete write start later. The lock orders device access, while the emitter
check stops obsolete handlers. Every operation using that device must follow
the same locking rule.

A separate `HardwareFailed` event that publishes `Broken` does not change this
emitter's `isDone`. In that scenario, additional state checks are still needed
to stop flashing and preserve `Broken`, as in section 8.

### Solo

The job occupies the controller's queue until its body and cleanup finish:

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
            await ctx.join(() => _ble.write(chunk));
            ctx.emit(Flashing(++written, chunks.length));
          }
        },
      );
}
```

`Policy.restart` requests cancellation and enqueues the replacement. `join`
waits for the current write; after a successful write it detects cancellation
and throws before the next iteration. The replacement starts after the old job
completes. The observed chunk sequence and non-overlap match the locked Bloc
implementation.

An external `Broken` state also cancels this job because it no longer matches
`NotBroken`. The failure run stops after `[0, 1, 2]` with
`Cancelled(rules: is not NotBroken)`. The check covers both replacement and
state invalidation.

If the upload starts child jobs through `ctx.run`, the parent also waits for
those children and their cleanup. Work intentionally allowed to outlive the job
can use `ctx.unattended`, whose errors are reported through the job's hooks; it
does not keep the queue occupied.

## 10. Releasing a resource returned after cancellation

An audio editor opens a native PCM buffer to draw a waveform. The user selects
a different clip while decoding is pending. The old waveform should be
discarded, but its buffer must still be released. These decoder calls may
overlap safely because their buffers are independent. A decoder requiring
serialized access needs section 9's waiting behavior instead.

### The first attempt

Checking `emit.isDone` before using the result prevents a stale waveform
update, and after section 9 that check is the reflex:

```dart
class PreviewBloc extends Bloc<OpenPreview, PreviewState> {
  final Decoder _decoder;

  PreviewBloc(this._decoder) : super(const NoPreview()) {
    on<OpenPreview>((e, emit) async {
      final buffer = await _decoder.open(e.clip);
      if (emit.isDone) return;
      emit(Preview(buffer.waveform()));
      await buffer.release();
    }, transformer: restartable());
  }
}
```

The state ends at `Preview(2)`, which is correct, and the stale buffer is
released zero times: the early return leaves it to the garbage collector, which
does not know how to release a native buffer. Nothing about the state says so.

### Bloc

Move the check inside a `try`/`finally` that owns the acquired buffer:

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

Both versions finish at `Preview(2)`. The first releases the current buffer
once and the stale buffer zero times; the guarded version releases each once.
The `finally` runs on the cancelled path too, which is the only reason the
stale buffer is released at all.

The handler continues waiting after emitter cancellation and releases the
buffer when it arrives. This is a working resource-management pattern; every
exit after acquisition must remain inside the `try` block. Additional resources
or ownership transfers need corresponding cleanup decisions. Cubit can use the
same pattern with an application-defined stale-request check, since it has no
handler emitter or `emit.isDone`.

### Solo

Register disposal on the call that acquires the buffer:

```dart
final class PreviewController extends Solo<PreviewState> {
  final Decoder _decoder;

  PreviewController(this._decoder) : super(const NoPreview());

  Job<void> open(Clip clip) => run<PreviewState, void>(
        key: 'preview',
        policy: Policy.restart,
        (ctx) async {
          final buffer = await ctx.wait(
            () => _decoder.open(clip),
            dispose: (buffer) => buffer.release(),
          );
          ctx.emit(Preview(buffer.waveform()));
        },
      );
}
```

`ctx.wait` can end the cancelled job before the decoder finishes. A late buffer
is still passed to `dispose`; one returned while the job is active is released
during its cleanup. The replacement job may therefore start without waiting for
the obsolete decode, while each buffer is released.

Use `dispose` here because the buffer is temporary, including on success.
`discard` is for a resource handed to the caller as the successful result; it
would not release this temporary buffer after a successful waveform update.

The guarded Bloc and solo runs both record
`[open 1, open 2, ready 2, sample 2, release 2, ready 1, release 1]` and end at
`Preview(2)`.

Late disposal can happen after the controller closes. In solo, `close()`
finishes before the obsolete buffer arrives; it is released when decoding
finally returns it. Use `join` when both the operation and its resource release
must finish before the queue or controller proceeds.
