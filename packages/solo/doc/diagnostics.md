# Diagnostics

A controller and its jobs can say what they are doing: what a body logs, which
job changed the state, what a close is waiting for and how long a job ran past
its cancellation. Nothing on this page changes where an error goes;
[Errors](errors.md) is about that.

The sections of the page, by what the application needs:

| The application needs | What gives it | Section |
| --- | --- | --- |
| What a body and the engine have to say, in a log | `ctx.log`, `Solo.debug`, `Job.debug` | [Logs](#logs) |
| A log of every controller | `Solo.observer` | [Watching every controller](#watching-every-controller) |
| What holds `close()`, or a job that hangs | `pending` | [What is holding the controller](#what-is-holding-the-controller) |
| The jobs that ran on past their cancellation | A stamp from `whenCancelled` in an observer | [Why cancellation was slow](#why-cancellation-was-slow) |

The lines under some blocks are what the code prints.

## Logs

Three channels carry what a body and the engine have to say:

```dart
// Application data for the log hooks and observers.
ctx.log(('zoom', zoom));

// And the engine's own trace, when the queue itself needs watching.
Solo.debug = print;

// And the core's trace of each job: start, errors, cancellation, outcome.
Job.debug = print;
```

`ctx.log(data)` hands application data to the log hooks and observers as it is,
so a listener that wants a line makes one. `Solo.debug` traces the queue of the
controller and its lifecycle as well. Each job reports its start, its errors, a
cancellation that reaches it and its outcome to `Job.debug`, the channel of the
core; when both are set, both show.

`ctx.log` calls nothing on the way either. Where a line costs something to
build, log the callback that builds it, and let the level decide whether to
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

The body logs every time. The line is built, the call of `describe()` included,
only where somebody listens at that level. Everywhere else the message stays a
closure that nobody called.

## Watching every controller

An application wants a log of every controller in the process, not of one. It
installs an observer at startup:

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

The observer prints what the application put into its jobs and its state: the
key and the `describe` of each job, its outcome with the text of an error, and
the `toString` of the state. When the log leaves the device, for a crash
reporter, the observer prints only what the application chose to send, such as
the type of the state rather than the state.

`SoloObserver` is told what the controllers are told, `onStart`, `onFinish`,
`onError`, `onLog`, `onChange` and `onClose`, for every controller of the
process, and `onCreate` besides. `onUnanswered` and `onListenerError` stay with
the controller alone.

The hook `onChange` is given a `SoloTransition`: the state before and after,
the `job` the change belongs to, and a `revision` that grows by one per change.
The revision keeps two transitions in order even when a hook changed the state
again from inside the first. The `job` is the one whose `emit` made the change
or whose state handler returned it. It is `null` for an `externalSetState`, and
it is a child of the running job when the child made the change, not the root
the child belongs to. It answers who changed the state, which nothing outside
the engine can work out.

The observer is called before the corresponding hook of the controller. Each
call stands on its own: a controller hook that leaves out `super` does not
switch the observer off. An error either hook throws goes to the current zone.
It does not change the outcome of the job, stop the queue or keep the other
hook from running. A `Cancelled` a hook throws neither reaches the zone nor
cancels the job.

An observer only watches. Setting one changes nothing about where an error then
goes.

## What is holding the controller

`close()` waits for the running job, and a job can take its time. The
controller says what it is waiting for:

```dart
unawaited(
  controller.close().timeout(
    const Duration(seconds: 5),
    onTimeout: () => log('closing is held by ${controller.pending}'),
  ),
);
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
| `cancellable` | whether it accepts a cancellation it may refuse |
| `closing` | whether `close()` was called on the controller |
| `draining` | whether that `close()` is a drain, which lets the job run to its end |
| `queued` | the jobs queued behind it, which start only after it is over |

The snapshot computes one answer of its own as well.
`SoloPendingJob.cancellationPending` is true when either cancellation above is
there, the accepted one or the held one. A job whose `cancellable` is false
turns down the cancellations it may turn down, so nothing is pending on it
however often it was asked to stop.

A job is not the only thing a close waits for, and `pending` names the other
two:

- A drain waits for the queue as well. A group of `collect` or `accumulate`
  stays queued until its timing lets it go. With no job running, `pending` is a
  `SoloPendingQueue`, and its `jobs` are what the drain still has to run.
- With `SoloStream`, the stream closes after the engine and waits for every
  subscription to take its done event. One left paused holds `close()` with
  `isFinished` already true, and `pending` is a `SoloPendingStream`.

The three print alike, so the line above needs no switch:

```text
closing is held by SoloPending([stuck] in its body, closing, cancelled by Cancelled(closed))
closing is held by SoloPending(draining, 1 queued: [group])
closing is held by SoloPending(stream: a subscription has not taken its done event)
```

`null` says that nothing the controller knows of holds the close. A timer reads
`pending` between the steps of a close, and a synchronous hook reads it in the
middle of one: `onFinish` of the last job and `onClose` read `null`, though
`close()` has not come back yet.

The snapshot answers whoever asks, and the example above asks at `close()`. A
job that hangs earlier, while the screen is still open and nothing is closing,
is asked about by nobody. An observer can ask on its own. It arms a timer when
a job starts and disarms it when the job ends:

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
root job the controller is on. That is the same job, unless the one that hangs
is a child:

```text
stuck is still running: SoloPending([stuck] in its body)
held is still running: SoloPending([held] in its body, holding Cancelled(manual) back)
```

The timer is armed at the start because a hang has no other end: `onFinish`
never comes for a job that never finishes. The recipe of
[Why cancellation was slow](#why-cancellation-was-slow) works out its delay in
`onFinish`, and so it says nothing about a hang.

Five seconds is a fact of the domain, not of the engine. A job that opens a
camera may fairly take longer, and the number is the one this application is
willing to call late.

`Hangs` only reports: the job it names goes on running. A job that must stop at
its limit takes the limit itself, `enqueue(timeout: ...)`. The limit cancels
the job, and the job ends `Cancelled(timeout)` when its body reaches a
checkpoint or returns. A body that awaits a call bare reaches none until the
call returns, and the queue and `close()` wait for it all that time. Such a
call is stopped only by its own means, such as the token that
[A deadline of a job](cancellation.md#a-deadline-of-a-job) on the cancellation
page hands to the seek. `ctx.abandonable` around the call ends the wait and
leaves the call running.

The snapshot reports and does not diagnose. A long wait does not prove a
forgotten `ctx.abandonable`. A body inside an external call it has to see
through gives the same snapshot, with the phase `body`. A resource that takes
its time to release holds the job as long, and the phase is then `cleanup`. The
phase says where the job is, not why. While the body runs, the phase is `body`
whatever it waits on, and the engine does not guess.

## Why cancellation was slow

`SoloPendingJob` answers while the job is still running. The other half of the
question comes afterwards, where nobody is watching: which jobs ran on past the
cancellation that was meant to stop them, and for how long.

### The first attempt

An observer sees both ends of a job, so it measures the time between them:

```dart
// The first attempt: a lifetime hides a cancellation that ran on.
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

The time between `onStart` and `onFinish` is the lifetime of the job. A job
that takes 300 ms because the work takes 300 ms reports the same line as one
that was cancelled 10 ms in and ran to the end regardless. The second is the
one worth finding, and these two hooks cannot tell them apart.

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
runs. The number counts from the moment the job accepted the cancellation, not
from `cancel()`, to the outcome, children and cleanup included. A cancellation
that comes while a `ctx.uncancellable` section is open is accepted when the
section ends: a 100 ms section cancelled 10 ms in gives 0 ms, while the caller
of `cancel` or `close` waited 90 ms.

The number catches one mistake in particular. A body that waits on something
slow with a bare `await` notices the cancellation only when the wait is over.
The same call through `ctx.abandonable` stops waiting at once, and so does a
delay written as `ctx.pause`. A 300 ms wait, cancelled 10 ms in:

| how the body waits | the number |
| --- | --- |
| `await Future.delayed(...)` | 290 ms |
| `ctx.abandonable(() => Future.delayed(...))` | 0 ms |
| `ctx.pause(...)` | 0 ms |

Only the first row is a line in the log: the other two stay under the 50 ms
where the observer starts to report.

A job cancelled before it started reports nothing. `onStart` never runs for it,
so nothing was registered or stamped. There was no body to notice the
cancellation, and in a controller that covers every job dropped from the queue.

The observer reads `clock.now()` rather than `DateTime.now()`. Under
`fake_async` the first moves with the fake time and the second stands still, so
a test can check the same observer. The observer runs in the application, so
`package:clock` goes in its dependencies and not in the dev ones. It is a leaf
package, and `fake_async` depends on it anyway wherever the tests run.

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

The stamp above is read when the job ends. So the longest cancellation of all,
the one that never ends, is the one it says nothing about. Here the stamp
becomes a timer: `whenCancelled` arms it, the end of the job disarms it, and
what is left is the job that was asked to stop and did not:

```text
ignores has not stopped: SoloPending([ignores] in its body, cancelled by Cancelled(manual))
```

A job nobody cancelled arms nothing here, however long it runs: this observer
is about a cancellation that has not landed, not about slow work. A
`ctx.uncancellable` section holds back a cancellation that comes while it is
open, and `whenCancelled` fires when the section closes. The five seconds count
from there. A child the cancellation passed to gets a line of its own, and the
snapshot in it is of the root again.

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

Every hook goes to each of them in the order of the list, each call on its own.
One that throws hands its error to the zone, and the next is called all the
same. If the same observer is in the list twice, `SoloObserver.all` throws
`ArgumentError`.
