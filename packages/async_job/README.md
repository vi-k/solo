# async_job

`async_job` adds cancellation, child tasks and resource cleanup to
asynchronous Dart code. It uses cooperative cancellation: the job's body
checks for cancellation through a context and stops at a suitable point.
The package works in pure Dart and depends only on `meta`.

A `Job<T>` runs an asynchronous function and records how it ended. Use
`await job.done` to get its outcome or `await job.value` to get its value.
`Job` itself does not implement `Future`.

## Why

Cancelling asynchronous work involves more than stopping an `await`. You
may also need to stop child tasks, close resources and report errors that
the caller has not handled.

A job manages these steps together. It finishes with one of three
outcomes: `Done`, `Failed` or `Cancelled` with a reason. It waits for its
children and runs registered cleanup before completing. An unobserved
`Failed` is reported to the zone that created the job, just as Dart reports
an unhandled `Future` error.

A plain `Future` has no cancellation operation. Flags and cancellation
tokens let you ask work to stop; `CancelableOperation` lets you cancel
waiting for a result. A job also provides cancellation checkpoints in the
body, child lifetimes, outcomes and an observer for errors.

The body receives a context, `ctx`. Use its methods to choose how an
operation responds to cancellation. For example, `ctx.join(action)` waits
for the operation to finish before reporting cancellation to the body.
A direct `await action()` keeps waiting even if the job is cancelled.

For state management, a queue and scheduling rules, use `solo`, which
builds on this package and re-exports its API. Neither package provides
retries, timeouts or a task pool; applications can add these as needed.

## Install

```sh
dart pub add async_job
```

## Quick start

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

This example opens a database, migrates it and returns it to the caller.
If the job is cancelled or fails, it closes the database.

- **The body starts on the next microtask.** The caller receives the job
  first and can register listeners before it runs. Cancelling immediately
  after construction skips the body and produces `Cancelled(manual)` with
  `started: false`. The delay in the example lets the body start first.
- **`ctx.join(Database.open)`** calls `Database.open` and returns the opened
  database. If cancellation arrives during opening, it waits for the call
  to finish before throwing `Cancelled` in the body.
- **`discard: (database) => database.close()`** closes the database if the
  job ends with cancellation or an error. With `Done(database)`, it stays
  open for the caller. Cleanup also covers cancellation after
  `return database`: for example, if the body has started a child that is
  still running, the job waits for that child before completing. Cancelling
  during this wait produces `Cancelled` and closes the database.
  See [Cleanup](#cleanup).
- **`ctx.onCancel(stop.cancel)`** connects job cancellation to the
  database's cancellation token. The callback runs as soon as the job
  accepts cancellation, before the body reaches its next checkpoint.
- **`ctx.join(() => database.migrate(stop))`** waits for the migration to
  finish. On cancellation, the token asks the migration to stop, and `join`
  waits for it to stop before the job closes the database. If you need to
  stop waiting immediately on cancellation, use `ctx.wait`. It stops the
  waiting without stopping the operation itself.
- **`ctx.uncancellable(() => database.markReady(stop))`** protects this
  step from cancellation. A cancellation request is held until the section
  ends, so `onCancel` does not fire and the token remains active during the
  call. After the section, the request takes effect and the next context
  checkpoint throws `Cancelled`. See [Cancellation](#cancellation).
- **`await job.cancel()`** requests cancellation and waits for the job to
  finish. You can omit `await` if you only need to request cancellation.

The complete runnable example, including a fake `Database`, is in
`example/example.dart`.

## Outcomes

`Outcome<T>` is sealed. A `switch` covering its three cases is exhaustive:

```dart
final message = switch (await job.done) {
  Done(:final value) => 'done $value',
  Failed(:final error) => 'failed $error',
  Cancelled(:final reason) => 'cancelled $reason',
};
```

`Cancelled` contains a `reason`, a `started` flag, an optional `description`
and the stack trace of the cancellation. The built-in reason classes are
`ManualCancelReason`, `ParentCancelReason` and `HandlerCancelReason`, all
extending `CancelReason`.

Check reasons by type, for example `reason is ParentCancelReason`. The
`name` property is a label for logs and does not determine equality.
Reasons use identity equality unless their class defines value equality.

You can define a reason that stores additional data, such as an error and
its original stack trace:

```dart
final class RequestCancelReason extends CancelReason {
  final Object error;
  final StackTrace stackTrace;

  const RequestCancelReason(this.error, this.stackTrace);

  @override
  String get name => 'request';
}
```

Pass the reason to `cancel()`. The cancellation listener and the outcome
receive the same instance:

```dart
try {
  await request();
} on Object catch (error, stackTrace) {
  await job.cancel(reason: RequestCancelReason(error, stackTrace));
}
```

The body can throw `Cancelled.by(reason: reason, started: true)` to use an
explicit reason, or `Cancelled('why')` to use `HandlerCancelReason`.
When a parent cancels a child, the child's `ParentCancelReason.cause`
holds the parent's `Cancelled`. When a child's cancellation escapes
through the parent body, the parent's `HandlerCancelReason.cause` holds
the child's `Cancelled`. These links preserve the original reason and its
data. An error's stack trace stored in a reason is separate from the
cancellation's stack trace.

Use these members to read or acknowledge the result:

- `job.done` completes with the outcome and never throws.
- `job.value` completes with the value, or throws on failure or
  cancellation.
- `job.ignore()` acknowledges that you will not use the outcome.

Accessing `done` or `value`, or calling `ignore()`, counts as observing a
failure. Reading `job.outcome`, receiving `onFinish` or awaiting
`job.cancel()` does not. An unobserved failure reaches the job's creation
zone on the microtask after the job finishes.

`job.whenCancelled(callback)` registers a synchronous listener and returns
a function to unregister it. The listener receives the `Cancelled` with
its reason and details. Its timing depends on how cancellation happens:

- For an external cancellation of a running job, it runs after cancellation
  has cascaded to children and `ctx.onCancel` callbacks have run, before
  the body finishes.
- For a job cancelled before start, it runs when the job is cancelled.
- If the body throws `Cancelled`, it runs after the body and its children
  have ended, before cleanup.

```dart
final job = Job<Report>(build);

// Cancellation has been accepted; the job may still be finishing.
final unregister = job.whenCancelled((cancelled) {
  print('cancelling: ${cancelled.reason}');
});

final outcome = await job.done;
// Safe after completion; call earlier to stop listening sooner.
unregister();
```

Registering after cancellation calls the listener immediately, even if
the job has finished. A refused cancellation does not notify listeners.
An `uncancellable` section delays notification until cancellation is
accepted. A job that finishes as `Done` or `Failed` without cancellation
releases its listeners without calling them. Registering a listener does
not count as observing a failure.

Each registration runs once. Listeners run in registration order, using a
snapshot of the list: removing a listener during notification does not
remove it from the current pass. A listener added during notification runs
immediately. Unregistering more than once is safe.

A synchronous listener error goes to `onError`, or to the job's creation
zone if there is no observer. A thrown `Cancelled` is never forwarded to
the zone. Listener errors do not change cancellation or prevent other
listeners from running. If you pass an `async` callback, its future is not
awaited and its errors are not caught by this mechanism.

## Cancellation

When a job accepts cancellation, it records the request. Context methods
then throw `Cancelled` so the body can stop: `check`, `wait`, `join`,
`uncancellable`, `run`, `each` and `onCancel` all check for cancellation.
You can still use `onDispose`, `onDiscard`, `disown` and `unattended`, so
the body can arrange cleanup after cancellation.

`Cancelled` implements `Exception`. If you catch `Exception` or `Object`,
rethrow the job's cancellation to avoid continuing work after it:

```dart
try {
  await ctx.join(() => database.migrate(stop));
} on Cancelled {
  rethrow; // never swallow this one
} on Exception catch (error) {
  ctx.log('migration failed: $error');
}
```

Or, when catching `Object`:

```dart
try {
  await ctx.join(() => database.migrate(stop));
} on Object catch (error) {
  if (error is Cancelled) rethrow;
  ctx.log('migration failed: $error');
}
```

Swallowing the job's cancellation lets the body continue even though the
final outcome will still be `Cancelled`. Catch specific error types where
possible, and let cancellation propagate.

A cancellation from `await child.value` may belong only to the child.
You can catch it if that child was optional. Call `ctx.check()` inside the
catch block to check the parent: it throws if the parent is cancelled too.

Choose a context method according to what should happen to the operation
when cancellation arrives:

- `ctx.join(action)` waits for the action to finish, then throws
  `Cancelled`. Use it when work must finish or stop before cleanup begins,
  such as a command already sent to a device. If a cleanup callback was
  provided, it is awaited before `Cancelled` is thrown.
- `ctx.wait(action)` throws `Cancelled` without waiting for the action to
  finish. The action continues; its eventual result is dropped or passed
  to the supplied cleanup callback. If cleanup is still in progress when
  the result arrives, that callback joins the cleanup stack and is awaited
  as part of job completion. If the job has already finished, the callback
  runs separately and is no longer included in that wait.
- `ctx.each(stream, onData)` processes stream events in order. For example:
  `Job<void>((ctx) => ctx.each(socket.messages, handle))`. It awaits an
  asynchronous `onData` callback before delivering the next event. The
  subscription is cancelled as soon as the job accepts cancellation, and
  also during cleanup on every outcome, even if the body stopped awaiting
  `each`. Cancellation does not interrupt or await an `onData` callback
  already waiting on a plain future. Cleanup may therefore close a resource
  that the callback is still using. Use context checkpoints in the callback
  if it needs to respond to cancellation.
- `ctx.uncancellable(action)` delays cancellation until the action ends.
  During the section, the job does not run `onCancel` callbacks or cascade
  cancellation to children. The request takes effect at the end of the
  section, and the next context checkpoint throws `Cancelled`. Include all
  steps that need this protection in the same section. Always await the
  call: an unawaited section can outlive the body. If the job finishes
  before the section ends, the pending cancellation is lost and `cancel()`
  can return with a `Done` outcome.
- `ctx.onCancel(callback)` runs a synchronous callback when the job accepts
  cancellation. Use it to cancel a token, abort a request or cancel a
  subscription. Dart allows an `async` function here, but its future will
  not be awaited; only synchronous errors reach `onError`, and asynchronous
  errors go to the zone. For asynchronous stop work, use
  `ctx.onCancel(() => ctx.unattended(device.stop))`.
- `ctx.unattended(action)` starts work that the job does not await or
  cancel. Its errors, including those after the job finishes, go to the
  job's observer or, without one, its creation zone. `unawaited(...)` only
  suppresses the analyzer warning and does not associate errors with a job.
  Start the work inside the callback and keep its futures and other
  asynchronous objects inside it, because it runs in a separate error zone.
- `ctx.check()` checks for cancellation where there is no operation to
  wrap, such as between steps of a calculation.

`Job(body, cancellable: false)` refuses ordinary cancellation once the
body starts. It can still be cancelled before start. A library built on
the core can also enforce cancellation through its own rules.

## Children

`ctx.run(child)` starts a child immediately. The parent waits for all its
children before finishing and passes cancellation to them. A child with
`cancellable: false` can refuse that cancellation. If the parent body
throws `Cancelled`, its children are cancelled too. If it throws another
error, the parent lets its children finish and waits for them.

```dart
final parent = Job<void>((ctx) async {
  final child = ctx.run(Job.deferred<int>((ctx) => ctx.wait(load)));
  final rows = await child.value;
  ctx.log('$rows rows');
});
```

Create children with `Job.deferred`, so the parent controls their start.
`ctx.run` rejects a regular `Job`, even before its scheduled start. This
avoids a race where the child starts independently and is left outside
the parent's cancellation and completion handling.

A child inherits the parent's observer unless it has its own. If a child's
cancellation escapes through `child.value` from the parent body, the
parent ends with `HandlerCancelReason` and a description naming the child.

`ctx.run` throws `ArgumentError` for a job from another implementation or
a job that starts automatically. It throws `StateError` if the child has
already started or the parent body has ended. If the parent is already
cancelled, it cancels the child before start and throws the parent's
`Cancelled`.

## Cleanup

Register cleanup when you acquire a resource:

```dart
final lock = await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

await ctx.join(() => database.migrate(stop));

return database;
```

Choose the callback according to who needs the resource after success:

- **`dispose`** runs on every outcome. Use it for resources used only by
  the job, such as a lock or a temporary file.
- **`discard`** runs on cancellation or failure. Use it for values the body
  returns or transfers to a caller. In this example, a successful job
  leaves the database open for the caller; otherwise, it closes it.

Using `discard` for a temporary resource that the body keeps to itself
leaks that resource on success, because the callback will not run.

For resources acquired separately, register cleanup with `ctx.onDispose`
or `ctx.onDiscard`. The same choice applies:

```dart
final buffer = StringBuffer();
ctx.onDispose(() => sink.add(buffer.toString()));
```

Both methods return a function that unregisters the callback. Use it if
the resource has already been released or transferred. Calling it again,
or after cleanup has run, is safe.

If an operation releases the resource itself, unregister inside the same
action. Otherwise, cancellation can make `join` throw before the body
reaches the unregister call, leaving the cleanup callback registered:

```dart
final remove = ctx.onDispose(cursor.close);
await ctx.join(() async {
  await cursor.readAll(); // closes it at the end
  remove();
});
```

For cleanup registered through `wait` or `join`, use `ctx.disown(value)`
when transferring ownership yourself. It removes the registration by
object identity and returns whether it found one. Pass the same instance
that the operation returned.

**Cleanup order.** Cleanup runs after all children finish, because they
may still use the parent's resources. Callbacks run in reverse registration
order, and each is awaited before the job completes. This also lets a
library built on the core wait for resource release when closing.

If cancellation arrives during cleanup, a `discard` previously skipped
on the successful path runs in a second pass. It can therefore run after
callbacks registered earlier than it.

Cleanup callbacks run outside the body, with its context closed. They are
not cancelled and must not await their own job. Keep them short and
unconditional. An error is reported to the observer; the remaining
callbacks still run.

**Cancellation after the body returns.** A job may still be waiting for
children or running cleanup after `return`. Cancellation during that time
can change its outcome to `Cancelled`. Registered resources are then
cleaned up accordingly. A value returned by an action abandoned by `wait`
is also cleaned up, regardless of the outcome, because it was never
delivered to the body.

Even if you acquire a resource with a plain `await`, you can register it
for cleanup immediately afterwards:

```dart
final job = Job<Database>((ctx) async {
  final database = await Database.open();
  ctx.onDiscard(database.close);

  return database;
});
```

Here cancellation cannot interrupt `Database.open()`. The body continues
waiting, then registers the opened database. If the job was cancelled
while opening, the final outcome is `Cancelled` and `onDiscard` closes
the database.

## Observer

`JobObserver` has four hooks: `onStart`, `onFinish`, `onError` and `onLog`.
The job calls the first three automatically. To send a log message, the
body calls `ctx.log(message)`.

Messages are passed as objects without conversion to strings. With no
observer, `ctx.log` does nothing, but Dart still evaluates its argument.
For example, `ctx.log('migration failed: $error')` formats the string even
without an observer. Pass the object directly to leave formatting to the
listener.

All four hooks have empty default implementations, so you can override
only those you need. You can also use `implements JobObserver` if your
class already extends another class. Pass the observer when creating the
job; children inherit it unless they have their own. If a hook throws,
its error goes to the current zone without changing the job's behavior.

```dart
final class Log extends JobObserver {
  @override
  void onFinish(Job<Object?> job) => print('$job: ${job.outcome}');
}

final job = Job<int>(
  key: 'load',
  observer: Log(),
  (ctx) => ctx.wait(load),
); // Job(load): Done(3)
```

A job's string representation is `Job($key)`. Use `key` to identify it in
logs or in a library's scheduling rules, such as `solo` queue policies.
`describe` adds context to the log description.

A body error is sent to the observer and stored in `Failed`. It is also
reported to the job's creation zone if the outcome remains unobserved.

Errors outside the body cannot become its outcome. These include late
errors from an action abandoned by `wait`, cleanup errors, cancellation
callback errors (`ctx.onCancel` or `job.whenCancelled`), errors from
`ctx.unattended` and errors while formatting a child's cancellation
description. They go to the observer, or directly to the job's creation
zone if there is no observer. An observer decides how to handle them.
A `Cancelled` reported through this route goes only to the observer and
is never forwarded to the zone as an unhandled error.

## Deferred start

`Job.deferred(body)` returns a `DeferredJob<T>` with a public `start()`
method. You can start it yourself, let a queue start it, or pass it to a
parent with `ctx.run(child)`.

```dart
final job = Job.deferred<void>((ctx) => ctx.wait(work));
// ... later, or from a queue of your own
job.start();
```

## Testing

A job starts and completes through microtasks. Use `package:fake_async`
to control microtasks and timers in tests without waiting in real time.
This package uses it in its own tests:

```dart
test('a cancelled open still closes what it opened', () {
  fakeAsync((async) {
    var closed = 0;
    final job = Job<Database>(
      (ctx) => ctx.join(
        Database.open,
        discard: (db) {
          closed++;
          return db.close();
        },
      ),
    );

    async.elapse(const Duration(milliseconds: 10));
    job.cancel().ignore(); // nothing awaits inside `fakeAsync`
    async.flushTimers();

    expect(job.outcome, isA<Cancelled>());
    expect(closed, 1); // what the test is named for
  });
});
```

`flushMicrotasks()` is enough to start a job. Operations scheduled through
`Future(...)` or `Future.delayed(...)` use timers, so advance them with
`flushTimers()` or `elapse(...)`.

## Building on the core

Extend `JobBase<T>` and `JobContextBase` to add features such as state,
a queue or scheduling rules. Their protected API provides access to job
status, pending cancellation, children, start and completion. Cancellation
has a flag controlling whether the job may refuse it. Override `started()`
and `finished()` to handle lifecycle events.

Use `reportToZone` to forward an error to the job's creation zone if your
own error handling has no recipient. Use `throwIfUnattended` to prevent
calls to your context methods from unattended work.

```dart
final class MyJob<T> extends JobBase<T> {
  final Future<T> Function(MyContext ctx) _body;

  MyJob(this._body, {super.key, super.observer});

  @override
  JobContextBase createContext() => MyContext(this);

  @override
  Future<T> execute(covariant MyContext ctx) => _body(ctx);

  // `start` is protected: the engine opens its own door to it.
  void launch() => start();
}

final class MyContext extends JobContextBase {
  MyContext(super.owner);
}

final job = MyJob<int>((ctx) => ctx.wait(load))..launch();
```

`wait`, `join` and `uncancellable` begin by calling `check()`. Override it
to apply additional checks to all three methods.

Protected methods are accessible within subclasses. If a separate
coordinator needs to call one, expose a wrapper on your subclass, as
`launch()` does above.

`solo` uses these extension points. The full protected API is documented in
the [JobBase](https://pub.dev/documentation/async_job/latest/async_job/JobBase-class.html)
reference.

## solo

[solo](https://pub.dev/packages/solo) adds state, a queue and declarative
rules. It runs one root job at a time and gives that job exclusive access
to state. Use it when you need a controller with these guarantees. It
re-exports `async_job`, so you only need a dependency on `solo`.

Jobs work wherever Dart runs. For `solo` widget integration, use
[flutter_solo](https://pub.dev/packages/flutter_solo).
