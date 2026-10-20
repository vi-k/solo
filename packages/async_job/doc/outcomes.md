# Outcomes

Once the body, its children and cleanup have finished, a job has an
`Outcome<T>`: `Done` with the value the body returned, `Failed` with the error
it threw, or `Cancelled`. `job.done` completes with it and never throws,
`job.value` gives the value alone, and `job.outcome` holds it once the job is
over, `null` before that. `Outcome<T>` is sealed, so a `switch` covering these
three cases is exhaustive.

The lines under the code are what it prints when it runs, and `zone:` is an
error that reached the zone uncaught.

## Reading the result

`report` is a `Job<Report>` the user can cancel. When it is over, the code that
started it prints one of three things: the report, the error the job failed
with, or that it was cancelled.

### The first attempt

`value` is the report, and a `try` takes what goes wrong:

```dart
// The first attempt: the catch takes a cancellation for a failure.
try {
  print('report: ${await report.value}');
} on Object catch (error) {
  print('failed: $error');
}
```

The user cancels, and the cancellation is printed as a failure:

```text
failed: Cancelled(manual)
```

`value` completes with the value on success and throws on failure or
cancellation, and for a cancellation it throws the `Cancelled` itself.
`Cancelled` implements `Exception`, so a `catch` takes it along with the
errors, `on Exception` as well as `on Object`.

### A switch over `done`

```dart
final message = switch (await report.done) {
  Done(:final value) => 'report: $value',
  Failed(:final error) => 'failed: $error',
  Cancelled(:final reason) => 'cancelled: $reason',
};
print(message);
```

```text
cancelled: manual
```

`done` hands the outcome over instead of throwing it, and each case gets its
own line. `value` fits code for which a cancellation is a failure like any
other, such as a test that expects the value. If you do not need the result at
all, call `report.ignoreFailure()` to acknowledge that choice.

## A failure nobody waits for

`backup` uploads in the background, and nothing awaits it. A status line reads
how it went whenever the line is drawn.

### The first attempt

`outcome` is how the job went, and `null` while it runs:

```dart
// The first attempt: reading outcome leaves the failure to the zone.
final backup = Job<void>(upload);

// Wherever the status line is drawn:
final status = switch (backup.outcome) {
  null => 'backing up',
  Done() => 'backed up',
  Failed(:final error) => 'backup failed: $error',
  Cancelled() => 'backup cancelled',
};
print('status: $status');
```

The upload fails. The zone the job was created in receives the error as an
uncaught one, and the status line drawn after that says the same:

```text
zone: Bad state: disk full
status: backup failed: Bad state: disk full
```

A failure nobody observes is answered for on the microtask after the job
finishes: an observer that mixes in `JobAnswerer` answers in `onUnanswered`,
and without one the job's creation zone receives it, as here. That keeps it
visible when no caller waits for the result. In a test that zone is the test's,
and the test fails. Reading `outcome` does not count as observing. A read that
comes after that microtask still works, `done` with the `Failed` and `value`
with its error, but the failure has been answered for by then.

### Telling the core it is handled

```dart
final backup = Job<void>(upload)..ignoreFailure();
```

```text
status: backup failed: Bad state: disk full
```

`ignoreFailure()` tells the core that the failure is handled elsewhere, here by
the status line, and nothing reaches the zone. `ignoreFailure()` is not the
only way to observe a failure:

| What the code does | Observes the failure? |
| --- | --- |
| Reads `done` | yes, even without awaiting it, and `done` never throws |
| Reads `value` | yes, even without awaiting it, and the waiting code gets the error itself and has to handle it, as with any `Future` |
| Reads `done` or `value` after the microtask that follows the end | too late: the failure has been answered for |
| Forwards the failure through `then` | yes, and the continuation takes responsibility for it |
| Reads `outcome` | no |
| Awaits `job.cancel()` | no |
| Registers a listener with `whenCancelled` or `whenFinished` | no |
| Gives the job an observer | no: `onError` and `onFinish` hear the failure, and it is answered for all the same — by the observer's `onUnanswered` if it mixes in `JobAnswerer` |

So code that waits for the job and handles its result needs no
`ignoreFailure()`.

Waiting does not observe the failure of the body of a job that ends
`Cancelled`. If `backup` is cancelled and its body fails, the code waiting for
it gets the cancellation, not the error, and the status line says
`backup cancelled`. The error goes the way of an error no outcome carries.
[Where errors go](errors.md#where-errors-go) on the errors page shows that way.
`ignoreFailure()` keeps it from being answered for, and then only an observer's
`onError` hears it.

### Hearing the end without the failure

```dart
// Runs when the backup is over, and does not observe its failure.
final unregister = backup.whenFinished((outcome) {
  print('status redrawn: $outcome');
});
```

```text
status redrawn: Failed(Bad state: disk full)
zone: Bad state: disk full
```

A status line that waits for `done` to redraw itself observes the failure, and
the zone stops hearing about it, even when the line is not the code responsible
for the backup. `whenFinished` calls its listener with the outcome once the job
is over: after its cleanup, and before anything waiting on `done` resumes.
Registering observes nothing: the failure is answered for as in the first
attempt, and the owner of `backup` keeps the choice of who observes it. A
screen that closes before the job ends calls `unregister()`; a listener
registered on a job that is already over runs at once.

## Why a job was cancelled

For a cancelled job, the outcome also explains why it stopped: `Cancelled`
holds a `reason`. A reason of your own can carry data, such as an error and its
original stack trace:

```dart
final class RequestCancelReason extends CancelReason {
  final Object error;
  final StackTrace stackTrace;

  const RequestCancelReason(this.error, this.stackTrace);

  @override
  String get name => 'request';
}
```

`report` runs a child, `fetch`, for its data, and catches nothing that comes
out of it:

```dart
final fetch = Job.deferred<Data>(download);
final report = Job<Report>((ctx) async {
  final data = await ctx.run(fetch);
  return Report(data);
});
```

`fetch` needs a token that a request elsewhere refreshes. When that request
fails, the code that sent it cancels `fetch` and passes the error in the
reason, and the outcome of `fetch` holds the very same reason:

```dart
try {
  await refreshToken();
} on Object catch (error, stackTrace) {
  await fetch.cancel(reason: RequestCancelReason(error, stackTrace));
}
```

The code that started `report` should tell a failed request from a cancellation
by the user.

### The first attempt

The `switch` over `done` gets a case for the reason:

```dart
// The first attempt: the reason of the request is one cause further down.
final message = switch (await report.done) {
  Done(:final value) => 'report: $value',
  Failed(:final error) => 'failed: $error',
  Cancelled(reason: RequestCancelReason(:final error)) =>
    'request failed: $error',
  Cancelled(:final reason) => 'cancelled: $reason',
};
print(message);
```

```text
cancelled: handler
```

The request cancelled `fetch`, not `report`. The cancellation of `fetch`
escaped through the body of `report`, and `report` ended with a `Cancelled` of
its own, whose reason is `HandlerCancelReason`: its body cancelled itself. The
`RequestCancelReason` is one step down, in the `cause` of that reason.

### Following the cause

```dart
CancelReason origin(Cancelled cancelled) => switch (cancelled.reason) {
      HandlerCancelReason(:final cause?) ||
      ParentCancelReason(:final cause?) ||
      ChainCancelReason(:final cause) =>
        origin(cause),
      final reason => reason,
    };

final message = switch (await report.done) {
  Done(:final value) => 'report: $value',
  Failed(:final error) => 'failed: $error',
  final Cancelled cancelled => switch (origin(cancelled)) {
      RequestCancelReason(:final error) => 'request failed: $error',
      final reason => 'cancelled: $reason',
    },
};
print(message);
```

```text
request failed: Bad state: token expired
```

Four reasons have a `cause`:

| Reason | Who gets it, and when | `cause` holds | Does `origin` follow it? |
| --- | --- | --- | --- |
| `ParentCancelReason` | a child, when its parent's cancellation cascades to it | the parent's `Cancelled` | yes |
| `HandlerCancelReason` | a parent, when a child's cancellation escapes through its body | the child's `Cancelled` | yes |
| `ChainCancelReason` | a job in a chain of `then`, when a neighbour's cancellation is forwarded to it | the neighbour's `Cancelled` | yes |
| `SiblingCancelReason` | a branch of `ctx.runAll`, when the group fails and stops the other branches | what the group stopped for: the error or the cancellation another branch ended with, or an error of the group itself | no, `origin` returns the `SiblingCancelReason` itself |

The three links `origin` follows preserve the original reason and its data, and
it follows them to the end: `cause` is `null` where nothing stands behind the
reason, as for a body that threw `Cancelled('why')` itself. A child whose
parent ran out of its deadline gets a `ParentCancelReason` too: its `origin` is
the parent's `TimeoutCancelReason`.

A body that awaits `value` of a job it does not own gets no
`HandlerCancelReason` for it: that job's cancellation goes through with its
reason as it is, and the outcome reads `Cancelled(manual)` for a job nobody
called `cancel` on.

Besides the `reason`, `Cancelled` contains a `started` flag, an optional
`description` and the stack trace of the cancellation. `started` tells you
whether the body ran or was cancelled before start. The built-in reason classes
are `ManualCancelReason`, `ParentCancelReason`, `HandlerCancelReason`,
`ChainCancelReason`, `SiblingCancelReason` and `TimeoutCancelReason`.
`TimeoutCancelReason` is what a job gets when the deadline given with `timeout`
runs out, as [A deadline](time.md#a-deadline) shows. All extend `CancelReason`.

Check reasons by type, for example `reason is ParentCancelReason`. The `name`
property is a label for logs and does not determine equality. Reasons use
identity equality unless their class defines value equality.

The body can throw `Cancelled.by(reason: reason)` to use an explicit reason, or
`Cancelled('why')` to use `HandlerCancelReason`. An error's stack trace stored
in a reason is separate from the cancellation's stack trace:
`RequestCancelReason.stackTrace` is where the request failed, and
`Cancelled.stackTrace` is where the cancellation came from.

## Reacting before the outcome

`report` runs a step a cancellation cannot interrupt, and cleans up after it:

```dart
final report = Job<void>((ctx) async {
  ctx.onDispose(() => print('cleanup'));
  await ctx.run(
    Job.deferred<void>(cancellable: false, (ctx) async {
      await ctx.pause(const Duration(milliseconds: 50));
      print('step finished');
    }),
  );
});
```

The screen that shows the report should say it is being cancelled the moment
somebody cancels it, while the step still runs.

### The first attempt

The outcome says whether the job was cancelled:

```dart
// The first attempt: done arrives only after the cleanup.
if (await report.done case Cancelled(:final reason)) {
  print('cancelling: $reason');
}
```

```text
step finished
cleanup
cancelling: manual
```

The screen says it only once the step and the cleanup are over. `done`
completes with the outcome, and the job has one only when its body, its
children and its cleanup have ended. Awaiting `report.cancel()` is no quicker:
it returns at the same moment. `report.isCancelled` turns `true` the moment the
cancellation is accepted, but the screen learns of that only when it reads the
getter again.

### Listening for the cancellation

To react when cancellation is accepted, without waiting for the final outcome,
register a listener with `job.whenCancelled(callback)`. It runs synchronously
and receives the `Cancelled` with its reason and details:

```dart
// Runs when the cancellation is accepted; the job may still be finishing.
final unregister = report.whenCancelled((cancelled) {
  print('cancelling: ${cancelled.reason}');
});
```

```text
cancelling: manual
step finished
cleanup
```

The registration returns a function that unregisters the listener. A screen
that closes while the report is still running calls it, and a cancellation that
comes afterwards tells the screen nothing:

```dart
// The screen closes; the report goes on.
unregister();
```

```text
step finished
cleanup
```

Once the job has finished there is nothing to unregister: every listener has
either run or been released, and calling the function then does nothing.

When the listener runs depends on how the job is cancelled:

| How the job is cancelled | When the listener runs |
| --- | --- |
| From outside, while it runs | after the cancellation has cascaded to the children and the `ctx.onCancel` callbacks have run, without waiting for the body to finish |
| Before it starts | when the job is cancelled |
| By its own body, which throws `Cancelled` or lets another job's cancellation through while nothing has cancelled the job | as the body ends, after the cancellation has cascaded to the children and the `ctx.onCancel` callbacks have run, without waiting for the children to end |

Once the pass over the listeners has begun, registering calls the new one
immediately, even if the job has finished: a listener that registers another
while it runs sees the new one run at once, ahead of the listeners still
waiting their turn. Until the pass begins, a new registration joins it after
the ones made before, even while the cancellation already cascades onto the
children or the job's `ctx.onCancel` callbacks run. A refused cancellation does
not start the pass. An `uncancellable` section delays it until cancellation is
accepted. A job that finishes as `Done` or `Failed` without cancellation
releases its listeners without calling them.

Each registration runs once. Listeners waiting their turn run in registration
order, using a snapshot of the list: removing a listener during the pass does
not take it out of the pass. Unregistering more than once is safe.

A synchronous listener error goes to `onError` and then to the job's creation
zone, unless the observer catches it in `onUnanswered`, as
[Where errors go](errors.md#where-errors-go) on the errors page shows. Without
an observer, it goes straight to that zone. A thrown `Cancelled` is never
forwarded to the zone. Listener errors do not change cancellation or prevent
other listeners from running.

`whenCancelled` is made for a synchronous callback, though Dart lets an `async`
one be passed. The job does not wait for the future of such a callback, and
none of the callback's errors reaches `onError`: an `async` function never
throws synchronously, and even an error before its first `await` goes into the
future it returns. The error is an uncaught one of the zone the listener was
called in. For a cancellation accepted inside `cancel()`, that is the zone of
the code that called it. For a cancellation an `uncancellable` section held,
and for a body that cancelled itself, it is the zone the body runs in. A job
made with `Job(...)` runs its body in the zone it was created in, and one made
with `Job.deferred` in the zone it was started from. If a job made with
`Job(...)` was created, or one made with `Job.deferred` started, inside work
handed to `ctx.unattended`, its body runs in the zone that work was started
from.
