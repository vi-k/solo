# Error rules

[Errors](errors.md) follows an error from the job to whoever answers for it.
This page gives the rules of that way: which places each kind of error passes,
the debug channel that shows them, an error that holds several failures, and
the rare cases. Its code goes on from that page: the migration of
[Where errors go](errors.md#where-errors-go), stopped at its token while the
user cancels, the filter of
[Errors of a cancellation](errors.md#errors-of-a-cancellation), and the
`DatabaseErrors` observer of
[Answering for errors](errors.md#answering-for-errors).

The lines under the code are what the code prints:

| Line | What it is |
| --- | --- |
| `cancel` | the user cancels the job |
| `outcome:` | what `job.done` completes with |
| `onUnanswered:` | an error the observer answered for |
| `zone:` | an error that reached the zone uncaught |

## Where each error goes

The table shows which places of the introduction of [Errors](errors.md) each
error passes, with an observer and without one. The answer is `onUnanswered` of
an observer that mixes in `JobAnswerer`; a job without such an observer has the
zone for its answer. Rarer ways, such as those of `ctx.runAll` and of engines,
are in [Rare routes](#rare-routes) below.

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

## The debug channel

While debugging, you can see the errors a job hands to its observer without
writing an observer. The app switches the debug channel on in `main`:

```dart
Job.debug = print;
```

The channel prints the start, the cancellation and the end of every job. It
also prints each error the job hands to its observer, whether the job has an
observer or not, and says so when the error goes on to the zone. The first
attempt of [Where errors go](errors.md#where-errors-go), under the channel:

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

## Several failures in one error

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

`Job.visitErrors` hands a `Cancelled` to `onCancelled` and any other error to
`onFailure`. It walks a `ParallelWaitError` depth first, its branches in order,
each with its own stack trace, and skips a `null` branch, which succeeded.
Nothing is lost: what the walk cannot read goes to `onFailure` whole, with the
stack trace of the error around it, and so does an error with neither a failure
nor a cancellation in it. Each `ParallelWaitError` is walked once and handed
over whole at most once, however many branches lead to it.

## Rare cases

Here are the limits of the filter and the rarer routes an error takes,
including the errors Dart hands to the zone past the job.

### Limits of the filter

- An error that the body makes of its own cancellation reaches the filter too,
  but the type test of
  [Errors of a cancellation](errors.md#errors-of-a-cancellation) does not know
  it. A body that catches everything around `ctx.abandonable` and throws an
  error of its own in its place, such as `throw AppException(error)`, wraps
  each `Cancelled` in an `AppException`, and the zone hears it at each
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
