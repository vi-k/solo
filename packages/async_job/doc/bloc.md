# async_job in a bloc app

A bloc handler can run its work as a job and keep everything else of bloc: the
events, the transformers, the states. Each section below takes one requirement
of an app on bloc 9 with `bloc_concurrency`, shows the answer of bloc alone and
then the same handler with a job in it, and says what the job takes off the
code and what stays with bloc. The code runs in pure Dart, and the states and
traces under it are what that code prints.

The sections, each a requirement where a job in the handler leaves the code
less to do:

- `close()` under `sequential()` waits for the call in flight —
  [Closing and cancelling in-flight work](#closing-and-cancelling-in-flight-work);
- a replacement upload must not write while the replaced one's write is
  pending —
  [Finishing an in-flight write before restarting](#finishing-an-in-flight-write-before-restarting);
- a buffer that arrives after its handler was replaced must still be released —
  [Releasing a resource returned after cancellation](#releasing-a-resource-returned-after-cancellation).

The scenarios where the queue of bloc is what has to change are listed in
[Where the queue is the problem](#where-the-queue-is-the-problem).

## The bridge

A job enters a handler as a stream: `emit.forEach` listens to it, and
cancelling the subscription cancels the job. `watch` is that stream, taken
apart in
[A stream that cancels the job](riverpod-and-bloc.md#a-stream-that-cancels-the-job):

```dart
/// The value of [job] as a stream. Cancelling the subscription cancels the
/// job.
///
/// Listen to it at once: the value is read in `onListen`, and a stream
/// nobody listens to leaves the job unwatched, its failure unobserved.
Stream<T> watch<T>(Job<T> job) {
  late final StreamController<T> controller;
  controller = StreamController<T>(
    onListen: () {
      job.value
          .then(controller.add, onError: controller.addError)
          .whenComplete(controller.close);
    },
    onCancel: job.cancel,
  );
  return controller.stream;
}
```

Two things of bloc decide where it is enough. `restartable()` cancels the
subscription of the handler it replaces, and `close()` cancels the
subscriptions of every running handler under `concurrent()`, the default, under
`droppable()` and under `restartable()`: there the job is cancelled with no
line of your own, and `close()` returns at once.

```text
concurrent: close took 0ms, the job Cancelled(manual)
droppable: close took 0ms, the job Cancelled(manual)
restartable: close took 0ms, the job Cancelled(manual)
```

Under `sequential()` `close()` cancels nothing. It waits for the running
handler, runs every queued event after it, and each job runs to its end:

```text
sequential: close took 190ms, the jobs [Done(1), Done(2)]
```

A handler that has to stop under `sequential()` keeps its job in a field, and
`close()` cancels it before `super.close()`. Such a handler awaits `job.done`
and not `job.value`: the value of a cancelled job throws `Cancelled`, and with
nobody to catch it the error goes to `onError` of the bloc and on to the zone.

```text
job.value under close: the zone [Cancelled(manual)]
```

`done` never throws. It returns the outcome, and a failure of the work is in it
as `Failed`, for the handler to deal with.

## Closing and cancelling in-flight work

A user sends a chat message and leaves the screen before the reply arrives. The
old operation must not update a closed screen or report the reply as read: the
user never saw it. The API answers a message in 50 ms; the events and the
state:

```dart
sealed class ChatEvent {
  const ChatEvent();
}

class SendMessage extends ChatEvent {
  const SendMessage(this.text);
  final String text;
}

class MarkReplyRead extends ChatEvent {
  const MarkReplyRead();
}

class ChatState {
  const ChatState([this.reply]);
  final String? reply;
  ChatState withReply(String reply) => ChatState(reply);
}
```

In the traces below the user sends "hi" and "bye", and the screen closes the
bloc 10 ms later: "hi" is in flight, "bye" waits in the queue.

### With bloc alone

A sequential handler checks closure after its await:

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
    on<MarkReplyRead>((e, emit) => _api.markRead(), transformer: sequential());
  }
}
```

```text
with bloc alone: close took 90ms, sent [hi, bye], reply null, reads 0
```

The guard keeps the reply off the state and the read off the server. Closing
still waits for the call in flight and then runs the queue: "bye" is sent while
`close()` runs, and `close()` returns after its answer, which the guard turns
away as well.

### With a job in the handler

The call goes into a job kept in a field, and `close()` cancels it before
`super.close()`:

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final Api _api;
  Job<String>? _sending;

  ChatBloc(this._api) : super(const ChatState()) {
    on<SendMessage>((e, emit) async {
      final job = _sending = Job(
        (ctx) => ctx.abandonable(() => _api.send(e.text)),
      );
      final outcome = await job.done;
      if (isClosed) return;
      switch (outcome) {
        case Done(:final value):
          emit(state.withReply(value));
          add(const MarkReplyRead());
        case Failed(:final error, :final stackTrace):
          Error.throwWithStackTrace(error, stackTrace);
        case Cancelled():
      }
    }, transformer: sequential());
    on<MarkReplyRead>((e, emit) => _api.markRead(), transformer: sequential());
  }

  @override
  Future<void> close() async {
    await _sending?.cancel();
    return super.close();
  }
}
```

```text
with a job: close took 50ms, sent [hi, bye], reply null, reads 0
```

`ctx.abandonable` ends the job at once when it is cancelled, and `close()` no
longer waits for what is left of the call for "hi". It still waits for the call
of every message in the queue: `sequential()` starts the handler for "bye"
while `close()` runs, and its job is not the one the field held when `close()`
cancelled it. A failure of the call comes out of `done` as `Failed`, and the
handler throws it again, so it reaches `onError` of the bloc and the zone as a
failure of `_api.send` does in the bloc alone:

```text
with a job, the call fails: the zone [Bad state: send: offline], reply null
```

```text
with bloc alone, the call fails: the zone [Bad state: send: offline], reply null
```

What stays with bloc: the `isClosed` check after the await, since a queued
message still gets its answer while `close()` runs, and the queue itself:
`sequential()` sends every message waiting in it.

## Finishing an in-flight write before restarting

A firmware upload writes BLE chunks one after another, 20 ms each. A
replacement upload must stop the old loop and wait for its current write before
sending any chunk of its own: the BLE API cannot abort an accepted write. In
the traces below each upload has four chunks, the second starts 30 ms after the
first, while chunk 1 is being written, and the third 5 ms after the second or
at the same moment.

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

class LockedFirmwareBloc extends Bloc<Flash, FirmwareState> {
  final Ble _ble;
  final _wire = Lock();

  LockedFirmwareBloc(this._ble) : super(const Idle()) {
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

The check inside the lock is the one that keeps the wire clear: the second
upload is replaced while it waits for the lock, and without the check its write
would start once the first one ends. Every handler that writes to the device
has to take the same lock.

### With a job in the handler

Each upload is a job that waits for the one before it, and `watch` cancels it
when `restartable()` replaces its handler:

```dart
class FirmwareBloc extends Bloc<Flash, FirmwareState> {
  final Ble _ble;
  Job<void>? _flashing;

  FirmwareBloc(this._ble) : super(const Idle()) {
    on<Flash>((e, emit) async {
      final previous = _flashing;
      final job = _flashing = Job<void>((ctx) async {
        if (previous != null) await ctx.join(() => previous.done);
        var written = 0;
        for (final chunk in e.chunks) {
          await ctx.join(() => _ble.write(chunk));
          emit(Flashing(++written, e.chunks.length));
        }
      });
      await emit.forEach(watch(job), onData: (_) => state);
    }, transformer: restartable());
  }
}
```

The wire and the states are the ones of the locked bloc, line for line, in both
series. `ctx.join` waits for what it is given and then throws `Cancelled` if
the job was cancelled meanwhile: a replaced job ends after its current write,
before its next `emit`, and the job after it writes nothing until then, since
it joins the `done` of the one before it first.

The handler takes the previous job and puts its own in the field at once,
before its first await, so the upload that comes next finds this one in the
field and waits for it. The waiting is in the body of the job, under
`ctx.join`, and not in the handler.

The job publishes its progress through the handler's `emit`, and that is
allowed: the handler is in `emit.forEach` until its job ends, and once the
handler is replaced its job throws at the next `join` and emits nothing more.

What stays with bloc: one rule instead of the lock and the checks of
`emit.isDone` — the field is read and written before the first await of the
handler.

## Releasing a resource returned after cancellation

An audio editor opens a native PCM buffer to draw a waveform, and the user
selects another clip while the first is still decoding. The old waveform must
not be shown, but its buffer must still be released. In the traces below clip 1
takes 50 ms to decode and clip 2 takes 20, and clip 2 is opened 5 ms after clip
1, so the decoder answers the second request first.

### With bloc alone

The check of the emitter goes inside a `try`/`finally` that owns the buffer:

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

```text
a second clip while the first decodes: [open 1, open 2, ready 2, sample 2, release 2, ready 1, release 1], state Preview(2)
```

```text
close while both decode: [open 1, open 2, closed, ready 2, release 2, ready 1, release 1]
```

The `finally` runs on the path of a replaced handler too, and that is the only
reason the stale buffer is released at all. Every exit after the buffer is
acquired has to stay inside the `try`.

### With a job in the handler

The release is declared on the call that returns the buffer:

```dart
class PreviewBloc extends Bloc<OpenPreview, PreviewState> {
  final Decoder _decoder;

  PreviewBloc(this._decoder) : super(const NoPreview()) {
    on<OpenPreview>((e, emit) async {
      final job = Job<int>((ctx) async {
        final buffer = await ctx.abandonable(
          () => _decoder.open(e.clip),
          dispose: (buffer) => buffer.release(),
        );
        return buffer.waveform();
      });
      await emit.forEach(watch(job), onData: Preview.new);
    }, transformer: restartable());
  }
}
```

The trace is the same in both cases, and each buffer is released once.
`ctx.abandonable` ends a cancelled job without waiting for the decoder, and a
buffer that arrives after that goes to `dispose`; a buffer that arrives while
the job is active is released when the job ends. The job returns the waveform
and not the buffer, since the buffer is released by then. It is `dispose` and
not `discard`: `discard` is for a resource handed to the caller as the result,
and it leaves alone the buffer of a job that ends `Done`.

What stays with bloc: no `try`/`finally` around the buffer. The release is
declared where the buffer is acquired, and an exit added to the handler later
cannot lose it.

## Where the queue is the problem

The other scenarios of [solo compared with bloc](../../solo/doc/vs-bloc.md) get
no section here: in each, what the code of a bloc app has to keep is about the
queue of bloc, and a job inside a handler does not change it.

| Scenario | What stays with bloc |
| --- | --- |
| [Ordering updates to shared state](../../solo/doc/vs-bloc.md#ordering-updates-to-shared-state) | one registration with `sequential()` for the events that update the same state: the order is the order of the queue |
| [An observer fails during a state update](../../solo/doc/vs-bloc.md#an-observer-fails-during-a-state-update) | the guard inside the observer: the failure is the observer's, not the work's |
| [Leaving a loading state when the work is cancelled](../../solo/doc/vs-bloc.md#leaving-a-loading-state-when-the-work-is-cancelled) | the reset from the handler of `CancelRefresh`: the replaced handler's emitter is done, whatever its job does |
| [Restarting one operation within a shared queue](../../solo/doc/vs-bloc.md#restarting-one-operation-within-a-shared-queue) | `_newestSeek`, the token of the `seek` in flight and the check after the await: which `seek` is still wanted is a question about the events waiting in the queue |
| [Typed methods with queued execution](../../solo/doc/vs-bloc.md#typed-methods-with-queued-execution) | function events and methods that return `void`: the job is created in the handler, after `add` has returned |
| [Removing selected pending work](../../solo/doc/vs-bloc.md#removing-selected-pending-work) | the generations through `Expando`: the work to remove is events in the queue, which have no job yet |
| [Awaiting a particular request](../../solo/doc/vs-bloc.md#awaiting-a-particular-request) | the completer on the event: `add` returns nothing, and the job is created after it |
| [Reacting to an independent external state change](../../solo/doc/vs-bloc.md#reacting-to-an-independent-external-state-change) | the second registration and the check after the await; a job in a field can take the check's place, with its cancellation from the handler of the external change and its outcome to sort out, and the trace stays the same |
