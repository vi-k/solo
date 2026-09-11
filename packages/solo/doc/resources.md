# Resources and cleanup

A job may acquire a database, subscription or another resource. Register
its release at the moment of acquiring it, so no cancellation can leave
it behind:

```dart
Job<void> load() => run<Idle, void>(
      key: 'load',
      (ctx) async {
        final db = await ctx.join(
          Database.open,
          dispose: (db) => db.close(),
        );

        final rows = await ctx.join(db.readAll);
        ctx.emit(Loaded(rows));
      },
    );
```

`wait` and `join` accept a `dispose` callback for a resource that belongs
to the job. Here the database belongs to the load operation and only its
rows become controller state, so `dispose` closes it on success, failure
or cancellation — including when cancellation prevents the acquired value
from reaching the body at all. `Database`, `Idle` and `Loaded(rows)` are
types from that application's model.

For resources obtained elsewhere, `ctx.onDispose(cursor.close)` registers
a cleanup callback. It returns a function you can keep as
`removeDisposer` to unregister the callback without running it. Register
each release once: adding `ctx.onDispose(db.close)` to the example would
close the same database twice.

The job waits for children, then runs registered cleanup in reverse
registration order, awaiting each callback. Cleanup finishes before the
final state handler, outcome delivery and release of the queue. An ordinary
`try`/`finally` remains useful for local work; registered cleanup also
covers the period after the body returns and while its children finish.

## Returning or transferring a resource

```dart
// The database is this job's result, and its taker owns it on success.
SoloJob<Database> open() => run<Idle, Database>(
      key: _Op.open,
      (ctx) async {
        final db = await ctx.join(
          Database.open,
          discard: (db) => db.close(),
        );
        await ctx.run(job<Idle, void>((child) => child.join(db.readAll)));
        return db;
      },
    );
```

Use `discard` instead of `dispose` when the resource is the job's result
and its recipient will own it on success. The corresponding registration
method is `ctx.onDiscard`. These callbacks run when the job ends without
successfully handing out its result. They do not release a resource kept
only inside a successful body; use `dispose` for that case. A waiting call
accepts either `dispose` or `discard`, never both.

The child above is why the distinction earns its keep: the body has
returned the database, but the job is not complete. If cancellation
arrives during that wait, the caller receives `Cancelled` instead of the
resource, and `discard` releases it.

When transferring a registered resource directly to state, first check
the job and remove the resource's registration with `disown`. Given a
database acquired with `dispose` and a state that will own it:

```dart
ctx
  ..check()
  ..disown(db)
  ..emit(Ready(db));
```

These calls are synchronous. If `check` throws, cleanup still owns the
database. If `emit` writes the state and then throws because a synchronous
listener cancelled the job, the database is already owned by the state
and no longer registered for job cleanup.

For an asynchronous transfer, put the transfer and `disown` inside one
awaited `ctx.uncancellable` section. Use a plain `await` for the transfer
inside that section, followed immediately by `disown`. A context checkpoint
between the two could throw cancellation by state rules after ownership
has changed but before its cleanup registration is removed.

## Cleanup ordering and late results

The waiting method decides when the release happens, not whether it
happens:

```dart
// Abandoned on cancellation: the file can arrive after the job has
// finished. It is still deleted, but nobody is waiting for that.
await ctx.wait(openTemp, dispose: (file) => file.delete());

// Deleted before the next job starts and before close() comes back.
await ctx.join(openTemp, dispose: (file) => file.delete());
```

Use `join` when resource release must precede the next job or controller
closure.

Cancellation can arrive after the body returns, including during cleanup.
If a `discard` registration was skipped on the success path, it is run in
a second pass when cancellation makes it necessary. In that case it runs
after later-processed disposers rather than in strict reverse order.

Cleanup errors go to error hooks and observers, with a zone fallback
when no handler is installed. A `Cancelled` from cleanup is not reported
as an error. Never await the same job's `done`, `value` or `cancel()` from
its cleanup, or wait for a later job in the same queue: all of them depend
on the current cleanup finishing.
