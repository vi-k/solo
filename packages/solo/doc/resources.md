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

  // Leaves with the result, so it is released only if it reaches nobody.
  final file = await ctx.join(openTemp, discard: (file) => file.delete());

  // Handed to the state, which owns it from here on.
  ctx
    ..check()
    ..disown(db)
    ..emit(Ready(db));
}
```

| Member | What it releases, and when |
| --- | --- |
| `dispose:` on `wait` or `join` | that call's value, whatever the outcome |
| `discard:` on `wait` or `join` | that call's value, and only if it reaches nobody |
| `ctx.onDispose(callback)` | whatever the callback closes, whatever the outcome |
| `ctx.onDiscard(callback)` | the same, and only if the job hands nothing over |
| `ctx.disown(value)` | nothing — it drops the registration a `wait` or `join` made |

Four sections below open with the version this vocabulary leads to — the member
whose name matches the requirement, or the registration written where it reads
best — and say what that version does instead of what it was meant to do. Where
the next version repairs that and brings a fault of its own, it stands as a
second attempt. The version that works follows under its own heading.
`Database`, `Idle`, `Loaded(rows)` and `Ready(db)` are types from that
application's model.

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
step for the reader and two for the engine, and a cancellation fits between
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

`wait` and `join` take a `dispose` callback for a resource that belongs to the
job, and the rule is one: a value that did not reach the body is released on
the spot; a value that did goes on the cleanup stack and is released when the
job ends. Here the database belongs to the load operation and only its rows
become controller state, so `dispose` closes it on success, on failure and on
cancellation — including the cancellation that keeps the value from the body.

`join` awaits that release before it throws, so the next job in the queue
starts with the database already closed. Register each release once: adding
`ctx.onDispose(db.close)` to this body would close the same database twice.

A resource the body makes itself has no such gap, because there is no await
between making it and registering its release — `ctx.onDispose(sub.cancel)`
stands right under `listen`. That registration returns a function you can keep
as `removeDisposer` to unregister the callback without running it.

## Returning a resource to the caller

Now the database is the result rather than a means: the job opens it, and the
caller owns it from `final db = await files.open().value`.

### The first attempt

```dart
SoloJob<Database> open() => run<Idle, Database>(
      key: _Op.open,
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

`discard` runs only when the job ends without handing its value over:
cancelled, or failed. The corresponding registration member is `ctx.onDiscard`.
A waiting call accepts either `dispose` or `discard`, never both. Everything
the job keeps to itself — a lock, a temporary file, a subscription — stays with
`dispose`, or it leaks on the path where no cancellation test looks.

The child above is why the distinction earns its keep: the body has returned
the database, but the job is not complete. If cancellation arrives during that
wait, the caller receives `Cancelled` instead of the resource, and `discard`
closes it.

A registration is settled by the outcome of the job that made it, and it does
not travel with the value. Whoever takes the database owns it from that moment
and registers its release themselves — a parent that takes it through
`ctx.run(child, discard: ...)` registers on the call, and `doc/children.md`
says why that cannot wait for the line below.

## Handing a resource to the state

The screen is to hold the database itself: `Ready(db)` becomes the state, and
the controller closes it when it closes.

### The first attempt

```dart
final db = await ctx.join(
  Database.open,
  dispose: (db) => db.close(),
);
ctx.emit(Ready(db));
```

The write goes through and the screen shows `Ready`. Then the body returns, the
job unwinds its cleanup stack, and `dispose` closes the database the screen is
holding. The state object does not change when that happens: the screen keeps a
handle that looks exactly as it did, and the failure surfaces at the first read
from it.

### The second attempt

```dart
ctx
  ..disown(db)
  ..emit(Ready(db));
```

`disown` drops the registration the call made, so the job no longer closes what
it is about to give away. It also drops it before anything checks whether the
write will happen at all.

`emit` is a checkpoint: for a job that has accepted cancellation it throws
`Cancelled` instead of writing. Cancellation reaching a body between a
protected step and this cascade is ordinary — `uncancellable` holds it back and
the checkpoint after the section is where it comes out. Here that checkpoint is
`emit`, and by the time it throws, the registration is already gone: the state
never received the database, the cleanup stack no longer knows about it, and
nobody closes it.

### Check, disown, emit

```dart
ctx
  ..check()
  ..disown(db)
  ..emit(Ready(db));
```

These calls are synchronous, so nothing arrives between them. `check` throws
first if the job is cancelled or its rules no longer hold, and the database is
still registered: cleanup closes it. If `emit` writes the state and then throws
because a synchronous listener cancelled the job, the state already owns the
database and the cleanup stack no longer does. Either way exactly one owner is
left.

For an asynchronous hand-over, the transfer and `disown` go inside one awaited
`uncancellable` section:

```dart
await ctx.uncancellable(() async {
  await archive.take(file);
  ctx.disown(file);
});
```

Use a plain `await` for the transfer inside that section. A context checkpoint
between the transfer and `disown` — `ctx.join(() => archive.take(file))` is
one — throws after ownership has changed and before the registration is
dropped, and cleanup then deletes a file the archive is holding.

## When the release happens

A job writes a temporary file and deletes it whatever happens. The next job in
the queue must not find it, and neither must `close()` when it returns.

### The first attempt

```dart
// Abandoned on cancellation: the file can arrive after the job has
// finished. It is still deleted, but nobody is waiting for that.
await ctx.wait(openTemp, dispose: (file) => file.delete());
```

The waiting method decides when the release happens, not whether it happens.
`wait` lets go of the call the moment cancellation is accepted: the job ends,
the queue moves on, and the next job starts while `openTemp` is still running.
The file appears after that, and the deletion follows it — late and alone, with
nobody waiting for either. A late error from the call or from the disposer goes
to the controller's error hook.

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
| End | final state handler, outcome delivery, release of the queue |

An ordinary `try`/`finally` remains useful for local work; registered cleanup
also covers the period after the body returns and while its children finish.

Cancellation can arrive after the body returns, including during cleanup. A
`discard` registration skipped on the success path then runs in a second pass,
after the disposers processed before it rather than in the strict reverse order
of registration.

Cleanup errors go to the controller's error hook and to observers, and with no
handler installed the error reaches the zone. A `Cancelled` thrown by cleanup
takes the same route to the hook and the observer, and never reaches the zone:
a cancellation is a decision somebody made, not a failure. The outcome of the
job is not affected by either — cleanup that throws leaves a `Done` job `Done`.

Never await the same job's `done`, `value` or `cancel()` from its cleanup, or
wait for a later job in the same queue: all of them depend on the current
cleanup finishing, and the wait never ends.
