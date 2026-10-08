# Testing

A controller is tested through its jobs: a call queues one and returns it, and
the state it publishes arrives later. The examples below use `package:test`,
and all but the last drive the `load` of the controller from
[Quick start](https://github.com/vi-k/solo/blob/main/packages/solo/README.md#quick-start)
in the package README:

```dart
final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        ifFailed: (state, error, stackTrace) => Failure(error),
        ifCancelled: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.abandonable(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}
```

`ifFailed` and `ifCancelled` are the state handlers of `load`: the first turns
a failure into `Failure`, the second puts the state back to `Initial`.
`key: 'load'` with `Policy.droppable` is what makes a second call join the load
already in flight. The tests below read all three. The API the controller calls
is faked: twenty milliseconds after the call it answers with the name, or
throws the error it was given.

```dart
class FakeProfileApi implements ProfileApi {
  final String name;
  final Object? error;

  FakeProfileApi({this.name = 'Ada Lovelace', this.error});

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

Every section below opens with the version the vocabulary of the API and of
`package:test` leads to — the assertion right after the call, the `close` that
should let the work finish, the `await` inside `fakeAsync`, the expectation
inside a zone, the `timeout` on a call — and says what it does instead of what
it was written to do. The version that works follows under its own heading.

## Awaiting a job

The plainest test of a controller calls a method and looks at the state: after
`load()` the profile should be `Loaded`, with the name the API returned.

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
queue, its body never ran, and its `ifCancelled` handler was not called at all.
A load cancelled while it runs ends `Cancelled` as well, with `started: true`,
and the state it ends in is the one its `ifCancelled` handler published.

## Closing the controller

`close()` returns a future that completes once the controller has shut down. It
reads as the way to wait for the load without holding its job: await the
`close`, then look at the state.

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
way, cancelled where it was waiting, and its `ifCancelled` handler would
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

The next test is of a load that fails: the API throws, and the state should be
`Failure`. The test has no use for the job, so it lets the drain do the
waiting.

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
`Bad state: no network`, under a stack trace that names the line of the fake
that threw and a frame of the engine, and no line of the test. A test that does
not wait for the job at all pays more: the failure arrives after the test has
ended, and the runner says so —
`This test failed after it had already completed`, against the name of a test
that has already passed while a later one is running. With no later test still
running by then, the run is over before the failure arrives: nobody says
anything, and the run is green.

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
the test's business rather than the zone's. The read has to come before the job
ends: a failure nobody has asked about is reported as the job finishes, so a
test that holds the job, drains the controller and reads `done` afterwards is
red all the same. A job the test starts and drops on purpose says so with
`job.ignoreFailure()`, which marks it observed without waiting for it. Reading
`job.outcome` does not mark anything: it is a look at a field, and the field is
`null` until the job has finished.

One failure is out of reach of all three: that of a call the job has walked
away from. Cancel a load while the fake is still answering, or close the
controller on it, and `ctx.abandonable` lets go of the call. The job ends
`Cancelled`; the call fails twenty milliseconds later, and its error belongs to
no outcome. It goes to the zone the job was created in, the test's again, and
by then the test is over. A test that expects such an error sets
`Solo.unansweredHandler`, which takes it in place of the zone:
[Answering for an error](errors.md#answering-for-an-error) on the errors page.

## The order of what happened

`Policy.droppable` is there so that a second `load()` made while the first one
runs starts nothing of its own. The state cannot show that: it ends up `Loaded`
either way. The test has to see the order of what happened. Timing and ordering
are tested with `package:fake_async`, and what happened is collected by an
observer — one for every controller in the process.

### The first attempt

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
      'load Cancelled(duplicate)',
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
load Cancelled(duplicate)
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

That first line is the `onFinish` of the dropped job, and the only line it ever
gets: its body never ran, so there was no `onStart` for it, and its
`ifCancelled` handler was not called either — which is why no state of its own
stands next to it. The key in the line is the key the policy matched on, the
same `load` the other job carries, so it is the outcome that tells the two
apart. In that outcome `duplicate` is the reason, a `DuplicateCancelReason`,
which `Policy.droppable` gives to the job it drops; a `cancel()` from outside
says `manual` in the same place.

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
load Cancelled(duplicate)
state: Loaded
load Done(Ada Lovelace)
```

The cancelled line is the same dropped job as before, in the place the test
expected it; both calls returned the first job, which is what `identical`
checks. The observer is a process-wide static, so the test resets it — through
`addTearDown` and not a line at the end, for the reason in
[What one test leaves for the next](#what-one-test-leaves-for-the-next).

## Awaiting inside fakeAsync

A test under `fakeAsync` wants what the tests of the first sections had: the
outcome of the load, then the state. The habit from those sections is to await
`done`.

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
unwinds, and nobody is left to move the fake clock or even to run its
microtasks: the load never starts, and no timer inside will ever fire. The
expectation never runs, and the only sign is a timeout that reads like a
deadlock in the controller. Without the `await` in front of `fakeAsync` there
is not even that: the test ends at once and green, and neither line under the
first `await` has run.

### Elapsing instead of awaiting

```dart
test('load fills in the name', () {
  fakeAsync((async) {
    final profile = ProfileController(FakeProfileApi());

    final job = profile.load()..ignoreFailure();
    async.elapse(const Duration(milliseconds: 20));

    expect(job.outcome, isA<Done<String>>());
    expect(profile.currentState, isA<Loaded>());

    profile.close();
    async.flushTimers();
  });
});
```

The callback stays synchronous and reads `job.outcome` where the test above
awaited `done` — and `ignoreFailure()` is what stands in for that read: inside
`fakeAsync` nothing can be awaited, so a failure would reach the zone with no
one having observed it. The fake's twenty milliseconds are a `Future.delayed`,
that is a timer, and `elapse` is what gets past it: `flushMicrotasks()` alone
leaves the job with no outcome at all and the state on `Loading`. `close()` and
a last `flushTimers()` end the test with an empty clock; a controller left with
work in flight stays as it is, and `fakeAsync` says nothing about a timer
nobody fired. The flush also fires what a cancelled load left in flight, so a
call that fails late fails inside the test that made it.

Cancellation is the one thing here that no clock has to move for:

```dart
final job = profile.load();
async.flushMicrotasks();

job.cancel();
expect(job.outcome, isNull);

async.flushMicrotasks();
expect('${job.outcome}', 'Cancelled(manual)');
```

The job accepts the cancellation inside the call, and the outcome is still a
few microtasks away: the body has to leave its `abandonable` call, and the
`ifCancelled` handler has to run. On the line under the call the outcome is
`null`, and one `flushMicrotasks()` carries it to `Cancelled`. The first
`flushMicrotasks()` is the one from the section above — it lets the load leave
the queue, so what gets cancelled is a load that is running; one still in the
queue is dropped inside the call, with its outcome there on the next line.

`elapse` moves `clock.now()` along with the timers, so a recipe that stamps
time — the observer of
[Stamping the cancellation](errors.md#stamping-the-cancellation) on the errors
page — is tested here too, without the test waiting for any of it.

## What one test leaves for the next

`Solo.observer` is a static, so the journal of the test above is still
installed when the next test starts, unless something takes it away.

### The first attempt

```dart
test('a second load while the first one runs is dropped', () {
  final journal = Journal();
  Solo.observer = journal;

  // ...the test...

  Solo.observer = null;
});
```

The reset runs only when the test passes. `expect` reports a failure by
throwing `TestFailure`, so the first expectation that fails skips every line
under it, and the journal of a test that is over stays installed for the next
one — collecting lines nobody reads, and reporting on controllers it has never
seen.

### addTearDown

```dart
Solo.observer = journal;
addTearDown(() => Solo.observer = null);
```

`addTearDown` runs whether the test passed or failed. Four statics belong to
the process rather than to a controller, and each of them outlives a test the
same way: `Solo.observer`, `Solo.unansweredHandler`, `Solo.debug` and the
`Job.debug` of the core that is set next to it. All four start as `null`, and
`null` is what the tear-down above puts back.

## Assertions inside a zone

That an unread failure reaches the zone is a promise of the engine, and a test
of it needs a zone of its own to catch the failure in: left to the zone of the
test, the failure is what turns the test red.

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

The test passes, and it would pass with no failure reaching the zone at all.
The expectation in the handler saves nothing on its own: the handler is called
only when an error arrives. When none does it never runs, the test is green,
and nothing has been said about the zone.

The expectation in the body is no better off. A job reports to the zone it was
created in, so the controller has to be built inside `runZonedGuarded`, and the
expectation about its state comes inside with it. There it stops being an
expectation: `expect` reports a failure by throwing `TestFailure`, and a throw
from inside the zone belongs to the zone's handler, like any other error. With
a state other than `Failure` the handler would be handed that `TestFailure`,
compare it to `StateError`, find no match and report that on a line of the
handler rather than the line the expectation was on; and the `await` would
never return — the body's error went to the zone instead of into its future —
so the test would end on a timeout.

### Collecting in the zone, asserting outside

```dart
test('a failure nobody read reaches the zone', () async {
  final zoneErrors = <Object>[];
  late final ProfileController profile;

  await runZonedGuarded(
    () async {
      profile = ProfileController(
        FakeProfileApi(error: StateError('no network')),
      )..load();
      await profile.close(mode: SoloCloseMode.drain);
    },
    (error, stackTrace) => zoneErrors.add(error),
  );

  expect(profile.currentState, isA<Failure>());
  expect(zoneErrors, [isA<StateError>()]);
});
```

The zone collects, and the test asserts after it, on lines of its own: the
state and the errors both. `profile` is declared outside the zone for that and
assigned inside it, where the job has to be created. The drain is what makes
those lines safe to write: by the time `close` returns, the job has finished
and its failure has been reported.

## Timeouts

A call that never answers would hold the queue for good, so the job that makes
it gets a deadline. A test of the deadline has two things to show: that the job
ends on time, and what has become of the call by then.

### The first attempt

```dart
final name = await ctx.abandonable(
  () => api.fetchName().timeout(const Duration(milliseconds: 5)),
);
```

`Future.timeout` limits the waiting, not the work behind it. Five milliseconds
in, the job ends `Failed` with a `TimeoutException` and the queue moves on,
while the call is still in flight and finishes later into nothing. A test sees
both halves:

```dart
test('the deadline ends the job, not the call', () {
  fakeAsync((async) {
    final profile = ProfileController(FakeProfileApi());

    final job = profile.load()..ignoreFailure();
    async.elapse(const Duration(milliseconds: 5));

    expect(job.outcome, isA<Failed>());
    expect(async.pendingTimers, hasLength(1));

    async.elapse(const Duration(milliseconds: 15));
    expect(async.pendingTimers, isEmpty);

    profile.close();
    async.flushTimers();
  });
});
```

The timer still on the clock when the job is over is the fake's own delay: the
fake has been called and has not returned. It returns at its twentieth
millisecond, fifteen after the job was over, with nobody waiting for it. The
deadline is five milliseconds only because the fake answers in twenty: against
this fake a deadline of seconds never fires, and the job ends `Done`. For a
result that can be abandoned this is the whole story, and `Future.timeout`
alone is enough.

### A deadline of the job

For a device operation that must stop before the next job, give the job the
deadline with `timeout` and hand the device's cancellation mechanism to
`ctx.onCancel`. The example is the controller of a camera rather than of the
profile: `hw` is the device, `CancelToken` is the token of its API and not a
type of this package, and `Idle` and `Connected` are the states:

```dart
Job<void> connect() => run<Idle, void>(
      key: 'connect',
      timeout: const Duration(seconds: 5),
      (ctx) async {
        final token = CancelToken();
        ctx.onCancel(token.cancel);
        await ctx.join(() => hw.open(cancelToken: token));
        ctx.emit(const Connected());
      },
    );
```

Five seconds after the body starts, the job is cancelled the way `cancel()`
cancels it: `ctx.onCancel` cancels the token, and `join` waits for the device
to stop, so the next job starts after it. A cancellation that comes from
outside takes the same way, so a cancelled job stops the device as well.
Whether the device actually stops depends on that device's API. The hardware
API completes with an error when its token is cancelled, and `join` throws that
error, but the job is cancelled by then: it ends `Cancelled(timeout)`, not
`Failed`, nothing reaches the zone, and the test needs no `ignoreFailure()`.
The five seconds cost the test nothing; its `FakeCamera` is a device that never
answers on its own, so the deadline is what ends the call:

```dart
test('connect gives up after five seconds', () {
  fakeAsync((async) {
    final camera = CameraController(FakeCamera());

    final job = camera.connect();
    async.elapse(const Duration(seconds: 5));

    expect('${job.outcome}', 'Cancelled(timeout)');
    expect(camera.currentState, isA<Idle>());

    camera.close();
    async.flushTimers();
  });
});
```

`connect()` gives `run` no state handlers, so the state stays `Idle`. A `run`
with `ifCancelled` gets the deadline there, not in `ifFailed`. The timer the
core keeps for it is gone as soon as the job ends: `async.pendingTimers` is
empty after the five seconds.
[A deadline of a job](cancellation.md#a-deadline-of-a-job) on the cancellation
page tells a deadline from the other cancellations in that handler.
