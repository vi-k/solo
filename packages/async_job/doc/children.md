# Children, streams and chains

## Children

A body delegates work to another job by registering it as a child:

```dart
final parent = Job<void>((ctx) async {
  final child = Job.deferred<int>((ctx) => ctx.wait(load));
  final rows = await ctx.run(child);
  ctx.log('$rows rows');
});
```

`ctx.run(child)` starts the child immediately and returns a future of its
result. The parent waits for all its children before finishing and passes
cancellation to them. A child with `cancellable: false` can refuse that
cancellation. If the parent body throws `Cancelled`, its children are cancelled
too. If it throws another error, the parent lets its children finish and waits
for them.

Create children with `Job.deferred`, so the parent controls their start.
`ctx.run` rejects a regular `Job`, even before its scheduled start. This avoids
a race where the child starts independently and is left outside the parent's
cancellation and completion handling.

`run` waits for the child to finish, including its children and cleanup, and
checks the parent's cancellation before returning the value to the body. If the
child refuses cancellation, `run` still waits for it; after the child succeeds,
`run` throws the parent's cancellation instead of continuing to the log call. A
child's error or cancellation is thrown through the returned future with its
stack trace.

Use `child.cancel()` to request cancellation and `child.done` to inspect the
outcome. To start a child concurrently, retain the future returned by
`ctx.run(child)` and await it later, or handle its errors. Use
`ctx.run(child).ignore()` when deliberately ignoring that result. The parent
still waits for the child before finishing. Ignoring the handle with
`child.ignore()` alone does not handle errors of the `run` future; an unhandled
future error, including cancellation, follows Dart's rules.

A child inherits the parent's observer unless it has its own. If a child's
cancellation escapes through `await ctx.run(child)` or `child.value`, the
parent ends with `HandlerCancelReason` and a description naming the child.

`ctx.run` throws synchronously for an invalid start: `ArgumentError` for a job
from another implementation or a job that starts automatically. It throws
`StateError` if the child has already started or the parent body has ended. If
the parent is already cancelled, it cancels the child before start and throws
the parent's `Cancelled`.

## Processing streams

`ctx.each(stream, onData)` subscribes to a stream and processes its events one
at a time. It immediately returns a child `Job<void>` that owns the
subscription. The callback receives that child's context and an event.

For example, `saveMessages` below accepts a stream of messages and an
asynchronous function that saves one message. `each` waits for each save before
passing the next message to the callback:

```dart
Future<void> saveMessages(
  Stream<String> messages,
  Future<void> Function(String message) save,
) async {
  final job = Job<void>((ctx) async {
    final processing = ctx.each(messages, (child, message) {
      return child.join(() => save(message));
    });
    await processing.value;
  });

  await job.value;
}
```

`processing.value` completes when the stream ends and the last save finishes. A
stream or callback error ends processing; awaiting `value` throws it into the
parent body and then to the caller of `saveMessages`. A thrown `Cancelled`
follows the cancellation path. Use the child's context inside the callback, as
`child.join` does here, so its cancellation is checked around the save
operation.

The returned job also lets the parent stop listening separately. This example
prints a tick every second, stops listening after 2.5 seconds, and continues
the parent body:

```dart
Future<void> watchTicks() async {
  final job = Job<void>((ctx) async {
    final ticks = ctx.each(
      Stream<int>.periodic(const Duration(seconds: 1), (index) => index + 1),
      (child, tick) => print('Tick $tick'),
    );

    await ctx.wait(
      () => Future<void>.delayed(const Duration(milliseconds: 2500)),
    );
    await ticks.cancel();
    print('Parent continues');
  });

  await job.value;
}
```

The output is `Tick 1`, `Tick 2`, then `Parent continues`. The stream has not
ended when `ticks.cancel()` cancels the subscription. The call waits for the
child to finish; cancelling that child does not itself cancel the parent.

Use `childJob.value` when its failure or cancellation should be thrown into the
body, or `childJob.done` to inspect its outcome without throwing. An uncaught
`Cancelled` from the child's `value` cancels the parent under the usual child
outcome rules.

The parent waits for the child even if its body returns without awaiting it. An
open stream therefore keeps the parent alive until the stream ends or the child
is cancelled. Accepted parent cancellation cascades to the child. The observer
sees this child as a separate job.

When the child accepts cancellation, it immediately cancels the subscription
and stops delivering events. It then waits for any running callback before
completing and releasing resources, so parent cleanup also waits. Use the
child's context checkpoints inside the callback: a plain `await` cannot be
interrupted and can delay cancellation forever. Do not await the child's own
completion or `cancel()` from its callback; the child is already waiting for
that callback.

The future returned by the underlying subscription's `cancel()` is not awaited.
If the source needs asynchronous cleanup, arrange to await that cleanup
separately. Normal stream completion still depends on the source sending
`onDone`. Like `run`, `each` can only start children while the parent body is
active; calls from `unattended` or cleanup are rejected.

## Chains

Use `then` to continue a job with its result. Each call returns a new `Job` and
gives its callback a separate context. The next callback starts after the
previous job succeeds, including its children and cleanup:

```dart
final loaded = Job<String>((ctx) => ctx.join(loadText));
final parsed = loaded.then<int>((ctx, text) => int.parse(text));
final saved = parsed.then<void>((ctx, number) => ctx.join(
      () => saveNumber(number),
    ));

await saved.value;
```

Cancelling `saved` also asks unfinished `parsed` and `loaded` to cancel.
Cancelling `parsed` asks unfinished `loaded` to cancel and cancels `saved`.
Cancelling `loaded` passes cancellation forward through both continuations.
Each forwarded request carries `ChainCancelReason` with the adjacent job's
`Cancelled` in `cause`. Completed jobs keep their outcomes. If you attach
several continuations to one job, cancelling one can cancel their shared source
and the other continuations too.

`await saved.cancel()` waits for the unfinished predecessors, their children
and cleanup, and any work and cleanup already started by `saved`. Sources
retain their normal cancellation rules: `cancellable: false` refuses a request,
and `uncancellable` holds it. A cancelled continuation still waits for that
source, then finishes without calling its callback. While waiting, it can be
`isCancelled` without being `isFinished`; its outcome has `started: false` if
it was cancelled while waiting for its source.

A failed predecessor forwards its error and stack without calling the callback.
Observe the tail through `value`, `done` or `ignore` to handle that failure. If
a cancelled continuation cannot forward a source failure, it does not observe
it either: for example, a source that refuses cancellation and later fails
still needs its own error handling.

The callback accepts a value or future. Returning another `Job` does not wait
for it; return `ctx.run(child)` for a deferred child. `then` does not start a
deferred source, and a continuation cannot be adopted through `ctx.run`. Do not
await a continuation from its source's body or cleanup: the continuation is
waiting for that source to finish.

Each continuation is a root job of the core. It has an optional `observer`
argument and inherits neither the source's observer nor domain state, rules or
a queue slot. Cleanup registered by the source has already run when the
continuation receives its value; a resource closed by the source's `onDispose`
is therefore already closed at that point.

### A chain is not a child

```dart
final child = Job.deferred<int>((ctx) => ctx.wait(load));
final tail = child.then<void>((ctx, rows) => report(rows * 2));

final parent = Job<void>((ctx) async {
  // The head is a child: the parent starts it and waits for it.
  ctx.log(await ctx.run(child));
  // await ctx.run(tail) would throw ArgumentError here: a continuation
  // starts itself when its source finishes.
});

await parent.value; // Done, whatever the tail is doing.
await tail.value; // The tail is yours to observe.
```

`ctx.run` takes a job nobody starts by itself, and a continuation is not one of
those: it starts when its source finishes. The length of the chain changes
nothing — `child.then(...).then(...)` is a continuation of a continuation, and
every link refuses adoption the same way. The head is the only job in a chain a
parent can adopt.

The parent waits for its children, not for what hangs off them. Once
`ctx.run(child)` has returned and the body ends, the parent finishes `Done`
while a slow tail is still running. Cancellation still reaches that tail,
through the source rather than through the parent: cancelling the parent
cancels the child, and the child's cancellation travels forward to the tail as
`ChainCancelReason`.

A failure in the tail is nobody's business but the tail's. Observe it through
`value`, `done` or `ignore`; an unobserved one goes to the zone that created
the chain, after the parent has already finished. So: a sequence that belongs
to the operation is children — `await ctx.run(a)`, then `await ctx.run(b)`. A
sequence that deliberately outlives it is a chain, and its outcome comes back
to you, not to the parent.
