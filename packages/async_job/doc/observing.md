# Observing and testing

A job's outcome says how the job ended. A `JobObserver` hears the rest: when
the job starts and ends, what its body logs, and the errors that no outcome
carries. The last section shows how to test a job without waiting in real time.

The lines under the code are what the code prints:

- `cancel`: the user cancels the job;
- `outcome:` what `job.done` completes with;
- `onError:` an error the observer hears;
- `onUnanswered:` an error the observer answered for;
- `zone:` an error that reached the zone uncaught.

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
    return ctx.abandonable(load);
  },
);
```

```text
Job(load): loading
Job(load): Done(3)
```

A `JobObserver` has four hooks: `onStart`, `onFinish`, `onError` and `onLog`.
The job calls the first three itself. The body sends messages to `onLog` with
`ctx.log(message)`. `onFinish` runs for every job, even one cancelled before it
started. `onStart` runs only for a job that starts.

The hooks do nothing by default, so an observer overrides only the hooks it
needs. An observer that also answers for errors mixes in `JobAnswerer`, which
adds a fifth hook, `onUnanswered`; see
[Answering for errors](#answering-for-errors) below. A class that already
extends another class mixes the observer in with `with JobObserver`, or
`with JobObserver, JobAnswerer`, and overrides the hooks the same way.

Whoever runs the job passes the observer when creating it. The children the job
runs inherit it unless they have their own. A continuation made with `then`
takes only the observer passed to `then`.

If a hook throws, its error goes to the current zone, and nothing else changes:
the job ends as it would have, and the other hooks are still called. A
`Cancelled` thrown by a hook does not reach the zone and does not cancel the
job. To cancel the job from a hook, call `job.cancel()`; the job is cancelled
as it would be from anywhere else.

When you create a job, you can give it a `key` and a `describe` callback. A
job's string form is:

- `Job($key)` with a key;
- `Job($key: $description)` with a key and a `describe` that returns a
  description that is not empty;
- `Job($description)` with such a description and no key;
- `Job()` with neither.

Use `key` to identify the job in logs or in the scheduling rules of a library,
such as the queue policies of `solo`. `describe` adds details to it.

A `key` whose `toString` throws, or a `describe` that throws, prints as a mark
in its place: `Job(load: <describe threw StateError>)`. The core names jobs in
its own error messages, and a broken name does not replace the message. The
error of the name itself is still reported, in two places. When the core names
a child in its parent's cancellation, the error goes as row 4 of the table
below says. When a line of the debug channel names the job, the error goes to
the zone.

A cancelled job should end soon. One that goes on is busy with work the user
has already given up on. An observer finds such jobs by timing how long each
one runs past its cancellation:

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
cancellation. `onFinish` runs when the outcome arrives. The time between them
is how long the job ran past its cancellation, children and cleanup included.
Three things decide the count:

- A body that waits on something slow with a bare `await` adds the rest of that
  wait to the count. The same call through `ctx.abandonable` shows 0 ms.
- The count starts when the job accepts the cancellation, not at `cancel()`.
  `ctx.uncancellable` holds a cancellation back, and the job accepts it when
  the section ends: a 100 ms section cancelled 10 ms in shows 0 ms, while the
  caller of `cancel` waited 90 ms.
- A body that gives itself up, by throwing `Cancelled` or by letting a child's
  cancellation out, accepts the cancellation as it throws, and the count starts
  there.

## A message for the log

A body migrates the database. When the migration fails, it logs the `error` it
caught. Someone debugging the app gives the job an observer. A release build
gives it none, and there the message should cost nothing.

### The first attempt

`log` takes a message, and a string is one:

```dart
// The first attempt: the string is built for nobody.
ctx.log('migration failed: $error');
```

Without an observer, `ctx.log` does nothing, but the string is already built:
Dart evaluates the argument before the call, so `error.toString()` runs for
nobody.

### Formatting left to the observer

```dart
ctx.log(() => 'migration failed: $error');
```

A callback puts off building the message. `ctx.log` passes the callback on
unchanged, like any other object, so without an observer nothing is built. With
an observer, calling the callback is that observer's convention: the `Log`
above calls a callback and prints what it returns, while an observer that
prints each message as it came would print the closure itself. Passing `error`
alone also leaves the formatting to the observer, and needs no convention.

## Where errors go

The app reports every error that reaches its zone uncaught. A job migrates the
database, and a cancellation stops the migration at its token, as in
[A token through `onCancel`](cancellation.md#a-token-through-oncancel) on the
cancellation page. The user cancels while the migration runs.

### The first attempt

Dart sends an error that nobody caught to the zone, so the app relies on the
zone, gives the job no observer and wires the token as the cancellation page
does:

```dart
// The first attempt: every cancellation reaches the zone as a failure.
final job = Job<void>((ctx) async {
  final stop = CancelToken();
  ctx.onCancel(stop.cancel);

  await ctx.join(() => database.migrate(stop));
});
```

```text
cancel
zone: DatabaseStopped
outcome: Cancelled(manual)
```

Nothing failed, and yet the zone reports a failure each time the user cancels.
This is what happens:

1. The job accepts the cancellation, and `onCancel` cancels the token. From
   then on the job will end `Cancelled`, whatever the migration does.
2. The migration stops at the token and throws its own `DatabaseStopped`, and
   `join` throws it as it is. The body fails with that error on a job that is
   already cancelled.
3. That error is not the outcome: the outcome carries the cancellation. The job
   answers for it as for any failure of its body that no outcome carries: the
   `onError` of an observer would hear it, and then it goes to the answer,
   which without an observer is the zone.

The job cannot tell what such an error is. Here it is the operation stopping at
the job's token. But a real failure after a cancellation goes the same way, and
that one has to be heard: if the database turns out to be locked after the user
cancelled, the app should learn of it.

### Errors of a cancellation

An error of a cancellation is one that an operation throws because the
cancellation of its job stopped it: the `DatabaseStopped` of a token that
`ctx.onCancel` cancelled, or a `DioException` of `dio` for which
`CancelToken.isCancel` holds. The app names such errors once, in `main`:

```dart
Job.isCancellationError = (error) => error is DatabaseStopped;
```

```text
cancel
outcome: Cancelled(manual)
```

The job stays as it was. `Job.isCancellationError` is asked about each failure
of a job that has accepted a cancellation. It is asked when the job is about to
send the failure to the answer, and only then. An error it names still reaches
`onError` and goes no further: neither `onUnanswered` nor the zone hears it.
The filter changes no outcome either. A failure of a job that nobody cancelled
is not asked about: a body that throws `DatabaseStopped` while its own job goes
on ends `Failed` with it, and if nobody observes that outcome, it reaches the
zone. Somebody else cancelled the token then, and the job has to say so.

The filter is called synchronously, with one failure at a time and never with a
`Cancelled`, so keep it to a type test. The job walks a `ParallelWaitError` and
asks about each failure inside it on its own. A filter that throws is an error
of the app: it goes to the zone the job was created in, and the failure it was
asked about goes on to the answer.

The field belongs to the app, like `Job.debug`, and a library does not set it.
Where two parts of the app name errors of their own, the second chains the
first:

```dart
final previous = Job.isCancellationError;
Job.isCancellationError =
    (error) => error is DatabaseStopped || (previous?.call(error) ?? false);
```

A test that sets the field puts it back in `tearDown`, as it would `Job.debug`.

The filter does not see an error that Dart hands to the zone itself, past the
job: that of a context call the body did not await, such as
`unawaited(ctx.join(() => database.migrate(stop)))`, and that of an `async`
callback of `ctx.onCancel`. Row 7 of the table below and
[A token through `onCancel`](cancellation.md#a-token-through-oncancel) take
these apart.

An error that the body makes of its own cancellation reaches the filter too,
but the type test above does not know it. A body that catches everything around
`ctx.abandonable` and throws an error of its own in its place, such as
`throw AppException(error)`, wraps each `Cancelled` in an `AppException`, and
the zone hears it at each cancellation. The filter names the wrapper by its
cause: `(error) => error is AppException && error.cause is Cancelled`.

The `catch` can call `ctx.check()` first instead, as in
[Asking the job](cancellation.md#asking-the-job) on the cancellation page: then
the cancellation itself goes out, and a cancellation is no failure. That costs
more than the filter. Once the job has accepted a cancellation, `ctx.check()`
throws it whatever the `catch` took. A body that waits with `ctx.join` loses
that way a real failure that reaches the `catch` after the cancellation, such
as an open that found the database locked: neither `onError` nor the zone hears
it. The filter keeps out only the errors it names.

The filter only keeps errors out of the answer, and `ctx.runAll` shows it. A
branch cancelled from outside whose body throws an error of a cancellation has
failed as far as the group can tell, so the group cancels the other branches
with a `SiblingCancelReason` whose cause is that error. A branch nobody
cancelled that ends `Failed` with such an error is a failure like any other,
and the group throws it in place of a cancellation of another branch: the body
of the parent gets that error, not `Cancelled`.

### An observer

The app also wants to see the errors of its jobs as they happen. A job opens
the database, the user cancels while it opens, and then the open fails: the
database is locked.

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
zone: Bad state: database locked
outcome: Cancelled(manual)
```

An observer hears through `onError` the errors its job catches, except its own
cancellation. It only hears them: overriding `onError` moves no error anywhere.
The failed open still reaches the zone, as it would without the observer: the
job ends `Cancelled`, and the filter above does not name a `StateError`.

The outcome counts as observed when somebody reads `done` or `value`, calls
`ignoreFailure()`, or forwards the failure through `then`: a continuation
cancelled before its source failed forwards nothing, and the failure stays
unobserved. See
[A failure nobody waits for](outcomes.md#a-failure-nobody-waits-for) on the
outcomes page. The observer's hooks do not observe the outcome, even a hook
that reads `job.outcome`, as the `onFinish` of `Log` above does.

The table shows where each error goes, with an observer and without one. "The
zone" is the zone the job was created in. "The answer" is `onUnanswered` if the
observer answers for errors, and the zone if it does not.

| The error | With an observer | Without one |
| --- | --- | --- |
| 1. The body's, and the job ends `Failed` with it | `onError`, and the zone if nobody observed the outcome | The zone if nobody observed the outcome |
| 2. The body's, and the job ends `Cancelled` | `onError`, then the answer | The zone |
| 3. The body's, in a branch of `ctx.runAll` whose group throws another failure | `onError`, then the answer | The zone |
| 4. From outside the body, in the places listed below | `onError`, then the answer | The zone |
| 5. A `Cancelled` thrown outside the body | `onError` | Nobody |
| 6. The job's own cancellation, out of an action `ctx.abandonable` stopped waiting for or out of work of `ctx.unattended` | Nobody | Nobody |
| 7. From a context call the body did not await (see below) | The zone the body runs in | The zone the body runs in |

Rows 4 and 7 cover only these cases:

- Row 4: a late error of an action `ctx.abandonable` stopped waiting for;
  cleanup; a callback of `ctx.onCancel`, `job.whenCancelled` or
  `job.whenFinished`; work of `ctx.unattended`; the `toString` of a child's
  `key`, its `describe` or its `Cancelled` when the core names the child in the
  parent's cancellation.
- Row 7: the error goes to the zone the body runs in, as with any future nobody
  awaits. This includes the job's own cancellation. For `ctx.abandonable`, it
  holds only until the body ends.

An error that `Job.isCancellationError` names goes no further than `onError` in
rows 2 and 4 once the job has accepted a cancellation, wherever it came from:
the body, a step of `ctx.uncancellable`, a child the job waited for, cleanup.

A context call the body did not await throws into a future that nobody awaits.
Dart hands that error to the zone the body runs in; for a job made with
`Job.deferred`, that is the zone it was started from. The job's own
cancellation goes there too: when the job is cancelled, `ctx.abandonable`
called without `await` throws `Cancelled` into its future, and Dart hands it to
the zone like any other error. It is Dart that sends this cancellation to the
zone, not the job.

For `ctx.abandonable` called without `await`, this holds only while the body
runs. If its action fails after the body has ended, the error takes row 4 of
the table, like the error of an action `ctx.abandonable` stopped waiting for on
a cancellation: `onError` hears it, and then it goes where the other errors
from outside the body go.

An error can reach both `onError` and the zone, and an app that reports in both
places hears it twice. The table shows two ways to the zone. The first: nobody
observed the outcome. The second: nobody answers for the error, or
`onUnanswered` sends it on. Observing the outcome closes the first way. An
observer that answers (`with JobAnswerer`) closes the second.

Two kinds of body failure are not carried by the outcome, and they go to
`onUnanswered` or the zone even when the outcome is observed: the job ends
`Cancelled`, and the outcome carries the cancellation (row 2); or a branch of
`ctx.runAll` failed and its group threw another error (row 3).
`ignoreFailure()` on the job whose body failed lets such a failure go:
`onError` still hears it, but it reaches neither `onUnanswered` nor the zone.
`ignoreFailure()` lets go of that job's failures alone: a child whose body
failed answers for its failure itself, whatever its parent calls.

While debugging, you can see the errors a job hands to its observer without
writing an observer: the debug channel shows them. `Job.debug = print;` prints
the start, the cancellation and the end of every job. It also prints each such
error, whether the job has an observer or not, and says so when the error goes
on to the zone. A `ParallelWaitError` takes one line, whole, where `onError`
hears each failure inside it on its own. For the first attempt above, the
channel prints `Job() error: DatabaseStopped` after the cancellation and before
the end, and after the end that the error went to the zone. With the filter, it
prints `Job() kept a cancellation error out of the answer: DatabaseStopped` in
place of the zone: the filter is one for the whole app, and the channel is
where you see why an error never reached the zone. The channel is one for all
the jobs of the app and speaks to whoever reads the console. The app hears what
it has to act on through an observer.

## Work the job does not wait for

A job sends an analytics event and does not wait for it. The sending fails:
analytics is offline. The job has the `Reporter` from the section above.

### The first attempt

Dart's `unawaited` marks a future that is left unawaited on purpose:

```dart
// The first attempt: the error goes to the zone, not to the job.
unawaited(analytics.send('loaded'));
```

```text
outcome: Done(null)
zone: Bad state: analytics offline
```

The observer hears nothing, and nothing ties the error to the job. A future
that nobody awaits hands its error to the zone as uncaught. `unawaited` only
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

`ctx.unattended(action)` keeps the errors of the work with the job, including
errors that come after the job finishes. The observer hears them, and then they
go on to the zone the job was created in, unless the observer answers for them.
Without an observer they go straight there. The job does not wait for the work
and does not cancel it.

Start the work inside the callback, and take nothing out of it. The work runs
in an error zone of its own, and the boundary holds both ways:

- A future made outside and awaited inside never comes back if it fails, and
  its error goes to the zone it was made in.
- A future made inside and awaited outside hangs whoever awaits it if it fails.
  If the body awaits it, the job hangs.

A job started inside the callback is outside the boundary: its body runs in the
zone the work was started from.

## Answering for errors

The errors that no outcome carries go on from `onError` to an answer. An
observer written only to watch, like `Reporter`, gives no answer, so these
errors go where they would go without an observer: to the zone. Watching alone
does not change where an error goes. An observer that answers for these errors
itself mixes in `JobAnswerer` and overrides `onUnanswered`:

```dart
final class Answering extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onUnanswered: $error');
}
```

The errors stop there and do not reach the zone. The default `onUnanswered`
sends them to the zone the job was created in, as happens without an answer. So
calling `super.onUnanswered(job, error, stackTrace)` sends an error on to the
zone as well. An observer that answers only for the database errors it knows
hands the rest to `super`:

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

The job hands `ctx.unattended` two operations awaited together. `saveDraft`
fails with a `DatabaseException`, and `sendAnalytics` fails with a
`StateError`. `[saveDraft(), sendAnalytics()].wait` throws a
`ParallelWaitError` that holds both failures:

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
onUnanswered: DatabaseException
zone: Bad state: analytics offline
```

`onUnanswered` is asked about one failure at a time. The job walks a
`ParallelWaitError` and asks about each failure inside it, with that failure's
stack trace. So the observer answers for the database error, and the zone hears
the analytics error on its own. An uncaught `Cancelled` is not a failure, and
nobody is asked about it, whether it comes alone or inside a
`ParallelWaitError`. Nor is anybody asked about an error that the app named in
[Errors of a cancellation](#errors-of-a-cancellation), once the job has
accepted a cancellation.

`onError` also hears them one at a time, and hears a `Cancelled` inside a
`ParallelWaitError` in a call of its own. The outcome keeps the error as it was
thrown: a body that fails with a `ParallelWaitError` ends `Failed` with that
error. `Job.visitErrors` does the same walk for whoever reads the outcome:

```dart
final outcome = await job.done;
if (outcome case Failed(:final error, :final stackTrace)) {
  Job.visitErrors(
    error,
    stackTrace,
    onFailure: (failure, failureStackTrace) => print('failed: $failure'),
  );
}
```

The override answers for the job that got the observer, and for the children
that inherit it, at any depth. To answer for every job at once, the app uses
its zone, where it already reports what nobody caught: the default
implementation brings these errors there. The zone gets the error and its stack
trace but not the job, so a report that names the job needs an override.

## Several observers

The app sends whatever nobody answered for to its crash reporter. The job from
[Work the job does not wait for](#work-the-job-does-not-wait-for) keeps its
`Reporter` as well. `Crashes` is the observer that answers:

```dart
final class Crashes extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onUnanswered: $error');
}
```

### The first attempt

`observer:` takes one `JobObserver`, so a class hands its hooks on to both, and
its answer on to `Crashes`:

```dart
// The first attempt: every hook handed on by hand, with no try/catch.
final class Both extends JobObserver with JobAnswerer {
  final _reporter = Reporter();
  final _crashes = Crashes();

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    _reporter.onError(job, error, stackTrace);
    _crashes.onError(job, error, stackTrace);
  }

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _crashes.onUnanswered(job, error, stackTrace);

  // onStart, onFinish and onLog the same way as onError.
}
```

```text
outcome: Done(null)
onError: Bad state: analytics offline
onUnanswered: Bad state: analytics offline
```

It works: `Reporter` hears the error, and `Crashes` answers for it. But each
hook is handed on by hand: five methods for two observers, and a third observer
adds a line to each. To be complete, each call also needs a `try`/`catch`;
otherwise an observer that throws switches off the ones after it.

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

`JobObserver.all` hands every hook to each observer, in the order of the list,
each call on its own: an observer that throws does not switch off the next one.
The observer that is a `JobAnswerer` watches at its place in the list too, and
answers for the whole list once every observer has heard `onError`. With no
`JobAnswerer` in the list, the errors go to the zone, as for an observer that
does not answer. Two observers that answer, or the same observer twice, make
`JobObserver.all` throw `ArgumentError`. An observer made by `JobObserver.all`
can stand in the list of another, and answers there when one inside it does.

## Testing

A test checks that cancelling a database open still closes the database once
the open finishes. `package:fake_async` runs timers and microtasks on fake
time, so the test waits for nothing in real time.

### The first attempt

`cancel()` returns a future that completes when the job is over, so the test
awaits it:

```dart
// The first attempt: neither expect runs.
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

The test passes, and it would pass with `expect(closed, 0)` too: neither
`expect` runs. Under `fakeAsync`, time moves only when the test moves it. The
callback returns at its first `await`, and `fakeAsync` returns with it. Nothing
moves the time again, so the future of `cancel()` never completes. Written as
`() => fakeAsync(...)`, the test would wait for that future instead and fail on
its timeout.

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

Nothing inside `fakeAsync` awaits. The future of `cancel()` is ignored,
`flushTimers()` runs the open to its end, and the checks see what happened.
`flushMicrotasks()` is enough to start a job, since its body starts in a
microtask. Operations scheduled with `Future(...)` or `Future.delayed(...)` use
timers, so advance them with `flushTimers()` or `elapse(...)`.
