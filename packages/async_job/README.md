# async_job

A `Future` in Dart cannot be cancelled. `async_job` adds cancellation, child
tasks and resource cleanup to asynchronous Dart code: a cancelled job stops at
its next checkpoint, runs its cleanup and ends after its children, in the
manner of structured concurrency. The package works in pure Dart and depends
only on `meta`.

A `Job<T>` runs a function called its body and records how it ended. Use
`await job.done` to get its outcome or `await job.value` to get the value
returned by the body. `Job` itself does not implement `Future`: a job started
without `await` is ordinary use rather than a forgotten wait, and the lints for
unawaited futures leave it alone. For the same reason `await job` compiles and
waits for nothing; the core set of `package:lints` flags it with
`await_only_futures`.

[Why a job](doc/why.md) shows what a job adds to a `Future`, a flag and
`CancelableOperation`, on a fuller example. [Reference](doc/reference.md) lists
every member of the context and what it does once the job is cancelled.

## Install

```sh
dart pub add async_job
```

The analyzer plugin [async_job_lints](https://pub.dev/packages/async_job_lints)
reports mistakes that compile, run and often pass a first test, such as a wait
in cleanup that never happens or a resource lost to a cancellation. Name it in
`analysis_options.yaml`, which turns on its warnings, and turn its lints on by
name, as its
[Install](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.md#install)
section shows:

```yaml
plugins:
  async_job_lints: ^0.1.0
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
  final outcome = job.done;

  // Somebody left the screen while the read was in flight.
  await Future<void>.delayed(const Duration(milliseconds: 50));

  // Waits for the body, its children and its cleanup.
  await job.cancel();
  print(switch (await outcome) {
    Done() => 'read',
    Failed(:final error) => 'failed: $error',
    Cancelled(:final reason) => 'cancelled: $reason',
  });
}
```

`example/quick_start.dart` runs this block with a `Database` that prints when
it opens and when it closes. It prints:

```text
database opened
database closed
cancelled: manual
```

`ctx.join` waited for the read it had already started, and the rows never
reached the body; `cancel()` returned once the job was over, cleanup included.
`done` is taken next to the constructor, so a failure that comes before the
cancellation lands in the `switch` instead of ending the program. An error the
read throws after the cancellation is not the outcome: the job ends
`Cancelled`, and the error is left uncaught, as
[Where errors go](doc/errors.md#where-errors-go) shows. The body starts on the
next microtask, which is why the block waits before it cancels.

## Guides

Also on the [documentation site](https://docs.yet-another.dev/async_job/), with
search.

| Page | What it covers |
| --- | --- |
| [Why a job](doc/why.md) | What a job adds to a `Future`, a flag and `CancelableOperation`, and a fuller example |
| [Outcomes](doc/outcomes.md) | `Done`, `Failed`, `Cancelled`, and observing a failure |
| [Cancellation](doc/cancellation.md) | Checkpoints, `onCancel`, `uncancellable` |
| [With riverpod and bloc](doc/riverpod-and-bloc.md) | A job under a provider, a notifier or a bloc handler, and an HTTP request it aborts |
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
| [Reference](doc/reference.md) | Every member of the context and what it does once the job is cancelled; the four words of the model |

## Versions

| A change | Comes in |
| --- | --- |
| A fix that keeps the public API | a patch release, such as `1.0.1` |
| A new class, member or optional parameter | a minor release, such as `1.1.0` |
| A removed or renamed member, a changed signature or documented behaviour | a major release, such as `2.0.0` |
| A new value of an enum or a new subclass of a sealed class | a major release, such as `2.0.0` |

From 1.0.0 on, `async_job` follows semantic versioning: the constraint `^1.0.0`
takes every minor and patch release, and they keep code written against 1.0.0
working, but for the cases below. The public API is what
`package:async_job/async_job.dart` exports; the text of error messages and of
debug output is not part of it. A member that goes away is first marked
`@Deprecated` in a minor release, with the name to use instead, and is removed
in the next major one.

A minor release can add a member to a class you extend, such as `JobObserver`,
and a member of the same name in your own code then stops compiling. It can add
a member to an interface you implement for a mock, such as `Job` or
`JobContext`, and a fake that implements it by hand, rather than through
`noSuchMethod`, then stops compiling too. The changelog of such a release names
the members it adds. A new top-level name can clash with the same name imported
from another package, until one of the imports hides it with `hide`.

A `switch` over an `Outcome` or a `JobErrorAnswer` can be exhaustive, and a new
subclass of the sealed `Outcome` or a new value of the enum would make it stop
compiling: these come only in a major release. `CancelReason` is open, and a
minor release can add a reason, so a `switch` over reasons keeps a default
case.

What `package:async_job/engine.dart` adds, the protocol for building an engine,
is outside the promise: `JobBase`, `JobContextBase`, `JobStatus` and their
protected members can change in a minor release, and the Engine protocol
section of the changelog of that release says how. An engine holds `async_job`
to one minor version, such as `>=1.0.0 <1.1.0`, and comes out with each minor
release of it; [Building on the core](doc/extending.md) says the same.

## solo

[solo](https://pub.dev/packages/solo) adds state, a queue and declarative
rules. It runs one root job at a time and gives that job exclusive access to
state. Use it when you need a controller with these guarantees. It re-exports
`async_job`, so you only need a dependency on `solo`. Code built on `solo`
names [solo_lints](https://pub.dev/packages/solo_lints) in place of
`async_job_lints`: it includes the rules of `async_job_lints` and adds those of
the controller.

Jobs work wherever Dart runs. For `solo` widget integration, use
[flutter_solo](https://pub.dev/packages/flutter_solo).
