# Groups

## Waiting for several children

An export needs two sources: the rows and the images. Neither waits for the
other, so both should open at once, and each branch closes what it opened
unless it hands it over. Whatever goes wrong, the parent has to end with the
truth about it, and nothing may stay open.

### The first attempt

```dart
// The first attempt: a race decides the outcome, and a source leaks.
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
// The first attempt with eagerError: the same race, the same leak.
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
list, exactly as [awaiting a single child](children.md) does. The order the
trouble arrived in no longer decides anything. The values in the envelope are
registered already, and closing them there as well closes them twice.

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
would have thrown. It goes otherwise for a branch an engine ends by hand with a
value after the group heard its body fail:
[Not waiting for the checkpoint](extending.md#not-waiting-for-the-checkpoint)
on the extending page says what comes out then. A failure the group received
and did not throw is not dropped; it goes the way of an error no outcome
carries.

The branches of a group wait for one another. A branch whose body has returned
a value does not unwind until the group has decided, and its `dispose`
callbacks wait with it. So a branch that waits for a sibling — for its value,
or for a lock the sibling releases in its `dispose` — can hang the group, with
no error and no timer. The last two of the five points below say when, and how
to take such a lock; for branches that depend on each other, use `[...].wait`.

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
`Done`. Once the group has handed the list over, the decision is final: every
branch ends `Done` with the value it gave, and a cancellation that reaches it
while it is still unwinding, the parent's cascade included, is turned away.

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
// The first attempt: a throw before the loop leaves every source open.
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
line. For a list the body keeps for itself, that closes every source, as long
as no `close` throws. One that throws ends the loop, and the sources after it
stay open.

A registration of its own for each source closes the rest all the same. The
cleanup stack runs every callback whatever the one before it did: an error from
one goes to `onError` and, by default, on to the zone, as
[Cleanup order and late results](cleanup.md#cleanup-order-and-late-results) on
the cleanup page describes. The loop takes the place of the `try`, on the very
next line:

```dart
final sources = await ctx.runAll(branches);
for (final source in sources) {
  ctx.onDispose(source.close);
}
await ctx.join(() => writeArchive(sources));
```

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
list in that case too, and stays out of the way when the list arrives. Each
source gets a registration of its own, as in the section above:

```dart
final exported = Job.deferred<List<Source>>((ctx) async {
  final sources = await ctx.runAll(branches);
  for (final source in sources) {
    ctx.onDiscard(source.close);
  }
  await ctx.join(() => writeArchive(sources));
  return sources;
});
```

The registrations go on the very next line, before anything that can throw: an
error or a cancellation above them would leave the list open, as in the first
attempt.
