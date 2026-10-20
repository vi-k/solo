# Time

A pause and a deadline are the two places where cancellation meets time:
`ctx.pause` waits and ends the moment the job is cancelled, and `timeout`
cancels the job once its limit runs out. The rest of cancellation is on
[Cancellation](cancellation.md).

The code works with the database of the cancellation page. `database.readAll`
reads the rows in 10 ms. The migration takes three steps of 10 ms and reads a
`CancelToken` before each, the database client's stop signal and not a type of
this package; finding it cancelled, it stops by throwing `DatabaseStopped`. The
app names that stop once, in `main`, as
[A token through `onCancel`](cancellation.md#a-token-through-oncancel) shows,
and every job on this page runs with that line.

The lines under the code are what it prints when it runs. The database says
what it writes, and `printing`, the observer of the migration jobs, prints what
reaches it: `onError:` for an error. `outcome:` is what `job.done` completes
with. A failure nobody observes goes on to the answer, which for `printing` is
the zone, as
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
reaches the zone: without an observer nobody hears it, and the code that
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

`timeout` gives the job a deadline of its own. The core starts the timer when
the body starts, so the time before the start is not counted, such as the wait
of a `Job.deferred` for its `start()` or for the `ctx.run` of a parent. When
the deadline runs out, the job is cancelled with `TimeoutCancelReason`, whose
`timeout` is the limit, and the outcome says so: `Cancelled(timeout)`, where
the timer of the first attempt left `Cancelled(manual)`, the same as the
user's.

The deadline is a cancellation like that of `cancel()`, not the
`TimeoutException` of `Future.timeout`:

- the body stops at its next checkpoint;
- an `uncancellable` section holds the request until it closes;
- a job cancelled already keeps its own reason;
- the children hear the deadline as the cause of their `ParentCancelReason`.

If the body and the children it waits for are over while the section still
holds the request, the request goes with the timer, and the job ends with what
the body returned.

The deadline bounds the body and the children the job waits for after it, not
the cleanup stack. The core cancels the timer before the stack unwinds: a
cancellation arriving there would turn a job that did its work into a cancelled
one and close its value through `discard`. It cancels the timer however else
the job ends, and observes nothing as it does:

| How the job gets its limit | Timer left behind | A failure of the job |
| --- | --- | --- |
| `Timer(limit, job.cancel)` | for 15 ms more | reaches the zone |
| `job.done.whenComplete(timer.cancel)` | none | reaches no zone |
| `timeout: limit` | none | reaches the zone |

A job still running when a test ends holds its timer like any other: a test
under `fakeAsync` or `testWidgets` ends such a job, by cancelling it or waiting
for it, before the test itself ends. A deadline that is zero or negative throws
`ArgumentError`, and so does one that comes with `cancellable: false`: the
deadline is a cancellation the job may refuse, and such a job would refuse it.

### A deadline for one step

A page goes out without its thumbnail if the thumbnail takes longer than 15 ms;
`renderThumbnail` takes 20. One step gets a deadline as a child of its own:

```dart
final thumbnail = Job.deferred<String>(
  renderThumbnail,
  key: 'thumbnail',
  timeout: const Duration(milliseconds: 15),
);
try {
  return 'page with ${await ctx.run(thumbnail)}';
} on Cancelled catch (cancelled) {
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
pattern and no `when`, so the clause takes every `Cancelled`, and the pattern
goes into an `if` inside it: it matches the reason of the deadline and takes
its duration. The `else` rethrows what is not the deadline: the job's own
cancellation, and a thumbnail somebody else cancelled. Let out, the child's
deadline ends the parent
`Cancelled(handler: Job(thumbnail): Cancelled(timeout))`. The key is there for
that line: a child without one prints as `Job()`.
