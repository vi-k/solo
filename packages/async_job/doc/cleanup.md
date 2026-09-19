# Cleanup

A job may open a lock, a database or a temporary file, and its children may
still be using them after the body returns. Register the release with the
context, at the point where the resource is acquired, and the job runs it when
the whole job finishes:

```dart
final lock = await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

await ctx.join(() => database.migrate(stop));

return database;
```

| Callback | When it runs |
| --- | --- |
| `dispose` | on every outcome |
| `discard` | when the job ends without handing its value over |

`wait`, `join` and `run` take both; `ctx.onDispose` and `ctx.onDiscard`
register a callback where there is no call to wrap. Passing a `dispose` and a
`discard` to one call is an `ArgumentError`.

Three sections below open with the version this vocabulary leads to — the
callback whose name matches the intent, or the registration written on the line
that reads best — and say what that version does instead of what it was meant
to do. Where the next version repairs that and brings a fault of its own, it
stands as a second attempt. The version that works follows under its own
heading.

## Choosing the callback

A job takes a lock for the work it does and opens a database it returns to
whoever asked for it. Neither may outlive the job that has no use for it.

### The first attempt

```dart
final lock = await ctx.join(Lock.acquire, discard: (lock) => lock.release());
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

return database;
```

Both resources leave with the same job, so the same callback looks right for
both. `discard` runs only when the job ends without handing its value over, and
a job that returns the database hands it over. The lock is released on every
path but the one the job is written for: cancelled or failed, it goes; done, it
stays held for as long as the process lives. A test that cancels the job sees
nothing wrong, because on that path the callback does run.

### Dispose for what stays

```dart
final lock = await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

return database;
```

`dispose` for what the job keeps to itself — a lock, a temporary file, a
subscription — and `discard` for what the body returns or hands outside. Here a
successful job leaves the database open for the caller and releases the lock
all the same; a cancelled or failed one releases both.

## A resource that travels

A resource can be opened by one job and handed to another: `connect` opens the
database, `ready` migrates it and passes it on. Whoever holds it last must
still be able to close it.

### The first attempt

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

`connect` registered the release, so the database looks covered wherever it
goes. A conditional registration is settled by the outcome of the job that made
it, and by nothing else. `connect` ended `Done` — it handed its value over — so
its `discard` is dropped together with the value, and nothing carries the
registration to the receiver. When the migration then fails, `ready` has a
database and no registration of its own, and the connection stays open with
nobody left to close it.

### The second attempt

```dart
final ready = Job.deferred<Database>((ctx) async {
  final database = await ctx.run(connect);
  ctx.onDiscard(database.close);
  await ctx.join(() => database.migrate());

  return database;
});
```

The receiver registers what it received, on the line where it receives it. With
the child's value in hand `run` checks the parent — for its own cancellation,
and for the rules of its domain — and a checkpoint that throws there takes the
value with it. The child ended `Done` and dropped its registration on the way,
the line that would have made the next one is never reached, and nothing closes
the database at all. A child that refuses the cascade with `cancellable: false`
reaches that window on any cancellation of its parent.

### Registering on arrival

```dart
final ready = Job.deferred<Database>((ctx) async {
  final database = await ctx.run(connect, discard: (db) => db.close());
  await ctx.join(() => database.migrate());

  return database;
});
```

Handed to `run`, the registration is made the moment the value comes back,
before that checkpoint. Now `ready` closes the database when it ends in
anything but a value, and hands it on untouched when it succeeds — to a
receiver that registers it the same way. This holds for every hand-over, a
group included: a branch of `ctx.runAll` registers on arrival each value its
own children hand it, like anyone else.

The receiver that registered the value on arrival is the one that closes it.
The same value stays reachable through the child's `Job.value` for as long as
anyone holds the handle, but closing it there closes it a second time. Where
the value reaches no receiver at all, closing falls to whoever holds the
handle:
[a branch that refused the group's stop](children.md#what-a-group-hands-back),
and [a chain whose `then` was cancelled while it waited](children.md#chains).

The debug channel names every hand-over that drops a registration, whether or
not the receiver registered anything, so the places where this rule applies can
be read off a run:

```text
Job(opener) handed its value over: 1 conditional cleanup dropped
```

## Registering without a call

Where there is no acquisition call to wrap, `ctx.onDispose` and `ctx.onDiscard`
register a callback directly. They follow the same outcome rules, and the
callback can do other final work as well, such as flushing a buffer when the
job finishes:

```dart
final buffer = StringBuffer();
ctx.onDispose(() => sink.add(buffer.toString()));
```

Both methods return a function that unregisters the callback. Use it when the
resource has already been released or transferred; calling it again, or after
cleanup has run, is safe. `wait`, `join` and `run` return the resource instead
of an unregister function, and the registration they made is dropped by
`ctx.disown(value)`. It looks the value up by identity and returns whether it
found one, so pass the very instance the call returned.

### The first attempt

```dart
final removeDisposer = ctx.onDispose(cursor.close);
await ctx.join(() => cursor.readAll()); // closes it at the end
removeDisposer();
```

The registration covers the cursor until the action closes it, and the line
after the action takes the registration away again. The body reaches that line
only if the call lets it: cancelled during `readAll`, `join` throws in place of
the value, and the registration is still standing. The cursor is closed by the
action, and cleanup closes it a second time.

### Unregistering inside the action

```dart
final removeDisposer = ctx.onDispose(cursor.close);
await ctx.join(() async {
  await cursor.readAll(); // closes it at the end
  removeDisposer();
});
```

Inside the action the two steps cannot be separated: whatever the call throws
afterwards, the release and its unregistration have already happened together.
The same holds for a value registered by the call itself — `ctx.disown(value)`
belongs where ownership changes, not on the line after it.

## Cleanup order and late results

| Step | What the job does |
| --- | --- |
| Children | waits for all of them, because they may use its resources |
| Cleanup stack | runs it last registration first, awaiting each callback |
| Second pass | runs a `discard` that cancellation has since made necessary |
| End | the outcome, and the release of whatever an engine holds |

Awaiting each callback is what lets a library built on the core wait for
resource release while closing.

Cleanup callbacks run after the body ends and are not cancelled. `ctx.wait` and
`ctx.join` are the body's and throw `StateError` here, so a callback awaits its
resource directly. It must not await its own job: `done`, `value` and
`cancel()` all complete after the cleanup that would be waiting for them. Keep
callbacks short and unconditional. An error from one goes to `onError` and the
remaining callbacks still run.

**Cancellation after the body returns.** A job may still be waiting for
children or running cleanup after `return`. Cancellation during that time can
change its outcome to `Cancelled`, and a database registered with `discard` is
then closed instead of being returned to the caller. A `discard` already
skipped on the successful path runs in a second pass, which puts it after
callbacks registered later than it rather than in the strict reverse order of
registration.

A branch of `ctx.runAll` is the one exception, and it is the whole point of the
hold. A branch is not let to an outcome until its group has decided, and once
the group has handed the values to the caller, a `discard` of that branch no
longer runs — not in a second pass, not on a cancellation arriving into the
unwinding, not at all. The value is in the caller's hands, and `discard` means
the value went to nobody. Until the group decides, everything above holds as
written: a cancellation reaching the branch closes what the branch took.

A value returned by an action abandoned by `wait` needs cleanup whatever the
outcome, because it never reached the body. Its registered callback runs even
after the job has ended — late and alone, with nobody waiting for it.

Registration works after a plain `await` as well, and the rule above is why it
is worth naming: a plain `await` is no checkpoint, so nothing can throw between
the call and the line under it.

```dart
final job = Job<Database>((ctx) async {
  final database = await Database.open();
  ctx.onDiscard(database.close);

  return database;
});
```

Cancellation arriving while `Database.open()` runs cannot interrupt it. The
body waits the call out, registers what it opened, and the job ends
`Cancelled` — with `onDiscard` closing the database, because the value reached
no caller. For an acquisition that a cancellation can cut short, prefer
`ctx.join` with `dispose` or `discard`, as above.
