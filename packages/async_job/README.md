# async_job

`async_job` adds cancellation, child tasks and resource cleanup to asynchronous
Dart code. The package works in pure Dart and depends only on `meta`.

A `Job<T>` runs a function called its body and records how it ended. Use
`await job.done` to get its outcome or `await job.value` to get the value
returned by the body. `Job` itself does not implement `Future`: a job started
without `await` is ordinary use rather than a forgotten wait, and the lints for
unawaited futures leave it alone.

## Why

A plain `Future` has no cancellation. A flag can ask work to stop, but the work
has to ask the flag after every `await` and close what it has opened each time:

```dart
var cancelled = false;

Future<void> load() async {
  final db = await Database.open();
  if (cancelled) {
    await db.close();
    return;
  }
  final rows = await db.readAll();
  if (cancelled) {
    await db.close();
    return;
  }
  use(rows);
  await db.close();
}
```

Every new `await` needs a check of its own, and every new resource adds its
cleanup to each check. Once the cleanup grows, checks start to be left out, and
a check left out lets the work go on after the cancellation, with nothing
pointing at the place.

A job checks for cancellation at each `ctx.join`, and the closing of the
database is registered once:

```dart
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
```

A `Job` finishes with one of three outcomes: `Done`, `Failed` or `Cancelled`
with a reason. It waits for its children and runs registered cleanup before
completing. An unobserved `Failed` is reported to the zone that created the
job, just as Dart reports an unhandled `Future` error. A failure is observed by
accessing the job's `done` or `value`, or by calling `ignore()`; awaiting
`cancel()` and reading `outcome`, as the block above does, do not observe it,
and neither does the job's observer (`JobObserver`).

An error that does not become the outcome, such as one from cleanup, goes to
the zone as well, unless the job's observer answers for it (`JobAnswerer`). But
an error of the body that happens once the job is cancelled, like an open that
fails after the cancellation in the Quick start below, goes only to the job's
observer, and without one to nobody.
[Where errors go](doc/observing.md#where-errors-go) on the observing page lists
each one, with an observer and without.

Cancellation is cooperative: `cancel()` requests it, and the body stops when it
reaches a cancellation checkpoint. A running job accepts the request inside
`cancel()` itself, unless an `uncancellable` section holds it back or the job
was created with `cancellable: false`: from then on the job is cancelled, its
`onCancel` callbacks run, and every checkpoint throws `Cancelled`. `Job`
provides these checkpoints through the context, `ctx`, passed to the body.
`ctx.join(action)` checks cancellation before starting the operation, waits for
it to finish, then checks again before returning its value to the body.

A direct `await action()` is allowed, but does not check job cancellation. It
keeps waiting, and the code after it can run even if the job has been
cancelled. That is why using the context is part of writing a cancellable body.
Inside an action passed to the context, such as the step of `ctx.uncancellable`
in the Quick start below, and in cleanup, a direct `await` is right: the
context adds no checkpoint between the awaits of that action.

Dart can already stop the waiting. `Future.timeout` stops it after a time
limit, and `CancelableOperation` from `package:async` stops delivering its
value on `cancel()`, running its `onCancel`, which can ask the work to stop.
Neither holds on to what the work opens: a value that arrives once the waiting
has stopped goes to nobody, and a database that opens late stays open.
`CancelableOperation` can catch such a database, but only in an `onCancel`
written for it, one that holds on to the future of the open:

```dart
final open = Database.open();
final operation = CancelableOperation.fromFuture(
  open,
  // cancel() stops the waiting; this closes the database once it opens.
  onCancel: () async => (await open).close(),
);
```

Such an `onCancel` covers one wait. Once the database has been handed over,
`cancel()` does nothing: the read that follows runs on, and closing the
database is up to the code after every `await` again, as with the flag. A
cancelled operation never completes its `value` either, so whoever awaits it
waits for good.

`ctx.join` hands a database that opens after the job's cancellation to its
`dispose` all the same, with no code written for the cancellation, and the job
ends once the database is closed. The registration covers the rest of the job
as well: a cancellation at a later `ctx.join`, an error or the end of the body
closes the database the same way, and the job ends `Cancelled`, `Failed` or
`Done`. `ctx.abandonable` stops the waiting as `Future.timeout` and
`CancelableOperation` do and still hands that database to its `dispose` when it
opens, even after the job has ended.

`async_job` does not provide state management, a task queue or scheduling
rules: [solo](#solo) adds them.

Neither package provides retries or a task pool; applications can add these as
needed. A job has no timeout of its own either: `Timer(limit, job.cancel)`
cancels it once the limit has run out, and does nothing to a job that has
already finished. The timer itself lives until the limit: a program with
nothing else to do does not exit before it fires. Cancelling it when the job
ends, `job.done.whenComplete(timer.cancel)`, observes the outcome: a failure of
the job then no longer reaches the zone, and the code that cancels the timer
has to report it.

## Install

```sh
dart pub add async_job
```

## Quick start

Suppose a job needs to open a database, migrate it, mark it ready and return
the open database to its caller. If the job fails or is cancelled, it must
close the database instead. The context lets the body describe both paths:

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

- **The body starts on the next microtask.** The caller receives the job first
  and can register listeners before it runs. Cancelling immediately after
  construction skips the body and produces `Cancelled(manual)` with
  `started: false`. The delay in the example lets the body start first.
- **`ctx.join(Database.open)`** calls `Database.open` and returns the opened
  database. If cancellation arrives during opening, it waits for the call to
  finish and throws `Cancelled` if opening succeeded. If opening fails, it
  throws the original error, even after cancellation. The job still ends
  `Cancelled`, so the error is nobody's outcome: it reaches the job's observer
  and stops there, and without an observer nothing hears it. See
  [Where errors go](doc/observing.md#where-errors-go) on the observing page.
- **`discard: (database) => database.close()`** closes the database if the job
  ends with cancellation or an error. With `Done(database)`, it stays open for
  the caller. Cleanup also covers cancellation after `return database`: for
  example, if the body has started a child that is still running, the job waits
  for that child before completing. Cancelling during this wait produces
  `Cancelled` and closes the database. See
  [Cleanup order and late results](doc/cleanup.md#cleanup-order-and-late-results)
  on the cleanup page.
- **`ctx.onCancel(stop.cancel)`** connects job cancellation to the database's
  cancellation token. `CancelToken` belongs to the database client, not to this
  package. The callback runs as soon as the job accepts cancellation, before
  the body reaches its next checkpoint.
- **`ctx.join(() => database.migrate(stop))`** waits for the migration to
  finish. On cancellation, the token asks the migration to stop, and `join`
  waits for it to stop before the job closes the database. If you need to stop
  waiting immediately on cancellation, use `ctx.abandonable`. It stops the
  waiting without stopping the operation itself.
- **`ctx.uncancellable(() async { ... })`** keeps the last step whole. The step
  writes the schema version and then runs `database.readyFlag()` as a child,
  and the section keeps a cancellation from coming between the two. Inside the
  section the job does not accept the cancellation: the child starts, and
  `onCancel` does not fire. The job accepts it when the section closes, and the
  body goes on to `return database`, yet the job ends `Cancelled` all the same,
  and `discard` closes the database: the section keeps the step whole, not the
  result. A step of plain code, one that makes no context call and takes no
  token that `onCancel` cancels, needs no section: one `join` around it is
  enough. See
  [Holding the cancellation back](doc/cancellation.md#holding-the-cancellation-back)
  on the cancellation page.
- **`ctx.run(database.readyFlag())`** starts, as a child, the job that writes
  the ready flag; `readyFlag()` makes it with `Job.deferred`, which leaves its
  start to `ctx.run`. See [Children](doc/children.md#children) on the children
  page.
- **`await job.cancel()`** requests cancellation and waits for the job to
  finish, including its cleanup. The outcome on the next line is therefore
  ready. You can omit `await` if you only need to request cancellation.

The complete runnable example, with a fake `Database` and `CancelToken`, is in
`example/example.dart`. It runs the job four times: once to the end, and
cancelled while the database opens, while it migrates and while the version is
written.

## Guides

Also on the [documentation site](https://docs.yet-another.dev/async_job/), with
search.

| Page | What it covers |
| --- | --- |
| [Outcomes](doc/outcomes.md) | `Done`, `Failed`, `Cancelled`, and observing a failure |
| [Cancellation](doc/cancellation.md) | Checkpoints, `onCancel`, `uncancellable` |
| [Children, streams and chains](doc/children.md) | `Job.deferred`, `ctx.run`, `ctx.runAll`, `ctx.each`, `then` |
| [Streams](doc/streams.md) | `ctx.each`, `Job.each`, and what `await for` and `listen` do in a body |
| [Cleanup](doc/cleanup.md) | `dispose`, `discard`, `onDispose`, ordering |
| [Observing and testing](doc/observing.md) | `JobObserver`, `JobAnswerer`, `Job.visitErrors`, logs, `unattended`, fake time |
| [Building on the core](doc/extending.md) | `JobBase`, `JobContextBase`, your own engine |

## solo

[solo](https://pub.dev/packages/solo) adds state, a queue and declarative
rules. It runs one root job at a time and gives that job exclusive access to
state. Use it when you need a controller with these guarantees. It re-exports
`async_job`, so you only need a dependency on `solo`.

Jobs work wherever Dart runs. For `solo` widget integration, use
[flutter_solo](https://pub.dev/packages/flutter_solo).
