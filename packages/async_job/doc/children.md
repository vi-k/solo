# Children

A body can hand work to another job in three ways:

1. The body starts a child with `ctx.run` and waits for it, or with `ctx.start`
   and leaves its outcome to whoever holds it. Several children waited for
   together make a [group](groups.md).
2. A [stream](streams.md) is processed one event at a time in a child that owns
   the subscription.
3. A [continuation](chains.md) made by `then` starts when the job it follows
   succeeds, and outlives it.

The words for the three are close, and the wrong one compiles as well as the
right one. Each in its place:

```dart
final job = Job<void>((ctx) async {
  // A child: the body starts it, waits for it, and cancels along with it.
  final rows =
      await ctx.run(Job.deferred<int>((c) => c.abandonable(loadRows)));

  // A stream: one event at a time, in a child of its own.
  final saving = ctx.each(events, (c, e) => c.join(() => save(e)));

  // A chain: it starts itself when its source succeeds, and no parent
  // can adopt it, so the body waits for it as for any future.
  final tail = saving.then<void>((c, _) => report(rows));
  await ctx.abandonable(() => tail.value);
});
```

In the sections below, the lines under a block of code are what that code
prints:

- `cancel`: the user cancels the parent;
- `Job(…)`: a message a body logged, or how a job ended, as the `Log` observer
  from [Observer](observing.md#observer) on the observing page prints them;
- `zone:` an error that reached the zone uncaught.

## Running a child

A job loads rows in a child and logs how many there are. The job has the `Log`
observer, and the child has none of its own:

```dart
final parent = Job<void>(key: 'parent', observer: Log(), (ctx) async {
  final child = Job.deferred<int>(key: 'rows', (c) => c.abandonable(load));
  final rows = await ctx.run(child);
  ctx.log('$rows rows');
});
```

```text
Job(rows): Done(21)
Job(parent): 21 rows
Job(parent): Done(null)
```

`ctx.run(child)` starts the child at once and returns a future of its value.
The future completes once the child is over, its own children and cleanup
included. The child takes the parent's observer, so the observer prints the
child's outcome as well. A child with an `observer` of its own keeps it. The
parent waits for every child it ran before it ends. The body keeps `child` to
cancel it with `child.cancel()` or read its outcome from `child.done`.

A child is made with `Job.deferred`, which leaves its start to whoever runs it.
`ctx.run` takes a `ChildJob`: a `Job.deferred`, or a job of an engine that
declares it. `Job(body)`, `then` and `Job.each` make jobs that start by
themselves. Such a job could start before the parent takes it in and run
outside the parent's cancellation, so the compiler turns it away.

## When the parent is cancelled

The user leaves the screen while the rows load, and the parent is cancelled:

```text
cancel
Job(rows): Cancelled(parent)
Job(parent): Cancelled(manual)
```

The parent passes the cancellation to its child and ends after it. The child
waits for `load` through `ctx.abandonable`, so it ends at once, and `load` runs
on with nobody waiting for it.

A child made with `cancellable: false` refuses the cancellation:

```dart
final child = Job.deferred<int>(
  key: 'rows',
  cancellable: false,
  (c) => c.abandonable(load),
);
```

```text
cancel
Job(rows): Done(21)
Job(parent): Cancelled(manual)
```

The child loads its rows, and the parent waits for it. Before `ctx.run` hands
the value to the body, it checks the parent's cancellation. The parent is
cancelled, so `ctx.run` throws the parent's `Cancelled`, and the line that logs
the rows never runs.

What the parent does to its children depends on how it ends:

| What happens to the parent | Its children | The parent ends |
| --- | --- | --- |
| It is cancelled | Are cancelled, except those made with `cancellable: false` | `Cancelled`, once they are over |
| Its body throws `Cancelled` | Are cancelled the same way | `Cancelled`, once they are over |
| Its body throws another error | Run to their end | `Failed`, once they are over |
| Its body returns | Run to their end | `Done`, once they are over |

A child's error comes back through the future `ctx.run` returned, with the
child's stack trace, and so does its `Cancelled`. A child's `Cancelled` that
the body lets out of `await ctx.run(child)` or `child.value` cancels the
parent. The parent then ends with a `HandlerCancelReason` whose description
names the child.

## A child the body does not await

A job loads rows and warms a cache at the same time. Nobody reads the cache
here, and the parent should still end only after it.

### The first attempt

```dart
// The first attempt: ignore() drops the failure of the cache.
final parent = Job<void>(key: 'parent', observer: Log(), (ctx) async {
  final rows = Job.deferred<int>(key: 'rows', (c) => c.abandonable(loadRows));
  final cache =
      Job.deferred<void>(key: 'cache', (c) => c.abandonable(warmCache));
  ctx.run(cache).ignore();
  final count = ctx.run(rows);
  ctx.log('${await count} rows');
});
```

Both children start at once, and the parent waits for both before it ends,
awaited or not. When the cache fails, the log shows it, and that is all:

```text
Job(rows): Done(21)
Job(parent): 21 rows
Job(cache): Failed(Bad state: cold)
Job(parent): Done(null)
```

The future of `ctx.run` is an ordinary Dart future. It throws the child's error
if the child fails, and the child's `Cancelled` if the child is cancelled.
`ctx.run` observes the child's outcome to complete it, so the core does not
answer for the failure: the future carries it. `ignore()` drops the future, and
the error with it. The observer still hears it in `onError`, and nothing
answers for it. `cache.ignoreFailure()` would change nothing: it quenches the
answer for a failure nobody looked at, and `ctx.run` has looked.

### Starting without a future

```dart
final parent = Job<void>(key: 'parent', observer: Log(), (ctx) async {
  final rows = Job.deferred<int>(key: 'rows', (c) => c.abandonable(loadRows));
  final cache =
      Job.deferred<void>(key: 'cache', (c) => c.abandonable(warmCache));
  ctx.start(cache);
  final count = ctx.run(rows);
  ctx.log('${await count} rows');
});
```

```text
Job(rows): Done(21)
Job(parent): 21 rows
Job(cache): Failed(Bad state: cold)
Job(parent): Done(null)
zone: Bad state: cold
```

`ctx.start(child)` starts the child at once, as `ctx.run` does, and returns
nothing. Nothing observes the child, so its failure goes the way of a failure
nobody observed: to `onUnanswered` of its observer if the observer mixes in
`JobAnswerer`, and otherwise to the zone, as here. A cancellation of the child
goes nowhere, and neither changes the outcome of the parent. When nobody needs
the failure, `cache.ignoreFailure()` says so, and the observer still hears it
in `onError`, as
[Telling the core it is handled](outcomes.md#telling-the-core-it-is-handled)
describes.

## When a cancelled child fails

A child migrates the database, and a cancellation stops the migration at its
token, as in
[A token through `onCancel`](cancellation.md#a-token-through-oncancel) on the
cancellation page. A parent like the one in [Running a child](#running-a-child)
runs it. The app has not named `DatabaseStopped` in `Job.isCancellationError`,
and the user leaves the screen while the migration runs:

```dart
final child = Job.deferred<void>(key: 'migration', (ctx) async {
  final stop = CancelToken();
  ctx.onCancel(stop.cancel);

  await ctx.join(() => database.migrate(stop));
});
await ctx.run(child);
```

```text
cancel
Job(migration): Cancelled(parent)
zone: DatabaseStopped
Job(parent): Cancelled(manual)
```

The migration stops by throwing its own `DatabaseStopped`, and the child's body
fails with it. The child still ends `Cancelled`, and `await ctx.run(child)`
throws that `Cancelled`. The body's error does not come with it. It goes where
an error that no outcome carries goes: to the child's observer and, unless that
observer catches it in `onUnanswered`, to the zone.
[Where errors go](errors.md#where-errors-go) on the errors page has the whole
route.

Three things keep that error out of the zone:

- `Job.isCancellationError`, where the app names the error once. Then it goes
  no further than the child's observer, as in
  [Errors of a cancellation](errors.md#errors-of-a-cancellation).
- An observer of the child that catches the error: a `JobAnswerer` with
  `onUnanswered` overridden.
- `child.ignoreFailure()`, which silences the error, whatever it is.

`ctx.run(child).ignore()` does not help here. It silences what the future
throws, and the future throws the cancellation.

## When `ctx.run` refuses a child

What the type of `ctx.run` does not show, `ctx.run` refuses synchronously,
before the child runs:

| The child | What `ctx.run` does | What happens to the child |
| --- | --- | --- |
| A job from another implementation | Throws `ArgumentError` | Nothing |
| A job that has already started or finished | Throws `StateError` | Nothing |
| Any job, once the parent body has ended | Throws `StateError` | Nothing |
| Any job, once the parent is cancelled | Throws the parent's `Cancelled` | It is cancelled before its start |

A child refused with `ArgumentError` or `StateError` stays with the code that
made it. A `Job.deferred` stays unstarted, and its `done` waits until that code
starts or cancels it.

[`ctx.runAll`](groups.md) makes the same checks for every job of its list
before the first start. It also refuses the same job twice with an
`ArgumentError`. A refusal with `ArgumentError` or `StateError` leaves every
job of the list as it was: the group starts none of them, the sound ones
included, and the `done` of each waits until the code that made it starts or
cancels it. A body that has caught the refusal and awaits a job of the list
waits for good. Under a cancelled parent, every job of the list is cancelled
before its start.

## How deep a tree goes

A tree of children can be as deep as the stack lets it be. Each level here runs
the next one as a child:

```dart
ChildJob<void> level(int depth) {
  return Job.deferred<void>((ctx) async {
    // Without this await, the whole chain is built on one stack.
    await null;
    if (depth > 0) await ctx.run(level(depth - 1));
  });
}
```

Two walks of the tree use the stack, and either of them can bound the depth.

The first walk builds the tree. Starting a child runs its body up to its first
`await`. Without the `await null` above, each level makes its own child before
it suspends, so the whole chain is built on one stack. On a desktop VM that
stack runs out at about a thousand levels, while the tree is still being built.
Such a tree still ends: `ctx.run` throws the `StackOverflowError` into the body
that called it. The jobs whose start the overflow cut short end once that body
is over.

With `await null`, each level is built on a microtask of its own, and the limit
moves to the second walk, the cancellation. A cancellation descends the tree
recursively and runs out of stack at about three thousand levels. Neither
number is a promise; both follow from the size of a body's frame.

A cancellation that runs out of stack stops where it ran out, and the jobs
below that depth go on running. The overflow comes out of `cancel()` itself,
before it returns a future, so `cancel().ignore()` does not catch it. Recursion
measured in thousands of nested jobs wants flattening, not a deeper stack.

## Processing streams

`ctx.each(stream, onData)` subscribes to a stream and processes its events one
at a time, in a child `Job<void>` that owns the subscription. The parent waits
for that child even if its body returns without awaiting it. The page on
[streams](streams.md) has the rest: what `await for` and `listen` do in a body
instead, how a callback stops for a cancellation, where the cleanup of one
event belongs, and `Job.each` for a job that is nothing but a stream.
