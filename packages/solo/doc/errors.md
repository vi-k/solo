# Errors and observation

State handlers and reporting hooks have different responsibilities.
`run(ifFailed: ...)` computes a state after a job fails. The controller's
`onError` method and `SoloObserver.onError` receive errors for logging or
reporting, including errors from cleanup and abandoned operations, and
`onUnanswered` answers for the ones no outcome carries.

Five sections below open with the version habit or the vocabulary of this API
leads to — a broad `catch`, a `throw` for a refusal, the member named for the
question you are asking — and say what that version does instead of what it was
meant to do. The version that works follows under its own heading.

## Reporting an error

A controller can override `onStart`, `onFinish`, `onError`, `onUnanswered`,
`onLog`, `onChange` and `onClose`, and `onListenerError` for a listener that
throws while being notified. The profile controller wants its failures in the
crash reporter.

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
an error from cleanup or from an operation abandoned by `abandonable`, a rule
that threw instead of answering — and it is told once for each job. An error a
child throws and its parent lets through is the failure of both: the hook hears
it twice, and the `job` it is given tells the two calls apart. It reports and
returns, which is all it is for: the hook answers for nothing, and overriding
it moves no error anywhere.

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
where `run(ifFailed: ...)` computes a state from it, and an outcome nobody
observes reaches the job's creation zone by itself. What no outcome carries is
the rest:

- an operation abandoned by `abandonable` that fails later;
- what the job calls outside its body: a disposer, a `ctx.onCancel` callback, a
  `whenCancelled` listener, a state handler of `run`;
- a `keepWhile` that throws when a change of state re-checks it;
- work handed to `ctx.unattended`;
- the failure of a branch of `ctx.runAll` that the group did not throw;
- the failure of a body when a cancellation reaches the job afterwards, whether
  before the error leaves the body or while the job still waits for children of
  its own or runs its cleanup: whoever reads that outcome gets the
  cancellation.

Somebody has to answer for those, and the one asked is always the same:
`onUnanswered`, on the controller whose job it was.

The override above answers for them here, and they reach nothing else: this
controller owns what its jobs failed at and has said so. A controller that
writes no such override keeps the default body, which hands them to
`Solo.unansweredHandler`. The application sets that handler:

```dart
Solo.unansweredHandler = (solo, job, error, stackTrace) =>
    Sentry.captureException(error, stackTrace: stackTrace);
```

One handler for the whole application, set once at startup. With none set,
these errors go to the zone the job was created in. The error arrives at the
hook, and the hook calls the handler, so each controller decides for its own
jobs whether the application-wide handler hears them at all. An override keeps
that route as well by calling `super.onUnanswered(job, error, stackTrace)`.

The hook and the handler get one failure at a time. When the error is a
`ParallelWaitError` that `[a, b].wait` throws with several errors in it, each
failure comes in a call of its own, with its own stack trace. An uncaught
`Cancelled`, alone or inside one, does not come at all. The reporting hook
`onError` hears them the same way, one at a time, and each `Cancelled` too.

One error no outcome carries is missing from that list, and nobody is asked to
answer for it: the failure of a body that comes after its job has accepted a
cancellation — a call that `ctx.join` is still waiting out fails, say. The job
ends `Cancelled`, the reporting hook is told of the error, and it goes no
further. Most often it is the operation the cancellation stopped, throwing as
it stops, and the engine cannot tell a failure of the operation from that. A
body that catches such an error asks the job, not the error:
[Letting cancellation through](#letting-cancellation-through) has the `catch`.

Answering for an error is a responsibility somebody takes, not a side effect of
switching a log on. Setting a `SoloObserver` is not it either — watching is not
answering.

## Watching every controller

`SoloObserver` is told what the controllers are told — `onStart`, `onFinish`,
`onError`, `onLog`, `onChange` and `onClose` — for every controller of the
process, plus `onCreate`. `onUnanswered` and `onListenerError` stay with the
controller alone. Install one at application startup:

```dart
final class LoggingObserver extends SoloObserver {
  @override
  void onStart(Solo<Object> solo, Job<Object?> job) => print('$job started');

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
`job` the change belongs to, and a `revision` that grows by one per change, so
two transitions are in order even when a hook changed the state again from
inside the first. The `job` is the one whose `emit` made the change or whose
state handler returned it: `null` for an `externalSetState`, and a child of the
running job rather than the root it belongs to. It answers who changed the
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

While a job holds it, `pending` is a `SoloPendingJob`, a snapshot of that job:

| Field | What it says |
| --- | --- |
| `job` | the job being waited for |
| `phase` | what it is doing: `body`, `children`, `cleanup` |
| `cancellation` | the cancellation it has accepted, or `null` |
| `heldCancellation` | the one an open `ctx.uncancellable` section holds back |
| `children` | how many children it is still waiting for |
| `inUncancellableSection` | whether such a section is open |
| `refusesCancellation` | whether it was created with `cancellable: false` |
| `closing` | whether `close()` was called on the controller |
| `draining` | whether that `close()` is a drain, which lets the job run to its end |

Next to those fields the snapshot computes one answer of its own:
`SoloPendingJob.cancellationPending` is true when either cancellation above is
there, the accepted one or the held one. A job with `refusesCancellation` turns
down the ones it may turn down, so nothing is pending on it however often it
was asked to stop.

A job is not the only thing a close waits for, and `pending` names the other
two. A drain waits for the queue as well, and a group of `collect` or
`accumulate` stays queued until its timing lets it go: with no job running,
`pending` is a `SoloPendingQueue`, and its `jobs` are what the drain has still
to run. With `SoloStream` the stream closes after the engine and waits for
every subscription to take its done event: one left paused holds `close()` with
`isFinished` already true, and `pending` is a `SoloPendingStream`. The three
print alike, so the line above needs no switch:

```text
closing is held by SoloPending([stuck] in its body, closing, cancelled by Cancelled(closed))
closing is held by SoloPending(draining, 1 queued: [group])
closing is held by SoloPending(stream: a subscription has not taken its done event)
```

`null` says that nothing the controller knows of holds the close. A timer reads
`pending` between the steps of a close, a synchronous hook in the middle of
one: `onFinish` of the last job and `onClose` read `null`, though `close()` has
not come back yet.

The snapshot answers whoever asks, and the example above asks at `close()`. A
job that hangs earlier — while the screen is still open and nothing is
closing — is asked about by nobody. An observer can ask without being asked —
arm a timer when a job starts and disarm it when the job ends:

```dart
final class Hangs extends SoloObserver {
  // An Expando holds its key weakly, so a job takes its timer with it.
  final _timers = Expando<Timer>('hang');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) => _timers[job] = Timer(
        const Duration(seconds: 5),
        () => log('${job.key} is still running: ${solo.pending}'),
      );

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) => _timers[job]?.cancel();
}
```

A job that ends in time disarms its own timer and says nothing. One that does
not is named at the front of its line. The snapshot beside the name is of the
root job the controller is on, which is the same job unless the one that hangs
is a child:

```text
stuck is still running: SoloPending([stuck] in its body)
held is still running: SoloPending([held] in its body, holding Cancelled(manual) back)
```

The timer is armed at the start because that is the only end a hang has:
`onFinish` never comes for a job that never finishes. The recipe of
[Why cancellation was slow](#why-cancellation-was-slow) works out its delay
right there, on `onFinish`, and so says nothing about a hang.

Five seconds is a statement about the domain, not about the engine: a job that
opens a camera may fairly take longer, and the number is the one this
application is willing to call late.

`Hangs` only reports: the job it names goes on running. A job that must stop at
its limit takes the limit itself, `run(timeout: ...)`, and ends
`Cancelled(timeout)` when the limit runs out;
[A deadline of a job](cancellation.md#a-deadline-of-a-job) on the cancellation
page shows it.

The snapshot reports and does not diagnose. A long wait does not prove a
forgotten `ctx.abandonable`: a body inside an external call it has to see
through looks the same, and a resource that takes its time to release holds the
job as long, in its `cleanup` phase. The phase says where the job is, not why:
while the body runs the phase is `body`, whatever it waits on, and the engine
does not guess.

## Why cancellation was slow

`SoloPendingJob` answers while the job is still running. The other half of the
question comes afterwards, and in a place where nobody is watching: which jobs
ran on past the cancellation that was meant to stop them, and for how long.

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
    // whenCancelled fires when the job accepts the cancellation, not when
    // cancel() was called: an open ctx.uncancellable section ends first.
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
runs. The number is counted from the moment the job accepted the cancellation,
not from `cancel()`, to the outcome, children and cleanup included. A
cancellation that comes while a `ctx.uncancellable` section is open is accepted
when the section ends: a 100 ms section cancelled 10 ms in gives 0 ms, while
the caller of `cancel` or `close` waited 90 ms.

The number is worth watching for one mistake in particular. A body that waits
on something slow with a bare `await` notices the cancellation only when the
wait is over, where the same call through `ctx.abandonable` stops waiting at
once, and so does a delay written as `ctx.pause`. A 300 ms wait, cancelled 10
ms in:

| how the body waits | the number |
| --- | --- |
| `await Future.delayed(...)` | 290 ms |
| `ctx.abandonable(() => Future.delayed(...))` | 0 ms |
| `ctx.pause(...)` | 0 ms |

Only the first row is a line in the log: the other two stay under the 50 ms the
observer starts reporting at.

A job cancelled before it started reports nothing, because `onStart` never runs
for it and so nothing was ever registered or stamped. There was no body to
notice the cancellation, and in a controller that covers every job dropped from
the queue.

`clock.now()` rather than `DateTime.now()`: under `fake_async` the first moves
with the fake time and the second stands still, so the same observer can be
checked by a test. The observer runs in the application, so `package:clock`
goes in its dependencies and not its dev ones; it is a leaf package, and
`fake_async` depends on it anyway wherever the tests run.

### A cancellation that never lands

```dart
final class StuckCancellations extends SoloObserver {
  final _timers = Expando<Timer>('cancellation');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) => job.whenCancelled(
        (_) => _timers[job] = Timer(
          const Duration(seconds: 5),
          () => log('${job.key} has not stopped: ${solo.pending}'),
        ),
      );

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) => _timers[job]?.cancel();
}
```

The stamp above is read when the job ends, so the longest cancellation of all —
the one that never ends — is the one it says nothing about. Here the stamp
becomes a timer: `whenCancelled` arms it, the end of the job disarms it, and
what is left is the job that was asked to stop and did not:

```text
ignores has not stopped: SoloPending([ignores] in its body, cancelled by Cancelled(manual))
```

A job nobody cancelled arms nothing here, however long it runs: this observer
is about a cancellation that has not landed, not about slow work. Nor does it
see a job inside an open `ctx.uncancellable` section — that cancellation is
still held back, and `whenCancelled` has not fired. A child the cancellation
passed to gets a line of its own, and the snapshot in it is of the root again.

`Solo.observer` holds one observer, and this page has four to install by now.
`SoloObserver.all` puts them in one:

```dart
Solo.observer = SoloObserver.all([
  LoggingObserver(),
  Hangs(),
  SlowCancellations(),
  StuckCancellations(),
]);
```

Every hook goes to each of them in the order of the list, each call on its own:
one that throws hands its error to the zone, and the next is called all the
same. The same observer twice in the list, and `SoloObserver.all` throws
`ArgumentError`.

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
sent.

### Observing the outcome

```dart
profile.load().ignoreFailure(); // the counterpart of Future.ignore
```

Accessing `job.done` or `job.value`, or calling `job.ignoreFailure()`, marks
the outcome as observed. `ignoreFailure()` is for the caller that needs no
result and leaves reporting to the hooks; a caller that needs the result takes
it with `await job.value` and answers for the error by catching it. One failure
it cannot catch: if the load fails and a cancellation reaches the job
afterwards, whether before the error leaves the body or while the job still
waits for children of its own or runs its cleanup, `await job.value` throws the
`Cancelled`, and the failure goes to `onUnanswered` like the errors below.
`ignoreFailure()` silences that one too.

Errors from cleanup, cancellation callbacks and operations abandoned by
`abandonable` go to the reporting hooks, and the controller is asked to answer
for them through `onUnanswered`. Without an override of it or an installed
`Solo.unansweredHandler`, they fall back to the job's creation zone. Such an
error can arrive after the job has already completed. It does not replace an
existing cancellation outcome. A `Cancelled` that arrives this way — an
abandoned action that ended in the cancellation of another job, say — is told
to the reporting hooks, and nobody is asked to answer for it: it reaches
neither `onUnanswered` nor `Solo.unansweredHandler` nor the zone. The job's own
cancellation, thrown back by such an action, is news to nobody and is not
reported at all.

An unhandled error of `job.value` or `ctx.run(child)` is still an unhandled
Future error under Dart's rules, even if that error is `Cancelled`: that route
to the zone is Dart's own, not the engine's. Handle those futures like any
other: `await` them where the error is caught, or give them `onError` or
`Future.ignore()`. `job.ignoreFailure()` does nothing for a future already
taken.

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
device failures. Cancel this job while `hw.setZoom` is in flight: `join` waits
the call out and throws `Cancelled` in place of its result, and the catch reads
that as a failure of the camera. It resets a camera that opened and took its
zoom, and whoever cancelled the job waits for the reset as well.

The two lines under the reset change nothing. `ctx.emit` on a cancelled job
throws `Cancelled` in turn, so `Broken` never reaches the screen and the
`rethrow` under it never runs — and the outcome is the same `Cancelled` that
`rethrow` would have given. That is what makes the reset hard to notice: the
job ends exactly as a cancelled job should, neither the hooks nor the zone
mention anything, and the only trace is on the device.

### Letting cancellation through

```dart
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Object catch (error) {
  ctx.check();
  await hw.reset();
  ctx.emit(Broken(error));
  rethrow;
}
```

`ctx.check()` asks the job, not the error: it throws the job's `Cancelled` if
the job has accepted one, whatever the catch took, and what follows handles the
failures of a job nobody cancelled. The check is the first line of the catch.
Written under the reset, it would let out a cancellation that has already reset
the camera, and the cost of the first attempt would stay exactly where it was.

A clause for the error does less. `on Cancelled { rethrow; }` in front of the
broad clause, or `if (error is Cancelled) rethrow;` as its first line, holds
while every call in the `try` runs to its end, as these two do. A call that is
told to stop — through a token that `ctx.onCancel` cancels, the way
[The token](cancellation.md#the-token) on the cancellation page wires one — and
stops by throwing sends the catch an error of its own in place of the
`Cancelled`: `join` throws an error of its call as it is. The clause lets that
error by, and the camera is reset for a cancellation again.
[Catching errors of the operation](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cancellation.md#catching-errors-of-the-operation)
on the cancellation page of `async_job` takes that clause apart.

Asking the job has its other side: a camera that fails on its own once the job
has accepted a cancellation is not reset by this catch either, and no hook
hears of the failure. On a cancelled job the catch only lets the cancellation
out.

Once a job has accepted cancellation, its outcome remains `Cancelled` even if
the body catches it. For a final failure state, prefer the `ifFailed` parameter
of `run` rather than writing that correction inside a broad catch.

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
The state handler passed as `ifFailed` to that same `run` is not called for it:
a state handler computes the state after a job that ran, and this one never
started. The queue goes on to the next job.

### A rule answers

```dart
// A rule answers; it does not throw to refuse.
canStart: (state) => state.free > 0,
```

A rule that answers `false` is not an error: it cancels the job, and the
`Cancelled` carries a trace. A `keepWhile` re-checked on a change says no from
inside it, so that trace is the change — the `emit` or the `externalSetState`
whose state broke the rule. Taking it costs most of what a change costs, so it
is taken where assertions are on and left out of a release build:
`Solo.traceStateChanges = true` keeps it everywhere, `false` drops it
everywhere. Dropped, the trace is taken at the rejection instead, a couple of
engine frames above the same change.

Where a rule says no away from the change, the trace names the place that
noticed. `canStart` is asked once, as the job leaves the queue, and names the
queue. A job that breaks its own rule is not re-evaluated on its own `emit`: it
finds out at its next checkpoint — a `ctx.state`, a `ctx.check()`, a waiting
method — and without the trace of the change that checkpoint is all the
`Cancelled` has.

Where a rule throws anyway decides what becomes of the error:

| Where it throws | What happens |
| --- | --- |
| A start rule | The job fails and the queue continues. |
| A rule at a context checkpoint | The body receives the error. |
| Re-evaluation after a state update | Reported; it does not itself cancel the running body. |
| The same re-evaluation, on a job with a state handler | Reported, and the handler is disabled. |

A job with a state handler is re-evaluated after its body has ended as well;
[Handler eligibility and errors](state.md#handler-eligibility-and-errors) on
the state page is about that. Re-evaluation errors fall back to the job's
creation zone when neither an override of `onUnanswered` nor a
`Solo.unansweredHandler` answers for them. In the root Dart zone, an unhandled
error can terminate the application. Install error reporting and observe job
outcomes according to your application's needs.

## Background work and logs

A body sends an analytics event. The job has nothing to wait for and nothing to
cancel: the event either goes out or it does not.

### The first attempt

```dart
unawaited(analytics.send('zoom'));
```

`unawaited` says what is meant — this caller does not wait — and that is all it
says. The future's error belongs to nobody in the job: the hooks never see it,
`Solo.unansweredHandler` is never asked, and it surfaces as an unhandled error
in whatever zone the body happened to run in, with nothing there to name the
job it came from.

### Work with a life of its own

```dart
// Work with a life of its own: the job neither waits for it nor cancels
// it, and its errors still reach the job's hooks.
ctx.unattended(() => analytics.send('zoom'));
```

`ctx.unattended(action)` starts work that the job does not wait for or cancel.
Its errors stay with the job, even after the job finishes: the reporting hooks
are told, `onUnanswered` is asked to answer, and with nothing to answer they
end in the zone the job was created in. Use it for work with an independent
lifetime.

Unattended work is not the job, and the context refuses there whatever acts on
the job: `ctx.run`, `ctx.runAll`, `ctx.each` and `ctx.uncancellable` all throw
a `StateError` that names the call —
`cannot run a child inside unattended work` for `ctx.run`. That throw is an
error of the work it happened in, so it takes the road above, to the hooks, and
the job itself still ends `Done`.

A captured context still belongs to the original job: `emit` can work while
that job is active, but is rejected after cancellation or completion. The
background operation does not extend the context's lifetime.

### Logs

```dart
// Application data for the log hooks and observers.
ctx.log(('zoom', zoom));

// And the engine's own trace, when the queue itself needs watching.
Solo.debug = print;

// And the core's trace of each job: start, errors, cancellation, outcome.
Job.debug = print;
```

`ctx.log(data)` forwards application data to log hooks and observers as it is,
so a listener that wants a line makes one. `Solo.debug` additionally traces the
controller's internal queue and lifecycle operations. Each job reports its
start, its errors, a cancellation that reaches it and its outcome to
`Job.debug`, the core's channel; both sides show when both are set.

`ctx.log` calls nothing on the way either. Where the line costs something to
build, log the callback that builds it and leave the level to decide whether to
call it:

```dart
// A line that costs something to build: log the callback, not the line.
ctx.log(() => 'zoom to $zoom on ${device.describe()}');

@override
void onLog(Job<Object?> job, Object? message) {
  if (!logger.isLoggable(Level.FINE)) return;
  logger.fine(message is Object? Function() ? message() : message);
}
```

The body logs unconditionally, and `describe()` runs only where somebody
listens at that level. Everywhere else the message stays a closure nobody
called.
