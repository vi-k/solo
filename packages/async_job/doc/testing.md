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
| `ctx.pause(duration)`, which waits on a timer | `elapse(duration)` or `flushTimers()` |
| The deadline of `timeout: limit`, which the core keeps on a timer | `elapse(limit)` or `flushTimers()` |

## A failure the test expects

A test checks that an open of a locked database fails.

### The first attempt

```dart
// The first attempt: the check passes, and the test fails.
test('a locked database fails the open', () {
  fakeAsync((async) {
    final job = Job<Database>((ctx) => ctx.join(Database.open));
    async.flushTimers();

    expect(job.outcome, isA<Failed>());
  });
});
```

```text
Bad state: database locked
```

The `expect` passes, and the test fails with the very error it checks for.
Reading `outcome` does not observe the failure: nobody read `done` or `value`
or called `ignoreFailure()`, so the failure goes to the zone the job was made
in. That is the zone of the test, and `package:test` fails a test whose zone
hears an error. The errors that no outcome carries, such as those of cleanup or
of `ctx.unattended`, get there the same way unless an observer answers for
them: see [Where each error goes](errors.md#where-each-error-goes).

### The failure read by the test

```dart
test('a locked database fails the open', () {
  fakeAsync((async) {
    final job = Job<Database>((ctx) => ctx.join(Database.open))
      ..ignoreFailure(); // the test reads the failure from the outcome
    async.flushTimers();

    expect(job.outcome, isA<Failed>());
  });
});
```

`ignoreFailure()` says that somebody takes care of the failure, and here it is
the test. A test that reads `job.done` or `job.value` observes it as well.

## Comparing outcomes

A test checks the value of a job through its outcome.

### The first attempt

```dart
// The first attempt: two outcomes printed alike are not equal.
test('the job loads three', () {
  fakeAsync((async) {
    final job = Job<int>((ctx) => ctx.join(load));
    async.flushTimers();

    expect(job.outcome, const Done(3));
  });
});
```

```text
Expected: Done<int>:<Done(3)>
  Actual: Done<int>:<Done(3)>
```

An outcome has no `==` of its own, so two outcomes are equal only when they are
one object, and the outcome of a job is never the one the test builds.

### By type and value

```dart
test('the job loads three', () {
  fakeAsync((async) {
    final job = Job<int>((ctx) => ctx.join(load));
    async.flushTimers();

    expect(
      job.outcome,
      isA<Done<int>>().having((done) => done.value, 'value', 3),
    );
  });
});
```

The same goes for the rest: `isA<Cancelled>()` with `having` on `reason`, and
`isA<Failed>()` with `having` on `error`.

## Settings between tests

```dart
setUp(() {
  final previous = Job.isCancellationError;
  Job.isCancellationError = (error) => error is DatabaseStopped;
  addTearDown(() => Job.isCancellationError = previous);
});
```

`Job.isCancellationError` and `Job.debug` are static. A test that sets one sets
it for each test after it in the same file: a filter left behind keeps the
errors it names away from the zone of those tests. `addTearDown` puts back what
was there.
