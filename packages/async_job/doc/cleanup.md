# Cleanup

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

- **`dispose`** runs on every outcome. Use it for resources used only by the
  job, such as a lock or a temporary file.
- **`discard`** runs on cancellation or failure. Use it for values the body
  returns or transfers to a caller. In this example, a successful job leaves
  the database open for the caller; otherwise, it closes it.

Using `discard` for a temporary resource that the body keeps to itself leaks
that resource on success, because the callback will not run.

If there is no acquisition call to wrap, register a callback directly with
`ctx.onDispose` or `ctx.onDiscard`. They follow the same outcome rules. The
callback can also perform other final work, such as flushing a buffer when the
job finishes:

```dart
final buffer = StringBuffer();
ctx.onDispose(() => sink.add(buffer.toString()));
```

Both methods return a function that unregisters the callback. Use it if the
resource has already been released or transferred. Calling it again, or after
cleanup has run, is safe.

If an operation releases the resource itself, unregister inside the same
action. Otherwise, cancellation can make `join` throw before the body reaches
the unregister call, leaving the cleanup callback registered:

```dart
final removeDisposer = ctx.onDispose(cursor.close);
await ctx.join(() async {
  await cursor.readAll(); // closes it at the end
  removeDisposer();
});
```

`wait` and `join` return the resource, so they do not give the body an
unregister function. For those registrations, use `ctx.disown(value)` when
transferring ownership yourself. It removes the registration by object identity
and returns whether it found one. Pass the same instance that the operation
returned.

**Cleanup order.** Cleanup runs after all children finish, because they may
still use the parent's resources. Callbacks run in reverse registration order,
and each is awaited before the job completes. This also lets a library built on
the core wait for resource release when closing.

Cleanup callbacks run after the body ends and are not cancelled. You cannot use
`ctx.wait` or `ctx.join` here, so await resource cleanup directly inside the
callback. It must not await its own job: `done`, `value` and `cancel()` all
wait for cleanup to finish, so that would deadlock. Keep callbacks short and
unconditional. Errors follow the observer rules below, and the remaining
callbacks still run.

**Cancellation after the body returns.** A job may still be waiting for
children or running cleanup after `return`. Cancellation during that time can
change its outcome to `Cancelled`. The database registered with `discard` will
then be closed instead of being returned to the caller. If a `discard` was
already skipped on the successful path, it runs in a second pass. It can
therefore run after callbacks registered earlier than it.

A value returned by an action abandoned by `wait` also needs cleanup,
regardless of the outcome, because it was never delivered to the body. Its
registered cleanup callback runs even if the job has already ended.

The following example shows that cleanup registration still works after a plain
`await`. For ordinary resource acquisition, prefer `ctx.join` with `discard`,
as shown above:

```dart
final job = Job<Database>((ctx) async {
  final database = await Database.open();
  ctx.onDiscard(database.close);

  return database;
});
```

Here cancellation cannot interrupt `Database.open()`. The body continues
waiting, then registers the opened database. If the job was cancelled while
opening, the final outcome is `Cancelled` and `onDiscard` closes the database.
