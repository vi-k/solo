# Outcomes

Once the body, its children and cleanup have finished, a job has an
`Outcome<T>`: `Done` with the value the body returned, `Failed` with the error
it threw, or `Cancelled`. `job.done` completes with it and never throws,
`job.value` gives the value alone, and `job.outcome` holds it once the job is
over, `null` before that. `Outcome<T>` is sealed, so a `switch` covering these
three cases is exhaustive.

The lines under the code are what it prints when it runs. Three sections below
open with the version the vocabulary of the API leads to — the member named
after the question you ask: `value` for the value, `outcome` for how the job
went, `reason` for why it was cancelled — and show what that code does. The
version that works follows under its own heading. The last section, on reacting
before the outcome, opens with the answer.

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
all, call `report.ignore()` to acknowledge that choice.

## A failure nobody waits for

`sync` uploads in the background, and nothing awaits it. A status line reads
how it went whenever the line is drawn.

### The first attempt

`outcome` is how the job went, and `null` while it runs:

```dart
final sync = Job<void>(upload);

// Wherever the status line is drawn:
final status = switch (sync.outcome) {
  null => 'syncing',
  Done() => 'synced',
  Failed(:final error) => 'sync failed: $error',
  Cancelled() => 'sync cancelled',
};
print('status: $status');
```

The upload fails. The status line says so, and the zone the job was created in
receives the same error as an uncaught one:

```text
status: sync failed: Bad state: disk full
zone: Bad state: disk full
```

A failure nobody observes goes to the job's creation zone on the microtask
after the job finishes: that keeps it visible when no caller waits for the
result. In a test that zone is the test's, and the test fails. Reading
`outcome` does not count as observing, and neither does the observer's
`onFinish` callback, awaiting `job.cancel()` or registering with
`whenCancelled`.

### Telling the engine it is handled

```dart
final sync = Job<void>(upload)..ignore();
```

```text
status: sync failed: Bad state: disk full
```

`ignore()` tells the engine that the failure is handled elsewhere, here by the
status line, and nothing reaches the zone. Accessing `done` or `value` observes
a failure as well, so code that waits for the job — to redraw the status line
when it is over, say — needs no `ignore()`. Forwarding a failure through `then`
observes it too; the `then` job takes responsibility for it.

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

`report` runs a child, `fetch`, for its data, and `fetch` needs a token that a
request elsewhere refreshes. When that request fails, the code that sent it
cancels `fetch` and passes the error in the reason; the cancellation listener
and the outcome of `fetch` receive the same instance:

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
stands behind the reason, as for a body that threw `Cancelled('why')` itself.
`SiblingCancelReason` has a `cause` too, but that is what a group stopped for —
the error another branch failed with, or the cancellation that ended it — and
`origin` stops at it.

Only a child is linked this way. A body that awaits `value` of a job it does
not own lets that job's cancellation through with its reason as it is: the
outcome reads `Cancelled(manual)` for a job nobody called `cancel` on.

Besides the `reason`, `Cancelled` contains a `started` flag, an optional
`description` and the stack trace of the cancellation. `started` tells you
whether the body ran or was cancelled before start. The built-in reason classes
are `ManualCancelReason`, `ParentCancelReason`, `HandlerCancelReason`,
`ChainCancelReason` and `SiblingCancelReason` — the last one is what a group of
`ctx.runAll` gives the siblings of a branch that went wrong. All extend
`CancelReason`.

Check reasons by type, for example `reason is ParentCancelReason`. The `name`
property is a label for logs and does not determine equality. Reasons use
identity equality unless their class defines value equality.

The body can throw `Cancelled.by(reason: reason, started: true)` to use an
explicit reason, or `Cancelled('why')` to use `HandlerCancelReason`. An error's
stack trace stored in a reason is separate from the cancellation's stack trace:
`RequestCancelReason.stackTrace` is where the request failed, and
`Cancelled.stackTrace` is where the cancellation came from.

## Reacting before the outcome

To react when cancellation is accepted, without waiting for the final outcome,
register a listener with `job.whenCancelled(callback)`. It runs synchronously
and receives the `Cancelled` with its reason and details. The registration
method returns a function to unregister the listener:

```dart
// Runs when the cancellation is accepted; the job may still be finishing.
final unregister = report.whenCancelled((cancelled) {
  print('cancelling: ${cancelled.reason}');
});

await report.done;
// Safe after completion; call earlier to stop listening sooner.
unregister();
```

When the listener runs depends on how the job is cancelled:

- For an external cancellation of a running job, it runs after cancellation has
  cascaded to children and `ctx.onCancel` callbacks have run, without waiting
  for the body to finish.
- For a job cancelled before start, it runs when the job is cancelled.
- If the body throws `Cancelled`, it runs after the body and its children have
  ended, before cleanup.

Registering once the cancellation has been announced calls the listener
immediately, even if the job has finished. A registration made in between —
while the cancellation cascades onto the children, or while a job whose body
gave itself up waits for them — joins that announcement instead, in its own
place: one made later never runs before one made earlier. A refused
cancellation does not notify listeners. An `uncancellable` section delays
notification until cancellation is accepted. A job that finishes as `Done` or
`Failed` without cancellation releases its listeners without calling them.

Each registration runs once. Listeners run in registration order, using a
snapshot of the list: removing a listener during notification does not remove
it from the current pass. A listener added during notification runs
immediately. Unregistering more than once is safe.

A synchronous listener error goes to `onError`, or to the job's creation zone
if there is no observer. A thrown `Cancelled` is never forwarded to the zone.
Listener errors do not change cancellation or prevent other listeners from
running. An `async` callback is accepted, but the job does not wait for its
future, and an error after its first `await` reaches neither `onError` nor the
job's creation zone: it is an uncaught error of the zone the listener was
called in, which for a cancellation from outside is the zone of the code that
called `cancel`.
