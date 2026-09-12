# Children and streams

A root job can split its work into child jobs:

```dart
SoloJob<String> sync(int item) => run<Ready, String>(
      key: _Op.sync,
      (ctx) async {
        // Created by the controller, started by the parent and outside
        // the queue: the parent holds the queue for both.
        final upload = job<Ready, String>(
          key: _Op.upload,
          (child) => child.join(() => api.push(item)),
        );
        final path = await ctx.run(upload);

        // A stream child. The parent waits for it even without an
        // await, and cancelling the parent cancels it.
        ctx.each(
          device.events,
          (child, event) async =>
              child.emit(child.state.copyWith(done: event)),
        );
        return path;
      },
    );
```

A child starts immediately, bypassing the queue, subject to its own start
rules. The parent keeps the queue occupied until all its children finish,
even if its body returns earlier.

`ctx.run(child)` returns `Future<T>`. It waits for the child, the child's
children and cleanup. On success, it checks the parent's cancellation and
state rules before returning the value. A child error or cancellation is
thrown into the parent body with its stack trace.

Keep the original `child` to cancel it or inspect `child.done`. To work
concurrently in parent and child, handle the returned future separately.
Their state writes can then interleave. `ctx.run(child).ignore()` explicitly
ignores that future's result while the parent still waits for its children.
`child.ignore()` alone does not handle errors of the future returned by
`run`.

Accepted parent cancellation propagates to children. This also applies
when the parent throws `Cancelled`, including an uncaught cancellation
from `await ctx.run(child)`. A parent body that fails instead lets its
children finish and waits for them. A child can refuse cancellation;
`ctx.run` still waits for it and checks the parent after child success.

A child rejected by its start rules still receives its parent, level and
observer, but requires no further waiting. A throwing start rule fails
the child and propagates that error through `ctx.run`.

## Processing a stream

`ctx.each(stream, onData)` creates and returns a child `Job<void>` that
owns the subscription. Each event callback receives that child's context.
Use it for state access and cancellation-aware operations:

```dart
Job<void> track() => run<Ready, void>(
      key: 'track',
      (ctx) => ctx.each(
        hw.positions,
        (child, p) => child.emit(child.state.copyWith(position: p)),
      ).value,
    );
```

This application-specific example copies hardware positions into a
`Ready` state. Returning the child's `.value` makes stream and callback
errors propagate into the parent body. Use `.done` to inspect the outcome,
or retain the returned job and call its `cancel()` to stop only this
subscription.

Events are processed in order. An asynchronous callback finishes before
the next callback starts; the first stream or callback error stops
processing. Cancellation removes the subscription immediately, prevents
further delivery, and waits for the current callback before completing
the child. Use the callback's context for waits; a plain `await` can keep
the child and parent alive indefinitely.

The parent waits for this child even without an explicit await, so an open
stream with no events still keeps the parent running. Accepted parent
cancellation, including during `close()`, cancels the child. The child is
cancellable even if the parent is not. It retains the parent's `W` and
`keepWhile` after the parent body returns, but does not repeat `canStart`.
Observers see it as a separate job.

Cancelling only the child does not directly cancel the parent. An uncaught
`Cancelled` from the child's `.value` does cancel the parent through its
body. Do not await the child's own completion or `cancel()` inside its
event callback, because the child is already waiting for that callback.

The future returned by the underlying stream subscription's `cancel()`
is not awaited. Await asynchronous source cleanup separately if needed.
Normal completion requires the source to send `onDone`. Like `ctx.run`,
`each` cannot start a child after the parent body ends, during cleanup,
or from `unattended` work.

## Following another controller

A controller dedicated to following another controller can keep a job
running over its stream. Read the current state first because the stream
only carries later updates:

```dart
final class ScreenController extends Solo<Screen> {
  final Solo<Session> session;

  ScreenController(this.session) : super(const Screen());

  Job<void> follow() => run<Screen, void>(
        key: 'follow',
        (ctx) async {
          void take(SoloContext<Screen, Screen> target, Session next) =>
              target.emit(target.state.copyWith(signedIn: next.signedIn));

          take(ctx, session.currentState); // what has already happened
          await ctx.each(session.stream, take).value; // what happens next
        },
      );
}
```

Here, `Screen` and `Session` are application states with a `signedIn`
property. The subscription keeps the following controller's queue
occupied until it ends. If that controller must also process other jobs,
use an external listener that queues a short job for each update instead.
When the update represents an immediate change to the validity of current
work, consider the [External state](state.md#external-state) rules instead.

## Chaining completed work

```dart
// Runs after the source succeeds, with a plain JobContext of its own.
Job<void> syncAndReport(int item) =>
    sync(item).then((ctx, path) => analytics.send(path));
```

`job.then((ctx, value) => ...)` creates a job that runs after its source
succeeds, including children and cleanup. Its callback receives the result
and a new core `JobContext`, and may return a value or future. A source
failure propagates without calling the callback.

The continuation does not inherit the controller's state context, rules,
observer or queue position. It has its own optional observer. To change
controller state, call a method that enqueues another job; other queued
jobs may run between the two operations. Use children within one parent
when the whole sequence must occupy the queue without another root job
running between its steps.

Cancellation propagates forward to continuations and backward to
unfinished sources, subject to each job's cancellation rules. Cancelling
the tail waits for those sources and their cleanup, including a source
that refuses cancellation. `close()` reaches a continuation through an
unfinished source, but does not own a continuation already running after
the source finished.
