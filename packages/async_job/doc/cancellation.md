# Cancellation

`cancel()` requests; the body answers at a checkpoint. Which checkpoint it is
decides what happens to the operation behind it:

```dart
Job<void>((ctx) async {
  // The database's own stop, cancelled together with the job.
  final stop = CancelToken();
  ctx.onCancel(stop.cancel);

  // The wait ends at once; the read goes on, and its value is dropped.
  final rows = await ctx.wait(database.readAll);

  // Waited for until the migration ends or stops at the token, and
  // only then does the job give up.
  await ctx.join(() => database.migrate(stop));

  // The cancellation waits for the whole step, and the child it
  // runs is not cancelled; the next checkpoint throws it.
  await ctx.uncancellable(() async {
    await database.writeVersion();
    await ctx.run(database.readyFlag());
  });

  // Nothing to wrap between the steps of a calculation.
  ctx.check();
  use(rows);
});
```

| Method | If cancellation arrives while it waits |
| --- | --- |
| `ctx.wait(action)` | Throws `Cancelled` at once. The action continues; its result is dropped, or goes to the call's `dispose` or `discard` if it has one. |
| `ctx.join(action)` | Waits for the action, then throws `Cancelled` instead of returning the value, or the action's own error if it failed. If the call has a `dispose` or `discard`, the value goes there first, and `join` throws once that callback has finished. |
| `ctx.uncancellable(action)` | Holds the request until the section ends: no `onCancel`, no cascade to children while it runs. |
| `ctx.check()` | Throws when the job has already accepted cancellation. |

A running job accepts the request inside `cancel()` itself, unless an
`uncancellable` section holds it back or the job was created with
`cancellable: false`. Accepting it makes the job cancelled: its `onCancel`
callbacks run, the cancellation passes to the children it has started, and the
job ends `Cancelled` whatever the body does next. From then on `check`, `wait`,
`join`, `uncancellable`, `run` and `each` throw `Cancelled` at their
checkpoints. `onCancel` throws too: its callbacks have already run, and one
registered now never would. `onDispose`, `onDiscard`, `disown` and `unattended`
remain available so the body can arrange cleanup after cancellation.

Inside an action passed to the context, a plain `await` is right: the context
adds no checkpoint between the steps of that action, and a step that needs a
check of its own takes a context call of its own.

The lines under the code are what it prints when it runs. The database says
what it writes, and the job's observer prints what reaches it: `log:` for
`ctx.log`, `onError:` for an error. `cancel` is the moment the user cancels,
`outcome:` is what `job.done` completes with, and `zone:` is an error that
reached the zone uncaught. Each section below opens with the version the names
lead to — `wait` to wait for an operation, `join` to see a step through, a
clause for `Cancelled` to let the cancellation pass, Dart's `unawaited` for
work nobody waits for — and shows what that code does. Where the version that
repairs it still falls short, it stands as a second attempt, and the version
that works follows under its own heading.

## Stopping the operation

The job opens a database, migrates it and hands it over; `discard` closes it
when the job ends without handing it over. The migration takes three steps of
10 ms and reads a `CancelToken` before each; finding it cancelled, it stops by
throwing `DatabaseStopped`. When the user cancels, the migration should stop,
and the database should close once nothing writes into it. The user cancels
during the second step, 15 ms in.

### The first attempt

`wait` waits for the migration:

```dart
final job = Job<Database>((ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );
  final stop = CancelToken();

  await ctx.wait(() => database.migrate(stop));

  return database;
});
```

```text
step 1
cancel
database closed
outcome: Cancelled(manual)
step 2 on a closed database
step 3 on a closed database
```

`wait` ends the waiting, not the migration. The cancellation comes out of
`wait` at once, the job ends, and `discard` closes the database with two steps
of the migration still to write. Whatever the migration throws afterwards goes
to `onError`. `wait` is for an operation the job may walk away from, such as a
read whose result nobody needs any more.

A result arriving that late is dropped, or goes to the `dispose` or `discard`
passed to `wait`: while the job is still finishing, that callback joins its
cleanup stack and the job awaits it; once the job has finished, the callback
runs on its own.

### The second attempt

`join` stays with the migration to its end:

```dart
await ctx.join(() => database.migrate(stop));
```

```text
step 1
cancel
step 2
step 3
database closed
outcome: Cancelled(manual)
```

Nothing writes into a closed database now: `join` waits for the migration, and
the job gives up only after it. But nothing told the migration to stop either,
so it writes the step nobody wants any more, and the outcome arrives when the
migration would have ended anyway.

### A token through `onCancel`

The migration knows nothing about the job's cancellation: it listens only to
its token. `onCancel` cancels the token together with the job:

```dart
final stop = CancelToken();
ctx.onCancel(stop.cancel);

await ctx.join(() => database.migrate(stop));
```

```text
step 1
cancel
step 2
migration stopped
onError: DatabaseStopped
database closed
outcome: Cancelled(manual)
```

`ctx.onCancel(callback)` runs synchronously when the job accepts the
cancellation, before the body reaches a checkpoint. It cancels the token, the
migration reads it before the third step and throws `DatabaseStopped`, and
`join` waits for that before the job closes the database. A request to abort or
a subscription to cancel is handed over the same way.

The `onError:` line is that `DatabaseStopped`. `join` throws an error of its
action as it is, even after a cancellation, and the body does not catch it. The
job still ends `Cancelled`, so the error is nobody's outcome: it reaches the
observer and stops there, and without an observer nothing hears it. What a
`catch` around this `join` sees is the subject of the section on catching,
below.

## A step that must finish

The migration is over, and the last step marks the database ready: it writes
the schema version and then the ready flag, and a database with the version and
no flag is neither old nor ready. The two writes are two calls of the database,
`writeVersion` and `writeReadyFlag`. The user cancels while the version is
being written.

### The first attempt

`join` waits for its action, so each write goes through one:

```dart
await ctx.join(database.writeVersion);
await ctx.join(database.writeReadyFlag);
```

```text
cancel
version written
outcome: Cancelled(manual)
```

The step does not finish: the database is left with a version and no ready
flag. Each `join` is a checkpoint of its own. The first one waits for the
version and then throws the cancellation, and the body never reaches the
second.

### One `join` for the step

```dart
await ctx.join(() async {
  await database.writeVersion();
  await database.writeReadyFlag();
});
```

```text
cancel
version written
ready flag written
outcome: Cancelled(manual)
```

The action has no checkpoint inside, so both writes are made, and the
cancellation comes out of `join` after them. That is enough while the step is
plain code: it takes no token that `onCancel` cancels, starts no child and
passes no checkpoint of the context.

### Holding the cancellation back

A step that uses the job itself is another matter. Suppose the flag is written
by a job of its own, `database.readyFlag()`, which the step runs as a child:

```dart
await ctx.join(() async {
  await database.writeVersion();
  await ctx.run(database.readyFlag());
});
```

```text
cancel
version written
outcome: Cancelled(manual)
```

The flag is lost again. `join` waits for its action, but the job accepts the
cancellation at once, and from then on `ctx.run` throws it instead of starting
the child; a child already running would be cancelled. `uncancellable` holds
the cancellation back until the step is over:

```dart
await ctx.uncancellable(() async {
  await database.writeVersion();
  await ctx.run(database.readyFlag());
});
```

```text
cancel
version written
ready flag written
outcome: Cancelled(manual)
```

While the section runs, the job does not accept the cancellation: `ctx.run`
starts the child, the job's children are not cancelled, and `onCancel` does not
fire. Held, not refused: the job accepts it the moment the section closes, and
the next checkpoint throws it. The job still ends `Cancelled`, even if the body
returns a value, so whatever has to happen after the step anyway belongs inside
the same section.

Always await `ctx.uncancellable`. The section opens when called, even if you do
not await its future. An unawaited section can outlive the body; if the job
finishes first, the held cancellation is lost and `cancel()` returns with a
`Done` outcome.

To protect the entire body instead of one section, create
`Job(body, cancellable: false)`. It refuses ordinary cancellation once the body
starts, but can still be cancelled before start. `solo`, built on this core,
also cancels a job when the controller's state no longer suits it: a job there
declares which states it runs in. Neither a section nor `cancellable: false`
holds that cancellation back.

## Catching errors of the operation

A failed migration is not fatal here: the body logs it and goes on to mark the
database ready. A cancelled job should still stop, and the log should hold
failures, not cancellations. The token is wired through `onCancel` as above,
and the user cancels 15 ms in.

### The first attempt

A cancellation throws `Cancelled`, so a clause for it comes first and rethrows:

```dart
try {
  await ctx.join(() => database.migrate(stop));
} on Cancelled {
  rethrow;
} on Exception catch (error) {
  ctx.log('migration failed: $error');
}
await ctx.join(() async {
  await database.writeVersion();
  await database.writeReadyFlag();
});
```

```text
step 1
cancel
step 2
migration stopped
log: migration failed: DatabaseStopped
outcome: Cancelled(manual)
```

The log calls a cancellation a failed migration. The token stopped the
migration, and what came out of `join` is the migration's own
`DatabaseStopped`, not a `Cancelled`: `join` throws an error of its action as
it is. The clause for `Cancelled` lets it by, `on Exception` takes it, and the
code inside that clause runs on a job that is already cancelled. The job still
ends `Cancelled`: the `join` of the next step throws before its action starts.
Without the token the clause for `Cancelled` holds: the migration runs to its
end, and `join` throws the `Cancelled`. Without that clause, `on Exception`
takes that `Cancelled` too, because `Cancelled` implements `Exception`, and
logs `migration failed: Cancelled(manual)`.

### Asking the job

Whether the job is cancelled is a question for the job, not for the error:

```dart
try {
  await ctx.join(() => database.migrate(stop));
} on Exception catch (error) {
  ctx.check();
  ctx.log('migration failed: $error');
}
```

```text
step 1
cancel
step 2
migration stopped
outcome: Cancelled(manual)
```

`ctx.check()` throws the job's cancellation if it has accepted one, whatever
the `catch` took. A migration that failed on its own is logged, and the body
goes on. There is no `onError: DatabaseStopped` line, unlike in the token
section: `on Exception` catches the `DatabaseStopped`, so it never leaves the
body. The body ends with the job's cancellation from `ctx.check()`, and a
cancellation does not go to `onError`. If the clause is to catch everything,
errors included, as `on Object catch (error)` does, it needs the same
`ctx.check()` as its first line.

If the job has already accepted cancellation, catching its `Cancelled` does not
undo it. Code after the catch runs, but the next checkpoint throws again, and
the outcome is still `Cancelled` even if the body returns a value.

A `Cancelled` caught in the body is not always the job's own. A child started
with `ctx.run` and cancelled directly, not through its parent, throws its
`Cancelled` out of `run`. If that child was optional, `ctx.check()` passes, and
the body goes on without it and ends `Done`. A clause that rethrows every
`Cancelled` ends the parent too, with `Cancelled(handler)`; see
[Outcomes](outcomes.md).

## Work the job does not wait for

When the migration is over, the job sends an analytics event and does not wait
for it. The job's observer is where the app hears about the job's errors, and
the sending fails: analytics is offline.

### The first attempt

Dart's `unawaited` marks a future left on purpose:

```dart
unawaited(analytics.send('migrated'));
```

```text
outcome: Done(null)
zone: Bad state: analytics offline
```

The observer hears nothing. A future nobody awaits hands its error to the zone
as an uncaught one; `unawaited` only tells the analyzer that not waiting is on
purpose.

### Work handed to the job

```dart
ctx.unattended(() => analytics.send('migrated'));
```

```text
outcome: Done(null)
onError: Bad state: analytics offline
```

`ctx.unattended(action)` keeps the work's errors with the job, including errors
after the job finishes: they go to its observer or, without one, the zone the
job was created in. The job does not wait for the work and does not cancel it.

An asynchronous stop passed to `onCancel` is the same kind of work. `onCancel`
takes a `void Function()`, and Dart lets an `async` function through: the
future it returns is awaited by nobody, and its error goes to the zone past the
observer. Only what the callback throws synchronously reaches `onError`. For a
device that takes a while to stop, hand the stop to the job:

```dart
ctx.onCancel(() => ctx.unattended(device.stop));
```

Start the work inside the callback and take nothing out of it: the work runs in
an error zone of its own, and the boundary holds both ways. A future made
outside and awaited in there never comes back if it fails, and its error goes
to the zone it was made in. A future made in there and awaited outside hangs
whoever awaits it if it fails; awaited by the body, it hangs the job.
