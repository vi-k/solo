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

To wait for several children at once, write `[ctx.run(a), ctx.run(b)].wait`
rather than `Future.wait`. Both wait for all of them; the difference is what
survives. `.wait` collects every error into one `ParallelWaitError`, and the
kernel reads that envelope: one carrying cancellations and successes ends the
parent with that cancellation, exactly as awaiting a single child does, while
one carrying a real failure stays a failure, with its errors and values
untouched. `Future.wait` keeps the first error to reach it and lets the rest
go: what they were stays out of the parent's outcome, and a cancellation among
them leaves no trace at all. Each failed child still announces its own failure
to its observer -- and only there, so a parent whose children have no observer
loses those errors entirely: the body took their futures, and that counts as
answering for them.

`eagerError: true` changes one thing only: when the body wakes. It buys no
early end -- nothing asks the other branches to stop and the kernel waits for
its children regardless, so the job still ends when the last of them does. What
the body can then do in between is the whole of the difference, and it is not
the difference it is usually taken for. Either way, a body that catches the
error and returns ends the job `Done` with a branch failed, and a value a
branch returned after the first error is gone: `Future.wait` drops the values
of the branches that did succeed, so a resource among them is closed by nobody.
`.wait` is the one that keeps them -- they are in `ParallelWaitError.values`,
where a body that catches the envelope can still release them. Inside a body,
take `ctx.runAll` when one failure makes the rest pointless, and
`[ctx.run(a), ctx.run(b)].wait` when it does not.

Neither of them stops a branch early. `.wait` returns once every branch is
done, so a sibling of a cancelled child runs to its end; what the parent's
cancellation reaches is the children it started outside that waiting. A
resource a branch opened is still released on time when the branch took it
through `ctx.wait(() => open(), dispose: (value) => value.close())`: the
cleanup belongs to the job, not to the waiting.

When one failure makes the rest of the work pointless, `ctx.runAll` runs the
children together and stops the others at the first sign of trouble:

```dart
final values = await ctx.runAll([
  Job.deferred<int>((ctx) => ctx.wait(loadRows)),
  Job.deferred<int>((ctx) => ctx.wait(loadExtra)),
]);
```

It starts every child synchronously, in the order of the list, and returns
their values in that order. As soon as the body of any branch ends in anything
but a value, the others are asked to stop with `SiblingCancelReason`; the
branch the trouble came from is not, or its error would turn into a
cancellation and be lost. What comes out is decided by the final outcomes: a
real failure if there is one, otherwise the first cancellation that arrived,
thrown as the object that outcome carries -- exactly what
`await ctx.run(child)` would have thrown. A failure the group received and did
not throw is not dropped; it goes where an error nobody answered for goes, and
goes there once.

When which: `[ctx.run(a), ctx.run(b)].wait` waits for every branch and stops
none, so use it when the branches are independent of each other's failure, or
when one of them waits for another. `ctx.runAll` stops the rest, so use it when
a result missing one of its parts is of no use anyway.

Ownership is the same rule as everywhere else, and a group is where it starts
to matter. A resource a branch keeps for itself goes to `onDispose`, and the
end of the branch closes it whatever the outcome. A resource a branch hands out
goes to `onDiscard`, or to the `discard` of `ctx.wait` and `ctx.join`: it then
lives until the group succeeds in full and reaches the caller open. When the
group ends in anything else, the branch that accepted the stop closes what it
took, and it closes it before the group returns -- so by the time the parent
catches the error, that much is already closed.

A branch that did not take the resource itself but got it from a child of its
own registers it on arrival, the way every receiver does: the child ended
`Done` inside the branch, and a child's registration is settled by the child's
outcome. `ctx.wait(() => ctx.run(opener), discard: ...)` puts the registration
on the branch, and everything above then holds for it. See
[Cleanup](cleanup.md).

One thing stays open, and it follows from a rule written elsewhere. A branch
created with `cancellable: false` refuses the stop and ends `Done`: it hands
its value over through its own `Job.value`, so its `discard` does not run and
the resource is the caller's to close, through the handle it passed in.

Four things `runAll` does not promise.

**The stop is cooperative.** A branch waiting through `ctx.wait` ends, and the
operation behind it plays on and writes its result. To stop the work itself,
hand the cancellation to it with `ctx.onCancel` and wait for it with
`ctx.join`. A branch created with `cancellable: false` refuses the stop
outright, and the group waits for it.

**The descendants of the branch that failed play out.** A failure never
cascades, so the children that branch started are not cancelled, and the group
waits for them as it waits for everything else.

**The outcome of a branch is not final until the group decides.** A body that
returned a value can still end `Cancelled`, and until the group has committed,
neither `child.outcome` nor `child.isCancelled` is the last word.

**A branch must not wait for another branch of the same group.** Awaiting a
sibling's `Job.value` never finishes: the sibling is held until the group
decides, and the group decides only once every branch is held. Nothing catches
that. For branches that depend on each other, `[...].wait` is the answer.

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

A `discard` of the source is the other way round: the source ended `Done`, so
it never ran and never will, and the continuation is the receiver -- it takes
the value as its argument and registers the release in its own body. One case
has no receiver at all: a continuation cancelled while it waited finishes
without ever calling its callback, so there is no body and no moment. The
resource is then the caller's to close, through the source's handle, exactly as
for a branch that refuses a group's stop.

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
