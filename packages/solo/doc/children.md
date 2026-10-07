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

What passes between a parent and its child beyond what this page shows is the
core's, and
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

`ctx.each(stream, onData)` subscribes in a child that owns the subscription and
hands the callback each event with the child's context: that is how `_sync`
above follows the progress of the upload. [Streams](streams.md) is about such
children in a controller: what a subscription made by hand in a body does, how
long the child holds the queue, and how to follow another controller.

One section below opens with the version the names of this API lead to — the
`then` that reads like "and then" — and says what that version does instead of
what it was meant to do. The next version repairs that and brings a fault of
its own, so it stands as a second attempt. The version that works follows under
its own heading. `api` and `analytics` belong to the application these examples
come from, and `Ready` is the state its controller works in, with the fields
`sent`, `path` and `paused`.

## The future of `ctx.run`

```dart
// The parent answers for a failed upload itself.
SoloJob<bool> trySync(int item) => run<Ready, bool>(
      key: _Op.trySync,
      (ctx) async {
        try {
          final path = await ctx.run(_sync(item));
          ctx.emit(ctx.state.copyWith(path: path));
          return true;
        } on ApiException {
          return false;
        }
      },
    );
```

`ctx.run(child)` returns a `Future<T>` of the child's result. It waits for the
child, the child's children and cleanup: the `catch` above runs once the API
has closed the progress `_sync` follows. On success, it checks the parent's
cancellation and state rules before returning the value, so a value the parent
has to release is registered on the call, `ctx.run(child, dispose: ...)`, and
not on the line after it:
[Discard, for a value that leaves](resources.md#discard-for-a-value-that-leaves)
on the resources page says why. A child error or cancellation is thrown into
the parent body with its stack trace.

The clause above names `ApiException` on purpose. `Cancelled` implements
`Exception`, so `on Exception` or `on Object` in its place would take a
cancellation along with the failures of the API, that of the child and that of
`trySync` itself.
[Catching errors inside a body](errors.md#catching-errors-inside-a-body) on the
errors page shows what that costs and what a broad clause has to do first.

## Working beside a child

```dart
SoloJob<String> syncAndAnnounce(int item) => run<Ready, String>(
      key: _Op.syncAndAnnounce,
      (ctx) async {
        // Kept, not awaited: the upload runs while the parent goes on.
        // A failure of the upload is ignored here, and the body fails
        // with it at the `return`.
        final uploading = ctx.run(_sync(item))..ignore();
        await ctx.join(() => analytics.send('started $item'));
        return uploading;
      },
    );
```

To work in the parent while a child runs, keep the future `ctx.run` returned
and await it later. The state writes of the two can then interleave, and each
job answers to its own rules for every one of them: a write of the child that
the parent's working type or `keepWhile` does not accept cancels the parent,
and the child with it.

Nobody waits for a future kept this way until the `await`: an upload that fails
while the parent is still sending would hand its error to the zone as an
unhandled one. `ignore()` on the kept future says that the error is not to be
reported there. The body fails with that error all the same, at the `return`,
where it hands the future on.

## Two ways to ignore a child

| In the parent | An error the future of `ctx.run` throws | A failure of the child that a cancellation covered |
| --- | --- | --- |
| `ctx.run(child).ignore()` | handled | goes to `onUnanswered` |
| `child.ignore()` | not handled, goes to the zone | silenced |

`ctx.run(child).ignore()` explicitly ignores that future's result while the
parent still waits for its children. `child.ignore()` alone does not handle
errors of the future returned by `run`.

If the child's body fails and a cancellation reaches the child afterwards,
whether before the error leaves the body or while the child still waits for
children of its own or runs its cleanup, its error is not thrown into the
parent body. The child ends `Cancelled`, `await ctx.run(child)` throws
`Cancelled`, and the error goes to the controller's `onUnanswered` — by default
to `Solo.errorHandler`, or to the zone without one. `child.ignore()` silences
it. `ctx.run(child).ignore()` does not: it handles what the future throws, and
the future throws the cancellation.

## A child the rules turn away

```dart
SoloJob<String> resend(int item) => run<Ready, String>(
      key: _Op.resend,
      (ctx) {
        // A child with a rule of its own: no upload while paused.
        final upload = job<Ready, String>(
          key: _Op.upload,
          canStart: (state) => !state.paused,
          (childCtx) => childCtx.join(() => api.push(item)),
        );
        return ctx.run(upload);
      },
    );
```

With the state paused, nothing is uploaded and `resend` ends:

```text
Cancelled(handler: child _Op.upload: Cancelled(rules: canStart))
```

A child the start rules turn away never runs. It is adopted first — parent and
level — and only then finished `Cancelled` with a `RulesCancelReason`: the
observer hears the drop as an outcome of this tree, with `job.level` telling it
how deep under the parent the job stands, and `child.done` holds the
cancellation. It joins no waiting list, so the parent waits for nothing; the
future of `ctx.run` carries that cancellation all the same, and it is what ends
`resend` above.

The rules `canStart` and `keepWhile`, when they throw themselves, are the other
case. The error is the rule's own, the child ends `Failed` with it, and
`ctx.run` throws it synchronously — the line after the call never runs.

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
