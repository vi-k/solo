# async_job

`async_job` adds cancellation, child tasks and resource cleanup to asynchronous
Dart code. The package works in pure Dart and depends only on `meta`.

A `Job<T>` runs a function called its body and records how it ended. Use
`await job.done` to get its outcome or `await job.value` to get the value
returned by the body. `Job` itself does not implement `Future`: a job started
without `await` is ordinary use rather than a forgotten wait, and the lints for
unawaited futures leave it alone.

## Install

```sh
dart pub add async_job
```

## Quick start

A job opens a database and reads from it, and somebody cancels it while the
read is in flight. The body receives a context, `ctx`, and each call it awaits
through `ctx.join` is a checkpoint: once the job is cancelled, the next one
throws `Cancelled`. `dispose` closes the database whichever way the job ends:

```dart
import 'package:async_job/async_job.dart';

Future<void> main() async {
  final job = Job<void>((ctx) async {
    // Checked before the call and again before the value comes back,
    // and the database is closed whichever way the job ends.
    final db = await ctx.join(Database.open, dispose: (db) => db.close());
    use(await ctx.join(db.readAll));
  });

  // Somebody left the screen while the read was in flight.
  await Future<void>.delayed(const Duration(milliseconds: 50));

  // Waits for the body, its children and its cleanup.
  await job.cancel();
  print(job.outcome); // Cancelled(manual)
}
```

`example/quick_start.dart` runs this block with a `Database` that prints when
it opens and when it closes. It prints:

```text
database opened
database closed
Cancelled(manual)
```

`ctx.join` waited for the read it had already started, and the rows never
reached the body. `await job.cancel()` returns once the job is over, cleanup
included, so `outcome` is ready on the next line; neither of them observes a
failure, as [Outcomes](doc/outcomes.md) explains. The body starts on the next
microtask: a job cancelled right after its constructor never runs it and ends
`Cancelled(manual)` with `started: false`, which is why the block waits first.

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
rules: [solo](#solo) adds them. Neither package provides retries or a task
pool. A deadline is built in: `Job(body, timeout: limit)` cancels the job once
the limit has run out, and it ends `Cancelled(timeout)`; see
[A deadline](doc/time.md#a-deadline) on the time page.

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

// Somebody changed their mind while the database was opening.
await Future<void>.delayed(const Duration(milliseconds: 10));
await job.cancel();

final outcome = await job.done; // Cancelled(manual)
```

- **`ctx.join(Database.open)`** waits for the open even after a cancellation,
  then throws `Cancelled`, or the open's own error if it failed. An error that
  comes after the cancellation has no outcome to carry it; see
  [Where errors go](doc/errors.md#where-errors-go).
- **`discard: (database) => database.close()`** closes the database when the
  job ends `Failed` or `Cancelled`; with `Done(database)` it stays open for the
  caller. See
  [Cleanup order and late results](doc/cleanup.md#cleanup-order-and-late-results).
- **`ctx.onCancel(stop.cancel)`** hands the cancellation to the client's own
  token the moment the job accepts it. `CancelToken` belongs to the database
  client, not to this package.
- **`ctx.join(() => database.migrate(stop))`** waits for the migration, and on
  a cancellation for it to stop. A client that stops by throwing sends that
  error to the job's observer and then to the answer, the zone by default, on
  every cancellation, unless the app names it once in
  `Job.isCancellationError`; see
  [Errors of a cancellation](doc/errors.md#errors-of-a-cancellation).
- **`ctx.uncancellable(() async { ... })`** keeps the version and its ready
  flag together: the child starts and a cancellation waits for the step, yet
  the job still ends `Cancelled` and `discard` closes the database. See
  [Holding the cancellation back](doc/cancellation.md#holding-the-cancellation-back).
- **`ctx.run(database.readyFlag())`** starts, as a child, the job that writes
  the ready flag; `readyFlag()` makes it with `Job.deferred`, which leaves its
  start to `ctx.run`. See [Children](doc/children.md).

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

## The context at a glance

What each member of `ctx` does, how it behaves once the job is cancelled, and
what a cancellation that comes while it runs does to it:

| Member | What it does | Once the job is cancelled | Cancelled while it runs |
| --- | --- | --- | --- |
| `ctx.check()` | A checkpoint where there is no call to wrap | Throws `Cancelled` |  |
| `ctx.join(action)` | Runs the action and waits for all of it | Throws `Cancelled` | Waits for the action to end, then throws |
| `ctx.abandonable(action)` | Runs the action and waits for it, but no longer than the job lives | Throws `Cancelled` | Throws at once; the action runs on |
| `ctx.uncancellable(action)` | Runs a step with the cancellation held back | Throws `Cancelled` | Holds the cancellation until the step ends; the next checkpoint throws |
| `ctx.pause(duration)` | Lets time pass | Throws `Cancelled` | Ends the pause and throws |
| `ctx.run(child)` | Starts a `ChildJob`, such as one made with `Job.deferred`, and waits for its value | Throws `Cancelled` | Passes the cancellation to the child, waits for it and throws |
| `ctx.start(child)` | Starts a `ChildJob` the body does not wait for, and leaves its outcome to whoever holds it | Throws `Cancelled` | Passes the cancellation to the child |
| `ctx.runAll(children)` | Runs children side by side and stops the rest as soon as one ends without a value | Throws `Cancelled` | Passes the cancellation to the children, waits for them and throws |
| `ctx.each(stream, onData)` | Starts a child that takes the events of a stream one at a time | Throws `Cancelled` | Passes the cancellation to the child |
| `ctx.onCancel(callback)` | Calls back the moment the job accepts a cancellation | Throws `Cancelled` |  |
| `ctx.onDispose(disposer)` | Cleans up when the job ends, whatever the outcome | Works as usual |  |
| `ctx.onDiscard(disposer)` | Cleans up unless the job ends `Done`; a body that ends `Done` without returning the value disposes of it itself | Works as usual |  |
| `ctx.disown(value)` | Drops the cleanup registered for a value | Works as usual |  |
| `ctx.unattended(action)` | Starts work the job does not wait for; its errors go where those of cleanup go | Works as usual | The work is not cancelled |
| `ctx.log(message)` | Hands a message to the observer; a closure is called by the observer that builds the line | Works as usual |  |
| `ctx.job` | The job of this context | Works as usual |  |

The last column holds where the job accepts the cancellation as it comes.
Inside `ctx.uncancellable`, and in a job created with `cancellable: false`, the
job does not accept it while the member runs, and the member goes on as if none
had come.

## Guides

Also on the [documentation site](https://docs.yet-another.dev/async_job/), with
search.

| Page | What it covers |
| --- | --- |
| [Outcomes](doc/outcomes.md) | `Done`, `Failed`, `Cancelled`, and observing a failure |
| [Cancellation](doc/cancellation.md) | Checkpoints, `onCancel`, `uncancellable` |
| [Time](doc/time.md) | `ctx.pause`, a deadline with `timeout` |
| [Children](doc/children.md) | `Job.deferred`, `ctx.run`, `ctx.start` for a child the body does not await, how deep a tree goes |
| [Groups](doc/groups.md) | `.wait`, `ctx.runAll`, what a group hands back |
| [Chains](doc/chains.md) | `then`, a continuation of a child, steps in a row |
| [Streams](doc/streams.md) | `ctx.each`, `Job.each`, and what `await for` and `listen` do in a body |
| [Cleanup](doc/cleanup.md) | `dispose`, `discard`, `onDispose`, ordering |
| [Observing](doc/observing.md) | `JobObserver`, a job's name, logs |
| [Errors](doc/errors.md) | Where an error goes, `JobAnswerer`, `Job.isCancellationError`, `Job.visitErrors`, `unattended`, `Job.debug` |
| [Testing](doc/testing.md) | A job under `fakeAsync`, and what moves its time |
| [Building on the core](doc/extending.md) | `JobBase`, `JobContextBase`, your own engine |

## solo

[solo](https://pub.dev/packages/solo) adds state, a queue and declarative
rules. It runs one root job at a time and gives that job exclusive access to
state. Use it when you need a controller with these guarantees. It re-exports
`async_job`, so you only need a dependency on `solo`.

Jobs work wherever Dart runs. For `solo` widget integration, use
[flutter_solo](https://pub.dev/packages/flutter_solo).
