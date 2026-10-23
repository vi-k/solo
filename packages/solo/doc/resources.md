# Resources and cleanup

A job that takes something, such as a database handle, a subscription, a lock
or a temporary file, has to give it back. Cancellation arrives at awaits and
from code a statement calls, never from the queue between two statements. The
context is where the release is registered, and the member you pick decides who
releases the resource and when:

```dart
(ctx) async {
  // Made here, on the spot: the release is registered on the next line,
  // even if `listen` has cancelled the job.
  final sub = device.events.listen(onEvent);
  ctx.onDispose(sub.cancel);

  // Taken from a call: the release goes on the call, not under it.
  final db = await ctx.join(Database.open, dispose: (db) => db.close());

  // Leaves with the result, so it is released only if the job ends
  // cancelled or failed.
  final file = await ctx.join(openTemp, discard: (file) => file.delete());

  // Handed to the state, which owns it from here on.
  ctx
    ..check()
    ..disown(db)
    ..emit(Ready(db));

  return file;
}
```

| Member | What it releases, and when |
| --- | --- |
| `dispose:` on `ctx.abandonable`, `ctx.join` or `ctx.run` | that call's value, whatever the outcome |
| `discard:` on `ctx.abandonable`, `ctx.join` or `ctx.run` | that call's value, and only if the job ends cancelled or failed |
| `ctx.onDispose(callback)` | whatever the callback closes, whatever the outcome |
| `ctx.onDiscard(callback)` | whatever the callback closes, and only if the job ends cancelled or failed |
| `ctx.disown(value)` | nothing: it drops the registration one of those three calls made for the value |

`Database`, `device`, `openTemp` and `archive` belong to the application these
examples come from, and `Idle`, `Loaded(rows)` and `Ready(db)` are the states
of its controller.

## Taking a resource from a call

A job opens the database, reads the rows and publishes them. Cancelled at any
point, it must leave no database open.

### The first attempt

```dart
// The first attempt: a cancellation fits between open and onDispose.
Job<void> load() => enqueue<Idle, void>(
      key: 'load',
      (ctx) async {
        final db = await ctx.join(Database.open);
        ctx.onDispose(db.close);

        final rows = await ctx.join(db.readAll);
        ctx.emit(Loaded(rows));
      },
    );
```

`onDispose` is the member for a resource the job releases whatever happens, and
the line under the acquisition is where it reads best. Those two lines are one
step for the reader but two for the engine, and a cancellation fits between
them.

Cancel this job while `Database.open` is in flight. This is what happens:

1. `join` stays with the call, as it should, and the database finishes opening.
2. Then `join` throws `Cancelled` in place of the value, and the body never
   reaches the line below.
3. The database is open, and the only reference to it went with the throw.
4. The cleanup stack is empty: nothing in this job knows that a database
   exists.

### The release travels with the call

```dart
Job<void> load() => enqueue<Idle, void>(
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

`abandonable` and `join` take a `dispose` callback for a resource that belongs
to the job, and the rule is one:

- a value that did not reach the body is released on the spot;
- a value that did goes on the cleanup stack and is released when the job ends.

Here the database belongs to the load operation, and only its rows become
controller state. So `dispose` closes it on success, on failure and on
cancellation, including the cancellation that keeps the value from the body.

`join` awaits that release before it throws, so the next job in the queue
starts with the database already closed. Register each release once: adding
`ctx.onDispose(db.close)` to this body would close the same database twice.

A resource the body makes itself has no such gap, because there is no await
between making it and registering its release. In the block at the top of this
page, `ctx.onDispose(sub.cancel)` stands right under `listen`. Code that
`listen` calls, such as the `onListen` of the source, may cancel the job before
`listen` returns; `onDispose` still takes the registration on a job that is
cancelled and still running, and the release runs with the rest. That
registration returns a function you can keep as `removeDisposer` to unregister
the callback without running it.

Nothing stops such a creation from riding on a call all the same:

```dart
final sub = await ctx.join(
  () => device.events.listen(onEvent),
  dispose: (sub) => sub.cancel(),
);
```

`abandonable` and `join` take an action that returns without waiting, so a
synchronous creation registers on the call like any other. What it buys over
`listen` with `onDispose` under it is the checkpoint the call makes before its
action. The call asks first whether the job has been cancelled, and throws
instead of starting. Take a cancellation already standing, such as one an
`uncancellable` section above has just let through. In that case the
subscription is never made at all, where that pair makes it and cancels it
during cleanup. The page [Cancellation](cancellation.md) is about those
checkpoints.

## Returning a resource to the caller

Now the database is the result rather than a means: `open` below opens it and
returns it. Whoever takes that value, as `await open().value` does, owns it
from then on.

### The first attempt

```dart
// The first attempt: success closes the database it hands out.
Job<Database> open() => enqueue<Idle, Database>(
      key: 'open',
      (ctx) async {
        final db = await ctx.join(
          Database.open,
          dispose: (db) => db.close(),
        );
        await ctx.run(job<Idle, void>((child) => child.join(db.readAll)));
        return db;
      },
    );
```

The database is still this job's to release if the job falls over, so the
callback that runs whatever the outcome looks like the safe one. But success is
an outcome too:

1. The body returns the handle.
2. Cleanup runs before the outcome is delivered, and `dispose` closes the
   database there.
3. The caller's `await` then completes with a handle that was closed a moment
   earlier.

Cancellation tests say nothing about this. On the cancelled path this job does
exactly what it should. It is the successful path that hands out a closed
database, and only a test that uses the result afterwards sees it.

### Discard, for a value that leaves

```dart
Job<Database> open() => enqueue<Idle, Database>(
      key: 'open',
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

`discard` runs only when the job does not end `Done`: cancelled, or failed. The
corresponding registration member is `ctx.onDiscard`. A call takes either
`dispose` or `discard`: passing both is an `ArgumentError`, thrown before the
call starts anything. Everything the job keeps to itself, such as a lock, a
temporary file or a subscription, stays with `dispose`. Otherwise it leaks on
the path where no cancellation test looks.

The child above is why the distinction earns its keep. `ctx.run` stands between
the database and the `return`, so the value is in hand while the job can still
be cancelled. A cancellation arriving during that wait ends the job before the
value leaves: the caller receives `Cancelled` instead of the database, and
`discard` closes it.

A registration is settled by the outcome of the job that made it, and it does
not travel with the value. A job that ended `Done` has handed the database over
whether or not anybody reads its `value`, and a caller that never does leaves
the database open. Whoever takes the database owns it from that moment and
registers its release themselves. A parent that takes it through
`ctx.run(child, discard: ...)` registers on the call. A registration on the
line below would be too late. `ctx.run` checks the parent once the child's
value is in hand, and a checkpoint that throws there takes the value with it.
So the line that would have registered the release is never reached.
[A resource that travels](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cleanup-rules.md#a-resource-that-travels)
on the cleanup rules page of `async_job` follows a database through such a
hand-over.

## Handing a resource to the state

The screen is to hold the database itself. The job opens it and migrates it, in
a step that must not be cut short. Then `Ready(db)` becomes the state, and from
there the database is the controller's to close, not the job's.

### The first attempt

```dart
// The first attempt: dispose closes the database the state holds.
final db = await ctx.join(
  Database.open,
  dispose: (db) => db.close(),
);
await ctx.uncancellable(db.migrate);
ctx.emit(Ready(db));
```

This is what happens:

1. The write goes through, and the screen shows `Ready`.
2. Then the body returns, and the job unwinds its cleanup stack.
3. `dispose` closes the database the screen is holding.
4. The state object does not change when that happens. The screen keeps a
   handle that looks exactly as it did, and the failure surfaces at the first
   read from it.

### The second attempt

```dart
// The second attempt: disown comes before the emit that may throw.
await ctx.uncancellable(db.migrate);
ctx
  ..disown(db)
  ..emit(Ready(db));
```

`disown` drops the registration `join` made for the database, so the job no
longer closes what it is about to give away. It also drops it before anything
checks whether the write will happen at all.

`emit` is a checkpoint: for a job that has accepted cancellation it throws
`Cancelled` instead of writing.

Cancel this job while the migration runs. This is what happens:

1. The `uncancellable` section holds the cancellation back until the migration
   is over.
2. The job accepts the cancellation as the section closes, and the cancellation
   comes out at the first checkpoint after that. Here that checkpoint is
   `emit`.
3. By the time `emit` throws, the registration is already gone.
4. The state never received the database, the cleanup stack no longer knows
   about it, and nobody closes it.

### Check, disown, emit

```dart
await ctx.uncancellable(db.migrate);
ctx
  ..check()
  ..disown(db)
  ..emit(Ready(db));
```

The three calls of the cascade are synchronous, so nothing arrives between
them. If `check` throws, which it does first when the job is cancelled or its
rules no longer hold, the database is still registered, and cleanup closes it.
If `emit` writes the state and then throws, because a synchronous listener
cancelled the job, the state already owns the database. The cleanup stack no
longer does. Either way exactly one owner is left.

`disown` finds the registration by the value `join` returned. One made with
`ctx.onDispose` is not found that way: `disown` returns `false`, and the
callback still runs. That one is dropped by the function `onDispose` returned,
called where `disown` stands here.

After the hand-over no job releases the database, and neither does `close()`.
Closing it is the controller's own work. The controller needs a method for it:
the method's job closes the database and moves the state on, and the method is
awaited before `close()`, as `dispose()` is in
[Awaiting the disposal](camera.md#awaiting-the-disposal) of the camera example.

For an asynchronous hand-over, the transfer and `disown` go inside one awaited
`uncancellable` section:

```dart
await ctx.uncancellable(() async {
  await archive.take(file);
  ctx.disown(file);
});
```

Neither line of the section is a checkpoint. The transfer is awaited plainly,
and `disown` only unregisters, so a cancellation has nowhere to come out
between them. The section holds an ordinary cancellation back until both are
done. The state rules of the job, which no section holds, are asked where the
section opens, before the transfer starts.

Without the section the pair comes apart. Take
`await ctx.join(() => archive.take(file))` with `ctx.disown(file)` on the line
under it: `join` checks the job again after the transfer, and a cancellation
accepted meanwhile makes it throw. The file is already in the archive then, and
its registration is still standing, so cleanup deletes what the archive is
holding.

## When the release happens

A job writes a temporary file and deletes it whatever happens. The next job in
the queue must not find it, and neither must `close()` when it returns.

### The first attempt

```dart
// The first attempt: the file is deleted late and alone.
// Deleted whatever happens: dispose runs on every outcome.
await ctx.abandonable(openTemp, dispose: (file) => file.delete());
```

The release happens either way, and the waiting method decides only when.
`abandonable` lets go of the call the moment cancellation is accepted:

1. The job ends, and the next job starts, or `close()` comes back, while
   `openTemp` is still running.
2. The file appears after that, and the deletion follows it, late and alone,
   with nobody waiting for either.

A late error from the call or from the disposer is told to the controller's
`onError` hook and then handed to `Solo.unansweredHandler`, or to the zone when
no handler is set.

### The wait that stays with it

```dart
// Deleted before the next job starts and before close() comes back.
await ctx.join(openTemp, dispose: (file) => file.delete());
```

`join` waits for the call, releases the value it was handed, and only then
throws. The deletion is part of what the queue waits for, so the next job never
starts against a file this one is still deleting. Use `join` when resource
release must precede the next job or controller closure.

## Cleanup order and late results

| Step | What the job does |
| --- | --- |
| Children | waits for every child to finish |
| Cleanup stack | runs it last registration first, awaiting each callback |
| Second pass | runs a `discard` that cancellation has since made necessary |
| End | gets its outcome, runs its state handler, lets the queue start the next job |

The first three steps belong to the core, `async_job`, and so do the late
results they can bring.
[Cleanup order and late results](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cleanup-rules.md#cleanup-order-and-late-results)
on the cleanup rules page of `async_job` describes that order and keeps it. A
controller adds the last row:

1. The outcome is fixed first.
2. Then the state handler passed to `enqueue` computes the state a failed or
   cancelled job leaves behind, as
   [State after failure or cancellation](state.md#state-after-failure-or-cancellation)
   on the state page describes.
3. Then the queue starts its next job.

Code that awaits `done` or `value` resumes after that start.

An ordinary `try`/`finally` is for what does not outlive the body: a lock held
for one step and released before the body goes on, a temporary of one turn of a
loop. A checkpoint throwing inside the `try` runs the `finally` like any other
throw. Registering those releases instead would hold them to the end of the job
and pile up one registration per turn. Registered cleanup is for what must live
that long, and it alone covers the time after the body returns and while its
children finish.

An error thrown by cleanup is told to the controller's `onError` hook and to
`Solo.observer`. Then it is handed to `Solo.unansweredHandler`, or to the zone
when no handler is set.
[Answering for an error](errors.md#answering-for-an-error) on the errors page
has the whole route. A `Cancelled` thrown by cleanup is told to the same two
and goes no further: a cancellation is a decision somebody made, not a failure.
Neither changes the outcome of the job: cleanup that throws leaves a `Done` job
`Done`.

Never await the same job's `done`, `value` or `cancel()` from its cleanup. Each
completes only after that cleanup, so the wait never ends, and neither does a
`close()` that waits for the job. A later job of the same queue cannot start
until this one is over, so waiting for it holds the queue for as long as that
job stays queued. `pending` reports such a job as `in its cleanup`, with the
later one among those `queued` behind it.
[What is holding the controller](diagnostics.md#what-is-holding-the-controller)
on the diagnostics page shows how to read it.
