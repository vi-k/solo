# Observing and testing

A job's outcome tells how it ended. A `JobObserver` hears the rest: when the
job starts and ends, what its body logs, and the errors no outcome carries. The
last section tests a job without waiting in real time.

The lines under the code are what it prints when it runs. `cancel` is the
moment the user cancels, `outcome:` is what `job.done` completes with,
`onError:` is what reaches the observer, `onUnanswered:` is an error an
observer answered for, and `zone:` is an error that reached the zone uncaught.
The first section, on the observer itself, opens with the answer. The others
open with the version habit leads to and show what that code does. The version
that works follows under its own heading.

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
  (ctx) async {
    ctx.log('loading');
    return ctx.wait(load);
  },
);
```

```text
Job(load): loading
Job(load): Done(3)
```

A `JobObserver` has four hooks: `onStart`, `onFinish`, `onError` and `onLog`.
`Job` calls the first three itself; the body sends messages to `onLog` through
`ctx.log(message)`. `onFinish` runs for every job, including one cancelled
before it started; `onStart` runs only for a job whose body runs.

They do nothing by default, so you override only those you need. An observer
that also answers for errors mixes in `JobAnswerer`, which adds a fifth hook,
`onUnanswered`: the subject of [Where errors go](#where-errors-go) below. A
class that already extends another class mixes the observer in with
`with JobObserver`, or `with JobObserver, JobAnswerer`, and overrides the hooks
it needs the same way. Whoever runs the job passes the observer when creating
it; the children it runs inherit it unless they have their own, and a
continuation made with `then` takes only the observer passed to `then`. If one
of the observer's hooks throws, its error goes to the current zone and nothing
else changes: the job ends as it would have, and the observer's other hooks are
still called. A `Cancelled` thrown by a hook does not reach the zone: nowhere
in the core is a thrown cancellation a failure. It does not cancel the job
either. A hook that has to cancel the job calls `job.cancel()`, and the job is
cancelled as it would be from anywhere else.

A job can be given a `key` and a `describe` callback when it is created. Its
string representation is `Job($key)`, or `Job($key: $description)` when
`describe` returns a description that is not empty, or `Job($description)` when
there is no key, or `Job()` when there is neither. Use `key` to identify the
job in logs or in a library's scheduling rules, such as `solo` queue policies;
`describe` adds details to that representation.

A cancelled job is expected to end soon, and one that goes on is busy with work
the user has already given up on. An observer finds such jobs by timing how
long each one runs past its cancellation:

```dart
final class SlowCancellations extends JobObserver {
  final _since = Expando<Stopwatch>('cancellation');

  @override
  void onStart(Job<Object?> job) =>
      job.whenCancelled((_) => _since[job] = Stopwatch()..start());

  @override
  void onFinish(Job<Object?> job) {
    final watch = _since[job];
    if (watch != null) {
      print('$job ran ${watch.elapsedMilliseconds} ms past its cancellation');
    }
  }
}
```

`Job.whenCancelled`, registered in `onStart`, fires when the job accepts a
cancellation, and `onFinish` when the outcome arrives; the time between them is
how long the job ran past its cancellation, children and cleanup included. A
body waiting on something slow with a bare `await` adds the rest of that wait
to the count, where the same call through `ctx.wait` shows 0 ms. The count
starts at acceptance, not at `cancel()`: a cancellation held back by
`ctx.uncancellable` is accepted when the section ends, so a 100 ms section
cancelled 10 ms in shows 0 ms, while the caller of `cancel` waited 90 ms. A
body that gives itself up, throwing `Cancelled` or letting a child's
cancellation out, accepts the cancellation as it throws, and the count starts
there.

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
then throws the open's own error, and the body fails with it on a job that is
already cancelled. That error is not the outcome, and the job hands it to its
observer alone. Most often such an error is the operation stopping at the job's
token, the way the migration throws `DatabaseStopped` in
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

An observer hears through `onError` the errors its job catches, all but its own
cancellation, and only hears them: overriding `onError` moves no error
anywhere. Where each one goes, with an observer and without, the zone being the
one the job was created in:

| The error | With an observer | Without one |
| --- | --- | --- |
| The body's, and the job ends `Failed` with it | `onError`, and the zone if nobody observed the outcome | The zone if nobody observed the outcome |
| The body's, and the job accepts a cancellation after it: one arriving before the error leaves the body, while the job waits for its children or runs its cleanup, or one `ctx.uncancellable` held while its step failed | `onError`, then `onUnanswered` if the observer answers, the zone otherwise | The zone |
| The body's, and it happened after the job accepted a cancellation | `onError` | Nobody |
| The body's, in a branch of `ctx.runAll` whose group throws another failure | `onError`, then `onUnanswered` if the observer answers, the zone otherwise | The zone |
| Outside the body: a late error of an action abandoned by `ctx.wait`, cleanup, a callback of `ctx.onCancel` or `job.whenCancelled`, work of `ctx.unattended`, formatting a child's cancellation description | `onError`, then `onUnanswered` if the observer answers, the zone otherwise | The zone |
| A `Cancelled` thrown outside the body | `onError`, then `onUnanswered` if the observer answers, nobody otherwise | Nobody |
| The job's own cancellation, out of an action abandoned by `ctx.wait` or work of `ctx.unattended` | Nobody | Nobody |
| What a context call the body did not await throws, the job's own cancellation included, and for `ctx.wait` only until the body ends | The zone the body runs in, as with any future nobody awaits | The zone the body runs in |

Whether a failure came before a cancellation is decided by when it happened,
not by when the body threw it. The failure of an operation behind `ctx.wait` or
`ctx.join`, of a callback of `ctx.each`, of a child or of a step of
`ctx.uncancellable` does not leave the body at once: that takes a few
microtasks, or a child's whole cleanup. If the job accepts a cancellation in
between, the order is: the failure happens, the job accepts the cancellation,
the body throws the failure. The job ends `Cancelled`, but the failure came
before the cancellation, and it takes the second row of the table, not the
third. The body keeps the failure first by letting it through, or by catching
it and throwing it again later; a new error thrown in its place, a wrapper
included, comes after the cancellation. The job learns when a failure happened
from these members and from its children: a future the body awaits on its own
comes first only if the body throws its error before the cancellation.

A body that catches the failed open and shows it to the user before throwing it
again:

```dart
final job = Job<Database>(
  observer: Reporter(),
  (ctx) async {
    try {
      return await ctx.join(Database.open);
    } catch (error) {
      await showError(error);
      rethrow;
    }
  },
);
```

The open fails at 20 ms, the user cancels at 30 ms while the error is on
screen, and the body throws the failure at 50 ms:

```text
cancel
onError: Bad state: database locked
zone: Bad state: database locked
outcome: Cancelled(manual)
```

The failure came before the cancellation, which is the second row: the zone
hears it, though the job ends `Cancelled`. Cancelled at 10 ms, before the open
fails, the same failure takes the third row, and only the observer hears it:

```text
cancel
onError: Bad state: database locked
outcome: Cancelled(manual)
```

A step of `ctx.uncancellable` and the same step behind `ctx.join` land in
different rows. The section holds a cancellation that arrives while the step
runs, and the job accepts it when the section closes, on the way out of the
failure: the failure came first and reaches the zone even without an observer.
`join` lets the job accept the cancellation as it arrives, so the step's
failure comes after it, and without an observer nobody hears it.

A context call the body did not await throws into a future nobody awaits, and
Dart hands that to the zone the body runs in: for `Job.deferred`, the zone that
started it, or the one the work was started from if it was started inside
`ctx.unattended`. The job's own cancellation goes there too: when the job is
cancelled, a `ctx.wait` called without `await` throws `Cancelled` into its
future, and Dart hands it to the zone like any other error. The job itself
never sends a cancellation to the zone; Dart does. For `ctx.wait`, all of this
holds only while the body runs. Once the body has ended, `ctx.wait` stops
waiting for its action, as it does on a cancellation. If the action fails after
that, its error takes the fifth row of the table, like that of an action
`ctx.wait` stopped waiting for on a cancellation: `onError` hears it, and it
goes on to the answer like the other errors outside the body.

The errors no outcome carries go on from `onError` to an answer. An observer
written to watch, like `Reporter`, gives none, and they go where they go
without an observer: to the zone, a cancellation dropped — a `Cancelled`, or a
`ParallelWaitError` carrying nothing but cancellations. So watching changes
nowhere an error goes. An observer that answers for these errors itself mixes
in `JobAnswerer` and overrides its `onUnanswered`:

```dart
final class Answering extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onUnanswered: $error');
}
```

The errors stop there and do not reach the zone. The default implementation of
`onUnanswered` sends them to the zone the job was created in and drops a
cancellation, as happens without an answer. So calling
`super.onUnanswered(job, error, stackTrace)` sends one on to the zone as well.
An observer that answers only for the database errors it knows hands the rest
to `super`:

```dart
final class DatabaseErrors extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (error is DatabaseException) {
      print('onUnanswered: $error');
    } else {
      super.onUnanswered(job, error, stackTrace);
    }
  }
}
```

It misses a database error that comes together with another. The job hands
`ctx.unattended` two operations waited for together: `saveDraft` fails with a
`DatabaseException` at 20 ms, and `sendAnalytics` with a `StateError` at 10 ms.
`[a, b].wait` throws a `ParallelWaitError` holding both failures, and the
observer gets that one error:

```dart
final job = Job<void>(
  observer: DatabaseErrors(),
  (ctx) async {
    ctx.unattended(() => [saveDraft(), sendAnalytics()].wait);
  },
);
```

```text
outcome: Done(null)
zone: ParallelWaitError(2 errors): DatabaseException
```

The database error went to the zone unanswered, and the analytics error is not
named at all. `Job.visitErrors` hands the observer the errors inside one at a
time:

```dart
final class DatabaseErrors extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      Job.visitErrors(
        error,
        stackTrace,
        onFailure: (failure, failureStackTrace) {
          if (failure is DatabaseException) {
            print('onUnanswered: $failure');
          } else {
            super.onUnanswered(job, failure, failureStackTrace);
          }
        },
      );
}
```

```text
outcome: Done(null)
onUnanswered: DatabaseException
zone: Bad state: analytics offline
```

`super` now gets the failures one at a time, so the zone hears the analytics
error on its own instead of the whole `ParallelWaitError`. Each uncaught
`Cancelled` inside a `ParallelWaitError` goes to `onCancelled`, which this
observer does not pass, and is dropped, as the default implementation drops it.
A check for `error is Cancelled` would not drop them all: a `ParallelWaitError`
carrying nothing but `Cancelled` is not a `Cancelled` itself, and `[a, b].wait`
throws exactly that when the futures it waits for fail with `Cancelled`.

The override answers for the job that got the observer and for the children
that inherit it, at any depth. The app answers for every job at once in its
zone, where it already reports what nobody caught: the default implementation
brings these errors there. The zone gets the error and its stack trace but not
the job, so a report that names the job takes an override.

An error can reach `onError` and the zone both, and an app that reports in both
places hears it twice. The table shows the way each error takes to the zone:
when nobody observed the outcome, or when nobody answers or `onUnanswered`
sends it on. Observing the outcome closes the first way;
[A failure nobody waits for](outcomes.md#a-failure-nobody-waits-for) on the
outcomes page shows how. An observer that answers closes the second. For the
two failures of a body the table sends to `onUnanswered` — one a cancellation
covered, and one of a branch whose group throws another — `job.ignore()` closes
the second way as well: `onError` hears the failure, and nobody answers for it.

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
after the job finishes: its observer hears them, and they go on to the zone the
job was created in unless the observer answers for them. Without an observer
they go straight there. The job does not wait for the work and does not cancel
it.

Start the work inside the callback and take nothing out of it: the work runs in
an error zone of its own, and the boundary holds both ways. A future made
outside and awaited in there never comes back if it fails, and its error goes
to the zone it was made in. A future made in there and awaited outside hangs
whoever awaits it if it fails; awaited by the body, it hangs the job.

## Several observers

The app hands what nobody answered for to its crash reporter, and the job of
the section above keeps its `Reporter`. `Crashes` answers:

```dart
final class Crashes extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onUnanswered: $error');
}
```

### The first attempt

`observer:` takes one `JobObserver`, so a class hands its hooks on to both:

```dart
final class Both extends JobObserver {
  final _observers = [Reporter(), Crashes()];

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    for (final observer in _observers) {
      observer.onError(job, error, stackTrace);
    }
  }

  // onStart, onFinish and onLog the same way.
}
```

```text
outcome: Done(null)
onError: Bad state: analytics offline
zone: Bad state: analytics offline
```

The lines are those of `Reporter` alone: `Crashes` was never asked. `Both` is
no `JobAnswerer`, so the job asks it for no answer, and the error goes to the
zone. A `Both` that mixes in `JobAnswerer` and hands `onUnanswered` to the ones
of its list that answer goes wrong the other way: with none among them the
error goes nowhere, and with two of them both answer for it.

### Observers in one list

```dart
final job = Job<void>(
  observer: JobObserver.all([Reporter(), Crashes()]),
  (ctx) async {
    ctx.unattended(() => analytics.send('loaded'));
  },
);
```

```text
outcome: Done(null)
onError: Bad state: analytics offline
onUnanswered: Bad state: analytics offline
```

`JobObserver.all` hands every hook to each observer in the order of the list,
each call on its own: one that throws does not switch off the next. The one
that is a `JobAnswerer` watches in its place and answers for the list, once
every observer has heard `onError`; with none, the errors go to the zone, as
for an observer that does not answer. Two that answer, or the same observer
twice, and `JobObserver.all` throws `ArgumentError`. An observer made by
`JobObserver.all` can stand in the list of another, and answers there when one
inside it does.

## Testing

A test checks that cancelling a database open still closes the database once
opening finishes. `package:fake_async` runs timers and microtasks on fake time,
so the test waits for nothing in real time.

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
