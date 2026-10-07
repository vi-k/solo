# Resources and cleanup

A job that takes something — a database handle, a subscription, a lock, a
temporary file — has to give it back, and cancellation arrives at awaits, not
between statements. The context is where the release is registered, and the
member you pick decides who releases the resource and when:

```dart
(ctx) async {
  // Made here, on the spot: nothing arrives between the two lines.
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
| `ctx.disown(value)` | nothing — it drops the registration one of those three calls made for the value |

Four sections below open with the version this vocabulary leads to — the member
whose name matches the requirement, or the registration written where it reads
best — and say what that version does instead of what it was meant to do. Where
the next version repairs that and brings a fault of its own, it stands as a
second attempt. The version that works follows under its own heading.
`Database`, `device`, `openTemp` and `archive` belong to the application these
examples come from, and `Idle`, `Loaded(rows)` and `Ready(db)` are the states
of its controller.

## Taking a resource from a call

A job opens the database, reads the rows and publishes them. Cancelled at any
point, it must leave no database open.

### The first attempt

```dart
Job<void> load() => run<Idle, void>(
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

Cancel this job while `Database.open` is in flight. `join` stays with the call,
as it should, and the database finishes opening; then `join` throws `Cancelled`
in place of the value, and the body never reaches the line below. The database
is open, the only reference to it went with the throw, and the cleanup stack is
empty: nothing in this job knows that a database exists.

### The release travels with the call

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

`abandonable` and `join` take a `dispose` callback for a resource that belongs
to the job, and the rule is one: a value that did not reach the body is
released on the spot; a value that did goes on the cleanup stack and is
released when the job ends. Here the database belongs to the load operation and
only its rows become controller state, so `dispose` closes it on success, on
failure and on cancellation — including the cancellation that keeps the value
from the body.

`join` awaits that release before it throws, so the next job in the queue
starts with the database already closed. Register each release once: adding
`ctx.onDispose(db.close)` to this body would close the same database twice.

A resource the body makes itself has no such gap, because there is no await
between making it and registering its release: in the block at the top of this
page `ctx.onDispose(sub.cancel)` stands right under `listen`. That registration
returns a function you can keep as `removeDisposer` to unregister the callback
without running it.

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
action: it asks first whether the job has been cancelled, and throws instead of
starting. With a cancellation already standing — one an `uncancellable` section
above has just let through, say — the subscription is never made at all, where
that pair makes it and cancels it during cleanup. The page
[Cancellation](cancellation.md) is about those checkpoints.

## Returning a resource to the caller

Now the database is the result rather than a means: `open` below opens it and
returns it, and whoever takes that value — `await open().value` — owns it from
then on.

### The first attempt

```dart
Job<Database> open() => run<Idle, Database>(
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
callback that runs whatever the outcome looks like the safe one. Success is an
outcome too. The body returns the handle, cleanup runs before the outcome is
delivered, and `dispose` closes the database there — the caller's `await` then
completes with a handle that was closed a moment earlier.

Cancellation tests say nothing about this. On the cancelled path this job does
exactly what it should; it is the successful path that hands out a closed
database, and only a test that uses the result afterwards sees it.

### Discard, for a value that leaves

```dart
Job<Database> open() => run<Idle, Database>(
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

`discard` runs only when the job ends without handing its value over:
cancelled, or failed. The corresponding registration member is `ctx.onDiscard`.
A call takes either `dispose` or `discard`: passing both is an `ArgumentError`,
thrown before the call starts anything. Everything the job keeps to itself — a
lock, a temporary file, a subscription — stays with `dispose`, or it leaks on
the path where no cancellation test looks.

The child above is why the distinction earns its keep: `ctx.run` stands between
the database and the `return`, so the value is in hand while the job can still
be cancelled. A cancellation arriving during that wait ends the job before the
value leaves — the caller receives `Cancelled` instead of the database, and
`discard` closes it.

A registration is settled by the outcome of the job that made it, and it does
not travel with the value. A job that ended `Done` has handed the database over
whether or not anybody reads its `value`: a caller that never does leaves the
database open. Whoever takes the database owns it from that moment and
registers its release themselves — a parent that takes it through
`ctx.run(child, discard: ...)` registers on the call. A line below would be too
late: `ctx.run` checks the parent once the child's value is in hand, and a
checkpoint that throws there takes the value with it, so the line that would
have registered the release is never reached.
[A resource that travels](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cleanup.md#a-resource-that-travels)
on the cleanup page of `async_job` follows a database through such a hand-over.

## Handing a resource to the state

The screen is to hold the database itself. The job opens it and migrates it, in
a step that must not be cut short; then `Ready(db)` becomes the state, and from
there the database is the controller's to close, not the job's.

### The first attempt

```dart
final db = await ctx.join(
  Database.open,
  dispose: (db) => db.close(),
);
await ctx.uncancellable(db.migrate);
ctx.emit(Ready(db));
```

The write goes through and the screen shows `Ready`. Then the body returns, the
job unwinds its cleanup stack, and `dispose` closes the database the screen is
holding. The state object does not change when that happens: the screen keeps a
handle that looks exactly as it did, and the failure surfaces at the first read
from it.

### The second attempt

```dart
await ctx.uncancellable(db.migrate);
ctx
  ..disown(db)
  ..emit(Ready(db));
```

`disown` drops the registration `join` made for the database, so the job no
longer closes what it is about to give away. It also drops it before anything
checks whether the write will happen at all.

`emit` is a checkpoint: for a job that has accepted cancellation it throws
`Cancelled` instead of writing. Cancel this job while the migration runs. The
`uncancellable` section holds the cancellation back until the migration is
over, the job accepts it as the section closes, and it comes out at the first
checkpoint after that. Here that checkpoint is `emit`, and by the time it
throws, the registration is already gone: the state never received the
database, the cleanup stack no longer knows about it, and nobody closes it.

### Check, disown, emit

```dart
await ctx.uncancellable(db.migrate);
ctx
  ..check()
  ..disown(db)
  ..emit(Ready(db));
```

The three calls of the cascade are synchronous, so nothing arrives between
them. `check` throws first if the job is cancelled or its rules no longer hold,
and the database is still registered: cleanup closes it. If `emit` writes the
state and then throws because a synchronous listener cancelled the job, the
state already owns the database and the cleanup stack no longer does. Either
way exactly one owner is left.

`disown` finds the registration by the value `join` returned. One made with
`ctx.onDispose` is not found that way — `disown` returns `false`, and the
callback still runs — and is dropped by the function `onDispose` returned,
called where `disown` stands here.

After the hand-over no job releases the database, and neither does `close()`.
Closing it is the controller's own work: a method whose job closes the database
and moves the state on, awaited before `close()`, as `dispose()` is in
[Awaiting the disposal](camera.md#awaiting-the-disposal) of the camera example.

For an asynchronous hand-over, the transfer and `disown` go inside one awaited
`uncancellable` section:

```dart
await ctx.uncancellable(() async {
  await archive.take(file);
  ctx.disown(file);
});
```

Neither line of the section is a checkpoint: the transfer is awaited plainly,
and `disown` only unregisters, so a cancellation has nowhere to come out
between them. The section holds an ordinary cancellation back until both are
done, and the state rules of the job, which no section holds, are asked where
the section opens, before the transfer starts. Written without the section, as
`await ctx.join(() => archive.take(file))` with `ctx.disown(file)` on the line
under it, the pair comes apart: `join` checks the job again after the transfer,
and a cancellation accepted meanwhile makes it throw with the file already in
the archive and its registration still standing, so cleanup deletes what the
archive is holding.

## When the release happens

A job writes a temporary file and deletes it whatever happens. The next job in
the queue must not find it, and neither must `close()` when it returns.

### The first attempt

```dart
// Deleted whatever happens: dispose runs on every outcome.
await ctx.abandonable(openTemp, dispose: (file) => file.delete());
```

The release happens either way; the waiting method decides only when.
`abandonable` lets go of the call the moment cancellation is accepted: the job
ends, and the next job starts, or `close()` comes back, while `openTemp` is
still running. The file appears after that, and the deletion follows it — late
and alone, with nobody waiting for either. A late error from the call or from
the disposer is told to the controller's `onError` hook and then handed to
`Solo.errorHandler`, or to the zone when no handler is set.

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
results they can bring:
[Cleanup order and late results](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cleanup.md#cleanup-order-and-late-results)
on the cleanup page of `async_job` is where that order is described and kept. A
controller adds the last row. The outcome is fixed first; then the state
handler passed to `run` computes the state a failed or cancelled job leaves
behind, as
[State after failure or cancellation](state.md#state-after-failure-or-cancellation)
on the state page describes; then the queue starts its next job. Code that
awaits `done` or `value` resumes after that start.

An ordinary `try`/`finally` is for what does not outlive the body: a lock held
for one step and released before the body goes on, a temporary of one turn of a
loop. A checkpoint throwing inside the `try` runs the `finally` like any other
throw, and registering those releases instead would hold them to the end of the
job and pile up one registration per turn. Registered cleanup is for what must
live that long, and it alone covers the time after the body returns and while
its children finish.

An error thrown by cleanup is told to the controller's `onError` hook and to
`Solo.observer`, and then handed to `Solo.errorHandler`, or to the zone when no
handler is set; [Answering for an error](errors.md#answering-for-an-error) on
the errors page has the whole route. A `Cancelled` thrown by cleanup goes the
same way and stops short of the zone: a cancellation is a decision somebody
made, not a failure. Neither changes the outcome of the job — cleanup that
throws leaves a `Done` job `Done`.

Never await the same job's `done`, `value` or `cancel()` from its cleanup: each
completes only after that cleanup, so the wait never ends, and neither does a
`close()` that waits for the job. A later job of the same queue cannot start
until this one is over, so waiting for it holds the queue for as long as that
job stays queued. `pending` reports such a job as `in its cleanup`;
[What is holding the controller](errors.md#what-is-holding-the-controller) on
the errors page shows how to read it.
