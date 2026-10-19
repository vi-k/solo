# Testing

A job runs on timers and microtasks, so a test can run it on fake time and wait
for nothing in real time. `package:fake_async` gives a test such time.

## A cancelled open

A test checks that cancelling a database open still closes the database once
the open finishes. `discard` closes a value that arrives after the
cancellation, as in
[A value that comes late](cleanup.md#a-value-that-comes-late).

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
`expect` runs. This is what happens:

1. Under `fakeAsync`, time moves only when the test moves it.
2. The callback returns at its first `await`, and `fakeAsync` returns with it.
3. Nothing moves the time again, so the future of `cancel()` never completes,
   and the code after it never runs.

Written as `() => fakeAsync(...)`, the test would wait for that future instead
and fail on its timeout.

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
What moves the time depends on what the test waits for:

| The test waits for | It calls |
| --- | --- |
| The start of a job, whose body starts in a microtask | `flushMicrotasks()` |
| Work scheduled with `Future(...)` or `Future.delayed(...)`, which use timers | `flushTimers()` or `elapse(...)` |
