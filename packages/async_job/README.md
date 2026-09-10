# async_job

`async_job` adds cancellation, child tasks and resource cleanup to
asynchronous Dart code. The package works in pure Dart and depends only
on `meta`.

A `Job<T>` runs a function called its body and records how it ended. Use
`await job.done` to get its outcome or `await job.value` to get the value
returned by the body. `Job` itself does not implement `Future`.

## Why

A plain `Future` has no cancellation operation. Flags and cancellation
tokens let you ask work to stop; `CancelableOperation` lets you cancel
waiting for a result. When that work also starts child tasks or opens
resources, you need to decide who waits for the children, closes the
resources and handles errors after the caller stops waiting.

`Job` manages this lifetime. It finishes with one of three
outcomes: `Done`, `Failed` or `Cancelled` with a reason. It waits for its
children and runs registered cleanup before completing. An unobserved
`Failed` is reported to the zone that created the job, just as Dart reports
an unhandled `Future` error. For errors from work the body no longer
awaits, `Job` also provides an observer.

Cancellation is cooperative: `cancel()` requests it, and the body stops
when it reaches a cancellation checkpoint. `Job` provides these checkpoints
through the context, `ctx`, passed to the body. Await external asynchronous
operations through its methods. For example, `ctx.join(action)` checks
cancellation before starting the operation, waits for it to finish, then
checks again before returning its value to the body.

A direct `await action()` is allowed, but does not check job cancellation.
It keeps waiting, and the code after it can run even if the job has been
cancelled. That is why using the context is part of writing a cancellable
body.

`async_job` does not provide state management, a task queue or scheduling
rules. If you need them, use `solo`, which adds these features on top of
`async_job` and re-exports its API.

Neither package provides retries, timeouts or a task pool; applications
can add these as needed.

## Install

```sh
dart pub add async_job
```

## Quick start

Suppose a job needs to open a database, migrate it and return the open
database to its caller. If the job fails or is cancelled, it must close
the database instead. The context lets the body describe both paths:

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
  final step from a request to stop. During migration, `join` waits while
  the token tells the database to stop. Here the step must finish without
  receiving that signal, so `uncancellable` holds the cancellation request:
  `onCancel` does not fire and the token remains active during the call.
  After the section, the request takes effect and the next context
  checkpoint throws `Cancelled`. See [Cancellation](#cancellation).
- **`await job.cancel()`** requests cancellation and waits for the job to
  finish, including its cleanup. The outcome on the next line is therefore
  ready. You can omit `await` if you only need to request cancellation.

The complete runnable example, including a fake `Database`, is in
`example/example.dart`.

## Outcomes

Once the body, its children and cleanup have finished, `job.done`
completes with an `Outcome<T>`. It never throws: success, failure and
cancellation are represented by `Done`, `Failed` and `Cancelled`.
`Outcome<T>` is sealed, so a `switch` covering these cases is exhaustive:

```dart
final message = switch (await job.done) {
  Done(:final value) => 'done $value',
  Failed(:final error) => 'failed $error',
  Cancelled(:final reason) => 'cancelled $reason',
};
```

If you only need the returned value, await `job.value`. It completes with
the value on success and throws on failure or cancellation. If you do not
need the result at all, call `job.ignore()` to acknowledge that choice.

Accessing `done` or `value`, or calling `ignore()`, counts as observing a
failure. Forwarding a failure through `then` observes it too; the
continuation takes responsibility for it. Reading `job.outcome`,
receiving the observer's `onFinish` callback
or awaiting `job.cancel()` does not. An unobserved failure reaches the
job's creation zone on the microtask after the job finishes. This keeps a
failure visible even when no caller waits for the result.

For a cancelled job, the outcome also explains why it stopped.
`Cancelled` contains a `reason`, a `started` flag, an optional `description`
and the stack trace of the cancellation. `started` tells you whether the
body ran or was cancelled before start. The built-in reason classes are
`ManualCancelReason`, `ParentCancelReason`, `HandlerCancelReason` and
`ChainCancelReason`, all extending `CancelReason`.

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

To react when cancellation is accepted, without waiting for the final
outcome, register a listener with `job.whenCancelled(callback)`. It runs
synchronously and receives the `Cancelled` with its reason and details.
The registration method returns a function to unregister the listener.
Its timing depends on how cancellation happens:

- For an external cancellation of a running job, it runs after cancellation
  has cascaded to children and `ctx.onCancel` callbacks have run, without
  waiting for the body to finish.
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

The cancellation listener tells the caller that cancellation was accepted.
The body learns about it through its context: after `Job` accepts the
request, `check`, `wait`, `join`, `uncancellable`, `run` and `each` throw
`Cancelled` at their checkpoints. `onCancel` also throws if registration
comes too late, because the cancellation notification has already happened.
`onDispose`, `onDiscard`, `disown` and `unattended` remain available so the
body can arrange cleanup after cancellation.

`Cancelled` implements `Exception`. If you catch `Exception` or `Object`,
rethrow the job's cancellation to avoid continuing work after it.
You can handle `Cancelled` in a separate catch clause:

```dart
try {
  await ctx.join(() => database.migrate(stop));
} on Cancelled {
  rethrow; // never swallow this one
} on Exception catch (error) {
  ctx.log('migration failed: $error');
}
```

Or check its type inside a shared catch clause:

```dart
try {
  await ctx.join(() => database.migrate(stop));
} on Object catch (error) {
  if (error is Cancelled) rethrow;
  ctx.log('migration failed: $error');
}
```

Both forms work with either `Exception` or `Object` as the broader catch
type. If `Job` has already accepted cancellation, catching its `Cancelled`
does not undo that cancellation. Code after the catch can run, but the next
context checkpoint throws again. When the job finishes, its outcome is
still `Cancelled`, even if the body returns a value. Catch specific error
types where possible, and let the job's cancellation propagate.

A caught `Cancelled` does not by itself mean this `Job` was cancelled.
If an operation throws it and the body catches it, the job can still end
with `Done`, provided it has not itself accepted cancellation. The same
applies to a cancellation from `await child.value`: you can catch it if
that child was optional. Call `ctx.check()` inside the catch block to
check the parent; it throws if the parent is cancelled too.

For an operation already in progress, choose whether cancellation should
wait for it to finish, stop waiting immediately or be delayed until the
operation ends:

- `ctx.join(action)` calls the action and waits for its result. If
  cancellation arrives during the call, it waits for the result and then
  throws `Cancelled`. Use it when work must finish or stop before cleanup,
  such as a command already sent to a device. If you supplied a cleanup
  callback for the returned value, it is awaited before the throw.
- `ctx.wait(action)` also calls the action and returns its result, but
  throws `Cancelled` immediately if cancellation arrives while waiting.
  The action continues. Its eventual result is dropped or passed to the
  supplied cleanup callback. If the job is still finishing, the callback
  joins its cleanup stack and is awaited before completion. If the job has
  already finished, the callback runs separately.
- `ctx.uncancellable(action)` delays cancellation until the action ends.
  During the section, `Job` does not run `onCancel` callbacks or cascade
  cancellation to children. The request takes effect when the section
  ends, and the next context checkpoint throws `Cancelled`. Include all
  steps that need this protection in the same section.

Always await `ctx.uncancellable`. The section opens when called, even if
you do not await its future. An unawaited section can outlive the body;
if `Job` finishes first, the pending cancellation is lost and `cancel()`
can return with a `Done` outcome. To protect the entire body instead of
one section, create `Job(body, cancellable: false)`. It refuses ordinary
cancellation once the body starts, but can still be cancelled before
start. A library built on the core can enforce cancellation through its
own rules.

Inside an action passed to the context, ordinary `await` is appropriate.
For example, several steps inside `ctx.uncancellable` can complete
together. The context manages the whole action; it does not add
checkpoints between its internal steps. If those steps need separate
cancellation checks, add context calls there too. Use `ctx.check()` where
there is no operation to wrap, such as between steps of a calculation.

To stop the underlying operation, it needs its own cancellation mechanism.
In the database example, `ctx.onCancel(stop.cancel)` signals the token,
and `join` waits for the migration to respond. `ctx.onCancel(callback)`
runs synchronously when the job accepts cancellation, before the body
reaches a checkpoint. Use it to cancel a token, abort a request or cancel
a subscription.

If stopping is itself asynchronous, use
`ctx.onCancel(() => ctx.unattended(device.stop))`. Passing an `async`
callback directly to `onCancel` is allowed by Dart, but its future will
not be awaited. Only synchronous callback errors reach `onError`;
asynchronous errors go to the zone.

`ctx.unattended(action)` starts work that the job does not await or cancel.
It keeps the work's errors associated with the job, including errors after
the job finishes: they go to its observer or, without one, its creation
zone. `unawaited(...)` only suppresses the analyzer warning and does not
provide this error handling. Start the work inside the callback and keep
its futures and other asynchronous objects inside it, because it runs in
a separate error zone.

For a stream, `ctx.each(stream, (child, event) { ... })` starts and returns
a child `Job<void>` that owns the subscription. The callback receives
that child's `JobContext`. For example, `ctx.each(socket.messages,
(child, message) => child.join(() => handle(message)))` processes messages
in order and waits for each handler before delivering the next message.
The first stream or callback error ends processing with a failed outcome;
a thrown `Cancelled` ends it with cancellation.

Keep the returned job as `subscription` to cancel it separately with
`await subscription.cancel()`. Use `await subscription.value` to await
completion and throw a failure or cancellation into the body, or
`await subscription.done` to inspect the outcome. Cancelling this child
does not itself mark the parent cancelled. An uncaught `Cancelled` from
its `value` cancels the parent under the usual child outcome rules.

The parent waits for the child even if its body returns without awaiting
it. An open stream therefore keeps the parent alive until the stream ends
or the child is cancelled. Accepted parent cancellation cascades to the
child. The observer sees this child as a separate job.

When the child accepts cancellation, it immediately cancels the
subscription and stops delivering events. It then waits for any running
callback before completing and releasing resources, so parent cleanup
also waits. Use the child's context checkpoints inside the callback:
a plain `await` cannot be interrupted and can delay cancellation forever.
Do not await the child's own completion or `cancel()` from its callback;
the child is already waiting for that callback.

The future returned by the underlying subscription's `cancel()` is not
awaited. If the source needs asynchronous cleanup, arrange to await that
cleanup separately. Normal stream completion still depends on the source
sending `onDone`. Like `run`, `each` can only start children while the
parent body is active; calls from `unattended` or cleanup are rejected.

## Children

When a body delegates work to another job, register it as a child with
`ctx.run(child)`. This starts the child immediately and returns a future
of its result. The parent waits for all its children before finishing
and passes cancellation to them. A child with `cancellable: false` can
refuse that cancellation. If the parent body
throws `Cancelled`, its children are cancelled too. If it throws another
error, the parent lets its children finish and waits for them.

```dart
final parent = Job<void>((ctx) async {
  final child = Job.deferred<int>((ctx) => ctx.wait(load));
  final rows = await ctx.run(child);
  ctx.log('$rows rows');
});
```

Create children with `Job.deferred`, so the parent controls their start.
`ctx.run` rejects a regular `Job`, even before its scheduled start. This
avoids a race where the child starts independently and is left outside
the parent's cancellation and completion handling.

`run` waits for the child to finish, including its children and cleanup,
and checks the parent's cancellation before returning the value to the
body. If the child refuses cancellation, `run` still waits for it; after
the child succeeds, `run` throws the parent's cancellation instead of
continuing to the log call. No separate `ctx.join` or `ctx.check()` is
needed. A child's error or cancellation is thrown through the returned
future with its stack trace.

The original `child` remains the handle for cancellation and inspecting
its outcome; `run` does not create another job. A plain `await child.value`
only delivers the child's value or error and does not check the parent's
cancellation. To start a child concurrently, retain the future returned
by `run` and await it later, or handle its errors. Use
`ctx.run(child).ignore()` when deliberately ignoring that result. The
parent still waits for the child before finishing. Ignoring the handle
with `child.ignore()` alone does not handle errors of the `run` future;
an unhandled future error, including cancellation, follows Dart's rules.

A child inherits the parent's observer unless it has its own. If a child's
cancellation escapes through `await ctx.run(child)` or `child.value`, the
parent ends with `HandlerCancelReason` and a description naming the child.

`ctx.run` throws synchronously for an invalid start: `ArgumentError` for
a job from another implementation or a job that starts automatically.
It throws `StateError` if the child has
already started or the parent body has ended. If the parent is already
cancelled, it cancels the child before start and throws the parent's
`Cancelled`.

## Chains

Use `then` to continue a job with its result. Each call returns a new
`Job` and gives its callback a separate context. The next callback starts
after the previous job succeeds, including its children and cleanup:

```dart
final loaded = Job<String>((ctx) => ctx.join(loadText));
final parsed = loaded.then<int>((ctx, text) => int.parse(text));
final saved = parsed.then<void>((ctx, number) => ctx.join(
      () => saveNumber(number),
    ));

await saved.value;
```

Cancelling `saved` also asks unfinished `parsed` and `loaded` to cancel.
Cancelling `parsed` asks unfinished `loaded` to cancel and cancels `saved`.
Cancelling `loaded` passes cancellation forward through both continuations.
Each forwarded request carries `ChainCancelReason` with the adjacent
job's `Cancelled` in `cause`. Completed jobs keep their outcomes. If you
attach several continuations to one job, cancelling one can cancel their
shared source and the other continuations too.

`await saved.cancel()` waits for the unfinished predecessors, their
children and cleanup, and any work and cleanup already started by `saved`.
Sources retain their normal cancellation rules: `cancellable: false`
refuses a request, and `uncancellable` holds it. A cancelled continuation
still waits for that source, then finishes without calling its callback.
While waiting, it can be `isCancelled` without being `isFinished`; its
outcome has `started: false` if it was cancelled while waiting for its
source.

A failed predecessor forwards its error and stack without calling the
callback. Observe the tail through `value`, `done` or `ignore` to handle
that failure. If a cancelled continuation cannot forward a source failure,
it does not observe it either: for example, a source that refuses
cancellation and later fails still needs its own error handling.

The callback accepts a value or future. Returning another `Job` does not
wait for it; return `ctx.run(child)` for a deferred child. `then` does
not start a deferred source, and a continuation cannot be adopted through
`ctx.run`. Do not await a continuation from its source's body or cleanup:
the continuation is waiting for that source to finish.

Each continuation is a root job of the core. It has an optional `observer`
argument and inherits neither the source's observer nor domain state,
rules or a queue slot. Cleanup registered by the source has already run
when the continuation receives its value; a resource closed by the
source's `onDispose` is therefore already closed at that point.

## Cleanup

The parent may open resources that its children still use after the body
returns. Register cleanup with the context so it runs when the whole job
finishes. You can register it at the point where you acquire the resource:

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

If there is no acquisition call to wrap, register a callback directly
with `ctx.onDispose` or `ctx.onDiscard`. They follow the same outcome
rules. The callback can also perform other final work, such as flushing a
buffer when the job finishes:

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
final removeDisposer = ctx.onDispose(cursor.close);
await ctx.join(() async {
  await cursor.readAll(); // closes it at the end
  removeDisposer();
});
```

`wait` and `join` return the resource, so they do not give the body an
unregister function. For those registrations, use `ctx.disown(value)`
when transferring ownership yourself. It removes the registration by
object identity and returns whether it found one. Pass the same instance
that the operation returned.

**Cleanup order.** Cleanup runs after all children finish, because they
may still use the parent's resources. Callbacks run in reverse registration
order, and each is awaited before the job completes. This also lets a
library built on the core wait for resource release when closing.

Cleanup callbacks run after the body ends and are not cancelled. You
cannot use `ctx.wait` or `ctx.join` here, so await resource cleanup directly
inside the callback. It must not await its own job:
`done`, `value` and `cancel()` all wait for cleanup to finish, so that would
deadlock. Keep callbacks short and unconditional. Errors follow the
observer rules below, and the remaining callbacks still run.

**Cancellation after the body returns.** A job may still be waiting for
children or running cleanup after `return`. Cancellation during that time
can change its outcome to `Cancelled`. The database registered with
`discard` will then be closed instead of being returned to the caller.
If a `discard` was already skipped on the successful path, it runs in a
second pass. It can therefore run after callbacks registered earlier
than it.

A value returned by an action abandoned by `wait` also needs cleanup,
regardless of the outcome, because it was never delivered to the body.
Its registered cleanup callback runs even if the job has already ended.

The following example shows that cleanup registration still works after
a plain `await`. For ordinary resource acquisition, prefer `ctx.join`
with `discard`, as shown above:

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

An outcome describes one job's result. Use `JobObserver` to also receive
lifecycle events, logs and errors from work outside the body.
It has four hooks: `onStart`, `onFinish`, `onError` and `onLog`. `Job` calls
the first three automatically; the body sends messages to `onLog` through
`ctx.log(message)`.

All four hooks have empty default implementations, so you can override
only those you need. You can also use `implements JobObserver` if your
class already extends another class. Pass the observer when creating the
job; children inherit it unless they have their own. If a hook throws,
its error goes to the current zone without changing the job's behavior.

```dart
final class Log extends JobObserver {
  @override
  void onFinish(Job<Object?> job) => print('$job: ${job.outcome}');

  @override
  void onLog(Job<Object?> job, Object? message) {
    final data = message is Object? Function() ? message() : message;
    print('$job: $data');
  }
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

Messages passed to `ctx.log` remain objects until the listener formats
them. With no observer, `ctx.log` does nothing, but Dart still evaluates
its argument. For example, `ctx.log('migration failed: $error')` formats
the string even without an observer. Pass the object directly to leave
formatting to the listener, or pass a callback to defer building the
message itself:

```dart
ctx.log(() => 'migration failed: $error');
```

The observer above calls the callback and formats the returned data.
Without an observer, the callback is never called and the interpolation
does not run. This is a convention of this observer: `ctx.log` passes the
callback through unchanged, just like any other object.

A body error is sent to the observer. If the job ends with that error,
it is stored in `Failed` and is also reported to the job's creation zone
if the outcome remains unobserved.

Errors outside the body cannot become its outcome. These include late
errors from an action abandoned by `wait`, cleanup errors, cancellation
callback errors (`ctx.onCancel` or `job.whenCancelled`), errors from
`ctx.unattended` and errors while formatting a child's cancellation
description. They go to the observer, or directly to the job's creation
zone if there is no observer. An observer decides how to handle them.
A `Cancelled` reported through this route goes only to the observer and
is never forwarded to the zone as an unhandled error.

## Deferred start

A regular `Job` schedules its own start on the next microtask. If the
caller needs to choose when work begins, use `Job.deferred(body)` instead.
It returns a `DeferredJob<T>` with a public `start()` method. You can call
it yourself, let a queue start the job, or pass it to a parent with
`ctx.run(child)`, as in the children example.

```dart
final job = Job.deferred<void>((ctx) => ctx.wait(work));
// ... later, or from a queue of your own
job.start();
```

## Testing

Testing start, cancellation and cleanup requires controlling microtasks
and timers. `package:fake_async` lets you do this without waiting in real
time. This package uses it in its own tests; here it checks that cancelling
a database open still closes the database once opening finishes:

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

If your library needs its own state, queue or scheduling rules, extend
`JobBase<T>` and `JobContextBase`. The base classes handle the job lifetime
described above, while your subclasses add the library's behavior.
Their protected API provides access to job status, pending cancellation,
children, start and completion. Cancellation has a flag controlling
whether the job may refuse it. Override `started()`
and `finished()` to handle lifecycle events.

For example, a custom job can create its own context type and expose a
method for its coordinator to start it:

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

When adding your own error handling, use `reportToZone` to forward an
error to the job's creation zone if there is no recipient. For a context
method that must not be called from unattended work, use
`throwIfUnattended` to enforce that restriction.

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
