# Children and chains

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

Job<String> sync(int item) => enqueueJob(_sync(item));
```

`job(...)` makes a job and starts nothing. `enqueueJob` gives it a place in the
queue, and `ctx.run` inside a body makes it a child; `_sync` is written once
and goes both ways later on this page.

A child starts immediately, bypassing the queue, subject to its own start
rules: its working type, `canStart` and `keepWhile`, the ones
[The rules](state.md#the-rules) on the state page describes. The parent keeps
the queue occupied until all its children finish, even if its body returns
earlier: `sync` is over once the upload has returned its path and the API has
closed the progress.

What passes between a parent and its child beyond what this page shows is the
core's, and
[the children page](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/children.md)
of `async_job` has it. That page shows that a cancellation the parent accepts
passes to its children and that a body that fails lets them finish and waits
for them. It also says why `child.ignoreFailure()` is no substitute for
handling the future of `ctx.run`. Several children side by side are a group of
`ctx.runAll`, under
[Waiting for several children](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/groups.md#waiting-for-several-children)
on the groups page. Where those pages make a child with `Job.deferred`, a
controller makes it with `job(...)`. Its `ctx.run` and `ctx.runAll` take no
other job, and each branch of a group answers to its start rules as a child of
`ctx.run` does.

`ctx.each(stream, onData)` subscribes in a child that owns the subscription and
hands the callback each event with the child's context: that is how `_sync`
above follows the progress of the upload. [Streams](streams.md) is about such
children in a controller: what a subscription made by hand in a body does, how
long the child holds the queue, and how to follow another controller.

`api` and `analytics` belong to the application these examples come from, and
`Ready` is the state its controller works in, with the fields `sent`, `path`
and `paused`.

## The future of `ctx.run`

```dart
// The parent answers for a failed upload itself.
Job<bool> trySync(int item) => enqueue<Ready, bool>(
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
cancellation and state rules before returning the value. So a value the parent
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
Job<String> syncAndAnnounce(int item) => enqueue<Ready, String>(
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
job answers to its own rules for every one of them. A write of the child that
the parent's working type or `keepWhile` does not accept cancels the parent,
and the child with it.

Nobody waits for a future kept this way until the `await`: an upload that fails
while the parent is still sending would hand its error to the zone as an
unhandled one. `ignore()` on the kept future says that the error is not to be
reported there. The body fails with that error all the same, at the `return`,
where it hands the future on.

## Three ways to ignore a child

| In the parent | An error the future of `ctx.run` throws | A failure of the body of a child that ends `Cancelled` |
| --- | --- | --- |
| `ctx.run(child).ignore()` | dropped: nobody answers for it | goes to `onUnanswered` |
| `child.ignoreFailure()` | not handled, goes to the zone | silenced |
| `ctx.start(child)` | there is no future: a failure of the child goes to `onUnanswered` | goes to `onUnanswered` |

`ctx.run(child).ignore()` explicitly ignores that future's result while the
parent still waits for its children. `child.ignoreFailure()` alone does not
handle errors of the future returned by `ctx.run`. `ctx.start(child)` starts
the child and returns no future: its failure goes to the controller's
`onUnanswered`, as any failure nobody observed does, and the parent waits for
the child all the same. Take `ctx.start` for a child whose failure somebody
still has to answer for, and `ctx.run(child).ignore()` only for one whose
failure nobody needs: the controller's `onError` hears it, and nothing answers
for it.

If the child ends `Cancelled` and its body failed, its error is not thrown into
the parent body. That happens, for instance, when the cancellation stops an
operation and the body throws that operation's error. `await ctx.run(child)`
throws `Cancelled`, and the error goes to the controller's `onUnanswered` — by
default to `Solo.unansweredHandler`, or to the zone without one.
`child.ignoreFailure()` silences it. `ctx.run(child).ignore()` does not: it
handles what the future throws, and the future throws the cancellation. An
error the app named in `Job.isCancellationError` goes no further than the
controller's `onError`, as in [The token](cancellation.md#the-token) on the
cancellation page.

## A child the rules turn away

```dart
Job<String> resend(int item) => enqueue<Ready, String>(
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
Cancelled(handler: Job(_Op.upload): Cancelled(rules: canStart))
```

A child the start rules turn away never runs. It is adopted first — parent and
level — and only then finished `Cancelled` with a `RulesCancelReason`. The
observer hears the drop as an outcome of this tree, with `job.level` telling it
how deep under the parent the job stands, and `child.done` holds the
cancellation. It joins no waiting list, so the parent waits for nothing; the
future of `ctx.run` carries that cancellation all the same, and it is what ends
`resend` above.

`handler:` in that line is not a state handler of `enqueue`. It is
`HandlerCancelReason`, the reason the core gives a body that lets the
cancellation of its child out, and after it come the child and the cancellation
it ended with. [Cancellation details](cancellation.md#cancellation-details) has
every reason and how it prints.

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
`JobContext`, and may return a value or future. If `sync` fails, the callback
is not called, and the job `then` returned ends `Failed` with the same error.

A continuation does not inherit the controller's state context, rules, observer
or queue position. It has its own optional observer, and its name is one `then`
gives it: `Job(then)`. It belongs to whoever called `then`, not to the
controller: the controller's hooks and `Solo.observer` do not hear it. A
failure reaches whoever reads its outcome, the failure of `sync` passed down
the chain included. The continuation answers for one nobody reads, and for an
error with no outcome, itself: in `onUnanswered` of its observer when that
observer mixes in `JobAnswerer`, and otherwise in the zone where `then` was
called. `Solo.unansweredHandler` does not hear them either.

The queue does not wait for what comes after a job: the slot is freed when the
root job finishes, and the next queued job starts while the continuation still
has to run. The report above can be on its way after the job queued behind
`sync` has taken the queue, and that is what a chain is for: a step the queue
has no business waiting for. Where that would be wrong, the steps belong inside
one job, as in [Steps in a row](#steps-in-a-row) below.

Cancellation travels along a chain both ways, as the
[Chains](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/chains.md)
page of `async_job` describes. For a controller that means that `close()`
reaches a continuation through an unfinished source, but does not own one
already running after the source finished.

A continuation is never a child. Inside a controller's body `ctx.run` takes
jobs of that controller, the ones `job(...)` makes and nobody has queued, and a
continuation is none of those. It is a root job of the core, a plain `Job` and
not a `ChildJob`, so `ctx.run(tail)` does not compile:

```text
The argument type 'Job<void>' can't be assigned to the parameter type 'ChildJob<dynamic>'.
```

A job of the core made by hand with `Job.deferred` is a `ChildJob` and
compiles, and the controller refuses it with an `ArgumentError`:

```text
Invalid argument (job): was not created by this Solo: "Job()"
```

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

Job<void> recordPath(String path) => enqueueJob(_recordPath(path));
```

### The first attempt

```dart
// The first attempt: the continuation queues behind other work.
Job<void> syncAndRecord(int item) =>
    sync(item).then((ctx, path) => recordPath(path).value);
```

`then` reads like the word for "and then". Its callback gets a plain core
`JobContext`, with no `emit` on it and no state behind it, so a continuation
cannot write controller state itself. It calls `recordPath`, an ordinary job of
the controller: that job does the `emit`, and it takes its turn at the back of
the controller's queue. The end of the source does two things at once: it frees
the slot and it starts the continuation. So whatever was queued while the
source ran stands ahead of the new job: with another method of the controller,
`save()`, called while `sync` was still running, the order is `sync`, `save`,
`recordPath`. And a controller that is draining takes no new job at all: the
path is never recorded, and the continuation ends `Cancelled(closed)`.

### The second attempt

```dart
// The second attempt: sync waits for this job to end; this job waits for sync.
Job<void> syncAndRecord(int item) => enqueue<Ready, void>(
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

The hang itself shows nothing, but `Solo.debug` warns of it when the job is
queued:

```text
enqueue Job(_Op.sync) while Job(_Op.syncAndRecord) is running: it starts after Job(_Op.syncAndRecord) ends
```

A droppable method called from inside its own job sets a trap that not even
`close()` gets out of. It hands back that very job: a `sync` that queues with
`droppable` and whose body retries with `await sync(item).value` awaits itself.
`close()` marks the job cancelled, but a plain `await` does not wake for that,
and the value comes only when the body ends, so `close()` waits for good as
well. `Solo.debug` shows it on the line of the duplicate:

```text
enqueue Job(_Op.sync): duplicate of Job(_Op.sync), which is running: if awaited from inside Job(_Op.sync), it waits for itself
```

### Two children in a row

```dart
// `_sync` and `_recordPath` again, now children. The parent holds the
// queue until its children are done, so a `save()` queued meanwhile
// waits for both steps.
Job<void> syncAndRecord(int item) => enqueue<Ready, void>(
      key: _Op.syncAndRecord,
      (ctx) async {
        final path = await ctx.run(_sync(item));
        await ctx.run(_recordPath(path));
      },
    );
```

A step written as `job(...)` has both ways open: `enqueueJob` gives it a queue
slot of its own, `ctx.run` makes it a child of a job that already holds one.
Use children within one parent when the whole sequence must occupy the queue
without another root job running between its steps.
