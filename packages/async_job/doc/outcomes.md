# Outcomes

Once the body, its children and cleanup have finished, `job.done` completes
with an `Outcome<T>`. It never throws: success, failure and cancellation are
represented by `Done`, `Failed` and `Cancelled`. `Outcome<T>` is sealed, so a
`switch` covering these cases is exhaustive:

```dart
final message = switch (await job.done) {
  Done(:final value) => 'done $value',
  Failed(:final error) => 'failed $error',
  Cancelled(:final reason) => 'cancelled $reason',
};
```

If you only need the returned value, await `job.value`. It completes with the
value on success and throws on failure or cancellation. If you do not need the
result at all, call `job.ignore()` to acknowledge that choice.

Accessing `done` or `value`, or calling `ignore()`, counts as observing a
failure. Forwarding a failure through `then` observes it too; the continuation
takes responsibility for it. Reading `job.outcome`, receiving the observer's
`onFinish` callback or awaiting `job.cancel()` does not. An unobserved failure
reaches the job's creation zone on the microtask after the job finishes. This
keeps a failure visible even when no caller waits for the result.

For a cancelled job, the outcome also explains why it stopped. `Cancelled`
contains a `reason`, a `started` flag, an optional `description` and the stack
trace of the cancellation. `started` tells you whether the body ran or was
cancelled before start. The built-in reason classes are `ManualCancelReason`,
`ParentCancelReason`, `HandlerCancelReason` and `ChainCancelReason`, all
extending `CancelReason`.

Check reasons by type, for example `reason is ParentCancelReason`. The `name`
property is a label for logs and does not determine equality. Reasons use
identity equality unless their class defines value equality.

You can define a reason that stores additional data, such as an error and its
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

Pass the reason to `cancel()`. The cancellation listener and the outcome
receive the same instance:

```dart
try {
  await request();
} on Object catch (error, stackTrace) {
  await job.cancel(reason: RequestCancelReason(error, stackTrace));
}
```

The body can throw `Cancelled.by(reason: reason, started: true)` to use an
explicit reason, or `Cancelled('why')` to use `HandlerCancelReason`. When a
parent cancels a child, the child's `ParentCancelReason.cause` holds the
parent's `Cancelled`. When a child's cancellation escapes through the parent
body, the parent's `HandlerCancelReason.cause` holds the child's `Cancelled`.
These links preserve the original reason and its data. An error's stack trace
stored in a reason is separate from the cancellation's stack trace.

To react when cancellation is accepted, without waiting for the final outcome,
register a listener with `job.whenCancelled(callback)`. It runs synchronously
and receives the `Cancelled` with its reason and details. The registration
method returns a function to unregister the listener. Its timing depends on how
cancellation happens:

- For an external cancellation of a running job, it runs after cancellation has
  cascaded to children and `ctx.onCancel` callbacks have run, without waiting
  for the body to finish.
- For a job cancelled before start, it runs when the job is cancelled.
- If the body throws `Cancelled`, it runs after the body and its children have
  ended, before cleanup.

```dart
final job = Job<Report>(build);

// Cancellation has been accepted; the job may still be finishing.
final unregister = job.whenCancelled((cancelled) {
  print('cancelling: ${cancelled.reason}');
});

final outcome = await job.done;
// Safe after completion; call earlier to stop listening sooner.
unregister();
```

Registering after cancellation calls the listener immediately, even if the job
has finished. A refused cancellation does not notify listeners. An
`uncancellable` section delays notification until cancellation is accepted. A
job that finishes as `Done` or `Failed` without cancellation releases its
listeners without calling them. Registering a listener does not count as
observing a failure.

Each registration runs once. Listeners run in registration order, using a
snapshot of the list: removing a listener during notification does not remove
it from the current pass. A listener added during notification runs
immediately. Unregistering more than once is safe.

A synchronous listener error goes to `onError`, or to the job's creation zone
if there is no observer. A thrown `Cancelled` is never forwarded to the zone.
Listener errors do not change cancellation or prevent other listeners from
running. If you pass an `async` callback, its future is not awaited and its
errors are not caught by this mechanism.
