# Observing and testing

## Observer

An outcome describes one job's result. A `JobObserver` also receives
lifecycle events, logs and errors from work outside the body:

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
); // Job(load): Done(3)
```

It has four hooks: `onStart`, `onFinish`, `onError` and `onLog`. `Job` calls
the first three automatically; the body sends messages to `onLog` through
`ctx.log(message)`.

All four have empty default implementations, so you can override only
those you need. You can also use `implements JobObserver` if your class
already extends another class. Pass the observer when creating the job;
children inherit it unless they have their own. If a hook throws, its
error goes to the current zone without changing the job's behavior.

A job's string representation is `Job($key)`. Use `key` to identify it in
logs or in a library's scheduling rules, such as `solo` queue policies.
`describe` adds context to the log description.

Messages passed to `ctx.log` remain objects until the listener formats
them. With no observer, `ctx.log` does nothing, but Dart still evaluates
its argument. For example, `ctx.log('migration failed: $error')` formats
the string even without an observer. Pass the object directly to leave
formatting to the listener, or pass a callback to defer building the
message itself:

```dart
ctx.log(() => 'migration failed: $error');
```

The observer above calls the callback and formats the returned data.
Without an observer, the callback is never called and the interpolation
does not run. This is a convention of this observer: `ctx.log` passes the
callback through unchanged, just like any other object.

A body error is sent to the observer. If the job ends with that error,
it is stored in `Failed` and is also reported to the job's creation zone
if the outcome remains unobserved.

Errors outside the body cannot become its outcome. These include late
errors from an action abandoned by `wait`, cleanup errors, cancellation
callback errors (`ctx.onCancel` or `job.whenCancelled`), errors from
`ctx.unattended` and errors while formatting a child's cancellation
description. They go to the observer, or directly to the job's creation
zone if there is no observer. An observer decides how to handle them.
A `Cancelled` reported through this route goes only to the observer and
is never forwarded to the zone as an unhandled error.

How long a cancelled job kept running is not a hook of its own, and does
not need one. `Job.whenCancelled` fires when the cancellation takes
effect and `onFinish` when the outcome arrives, so an observer that
stamps the clock in the first and subtracts in the second has the number:
the wait the caller of `cancel` sits through. It catches what causes that
wait — a body waiting on something slow with a bare `await` holds the
cancellation for its whole length, where the same call through `ctx.wait`
gives it up at once. `solo` shows the observer in full; see
`doc/errors.md` there.

## Testing

Testing start, cancellation and cleanup requires controlling microtasks
and timers. `package:fake_async` lets you do this without waiting in real
time. This package uses it in its own tests; here it checks that cancelling
a database open still closes the database once opening finishes:

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

`flushMicrotasks()` is enough to start a job. Operations scheduled through
`Future(...)` or `Future.delayed(...)` use timers, so advance them with
`flushTimers()` or `elapse(...)`.
