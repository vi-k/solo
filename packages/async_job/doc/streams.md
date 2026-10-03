# Streams

A job follows a stream in a child that owns the subscription: `ctx.each` starts
that child, delivers the events to a callback one at a time, and ends the
subscription with the job. `Job.each` is the same for a job with nothing else
to do.

Three sections below open with the version habit leads to — the `await for`,
the `listen` and the `asyncMap` every Dart program already has, a plain
`await`, the `dispose` a body would use — and say what that version does
instead of what it was meant to do. The version that works follows under its
own heading. The other sections have no such version, and open with the answer.

## Processing a stream

A job saves every message of a stream: one at a time, failing when a save
fails, and stopping when it is cancelled.

### The first attempt

```dart
Job<void>((ctx) async {
  await for (final message in messages) {
    await ctx.join(() => store.saveBody(message));
  }
});
```

While a save runs, `join` is a checkpoint: a cancellation that arrives then is
thrown when the save is done, and the loop lets go of the stream. Between two
messages there is no checkpoint. The body is parked inside `await for`, which
knows nothing of the job, so a job cancelled while the stream is silent goes on
running, still subscribed, until the next message arrives — and `job.cancel()`
does not return before that either. On a stream that has gone silent for good,
that is never.

### The second attempt

```dart
Job<void>((ctx) async {
  final subscription = messages.listen((message) async {
    await store.saveBody(message);
  });
  ctx.onCancel(subscription.cancel);
  await ctx.wait(subscription.asFuture<void>);
});
```

The last two lines tie the subscription to the job: a cancellation cancels it,
and the body waits for the stream to end. Two things are still missing.

`listen` does not wait for an asynchronous callback. A second message arrives
while the first is being saved, and its save starts at once: the two run side
by side, and nothing says which one finishes first.

And the stream calls the callback, not the body. An error thrown in it goes to
the zone and past the job: the job stays running and subscribed, its outcome
knows nothing of the failure, and neither does whoever awaits its `value`. The
`onError` of `listen` does not change that: it hears the errors of the stream,
not what the callback throws.

### The third attempt

```dart
Job<void>((ctx) async {
  final subscription = messages.asyncMap(store.saveBody).listen((_) {});
  ctx.onCancel(subscription.cancel);
  await ctx.wait(subscription.asFuture<void>);
});
```

`asyncMap` waits for each save before it takes the next message, and an error
of a save becomes an error of the stream, which fails the job. What is left is
the cancellation. `subscription.cancel()` stops the delivery, but not the save
that is already running, and nothing waits for that save: the job ends as
`Cancelled`, and its `cancel()` returns, while the message is still being
saved. The save finishes after the job has ended, and if it fails then, its
error reaches neither the job nor the zone.

### A child that owns the subscription

```dart
Job<void>((ctx) async {
  final saving = ctx.each(messages, (childCtx, message) {
    return childCtx.join(() => store.saveBody(message));
  });
  await saving.value;
});
```

`ctx.each(stream, onData)` subscribes to the stream and immediately returns a
child `Job<void>` that owns the subscription. The callback receives that
child's context and an event. The child delivers the next message when the
callback for the previous one has finished, so the saves run one after another.
It cancels the subscription the moment it accepts a cancellation, whether a
message is on its way or not. A save that is running at that moment is waited
for: `join` holds the cancellation until the save has finished, and the child
ends after it. And an error of the stream or of the callback ends it `Failed`.

`saving.value` completes when the stream ends and the last save finishes;
awaiting it throws the child's failure into the body, and a `Cancelled` it
throws follows the cancellation path: uncaught, it cancels the parent under the
usual child outcome rules. `saving.done` does not throw: awaiting it returns
the child's `Outcome`, whether `Done`, `Failed` or `Cancelled`.

The parent waits for the child even if its body returns without awaiting it. An
open stream therefore keeps the parent alive until the stream ends or the child
is cancelled. Accepted parent cancellation cascades to the child. The observer
sees this child as a separate job.

Like `run`, `each` can only start children while the parent body is active;
calls from `unattended` or cleanup are rejected. Normal stream completion
depends on the source sending `onDone`.

## A callback in several steps

A message is saved in two steps — the body of the message, then its
attachments — and a cancellation should stop the save between them.

### The first attempt

```dart
ctx.each(messages, (childCtx, message) async {
  await store.saveBody(message);
  await store.saveAttachments(message);
});
```

When the child accepts cancellation, it cancels the subscription at once and
stops delivering events. What it cannot do is interrupt the callback already
running: a plain `await` is not a checkpoint, so the callback comes back from
the first step and starts the second, and runs to its end as if nothing had
happened. The child waits for it, and so does the parent's cleanup: a cancelled
job whose callback still has work in it releases nothing until that callback is
done.

### The child's own checkpoints

```dart
ctx.each(messages, (childCtx, message) async {
  await childCtx.join(() => store.saveBody(message));
  await childCtx.join(() => store.saveAttachments(message));
});
```

The callback gets the child's context precisely so its steps can stop for a
cancellation. `childCtx.join` waits for the step it wraps — a save halfway
through is still a save — and then lets the cancellation out in place of the
value, so the second step never starts and the parent's cleanup runs as soon as
the first one is done. `childCtx.wait` is the other choice, for a step whose
result can be abandoned. What must not go in there is the child's own
completion: awaiting the `value` of the job `each` returned, or its `cancel()`,
from inside the callback never finishes, because the child is already waiting
for that callback.

## What one event opens

Each message is written through a draft, and the draft has to be closed when
its message is written.

### The first attempt

```dart
ctx.each(messages, (childCtx, message) async {
  final draft = await childCtx.join(
    () => store.openDraft(message),
    dispose: (draft) => draft.close(),
  );
  await childCtx.join(draft.write);
});
```

The callback hands the closing to `dispose`, the way a body does. `dispose`
puts it on the cleanup stack of the child, and that stack unwinds when the
child ends, not when the callback returns. Two messages in, both drafts are
written and neither is closed; they close together when the stream ends, and on
a stream that does not end they never do. `ctx.onDispose` and `discard` in the
callback register on the same stack.

### A child for the event

```dart
ctx.each(messages, (childCtx, message) {
  return childCtx.run(Job.deferred<void>((eventCtx) async {
    final draft = await eventCtx.join(
      () => store.openDraft(message),
      dispose: (draft) => draft.close(),
    );
    await eventCtx.join(draft.write);
  }));
});
```

What one event opens belongs to a child started for that event. The callback
returns the future of `run`, so the next message waits for this child, and the
child's stack unwinds before it: each draft is closed before the next one is
opened. Cancelled halfway through a write, the child still closes its draft
before the job ends.

## Stopping the stream alone

The job that `each` returns lets the parent stop listening and go on. This
example prints a tick every second, stops listening after 2.5 seconds, and
continues the parent body:

```dart
Future<void> watchTicks() async {
  final job = Job<void>((ctx) async {
    final ticks = ctx.each(
      Stream<int>.periodic(const Duration(seconds: 1), (index) => index + 1),
      (childCtx, tick) => print('Tick $tick'),
    );

    await ctx.pause(const Duration(milliseconds: 2500));
    await ticks.cancel();
    print('Parent continues');
  });

  await job.value;
}
```

The output is `Tick 1`, `Tick 2`, then `Parent continues`. The stream has not
ended when `ticks.cancel()` cancels the subscription. The call waits for the
child to finish; cancelling that child does not itself cancel the parent.

## Waiting for the source to close

```dart
final feed = Feed();
ctx.onDispose(feed.close);
await ctx.each(feed.messages, (childCtx, message) => save(message)).value;
```

The future returned by the underlying subscription's `cancel()` is the source's
own cleanup: a connection shutting down, a file being flushed. The child lets
go of the stream and ends without waiting for it, so the job can be over while
the source is still closing. If that future fails, the error goes to `onError`
of the child's observer and, unless that observer answers for it, to the zone.

A job that must not end before the source has closed puts that closing on its
own cleanup stack, as above. `feed.close()` here returns a future that
completes when the connection is down. The cleanup of the job awaits it, so the
job ends after it, and `cancel()` and a parent, which wait for the job, wait
for the source as well.

## A job that only follows a stream

```dart
Future<void> saveAll(
  Stream<String> messages,
  Future<void> Function(String message) save,
) async {
  final saving = Job.each(messages, (ctx, message) {
    return ctx.join(() => save(message));
  });

  await saving.value;
}
```

The job in [Processing a stream](#processing-a-stream) is two jobs: a parent
with nothing else to do, and the child that owns the subscription. `Job.each`
makes one job that follows the stream by itself. It is a root, not a child, and
the callback receives the context of that job. The stream is followed as
`ctx.each` follows it; `key`, `describe`, `cancellable` and `observer` are
those of `Job(...)`.

Three things are different from the child:

- **It starts inside the call.** A job made with `Job(...)` starts its body on
  the next microtask. `Job.each` has subscribed by the time it returns, so an
  event a broadcast stream sends right after the call is not lost. The
  observer's `onStart` therefore runs before the caller has the handle, and a
  source that hands an event over from inside `listen` reaches the callback
  before the call returns. A callback that needs its own job reads `ctx.job`.
- **It is a root wherever it is made.** Called in the body of another job, it
  is not a child of that job: the body neither waits for it nor cancels it, and
  `ctx.run` refuses it with an `ArgumentError`. Inside a body, follow the
  stream with `ctx.each`. A failure nobody reads goes to the zone, as from any
  root.
- **With `cancellable: false` nothing outside stops it.** Such a job refuses
  every cancellation, and `cancel()` does not return until the job ends by
  itself: the stream ends or fails, or the callback throws — a `Cancelled`
  included. On a stream that never ends, that is the only way out.
