# Streams

A job of a controller follows a stream in a child that owns the subscription:
`ctx.each` starts that child and hands its callback each event with the child's
context. The subscription lives exactly as long as the child: the child ends
when the stream is done, and cancelling the child or the job cancels the
subscription. This page is about what a controller adds to such a child: the
queue it holds, `close()`, the start rules, and the stream of another
controller.

Both sections below open with the version habit or the names of this API lead
to — the `listen` every Dart program already has, the stream that is there to
be followed — and say what that version does instead of what it was meant to
do. The version that works follows under its own heading. `hw` belongs to the
application these examples come from, and `Ready` is the state its controller
works in, with the field `position`.

## Processing a stream

A controller copies the positions its hardware reports into the state.

### The first attempt

```dart
Job<void> track() => run<Ready, void>(
      key: 'track',
      (ctx) async {
        hw.positions.listen(
          (p) => ctx.emit(ctx.state.copyWith(position: p)),
        );
      },
    );
```

The body subscribes and returns, so the job is over before the first position
arrives, and the queue moves on. The subscription stays, holding the context of
a job that has finished. Each position it delivers throws out of `emit` into
the zone, and the state never changes:

```text
Bad state: Job(track) has already finished, cannot emit
```

Nothing ends that subscription either: there is no job left to cancel, and
`close()` knows nothing of it. Registering `sub.cancel` with `ctx.onDispose`
does not repair that: the cleanup runs as soon as the body returns, and the
subscription is gone before the first position.

### A child that owns the subscription

```dart
Job<void> track() => run<Ready, void>(
      key: 'track',
      (ctx) => ctx.each(hw.positions, (childCtx, p) {
        childCtx.emit(childCtx.state.copyWith(position: p));
      }).value,
    );
```

`ctx.each(stream, onData)` creates and returns a child `Job<void>` that owns
the subscription. Each event callback receives that child's context. Use it for
state access and cancellation-aware operations. Returning the child's `.value`
makes stream and callback errors propagate into the parent body. Use `.done` to
inspect the outcome, or retain the returned job and call its `cancel()` to stop
only this subscription.

The child ends when the source sends `onDone`, so an open stream with no events
is a child still running; and the parent waits for its children with or without
an explicit await, so it keeps running too, and holds the queue. Accepted
parent cancellation, including during `close()`, cancels the child; a draining
`close(mode: SoloCloseMode.drain)` cancels nothing and waits for the stream to
end. The child is cancellable even if the parent is not. It retains the
parent's working type and `keepWhile` after the parent body returns, but does
not repeat `canStart`. Observers see it as a separate job, `Job(each)`.

Cancelling only the child does not directly cancel the parent. An uncaught
`Cancelled` from the child's `.value` does cancel the parent through its body.
A child whose outcome nobody reads, like the progress in `_sync` at the top of
[Children and streams](children.md), still holds the parent, but its failure is
not the parent's: the parent ends `Done`, and the failure goes where a failure
nobody read goes, to the zone, as in
[Handled and unhandled failures](errors.md#handled-and-unhandled-failures) on
the errors page. `ignoreFailure()` on the child keeps it out of the zone.

Events are delivered one at a time, and a cancellation waits for the callback
in flight. That is why waits belong to the callback's context:
`childCtx.abandonable` ends with the cancellation the moment it arrives and
leaves the action running alone, while a plain `await` ends only when its own
future does — and until the callback returns, the child and the parent are
still running, the queue is held and `close()` does not come back. Do not await
the child's own completion or its `cancel()` inside an event callback: that is
a deadlock. The child waits for the callback to return, the callback waits for
the child, and the parent waits for the child — nothing moves again. To stop
the subscription from inside a callback, call `cancel()` and do not await it.

The child does not wait for the source: the future the subscription's
`cancel()` returns is the cleanup of the source, which this job does not own.
If that cleanup fails, its error goes to `Solo.onError` and on to
`Solo.onUnanswered`, as an error no outcome carries does. A job that must not
end before its source has closed waits for that itself, the way
[Waiting for the source to close](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/streams.md#waiting-for-the-source-to-close)
on the streams page of `async_job` does. The rest of that page holds here as
well, with `job(...)` where it writes `Job.deferred`: what `await for` and a
`listen` tied to the job do in a body, how a callback in several steps stops
for a cancellation, and where the cleanup of one event belongs.

## Following another controller

A screen shows whether the user is signed in, and the session is the state of
another controller.

### The first attempt

```dart
final class ScreenController extends Solo<Screen> {
  final SoloStream<Session> session;

  ScreenController(this.session) : super(const Screen());

  Job<void> follow() => run<Screen, void>(
        key: 'follow',
        (ctx) => ctx.each(session.stream, (childCtx, next) {
          childCtx.emit(childCtx.state.copyWith(signedIn: next.signedIn));
        }).value,
      );
}
```

The stream of a controller carries the changes of its state, not the state it
is in. A session that is already signed in when `follow()` starts sends
nothing, and the screen goes on showing `signedIn: false` until the session
changes.

### The state first, then the stream

```dart
Job<void> follow() => run<Screen, void>(
      key: 'follow',
      (ctx) async {
        void take(SoloContext<Screen, Screen> target, Session next) =>
            target.emit(target.state.copyWith(signedIn: next.signedIn));

        take(ctx, session.currentState); // what has already happened
        await ctx.each(session.stream, take).value; // what happens next
      },
    );
```

Here `Screen` and `Session` are application states with a `signedIn` property.
The read and the subscription stand on two lines with no `await` between them,
so no change of the session falls between the two.

The subscription keeps the following controller's queue occupied until it ends:
no other job of that controller starts before the session closes its stream,
and a draining `close` waits for the same. So this job suits a controller that
does nothing but follow. A controller with other jobs to run holds a
subscription of its own instead, made in its constructor and cancelled in
`onClose`, and from it either queues a short job for each update or, when the
update is a fact the running work has to hear at once, writes it with
`externalSetState`. [External state](state.md#external-state) on the state page
shows such a subscription and says which of the two an update calls for.

