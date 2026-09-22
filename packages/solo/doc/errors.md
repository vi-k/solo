# Errors and observation

State handlers and reporting hooks have different responsibilities.
`run(onError: ...)` computes a state after a job fails. The controller's
`onError` method and `SoloObserver.onError` receive errors for logging or
reporting, including errors from cleanup and abandoned operations, and
`onUnanswered` answers for the ones no outcome carries.

Five sections below open with the version the vocabulary of this API leads to —
the member named for the question you are asking, the call that says what you
mean — and say what that version does instead of what it was meant to do. The
version that works follows under its own heading.

## Reporting an error

A controller can override `onStart`, `onFinish`, `onError`, `onLog`, `onChange`
and `onClose`, and `onListenerError` for a listener that throws while being
notified. The profile controller wants its failures in the crash reporter.

```dart
final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  // ...the jobs from the quick start...

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      reportCrash(error, stackTrace);
}
```

The hook is told about every error its jobs run into — the failure of a body,
an error from cleanup or from an operation abandoned by `wait`, a rule that
threw instead of answering — and it is told once. It reports and returns, which
is all it is for: the hook answers for nothing, and overriding it moves no
error anywhere.

### Answering for an error

```dart
final class ProfileController extends Solo<ProfileState> {
  // ...the jobs and the reporting hook above...

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _apiFailures.add(error);
}
```

Most errors are carried by an outcome. The failure of a body becomes `Failed`,
where `run(onError: ...)` computes a state from it, and an outcome nobody
observes reaches the job's creation zone by itself. What no outcome carries is
the rest: an operation abandoned by `wait` that fails later, a disposer, an
`onCancel` callback, work handed to `ctx.unattended`. Somebody has to answer
for those, and the one asked is always the same: `onUnanswered`, on the
controller whose job it was.

The override above answers for them here, and they reach nothing else: this
controller owns what its jobs failed at and has said so. A controller that
writes no such override keeps the default body, which hands them on:

```dart
Solo.errorHandler = (solo, job, error, stackTrace) =>
    Sentry.captureException(error, stackTrace: stackTrace);
```

One handler for the whole process, set once at startup; it takes `solo` because
it serves every controller. With none set, these errors go to the zone the job
was created in. The error arrives at the hook, and the hook calls the handler,
so each controller decides for its own jobs whether the process-wide handler
hears them at all. An override keeps that route as well by calling
`super.onUnanswered(job, error, stackTrace)`.

Answering for an error is a responsibility somebody takes, not a side effect of
switching a log on. Setting a `SoloObserver` is not it either — watching is not
answering.

## Watching every controller

`SoloObserver` receives the same events across controllers, plus `onCreate`.
Install one at application startup:

```dart
final class LoggingObserver extends SoloObserver {
  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      print('$job started');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      print('$job finished ${job.outcome}');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      print('${transition.job ?? 'external'}: ${transition.current}');
}

void main() {
  Solo.observer = LoggingObserver();
}
```

A change hook is given a `SoloTransition`: the state before and after, the
`job` whose `emit` made it — `null` for an `externalSetState`, and a child of
the running job rather than the root it belongs to — and a `revision` that
grows by one per change, so two transitions are in order even when a hook
changed the state again from inside the first. It answers who changed the
state, which nothing outside the engine can work out.

The observer is called before the controller's corresponding hook. Each call is
independent; omitting `super` in a controller hook does not disable the
observer. An error thrown by either hook is sent to the current Dart zone
without changing the job's outcome, stopping the queue, or preventing the other
hook from running.

An observer only watches. Setting one changes nothing about where an error then
goes.

## What is holding the controller

`close()` waits for the running job, and a job can take its time. The
controller says what it is waiting for:

```dart
unawaited(controller.close().timeout(
  const Duration(seconds: 5),
  onTimeout: () => log('closing is held by ${controller.pending}'),
));
```

`SoloPending` is a snapshot of the job the controller is waiting for:

| Field | What it says |
| --- | --- |
| `job` | the job being waited for |
| `phase` | what it is doing: `body`, `children`, `cleanup` |
| `cancellation` | the cancellation it is marked with, or `null` |
| `heldCancellation` | the one an open `ctx.uncancellable` section holds back |
| `children` | how many children it is still waiting for |
| `inUncancellableSection` | whether such a section is open |
| `refusesCancellation` | whether it was created with `cancellable: false` |
| `closing` | whether `close()` was called on the controller |

Next to those fields the snapshot computes one answer of its own:
`pending.cancellationPending` is true when either cancellation above is there,
the marked one or the held one. A job with `refusesCancellation` turns down the
ones it may turn down, so nothing is pending on it however often it was asked
to stop.

`null` says that no job is running, not that nothing holds the close. A drain
waits for the queue as well, and a group of `collect` or `accumulate` stays
queued until its timing lets it go — `isDraining` is still true then. With
`SoloStream` the stream closes after the engine and waits for every
subscription to take its done event: one left paused holds `close()` with
`isFinished` already true.

It reports and does not diagnose. A long wait does not prove a forgotten
`ctx.wait`: a body inside an external call looks the same, and so does a
resource that takes its time to release. The phase says where the job is, not
why: a body is `body` whatever it waits on, and the engine does not guess.

## Why cancellation was slow

`SoloPending` answers while the wait is on, and somebody has to be there to
ask. The other half of the question comes afterwards, and in a place where
nobody is watching: which jobs ran on past the cancellation that was meant to
stop them, and for how long.

### The first attempt

```dart
final class SlowJobs extends SoloObserver {
  final _startedAt = Expando<DateTime>('start');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      _startedAt[job] = clock.now();

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final startedAt = _startedAt[job];
    if (startedAt == null) return;
    final ran = clock.now().difference(startedAt);
    if (ran > const Duration(milliseconds: 50)) {
      log('${job.key} ran ${ran.inMilliseconds} ms');
    }
  }
}
```

`onStart` and `onFinish` are the two ends of a job, and the difference between
them is its lifetime. A job that takes 300 ms because the work takes 300 ms
reports the same line as one that was cancelled 10 ms in and ran to the end
regardless. The second is the one worth finding, and these two hooks cannot
tell them apart.

### Stamping the cancellation

```dart
final class SlowCancellations extends SoloObserver {
  // An Expando holds its key weakly, so a job takes its stamp with it and
  // there is nothing to clean up.
  final _markedAt = Expando<DateTime>('cancellation');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) {
    // whenCancelled fires when the cancellation takes effect, not when
    // cancel() was called: a step held by ctx.uncancellable runs first.
    job.whenCancelled((_) => _markedAt[job] = clock.now());
  }

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final markedAt = _markedAt[job];
    if (markedAt == null) return;
    final delay = clock.now().difference(markedAt);
    if (delay > const Duration(milliseconds: 50)) {
      log('${job.key} ran ${delay.inMilliseconds} ms past its cancellation');
    }
  }
}
```

A job nobody cancelled is never stamped and never reported, however long it
runs. The number is what the caller of `cancel` or `close` sat through: from
the moment the cancellation took effect to the outcome, children and cleanup
included.

It is worth watching for one mistake in particular. A body that waits on
something slow with a bare `await` holds the cancellation for the whole wait,
where the same call through `ctx.wait` gives it up at once. A 300 ms wait,
cancelled 10 ms in:

| how the body waits | reported delay |
| --- | --- |
| `await Future.delayed(...)` | 290 ms |
| `ctx.wait(() => Future.delayed(...))` | 0 ms |

A job cancelled before it started reports nothing, because `onStart` never runs
for it and so nothing was ever registered or stamped. There was no body to
notice the cancellation, and in a controller that covers every job dropped from
the queue.

`clock.now()` rather than `DateTime.now()`: under `fake_async` the first moves
with the fake time and the second stands still, so the same observer can be
checked by a test. The observer runs in the application, so `package:clock`
goes in its dependencies and not its dev ones; it is a leaf package, and
`fake_async` depends on it anyway wherever the tests run.

## Handled and unhandled failures

A screen starts a job and goes on with its build: `profile.load()`, and nobody
waits for the result. Something still has to answer for a failure.

### The first attempt

```dart
final class Failures extends SoloObserver {
  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final outcome = job.outcome;
    if (outcome is Failed) {
      reportCrash(outcome.error, outcome.stackTrace);
    }
  }
}
```

Every failure now reaches the reporter, and the code reads as if failures were
answered for. They are not. Reading `job.outcome` says what happened without
taking responsibility for it, and an observer only watches: an installed
observer marks no outcome as observed. A `Failed` that nobody observed goes to
the job's creation zone through `Zone.handleUncaughtError` as well, where an
unhandled error can end the application — a moment after the crash report was
sent by hand.

### Observing the outcome

```dart
profile.load().ignore(); // the counterpart of Future.ignore
```

Accessing `job.done` or `job.value`, or calling `job.ignore()`, marks the
outcome as observed. `ignore()` is for the caller that needs no result and
leaves reporting to the hooks; a caller that needs the result takes it with
`await job.value` and answers for the error by catching it.

Errors from cleanup, cancellation callbacks and operations abandoned by `wait`
go to the reporting hooks, and the controller is asked to answer for them
through `onUnanswered`. Without an override of it or an installed
`Solo.errorHandler`, they fall back to the job's creation zone. Such an error
can arrive after the job has already completed. It does not replace an existing
cancellation outcome. A `Cancelled` that arrives this way — an abandoned action
that ended in one — is a late failure like any other to the hooks, and they see
it; the zone never does, whatever route leads there.

An unhandled error of `job.value` or `ctx.run(child)` is still an unhandled
Future error under Dart's rules, even if that error is `Cancelled`. Handle
those futures with `await`, `catchError` or `ignore()` as appropriate.

## Catching errors inside a body

A body drives the camera. It wants a failure state of its own, and a device
left half-open put back the way it was.

### The first attempt

```dart
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Object catch (error) {
  await hw.reset();
  ctx.emit(Broken(error));
  rethrow;
}
```

`Cancelled` implements `Exception`, so a broad `catch` takes it along with the
device failures. Cancel this job while `hw.open` is in flight: `join` throws
`Cancelled`, the catch reads it as a failure of the camera and resets a camera
this job never opened. `ctx.emit` on a cancelled job throws `Cancelled` in
turn, so `Broken` is never published and the `rethrow` under it never runs. The
outcome is the `Cancelled` it would have been anyway, and nothing in the hooks
or the zone mentions the reset.

### Letting cancellation through

```dart
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Cancelled {
  rethrow;
} on Object catch (error) {
  await hw.reset();
  ctx.emit(Broken(error));
  rethrow;
}
```

Cancellation leaves first, and what follows handles device failures only. Once
a job has accepted cancellation, its outcome remains `Cancelled` even if the
body catches it. For a final failure state, prefer the `onError` parameter of
`run` rather than writing that correction inside a broad catch.

## Errors in state rules

A job that needs a free slot asks for one in its start rule.

### The first attempt

```dart
canStart: (state) {
  if (state.free == 0) throw StateError('no free slot');

  return true;
},
```

A throw reads like a refusal and is a failure. The error goes to the reporting
hooks — a crash report for an ordinary "not now" — and the job ends `Failed`,
which reaches the creation zone as well unless somebody observes that outcome.
The `onError` handler of that same `run` does not answer for it either: a state
handler corrects the state of a job that ran, and this one never started. The
queue goes on to the next job.

### A rule answers

```dart
// A rule answers; it does not throw to refuse.
canStart: (state) => state.free > 0,
```

A rule that answers `false` is not an error: it cancels the job, and the
`Cancelled` carries the trace of the change it turned down — the `emit` or the
`externalSetState` whose state broke the rule. Taking that trace costs most of
what a change costs, so it is taken where assertions are on and left out of a
release build. `Solo.traceStateChanges = true` keeps it everywhere and `false`
drops it everywhere; without it the cancellation still carries the trace of the
place that noticed.

Where a rule throws anyway decides who hears about it:

| Where it throws | What happens |
| --- | --- |
| A start rule | The job fails and the queue continues. |
| A rule at a context checkpoint | The body receives the error. |
| Re-evaluation after a state update | Reported; it does not itself cancel the running body. |
| A check that also controls a final state handler | The handler is disabled. |

Re-evaluation errors fall back to the job's creation zone when neither an
override of `onUnanswered` nor a `Solo.errorHandler` answers for them. In the
root Dart zone, an unhandled error can terminate the application. Install error
reporting and observe job outcomes according to your application's needs.

## Background work and logs

A body sends an analytics event. The job has nothing to wait for and nothing to
cancel: the event either goes out or it does not.

### The first attempt

```dart
unawaited(analytics.send('zoom'));
```

`unawaited` says what is meant — this caller does not wait — and that is all it
says. The future's error belongs to nobody in the job: the hooks never see it,
`Solo.errorHandler` is never asked, and it surfaces as an unhandled error in
whatever zone the body happened to run in, with nothing there to name the job
it came from.

### Work with a life of its own

```dart
// Work with a life of its own: the job neither waits for it nor cancels
// it, and its errors still reach the job's hooks.
ctx.unattended(() => analytics.send('zoom'));
```

`ctx.unattended(action)` starts work that the job does not wait for or cancel.
Its errors are reported through the job's error hooks, even after the job
finishes, with the same zone fallback when no handler is installed. Use it for
work with an independent lifetime. Starting children from this work is
prohibited. A captured context still belongs to the original job: `emit` can
work while that job is active, but is rejected after cancellation or
completion. The background operation does not extend the context's lifetime.

### Logs

```dart
// Application data for the log hooks and observers.
ctx.log(('zoom', zoom));

// And the engine's own trace, when the queue itself needs watching.
Solo.debug = print;
```

`ctx.log(data)` forwards application data to log hooks and observers as it is,
so a listener that wants a line makes one. `Solo.debug` additionally traces the
controller's internal queue and lifecycle operations.
