# Outcomes

Once the body, its children and cleanup have finished, a job has an
`Outcome<T>`: `Done` with the value the body returned, `Failed` with the error
it threw, or `Cancelled`. `job.done` completes with it and never throws,
`job.value` gives the value alone, and `job.outcome` holds it once the job is
over, `null` before that. `Outcome<T>` is sealed, so a `switch` covering these
three cases is exhaustive.

The lines under the code are what it prints when it runs, and `zone:` is an
error that reached the zone uncaught. Each section below opens with the version
the API leads to and shows what that code does: in the first three, the member
named after the question you ask — `value` for the value, `outcome` for how the
job went, `reason` for why it was cancelled; in the last, the outcome read
through `done`, the way the first section reads it. The version that works
follows under its own heading.

## Reading the result

`report` is a `Job<Report>` the user can cancel. When it is over, the code that
started it prints one of three things: the report, the error the job failed
with, or that it was cancelled.

### The first attempt

`value` is the report, and a `try` takes what goes wrong:

```dart
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

A failure nobody observes goes to the job's creation zone on the microtask
after the job finishes: that keeps it visible when no caller waits for the
result. In a test that zone is the test's, and the test fails. Reading
`outcome` does not count as observing, and neither does awaiting
`job.cancel()`, registering with `whenCancelled` or any callback of the
observer: `onError` and `onFinish` hear the failure, and it reaches the zone
all the same.

### Telling the core it is handled

```dart
final backup = Job<void>(upload)..ignoreFailure();
```

```text
status: backup failed: Bad state: disk full
```

`ignoreFailure()` tells the core that the failure is handled elsewhere, here by
the status line, and nothing reaches the zone. Accessing `done` or `value`
observes a failure as well, so code that waits for the job — to redraw the
status line when it is over, say — needs no `ignoreFailure()`. `done` never
throws; with `value` the waiting code gets the error itself and has to handle
it, as with any `Future`. Forwarding a failure through `then` observes it too;
the continuation takes responsibility for it.

Waiting does not observe a failure a cancellation covers: the body of `backup`
fails, and a cancellation arrives after it — while the job still waits for its
children or runs its cleanup, say. The job ends `Cancelled`: the code waiting
for it gets the cancellation, not the error, and the status line says
`backup cancelled`. The error goes the way of an error no outcome carries —
[Where errors go](observing.md#where-errors-go) on the observing page shows it.
`ignoreFailure()` keeps it out of the zone, and then only an observer's
`onError` hears it.

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
its own, whose reason is `HandlerCancelReason`: its body gave up. The
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

Three reasons hold the cancellation that caused them in `cause`. When a parent
cancels a child, the child's `ParentCancelReason.cause` holds the parent's
`Cancelled`. When a child's cancellation escapes through the parent body, the
parent's `HandlerCancelReason.cause` holds the child's `Cancelled`. In a chain
of `then`, a job cancelled by its neighbour holds the neighbour's `Cancelled`
in `ChainCancelReason.cause`. These links preserve the original reason and its
data, and `origin` follows them to the end: `cause` is `null` where nothing
stands behind the reason, as for a body that threw `Cancelled('why')` itself. A
child cancelled because the deadline of its parent ran out follows the same
link: its `origin` is the parent's `TimeoutCancelReason`. `SiblingCancelReason`
has a `cause` too, but that is what the group of `ctx.runAll` stopped for — the
error or the cancellation another branch ended with, or an error of the group
itself. So `origin` does not follow that `cause`: it returns the
`SiblingCancelReason` itself.

A body that awaits `value` of a job it does not own gets no
`HandlerCancelReason` for it: that job's cancellation goes through with its
reason as it is, and the outcome reads `Cancelled(manual)` for a job nobody
called `cancel` on.

Besides the `reason`, `Cancelled` contains a `started` flag, an optional
`description` and the stack trace of the cancellation. `started` tells you
whether the body ran or was cancelled before start. The built-in reason classes
are `ManualCancelReason`, `ParentCancelReason`, `HandlerCancelReason`,
`ChainCancelReason`, `SiblingCancelReason` and `TimeoutCancelReason`.
`SiblingCancelReason` is what a group of `ctx.runAll` gives its branches when
it fails, and `TimeoutCancelReason` is what a job gets when the deadline given
with `timeout` runs out, as [A deadline](cancellation.md#a-deadline) shows. All
extend `CancelReason`.

Check reasons by type, for example `reason is ParentCancelReason`. The `name`
property is a label for logs and does not determine equality. Reasons use
identity equality unless their class defines value equality.

The body can throw `Cancelled.by(reason: reason, started: true)` to use an
explicit reason, or `Cancelled('why')` to use `HandlerCancelReason`. An error's
stack trace stored in a reason is separate from the cancellation's stack trace:
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

- For an external cancellation of a running job, it runs after cancellation has
  cascaded to children and `ctx.onCancel` callbacks have run, without waiting
  for the body to finish.
- For a job cancelled before start, it runs when the job is cancelled.
- If the body gives itself up — throws `Cancelled` itself or lets another job's
  cancellation through while nothing has cancelled the job — it runs as the
  body ends, after cancellation has cascaded to children and `ctx.onCancel`
  callbacks have run, without waiting for the children to end.

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
zone, unless the observer answers for it, as
[Where errors go](observing.md#where-errors-go) on the observing page shows.
Without an observer, it goes straight to that zone. A thrown `Cancelled` is
never forwarded to the zone. Listener errors do not change cancellation or
prevent other listeners from running. `whenCancelled` is made for a synchronous
callback, though Dart lets an `async` one be passed. The job does not wait for
the future of such a callback, and none of the callback's errors reaches
`onError`: an `async` function never throws synchronously, and even an error
before its first `await` goes into the future it returns. The error is an
uncaught one of the zone the listener was called in. For a cancellation
accepted inside `cancel()`, that is the zone of the code that called it. For a
cancellation an `uncancellable` section held, and for a body that gave itself
up, it is the zone the body runs in. A job made with `Job(...)` runs its body
in the zone it was created in, and one made with `Job.deferred` in the zone it
was started from. If a job made with `Job(...)` was created, or one made with
`Job.deferred` started, inside work handed to `ctx.unattended`, its body runs
in the zone that work was started from.
