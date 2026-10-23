# Errors

A `JobObserver` hears the errors that no outcome carries, as
[Observing](observing.md) shows. This page follows an error from the job to
whoever answers for it. An error the job catches passes these places in order
and goes no further than the first one that keeps it. A cancellation the job
catches goes no further than `onError`, unless an engine ends the job `Failed`
with it, as the last row of [Rare routes](error-rules.md#rare-routes) shows.

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
[Where each error goes](error-rules.md#where-each-error-goes) shows.

An app that only wants every error reported once starts from the next section,
[Reporting each error once](#reporting-each-error-once).
[Error rules](error-rules.md) goes on from this page: the way each kind of
error takes, the debug channel, an error that holds several failures, and the
rare cases.

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
[Where each error goes](error-rules.md#where-each-error-goes) and
[Rare routes](error-rules.md#rare-routes) on the error rules page show every
way an error takes.

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
zone the work was started from. It has an outcome and an observer of its own,
and its unobserved failure goes to the answer of its own observer, or to that
zone, rather than to the observer of this job. For work inside the work of
another job, that is the zone the outer work was started from.

`ctx.abandonable` and `ctx.join` work inside the callback on the body's terms,
even after the body has ended. On a job that has accepted a cancellation, the
value is released and the call throws the cancellation. On a job that is over,
a value with a `dispose` or `discard` is released, and the call throws a
`StateError` instead of handing it over closed.

Polling `ctx.check()` is no way to stop such work with the job. On a job nobody
cancelled, it throws a `StateError` while the core unwinds the cleanup stack,
and once the job has ended `Done` it does not throw at all, so a loop waiting
for it holds the job forever. Ask `job.isFinished`, or wait for `job.done`.

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

An error that holds several failures, such as a `ParallelWaitError`, is
answered for failure by failure: see
[Several failures in one error](error-rules.md#several-failures-in-one-error)
on the error rules page.

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
