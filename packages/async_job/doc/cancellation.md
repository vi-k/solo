# Cancellation

`cancel()` requests; the body answers at a checkpoint. Which checkpoint it
is decides what happens to the operation behind it:

```dart
Job<void>((ctx) async {
  // The wait ends at once; the request goes on, and its value is
  // dropped or handed to the cleanup callback.
  final rows = await ctx.wait(db.readAll);

  // Waited out to the end, and only then does the cancellation come
  // out in place of the value.
  await ctx.join(() => db.migrate(stop));

  // Nothing marks the job while this runs; the next checkpoint throws.
  await ctx.uncancellable(() => db.markReady(stop));

  // Nothing to wrap between the steps of a calculation.
  ctx.check();
  use(rows);
});
```

| Method | If cancellation arrives while it waits |
| --- | --- |
| `ctx.wait(action)` | Throws `Cancelled` at once. The action continues; its result is dropped or passed to the cleanup callback. |
| `ctx.join(action)` | Waits for the action, then throws instead of returning the value. A cleanup callback for that value is awaited first. |
| `ctx.uncancellable(action)` | Holds the request until the section ends: no `onCancel`, no cascade to children while it runs. |
| `ctx.check()` | Throws when the job has already accepted cancellation. |

After `Job` accepts the request, `check`, `wait`, `join`, `uncancellable`,
`run` and `each` throw `Cancelled` at their checkpoints. `onCancel` also
throws if registration comes too late, because the cancellation
notification has already happened. `onDispose`, `onDiscard`, `disown` and
`unattended` remain available so the body can arrange cleanup after
cancellation.

If the action awaited by `join` fails, its original error is thrown even
after cancellation, and the job's accepted cancellation remains in effect.
Use `join` when work must finish or stop before cleanup, such as a command
already sent to a device. With `wait`, a result arriving late is dropped
or passed to the supplied cleanup callback: if the job is still finishing,
that callback joins its cleanup stack and is awaited before completion;
if the job has already finished, the callback runs separately.

Always await `ctx.uncancellable`. The section opens when called, even if
you do not await its future. An unawaited section can outlive the body;
if `Job` finishes first, the pending cancellation is lost and `cancel()`
can return with a `Done` outcome. To protect the entire body instead of
one section, create `Job(body, cancellable: false)`. It refuses ordinary
cancellation once the body starts, but can still be cancelled before
start. A library built on the core can enforce cancellation through its
own rules.

Inside an action passed to the context, ordinary `await` is appropriate.
Several steps inside `ctx.uncancellable` can complete together: the
context manages the whole action and does not add checkpoints between its
internal steps. If those steps need separate cancellation checks, add
context calls there too.

## Catching without swallowing

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

## Stopping the underlying operation

Cancellation marks the job. Stopping the work behind it needs the
operation's own mechanism:

```dart
// Ask the operation itself to stop, then wait for it to do so.
ctx.onCancel(stop.cancel);
await ctx.join(() => database.migrate(stop));

// When stopping is itself asynchronous.
ctx.onCancel(() => ctx.unattended(device.stop));
```

`ctx.onCancel(callback)` runs synchronously when the job accepts
cancellation, before the body reaches a checkpoint. Use it to cancel a
token, abort a request or cancel a subscription.

Passing an `async` callback directly to `onCancel` is allowed by Dart, but
its future will not be awaited — hence the `unattended` above. Only
synchronous callback errors reach `onError`; asynchronous errors go to
the zone.

## Work the job does not wait for

```dart
// Neither awaited nor cancelled, and its errors still belong to this job.
ctx.unattended(() => analytics.send('migrated'));
```

`ctx.unattended(action)` keeps the work's errors associated with the job,
including errors after the job finishes: they go to its observer or,
without one, its creation zone. `unawaited(...)` only suppresses the
analyzer warning and does not provide this error handling. Start the work
inside the callback and keep its futures and other asynchronous objects
inside it, because it runs in a separate error zone.
