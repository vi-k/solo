# Chains

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
`then<void>((ctx, number) => saving)`, compiles, and the continuation does not
wait for `saving`: it finishes `Done` at once, and a `saving` that starts by
itself goes on alone. Nothing here starts a deferred `saving`, so there the
continuation fails with an `ArgumentError` instead; that check is made for
`void` only, because a wider type may hold a job as its value. A continuation
waits for a job it runs as its child:

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
adopted: it starts by itself once its source finishes, and `ctx.run` does not
take it, because `then` returns a plain `Job` and not a `ChildJob`.

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
source's observer nor anything an engine attaches to the source. Cleanup
registered by the source has already run when the continuation receives its
value; a resource closed by the source's `onDispose` is therefore already
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
through the handle, `(await opened.value).close()`, exactly as for
[a branch that refuses a group's stop](groups.md#what-a-group-hands-back).

An observer on the last link hears a failure from anywhere up the chain, as
that link's own: the failure comes down the chain and ends every link after it.
An error with no outcome, such as a failure of `ctx.unattended` work or of a
disposer, stays with the link where it happened: it goes to that link's
observer and, unless the observer catches it in `onUnanswered`, to the zone the
link was made in — for a continuation, the zone `then` was called in.

## A continuation of a child

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

The other way round, the continuation does reach its source while the source
runs. `tail.cancel()` while the child still loads travels back along the chain,
as the opening of this page describes, and asks the child to cancel.
`ctx.run(child)` throws the child's cancellation into the parent's body, and
the parent ends `Cancelled` too, with `HandlerCancelReason`:

```text
parent: Cancelled(handler: Job(): Cancelled(chain)), child: Cancelled(chain)
```

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
// The first attempt: ctx.run does not take a continuation.
final child = Job.deferred<int>((ctx) => ctx.abandonable(load));
final tail = child.then<void>((ctx, rows) => report(rows));

final parent = Job<void>((ctx) async {
  ctx.log(await ctx.run(child));
  await ctx.run(tail);
});
```

The second `ctx.run` does not compile:

```text
The argument type 'Job<void>' can't be assigned to the parameter type 'ChildJob<dynamic>'.
```

`ctx.run` takes a `ChildJob`, a job its parent starts, and a continuation
starts itself once its source finishes: `then` returns a plain `Job`. The
length of the chain changes nothing: `child.then(...).then(...)` hangs one
continuation off another, and no link of it is a child.

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
