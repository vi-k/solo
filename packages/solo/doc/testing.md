# Testing

A controller is tested through its jobs: a call queues one and returns it, and
the state it publishes arrives later. Every example below uses `package:test`
and drives the `load` of the quick start controller from the
[README](https://github.com/vi-k/solo/blob/main/packages/solo/README.md):

```dart
final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        onError: (state, error, stackTrace) => Failure(error),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}
```

`onError` turns a failure into `Failure`, `onCancel` puts the state back to
`Initial`, and `key: 'load'` with `Policy.droppable` is what makes a second
call join the load already in flight — the tests below read all three. The API
it calls is faked: an answer after twenty milliseconds, or an error.

```dart
class FakeProfileApi implements ProfileApi {
  FakeProfileApi({this.name = 'Ada Lovelace', this.error});

  final String name;
  final Object? error;

  @override
  Future<String> fetchName() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final error = this.error;
    if (error != null) throw error;
    return name;
  }
}
```

Two kinds of test run through the page. One holds a job and awaits it: the
outcome is the only signal it needs, and the fake's twenty milliseconds are
waited out for real. The other has to look between the events — the order two
calls ended up in, a deadline five seconds away — and can await nothing at all:
it runs under `package:fake_async`, where the clock moves when the test says
so. The three sections below await; `fakeAsync` starts with the fourth.

Seven sections below open with the test the vocabulary of the API and of
`package:test` leads to — the assertion right after the call, the `close` that
should let the work finish, the `await` inside `fakeAsync`, the expectation
inside a zone — and say what that test does instead of what it was written to
do. The version that works follows under its own heading.

## Awaiting a job

### The first attempt

```dart
test('load fills in the name', () {
  final profile = ProfileController(FakeProfileApi());

  profile.load();

  expect(profile.currentState, isA<Loaded>());
});
```

The test fails, and the state it prints is `Initial` — not even `Loading`, the
state the body emits on its first line. `load()` queues a job and returns; the
body starts on a later microtask, and the fake answers twenty milliseconds
after that. Nothing of the load has happened by the time the expectation runs,
and the message reads as though the controller had ignored the call.

### Awaiting the outcome

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;

  expect(outcome, isA<Done<String>>());
  expect(
    profile.currentState,
    isA<Loaded>().having((state) => state.name, 'name', 'Ada Lovelace'),
  );

  await profile.close();
});
```

`done` completes with the outcome and never throws, so the same line serves a
load that succeeds, fails or is cancelled. By the time it completes the state
handlers have run as well, and the state the test reads is the final one.

`value` is the other half — the value the body returned, or the error it threw:

```dart
test('a failed load carries the error to the caller', () async {
  final profile = ProfileController(
    FakeProfileApi(error: StateError('no network')),
  );

  await expectLater(profile.load().value, throwsA(isA<StateError>()));
  expect(profile.currentState, isA<Failure>());

  await profile.close();
});
```

A cancellation is an outcome as well, and `done` is what a test about one asks:

```dart
test('a cancelled load ends Cancelled', () async {
  final profile = ProfileController(FakeProfileApi());
  final job = profile.load();

  await job.cancel();

  expect(
    await job.done,
    isA<Cancelled>().having((outcome) => outcome.started, 'started', isFalse),
  );
  expect(profile.currentState, isA<Initial>());

  await profile.close();
});
```

`cancel()` completes when the job has finished, so the outcome is there on the
line below it. `done` hands it over like any other, while `value` would throw
it — a test expecting a cancellation would be reading it out of a `throwsA`.
`started: false` is why the state is untouched here: the job was still in the
queue, its body never ran, and the controller's `onCancel` was not called at
all. A load cancelled while it runs ends with the same `Cancelled`, and the
state it ends in is the one its `onCancel` published.

## Closing the controller

### The first attempt

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  profile.load();
  await profile.close();

  expect(profile.currentState, isA<Loaded>());
});
```

`close()` cancels, and the state the expectation sees is `Initial`. The job
here never leaves the queue: both lines run in the same turn, so `close` drops
it with `Cancelled(closed)` before the body starts, and the state is still the
one the controller was built with. A load that had started would end the same
way, cancelled where it was waiting, and the controller's `onCancel` would
publish `Initial` over the `Loading` its body had emitted.

### Letting the work finish

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;
  await profile.close();

  expect(outcome, isA<Done<String>>());
  expect(profile.currentState, isA<Loaded>());
});
```

The job is awaited first and `close` comes after it, as the end of the test
rather than a way to wait. Where the test holds no job — a controller that
queues work of its own, a widget that fills the queue — `close` can run what is
already in it:

```dart
await profile.close(mode: SoloCloseMode.drain);
```

A drain runs the queue; it does not promise the work succeeds. A drained job
can still fail, and what that costs a test is the next section.

## A failure nobody read

### The first attempt

```dart
test('a failed load shows the failure', () async {
  final profile = ProfileController(
    FakeProfileApi(error: StateError('no network')),
  );

  profile.load();
  await profile.close(mode: SoloCloseMode.drain);

  expect(profile.currentState, isA<Failure>());
});
```

The expectation holds and the test is red anyway. Nobody read the job's
outcome, so the engine reports the failure to the zone the job was created in —
here the zone of the test — and the runner fails the test with
`Bad state: no network` under a stack trace that runs through `JobContext`
without naming a line of the test. A test that does not wait for the job at all
pays more: the failure arrives after the test has ended, and the runner says
so — `This test failed after it had already completed`, against the name of a
test that has already passed while a later one is running.

### Reading the outcome

```dart
test('a failed load shows the failure', () async {
  final profile = ProfileController(
    FakeProfileApi(error: StateError('no network')),
  );

  final outcome = await profile.load().done;

  expect(outcome, isA<Failed>());
  expect(profile.currentState, isA<Failure>());

  await profile.close();
});
```

Reading `done` or `value` marks the job observed, and an observed failure is
the test's business rather than the zone's. A job the test starts and drops on
purpose says so with `job.ignore()`, which marks it observed without waiting
for it. Reading `job.outcome` does not mark anything: it is a look at a field,
and the field is `null` until the job has finished.

## The order of what happened

### The first attempt

Timing and ordering are tested with `package:fake_async`, and what happened is
collected by an observer — one for every controller in the process:

```dart
final class Journal extends SoloObserver {
  final lines = <String>[];

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} started');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} ${job.outcome}');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      lines.add('state: ${transition.current.runtimeType}');
}

test('a second load while the first one runs is dropped', () {
  fakeAsync((async) {
    final journal = Journal();
    Solo.observer = journal;
    addTearDown(() => Solo.observer = null);
    final profile = ProfileController(FakeProfileApi());

    final first = profile.load();
    final second = profile.load();
    expect(identical(first, second), isTrue);

    async.elapse(const Duration(milliseconds: 20));
    expect(journal.lines, [
      'load started',
      'state: Loading',
      'load Cancelled(manual: duplicate)',
      'state: Loaded',
      'load Done(Ada Lovelace)',
    ]);

    profile.close();
    async.flushTimers();
  });
});
```

The journal comes out in another order:

```text
load Cancelled(manual: duplicate)
load started
state: Loading
state: Loaded
load Done(Ada Lovelace)
```

Both calls are made in the same turn, so the queue has not run between them.
`droppable` finds the first job still waiting, and the second call drops the
job it has just created — inside the call itself, before anything has started.
The test is right that a duplicate was dropped and wrong about the case its
name describes: nothing was running.

### Letting the first job start

```dart
final first = profile.load();
async.flushMicrotasks();
final second = profile.load();
```

One `flushMicrotasks()` is the difference between the two cases. With it the
first job leaves the queue and emits `Loading`, and the second call finds a
load that is running:

```text
load started
state: Loading
load Cancelled(manual: duplicate)
state: Loaded
load Done(Ada Lovelace)
```

The cancelled duplicate in the journal is the newly created job that
`droppable` discarded; both calls returned the first job, which is what
`identical` checks. The observer is a process-wide static, so the test resets
it — through `addTearDown` and not a line at the end, for the reason in
[What one test leaves for the next](#what-one-test-leaves-for-the-next).

## Awaiting inside fakeAsync

### The first attempt

```dart
test('load fills in the name', () async {
  await fakeAsync((async) async {
    final profile = ProfileController(FakeProfileApi());

    final outcome = await profile.load().done;

    expect(outcome, isA<Done<String>>());
    await profile.close();
  });
});
```

The test hangs until the test's own timeout kills it. The callback suspends at
its first `await` and returns a future; `fakeAsync` hands that future back and
unwinds, and with nobody left to elapse the fake clock no timer inside it will
ever fire. The expectation never runs, and the only sign is a timeout that
reads like a deadlock in the controller.

### Elapsing instead of awaiting

```dart
test('load fills in the name', () {
  fakeAsync((async) {
    final profile = ProfileController(FakeProfileApi());

    final job = profile.load()..ignore();
    async.elapse(const Duration(milliseconds: 20));

    expect(job.outcome, isA<Done<String>>());
    expect(profile.currentState, isA<Loaded>());

    profile.close();
    async.flushTimers();
  });
});
```

The callback stays synchronous and reads `job.outcome` where the test above
awaited `done` — and `ignore()` is what stands in for that read: inside
`fakeAsync` nothing can be awaited, so a failure would reach the zone with no
one having observed it. `flushMicrotasks()` runs microtasks; `Future(...)` and
`Future.delayed(...)` use timers and need `elapse(...)` or `flushTimers()`.
Cancellation is requested with `job.cancel().ignore()` — that one is
`Future.ignore`, on the future the call returns — and lands on the next
microtask. `close()` and a last `flushTimers()` end the test with an empty
clock; a controller left with work in flight stays as it is, and `fakeAsync`
says nothing about a timer nobody fired.

`elapse` moves `clock.now()` along with the timers, so a recipe that stamps
time — the observer of
[Why cancellation was slow](errors.md#why-cancellation-was-slow) — is tested
here too, without the test waiting for any of it.

## What one test leaves for the next

### The first attempt

```dart
test('a second load while the first one runs is dropped', () {
  final journal = Journal();
  Solo.observer = journal;

  // ...the test...

  Solo.observer = null;
});
```

The reset runs when the test passes, which is when it was not needed. `expect`
reports a failure by throwing `TestFailure`, so the first expectation that
fails skips every line under it, and the journal of a test that is over stays
installed for the next one — collecting lines nobody reads, and reporting on
controllers it has never seen.

### addTearDown

```dart
Solo.observer = journal;
addTearDown(() => Solo.observer = null);
```

`addTearDown` runs whether the test passed or failed. Four statics belong to
the process rather than to a controller, and each of them outlives a test the
same way: `Solo.observer`, `Solo.errorHandler`, `Solo.traceStateChanges` and
`Solo.debug`. The last two have a default that is not `null` —
`traceStateChanges` is on wherever assertions are — so a test that changes one
restores the value it found, not a constant.

## Assertions inside a zone

### The first attempt

```dart
test('a failure nobody read reaches the zone', () async {
  await runZonedGuarded(
    () async {
      final profile = ProfileController(
        FakeProfileApi(error: StateError('no network')),
      )..load();
      await profile.close(mode: SoloCloseMode.drain);

      expect(profile.currentState, isA<Failure>());
    },
    (error, stackTrace) => expect(error, isA<StateError>()),
  );
});
```

The test is green whatever the zone caught. A job reports to the zone it was
created in, so the controller has to be built inside `runZonedGuarded`, and the
expectations follow it in — where `expect` throws `TestFailure` and the handler
collects that throw like any other error. The expectation in the handler is no
better: it says nothing at all about the run where no error arrives.

### Collecting in the zone, asserting outside

```dart
test('a failure nobody read reaches the zone', () async {
  final zoneErrors = <Object>[];

  await runZonedGuarded(
    () async {
      final profile = ProfileController(
        FakeProfileApi(error: StateError('no network')),
      )..load();
      await profile.close(mode: SoloCloseMode.drain);
    },
    (error, stackTrace) => zoneErrors.add(error),
  );

  expect(zoneErrors, [isA<StateError>()]);
});
```

The zone collects, the test asserts after it. The drain is what makes the line
below safe to write: by the time `close` returns, the job has finished and its
failure has been reported.

## Timeouts

### The first attempt

```dart
final name = await ctx.wait(
  () => api.fetchName().timeout(const Duration(seconds: 5)),
);
```

`Future.timeout` limits the waiting, not the work behind it. Five seconds in,
the job ends `Failed(TimeoutException)` and the queue moves on, while the
request is still in flight and finishes later into nothing. A test sees both
halves: when the job ends, the fake has been called and has not returned; a few
milliseconds later it returns, with nobody waiting for it. For a result that
can be abandoned this is the whole story, and the line above is enough.

### A timer wired to the device

For a device operation that must stop before the next job, connect a timer to
the device's cancellation mechanism and await the operation with `join`. In
this example, the hardware API completes with an error when its token is
cancelled, so a timeout fails the job:

```dart
Job<void> connect() => run<Idle, void>(
      key: 'connect',
      (ctx) async {
        final token = CancelToken();
        final timer = Timer(const Duration(seconds: 5), token.cancel);
        ctx.onCancel(token.cancel);
        try {
          await ctx.join(() => hw.open(cancelToken: token));
        } finally {
          timer.cancel();
        }
        ctx.emit(const Connected());
      },
    );
```

The `finally` block cancels the timer on every exit, and `ctx.onCancel` hands
the same token to a cancellation that comes from outside, so a cancelled job
stops the device as well. Whether the device actually stops, and which error it
returns, depends on that device's API. The five seconds cost the test nothing:

```dart
test('connect gives up after five seconds', () {
  fakeAsync((async) {
    final camera = CameraController(FakeCamera());

    final job = camera.connect()..ignore();
    async.elapse(const Duration(seconds: 5));

    expect(job.outcome, isA<Failed>());
    expect(camera.currentState, isA<Idle>());

    camera.close();
    async.flushTimers();
  });
});
```
