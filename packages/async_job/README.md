# async_job

`async_job` adds cancellation, child tasks and resource cleanup to asynchronous
Dart code. The package works in pure Dart and depends only on `meta`.

A `Job<T>` runs a function called its body and records how it ended. Use
`await job.done` to get its outcome or `await job.value` to get the value
returned by the body. `Job` itself does not implement `Future`.

## Why

A plain `Future` has no cancellation. A flag can ask work to stop, but nothing
answers for what the work has already opened:

```dart
var cancelled = false;

Future<void> load() async {
  final db = await Database.open();
  if (cancelled) {
    return; // the database stays open
  }
  final rows = await db.readAll();
  if (cancelled) {
    return; // and so does it here
  }
  use(rows);
}
```

A job answers for it:

```dart
final job = Job<void>((ctx) async {
  // Checked before the call and again before the value comes back,
  // and the database is closed whichever way the job ends.
  final db = await ctx.join(Database.open, dispose: (db) => db.close());
  use(await ctx.join(db.readAll));
});

// Waits for the body, its children and its cleanup.
await job.cancel();
print(job.outcome); // Cancelled(manual)
```

`Job` manages this lifetime. It finishes with one of three outcomes: `Done`,
`Failed` or `Cancelled` with a reason. It waits for its children and runs
registered cleanup before completing. An unobserved `Failed` is reported to the
zone that created the job, just as Dart reports an unhandled `Future` error.
For errors from work the body no longer awaits, `Job` also provides an
observer.

Cancellation is cooperative: `cancel()` requests it, and the body stops when it
reaches a cancellation checkpoint. `Job` provides these checkpoints through the
context, `ctx`, passed to the body. `ctx.join(action)` checks cancellation
before starting the operation, waits for it to finish, then checks again before
returning its value to the body.

A direct `await action()` is allowed, but does not check job cancellation. It
keeps waiting, and the code after it can run even if the job has been
cancelled. That is why using the context is part of writing a cancellable body.
`CancelableOperation` cancels the waiting; a job owns what the work left
behind.

`async_job` does not provide state management, a task queue or scheduling
rules. If you need them, use `solo`, which adds these features on top of
`async_job` and re-exports its API.

Neither package provides retries, timeouts or a task pool; applications can add
these as needed.

## Install

```sh
dart pub add async_job
```

## Quick start

Suppose a job needs to open a database, migrate it and return the open database
to its caller. If the job fails or is cancelled, it must close the database
instead. The context lets the body describe both paths:

```dart
import 'package:async_job/async_job.dart';

final job = Job<Database>((ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );

  final stop = CancelToken();
  ctx.onCancel(stop.cancel);

  await ctx.join(() => database.migrate(stop));
  await ctx.uncancellable(() => database.markReady(stop));

  return database;
});

// Somebody changed their mind while the database was opening.
await Future<void>.delayed(const Duration(milliseconds: 10));
await job.cancel();

final outcome = await job.done; // Cancelled(manual)
```

- **The body starts on the next microtask.** The caller receives the job first
  and can register listeners before it runs. Cancelling immediately after
  construction skips the body and produces `Cancelled(manual)` with
  `started: false`. The delay in the example lets the body start first.
- **`ctx.join(Database.open)`** calls `Database.open` and returns the opened
  database. If cancellation arrives during opening, it waits for the call to
  finish and throws `Cancelled` if opening succeeded. If opening fails, it
  throws the original error, even after cancellation.
- **`discard: (database) => database.close()`** closes the database if the job
  ends with cancellation or an error. With `Done(database)`, it stays open for
  the caller. Cleanup also covers cancellation after `return database`: for
  example, if the body has started a child that is still running, the job waits
  for that child before completing. Cancelling during this wait produces
  `Cancelled` and closes the database. See [Cleanup](doc/cleanup.md).
- **`ctx.onCancel(stop.cancel)`** connects job cancellation to the database's
  cancellation token. The callback runs as soon as the job accepts
  cancellation, before the body reaches its next checkpoint.
- **`ctx.join(() => database.migrate(stop))`** waits for the migration to
  finish. On cancellation, the token asks the migration to stop, and `join`
  waits for it to stop before the job closes the database. If you need to stop
  waiting immediately on cancellation, use `ctx.wait`. It stops the waiting
  without stopping the operation itself.
- **`ctx.uncancellable(() => database.markReady(stop))`** protects this final
  step from a request to stop. During migration, `join` waits while the token
  tells the database to stop. Here the step must finish without receiving that
  signal, so `uncancellable` holds the cancellation request: `onCancel` does
  not fire and the token remains active during the call. After the section, the
  request takes effect and the next context checkpoint throws `Cancelled`. See
  [Cancellation](doc/cancellation.md).
- **`await job.cancel()`** requests cancellation and waits for the job to
  finish, including its cleanup. The outcome on the next line is therefore
  ready. You can omit `await` if you only need to request cancellation.

The complete runnable example, including a fake `Database`, is in
`example/example.dart`.

## Guides

Also on the [documentation site](https://docs.yet-another.dev/async_job/), with
search.

| Page | What it covers |
| --- | --- |
| [Outcomes](doc/outcomes.md) | `Done`, `Failed`, `Cancelled`, and who is answerable for an error |
| [Cancellation](doc/cancellation.md) | Checkpoints, `onCancel`, `uncancellable`, reasons |
| [Children, streams and chains](doc/children.md) | `ctx.run`, `ctx.each`, `then` |
| [Cleanup](doc/cleanup.md) | `dispose`, `discard`, `onDispose`, ordering |
| [Observing and testing](doc/observing.md) | `JobObserver`, logs, fake time |
| [Building on the core](doc/extending.md) | `JobBase`, deferred start, your own engine |

## solo

[solo](https://pub.dev/packages/solo) adds state, a queue and declarative
rules. It runs one root job at a time and gives that job exclusive access to
state. Use it when you need a controller with these guarantees. It re-exports
`async_job`, so you only need a dependency on `solo`.

Jobs work wherever Dart runs. For `solo` widget integration, use
[flutter_solo](https://pub.dev/packages/flutter_solo).
