# Why a job

What a job adds to a plain `Future`, a flag and `CancelableOperation`, and a
fuller example where it does all of that at once.

## Why

A plain `Future` has no cancellation. A flag can ask work to stop, but the work
has to ask the flag after every `await`, and a `finally` closes what it has
opened:

```dart
var cancelled = false;

Future<void> load() async {
  final db = await Database.open();
  try {
    if (cancelled) return;
    final rows = await db.readAll();
    if (cancelled) return;
    use(rows);
  } finally {
    await db.close();
  }
}
```

Every new `await` needs a check of its own, and a check left out lets the work
go on after the cancellation, with nothing pointing at the place. And `load`
returns the same way whether it was cancelled or ran to its end, so its caller
cannot tell the two apart.

Dart can already stop the waiting. `Future.timeout` stops it after a time
limit, and `CancelableOperation` from `package:async` stops delivering its
value on `cancel()`. Neither holds on to what the work opens: a database that
opens once the waiting has stopped stays open. `CancelableOperation` catches it
only in an `onCancel` written for that one wait:

```dart
final open = Database.open();
final operation = CancelableOperation.fromFuture(
  open,
  // cancel() stops the waiting; this closes the database once it opens.
  onCancel: () async => (await open).close(),
);
```

Once the database has been handed over, `cancel()` does nothing: the read that
follows runs on, and the work is back to a flag and a `finally`. A cancelled
operation never completes its `value` either, so whoever awaits it waits for
good.

A job adds three things:

- **A checkpoint at every call it awaits through the context.** `ctx.join`
  checks before the call and before the value comes back, and the job ends
  `Cancelled`, which its caller can tell from `Done`.
- **Cleanup registered where the resource opens.** `dispose` closes the
  database however the job ends, and a database that opens after the
  cancellation is closed too, with no code written for the cancellation.
- **Children it waits for.** A job ends after its children and its cleanup, and
  a cancellation it accepts passes to its children.

`async_job` does not provide state management, a task queue or scheduling
rules:
[solo](https://github.com/vi-k/solo/blob/main/packages/async_job/README.md#solo)
adds them. Neither package provides retries or a task pool. A deadline is built
in: `Job(body, timeout: limit)` cancels the job once the limit has run out, and
it ends `Cancelled(timeout)`; see [A deadline](time.md#a-deadline) on the time
page.

## A fuller example

A job opens a database, migrates it, marks it ready and returns the open
database to its caller. If the job fails or is cancelled, it closes the
database instead:

```dart
final job = Job<Database>((ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );

  final stop = CancelToken();
  ctx.onCancel(stop.cancel);

  await ctx.join(() => database.migrate(stop));
  await ctx.uncancellable(() async {
    await database.writeVersion();
    await ctx.run(database.readyFlag());
  });

  return database;
});
final outcome = job.done;

// Somebody changed their mind while the database was opening.
await Future<void>.delayed(const Duration(milliseconds: 10));
await job.cancel();

print(await outcome); // Cancelled(manual)
```

- **`ctx.join(Database.open)`** waits for the open even after a cancellation,
  then throws `Cancelled`, or the open's own error if it failed. An error that
  comes after the cancellation has no outcome to carry it; see
  [Where errors go](errors.md#where-errors-go).
- **`discard: (database) => database.close()`** closes the database when the
  job ends `Failed` or `Cancelled`; with `Done(database)` it stays open for the
  caller. See
  [`dispose` for what the job keeps](cleanup.md#dispose-for-what-the-job-keeps).
- **`ctx.onCancel(stop.cancel)`** hands the cancellation to the client's own
  token the moment the job accepts it. `CancelToken` belongs to the database
  client, not to this package.
- **`ctx.join(() => database.migrate(stop))`** waits for the migration, and on
  a cancellation for it to stop. A client that stops by throwing sends that
  error to the job's observer and then to the answer, the zone by default, on
  every cancellation, unless the app names it once in
  `Job.isCancellationError`; see
  [Errors of a cancellation](errors.md#errors-of-a-cancellation).
- **`ctx.uncancellable(() async { ... })`** keeps the version and its ready
  flag together: the child starts and a cancellation waits for the step, yet
  the job still ends `Cancelled` and `discard` closes the database. See
  [Holding the cancellation back](cancellation.md#holding-the-cancellation-back).
- **`ctx.run(database.readyFlag())`** starts, as a child, the job that writes
  the ready flag; `readyFlag()` makes it with `Job.deferred`, which leaves its
  start to `ctx.run`. See [Children](children.md).
- **`final outcome = job.done;`** comes right after the job is made, before
  anything waits. Reading `done` tells the core the failure is handled, so a
  job that fails during the wait below brings its error back in `outcome`
  alone; read after the wait, `done` would carry an error that had already gone
  to the zone. See
  [Telling the core it is handled](outcomes.md#telling-the-core-it-is-handled).

The complete runnable example, with a fake `Database` and `CancelToken`, is in
`example/example.dart`. It runs the job four times: once to the end, and
cancelled while the database opens, while it migrates and while the version is
written. It prints:

```text
Nobody changes their mind:
database opened
migrated
version written
ready flag written
Done(database)
database closed

Somebody changes their mind while the database opens:
database opened
database closed
Cancelled(manual)

While it migrates, the token stops the migration:
database opened
migration stopped
database closed
Cancelled(manual)

While the version is written, the step ends whole:
database opened
migrated
version written
ready flag written
database closed
Cancelled(manual)
```

The pages go on from here: [Outcomes](outcomes.md) for what `done` hands back,
and [Cancellation](cancellation.md) for the checkpoints this example uses.
