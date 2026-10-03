# Children and streams

A root job can split its work into child jobs:

```dart
// Made by the controller and started by nobody yet: the queue takes it
// through `sync` below, a parent takes it through `ctx.run`.
SoloJob<String> _sync(int item) => job<Ready, String>(
      key: _Op.sync,
      (ctx) async {
        // A stream child: the progress of the upload, which the API
        // closes when the upload ends. The parent waits for the child
        // even without an await, and cancelling the parent cancels it.
        ctx.each(
          api.progress(item),
          (childCtx, sent) =>
              childCtx.emit(childCtx.state.copyWith(sent: sent)),
        );

        // Created by the controller, started by the parent and outside
        // the queue: the parent holds the queue while it runs.
        final upload = job<Ready, String>(
          key: _Op.upload,
          (childCtx) => childCtx.join(() => api.push(item)),
        );
        return ctx.run(upload);
      },
    );

SoloJob<String> sync(int item) => add(_sync(item));
```

`job(...)` makes a job and starts nothing. `add` gives it a place in the queue,
and `ctx.run` inside a body makes it a child; `_sync` is written once and goes
both ways later on this page.

A child starts immediately, bypassing the queue, subject to its own start
rules: its working type, `canStart` and `keepWhile`, the ones
[The rules](state.md#the-rules) on the state page describes. The parent keeps
the queue occupied until all its children finish, even if its body returns
earlier: `sync` is over once the upload has returned its path and the API has
closed the progress.

`ctx.run(child)` returns a `Future<T>` of the child's result. It waits for the
child, the child's children and cleanup. On success, it checks the parent's
cancellation and state rules before returning the value, so a value the parent
has to release is registered on the call, `ctx.run(child, dispose: ...)`, and
not on the line after it:
[Discard, for a value that leaves](resources.md#discard-for-a-value-that-leaves)
on the resources page says why. A child error or cancellation is thrown into
the parent body with its stack trace.

To work in the parent while a child runs, keep the future `ctx.run` returned
and await it later. The state writes of the two can then interleave, and each
job answers to its own rules for every one of them: a write of the child that
the parent's working type or `keepWhile` does not accept cancels the parent,
and the child with it. `ctx.run(child).ignore()` explicitly ignores that
future's result while the parent still waits for its children. `child.ignore()`
alone does not handle errors of the future returned by `run`.

If the child's body fails and a cancellation reaches the child afterwards,
whether before the error leaves the body or while the child still waits for
children of its own or runs its cleanup, its error is not thrown into the
parent body. The child ends `Cancelled`, `await ctx.run(child)` throws
`Cancelled`, and the error goes to the controller's `onUnanswered` — by default
to `Solo.errorHandler`, or to the zone without one. `child.ignore()` silences
it. `ctx.run(child).ignore()` does not: it handles what the future throws, and
the future throws the cancellation.

A child the start rules turn away never runs. It is adopted first — parent and
level — and only then finished `Cancelled` with a `RulesCancelReason`: the
observer hears the drop as an outcome of this tree, with `job.level` telling it
how deep under the parent the job stands, and `child.done` holds the
cancellation. It joins no waiting list, so the parent waits for nothing; the
future of `ctx.run` carries that cancellation all the same.

The rules `canStart` and `keepWhile`, when they throw themselves, are the other
case. The error is the rule's own, the child ends `Failed` with it, and
`ctx.run` throws it synchronously — the line after the call never runs.

The rest of what passes between a parent and its child is the core's, and
[Children](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/children.md#children)
on the children page of `async_job` has it — that a cancellation the parent
accepts passes to its children, that a body that fails lets them finish and
waits for them, and why `child.ignore()` is no substitute for handling the
future of `ctx.run`. Several children side by side are a group of `ctx.runAll`,
under
[Waiting for several children](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/children.md#waiting-for-several-children)
on the same page. Where that page makes a child with `Job.deferred`, a
controller makes it with `job(...)`: its `ctx.run` and `ctx.runAll` take no
other job, and each branch of a group answers to its start rules as a child of
`ctx.run` does.

Three sections below open with the version habit or the names of this API lead
to — the `listen` every Dart program already has, the stream that is there to
be followed, the `then` that reads like "and then" — and say what that version
does instead of what it was meant to do. Where the next version repairs that
and brings a fault of its own, it stands as a second attempt. The version that
works follows under its own heading. `api`, `hw` and `analytics` belong to the
application these examples come from, and `Ready` is the state its controller
works in, with the fields `sent`, `position` and `path`.

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
this page, still holds the parent, but its failure is not the parent's: the
parent ends `Done`, and the failure goes where a failure nobody read goes, to
the zone, as in
[Handled and unhandled failures](errors.md#handled-and-unhandled-failures) on
the errors page. `ignore()` on the child keeps it out of the zone.

Events are delivered one at a time, and a cancellation waits for the callback
in flight. That is why waits belong to the callback's context: `childCtx.wait`
ends with the cancellation the moment it arrives and leaves the action running
alone, while a plain `await` ends only when its own future does — and until the
callback returns, the child and the parent are still running, the queue is held
and `close()` does not come back. Do not await the child's own completion or
its `cancel()` inside an event callback: that is a deadlock. The child waits
for the callback to return, the callback waits for the child, and the parent
waits for the child — nothing moves again. To stop the subscription from inside
a callback, call `cancel()` and do not await it.

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

## Chaining completed work

```dart
// Runs after `sync` succeeds, outside the queue, with a plain JobContext.
Job<void> syncAndReport(int item) =>
    sync(item).then((ctx, path) => analytics.send(path));
```

`job.then((ctx, value) => ...)` creates a continuation: a job that runs after
its source succeeds, including children and cleanup — for `sync`, once the API
has closed the progress. Its callback receives the result and a new core
`JobContext`, and may return a value or future. A source failure propagates
without calling the callback.

A continuation does not inherit the controller's state context, rules, observer
or queue position. It has its own optional observer. It belongs to whoever
called `then`, not to the controller: the controller's hooks and
`Solo.observer` do not hear it. A failure reaches whoever reads its outcome,
the failure of `sync` passed down the chain included, and one nobody reads goes
to the zone. An error with no outcome goes to the zone where `then` was called.

The queue does not wait for what comes after a job: the slot is freed when the
root job finishes, and the next queued job starts while the continuation still
has to run. The report above can be on its way after the job queued behind
`sync` has taken the queue, and that is what a chain is for: a step the queue
has no business waiting for. Where that would be wrong, the steps belong inside
one job, as in [Steps in a row](#steps-in-a-row) below.

Cancellation travels along a chain both ways, as
[Chains](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/children.md#chains)
on the children page of `async_job` describes. For a controller that means that
`close()` reaches a continuation through an unfinished source, but does not own
one already running after the source finished.

A continuation is never a child. Inside a controller's body `ctx.run` takes
jobs of that controller, the ones `job(...)` makes and nobody has queued, and a
continuation is none of those: it is a root job of the core. The controller
refuses it with an `ArgumentError`:

```text
Invalid argument (job): was not created by this Solo: "Job(then)"
```

A job of the core made by hand is refused in the same words.

## Steps in a row

`sync` returns the path of what it uploaded, and the path has to be in the
state before any other job of the queue runs. The step that records it is split
the way `sync` is:

```dart
// The same split as `sync`: the step itself, and the queue's way in.
SoloJob<void> _recordPath(String path) => job<Ready, void>(
      key: _Op.record,
      (ctx) async => ctx.emit(ctx.state.copyWith(path: path)),
    );

SoloJob<void> recordPath(String path) => add(_recordPath(path));
```

### The first attempt

```dart
Job<void> syncAndRecord(int item) =>
    sync(item).then((ctx, path) => recordPath(path).value);
```

`then` reads like the word for "and then". Its callback gets a plain core
`JobContext`, with no `emit` on it and no state behind it, so a continuation
cannot write controller state itself: it asks the controller for another job,
and that job takes its turn at the back of the queue. The end of the source
does two things at once: it frees the slot and it starts the continuation. So
whatever was queued while the source ran stands ahead of the new job: with
another method of the controller, `save()`, called while `sync` was still
running, the order is `sync`, `save`, `recordPath`. And a controller that is
draining takes no new job at all: the path is never recorded, and the
continuation ends `Cancelled(closed)`.

### The second attempt

```dart
SoloJob<void> syncAndRecord(int item) => run<Ready, void>(
      key: _Op.syncAndRecord,
      (ctx) async {
        final path = await sync(item).value;
        await recordPath(path).value;
      },
    );
```

One job now holds the queue across both steps, and it calls the methods the
controller already has. But a method that queues makes a root job wherever it
is called from, and that job waits for the slot the caller is holding. The
caller is waiting for that job: the upload never starts, and nothing moves
until `close()` cancels both. Called without the `await`, such a method is no
trap: what it queues runs after this job and after everything queued before it.

### Two children in a row

```dart
// `_sync` and `_recordPath` again, now children. The parent holds the
// queue until its children are done, so a `save()` queued meanwhile
// waits for both steps.
SoloJob<void> syncAndRecord(int item) => run<Ready, void>(
      key: _Op.syncAndRecord,
      (ctx) async {
        final path = await ctx.run(_sync(item));
        await ctx.run(_recordPath(path));
      },
    );
```

A step written as `job(...)` has both ways open: `add` gives it a queue slot of
its own, `ctx.run` makes it a child of a job that already holds one. Use
children within one parent when the whole sequence must occupy the queue
without another root job running between its steps.
