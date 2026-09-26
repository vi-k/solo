# Observing and testing

A job's outcome tells how it ended. A `JobObserver` hears the rest: when the
job starts and ends, what its body logs, and the errors no outcome carries. The
last section tests a job without waiting in real time.

The lines under the code are what it prints when it runs. `cancel` is the
moment the user cancels, `outcome:` is what `job.done` completes with,
`onError:` is what reaches the observer, and `zone:` is an error that reached
the zone uncaught. The first section, on the observer itself, opens with the
answer. The others open with the version the names lead to — a string for
`ctx.log`, the zone for an error nobody caught, `unawaited` for a future left
on purpose, `await` for the future `cancel()` returns — and show what that code
does. The version that works follows under its own heading.

## Observer

A job loads a number. Its observer prints how the job ended and what the body
logged:

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
);
```

```text
Job(load): Done(3)
```

A `JobObserver` has five hooks: `onStart`, `onFinish`, `onError`,
`onUnanswered` and `onLog`. `Job` calls the first four itself; the body sends
messages to `onLog` through `ctx.log(message)`. `onFinish` runs for every job,
including one cancelled before it started; `onStart` runs only for a job whose
body runs.

All but `onUnanswered` do nothing by default, so you override only those you
need; what `onUnanswered` does is the subject of
[Where errors go](#where-errors-go) below. A class that already extends another
class mixes the observer in with `with JobObserver` and keeps these defaults.
Whoever runs the job passes the observer when creating it; the children it runs
inherit it unless they have their own, and a continuation made with `then`
takes only the observer passed to `then`. If one of the observer's hooks
throws, its error goes to the current zone and nothing else changes: the job
ends as it would have, and the observer's other hooks are still called.

A job's string representation is `Job($key)`, or `Job($key: $description)` when
`describe` returns something, or `Job($description)` when there is no key, or
`Job()` when there is neither. Use `key` to identify the job in logs or in a
library's scheduling rules, such as `solo` queue policies; `describe` adds
details to that representation.

An observer can also time a cancellation. `Job.whenCancelled`, registered in
`onStart`, fires when the job accepts the cancellation, and `onFinish` when the
outcome arrives; the time between them is how long the job ran past its
cancellation, children and cleanup included. A body waiting on something slow
with a bare `await` shows up with the rest of that wait, where the same call
through `ctx.wait` shows 0 ms. The count starts at acceptance, not at
`cancel()`: a cancellation held back by `ctx.uncancellable` is accepted when
the section ends, so a 100 ms section cancelled 10 ms in shows 0 ms, while the
caller of `cancel` waited 90 ms.

## A message for the log

A body migrates the database and, when the migration fails, logs the `error` it
caught. Someone debugging the app gives the job an observer; a release build
gives it none, and there the message should cost nothing.

### The first attempt

`log` takes a message, and a string is one:

```dart
ctx.log('migration failed: $error');
```

Without an observer `ctx.log` does nothing, yet the string is already built:
Dart evaluates the argument before the call, and `error.toString()` runs for
nobody.

### Formatting left to the observer

```dart
ctx.log(() => 'migration failed: $error');
```

A callback defers building the message itself. `ctx.log` passes it through
unchanged, like any other object, so without an observer nothing is built. With
one, building it is the observer's convention: the `Log` above calls a callback
and prints what it returns, and an observer that prints the message as it came
prints the closure itself. Passing `error` alone leaves the formatting to the
observer too, and needs no convention.

## Where errors go

The app reports every error that reaches its zone uncaught. A job opens the
database, the user cancels while it opens, and then the open fails: the
database is locked.

### The first attempt

Dart sends an error nobody caught to the zone, so the app counts on the zone
and gives the job no observer:

```dart
final job = Job<Database>(
  (ctx) => ctx.join(
    Database.open,
    discard: (database) => database.close(),
  ),
);
```

```text
cancel
outcome: Cancelled(manual)
```

Nothing reaches the zone, and the app never learns that the open failed: the
job itself caught the error. The job accepted the cancellation while the
database was opening, so it ends `Cancelled` whatever the open does. `join`
then throws the open's own error, and the body gives up with it on a job that
is already cancelled. That error is not the outcome, and the job hands it to
its observer alone. Most often such an error is the operation stopping at the
job's token, the way the migration throws `DatabaseStopped` in
[A token through `onCancel`](cancellation.md#a-token-through-oncancel) on the
cancellation page, and in the zone every such cancellation would show up as a
failure. The job cannot tell that stop from a failure like this one, so without
an observer neither is heard.

### An observer

```dart
final class Reporter extends JobObserver {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onError: $error');
}

final job = Job<Database>(
  observer: Reporter(),
  (ctx) => ctx.join(
    Database.open,
    discard: (database) => database.close(),
  ),
);
```

```text
cancel
onError: Bad state: database locked
outcome: Cancelled(manual)
```

An observer hears every error of its job through `onError`, and only hears it:
overriding `onError` moves no error anywhere. Where each one goes, with an
observer and without, the zone being the one the job was created in:

| The error | With an observer | Without one |
| --- | --- | --- |
| The body's, and the job ends `Failed` with it | `onError`, and the zone if nobody observed the outcome | The zone if nobody observed the outcome |
| The body's, and a cancellation arrives while the job waits for its children or runs its cleanup | `onError`, then `onUnanswered`: the zone by default | The zone |
| The body's, after the job accepted a cancellation | `onError` | Nobody |
| The body's, in a branch of `ctx.runAll` whose group throws another failure | `onError`, then `onUnanswered`: the zone by default | The zone |
| Outside the body: a late error of an action abandoned by `wait`, cleanup, a callback of `ctx.onCancel` or `job.whenCancelled`, work of `ctx.unattended`, formatting a child's cancellation description | `onError`, then `onUnanswered`: the zone by default | The zone |
| A `Cancelled` thrown outside the body | `onError`, then `onUnanswered`: nobody by default | Nobody |

The errors no outcome carries go on from `onError` to `onUnanswered`, the hook
that answers for them. Its default body sends them where they go without an
observer, to the zone, and drops a cancellation: a `Cancelled`, or a
`ParallelWaitError` carrying nothing but cancellations. So an observer written
to watch, like `Reporter`, changes nowhere an error goes. An observer that
answers for these errors itself overrides `onUnanswered`:

```dart
@override
void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
    print('onUnanswered: $error');
```

The errors stop there and do not reach the zone. Calling
`super.onUnanswered(job, error, stackTrace)` sends one on to the zone as well.
Hand `super` whatever the override cannot tell apart: the default body knows
which errors are cancellations.

The override answers for the job that got the observer and for the children
that inherit it, at any depth. The app answers for every job at once in its
zone, where it already reports what nobody caught: the default body brings
these errors there. The zone gets the error and its stack trace but not the
job, so a report that names the job takes an override.

An error can reach `onError` and the zone both, and an app that reports in both
places hears it twice. The table shows the way each error takes to the zone:
when nobody observed the outcome, or when `onUnanswered` sends it on. Observing
the outcome closes the first way;
[A failure nobody waits for](outcomes.md#a-failure-nobody-waits-for) on the
outcomes page shows how. An override of `onUnanswered` closes the second. For
the two failures of a body the table sends to `onUnanswered` — one a
cancellation covered, and one of a branch whose group throws another —
`job.ignore()` closes the second way as well: `onError` hears the failure, and
nobody answers for it.

## Work the job does not wait for

A job sends an analytics event and does not wait for it, and the sending fails:
analytics is offline. The job has the `Reporter` from the section above.

### The first attempt

Dart's `unawaited` marks a future left on purpose:

```dart
unawaited(analytics.send('loaded'));
```

```text
outcome: Done(null)
zone: Bad state: analytics offline
```

The observer hears nothing, and nothing ties the error to the job. A future
nobody awaits hands its error to the zone as an uncaught one; `unawaited` only
tells the analyzer that not waiting is on purpose.

### Work handed to the job

```dart
ctx.unattended(() => analytics.send('loaded'));
```

```text
outcome: Done(null)
onError: Bad state: analytics offline
zone: Bad state: analytics offline
```

`ctx.unattended(action)` keeps the work's errors with the job, including errors
after the job finishes: its observer hears them, and its `onUnanswered` sends
them on to the zone the job was created in. Without an observer they go
straight there. The job does not wait for the work and does not cancel it.

Start the work inside the callback and take nothing out of it: the work runs in
an error zone of its own, and the boundary holds both ways. A future made
outside and awaited in there never comes back if it fails, and its error goes
to the zone it was made in. A future made in there and awaited outside hangs
whoever awaits it if it fails; awaited by the body, it hangs the job.

## Testing

A test checks that cancelling a database open still closes the database once
opening finishes. `package:fake_async` runs timers and microtasks on fake time,
so the test waits for nothing in real time; this package uses it in its own
tests.

### The first attempt

`cancel()` returns a future that completes when the job is over, so the test
awaits it:

```dart
test('a cancelled open still closes what it opened', () {
  fakeAsync((async) async {
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
    await job.cancel();

    expect(job.outcome, isA<Cancelled>());
    expect(closed, 1);
  });
});
```

The test passes, and it would pass with `expect(closed, 0)` as well: neither
`expect` runs. Under `fakeAsync` time moves only when the test moves it. The
callback returns at its first `await`, `fakeAsync` returns with it, and nothing
moves the time again, so the future of `cancel()` never completes. Written as
`() => fakeAsync(...)`, the test waits for that future instead and fails on its
timeout.

### Time moved by the test

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

Nothing inside `fakeAsync` awaits: the future of `cancel()` is ignored,
`flushTimers()` runs the open to its end, and the checks see what happened.
`flushMicrotasks()` is enough to start a job, since its body starts on a
microtask. Operations scheduled through `Future(...)` or `Future.delayed(...)`
use timers, so advance them with `flushTimers()` or `elapse(...)`.
