# Children, streams and chains

A body can hand work to another job in three ways:

1. A child is started by the body and waited for by it.
2. A stream is processed one event at a time in a child that owns the
   subscription.
3. A continuation made by `then` starts when the job it follows succeeds, and
   outlives it.

The words for the three are close, and the wrong one compiles:

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

Three sections below open with the version habit or the names of the API lead
to — the plain `Future.wait` every Dart program already has, or the method
whose name matches the requirement — and say what that version does instead of
what it was meant to do. The version that works follows under its own heading.

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
`ctx.run` rejects a regular `Job`, because such a job starts automatically: it
may start before the parent registers it and then run outside the parent's
cancellation and completion handling.

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

If the child's body fails and a cancellation reaches the child afterwards —
while it still waits for children of its own or runs its cleanup, say — its
error does not arrive through that future. The child ends `Cancelled`,
`await ctx.run(child)` throws `Cancelled`, and the error goes where an error
nobody handled goes: to the child's observer and, unless that observer answers
for it, to the zone, as in [Where errors go](observing.md#where-errors-go) on
the observing page. `child.ignoreFailure()` silences it.
`ctx.run(child).ignore()` does not: it silences what the future throws, and the
future throws the cancellation. To answer for the error differently, give the
child an observer that answers: a `JobAnswerer` with `onUnanswered` overridden.

### When `ctx.run` refuses a child

`ctx.run` refuses an invalid start synchronously, before the child runs:

| The child | What `ctx.run` does |
| --- | --- |
| A job that starts automatically, or one from another implementation | Throws `ArgumentError` |
| A job that has already started or finished | Throws `StateError` |
| Any job, once the parent body has ended | Throws `StateError` |
| Any job, once the parent is cancelled | Cancels the child before its start and throws the parent's `Cancelled` |

### How deep a tree goes

```dart
Job<void> level(int depth) {
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
the overflow lands while the tree is still being built. With `await null`,
building goes by microtasks, and the limit moves to the other walk —
cancellation, which descends the tree recursively and reaches about three
thousand. Neither number is a promise; both follow from the size of a body's
frame.

A cascade that runs out of stack stops where the stack ran out, and the jobs
below that depth go on running. The overflow comes out of `cancel()` itself,
before it returns a future, so `cancel().ignore()` does not catch it. Recursion
measured in thousands of nested jobs wants flattening, not a deeper stack.

## Waiting for several children

An export needs two sources: the rows and the images. Neither waits for the
other, so both should open at once, and each branch closes what it opened
unless it hands it over. Whatever goes wrong, the parent has to end with the
truth about it, and nothing may stay open.

### The first attempt

```dart
final parent = Job<void>((ctx) async {
  final rows = Job.deferred<Source>(
    (ctx) => ctx.abandonable(openRows, discard: (source) => source.close()),
  );
  final images = Job.deferred<Source>(
    (ctx) => ctx.abandonable(openImages, discard: (source) => source.close()),
  );

  final sources = await Future.wait([ctx.run(rows), ctx.run(images)]);
  await ctx.join(() => writeArchive(sources));
});
```

`Future.wait` keeps the first error that reaches it and lets the rest go, and
that decides the parent's outcome by a race. Say `rows` fails and `images` ends
`Cancelled`: if the failure reaches `Future.wait` first, the parent ends
`Failed`; if the cancellation does, it ends `Cancelled(HandlerCancelReason)`,
and the failure of `rows` is nowhere in the outcome. Each failed child does
still announce its own failure to its observer — and only there, so where
neither the parent nor its children have an observer, that error is lost
entirely. Neither the core nor Dart hands it to the zone: for the core, `run`
looks at the child's outcome, since the body waits for its future, and
`Future.wait` lets every error but the first go quietly.

If `rows` fails and `images` succeeds, the source `images` opened is lost with
the values. `discard` closes the value only if it reaches nobody, and here it
reaches the body: the branch returns what it opened and ends `Done`, so its own
cleanup never closes it. The body registered nothing when the value arrived;
`Future.wait` then completes with the error and drops the values of the
branches that succeeded, so the body never even holds it. Nobody closes that
source.

`eagerError: true` does not repair either of the two:

```dart
final sources = await Future.wait(
  [ctx.run(rows), ctx.run(images)],
  eagerError: true,
);
```

It changes one thing only: when the body wakes. It buys no early end — nothing
asks the other branches to stop, and the core waits for its children
regardless, so the job still ends when the last of them does. What the body can
do in between is the whole of the difference. The outcome is still decided by
whichever trouble came first, and the source of the branch that succeeded is
still lost with the values.

### Registered on arrival, waited for in one envelope

```dart
final parent = Job<void>((ctx) async {
  final rows = Job.deferred<Source>(
    (ctx) => ctx.abandonable(openRows, discard: (source) => source.close()),
  );
  final images = Job.deferred<Source>(
    (ctx) => ctx.abandonable(openImages, discard: (source) => source.close()),
  );

  final sources = await [
    ctx.run(rows, dispose: (source) => source.close()),
    ctx.run(images, dispose: (source) => source.close()),
  ].wait;
  await ctx.join(() => writeArchive(sources));
});
```

Two things changed, and each repairs one of the two faults.

`ctx.run(child, dispose: ...)` registers the value on the parent the moment the
branch hands it over, and from then on the parent closes it when it ends,
whatever it ends with. When `rows` succeeds and `images` fails or is cancelled,
the parent closes the rows source: the `dispose` passed with `ctx.run(rows)`
runs as the parent finishes. It does the same after the archive is written, and
when a cancellation reached the parent in between. A branch that never got as
far as returning closes its own through the `discard` it opened the source
with. This alone closes what the first attempt left open, and it would under
`Future.wait` too. The rule is the one of
[Registering on arrival](cleanup.md#registering-on-arrival) on the cleanup
page; `dispose` rather than `discard`, because the parent keeps the sources to
itself.

`.wait` repairs the outcome. It collects every error into one
`ParallelWaitError`, and the values of the branches that did succeed go into
the same envelope. The core reads it: an envelope carrying a real failure stays
a failure, with its errors and values untouched, and one carrying only
cancellations and successes ends the parent with the first cancellation in the
list, exactly as awaiting a single child does. The order the trouble arrived in
no longer decides anything. The values in the envelope are registered already,
and closing them there as well closes them twice.

`.wait` stops no branch early: it returns once every branch is done, so when
one branch fails or is cancelled on its own, its sibling runs to its end. A
cancellation of the parent is another matter — it cascades to every child, the
branches of `.wait` included. A resource a branch opened for itself is still
released on time when the branch took it through
`ctx.abandonable(() => open(), dispose: (value) => value.close())`: the cleanup
belongs to the job, not to the waiting.

### When one failure makes the rest pointless

```dart
final values = await ctx.runAll([
  Job.deferred<int>((ctx) => ctx.abandonable(loadRows)),
  Job.deferred<int>((ctx) => ctx.abandonable(loadExtra)),
]);
```

`ctx.runAll` starts every child synchronously, in the order of the list, and
returns their values in that order. As soon as the body of any branch ends in
anything but a value, the others are asked to stop with `SiblingCancelReason`;
the branch the trouble came from is not, or its error would turn into a
cancellation and be lost. What comes out is decided by the final outcomes: a
real failure if there is one, otherwise the first cancellation that arrived,
thrown as the object that outcome carries — exactly what `await ctx.run(child)`
would have thrown. A failure the group received and did not throw is not
dropped; it goes where an error nobody answered for goes.

| Form | Waits for | Stops the others | Values of the branches that succeeded |
| --- | --- | --- | --- |
| `Future.wait` | every branch | no | dropped before the body sees them |
| `Future.wait(eagerError: true)` | the first error, then the job waits anyway | no | dropped |
| `[...].wait` | every branch | no | in `ParallelWaitError.values` |
| `ctx.runAll` | every branch | yes, with `SiblingCancelReason` | returned in order when every branch succeeds |

Use `[ctx.run(a), ctx.run(b)].wait` when the branches are independent of each
other's failure, or when one of them waits for another. Use `ctx.runAll` when a
result missing one of its parts is of no use anyway. None of the forms closes
what the branches returned: a form only hands the values over or drops them.
What closes a value is the registration its receiver made the moment it
arrived. Under `ctx.run` that is the `dispose` passed with each call, as in
[Registered on arrival, waited for in one envelope](#registered-on-arrival-waited-for-in-one-envelope)
above. `ctx.runAll` takes no such argument, and
[The list a group returns](#the-list-a-group-returns) shows how to register
that list.

Five things `runAll` does not promise. Some of them turn on what the group does
with a branch whose body has returned a value: the group holds that branch
until its own end is decided, and until then the branch has no outcome and its
cleanup waits.

**The stop is cooperative.** A branch waiting through `ctx.abandonable` ends,
and the operation behind it plays on and writes its result. To stop the work
itself, hand the cancellation to it with `ctx.onCancel` and wait for it with
`ctx.join`. A branch created with `cancellable: false` refuses the stop
outright, and the group waits for it.

**The descendants of the branch that failed play out.** A failure never
cascades, so the children that branch started are not cancelled, and the group
waits for them as it waits for everything else.

**The outcome of a branch is not final until the group decides.** A body that
returned a value can still end `Cancelled`: until the group decides, the
branch's `outcome` is `null` and its `isCancelled` is `false`. When another
branch ends in anything but a value, the group cancels this one with
`SiblingCancelReason`, and it ends `Cancelled`, with `isCancelled` now `true`.
A branch created with `cancellable: false` refuses that cancellation and ends
`Done`.

**A branch waiting for another branch of the same group may never end.**
Awaiting a sibling's `Job.value` or `Job.done` hangs the group: the sibling is
held until the group decides, and the group decides only once every branch is
held, or once the body of one of them has ended in anything but a value. The
core does not detect such a hang: no error comes out, and the group simply
waits. A cancellation unties it on the same terms as the lock of the next
point: a branch awaiting the sibling through `ctx.abandonable` ends, unless it
was created with `cancellable: false` or waits inside `ctx.uncancellable`; one
in a bare `await` does not. For branches that depend on each other,
`[...].wait` is the way out.

**The same goes for a branch waiting for what another one releases in its
cleanup.** A branch starts unwinding only when every branch has ended its body
and its children, or when the body of one of them has ended in anything but a
value; until then its `dispose` and `onDispose` callbacks wait too. Say the
branches share a lock, or a pool with fewer free slots than the branches that
want one, and each branch takes the lock or a slot as on
[the cleanup page](cleanup.md):
`ctx.join(Lock.acquire, dispose: (lock) => lock.release())`. The release is
that `dispose`, and it waits, so the lock or slot stays with the branch that
got it. The branch waiting for it keeps every branch from unwinding, and the
group hangs with no timer and no error until the body of another branch ends in
anything but a value.

A cancellation, of the parent or of a branch, unties it only when it ends what
a branch still waits on before it unwinds: its body, or a child of it, waiting
through `ctx.abandonable` or on an operation that hears `ctx.onCancel`. It does
not end one stuck in `ctx.join` on an operation deaf to it, in a bare `await`,
inside `ctx.uncancellable`, or in a job created with `cancellable: false`.
Cancelling the branch that holds the lock does nothing: its body is over. Take
such a lock in a child of the branch instead, which releases it when the child
ends, still inside the body of the branch:

```dart
Job.deferred<Source>((ctx) async {
  final locked = Job.deferred<Source>((ctx) async {
    await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
    return ctx.abandonable(openRows, discard: (source) => source.close());
  });

  return ctx.run(locked, discard: (source) => source.close());
});
```

The child `locked` holds the lock and also opens the source the branch returns.
It does not close that source itself — it hands the source over, and its
`discard` runs only if the value reaches nobody. So the branch registers its
own closing the moment the source arrives: the `discard` passed to
`ctx.run(locked, ...)`, as in
[Registering on arrival](cleanup.md#registering-on-arrival). If the group ends
in anything but success, the branch closes the source itself, and by then
nobody holds the lock: the child released it when it ended. Or use
`[...].wait`, under which every branch unwinds on its own.

## What a group hands back

A branch says whether a resource is its own or handed out by the member it
registers the release with:

```dart
Job.deferred<Source>((ctx) async {
  final cache =
      await ctx.abandonable(openCache, dispose: (cache) => cache.close());
  final rows =
      await ctx.abandonable(openRows, discard: (source) => source.close());
  await ctx.join(() => cache.warm(rows));

  return rows;
});
```

Ownership is the same rule as everywhere else, and a group is where it starts
to matter. A resource a branch keeps for itself goes to the `dispose` of
`ctx.abandonable` and `ctx.join`, or to `onDispose`, and the end of the branch
closes it whatever the outcome. A resource a branch hands out goes to their
`discard`, or to `onDiscard`: it then lives until the group succeeds in full
and reaches the caller open. When the group ends in anything else, the branch
that accepted the stop closes what it took, and it closes it before the group
returns — so by the time the parent catches the error, that resource is already
closed.

A branch can also get the resource from a child of its own, as the branch with
the child `locked` does in the section above. The child's own `discard` does
not close it: the child hands the resource over and ends `Done` inside the
branch, before the group has decided anything, and a `discard` runs only if the
value reaches nobody. Here it reached the branch, so the branch registers the
resource again the moment it arrives, with `ctx.run(child, discard: ...)`. That
registration is the branch's own: the resource lives until the group succeeds
in full, and the branch closes it if the group ends in anything else. The
cleanup page shows the call in
[Registering on arrival](cleanup.md#registering-on-arrival).

One thing stays open, and it follows from
[Choosing the callback](cleanup.md#choosing-the-callback) on the cleanup page.
A branch created with `cancellable: false` refuses the stop and ends `Done`,
and its value counts as handed over through its own `Job.value`: a `discard`
the branch registered would not run, and nothing else closes the resource. The
body still holds `rows`, the job it passed to `runAll`, and closes the value
through it:

```dart
final rows = Job.deferred<Source>(cancellable: false, (ctx) => openRows());
try {
  await ctx.runAll([rows, images]);
} on Object {
  if (rows.outcome case Done(:final value)) value.close();
  rethrow;
}
```

## The list a group returns

`ctx.runAll` hands the body a list of open sources, and the body has to close
every one of them, whatever happens after the group returns. The list is a
value like any other, and the body is its receiver: unlike `run`, `runAll`
takes no `dispose` or `discard` of its own to register it with on arrival, so
the body registers the list itself.

### The first attempt

```dart
final sources = await ctx.runAll(branches);
await ctx.join(() => writeArchive(sources));
for (final source in sources) {
  source.close();
}
```

The body closes the sources where it is done with them, the way any Dart code
closes a file after the last write. The loop runs only if the body gets to it.
If a cancellation arrives while the archive is being written, `ctx.join` waits
the archive out and then throws the cancellation in place of its value; a
failing `writeArchive` throws its error the same way. Either way the body never
reaches the loop. The list is already in the body's hands and now unreachable,
and nothing announces the leak: what the caller sees is an ordinary
cancellation or the error of the archive.

### A `try` on the next line

```dart
final sources = await ctx.runAll(branches);
try {
  await ctx.join(() => writeArchive(sources));
} finally {
  for (final source in sources) {
    source.close();
  }
}
```

The `try` opens on the very next line after the group returns, before anything
that can throw, and `finally` runs however the body leaves it: on the
cancellation `join` throws, on the error of the archive, or after the last
line. For a list the body keeps for itself, that closes every source.
`ctx.onDispose` with the same loop, on the same line, does what `finally` does.

### A list the body hands out

```dart
final exported = Job.deferred<List<Source>>((ctx) async {
  final sources = await ctx.runAll(branches);
  try {
    await ctx.join(() => writeArchive(sources));
  } on Object {
    for (final source in sources) {
      source.close();
    }
    rethrow;
  }
  return sources;
});
```

This branch writes the archive and then returns the sources open, for its
caller to use further. `finally` would close them on success as well, so the
closing moves to `catch`. That covers every error of the body, and nothing
after it: a returned list can still reach nobody. When `exported` is a branch
of a `ctx.runAll` group and a sibling fails after the body has returned, the
group cancels the branch, as
[What a group hands back](#what-a-group-hands-back) describes, and the list
never reaches the caller. The body has long left the `try` by then, and the
sources stay open.

`ctx.onDiscard` runs exactly when the value reaches nobody, so it closes the
list in that case too, and stays out of the way when the list arrives:

```dart
final exported = Job.deferred<List<Source>>((ctx) async {
  final sources = await ctx.runAll(branches);
  ctx.onDiscard(() {
    for (final source in sources) {
      source.close();
    }
  });
  await ctx.join(() => writeArchive(sources));
  return sources;
});
```

`ctx.onDiscard` goes on the very next line, before anything that can throw: an
error or a cancellation above the registration would leave the list open, as in
the first attempt.

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
    final processing = ctx.each(messages, (childCtx, message) {
      return childCtx.join(() => save(message));
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

The parent waits for the child even if its body returns without awaiting it, so
an open stream keeps the parent alive until the stream ends or the child is
cancelled, and a cancellation the parent accepts passes to the child.

The page on [streams](streams.md) has the rest: what `await for` and `listen`
do in a body instead, how a callback stops for a cancellation, where the
cleanup of one event belongs, and `Job.each` for a job that is nothing but a
stream.

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
and the others too.

A continuation starts only when its source has finished, so a link that is
running has nothing unfinished behind it. Once `parsed` works, `loaded` is over
and `loaded.cancel()` does nothing: `parsed` goes on, and `saved` after it. The
same holds one link down: with `saved` running, cancelling `loaded` or `parsed`
leaves it alone. To stop a link that is running, cancel that link or one after
it.

`await saved.cancel()` waits for the unfinished predecessors, their children
and cleanup, and any work and cleanup already started by `saved`. Sources
retain their normal cancellation rules: `cancellable: false` refuses a request,
and `uncancellable` holds it. A cancelled continuation still waits for that
source, then finishes without calling its callback. While waiting, it can be
`isCancelled` without being `isFinished`; its outcome has `started: false` if
it was cancelled while waiting for its source.

A failed predecessor forwards its error and stack without calling the callback.
Observe the continuation through `value`, `done` or `ignoreFailure` to handle
that failure. If a cancelled continuation cannot forward a source failure, it
does not observe it either: for example, a source that refuses cancellation and
later fails still needs its own error handling.

The callback returns a value or a future, and the continuation waits for the
future. A `Job` is not a future. A callback that returns one,
`then<void>((ctx, number) => saving)`, compiles, and the continuation finishes
`Done` at once without waiting for `saving`; a deferred `saving` is never even
started. A continuation waits for a job it runs as its child:

```dart
final stored = parsed.then<void>((ctx, number) {
  final saving = Job.deferred<void>(
    (ctx) => ctx.join(() => saveNumber(number)),
  );
  return ctx.run(saving);
});
```

`then` does not start its source. A chain hung off a `Job.deferred` stays
unstarted, every link of it, until the source is started: by `start()`, or by
`ctx.run(source)` in the body that adopts it. The continuation itself is never
adopted: it starts by itself once its source finishes, and `ctx.run` refuses
it.

A continuation starts once its source has finished, cleanup included, so a
source that waits for its own continuation waits forever:

```dart
late final Job<int> parsed;
final loaded = Job<String>((ctx) async {
  final text = await ctx.join(loadText);
  await parsed.value;
  return text;
});
parsed = loaded.then<int>((ctx, text) => int.parse(text));
```

`parsed` starts once `loaded` has finished, and `loaded` is waiting for
`parsed`. Neither ends, and `loaded.cancel()` does not return either.
`parsed.done` in place of `parsed.value` changes nothing, and neither does
moving the await into the cleanup of `loaded`.

Each continuation is a root job of the core, wherever `then` is called: made in
the body of another job, it is not that job's child, and the job does not wait
for it. It has an optional `observer` argument and inherits neither the
source's observer nor anything an engine of a domain attaches to the source.
Cleanup registered by the source has already run when the continuation receives
its value; a resource closed by the source's `onDispose` is therefore already
closed at that point.

A `discard` of the source is the other way round. Here `opened` hands out the
rows it opened, and `archived` receives them:

```dart
final opened = Job<Source>(
  (ctx) => ctx.abandonable(openRows, discard: (rows) => rows.close()),
);
final archived = opened.then<void>((ctx, rows) async {
  ctx.onDispose(rows.close);
  await ctx.join(() => writeArchive([rows]));
});
```

`opened` ended `Done`, so its `discard` did not run and never will. The
receiver is the continuation: `rows` comes as its argument, and it registers
the closing in its own body, on the first line.

One case has no receiver at all. `archived.cancel()` while `opened` is still
opening finishes `archived` without ever calling its callback, so there is no
body to register anything in. The cancellation goes on to `opened`. If `opened`
takes it, its `discard` closes the rows when they arrive. If `opened` refuses
it — `cancellable: false`, or already finished when the request arrived — it
ends `Done` all the same, with the rows open. The caller then closes them
through the handle, `(await opened.value).close()`, exactly as for a branch
that refuses a group's stop.

An observer on the last link hears a failure from anywhere up the chain, as
that link's own: the failure comes down the chain and ends every link after it.
An error with no outcome, such as a failure of `ctx.unattended` work or of a
disposer, stays with the link where it happened: it goes to that link's
observer and, unless the observer answers for it, to the zone the link was made
in — for a continuation, the zone `then` was called in.

### A continuation of a child

The parent needs the rows; the report on them may finish after the parent has:

```dart
final child = Job.deferred<int>((ctx) => ctx.abandonable(load));
final tail = child.then<void>((ctx, rows) => report(rows));

final parent = Job<void>((ctx) async {
  // The source is a child: the parent starts it and waits for it.
  ctx.log(await ctx.run(child));
});

await parent.value; // Done, whatever tail is doing.
await tail.value; // tail is yours to observe.
```

The parent waits for its children, not for what hangs off them. Once
`ctx.run(child)` has returned and the body ends, the parent finishes `Done`
while a slow continuation is still running. The parent's cancellation reaches
the continuation only while it still waits for its source: cancelling the
parent cancels the child, and the child's cancellation travels forward to the
continuation as `ChainCancelReason`. Once the source has finished and the
continuation runs, nothing the parent does reaches it; only the continuation's
own handle stops it, `tail.cancel()`, or
`ctx.onCancel(() => tail.cancel().ignore())` in a parent body that is still
running.

A failure in the continuation is nobody's business but its own. Observe it
through `value`, `done` or `ignoreFailure`; an unobserved one goes to the zone
`then` was called in, after the parent has already finished. Its outcome comes
back to you, not to the parent.

## Steps in a row

A job loads the rows and then reports them, and it must not end before the
report is done.

### The first attempt

`then` reads like the word for "and then", so the report becomes a
continuation, and the body adopts both:

```dart
final child = Job.deferred<int>((ctx) => ctx.abandonable(load));
final tail = child.then<void>((ctx, rows) => report(rows));

final parent = Job<void>((ctx) async {
  ctx.log(await ctx.run(child));
  await ctx.run(tail);
});
```

The second `ctx.run` throws `ArgumentError`:

```text
Invalid argument (child): is a continuation,
which starts itself once its source finishes: "Job(then)"
```

`ctx.run` takes a job nobody starts by itself, and a continuation is not one of
those. The length of the chain changes nothing: `child.then(...).then(...)`
hangs one continuation off another, and every link refuses adoption the same
way.

### Two children in a row

```dart
final parent = Job<void>((ctx) async {
  final rows =
      await ctx.run(Job.deferred<int>((ctx) => ctx.abandonable(load)));
  await ctx.run(Job.deferred<void>((ctx) => ctx.join(() => report(rows))));
});
```

A sequence that belongs to the operation is children. The second `ctx.run`
starts once the first has returned its value, the parent waits for both, and
its cancellation reaches whichever of them is running. A chain is for the
opposite case, a step that outlives the operation or runs outside it:
[A continuation of a child](#a-continuation-of-a-child).
