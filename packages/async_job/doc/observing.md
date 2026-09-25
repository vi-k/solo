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

It has four hooks: `onStart`, `onFinish`, `onError` and `onLog`. `Job` calls
the first three itself; the body sends messages to `onLog` through
`ctx.log(message)`. `onFinish` runs for every job, including one cancelled
before it started; `onStart` runs only for a job whose body runs.

All four do nothing by default, so you override only those you need. You can
also use `implements JobObserver` if your class already extends another class.
Pass the observer when creating the job; the children it runs inherit it unless
they have their own. If a hook throws, its error goes to the current zone and
nothing else changes: the job ends as it would have, and the other hooks are
still called.

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
[Why cancellation was slow](https://github.com/vi-k/solo/blob/main/packages/solo/doc/errors.md#why-cancellation-was-slow)
on the errors page of `solo` shows such an observer in full.

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

An error nobody caught goes to the zone, and the app hears what reaches it; the
job gets no observer:

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

Nothing reaches the zone, and the app never learns that the open failed. The
job accepted the cancellation while the database was opening, so it ends
`Cancelled` whatever the open does. `join` then throws the open's own error,
and the body gives up with it on a job that is already cancelled: that error is
not the outcome, and it goes to the observer alone. Without one, nobody hears
it.

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

An observer hears every error of its job. Where each one goes, with an observer
and without, the zone being the one the job was created in:

| The error | With an observer | Without one |
| --- | --- | --- |
| The body's, and the job ends `Failed` with it | `onError`, and the zone if nobody observed the outcome | The zone if nobody observed the outcome |
| The body's, and a cancellation arrives while the job waits for its children | `onError`, and the zone if nobody observed the outcome | The zone if nobody observed the outcome |
| The body's, after the job accepted a cancellation | `onError` | Nobody |
| Outside the body: a late error of an action abandoned by `wait`, cleanup, a callback of `ctx.onCancel` or `job.whenCancelled`, work of `ctx.unattended`, formatting a child's cancellation description | `onError` | The zone |
| A `Cancelled` thrown outside the body | `onError` | Nobody |

A failure the job ends with reaches `onError` and, when nobody observed the
outcome, the zone as well: an app that reports in both places hears it twice.
Observing the outcome keeps it out of the zone;
[A failure nobody waits for](outcomes.md#a-failure-nobody-waits-for) on the
outcomes page shows how.

## Work the job does not wait for

A job sends an analytics event and does not wait for it, and the sending fails:
analytics is offline. The job has the `Reporter` from the section above, so the
app hears about the job's errors there.

### The first attempt

Dart's `unawaited` marks a future left on purpose:

```dart
unawaited(analytics.send('loaded'));
```

```text
outcome: Done(null)
zone: Bad state: analytics offline
```

The observer hears nothing. A future nobody awaits hands its error to the zone
as an uncaught one; `unawaited` only tells the analyzer that not waiting is on
purpose.

### Work handed to the job

```dart
ctx.unattended(() => analytics.send('loaded'));
```

```text
outcome: Done(null)
onError: Bad state: analytics offline
```

`ctx.unattended(action)` keeps the work's errors with the job, including errors
after the job finishes: they go to its observer or, without one, the zone the
job was created in. The job does not wait for the work and does not cancel it.

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
