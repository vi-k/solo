# solo under bloc

A bloc can hand its work to a `solo` controller and keep everything else of
bloc: the events, the transformers, the state a screen reads. Each section
below takes one requirement of an app on bloc 9 with `bloc_concurrency`, shows
the answer of bloc alone and then the same bloc with a controller under it, and
says what the controller takes off the code and what stays with bloc. The
controllers are the ones of the Solo sections of
[solo and bloc, side by side](vs-bloc.md), where each of them stands without
bloc. The code runs in pure Dart, and the states and traces under it are what
that code prints.

The sections, each a requirement where a controller under the bloc leaves the
code less to do:

- `close()` under `sequential()` waits for the call in flight and sends every
  queued message —
  [Closing and cancelling in-flight work](#closing-and-cancelling-in-flight-work).

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

The bloc publishes them from the handler of an event of its own, which the
constructor adds and which runs as long as the bloc lives:

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
    on<_Started>(
      (e, emit) => emit.forEach(_counter.stream, onData: (state) => state),
    );
    on<CountTo>((e, emit) => _counter.countTo(e.target).done);
    on<Reset>((e, emit) => _counter.reset().done);
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

The handlers of `CountTo` and `Reset` wait for the jobs of the controller as
for any job. A method of a controller returns a `Job`, and the handler awaits
`job.done`, which never throws and returns the outcome. `job.value` of a job
the closing controller cancelled throws `Cancelled`, and with nobody to catch
it the error goes to `onError` of the bloc and on to the zone, as
[The bridge](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/bloc.md#the-bridge)
on the page of `async_job` shows.

The bloc counts to 2, is reset twice and counts to 3, and the screen closes it
35 ms in, after the first step of the last count:

```text
controller [1, 2, 0, 0, 1]
bloc       [1, 2, 0, 1]
close took 0ms, bloc.state 1, counter.isClosed true, bloc.isClosed true
```

The bloc publishes every state of the controller but one equal to the state
before it, which bloc drops as it drops any such `emit`; `SoloStream` publishes
it. `close()` of the bloc closes the controller, and the controller cancels the
count at `ctx.pause`. The closed controller closes its stream, and
`emit.forEach` ends with it. Why the controller closes first is taken apart in
[Closing and cancelling in-flight work](#closing-and-cancelling-in-flight-work).

`_counter.stream.listen(emit)` in the constructor would be shorter, but `emit`
of a bloc is for its handlers and tests, and the analyzer reports such a call
as `invalid_use_of_visible_for_testing_member`.

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

### With a controller under the bloc

The calls go to the controller of
[Closing and cancelling in-flight work](vs-bloc.md#closing-and-cancelling-in-flight-work),
and the reply and the read are its jobs:

```dart
final class ChatController extends Solo<ChatState> {
  final Api _api;

  ChatController(this._api) : super(const ChatState());

  Job<void> send(String text) =>
      enqueue<ChatState, void>(key: 'send', (ctx) async {
        final reply = await ctx.abandonable(() => _api.send(text));
        ctx.emit(ctx.state.withReply(reply));
        markReplyRead();
      });

  Job<void> markReplyRead() =>
      enqueue<ChatState, void>((ctx) => ctx.abandonable(_api.markRead));
}
```

The bloc keeps its events and its `sequential()`, takes the stream from the
controller with `SoloStream`, and closes the controller before itself:

```dart
final class StreamedChat = ChatController with SoloStream<ChatState>;

final class _Started extends ChatEvent {
  const _Started();
}

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._chat) : super(_chat.currentState) {
    on<_Started>(
      (e, emit) => emit.forEach(_chat.stream, onData: (state) => state),
    );
    on<SendMessage>(
      (e, emit) => _chat.send(e.text).done,
      transformer: sequential(),
    );
    add(const _Started());
  }

  final StreamedChat _chat;

  @override
  Future<void> close() async {
    await _chat.close();
    return super.close();
  }
}
```

```text
with a controller: close took 0ms, sent [hi], reply null, reads 0
```

Closing the controller cancels "hi" at `ctx.abandonable`, before the reply and
the read. `sequential()` still starts the handler for "bye", and the closed
controller ends its job `Cancelled(closed)` without a call. Then
`super.close()` finds nothing to wait for.

The order is what holds it. With `super.close()` first, `sequential()` runs its
queue through a controller that is still open, and the requirement is lost
twice over: both messages go to the API, and both replies reach the state of
the closing bloc and are reported read.

```text
with super.close() first: close took 100ms, sent [hi, bye], reply reply to bye, reads 2
```

What stays with bloc: the order of `close()` — the controller first, then
`super.close()`. The handler checks no `isClosed`: the reply and the read are
jobs of the controller, and a closed controller runs neither.
