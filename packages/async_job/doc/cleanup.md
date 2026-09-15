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

**A resource that travels registers again on arrival.** A conditional
registration is settled by the outcome of the job that made it, and by nothing
else. A job that ends `Done` handed its value to somebody, so its `discard` is
dropped together with the value, and nothing carries it to the receiver. Here
`connect` opens the database and `ready` hands it on migrated:

```dart
final connect = Job.deferred<Database>(
  (ctx) => ctx.wait(Database.open, discard: (db) => db.close()),
);

final ready = Job.deferred<Database>((ctx) async {
  final database = await ctx.run(connect);
  await ctx.join(() => database.migrate());

  return database;
});
```

`connect` ended `Done`, so its `discard` never runs — and when the migration
fails, `ready` has a database and no registration of its own, so the connection
stays open with nobody left to close it. Register the resource where it
arrives, and the rule carries on from there:

```dart
final ready = Job.deferred<Database>((ctx) async {
  final database = await ctx.wait(
    () => ctx.run(connect),
    discard: (db) => db.close(),
  );
  await ctx.join(() => database.migrate());

  return database;
});
```

Through `wait` and not a plain `await` with an `onDiscard` after it: a child
that refuses a cancellation ends `Done` while its parent is already cancelled,
`ctx.run` then throws the parent's own `Cancelled`, and a registration written
on the next line is never reached. `wait` is handed the value all the same and
runs the `discard`.

A received value then has two ways back to the same resource: the registration
the receiver made, and the child's own `Job.value`, which carries it for as
long as anyone holds the handle. Only one of them may close it. The receiver
that registered it on arrival owns it, and closing it through the handle as
well closes it twice; [Children, streams and chains](children.md) names the
handle for the case where the value reaches no receiver at all.

Now `ready` closes the database when it ends in anything but a value, and hands
it on untouched when it succeeds — to a receiver that registers it the same
way. This holds for every hand-over, a group included: a branch of `ctx.runAll`
that got its value from a child of its own registers it on arrival like anyone
else.

The debug channel names every hand-over that drops a registration, whether or
not the receiver registered anything, so the places where this rule applies can
be read off a run:

```text
Job(opener) handed its value over: 1 conditional cleanup dropped
```

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

A branch of `ctx.runAll` is the one exception, and it is the whole point of the
hold. A branch is not let to an outcome until its group has decided, and once
the group has handed the values to the caller, a `discard` of that branch no
longer runs — not in a second pass, not on a cancellation arriving into the
unwinding, not at all. The value is in the caller's hands, and `discard` means
the value went to nobody. Until the group decides, everything above holds as
written: a cancellation reaching the branch closes what the branch took.

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
