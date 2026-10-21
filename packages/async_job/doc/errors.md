# Errors

A `JobObserver` hears the errors that no outcome carries, as
[Observing](observing.md) shows. This page follows an error from the job to
whoever answers for it. An error the job catches passes these places in order
and goes no further than the first one that keeps it. A cancellation the job
catches goes no further than `onError`, unless an engine ends the job `Failed`
with it, as the last row of [Rare routes](#rare-routes) shows.

| Place | What it does with the error | Section |
| --- | --- | --- |
| `onError` | an observer hears it and moves it nowhere | [An observer](#an-observer) |
| The outcome | keeps a failure that a `Failed` carries, once somebody observes that outcome | [An observer](#an-observer) |
| The filter | keeps an error that `Job.isCancellationError` names, once the job has accepted a cancellation | [Errors of a cancellation](#errors-of-a-cancellation) |
| The answer | `onUnanswered` of an observer that mixes in `JobAnswerer` keeps the error, or sends it on to the zone | [Answering for errors](#answering-for-errors) |
| The zone | the zone the job was created in gets the error as an uncaught error there | [Where errors go](#where-errors-go) |

A job without an observer that answers has the zone for its answer.
`ignoreFailure()` on a job keeps the failure of its body right after `onError`,
even when the job ends `Cancelled`, as
[Where each error goes](#where-each-error-goes) shows.

An app that only wants every error reported once starts from the next section,
[Reporting each error once](#reporting-each-error-once).

The lines under the code are what the code prints:

| Line | What it is |
| --- | --- |
| `cancel` | the user cancels the job |
| `outcome:` | what `job.done` completes with |
| `onError:` | an error the observer hears |
| `onUnanswered:` | an error the observer answered for |
| `zone:` | an error that reached the zone uncaught |

## Reporting each error once

An app that reports errors wants each of them once. Two places that do not
overlap take them all: an observer that answers for errors, and the zone the
app runs in.

```dart
final class Reports extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('report: $job: $error');
}
```

```dart
runZonedGuarded(
  startApp,
  (error, stackTrace) => print('report: $error'),
);
```

`startApp` is the function that starts the app, such as
`() => runApp(const App())` in Flutter. Each root job gets
`observer: Reports()`, and its children inherit it. This is who reports what:

| The error | Reported by |
| --- | --- |
| A failure whose outcome nobody observed | `Reports`, which names the job |
| A failure whose outcome somebody observed | nobody: the code that observed it has it |
| A failure of a child that its parent let out of the body | `Reports` once, as the parent's failure, if nobody observed the parent |
| An error no outcome carries, such as one of the body of a cancelled job, of cleanup, of a callback, of an action the job stopped waiting for | `Reports`, which names the job |
| An error the app throws outside its jobs | the zone |

`Reports` answers for every error of a job that nobody else has, so they stop
there and do not reach the zone; the zone gets what the app throws outside its
jobs. The zone does not know a job, so its report does not name one. `onError`
stays out of the report: a failure it hears may be reported as well, and it
hears one failure once on each job whose outcome that failure is.
[An observer](#an-observer) below says when an outcome counts as observed.
[Where each error goes](#where-each-error-goes) and [Rare routes](#rare-routes)
show every way an error takes.

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
send the failure to the answer, and only then. An error it names stops at
`onError` and changes no outcome. A failure of a job that nobody cancelled is
not asked about: a body that throws `DatabaseStopped` while its own job goes on
ends `Failed` with it, and if nobody observes that outcome, it goes on to the
answer. Somebody else cancelled the token then, and the job has to say so.

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

### Where each error goes

The table shows which places of the introduction each error passes, with an
observer and without one. Rarer ways, such as those of `ctx.runAll` and of
engines, are in [Rare routes](#rare-routes) below.

| The error | With an observer | Without one |
| --- | --- | --- |
| The body's, and the job ends `Failed` with it | `onError`, then the answer if nobody observed the outcome | The zone if nobody observed the outcome |
| The body's, and the job ends `Cancelled` | `onError`, then the answer | The zone |
| A late error of an action `ctx.abandonable` stopped waiting for | `onError`, then the answer | The zone |
| An error of cleanup | `onError`, then the answer | The zone |
| An error of a callback of `ctx.onCancel`, `job.whenCancelled` or `job.whenFinished` | `onError`, then the answer | The zone |
| An error of work of `ctx.unattended` | `onError`, then the answer | The zone |

**What keeps an error out of the answer.**

- `ignoreFailure()` on a job stops the failure of its body at `onError`. It
  lets go of that job's failures alone: a child whose body failed answers for
  its failure itself, whatever its parent calls.
- `Job.isCancellationError`, once the job has accepted a cancellation, stops an
  error it names at `onError` wherever the error came from: the body, a step of
  `ctx.uncancellable`, a child the job waited for, cleanup. That holds in the
  rows that end with the answer, in this table and in
  [Rare routes](#rare-routes): those of the body of a cancelled job and those
  from outside the body.
- The outcome keeps only the failure it carries. When the job ends `Cancelled`,
  its outcome carries the cancellation, so the failure of its body goes to
  `onUnanswered` or the zone even when somebody reads `done` or `value`, and so
  does the failure of a branch of `ctx.runAll` whose group threw another error.

**One error, several calls.**

- An app that reports in both `onError` and its zone hears twice an error that
  reaches both. The table shows one way from the job to the zone: the answer,
  when nobody answers for the error, or `onUnanswered` sends it on or throws.
  An engine that ends a job `Failed` on purpose adds a second, past the answer:
  the last row of [Rare routes](#rare-routes).
- One failure that is the outcome of several jobs reaches `onError` once on
  each of them. A child of `ctx.run` fails, its parent lets the failure out of
  its body, and the observer the child inherited hears the same object on the
  child and then on the parent. A branch of `ctx.runAll` and its parent do the
  same, and so do a source and its continuation of `then` given one observer.
- An observer that counts failures tells the second call from a new error by
  `identical`, and an `Expando` remembers the errors it has heard without
  keeping them alive. An error thrown as a constant, such as
  `throw const SignedOut()`, is the same object at every throw, and two such
  failures count as one. An `Expando` takes no string, number, boolean or
  record and throws when given one: such a value has no identity of its own to
  tell two calls apart, and the observer counts it at every call.

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

A failure the outcome carries goes on to the answer a microtask after the job
ends, unless somebody has observed the outcome by then, and an observer that
answers gets it in `onUnanswered`. The outcome counts as observed when somebody
reads `done` or `value`, calls `ignoreFailure()`, or forwards the failure
through `then`: a continuation cancelled before its source failed forwards
nothing, and the failure stays unobserved. See
[A failure nobody waits for](outcomes.md#a-failure-nobody-waits-for) on the
outcomes page. The observer's hooks do not observe the outcome, even a hook
that reads `job.outcome`, as the `onFinish` of `Log` in
[Observer](observing.md#observer) does.

### The debug channel

While debugging, you can see the errors a job hands to its observer without
writing an observer. The app switches the debug channel on in `main`:

```dart
Job.debug = print;
```

The channel prints the start, the cancellation and the end of every job. It
also prints each error the job hands to its observer, whether the job has an
observer or not, and says so when the error goes on to the zone. The first
attempt above, under the channel:

```text
Job() started
cancel
cancel Job(): Cancelled(manual)
Job() error: DatabaseStopped
Job() finished: Cancelled(manual)
Job() error nobody answered for: DatabaseStopped
Job() error went to the zone: DatabaseStopped
zone: DatabaseStopped
outcome: Cancelled(manual)
```

The lines that start with `Job()` and the line `cancel Job()` are the
channel's. With the filter, the three lines after `Job() finished` give way to
one: `Job() kept a cancellation error out of the answer: DatabaseStopped`. The
filter is one for the whole app, and the channel is where you see why an error
never reached the zone.

A `ParallelWaitError` takes one line of the channel, whole, where `onError`
hears each failure inside it on its own. The channel is one for all the jobs of
the app and speaks to whoever reads the console. The app hears what it has to
act on through an observer.

## Work the job does not wait for

A job sends an analytics event and does not wait for it. The sending fails:
analytics is offline. The job has the `Reporter` from
[An observer](#an-observer).

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

The errors that no outcome carries go on from `onError` to an answer, and so do
the failures whose outcome nobody observes. An observer written only to watch,
like `Reporter`, gives no answer, so these errors go to the zone. An observer
that answers for them itself mixes in `JobAnswerer` and overrides
`onUnanswered`:

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

The override answers for the job that got the observer, and for the children
that inherit it, at any depth. To answer for every job at once, the app uses
its zone, where it already reports what nobody caught: the default
implementation brings these errors there. The zone gets the error and its stack
trace but not the job, so a report that names the job needs an override.

An override that throws does not take the error with it. The error goes to the
zone the job was created in, and then what the override threw goes to the
current zone, as from any hook; a `Cancelled` it throws stays out, and so does
the error itself thrown back, so the error goes there once. An override that
reported the error before it threw has it reported twice: to its own system and
to the zone.

### Several failures in one error

A job hands `ctx.unattended` two operations awaited together. `saveDraft` fails
with a `DatabaseException`, and `sendAnalytics` fails with a `StateError`.
`[saveDraft(), sendAnalytics()].wait` throws a `ParallelWaitError` that holds
both failures:

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
the analytics error on its own. A `Failed` with such an error that nobody
observes is answered for the same way, failure by failure. Nobody is asked
about an uncaught `Cancelled`, alone or inside a `ParallelWaitError`: a
cancellation is no failure. Nor is anybody asked, once the job has accepted a
cancellation, about an error `Job.isCancellationError` names.

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

## Rare cases

Here are the limits of the filter and the rarer routes an error takes,
including the errors Dart hands to the zone past the job.

### Limits of the filter

- An error that the body makes of its own cancellation reaches the filter too,
  but the type test of [Errors of a cancellation](#errors-of-a-cancellation)
  does not know it. A body that catches everything around `ctx.abandonable` and
  throws an error of its own in its place, such as `throw AppException(error)`,
  wraps each `Cancelled` in an `AppException`, and the zone hears it at each
  cancellation. The filter names the wrapper by its cause:

```dart
Job.isCancellationError =
    (error) => error is AppException && error.cause is Cancelled;
```

- The `catch` can call `ctx.check()` first instead, as in
  [Asking the job](cancellation.md#asking-the-job) on the cancellation page:
  then the cancellation itself goes out, and a cancellation is no failure. That
  costs more than the filter: once the job has accepted a cancellation,
  `ctx.check()` throws it whatever the `catch` took. A body that waits with
  `ctx.join` loses that way a real failure that reaches the `catch` after the
  cancellation, such as an open that found the database locked: neither
  `onError` nor the zone hears it. The filter keeps out only the errors it
  names.
- The filter only keeps errors out of the answer, and `ctx.runAll` shows it. A
  branch cancelled from outside whose body throws an error of a cancellation
  has failed as far as the group can tell. So the group cancels the other
  branches with a `SiblingCancelReason` whose cause is that error. A branch
  nobody cancelled that ends `Failed` with such an error is a failure like any
  other. The group throws it in place of a cancellation of another branch, and
  the body of the parent gets that error, not `Cancelled`.

### Rare routes

These are the ways of a branch of `ctx.runAll`, of the name of a child, of a
`Cancelled` and of an engine.

| The error | With an observer | Without one |
| --- | --- | --- |
| The body's, in a branch of `ctx.runAll` whose group throws another failure | `onError`, then the answer | The zone |
| An error of the `toString` of a child's `key`, its `describe` or its `Cancelled`, when the core names the child in the parent's cancellation | `onError`, then the answer | The zone |
| A `Cancelled` thrown outside the body | `onError` | Nobody |
| The job's own cancellation, out of an action `ctx.abandonable` stopped waiting for or out of work of `ctx.unattended` | Nobody | Nobody |
| The failure of a job an engine ends `Failed` with a `Cancelled`, or with a `ParallelWaitError` of nothing but cancellations, to make it fail on purpose | `onError`, then the zone past the answer if nobody observed the outcome | The zone if nobody observed the outcome |

**What Dart hands to the zone past the job.** A context call the body does not
await throws into a future that nobody awaits. Dart, not the job, hands that
error to the zone the body runs in.

- The error of such a call goes there with an observer or without one. For a
  job made with `Job.deferred`, the zone the body runs in is the zone it was
  started from.
- While the body runs, a cancellation of the job makes a `ctx.abandonable`
  called without `await` throw `Cancelled` into its future, and Dart hands the
  job's own cancellation to that zone like any other error.
- `ctx.abandonable` is the one exception once the body has ended: an action
  that fails then takes the way of the late error in
  [Where each error goes](#where-each-error-goes), to `onError` and on to the
  answer. A call of `ctx.abandonable` without `await` reaches the zone the body
  runs in, with its error or with the job's cancellation, only while the body
  runs.

The filter sees none of the errors Dart hands to the zone, and the error of an
`async` callback of `ctx.onCancel` is one of them, as
[A stop that takes time](cancellation.md#a-stop-that-takes-time) shows.
