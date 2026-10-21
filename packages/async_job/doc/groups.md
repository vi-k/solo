# Groups

A group is several children of one job that run at the same time, and the job
waits for all of them. `.wait` over the futures of `ctx.run` lets every branch
run to its end, and `ctx.runAll` cancels the branches still running as soon as
one ends without a value.

The lines under the code are what the code reports:

- `rows closed`: the source of the rows is closed;
- `lock acquired`, `lock waits`, `lock released`: what happens to a lock the
  branches share;
- `outcome:` what `parent.done` completes with.

## Waiting for several children

An export needs two sources: the rows and the images. Neither waits for the
other, so both open at once. Each branch closes what it opened, unless it hands
it over. Whatever goes wrong, the parent has to end with the truth about it,
and nothing may stay open.

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

`Future.wait` is how Dart waits for several futures, and here it has two
faults. This is what happens:

1. The outcome is decided by a race. `Future.wait` keeps the first error that
   reaches it and lets the rest go quietly. Say `rows` fails and `images` ends
   `Cancelled`. If the failure comes first, the parent ends `Failed`. If the
   cancellation comes first, the parent ends `Cancelled(HandlerCancelReason)`,
   and the failure of `rows` is nowhere in the outcome. Only the child's
   observer hears it then. The core does not hand it to the zone: the body
   waited for the future of `run`, so the core counts the failure as looked at.
   Where neither the parent nor its children have an observer, the error is
   lost.
2. A source leaks. Say `rows` fails and `images` succeeds. The branch `images`
   returns its source and ends `Done`, so its `discard` does not run: the value
   reached `ctx.run`. But `Future.wait` completes with the error and drops the
   values, so the body never holds the source. Nobody closes it.

`eagerError: true` repairs neither:

```dart
// The first attempt with eagerError: the same race, the same leak.
final sources = await Future.wait(
  [ctx.run(rows), ctx.run(images)],
  eagerError: true,
);
```

It changes only when the body wakes: at the first error, not after the last
branch. Nothing asks the other branches to stop, and the core waits for its
children anyway, so the job ends no earlier. The outcome is still decided by
whichever trouble came first, and the source of the branch that succeeded is
still lost.

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

When `rows` opens and `images` fails, this prints:

```text
rows closed
outcome: Failed(ParallelWaitError: Bad state: disk)
```

Two things changed, and each repairs one fault.

`ctx.run(child, dispose: ...)` repairs the leak. It registers the value on the
parent the moment the branch hands it over. From then on, the parent closes the
value when it ends, whatever it ends with. The parent may end after the archive
is written, when the other branch fails or is cancelled, or when it is
cancelled in between. A branch that never returned closes its source through
the `discard` it opened the source with. This would repair the leak under
`Future.wait` too. It is the rule of
[Registering on arrival](cleanup.md#registering-on-arrival) on the cleanup
page. The callback is `dispose` rather than `discard`, because the parent keeps
the sources to itself.

`.wait` repairs the outcome. It collects every error into one
`ParallelWaitError`, together with the values of the branches that succeeded.
The core reads that envelope. An envelope with a real failure stays a failure,
with its errors and values untouched. An envelope with only cancellations and
values ends the parent with the first cancellation in the list, as
[awaiting a single child](children.md) does. The order in which the trouble
arrived no longer decides anything. The values in the envelope are registered
already, so closing them there as well would close them twice.

`.wait` stops no branch early. It returns once every branch is done, so when
one branch fails or is cancelled on its own, its sibling runs to its end. A
cancellation of the parent does stop them: it passes to every child, the
branches of `.wait` included. A resource a branch opened for itself is still
released when the branch ends, if the branch registered it with `dispose`:
`ctx.abandonable(() => open(), dispose: (value) => value.close())`. The cleanup
belongs to the job, not to the waiting.

### When one failure makes the rest pointless

Sometimes a result that misses one of its parts is of no use, and the branches
still running should stop as soon as one fails. `ctx.runAll` does that:

```dart
final values = await ctx.runAll([
  Job.deferred<int>((ctx) => ctx.abandonable(loadRows)),
  Job.deferred<int>((ctx) => ctx.abandonable(loadExtra)),
]);
```

`ctx.runAll` starts every child synchronously, in the order of the list, and
returns their values in that order. As soon as the body of a branch ends
without a value, the group cancels the other branches with
`SiblingCancelReason`. It does not cancel the branch the trouble came from, or
that branch's error would turn into a cancellation and be lost.

What `runAll` throws is decided by the final outcomes: a real failure if there
is one, otherwise the first cancellation that arrived, other than those the
group asked for itself. It throws the object that outcome carries, as
`await ctx.run(child)` would. A failure the group received and did not throw
goes the way of an error that no outcome carries. An engine may end a branch by
hand with a value after the group heard its body fail. The group then goes by
that failure and not by the branch's `Done`: see
[Finishing a job by hand](extending.md#finishing-a-job-by-hand) on the
extending page.

| Form | Waits for | Stops the others | Values of the branches that succeeded |
| --- | --- | --- | --- |
| `Future.wait` | every branch | no | dropped before the body sees them |
| `Future.wait(eagerError: true)` | the first error, then the job waits anyway | no | dropped |
| `[...].wait` | every branch | no | in `ParallelWaitError.values` |
| `ctx.runAll` | on success, the cleanup of every branch, except one a branch registers after running it; on failure, every branch to its end | yes, with `SiblingCancelReason` | returned in order when every branch succeeds |

Use `[ctx.run(a), ctx.run(b)].wait` when the branches do not depend on each
other's failure, or when one of them waits for another. Use `ctx.runAll` when a
result that misses one of its parts is of no use anyway.

None of the forms closes what the branches returned: a form only hands the
values over or drops them. A value is closed by the registration its receiver
made when it arrived. Under `ctx.run`, that is the `dispose` passed with each
call. `ctx.runAll` takes no such argument, and
[The list a group returns](#the-list-a-group-returns) shows how to register
that list.

The branches of a group wait for one another. A branch whose body has returned
a value does not unwind until every branch has ended its body and its children,
or until the body of one has ended without a value. Its `dispose` callbacks
wait with it. So a branch that waits for a sibling can hang the group;
[Branches that wait for each other](#branches-that-wait-for-each-other) shows
how.

On success `ctx.runAll` hands the values over once every branch has run its
cleanup, and before the branches end. A branch that has run its cleanup waits
there for the cleanup of the others. A cleanup it registers in that wait, from
a timer or an event of its own, runs after the values arrive, under the parent,
which waits for its children as always. On failure `ctx.runAll` waits for every
branch to end, so by the time the error arrives everything the branches took is
closed.

## Branches that wait for each other

Two branches read rows under one lock, because the store lets in one reader at
a time. A pool with fewer free slots than the branches that want one goes the
same way. Each branch takes the lock the way the cleanup page takes a resource,
with `ctx.join(Lock.acquire, dispose: (lock) => lock.release())`.

### The first attempt

```dart
// The first attempt: the lock waits for the group, and the group for it.
ChildJob<int> reading() {
  return Job.deferred<int>((ctx) async {
    await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
    return ctx.abandonable(loadRows);
  });
}

final parent = Job<List<int>>((ctx) => ctx.runAll([reading(), reading()]));
```

```text
lock acquired
lock waits
```

Nothing more comes: the group hangs, with no error and no timer. This is what
happens:

1. The first branch takes the lock, reads and returns its value. Its body is
   over, but the branch does not unwind yet, and the `dispose` that releases
   the lock waits with it.
2. The second branch waits for the lock, so its body does not end.
3. The branches unwind once every body has ended with its children, or once one
   has ended without a value. Neither happens, and the core does not detect the
   hang.

A branch that awaits a sibling's `Job.value` or `Job.done` hangs the group the
same way: the sibling has no outcome until the group decides.

A cancellation does not help here. It unties such a group only when it ends
what a branch still waits on: a body, or a child of it, that waits through
`ctx.abandonable` or on an operation that hears `ctx.onCancel`. The second
branch waits in `ctx.join` on `Lock.acquire`, which does not hear it, so even a
cancelled parent hangs. A cancellation does not end a bare `await` either, nor
a wait inside `ctx.uncancellable` or in a job created with
`cancellable: false`. Cancelling the branch that holds the lock does nothing:
its body is over.

### The lock in a child of the branch

```dart
ChildJob<int> reading() {
  return Job.deferred<int>((ctx) async {
    final locked = Job.deferred<int>((ctx) async {
      await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
      return ctx.abandonable(loadRows);
    });
    return ctx.run(locked);
  });
}
```

```text
lock acquired
lock waits
lock released
lock acquired
lock released
outcome: Done([21, 21])
```

The child `locked` holds the lock, and the child ends inside the body of the
branch. Its cleanup releases the lock then, before the group has decided
anything, and the second branch takes the lock. For branches that depend on
each other, `[...].wait` is the other way out: under it, every branch unwinds
on its own.

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
to matter. The member the branch registers the release with decides who closes
the resource and when:

| The branch registers the release with | The group succeeds in full | The group ends in anything else |
| --- | --- | --- |
| The `dispose` of `ctx.abandonable` and `ctx.join`, or `onDispose`: a resource the branch keeps for itself | The end of the branch closes it | The end of the branch closes it |
| Their `discard`, or `onDiscard`: a resource the branch hands out | It reaches the caller open | The branch that accepted the stop closes it before the group returns: by the time the parent catches the error, it is closed |
| The `discard` of `ctx.run(child, discard: ...)`: a resource from a child of the branch | It reaches the caller open | The same as in the row above: the registration is the branch's own |
| Any `discard`, in a branch created with `cancellable: false` | It reaches the caller open | No registration: the branch refuses the stop and ends `Done`, so the `discard` does not run. The body closes the value through the branch's job, as below |

A branch can also get the resource from a child of its own:

```dart
Job.deferred<Source>((ctx) async {
  final opening = Job.deferred<Source>(
    (ctx) => ctx.abandonable(openRows, discard: (source) => source.close()),
  );
  return ctx.run(opening, discard: (source) => source.close());
});
```

The child's own `discard` does not close the source. The child hands the source
over and ends `Done` inside the branch, before the group has decided anything,
and a `discard` runs only if its job does not end `Done`. Here the source
reached the branch. So the branch registers the source again the moment it
arrives, with the `discard` passed to `ctx.run`. That registration is the
branch's own, the third row of the table. The cleanup page shows the call in
[Registering on arrival](cleanup.md#registering-on-arrival).

The last row follows from
[Choosing the callback](cleanup.md#choosing-the-callback) on the cleanup page.
A branch created with `cancellable: false` refuses the stop and ends `Done`.
Its value counts as handed over through its own `Job.value`: a `discard` the
branch registered would not run, and nothing else closes the resource. The body
still holds `rows`, the job it passed to `runAll`, and closes the value through
it:

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
value like any other, and the body is its receiver. Unlike `run`, `runAll`
takes no `dispose` or `discard` to register the list with on arrival, so the
body registers it itself.

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
the archive out and then throws the cancellation instead of returning. A
failing `writeArchive` throws its error the same way. Either way, the body
never reaches the loop. The list is lost in the body's hands, and nothing
announces the leak: the caller sees an ordinary cancellation or the error of
the archive.

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
that can throw. `finally` runs however the body leaves the `try`: on the
cancellation `join` throws, on the error of the archive, or after the last
line. For a list the body keeps for itself, that closes every source, as long
as no `close` throws. A `close` that throws ends the loop, and the sources
after it stay open.

A registration of its own for each source closes the rest all the same. The
cleanup stack runs every callback, whatever the one before it did. An error
from one goes to `onError` and, by default, on to the zone, as
[Cleanup order and late results](cleanup.md#cleanup-order-and-late-results) on
the cleanup page describes. The loop of registrations takes the place of the
`try`, on the very next line:

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
caller to use. `finally` would close them on success as well, so the closing
moves to `catch`. That covers every error of the body and nothing after it,
while a returned list can still reach nobody. Say `exported` is a branch of a
`ctx.runAll` group, and a sibling fails after the body has returned. The group
cancels the branch, as [What a group hands back](#what-a-group-hands-back)
describes, and the list never reaches the caller. The body left the `try` long
before, and the sources stay open.

`ctx.onDiscard` runs exactly when the branch does not end `Done`: it fails, or
the group stops it. So it closes the list in that case too, and stays out of
the way when the list arrives. Each source gets a registration of its own, as
in the section above:

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

The registrations go on the very next line, before anything that can throw. An
error or a cancellation above them would leave the list open, as in the first
attempt.

## What `runAll` does not promise

A branch whose body has returned a value is not over yet: it waits for the rest
of the group, as
[Branches that wait for each other](#branches-that-wait-for-each-other) shows.
Three things one might expect do not happen:

| What one might expect | What happens |
| --- | --- |
| A branch the group stops stops its work | Only its waiting stops. A branch that waits through `ctx.abandonable` ends, and the operation behind it plays on. To stop the work itself, hand the cancellation to it with `ctx.onCancel` and wait for it with `ctx.join`. A branch created with `cancellable: false` refuses the stop, and the group waits for it |
| The children of the branch that failed are cancelled | They play out. A failure never passes down to children, and the group waits for them as for everything else |
| A branch whose body returned a value has its outcome | Its `outcome` is `null` and its `isCancelled` is `false` until the group decides. It can still end `Cancelled`: when another branch ends without a value, the group cancels it with `SiblingCancelReason`, and `isCancelled` becomes `true` |

Once the group has handed the list over, the decision is final. Every branch
ends `Done` with the value it gave. A cancellation that reaches a branch while
it is still unwinding is turned away, the parent's cascade included.
