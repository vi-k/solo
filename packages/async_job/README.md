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

The analyzer plugin [solo_lints](https://pub.dev/packages/solo_lints) reports
mistakes that compile, run and often pass a first test, such as a wait in
cleanup that never happens or a resource lost to a cancellation. Name it in
`analysis_options.yaml`:

```yaml
plugins:
  solo_lints: ^0.1.1
```

That turns on its warnings; the lints are turned on by name, as its
[Install](https://github.com/vi-k/solo/blob/main/packages/solo_lints/README.md#install)
section shows.

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
failure in the sense of [Four words](#four-words). The body starts on the next
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
  [`dispose` for what the job keeps](doc/cleanup.md#dispose-for-what-the-job-keeps).
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
| `ctx.check()` | A bare checkpoint | Throws `Cancelled` |  |
| `ctx.join(action)` | Waits for all of the action | Throws `Cancelled` | Waits, then throws |
| `ctx.abandonable(action)` | Waits while the job lives | Throws `Cancelled` | Throws at once |
| `ctx.uncancellable(action)` | Holds the cancellation back | Throws `Cancelled` | Holds it until the step ends |
| `ctx.pause(duration)` | Lets time pass | Throws `Cancelled` | Ends and throws |
| `ctx.child(body)` | Makes a child to run | Works as usual |  |
| `ctx.run(child)` | Runs a child and waits | Throws `Cancelled` | Passes it on, waits, throws |
| `ctx.start(child)` | Starts a child, no waiting | Throws `Cancelled` | Passes it on |
| `ctx.runAll(children)` | Runs children side by side | Throws `Cancelled` | Passes it on, waits, throws |
| `ctx.each(stream, onData)` | Follows a stream in a child | Throws `Cancelled` | Passes it on |
| `ctx.onCancel(callback)` | Calls back on a cancellation | Throws `Cancelled` |  |
| `ctx.onDispose(disposer)` | Cleans up at the end | Works as usual |  |
| `ctx.onDiscard(disposer)` | Cleans up unless `Done` | Works as usual |  |
| `ctx.disown(value)` | Drops a value's cleanup | Works as usual |  |
| `ctx.unattended(action)` | Starts work nobody waits for | Works as usual | Not cancelled |
| `ctx.log(message)` | Hands a message to the observer | Works as usual |  |
| `ctx.job` | The job of this context | Works as usual |  |
| `ctx.heldCancellation` | The held cancellation, or `null` | Works as usual |  |

What the cells leave out:

- `ctx.check()` is the checkpoint for a place where there is no call to wrap.
- `ctx.abandonable` stops waiting when the job is cancelled, and the action
  runs on. `ctx.uncancellable` holds the cancellation until the step ends, and
  the next checkpoint throws it.
- `ctx.child` makes an unstarted child that the engine of the job accepts, for
  code that holds the context and does not know the engine: a `Job.deferred` is
  a child of the core, and an engine that owns its children turns it away. It
  starts and checks nothing; the members that start a child do the refusing.
- `ctx.run`, `ctx.start` and `ctx.runAll` take a `ChildJob`, such as one made
  with `Job.deferred` or `ctx.child`, and pass the cancellation to their
  children. `ctx.start` leaves the outcome of its child to whoever holds the
  child. `ctx.runAll` stops the rest as soon as one child ends without a value.
- `ctx.each` hands the events of the stream to its callback one at a time.

- `ctx.onCancel` calls back the moment the job accepts a cancellation.
  `ctx.onDispose` cleans up whatever the outcome. `ctx.onDiscard` cleans up
  unless the job ends `Done`, and a body that ends `Done` without returning the
  value disposes of it itself.
- The errors of the work of `ctx.unattended` go to `onError`, then are answered
  for.
- A closure handed to `ctx.log` is called by the observer that builds the line.
- `ctx.heldCancellation` is the cancellation an open `uncancellable` section
  holds back.

The last column holds where the job accepts the cancellation as it comes.
Inside `ctx.uncancellable`, and in a job created with `cancellable: false`, the
job does not accept it while the member runs, and the member goes on as if none
had come.

## Four words

Four words carry the model of errors and cancellation, and each means less than
it does in everyday English:

| Word | What it means | Page |
| --- | --- | --- |
| Observe a failure | Read `done` or `value`, forward the failure through `then`, or call `ignoreFailure()`, by the microtask after the job ends; reading `outcome` or giving the job an observer does not count. | [Outcomes](doc/outcomes.md#a-failure-nobody-waits-for) |
| Answer for an error | What happens to a failure nobody observes and to an error no outcome carries: `onUnanswered` of an observer that mixes in `JobAnswerer` takes it, or the zone if the job has no such observer. | [Errors](doc/errors.md#answering-for-errors) |
| The zone | The zone the job was created in; an error that reaches it is an uncaught error there. | [Errors](doc/errors.md) |
| Accept a cancellation | The job becomes cancelled: the cancellation passes to its children, its `onCancel` callbacks run, and it ends `Cancelled` whatever the body does next. | [Cancellation](doc/cancellation.md) |

## Guides

Also on the [documentation site](https://docs.yet-another.dev/async_job/), with
search.

| Page | What it covers |
| --- | --- |
| [Outcomes](doc/outcomes.md) | `Done`, `Failed`, `Cancelled`, and observing a failure |
| [Cancellation](doc/cancellation.md) | Checkpoints, `onCancel`, `uncancellable` |
| [Time](doc/time.md) | `ctx.pause`, a deadline with `timeout` |
| [Children](doc/children.md) | `Job.deferred`, `ctx.child`, `ctx.run`, `ctx.start` for a child the body does not await, how deep a tree goes |
| [Groups](doc/groups.md) | `.wait`, `ctx.runAll`, what a group hands back |
| [Chains](doc/chains.md) | `then`, a continuation of a child, steps in a row |
| [Streams](doc/streams.md) | `ctx.each`, `Job.each`, and what `await for` and `listen` do in a body |
| [Cleanup](doc/cleanup.md) | `dispose`, `discard`, `ctx.disown` for a value the job keeps back |
| [Cleanup rules](doc/cleanup-rules.md) | A resource handed to another job, `onDispose` and unregistering, ordering and late results |
| [Observing](doc/observing.md) | `JobObserver`, a job's name, logs |
| [Errors](doc/errors.md) | Where an error goes, `JobAnswerer`, `Job.isCancellationError`, `unattended`, `JobObserver.all` |
| [Error rules](doc/error-rules.md) | The way of each kind of error, `Job.debug`, `Job.visitErrors`, rare cases |
| [Testing](doc/testing.md) | A job under `fakeAsync`, and what moves its time |
| [Building on the core](doc/extending.md) | `JobBase`, `JobContextBase`, a job of your own, `Job.deferred`, `finish` |
| [An engine of your own](doc/engine.md) | A queue that refuses in `cancelWith`, a rule in `check()` |

## Versions

| A change | Comes in |
| --- | --- |
| A fix that keeps the public API | a patch release, such as `1.0.1` |
| A new class, member or optional parameter | a minor release, such as `1.1.0` |
| A removed or renamed member, a changed signature or documented behaviour | a major release, such as `2.0.0` |

From 1.0.0 on, `async_job` follows semantic versioning: the constraint `^1.0.0`
takes every minor and patch release, and they keep code written against 1.0.0
working, but for the cases below. The public API is what
`package:async_job/async_job.dart` and `package:async_job/engine.dart` export;
the text of error messages and of debug output is not part of it. A member that
goes away is first marked `@Deprecated` in a minor release, with the name to
use instead, and is removed in the next major one.

A minor release can add a member to a class you extend, such as `JobObserver`
or `JobBase`, and a member of the same name in your own code then stops
compiling. It can add a member to an interface you implement for a mock, such
as `Job` or `JobContext`, and a fake that implements it by hand, rather than
through `noSuchMethod`, then stops compiling too. The changelog of such a
release names the members it adds. A new top-level name can clash with the same
name imported from another package, until one of the imports hides it with
`hide`.

## solo

[solo](https://pub.dev/packages/solo) adds state, a queue and declarative
rules. It runs one root job at a time and gives that job exclusive access to
state. Use it when you need a controller with these guarantees. It re-exports
`async_job`, so you only need a dependency on `solo`.

Jobs work wherever Dart runs. For `solo` widget integration, use
[flutter_solo](https://pub.dev/packages/flutter_solo).
