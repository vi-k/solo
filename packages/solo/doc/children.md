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
rules. The parent keeps the queue occupied until all its children finish, even
if its body returns earlier.

`ctx.run(child)` returns `Future<T>`. It waits for the child, the child's
children and cleanup. On success, it checks the parent's cancellation and state
rules before returning the value. A child error or cancellation is thrown into
the parent body with its stack trace.

Keep the original `child` to cancel it or inspect `child.done`. To work
concurrently in parent and child, handle the returned future separately. Their
state writes can then interleave. `ctx.run(child).ignore()` explicitly ignores
that future's result while the parent still waits for its children.
`child.ignore()` alone does not handle errors of the future returned by `run`.

Accepted parent cancellation propagates to children. This also applies when the
parent throws `Cancelled`, including an uncaught cancellation from
`await ctx.run(child)`. A parent body that fails instead lets its children
finish and waits for them. A child can refuse cancellation; `ctx.run` still
waits for it and checks the parent after child success.

A child the start rules turn away never runs. It is adopted first -- parent and
level -- and only then finished `Cancelled` with a `RulesCancelReason`: the
observer hears the drop as an outcome of this tree, with `job.level` telling it
how deep under the parent the line belongs, and `child.done` holds the
cancellation. It joins no waiting list, so the parent waits for nothing; the
future of `ctx.run` carries that cancellation all the same.

The rules `canStart` and `keepWhile`, when they throw themselves, are the other
case. The error is the rule's own, the child ends `Failed` with it, and
`ctx.run` throws it synchronously -- the line after the call never runs.

## Processing a stream

`ctx.each(stream, onData)` creates and returns a child `Job<void>` that owns
the subscription. Each event callback receives that child's context. Use it for
state access and cancellation-aware operations:

```dart
Job<void> track() => run<Ready, void>(
      key: 'track',
      (ctx) => ctx.each(
        hw.positions,
        (child, p) => child.emit(child.state.copyWith(position: p)),
      ).value,
    );
```

This application-specific example copies hardware positions into a `Ready`
state. Returning the child's `.value` makes stream and callback errors
propagate into the parent body. Use `.done` to inspect the outcome, or retain
the returned job and call its `cancel()` to stop only this subscription.

Events are processed in order. An asynchronous callback finishes before the
next callback starts; the first stream or callback error stops processing.
Cancellation removes the subscription immediately, prevents further delivery,
and waits for the current callback before completing the child. That last part
is why waits belong to the callback's context: `child.wait` ends with the
cancellation the moment it arrives and leaves the action running alone, while a
plain `await` ends only when its own future does -- and until the callback
returns, the child and the parent are still running.

The child ends when the source sends `onDone`, so an open stream with no events
is a child still running; and the parent waits for its children with or without
an explicit await, so it keeps running too. Accepted parent cancellation,
including during `close()`, cancels the child. The child is cancellable even if
the parent is not. It retains the parent's `W` and `keepWhile` after the parent
body returns, but does not repeat `canStart`. Observers see it as a separate
job.

Cancelling only the child does not directly cancel the parent. An uncaught
`Cancelled` from the child's `.value` does cancel the parent through its body.
Do not await the child's own completion or its `cancel()` inside an event
callback: that is a deadlock. The child waits for the callback to return, the
callback waits for the child, and the parent waits for the child -- nothing
moves again. To stop the subscription from inside a callback, call `cancel()`
and do not await it.

The child waits for the callback in flight, but not for the source: the engine
does not await the future that the subscription's `cancel()` returns, and
quenches its error instead of letting it reach the zone. Delivery stops at
once, and what that future carries is the cleanup of the source, which this job
does not own -- waiting for it would hold the child on a source free to take
its time or never come back, and a cleanup that failed is the source's business
too. If your source has asynchronous cleanup to wait for, wait for it yourself.
Like `ctx.run`, `each` cannot start a child after the parent body ends, during
cleanup, or from `unattended` work.

## Following another controller

A controller dedicated to following another controller can keep a job running
over its stream. Read the current state first because the stream only carries
later updates:

```dart
final class ScreenController extends Solo<Screen> {
  final SoloStream<Session> session;

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

Here, `Screen` and `Session` are application states with a `signedIn` property.
The subscription keeps the following controller's queue occupied until it ends.
If that controller must also process other jobs, use an external listener that
queues a short job for each update instead. When the update represents an
immediate change to the validity of current work, consider the
[External state](state.md#external-state) rules instead.

## Chaining completed work

```dart
// Runs after the source succeeds, with a plain JobContext of its own.
Job<void> syncAndReport(int item) =>
    sync(item).then((ctx, path) => analytics.send(path));
```

`job.then((ctx, value) => ...)` creates a job that runs after its source
succeeds, including children and cleanup. Its callback receives the result and
a new core `JobContext`, and may return a value or future. A source failure
propagates without calling the callback.

A `then` job does not inherit the controller's state context, rules, observer
or queue position. It has its own optional observer. Its callback gets a plain
core `JobContext`, with no `emit` on it and no state behind it, so a `then`
cannot write controller state itself: it asks the controller for another job,
and that job takes its turn at the back of the queue. The end of the source
does two things at once: it frees the slot and it starts the `then`. So
whatever was queued while the source ran stands ahead of the new job.

```dart
// The callback has no state to write, so it asks for a job:
// `recordPath` is a method of the controller with a `run` of its own.
// A `save()` queued while `sync` was still running goes ahead of it:
// sync, save, recordPath.
Job<void> syncAndRecord(int item) =>
    sync(item).then((ctx, path) => recordPath(path).value);

// The same two steps as one job. The parent holds the queue until its
// child is done, so that `save()` waits for both of them.
SoloJob<void> syncAndRecordTogether(int item) => run<Ready, void>(
      key: _Op.sync,
      (ctx) async {
        final path = await ctx.run(
          job<Ready, String>(
            key: _Op.upload,
            (child) => child.join(() => api.push(item)),
          ),
        );
        ctx.emit(ctx.state.copyWith(path: path));
      },
    );
```

Use children within one parent when the whole sequence must occupy the queue
without another root job running between its steps.

Cancellation propagates forward to `then` jobs and backward to unfinished
sources, subject to each job's cancellation rules. Cancelling the tail waits
for those sources and their cleanup, including a source that refuses
cancellation. `close()` reaches a `then` job through an unfinished source, but
does not own one already running after the source finished.

Inside a controller's body `ctx.run` is narrower still: it takes jobs of that
controller, the ones `job(...)` makes and nobody has queued. A `then` job is a
root job of the core, so it is turned away there as well, with the controller's
own complaint — that the job was not created by this `Solo`, which is what a
bare core job gets too.

The queue does not wait for a tail. The slot is freed when the root job
finishes, and the next queued job starts while the `then` job still has to run:
one hung off `load()` can be working after `save()` has taken the queue. Where
that would be wrong, keep the sequence inside one job and make its steps
children.
