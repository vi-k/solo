# Time

A pause and a deadline are the two places where cancellation meets time:
`ctx.pause` waits and ends the moment the job is cancelled, and `timeout`
cancels the job once its limit runs out. A wait that a cancellation must not
cut short takes its bound from `Future.timeout` instead, as
[A call that may not come back](#a-call-that-may-not-come-back) shows. The rest
of cancellation is on [Cancellation](cancellation.md).

The code works with the database of the cancellation page: `database.readAll`
reads the rows in 10 ms, and the migration takes three steps of 10 ms. Before
each step the migration reads a `CancelToken`, the database client's stop
signal and not a type of this package; finding it cancelled, it stops by
throwing `DatabaseStopped`. The app names that stop once, in `main`, as
[A token through `onCancel`](cancellation.md#a-token-through-oncancel) shows,
and every job on this page runs with that line. The last section stops the
device of that page, whose stop takes 10 ms.

The lines under the code are what it prints when it runs. The database and the
device say what they do, `cancel` is the moment the user cancels, and
`printing`, the observer of every job with lines under it, prints what reaches
it: `log:` for `ctx.log`, `onError:` for an error. `outcome:` is what
`job.done` completes with. A failure nobody observes goes on to the answer,
which for `printing` is the zone, as
[A failure nobody waits for](outcomes.md#a-failure-nobody-waits-for) shows.

## Letting time pass

The job reads the rows once a second.

### The first attempt

```dart
// The first attempt: a plain await sits the delay out.
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
// The second attempt: the timer of the delay outlives the job.
await ctx.abandonable(
  () => Future<void>.delayed(const Duration(seconds: 1)),
);
```

Now the delay is behind a checkpoint, and the job ends the moment it is
cancelled. But `abandonable` ends the waiting, not the work, and the work here
is a timer. A `Future.delayed` cannot be cancelled, so its timer runs for the
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
other, and the pause runs its whole length. A negative duration counts as zero,
as it does for `Future.delayed`: unlike a `timeout`, `ctx.pause` does not throw
for it.

## A deadline

The migration is given 15 ms. Past that, the job should stop the way it stops
when the user cancels: the token stops the migration, and `discard` closes the
database. Nobody cancels by hand here.

### The first attempt

`cancel` is what stops a job, so a timer calls it once the limit has run out:

```dart
// The first attempt: the timer of the limit outlives the job.
const limit = Duration(milliseconds: 15);

final job = Job<Database>(observer: printing, (ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );
  final stop = CancelToken();
  ctx.onCancel(stop.cancel);

  await ctx.join(() => database.migrate(stop));

  return database;
});
Timer(limit, job.cancel);
```

```text
step 1
step 2
migration stopped
onError: DatabaseStopped
database closed
outcome: Cancelled(manual)
```

The job stops as it does for the user in
[A token through `onCancel`](cancellation.md#a-token-through-oncancel) on the
cancellation page, and a job that has already finished is left as it is:
`cancel()` does nothing to it. But the timer lives until the limit, whether the
job is over or not. A migration that fails on a bad schema ends the job
`Failed` at once, and the timer runs for the 15 ms that are left with nothing
to cancel. A program that has nothing else to do does not exit until it fires,
and a test that looks for pending timers finds one.

### The second attempt

The timer is cancelled when the job ends:

```dart
// The second attempt: reading done keeps the failure from the zone.
final timer = Timer(limit, job.cancel);
job.done.whenComplete(timer.cancel);
```

No timer is left behind now, but reading `job.done` observes the outcome. The
failure on the bad schema still reaches the observer as `onError` and no longer
reaches the zone. Without an observer nobody hears it, and the code that
cancels the timer has to report it itself.

### A deadline of the job

```dart
final job = Job<Database>(observer: printing, timeout: limit, (ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );
  final stop = CancelToken();
  ctx.onCancel(stop.cancel);

  await ctx.join(() => database.migrate(stop));

  return database;
});
```

```text
step 1
step 2
migration stopped
onError: DatabaseStopped
database closed
outcome: Cancelled(timeout)
```

`timeout` gives the job a deadline of its own. When the deadline runs out, the
job is cancelled with `TimeoutCancelReason`, whose `timeout` is the limit. The
outcome says so: `Cancelled(timeout)`, where the timer of the first attempt
left `Cancelled(manual)`, the same as the user's.

The deadline is a cancellation like that of `cancel()`, not the
`TimeoutException` of `Future.timeout`:

- The body stops at its next checkpoint.
- An `uncancellable` section holds the request until it closes, and the job
  takes it then, before the body returns: a body that ends with
  `return ctx.uncancellable(...)` ends `Cancelled(timeout)`, the value of the
  section reaches neither the outcome nor `value`, and the registrations of
  `onDiscard` run. Only a body that went on without awaiting the section can be
  over while the section still holds the request: then the request goes with
  the timer, and the job ends with what the body returned. See
  [Holding the cancellation back](cancellation.md#holding-the-cancellation-back).
- A job cancelled already keeps its own reason.
- The children hear the deadline as the cause of their `ParentCancelReason`.

The deadline bounds the body and the children the job waits for after it, not
the cleanup stack. How the core runs the timer:

- The core starts the timer when the body starts, so the time before the start
  is not counted, such as the wait of a `Job.deferred` for its `start()` or for
  the `ctx.run` of a parent.
- The core cancels the timer before the cleanup stack unwinds: a cancellation
  arriving there would turn a job that did its work into a cancelled one and
  close its value through `discard`.
- The core cancels the timer however else the job ends.

The core observes nothing as it cancels the timer, so with `timeout` a failure
of the job still reaches the zone:

| How the job gets its limit | Timer left behind | A failure of the job |
| --- | --- | --- |
| `Timer(limit, job.cancel)` | for 15 ms more | reaches the zone |
| `job.done.whenComplete(timer.cancel)` | none | reaches no zone |
| `timeout: limit` | none | reaches the zone |

A job still running when a test ends holds its timer like any other. A test
under `fakeAsync` or `testWidgets` ends such a job, by cancelling it or waiting
for it, before the test itself ends.

A deadline that is zero or negative throws `ArgumentError`, and so does one
that comes with `cancellable: false`: the deadline is a cancellation the job
may refuse, and a job with `cancellable: false` would refuse it.

### A deadline for one step

A page goes out without its thumbnail if the thumbnail takes longer than 15 ms;
`renderThumbnail` takes 20. One step gets a deadline as a child of its own,
made by `ctx.child`, which the engine of the job accepts:

```dart
final thumbnail = ctx.child<String>(
  renderThumbnail,
  key: 'thumbnail',
  timeout: const Duration(milliseconds: 15),
);
try {
  return 'page with ${await ctx.run(thumbnail)}';
} on Cancelled catch (cancelled) {
  ctx.check();
  if (cancelled.reason case TimeoutCancelReason(:final timeout)) {
    return 'page without a thumbnail after ${timeout.inMilliseconds} ms';
  } else {
    rethrow;
  }
}
```

```text
outcome: Done(page without a thumbnail after 15 ms)
```

The child ends `Cancelled(timeout)`, and `ctx.run` throws that cancellation
into the body of the parent. The parent itself is not cancelled: the deadline
ran out for the child. A `catch` clause in Dart filters by type alone, with no
pattern and no `when`, so the clause takes every `Cancelled`. `ctx.check()`
comes first in it and throws the job's own cancellation, because the reason of
a deadline does not say whose deadline it is: a job whose own `timeout` ran out
before `ctx.run` gets its own `Cancelled(timeout)` from it up front, and
without the check would take it for the thumbnail's and go on. The pattern goes
into an `if` after it: it matches the reason of the deadline and takes its
duration. The `else` rethrows a thumbnail somebody else cancelled. Let out, the
child's deadline ends the parent
`Cancelled(body: Job(thumbnail): Cancelled(timeout))`. The key is there for
that line: a child without one prints as `Job()`.

## A call that may not come back

The job stops the device and then releases it, and it waits for the stop whole:
a device released while it is still stopping is what
[A stop that takes time](cancellation.md#a-stop-that-takes-time) on the
cancellation page sets out to avoid. A stop takes 10 ms, but now and then the
device does not answer one at all. After 15 ms the job should give up on such a
stop and release the device all the same.

### The first attempt

```dart
// The first attempt: a stop the device never answers holds the job for good.
ctx.onDispose(device.release);
await ctx.join(device.stop);
```

The device does not answer the stop, and the user cancels 5 ms in:

```text
cancel
```

Nothing comes after that line: the job never ends, and the device is never
released. `join` waits for its action whole, through a cancellation too, and
this action never comes back. `cancel()` returns once the job has ended, so the
future it returns never completes either.

### The second attempt

A deadline bounds a wait, and
[A deadline for one step](#a-deadline-for-one-step) gives one to a single step
as a child:

```dart
// The second attempt: a cancellation of the job walks away from the stop.
ctx.onDispose(device.release);
await ctx.run(
  ctx.child(
    (ctx) => ctx.abandonable(device.stop),
    key: 'stop',
    timeout: const Duration(milliseconds: 15),
  ),
);
```

The device does not answer the stop:

```text
device released
outcome: Cancelled(body: Job(stop): Cancelled(timeout))
```

The bound holds. The child ends `Cancelled(timeout)` after 15 ms, the device is
released, and the deadline of the child, let out of the body, ends the job. The
child waits for the stop with `abandonable`: with `join` in it, the deadline
would wait for the stop as well, and a stop that never comes back would hold
the child as the first attempt holds the job.

The device answers in 10 ms, and the user cancels 5 ms in:

```text
cancel
device released
outcome: Cancelled(manual)
device stopped
```

A cancellation of the job passes to its children, and `abandonable` in the
child walks away from a stop 5 ms short of its end: the device is released
while it is still stopping. It is the trace of the first attempt of
[A stop that takes time](cancellation.md#a-stop-that-takes-time), and the stop
is the call the job wanted to wait for whole.

### A timeout inside `join`

```dart
ctx.onDispose(device.release);
try {
  await ctx.join(
    () => device.stop().timeout(const Duration(milliseconds: 15)),
  );
} on TimeoutException {
  ctx.log('the device did not answer');
}
```

The device does not answer the stop:

```text
log: the device did not answer
device released
outcome: Done(null)
```

The device answers in 10 ms, and the user cancels 5 ms in:

```text
cancel
device stopped
device released
outcome: Cancelled(manual)
```

`join` waits for the stop whole, through a cancellation of the job, and
`Future.timeout` bounds that wait: after 15 ms the future `join` waits for
fails with a `TimeoutException`. It is the `TimeoutException` of Dart, an error
of the call, and not a deadline of the core: no job is cancelled, and no
`TimeoutCancelReason` is made. `join` throws an error of its action as it is,
cancelled or not, so the body says what a stop without an answer means: here a
line in the log, and the job ends `Done`, or `Cancelled` when the user
cancelled meanwhile. Without the `try` the job ends `Failed` with the
`TimeoutException`; a job cancelled meanwhile ends `Cancelled`, and the error
goes where any failure of the body of a cancelled job goes: to the observer and
then to the zone. A stop that ends or fails after the bound reaches nobody:
`Future.timeout` drops what comes too late itself.

`ctx.uncancellable` around the child of the second attempt waits for the stop
as well: the section holds the cancellation of the job back, and the child does
not hear it, as
[Holding the cancellation back](cancellation.md#holding-the-cancellation-back)
on the cancellation page shows. Two things set it apart from a timeout inside
`join`. A cancellation the job cannot refuse, such as a rule an engine adds, is
not held, and the child walks away from the stop as in the second attempt,
while `join` waits through it. And a stop that fails after the bound fails in a
call the child walked away from, so its error reaches the observer and the
zone, where `Future.timeout` drops it.
