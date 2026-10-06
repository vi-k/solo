# Cancellation

`cancel()` requests; the body stops at a checkpoint. Which checkpoint it is
decides what happens to the operation behind it:

```dart
Job<void>((ctx) async {
  // The database client's own stop signal, cancelled with the job.
  final stop = CancelToken();
  ctx.onCancel(stop.cancel);

  // The wait ends at once; the read goes on, and its value is dropped.
  final rows = await ctx.abandonable(database.readAll);

  // Waited for until the migration ends or stops at the token, and
  // only then does the job give up.
  await ctx.join(() => database.migrate(stop));

  // The cancellation waits for the whole step, and the child it
  // runs is not cancelled; the next checkpoint throws it.
  await ctx.uncancellable(() async {
    await database.writeVersion();
    await ctx.run(database.readyFlag());
  });

  // Nothing to wrap between the steps of a calculation.
  ctx.check();
  use(rows);
});
```

| Method | If cancellation arrives while it waits |
| --- | --- |
| `ctx.abandonable(action)` | Abandons the action: stops waiting for it and throws `Cancelled` at once, while the action goes on. Its result is dropped, or goes to the call's `dispose` or `discard` if it has one. |
| `ctx.join(action)` | Joins the action: keeps waiting for it until it ends, then throws `Cancelled` instead of returning the value, or the action's own error if it failed. If the call has a `dispose` or `discard`, the value goes there first, and `join` throws once that callback has finished. |
| `ctx.uncancellable(action)` | Holds the request until the section ends: no `onCancel`, no cascade to children while it runs. |
| `ctx.pause(duration)` | Throws `Cancelled` at once, and cancels its timer. |
| `ctx.check()` | Throws when the job has already accepted cancellation. |

A running job accepts the request inside `cancel()` itself, unless an
`uncancellable` section holds it back or the job was created with
`cancellable: false`. Accepting it makes the job cancelled: the cancellation
passes to the children it has started, its `onCancel` callbacks run, and the
job ends `Cancelled` whatever the body does next. From then on `check`,
`abandonable`, `join`, `pause`, `uncancellable`, `run`, `runAll` and `each`
throw `Cancelled` at their checkpoints. `onCancel` throws too: its callbacks
have already run, and one registered now never would. `onDispose`, `onDiscard`,
`disown` and `unattended` remain available so the body can arrange cleanup
after cancellation.

A body that gives itself up, by throwing `Cancelled` or by letting out the
cancellation of a child, accepts the cancellation as it throws, and the job is
cancelled the same way: the cancellation passes to its children, its `onCancel`
callbacks run, and it ends `Cancelled`.

Inside an action passed to the context, a plain `await` is right: the context
adds no checkpoint between the steps of that action, and a step that needs a
check of its own takes a context call of its own.
[A step that must finish](#a-step-that-must-finish) puts two writes in a `join`
each and then in one `join`, and shows what each form does when the
cancellation comes during the first write.

The lines under the code are what it prints when it runs. The database says
what it writes, and `printing`, the observer of every job below, prints what
reaches it: `log:` for `ctx.log`, `onError:` for an error. `cancel` is the
moment the user cancels, and `outcome:` is what `job.done` completes with. Each
part of the page below opens with the version habit or the names of the API
lead to — `abandonable` to answer a cancellation at once, `join` to see a step
through, a clause for `Cancelled` to let the cancellation pass, a plain
`Future.delayed` between two reads — and shows what that code does. Where the
version that repairs it still falls short, it stands as a second attempt, and
the version that works follows under its own heading.

## Stopping the operation

The job opens a database, migrates it and hands it over; `discard` closes it
when the job ends without handing it over. The migration takes three steps of
10 ms and reads a `CancelToken` before each, the database client's stop signal
and not a type of this package; finding it cancelled, it stops by throwing
`DatabaseStopped`. When the user cancels, the migration should stop, and the
database should close once nothing writes into it. The user cancels during the
second step, 15 ms in.

### The first attempt

The body waits for the migration through `abandonable`, so that a cancellation
ends the job at once:

```dart
final job = Job<Database>(observer: printing, (ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );
  final stop = CancelToken();

  await ctx.abandonable(() => database.migrate(stop));

  return database;
});
```

```text
step 1
cancel
database closed
outcome: Cancelled(manual)
step 2 on a closed database
step 3 on a closed database
```

`abandonable` ends the waiting, not the migration. The cancellation comes out
of `abandonable` at once, the job ends, and `discard` closes the database with
two steps of the migration still to write. Whatever the migration throws
afterwards goes to `onError` and, by default, on to the zone. `abandonable` is
for an operation the job may walk away from, such as a read whose result nobody
needs any more.

A result arriving that late is dropped, or goes to the `dispose` or `discard`
passed to `abandonable`. While the body or the job's children still run, that
callback runs at once and the job awaits it; if the job is already running its
cleanup stack, the callback joins the stack, and once the job has finished, the
callback runs on its own.
[Cleanup order and late results](cleanup.md#cleanup-order-and-late-results) on
the cleanup page takes this order apart.

### The second attempt

`join` stays with the migration to its end:

```dart
await ctx.join(() => database.migrate(stop));
```

```text
step 1
cancel
step 2
step 3
database closed
outcome: Cancelled(manual)
```

Nothing writes into a closed database now: `join` waits for the migration, and
the job gives up only after it. But nothing told the migration to stop either,
so it writes the step nobody wants any more, and the outcome arrives when the
migration would have ended anyway.

### A token through `onCancel`

The migration knows nothing about the job's cancellation: it listens only to
its token. `onCancel` cancels the token together with the job:

```dart
final stop = CancelToken();
ctx.onCancel(stop.cancel);

await ctx.join(() => database.migrate(stop));
```

```text
step 1
cancel
step 2
migration stopped
onError: DatabaseStopped
database closed
outcome: Cancelled(manual)
```

The callback given to `ctx.onCancel` runs synchronously when the job accepts
the cancellation, before the body reaches a checkpoint. Here it cancels the
token, the migration reads it before the third step and throws
`DatabaseStopped`, and `join` waits for that before the job closes the
database. A request to abort or a subscription to cancel goes through
`onCancel` the same way.

The `onError:` line is that `DatabaseStopped`. `join` throws an error of its
action as it is, even after a cancellation, and the body does not catch it. The
job still ends `Cancelled`, so the error is nobody's outcome: it reaches the
observer and stops there, and without an observer nothing hears it. What a
`catch` around this `join` sees is the subject of
[Catching errors of the operation](#catching-errors-of-the-operation), below.

A stop that takes time, such as a device's, needs more than `onCancel` alone.
`onCancel` takes a `void Function()`, and Dart lets an `async` function
through: the future it returns is awaited by nobody, and its error goes past
the observer to the zone the callback was called in, which for a cancellation
accepted inside `cancel()` is the zone of the code that called `cancel()`. Only
what the callback throws synchronously reaches `onError`, and an `async`
function never throws synchronously: even an error before its first `await`
goes into its future. For a device that takes a while to stop, run the stop as
work the job does not wait for:

```dart
ctx.onCancel(() => ctx.unattended(device.stop));
```

`ctx.unattended` keeps the errors of the stop with the job: they reach the
observer, and after it, by default, the zone the job was created in;
[Work the job does not wait for](observing.md#work-the-job-does-not-wait-for)
on the observing page takes it apart. That is all it does: the job does not
wait for the stop, and a device released in `onDispose` is released while it is
still stopping. To end only after the device has stopped, the job waits with
`join` for an operation the stop interrupts, here a recording that ends only
once the device has stopped:

```dart
ctx.onCancel(() => ctx.unattended(device.stop));
await ctx.join(device.record);
```

`join` waits until the stop has ended the recording, as it waits for the
migration to stop at the token. An operation that ends as soon as the stop
begins leaves `join` nothing to wait for, and the job ends while the device is
still stopping.

## A step that must finish

The migration is over, and the last step marks the database ready: it writes
the schema version and then the ready flag, and a database with the version and
no flag is neither old nor ready. The two writes are two calls of the database,
`writeVersion` and `writeReadyFlag`. The user cancels while the version is
being written.

### The first attempt

`join` waits for its action, so each write goes through one:

```dart
await ctx.join(database.writeVersion);
await ctx.join(database.writeReadyFlag);
```

```text
cancel
version written
outcome: Cancelled(manual)
```

The step does not finish: the database is left with a version and no ready
flag. Each `join` is a checkpoint of its own. The first one waits for the
version and then throws the cancellation, and the body never reaches the
second.

### One `join` for the step

```dart
await ctx.join(() async {
  await database.writeVersion();
  await database.writeReadyFlag();
});
```

```text
cancel
version written
ready flag written
outcome: Cancelled(manual)
```

The action has no checkpoint inside, so both writes are made, and the
cancellation comes out of `join` after them. That is enough while the step is
plain code: it takes no token that `onCancel` cancels, starts no child and
passes no checkpoint of the context.

## A step that runs a child

The step is the same, and the flag is written by a job of its own now:
`database.readyFlag()` returns it, and the step runs it as a child with
`ctx.run`. The user cancels while the version is being written.

### The first attempt

The step keeps its one `join`:

```dart
await ctx.join(() async {
  await database.writeVersion();
  await ctx.run(database.readyFlag());
});
```

```text
cancel
version written
outcome: Cancelled(manual)
```

The flag is lost again. `join` waits for its action, but the job accepts the
cancellation at once, and from then on `ctx.run` throws it instead of starting
the child; a child already running would be cancelled.

### Holding the cancellation back

`uncancellable` holds the cancellation back until the step is over:

```dart
await ctx.uncancellable(() async {
  await database.writeVersion();
  await ctx.run(database.readyFlag());
});
```

```text
cancel
version written
ready flag written
outcome: Cancelled(manual)
```

While the section runs, the job does not accept the cancellation: `ctx.run`
starts the child, the job's children are not cancelled, and `onCancel` does not
fire. Held, not refused: the job accepts it the moment the section closes, and
the next checkpoint throws it. The job still ends `Cancelled`, even if the body
returns a value, so whatever has to happen after the step anyway belongs inside
the same section.

If the step fails and the body lets the error through, the failure came before
the job accepted the cancellation the section held: the job still ends
`Cancelled`, and the failure reaches the zone even without an observer. Through
`join`, where the job accepts the cancellation at once, the same failure comes
after it, and only an observer hears it.
[Where errors go](observing.md#where-errors-go) on the observing page has both.

Always await `ctx.uncancellable`. The section opens when called, even if you do
not await its future. An unawaited section can outlive the body; if the job
finishes first, the held cancellation is lost: `cancel()` completes, and the
outcome is `Done`. If the body goes on without awaiting the section and then
gives itself up, by throwing `Cancelled` or by letting out the cancellation of
a child, the job accepts that cancellation at once: a section holds back a
cancellation request, not a cancellation the body throws itself. `onCancel`
runs while the section is still open, and `abandonable` inside it throws.

To protect the entire body instead of one section, create
`Job(body, cancellable: false)`. It refuses ordinary cancellation once the body
starts.

Before that the job can still be cancelled: it ends `Cancelled` with
`started: false`, and the body never runs. The flag keeps a body that has begun
from being cut short, and before the start there is nothing to cut. A job made
with `Job(body)` starts on the next microtask, so only a cancellation that
comes sooner finds it not started. A job made with `Job.deferred` waits until
someone starts it, by `start()` or by `ctx.run` of a parent, and the core
cannot tell whether anyone will. Had such a job refused the cancellation and
then never been started, it would never finish: its `done` would not complete,
the `cancel()` it refused would wait forever, and `cancel()` has no stronger
form to drop the job with.

An engine that holds jobs before their start knows what the core does not: it
starts them itself. `solo`, built on this core, starts the jobs of its queue,
and it refuses on behalf of a `cancellable: false` job while that job waits
there. [A queue of your own](extending.md#a-queue-of-your-own) on the extending
page builds such a refusal. `solo` also cancels a job when the controller's
state no longer suits it: a job there declares which states it runs in. Neither
a section nor `cancellable: false` holds that cancellation back.

## Catching errors of the operation

A failed migration is not fatal here: the body logs it and goes on to mark the
database ready. A cancelled job should still stop, and the log should hold
failures, not cancellations. The user cancels 15 ms in.

### The first attempt

A cancellation throws `Cancelled`, so a clause for it comes first and rethrows:

```dart
final stop = CancelToken();
ctx.onCancel(stop.cancel);

try {
  await ctx.join(() => database.migrate(stop));
} on Cancelled {
  rethrow;
} on Exception catch (error) {
  ctx.log('migration failed: $error');
}
await ctx.join(() async {
  await database.writeVersion();
  await database.writeReadyFlag();
});
```

```text
step 1
cancel
step 2
migration stopped
log: migration failed: DatabaseStopped
outcome: Cancelled(manual)
```

The log calls a cancellation a failed migration. The token stopped the
migration, and what came out of `join` is the migration's own
`DatabaseStopped`, not a `Cancelled`: `join` throws an error of its action as
it is. The clause for `Cancelled` lets it by, `on Exception` takes it, and the
code inside `on Exception` runs on a job that is already cancelled. The job
still ends `Cancelled`: the `join` of the next step throws before its action
starts. Without the token the clause for `Cancelled` holds: the migration runs
to its end, and `join` throws the `Cancelled`. Without that clause,
`on Exception` takes that `Cancelled` too, because `Cancelled` implements
`Exception`, and logs `migration failed: Cancelled(manual)`.

### Asking the job

Whether the job is cancelled is a question for the job, not for the error:

```dart
try {
  await ctx.join(() => database.migrate(stop));
} on Exception catch (error) {
  ctx.check();
  ctx.log('migration failed: $error');
}
```

```text
step 1
cancel
step 2
migration stopped
outcome: Cancelled(manual)
```

`ctx.check()` throws the job's cancellation if it has accepted one, whatever
the `catch` took. A migration that failed on its own is logged, and the body
goes on. There is no `onError: DatabaseStopped` line, unlike in
[A token through `onCancel`](#a-token-through-oncancel): `on Exception` catches
the `DatabaseStopped`, so it never leaves the body. The body ends with the
job's cancellation from `ctx.check()`, and a cancellation does not go to
`onError`. If the clause is to catch everything, `Error` included, as
`on Object catch (error)` does, it needs the same `ctx.check()` as its first
line.

If the job has already accepted cancellation, catching its `Cancelled` does not
undo it. Code after the catch runs, but the next checkpoint throws again, and
the outcome is still `Cancelled` even if the body returns a value.

A `Cancelled` caught in the body is not always the job's own. An operation
throws one when it waits for `value` of a job that was cancelled, and a child
started with `ctx.run` and cancelled directly, not through its parent, throws
its `Cancelled` out of `run`. `ctx.check()` passes then, because the job itself
was not cancelled, and the body goes on and can end `Done`. The clause above
logs such a `Cancelled` as a failure. Past `ctx.check()` a `Cancelled` is not
the job's, so a test of its type tells an optional child that was cancelled
from one that failed:

```dart
final thumbnail = Job.deferred<String>(renderThumbnail);
try {
  return 'page with ${await ctx.run(thumbnail)}';
} on Exception catch (error) {
  ctx.check();
  if (error is! Cancelled) ctx.log('thumbnail failed: $error');
  return 'page without a thumbnail';
}
```

A clause that rethrows every `Cancelled` ends the job too. If it is a child's
`Cancelled`, the job ends with the reason `HandlerCancelReason`; if it is the
`Cancelled` an operation got from `value` of a cancelled job, the job ends with
that job's own reason. The page on outcomes takes these reasons apart in
[Why a job was cancelled](outcomes.md#why-a-job-was-cancelled).

## Letting time pass

The job reads the rows once a second.

### The first attempt

```dart
final job = Job<void>((ctx) async {
  while (true) {
    use(await ctx.abandonable(database.readAll));
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});
```

The user cancels 500 ms in, halfway through the delay, and the job ends 510 ms
later. A plain `await` is no checkpoint: the body sits the delay out and learns
of the cancellation at the `ctx.abandonable` of the next turn. Until then
`cancel()` does not return, and whatever waits for the job waits with it.

### The second attempt

```dart
await ctx.abandonable(
  () => Future<void>.delayed(const Duration(seconds: 1)),
);
```

Now the delay is behind a checkpoint, and the job ends the moment it is
cancelled. But `abandonable` ends the waiting, not the work, and the work here
is a timer: a `Future.delayed` cannot be cancelled, so its timer runs for the
510 ms that are left, with nothing waiting for it. A program that has nothing
else to do does not exit until it fires, and a test that looks for pending
timers finds one.

### A pause of the job

```dart
await ctx.pause(const Duration(seconds: 1));
```

`ctx.pause` is a checkpoint that takes time. It throws `Cancelled` at once when
the cancellation arrives, as `ctx.abandonable` does, and its timer is cancelled
with it:

| How the body waits | The job ends | Timer left behind |
| --- | --- | --- |
| `await Future.delayed(...)` | 510 ms after the cancellation | none |
| `ctx.abandonable(() => Future.delayed(...))` | at once | for 510 ms more |
| `ctx.pause(...)` | at once | none |

Without a duration, `ctx.pause()` comes back on the next turn of the event
loop: a place for a long calculation to let other work run and to hear a
cancellation. Inside `ctx.uncancellable` the cancellation is held like any
other, and the pause runs its whole length.
