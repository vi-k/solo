# async_job in a bloc app

A bloc handler can run its work as a job and keep everything else of bloc: the
events, the transformers, the states. Each section below takes one requirement
of an app on bloc 9 with `bloc_concurrency`, shows the answer of bloc alone and
then the same handler with a job in it, and says what the job takes off the
code and what stays with bloc. The code runs in pure Dart, and the states and
traces under it are what that code prints.

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
