# Cleanup

A job may take a lock, open a database or create a temporary file, and its
children may still be using them after the body returns. Register the release
with the context, at the point where the resource is acquired, and the job runs
it when the whole job finishes:

```dart
final lock = await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

await ctx.join(() => database.migrate());

return database;
```

| What the job holds | Member | When it runs |
| --- | --- | --- |
| What it keeps to itself, from a call: a lock, a temporary file, a subscription | `dispose` of `abandonable`, `join` or `run` | on every outcome |
| What the body returns or hands outside, from a call | `discard` of `abandonable`, `join` or `run` | unless the job ends `Done` |
| What it keeps to itself, with no call to wrap | `ctx.onDispose` | on every outcome |
| What the body returns or hands outside, with no call to wrap | `ctx.onDiscard` | unless the job ends `Done` |
| A value of `abandonable`, `join` or `run` that changes hands | `ctx.disown(value)` | never: it drops the registration the call made |

Passing a `dispose` and a `discard` to one call is an `ArgumentError`.

The lines under the code below are what it prints when it runs. The lock, the
database, its cache and the cursor say what happens to them, `cancel` is the
moment the user cancels, and `outcome:` is how the job ends.

## Choosing the callback

A job takes a lock for the work it does and opens a database it returns to
whoever asked for it. The lock is needed by the work of the job, and the
database by the caller, if it reaches one; neither may live longer than it is
needed. The job succeeds.

### The first attempt

Both resources leave with the same job, so the same callback looks right for
both:

```dart
// The first attempt: on success the lock is never released.
final lock = await ctx.join(Lock.acquire, discard: (lock) => lock.release());
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

return database;
```

```text
lock acquired
database opened
outcome: Done(database)
```

The lock is never released. This is what happens:

1. `discard` runs only when the job does not end `Done`.
2. A job that returns the database ends `Done(database)`, so neither `discard`
   runs.
3. The database stays open for the caller, as it should, and the lock stays
   held for as long as the process lives.

Cancelled or failed, the job releases both; only the path it is written for
leaks the lock. A test that cancels the job sees nothing wrong, because on that
path the callback does run.

### `dispose` for what the job keeps

```dart
final lock = await ctx.join(Lock.acquire, dispose: (lock) => lock.release());
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

return database;
```

```text
lock acquired
database opened
lock released
outcome: Done(database)
```

| Resource | Callback | The job is done | The job fails or is cancelled |
| --- | --- | --- | --- |
| What the job keeps to itself: a lock, a temporary file, a subscription | `dispose` | released | released |
| What the body returns or hands outside | `discard` | handed over open | released |

A branch of `ctx.runAll` releases later than its body ends. It starts unwinding
only when every branch of the group has ended its body and waited for its
children, or when the body of one of them has ended in anything but a value. A
lock two branches share stays taken until then. The branch waiting for it keeps
the group from getting there, so the group hangs.
[Branches that wait for each other](groups.md#branches-that-wait-for-each-other)
on the groups page shows the hang and how to take such a lock.

## A value the job keeps back

A job opens a database for its caller and hands it over only when the schema is
current. Otherwise it returns `null`, and the caller migrates first. This time
the schema is out of date.

### The first attempt

```dart
// The first attempt: the database the job keeps back stays open.
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

if (!await ctx.join(database.isCurrent)) {
  return null;
}

return database;
```

```text
database opened
outcome: Done(null)
```

The database is never closed, and nobody holds it. This is what happens:

1. `discard` runs only when the job does not end `Done`.
2. `return null` ends the job `Done(null)`. `discard` asks how the job ended,
   not where the database went, so it does not run.

The debug channel, switched on with `Job.debug = print;`, names the value the
job ended without:

```text
Job() ended Done(null) without the value of 1 conditional cleanup (database): unless it is inside the result, nothing will dispose of it
```

### Closing what the job keeps back

```dart
final database = await ctx.join(
  Database.open,
  discard: (database) => database.close(),
);

if (!await ctx.join(database.isCurrent)) {
  ctx.disown(database);
  await database.close();
  return null;
}

return database;
```

```text
database opened
database closed
outcome: Done(null)
```

The body that keeps the value back closes it itself, and takes the registration
back first. A cancellation may come while the database closes and end the job
`Cancelled`; without `ctx.disown` the `discard` would then close the database a
second time.

## A resource that travels

A resource can be opened by one job and handed to another: `connect` opens the
database, `ready` migrates it and passes it on. Whoever holds it last must
still be able to close it.

### The first attempt

`connect` registered the release, so the database looks covered wherever it
goes. The migration fails:

```dart
// The first attempt: discard stays with connect, and the database leaks.
final connect = Job.deferred<Database>(
  key: 'connect',
  (ctx) => ctx.abandonable(
    Database.open,
    discard: (database) => database.close(),
  ),
);

final ready = Job.deferred<Database>((ctx) async {
  final database = await ctx.run(connect);
  await ctx.join(() => database.migrate());

  return database;
});
```

```text
database opened
database migration failed
outcome: Failed(MigrationFailed)
```

The database stays open with nobody left to close it. This is what happens:

1. `connect` ends `Done`: it handed its value over, so its `discard` is dropped
   together with the value.
2. A `discard` is a conditional registration. It is settled by the outcome of
   the job that made it, not of the job the value goes to, and nothing carries
   it to the receiver.
3. The migration fails, and `ready` ends with a database and no registration of
   its own.

The one exception to the second point, a branch of `ctx.runAll`, is in
[Cancellation after the body returns](#cancellation-after-the-body-returns).

The debug channel, switched on with `Job.debug = print;`, names every hand-over
that drops a registration, whether or not the receiver registered anything, so
the places where this rule applies can be read off a run. For `connect` above
it says:

```text
Job(connect) handed its value over: 1 conditional cleanup dropped
```

### The second attempt

The receiver registers what it received, on the line where it receives it:

```dart
// The second attempt: a checkpoint in run can lose the value first.
final ready = Job.deferred<Database>((ctx) async {
  final database = await ctx.run(connect);
  ctx.onDiscard(database.close);
  await ctx.join(() => database.migrate());

  return database;
});
```

A failed migration closes the database now. But the user cancels `ready` just
as `connect` has ended, and the database is lost again:

```text
database opened
cancel
outcome: Cancelled(manual)
```

This is what happens:

1. `connect` ends `Done` and drops its registration on the way.
2. With the child's value in hand, `run` checks the parent: for its own
   cancellation and, under an engine built on the core such as `solo`, for the
   rules of that engine. The check throws, here the cancellation, and the value
   goes with it.
3. The `onDiscard` line is never reached, and nothing closes the database at
   all.

### Registering on arrival

```dart
final ready = Job.deferred<Database>((ctx) async {
  final database = await ctx.run(
    connect,
    discard: (database) => database.close(),
  );
  await ctx.join(() => database.migrate());

  return database;
});
```

The same cancellation:

```text
database opened
cancel
database closed
outcome: Cancelled(manual)
```

Handed to `run`, the cleanup takes the value the moment it comes back, and the
checkpoint can no longer take it away. When the checkpoint throws, `run` closes
the database on the spot and waits for the close before the body hears the
cancellation; when it passes, the registration goes on the stack of `ready`.
Now `ready` closes the database when it ends in anything but a value, and hands
it on untouched when it succeeds, to a receiver that registers it the same way.
When the cancellation comes decides who closes the database:

| When `ready` is cancelled | The second attempt | Registering on arrival |
| --- | --- | --- |
| While `connect` opens the database | `connect`, cancelled through the cascade | `connect`, cancelled through the cascade |
| After `connect` has ended `Done`, before `run` hands the value to the body | nobody | `ready` |
| While a `connect` with `cancellable: false` opens it | nobody: `connect` ends `Done` all the same | `ready` |

This holds for every hand-over, a group included: a branch of `ctx.runAll`
registers on arrival each value its own children hand it, like anyone else. The
checkpoint of `ctx.join` after its action releases the value the same way,
whatever it throws, a rule of the engine that throws included.

The receiver that registered the value on arrival is the one that closes it.
The same value stays reachable through the child's `Job.value` for as long as
anyone holds the handle, but closing it there closes it a second time. Where
the value reaches no receiver at all, closing falls to whoever holds the
handle. A branch that refused the group's stop is one such case, in
[What a group hands back](groups.md#what-a-group-hands-back); a chain whose
`then` was cancelled while it waited is another, on the [Chains](chains.md)
page.

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
cleanup has run, is safe. `abandonable`, `join` and `run` return the resource
instead of an unregister function, and the registration they made is dropped by
`ctx.disown(value)`. It looks the value up by identity and returns whether it
found one, so pass the very instance the call returned.

### The first attempt

`readAll` closes the cursor once it has read everything. The job registers the
close to cover the cursor until the read closes it, and takes the registration
back after the read. The user cancels during the read:

```dart
// The first attempt: a cancellation in readAll closes the cursor twice.
final removeDisposer = ctx.onDispose(cursor.close);
await ctx.join(() => cursor.readAll()); // closes the cursor at the end
removeDisposer();
```

```text
cancel
cursor read
cursor closed
cursor closed
outcome: Cancelled(manual)
```

The cursor is closed twice. This is what happens:

1. `join` waits for `readAll`, which reads and closes the cursor.
2. The job is cancelled during the read, so `join` throws the cancellation in
   place of the value, and the line that takes the registration away never
   runs.
3. The registration is still standing, and cleanup closes the cursor a second
   time.

### Unregistering inside the action

```dart
final removeDisposer = ctx.onDispose(cursor.close);
await ctx.join(() async {
  await cursor.readAll(); // closes the cursor at the end
  removeDisposer();
});
```

```text
cancel
cursor read
cursor closed
outcome: Cancelled(manual)
```

Inside the action the two steps cannot be separated: whatever the call throws
afterwards, the release and its unregistration have already happened together.
The same holds for a value registered by the call itself: `ctx.disown(value)`
belongs where ownership changes, not on the line after it.

An asynchronous hand-over and its `ctx.disown` go together inside one awaited
`ctx.uncancellable` section. The step is a bare `await`, not `ctx.join`, and
nothing between it and `ctx.disown` throws the job's cancellation, no member of
the context and no `await child.value`, because a section does not hold a
cancellation the rules of an engine make.

### Registering after a plain `await`

Registration works after a plain `await` as well. A plain `await` is no
checkpoint, unlike the `ctx.run` of [The second attempt](#the-second-attempt):
nothing can throw between the call and the line under it. The user cancels
while the database opens:

```dart
final job = Job<Database>((ctx) async {
  final database = await Database.open();
  ctx.onDiscard(database.close);

  return database;
});
```

```text
cancel
database opened
database closed
outcome: Cancelled(manual)
```

Cancellation arriving while `Database.open()` runs cannot interrupt it. The
body waits the call out, registers what it opened, and the job ends
`Cancelled`; `onDiscard` closes the database, because the value reached no
caller. Where the body waits through `ctx.abandonable`, `ctx.join` or
`ctx.run`, hand the callback to that call, as
[Registering on arrival](#registering-on-arrival) does. Each of them is a
checkpoint, and the line under it may never run.

## Cleanup order and late results

The body has returned, and the job still has its children and its cleanup
ahead. It takes them in this order:

| Step | What the job does |
| --- | --- |
| Children | waits for all of them, because they may use its resources |
| Cleanup stack | runs it last registration first, awaiting each callback |
| Second pass | runs a `discard` that cancellation has since made necessary |
| End | the outcome, and the release of whatever an engine holds |

Each callback is awaited, so the job ends only after the last of them is over.
Whoever waits for the job waits for them too: a `solo` controller completes
`close()` only once the cleanup of the job it cancelled has run.

The callbacks on the cleanup stack run after the body ends, and cancellation
does not interrupt them: neither one already accepted nor one arriving into the
unwinding itself. `check`, `abandonable`, `join`, `pause`, `uncancellable`,
`run`, `start`, `runAll`, `each` and `onCancel` are the body's and throw
`StateError` here, so a callback must await its resource directly. On a
cancelled job `check` throws the job's `Cancelled` instead, as it does once the
job has finished. So an action the body walked away from, polling `check` to
stop, gets the cancellation it waits for.

A callback must not await its own job: `done`, `value` and `cancel()` all
complete after the cleanup that would be waiting for them. Keep callbacks
short, and let them wait for nothing but the release itself: nothing will
interrupt them. An error from one goes to `onError` and, by default, on to the
zone, and the remaining callbacks still run; a `Cancelled` stops at `onError`.

### Cancellation after the body returns

A job may still be waiting for children or running cleanup after `return`. The
body returns the database while a child still warms its cache, and the user
cancels then:

```dart
final job = Job<Database>((ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );
  // The body does not wait for the cache; the job does.
  ctx.start(Job.deferred<void>((c) => c.join(database.warmCache)));

  return database;
});
```

```text
database opened
cancel
cache warmed
database closed
outcome: Cancelled(manual)
```

A cancellation during that time changes the outcome to `Cancelled`, and the
database registered with `discard` is closed instead of being returned to the
caller. Here it comes while the job waits for the cache, so the `discard` runs
in its place on the stack. A cancellation that comes into the unwinding after
the stack has passed a `discard` over runs it in a second pass. The second pass
puts that `discard` after callbacks registered before it, rather than in the
strict reverse order of registration.

A branch of `ctx.runAll` is the one exception. Once its group has handed the
values to the caller, a `discard` of the branch no longer runs: not in a second
pass, not on a cancellation arriving into the unwinding, not at all. The value
is in the caller's hands, and `discard` means the value went to nobody. This is
why a group holds a branch whose body has returned a value. It holds the branch
until every branch has returned one and run its cleanup stack, or until the
body of one of them ends in anything but a value. A branch gets no outcome
before that. While the group holds the branch, everything above applies as
written: a cancellation reaching the branch closes what the branch took.

### A value that comes late

A value returned by an action abandoned by `abandonable` needs cleanup whatever
the outcome, because it never reached the body. When its callback runs depends
on when the value arrives:

| When the value arrives | When its callback runs |
| --- | --- |
| During the body, while the job waits for its children, or while a branch of `ctx.runAll` waits for its group | at once |
| While the job runs its cleanup stack | on the stack, after the callback that is running |
| After the job has ended | at once, late and alone, with nobody waiting for it |

The callback does not wait for the unwinding. A child the job is still waiting
for may want the same lock or slot of a pool, and a value held for the
unwinding would keep it from that child for good. A release that begins before
the job ends keeps the job from ending until the release is over.

In the first row of the table the release runs alongside the rest of the job:
the body, the children and the release of another such value. Of the cleanup
callbacks, only the callback of a late value overlaps anything. On the cleanup
stack the release takes the place of a callback registered when the value came.
A callback registered later may run while the release is still going. One
registered earlier, such as the one that closes the pool the value came from,
runs only once the release is over.

A branch of `ctx.runAll` waits for its group twice: before its cleanup stack
and after it, until every branch has run its own. A value that comes before the
stack is released as above. One that comes after it is released at once too.
But the stack has run by then, the callback that closes the pool included, and
only the end of the branch waits for the release. Kept for the second pass, the
value would keep the slot from the cleanup of another branch the group waits
for, and the group would wait for good.

A value that comes to a call the body walked away from without a cancellation
still goes to whoever holds the call's future, and its release waits for the
unwinding on the stack. The core takes a value for late from the moment it
learns the body has ended, not from the body's `return`, so a call that gives
out a resource is not one to walk away from.

A call left unawaited on purpose has its type written out,
`unawaited(ctx.abandonable<Database>(...))`. Without it `T` is inferred from
`unawaited` as `void`, and `dispose` has to take `void`.
