# Children, streams and chains

A body can hand work to another job. A child is started by the body and waited
for by it; a stream is processed one event at a time in a child that owns the
subscription; a continuation starts when the job it follows finishes, and
outlives it. The words for the three are close, and the wrong one compiles:

```dart
(ctx) async {
  // A child: the body starts it, waits for it, and cancels along with it.
  final rows = await ctx.run(Job.deferred<int>((c) => c.wait(loadRows)));

  // A stream: one event at a time, in a child of its own.
  final saving = ctx.each(events, (child, e) => child.join(() => save(e)));

  // A chain: it starts itself when its source finishes, and no parent
  // can adopt it.
  final tail = saving.then<void>((c, _) => report(rows));
}
```

Four sections below open with the version this vocabulary leads to -- the plain
`Future.wait` that every Dart program already has in it, or the method whose
name matches the requirement -- and say what that version does instead of what
it was meant to do. The first attempt is not a strawman: it is the code the
API's own names ask for. Where the next version repairs that and brings a fault
of its own, it stands as a second attempt. The version that works follows under
its own heading.

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
still waits for the child before finishing. `child.ignore()` does not do it: it
quenches the engine's report of a failure nobody looked at, and `run` already
looks -- it waits for the child's value. The error arrives through the future
`run` returned, an ordinary Dart future: left unhandled, it goes to the zone,
and so does a cancellation of the child.

A child inherits the parent's observer unless it has its own. If a child's
cancellation escapes through `await ctx.run(child)` or `child.value`, the
parent ends with `HandlerCancelReason` and a description naming the child.

`ctx.run` throws synchronously for an invalid start: `ArgumentError` for a job
from another implementation or a job that starts automatically. It throws
`StateError` if the child has already started or the parent body has ended. If
the parent is already cancelled, it cancels the child before start and throws
the parent's `Cancelled`.

How deep a tree may go is bounded by the stack, and by two different walks of
it. Starting a child runs the child's body up to its first `await`, so a body
that makes its own child before it suspends builds the whole chain on one
stack: about a thousand levels on a desktop VM, and the overflow lands while
the tree is still being built. A single `await` before `ctx.run` breaks that
into microtasks and lifts the limit to the other walk -- cancellation, which
descends the tree recursively and reaches about three thousand. Neither number
is a promise; both follow from the size of a body's frame, and the second one
moves between runs of the same program as the compiler optimizes the descent
under way.

A cascade that runs out of stack tells every job it marked to stop, save a
handful at the deep end: down there the stack has only just run out, and a
callback that asks for a few frames of its own may not get them. An overflow
landing there is not announced as a failure of that callback, because it is not
one; anywhere else a callback that runs out of stack by itself is reported like
any other failure of one, and changes nothing about the cancellation. What the
cascade never reached -- the depth below the break -- is left running.
Recursion measured in thousands of nested jobs wants flattening, not a deeper
stack.

## Waiting for several children

An export needs two sources: the rows and the images. Neither waits for the
other, so both should open at once, and each branch closes what it opened
unless it hands it over. Whatever goes wrong, the parent has to end with the
truth about it, and nothing may stay open.

### The first attempt

```dart
final parent = Job<void>((ctx) async {
  final rows = Job.deferred<Source>(
    (ctx) => ctx.wait(openRows, discard: (source) => source.close()),
  );
  final images = Job.deferred<Source>(
    (ctx) => ctx.wait(openImages, discard: (source) => source.close()),
  );

  final sources = await Future.wait([ctx.run(rows), ctx.run(images)]);
  await ctx.join(() => writeArchive(sources));
});
```

`Future.wait` keeps the first error that reaches it and lets the rest go, and
that decides the parent's outcome by a race. A failure that arrives before the
other branch is cancelled ends the parent `Failed`; a cancellation that arrives
first ends it `Cancelled(HandlerCancelReason)`, and the failure of the other
branch is nowhere in the outcome. Each failed child does still announce its own
failure to its observer -- and only there, so a parent whose children have no
observer of their own loses that error entirely: the body took their futures,
and that counts as answering for them.

The source the other branch opened is lost with the values. A branch that
returns what it opened hands it over -- that is what `discard` means, and the
branch ended `Done`, so its own cleanup never closes it. The receiver is the
body, and the body never gets it: `Future.wait` completes with the error and
drops the values of the branches that succeeded. Nobody closes that source.

### The second attempt

```dart
final sources = await Future.wait(
  [ctx.run(rows), ctx.run(images)],
  eagerError: true,
);
```

`eagerError: true` changes one thing only: when the body wakes. It buys no
early end -- nothing asks the other branches to stop, and the kernel waits for
its children regardless, so the job still ends when the last of them does. What
the body can do in between is the whole of the difference, and it is not the
difference the flag is usually taken for. The outcome is still decided by
whichever trouble came first, and the source the other branch opened is still
lost with the values.

### One envelope for every error and every value

```dart
final sources = await [ctx.run(rows), ctx.run(images)].wait;
await ctx.join(() => writeArchive(sources));
```

`.wait` collects every error into one `ParallelWaitError`, and the values of
the branches that did succeed go into the same envelope. The kernel reads it:
an envelope carrying a real failure stays a failure, with its errors and values
untouched, and one carrying only cancellations and successes ends the parent
with that cancellation, exactly as awaiting a single child does. The order the
trouble arrived in no longer decides anything.

A body that catches the envelope can still release what the successful branches
returned, because they are in it:

```dart
try {
  final sources = await [ctx.run(rows), ctx.run(images)].wait;
  await ctx.join(() => writeArchive(sources));
} on ParallelWaitError<List<Source?>, List<AsyncError?>> catch (error) {
  for (final source in error.values.whereType<Source>()) {
    source.close();
  }
  rethrow;
}
```

Neither form stops a branch early. `.wait` returns once every branch is done,
so a sibling of a cancelled child runs to its end; what the parent's
cancellation reaches is the children it started outside that waiting. A
resource a branch opened for itself is still released on time when the branch
took it through `ctx.wait(() => open(), dispose: (value) => value.close())`:
the cleanup belongs to the job, not to the waiting.

### When one failure makes the rest pointless

```dart
final values = await ctx.runAll([
  Job.deferred<int>((ctx) => ctx.wait(loadRows)),
  Job.deferred<int>((ctx) => ctx.wait(loadExtra)),
]);
```

`ctx.runAll` starts every child synchronously, in the order of the list, and
returns their values in that order. As soon as the body of any branch ends in
anything but a value, the others are asked to stop with `SiblingCancelReason`;
the branch the trouble came from is not, or its error would turn into a
cancellation and be lost. What comes out is decided by the final outcomes: a
real failure if there is one, otherwise the first cancellation that arrived,
thrown as the object that outcome carries -- exactly what
`await ctx.run(child)` would have thrown. A failure the group received and did
not throw is not dropped; it goes where an error nobody answered for goes, and
goes there once.

| Form | Waits for | Stops the others | Values of the branches that succeeded |
| --- | --- | --- | --- |
| `Future.wait` | every branch | no | dropped |
| `Future.wait(eagerError: true)` | the first error, then the job waits anyway | no | dropped |
| `[...].wait` | every branch | no | in `ParallelWaitError.values` |
| `ctx.runAll` | every branch | yes, with `SiblingCancelReason` | returned in order, or lost with the group |

Use `[ctx.run(a), ctx.run(b)].wait` when the branches are independent of each
other's failure, or when one of them waits for another. Use `ctx.runAll` when a
result missing one of its parts is of no use anyway.

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

## What a group hands back

A branch says which of the two a resource is by the member it registers the
release with:

```dart
Job.deferred<Source>((ctx) async {
  final cache = await ctx.wait(openCache, dispose: (c) => c.close());
  final rows = await ctx.wait(openRows, discard: (source) => source.close());
  await ctx.join(() => cache.warm(rows));

  return rows;
});
```

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
outcome. `ctx.run(opener, discard: ...)` puts the registration on the branch,
and everything above then holds for it. See [Cleanup](cleanup.md).

One thing stays open, and it follows from a rule written elsewhere. A branch
created with `cancellable: false` refuses the stop and ends `Done`: it hands
its value over through its own `Job.value`, so its `discard` does not run and
the resource is the caller's to close, through the handle it passed in.

The list itself is a value like any other, and the body is its receiver: unlike
`run`, `runAll` takes no `dispose` or `discard` of its own to register it with
on arrival.

### The first attempt

```dart
final sources = await ctx.runAll(branches);
await ctx.join(loadManifest);
await ctx.wait(
  () => sources,
  discard: (values) {
    for (final source in values) {
      source.close();
    }
  },
);
```

The registration reads like the rest of the body, and most of the time it
works: the action hands the list straight back, the `discard` goes on the job,
and a cancellation that arrives later closes every source in the list. What it
cannot survive is a cancellation that arrives **before** this line -- during
the manifest above it, or anywhere else the body waits after the group
returned. `ctx.wait` opens with a checkpoint of its own, before the action ever
runs, so a pending cancellation comes out of that checkpoint as `Cancelled`.
The line throws instead of registering, the list is already in the body's hands
and now unreachable, and nothing announces the leak: what the caller sees is an
ordinary cancellation.

### The next line

```dart
final sources = await ctx.runAll(branches);
ctx.onDispose(() {
  for (final source in sources) {
    source.close();
  }
});
```

`ctx.onDispose` and `ctx.onDiscard` run no check first, so there is no
checkpoint left for a pending cancellation to win, and the registration happens
even on a job already marked. Put it on the very next line after the group
returns: `onDispose` when the list is the body's own, `onDiscard` when the list
is what the body returns or hands on further -- the same choice as anywhere
else in this rule.

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
follows the cancellation path.

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

Like `run`, `each` can only start children while the parent body is active;
calls from `unattended` or cleanup are rejected. The future returned by the
underlying subscription's `cancel()` is not awaited. If the source needs
asynchronous cleanup, arrange to await that cleanup separately. Normal stream
completion still depends on the source sending `onDone`.

### The first attempt

A message is saved in two steps -- the body of the message, then its
attachments -- and the callback awaits both:

```dart
ctx.each(messages, (child, message) async {
  await store.saveBody(message);
  await store.saveAttachments(message);
});
```

When the child accepts cancellation, it cancels the subscription at once and
stops delivering events. What it cannot do is interrupt the callback already
running: a plain `await` is not a checkpoint, so the callback comes back from
the first step and starts the second, and runs to its end as if nothing had
happened. The child waits for it, and so does the parent's cleanup: a cancelled
job whose callback still has work in it releases nothing until that callback is
done.

### The child's own checkpoints

```dart
ctx.each(messages, (child, message) async {
  await child.join(() => store.saveBody(message));
  await child.join(() => store.saveAttachments(message));
});
```

The callback gets the child's context precisely so its steps can be answered
for. `child.join` waits for the step it wraps -- a save halfway through is
still a save -- and then lets the cancellation out in place of the value, so
the second step never starts and the parent's cleanup runs as soon as the first
one is done. `child.wait` is the other choice, for a step whose result can be
abandoned. What must not go in there is the child's own completion: awaiting
`child.value` or `child.cancel()` from inside the callback never finishes,
because the child is already waiting for that callback.

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
without ever calling its callback, so there is no body and no moment. A source
that took the cancellation with it closed what it took on the way out; one that
refused it -- `cancellable: false`, or already finished when the request
arrived -- ends `Done` all the same, and the resource is then the caller's to
close, through the source's handle, exactly as for a branch that refuses a
group's stop.

### The first attempt

A job loads the rows, a continuation reports them, and the body wants both done
before it ends -- so it adopts them both:

```dart
final child = Job.deferred<int>((ctx) => ctx.wait(load));
final tail = child.then<void>((ctx, rows) => report(rows * 2));

final parent = Job<void>((ctx) async {
  ctx.log(await ctx.run(child));
  await ctx.run(tail);
});
```

The second `ctx.run` throws `ArgumentError`: `Invalid argument (child): A
continuation starts itself after its source finishes`. `ctx.run` takes a job
nobody starts by itself, and a continuation is not one of those. The length of
the chain changes nothing -- `child.then(...).then(...)` is a continuation of a
continuation, and every link refuses adoption the same way.

### The head is the only child

```dart
final parent = Job<void>((ctx) async {
  // The head is a child: the parent starts it and waits for it.
  ctx.log(await ctx.run(child));
});

await parent.value; // Done, whatever the tail is doing.
await tail.value; // The tail is yours to observe.
```

The parent waits for its children, not for what hangs off them. Once
`ctx.run(child)` has returned and the body ends, the parent finishes `Done`
while a slow tail is still running. Cancellation still reaches that tail,
through the source rather than through the parent: cancelling the parent
cancels the child, and the child's cancellation travels forward to the tail as
`ChainCancelReason`.

A failure in the tail is nobody's business but the tail's. Observe it through
`value`, `done` or `ignore`; an unobserved one goes to the zone that created
the chain, after the parent has already finished. So: a sequence that belongs
to the operation is children -- `await ctx.run(a)`, then `await ctx.run(b)`. A
sequence that deliberately outlives it is a chain, and its outcome comes back
to you, not to the parent.
