# Cleanup

A job may take a lock, open a database or create a temporary file, and its
children may still be using them after the body returns. Register the release
with the context, at the point where the resource is acquired, and the job runs
it when the whole job finishes:

```dart
final lock = await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

await ctx.join(() => database.migrate());

return database;
```

| What the job holds | Member | When it runs |
| --- | --- | --- |
| What it keeps to itself, from a call: a lock, a temporary file, a subscription | `dispose` of `abandonable`, `join` or `run` | on every outcome |
| What the body returns or hands outside, from a call | `discard` of `abandonable`, `join` or `run` | unless the job ends `Done` |
| What it keeps to itself, with no call to wrap | `ctx.onDispose` | on every outcome |
| What the body returns or hands outside, with no call to wrap | `ctx.onDiscard` | unless the job ends `Done` |
| A value of `abandonable`, `join` or `run` that changes hands | `ctx.disown(value)` | never: it drops the registration the call made |

Passing a `dispose` and a `discard` to one call is an `ArgumentError`.

This page chooses between `dispose` and `discard` and closes a value the job
keeps back. [Cleanup rules](cleanup-rules.md) goes on from there: a resource
handed from one job to another, `ctx.onDispose` and `ctx.onDiscard` where there
is no call to wrap, the order of cleanup and a value that comes late.

The lines under the code below are what it prints when it runs. The lock and
the database say what happens to them, and `outcome:` is how the job ends.

## Choosing the callback

A job takes a lock for the work it does and opens a database it returns to
whoever asked for it. The lock is needed by the work of the job, and the
database by the caller, if it reaches one; neither may live longer than it is
needed. The job succeeds.

### The first attempt

Both resources leave with the same job, so the same callback looks right for
both:

```dart
// The first attempt: on success the lock is never released.
final lock = await ctx.join(Lock.acquire, discard: (lock) => lock.release());
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

return database;
```

```text
lock acquired
database opened
outcome: Done(database)
```

The lock is never released. This is what happens:

1. `discard` runs only when the job does not end `Done`.
2. A job that returns the database ends `Done(database)`, so neither `discard`
   runs.
3. The database stays open for the caller, as it should, and the lock stays
   held for as long as the process lives.

Cancelled or failed, the job releases both; only the path it is written for
leaks the lock. A test that cancels the job sees nothing wrong, because on that
path the callback does run.

### `dispose` for what the job keeps

```dart
final lock = await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

return database;
```

```text
lock acquired
database opened
lock released
outcome: Done(database)
```

| Resource | Callback | The job is done | The job fails or is cancelled |
| --- | --- | --- | --- |
| What the job keeps to itself: a lock, a temporary file, a subscription | `dispose` | released | released |
| What the body returns or hands outside | `discard` | handed over open | released |

A branch of `ctx.runAll` releases later than its body ends. It starts unwinding
only when every branch of the group has ended its body and waited for its
children, or when the body of one of them has ended in anything but a value. A
lock two branches share stays taken until then. The branch waiting for it keeps
the group from getting there, so the group hangs.
[Branches that wait for each other](groups.md#branches-that-wait-for-each-other)
on the groups page shows the hang and how to take such a lock.

Each callback is awaited, so the job ends only after the last of them is over.
Whoever waits for the job waits for them too: a `solo` controller completes
`close()` only once the cleanup of the job it cancelled has run.

The job keeps the callbacks it registers on its cleanup stack. They run after
the body ends, and cancellation does not interrupt them: neither one already
accepted nor one arriving into the unwinding itself. `check`, `abandonable`,
`join`, `pause`, `uncancellable`, `run`, `start`, `runAll`, `each` and
`onCancel` are the body's and throw `StateError` here, so a callback must await
its resource directly. On a cancelled job `check` throws the job's `Cancelled`
instead, as it does once the job has finished. So an action the body walked
away from, polling `check` to stop, gets the cancellation it waits for.

Two releases do not wait for the stack. A checkpoint that throws on a value
that has just arrived releases it on the spot, before the body hears the
cancellation, as
[Registering on arrival](cleanup-rules.md#registering-on-arrival) shows. A
value that comes late is released when it comes, during the body or after the
job has ended, as
[A value that comes late](cleanup-rules.md#a-value-that-comes-late) describes.
Both sections are on the cleanup rules page.

A callback must not await its own job: `done`, `value` and `cancel()` all
complete after the cleanup that would be waiting for them. Keep callbacks
short, and let them wait for nothing but the release itself: nothing will
interrupt them. An error from one goes to `onError` and, by default, on to the
[zone](errors.md#where-errors-go), and the remaining callbacks still run; a
`Cancelled` stops at `onError`.

## A value the job keeps back

A job opens a database for its caller and hands it over only when the schema is
current. Otherwise it returns `null`, and the caller migrates first. This time
the schema is out of date.

### The first attempt

```dart
// The first attempt: the database the job keeps back stays open.
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

if (!await ctx.join(database.isCurrent)) {
  return null;
}

return database;
```

```text
database opened
outcome: Done(null)
```

The database is never closed, and nobody holds it. This is what happens:

1. `discard` runs only when the job does not end `Done`.
2. `return null` ends the job `Done(null)`. `discard` asks how the job ended,
   not where the database went, so it does not run.

The debug channel, switched on with `Job.debug = print;`, names the value the
job ended without:

```text
Job() ended Done(null) without the value of 1 conditional cleanup (database): unless it is inside the result, nothing will dispose of it
```

### Closing what the job keeps back

```dart
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

if (!await ctx.join(database.isCurrent)) {
  ctx.disown(database);
  await database.close();
  return null;
}

return database;
```

```text
database opened
database closed
outcome: Done(null)
```

The body that keeps the value back closes it itself, and takes the registration
back first. A cancellation may come while the database closes and end the job
`Cancelled`; without `ctx.disown` the `discard` would then close the database a
second time. `ctx.disown` looks the value up by identity and returns whether it
found one, so pass it the very instance the call returned.
