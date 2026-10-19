# Children

A body can hand work to another job in three ways:

1. A child is started by the body and waited for by it. Several children waited
   for together make a [group](groups.md).
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
  // can adopt it.
  final tail = saving.then<void>((c, _) => report(rows));
});
```

## Children

A body delegates work to another job by registering it as a child:

```dart
final parent = Job<void>((ctx) async {
  final child = Job.deferred<int>((ctx) => ctx.abandonable(load));
  final rows = await ctx.run(child);
  ctx.log('$rows rows');
});
```

`ctx.run(child)` starts the child immediately and returns a future of its
result. The parent waits for all its children before finishing. When the parent
is cancelled, it passes the cancellation on to its children, and it does the
same when its body throws `Cancelled`. A child with `cancellable: false`
refuses the cancellation either way: it runs to its end, and the parent waits
for it and only then ends `Cancelled`. If the body throws another error, the
parent lets its children finish and waits for them.

Create children with `Job.deferred`, so the parent controls their start.
`ctx.run` takes a `ChildJob`, and a regular `Job` is not one, because such a
job starts automatically: it may start before the parent registers it and then
run outside the parent's cancellation and completion handling.

`run` waits for the child to finish, including its children and cleanup, and
checks the parent's cancellation before returning the value to the body. If the
child refuses cancellation, `run` still waits for it; after the child succeeds,
`run` throws the parent's cancellation instead of continuing to the log call. A
child's error or cancellation is thrown through the returned future with its
stack trace. Use `child.cancel()` to request cancellation and `child.done` to
inspect the outcome.

A child inherits the parent's observer unless it has its own. If a child's
cancellation escapes through `await ctx.run(child)` or `child.value`, the
parent ends with `HandlerCancelReason` and a description naming the child.

### A child the body does not await

```dart
final parent = Job<void>((ctx) async {
  final rows = ctx.run(Job.deferred<int>((c) => c.abandonable(loadRows)));
  final child = Job.deferred<void>((c) => c.abandonable(warmCache));
  ctx.run(child).ignore();
  ctx.log('${await rows} rows');
});
```

Both children start at once. `rows` is the future `ctx.run` returned, kept and
awaited later; a future kept this way must be awaited or have its errors
handled. `child` warms a cache nobody reads here, and `ctx.run(child).ignore()`
says the result is not wanted. The parent still waits for both before
finishing. `child.ignoreFailure()` is no substitute for
`ctx.run(child).ignore()`. `child.ignoreFailure()` quenches the core's report
of a failure nobody looked at, and here `run` looks — it waits for the child's
value. If `child` fails, its error arrives through the future `run` returned,
an ordinary Dart future: left unhandled, it goes to the zone, and so does the
child's `Cancelled`. `ctx.run(child).ignore()` silences the error of that
future and nothing more: the child's observer still hears the error through
`onError`.

If the child ends `Cancelled` and its body failed, the error does not arrive
through that future. That happens, for instance, when the cancellation stops an
operation and the body throws that operation's error. `await ctx.run(child)`
throws `Cancelled`, and the error goes where an error nobody handled goes: to
the child's observer and, unless that observer catches it in `onUnanswered`, to
the zone, as in [Where errors go](observing.md#where-errors-go) on the
observing page. An error the app names in `Job.isCancellationError` goes no
further than the child's observer, as in
[Errors of a cancellation](observing.md#errors-of-a-cancellation).
`child.ignoreFailure()` silences the error, whatever it is.
`ctx.run(child).ignore()` does not: it silences what the future throws, and the
future throws the cancellation. To send the error somewhere else, give the
child an observer that catches it: a `JobAnswerer` with `onUnanswered`
overridden.

### When `ctx.run` refuses a child

`ctx.run` takes a `ChildJob`: a `Job.deferred`, or a job of an engine that
declares it. A job that starts by itself, one from `Job(body)`, `then` or
`Job.each`, is not one, and the compiler turns it away. What the type does not
show, `ctx.run` refuses synchronously, before the child runs:

| The child | What `ctx.run` does |
| --- | --- |
| A job from another implementation | Throws `ArgumentError` |
| A job that has already started or finished | Throws `StateError` |
| Any job, once the parent body has ended | Throws `StateError` |
| Any job, once the parent is cancelled | Cancels the child before its start and throws the parent's `Cancelled` |

An `ArgumentError` or a `StateError` leaves the child untouched, with the code
that made it: a `Job.deferred` that `ctx.run` refused that way stays unstarted,
and its `done` waits until that code starts or cancels it.
[`ctx.runAll`](groups.md) makes the same checks for every job of its list
before the first start and refuses the same job twice with an `ArgumentError`;
such a refusal leaves every job of the list untouched.

### How deep a tree goes

```dart
ChildJob<void> level(int depth) {
  return Job.deferred<void>((ctx) async {
    // Without this await, the whole chain is built on one stack.
    await null;
    if (depth > 0) await ctx.run(level(depth - 1));
  });
}
```

How deep a tree may go is bounded by the stack, and by two different walks of
it. Starting a child runs the child's body up to its first `await`. Without the
`await null` above, each level makes its own child before it suspends, and the
whole chain is built on one stack: about a thousand levels on a desktop VM, and
the overflow lands while the tree is still being built. A tree that overflows
there still ends: `ctx.run` throws the `StackOverflowError` into the body that
called it, and the jobs whose start the overflow cut short end once that body
is over. With `await null`, building goes by microtasks, and the limit moves to
the other walk — cancellation, which descends the tree recursively and reaches
about three thousand. Neither number is a promise; both follow from the size of
a body's frame.

A cascade that runs out of stack stops where the stack ran out, and the jobs
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
