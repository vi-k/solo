# Chains

A chain continues a job with its result. Here the app loads a number as text,
parses it and saves it. `then` returns a new job that starts once its source
has succeeded, children and cleanup included, and gives its callback the value
and a context of its own:

```dart
final loaded = Job<String>((ctx) => ctx.join(loadText));
final parsed = loaded.then<int>((ctx, text) => int.parse(text));
final saved = parsed.then<void>((ctx, number) => ctx.join(
      () => saveNumber(number),
    ));

await saved.value;
```

The output blocks of this page hold:

- `loaded:`, `parsed:`, `saved:` the outcome of that link;
- `parent:`, `child:` the outcomes after `tail.cancel()` in
  [A continuation of a child](#a-continuation-of-a-child).

## Cancelling a chain

The text is still loading when the user leaves the screen, and the screen
cancels the last link:

```dart
// The user left the screen while the text was loading.
await saved.cancel();
print('loaded: ${loaded.outcome}');
print('parsed: ${parsed.outcome}');
print('saved: ${saved.outcome}');
```

```text
loaded: Cancelled(chain)
parsed: Cancelled(chain)
saved: Cancelled(manual)
```

A cancellation travels along the chain both ways. It asks the unfinished links
before the cancelled one to cancel, and it cancels the links after it. Each
link it reaches gets `ChainCancelReason`, with the `Cancelled` of the link it
came from in `cause`:

| You cancel | Asked to cancel, if unfinished | Cancelled once the link you cancel accepts |
| --- | --- | --- |
| `loaded` | none | `parsed` and `saved` |
| `parsed` | `loaded` | `saved` |
| `saved` | `loaded` and `parsed` | none |


A link that refuses stops the cancellation there: cancel a `loaded` made with
`cancellable: false`, and `parsed` and `saved` go on. Finished links keep their
outcomes. If several continuations hang off one job, cancelling one of them can
cancel the shared source, and the other continuations with it.

A continuation starts only when its source has finished, so a running link has
nothing unfinished behind it. While `parsed` runs, `loaded` is over, and
`loaded.cancel()` does nothing: `parsed` goes on, and `saved` after it. While
`saved` runs, cancelling `loaded` or `parsed` leaves it alone. To stop a
running link, cancel that link or one after it.

`await saved.cancel()` returns once the unfinished links before `saved` have
ended, with their children and cleanup, and once `saved` has ended the work and
cleanup it started. A source keeps its own rules: `cancellable: false` refuses
the request, and `uncancellable` holds it back. A cancelled continuation still
waits for such a source and then ends without calling its callback. Meanwhile
it is `isCancelled` but not `isFinished`. Its outcome has `started: false` if
it was cancelled while it waited for its source.

## When a link fails

A failed link passes its error and stack on without calling the next callback.
The failure comes down the chain and ends every link after it, so whoever
observes the last link through `value`, `done` or `ignoreFailure` handles a
failure from anywhere up the chain. The `JobObserver` of the last link hears it
as that link's own failure.

Where an error goes depends on what failed:

| What failed | Where the error goes |
| --- | --- |
| The body of a link or the callback of a continuation | Down the chain, to whoever observes the last link. Unobserved, it goes to the zone the last `then` was called in |
| A source that refused the cancellation of its continuation and failed later | To the zone the source was made in, unless something observes the source. The cancelled continuation does not forward the error, so it does not observe it either |
| Work of `ctx.unattended` or a disposer, which no outcome carries | The observer of the link where it happened, then, unless the observer catches it in `onUnanswered`, the zone the link was made in. For a continuation, that is the zone `then` was called in |

## What the callback returns

The callback returns a value or a future, and the continuation waits for the
future. Here a job of its own saves the number.

### The first attempt

```dart
// The first attempt: the continuation does not wait for a job.
final stored = parsed.then<void>((ctx, number) {
  final saving = Job<void>((ctx) => ctx.join(() => saveNumber(number)));
  return saving;
});
```

The code compiles. The `void_checks` lint, which `package:lints` turns on,
marks this callback, but not the arrow form `(ctx, number) => saving`, and the
compiler marks neither. `stored` does not wait for `saving`. This is what
happens:

1. `then` waits for a future, and a `Job` is not a future. The continuation
   takes `saving` for its value and ends `Done` at once.
2. `saving` starts by itself and goes on alone, and nobody waits for it.
3. A `saving` made with `Job.deferred` would never start, because nothing here
   starts it. For a `void` continuation the core checks this, and `stored`
   fails with an `ArgumentError`. A continuation of a wider type takes the job
   for its value: a job may be the value it means to hand on.

### A job the continuation runs as its child

```dart
final stored = parsed.then<void>((ctx, number) {
  final saving = Job.deferred<void>(
    (ctx) => ctx.join(() => saveNumber(number)),
  );
  return ctx.run(saving);
});
```

`ctx.run` starts `saving` and returns a future of its value, and the
continuation waits for it.

## A continuation is not a child

Each continuation is a root job of the core, wherever `then` is called. Made in
the body of another job, it is not that job's child, and that job does not wait
for it. It has an optional `observer` argument and inherits neither the
source's observer nor anything an engine attaches to the source.

| | A child | A continuation |
| --- | --- | --- |
| Made by | `Job.deferred` | `then` |
| Starts | when its parent runs it with `ctx.run` | by itself, once its source has succeeded |
| Waited for by | its parent | nobody: it is a root job |
| `ctx.run` takes it | yes, it is a `ChildJob` | no, it is a plain `Job` |

`then` does not start its source. A chain hung off a `Job.deferred` stays
unstarted, every link of it, until the source is started: by `start()`, or by
`ctx.run(source)` in the body that adopts it.

## What the source hands out

`opened` opens the rows and hands them out, and `archived` writes them to an
archive:

```dart
final opened = Job<Source>(
  (ctx) => ctx.abandonable(openRows, discard: (rows) => rows.close()),
);
final archived = opened.then<void>((ctx, rows) async {
  ctx.onDispose(rows.close);
  await ctx.join(() => writeArchive([rows]));
});
```

Cleanup the source registered has run by the time the continuation receives its
value: a resource closed by the source's `onDispose` is already closed then.
`discard` is the other way round: it runs only for a value that reached nobody.
`opened` ended `Done`, so its `discard` did not run and never will. The
receiver is the continuation: `rows` comes as its argument, and it registers
the closing in its own body, on the first line.

One case has no receiver at all. `archived.cancel()` while `opened` is still
opening ends `archived` without calling its callback, so there is no body to
register anything in. The cancellation goes on to `opened`, and who closes the
rows depends on what `opened` does with it:

| How the chain goes | Who closes the rows |
| --- | --- |
| `archived` receives the rows | `archived`, through `ctx.onDispose` |
| `archived` is cancelled while `opened` opens, and `opened` takes the cancellation | `opened`, through its `discard`, when the rows arrive |
| The same, and `opened` refuses it: `cancellable: false`, or it has finished by the time the request arrives | The caller, through the handle: `(await opened.value).close()`, as for [a branch that refuses a group's stop](groups.md#what-a-group-hands-back) |

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
while a slow continuation is still running. What stops `tail` depends on
whether it still waits for the child:

| What | While `tail` waits for the child | While `tail` runs |
| --- | --- | --- |
| Cancelling the parent | Stops it: the parent cancels the child, and the child's cancellation travels forward as `ChainCancelReason` | Does not reach it |
| `tail.cancel()` | Stops it | Stops it |
| `ctx.onCancel(() => tail.cancel().ignore())` in a parent body that still runs | Stops it | Stops it |

The other way round, the continuation does reach its source while the source
runs. `tail.cancel()` while the child still loads travels back along the chain,
as [Cancelling a chain](#cancelling-a-chain) describes, and asks the child to
cancel. `ctx.run(child)` throws the child's cancellation into the parent's
body, and the parent ends `Cancelled` too, with `HandlerCancelReason`:

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

## A source that waits for its continuation

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
