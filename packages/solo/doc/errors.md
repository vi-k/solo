# Errors and observation

State handlers and reporting hooks have different responsibilities.
`run(onError: ...)` computes a state after a job fails. The controller's
`onError` method and `SoloObserver.onError` receive errors for logging or
reporting, including errors from cleanup and abandoned operations.

A controller can override `onStart`, `onFinish`, `onError`, `onLog` and
`onChange`. For example, add an error hook to the profile controller:

```dart
final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  // ...the jobs from the quick start...

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    reportCrash(error, stackTrace);
  }
}
```

`SoloObserver` receives the same events across controllers, plus
`onCreate` and `onClose`. Install one at application startup:

```dart
final class LoggingObserver extends SoloObserver {
  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job finished ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, SoloTransition<Object> transition) =>
      print('${transition.job ?? 'external'}: ${transition.current}');
}

void main() {
  SoloBase.observer = LoggingObserver();
}
```

A change hook is given a `SoloTransition`: the state before and after,
the `job` whose `emit` made it — `null` for an `externalSetState`, and a
child of the running job rather than the root it belongs to — and a
`revision` that grows by one per change, so two transitions are in order
even when a hook changed the state again from inside the first. It
answers who changed the state, which nothing outside the engine can work
out.

The observer is called before the controller's corresponding hook.
Each call is independent; omitting `super` in a controller hook does not
disable the observer. An error thrown by either hook is sent to the
current Dart zone without changing the job's outcome, stopping the queue,
or preventing the other hook from running.

An observer only watches. Setting one changes nothing about where an
error then goes. To answer for the errors that have nowhere else to go,
set a handler:

```dart
SoloBase.errorHandler = (solo, job, error, stackTrace) =>
    Sentry.captureException(error, stackTrace: stackTrace);
```

One handler for the process, set once at startup. With it set, those
errors go to it instead of the zone; with nobody set, they go to the
zone. Separating the two is deliberate: answering for an error is a
responsibility somebody takes, not a side effect of switching a log on.

## What is holding the controller

`close()` waits for the running job, and a job can take its time. The
controller says what it is waiting for:

```dart
unawaited(controller.close().timeout(
  const Duration(seconds: 5),
  onTimeout: () => log('closing is held by ${controller.pending}'),
));
```

`SoloPending` names the job, its `phase` — body, children, cleanup — the
cancellation it carries, whether a `ctx.uncancellable` section is holding
one back, and whether the job was created with `cancellable: false` and
turns them down.

It reports and does not diagnose. A long wait does not prove a forgotten
`ctx.wait`: a body inside an external call looks the same, and so does a
resource that takes its time to release. What the engine cannot see is
`SoloPhase.unknown`, not a guess.

## Why cancellation was slow

```dart
final class SlowCancellations extends SoloObserver {
  // An Expando holds its key weakly, so a job takes its stamp with it and
  // there is nothing to clean up.
  final _markedAt = Expando<DateTime>('cancellation');

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) {
    // whenCancelled fires when the cancellation takes effect, not when
    // cancel() was called: a step held by ctx.uncancellable runs first.
    job.whenCancelled((_) => _markedAt[job] = clock.now());
  }

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) {
    final markedAt = _markedAt[job];
    if (markedAt == null) return;
    final delay = clock.now().difference(markedAt);
    if (delay > const Duration(milliseconds: 50)) {
      log('${job.key} ran ${delay.inMilliseconds} ms past its cancellation');
    }
  }
}
```

`SoloPending` says what is being waited for while the wait is on; this
says how long it took, once it is over, and it goes on saying it where
nobody is watching. The number is what the caller of `cancel` or `close`
sat through: from the moment the cancellation took effect to the outcome,
children and cleanup included.

It is worth watching for one mistake in particular. A body that waits on
something slow with a bare `await` holds the cancellation for the whole
wait, where the same call through `ctx.wait` gives it up at once. A 300 ms
wait, cancelled 10 ms in:

| how the body waits | reported delay |
| --- | --- |
| `await Future.delayed(...)` | 290 ms |
| `ctx.wait(() => Future.delayed(...))` | 0 ms |

A job cancelled before it started reports nothing, because `onStart`
never runs for it and so nothing was ever registered or stamped. There
was no body to notice the cancellation, and in a controller that covers
every job dropped from the queue.

`clock.now()` rather than `DateTime.now()`: under `fake_async` the first
moves with the fake time and the second stands still, so the same observer
can be checked by a test. `package:clock` is a leaf package and already
sits in the graph of anything that uses `fake_async`.

## Handled and unhandled failures

Accessing `job.done` or `job.value`, or calling `job.ignore()`, marks the
outcome as observed. A `Failed` outcome that nobody observes goes to the
job's creation zone through `Zone.handleUncaughtError`, in addition to
the error hooks. An installed observer alone does not mark outcomes as
observed. If reporting is handled elsewhere and the caller needs no result:

```dart
profile.load().ignore(); // the counterpart of Future.ignore
```

Errors from cleanup, cancellation callbacks and operations abandoned by
`wait` go to the reporting hooks. Without an overridden error hook or an
installed `SoloBase.errorHandler`, they fall back to the job's creation
zone. Such an
error can arrive after the job has already completed. It does not replace
an existing cancellation outcome. These reporting paths exclude
`Cancelled` itself.

An unhandled error of `job.value` or `ctx.run(child)` is still an unhandled
Future error under Dart's rules, even if that error is `Cancelled`.
Handle those futures with `await`, `catchError` or `ignore()` as appropriate.

## Catching errors inside a body

`Cancelled` implements `Exception`, so a broad `catch` also catches
cancellation. If a body needs its own error handling, pass cancellation
through first. This fragment handles a camera failure while preserving
cancellation:

```dart
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Cancelled {
  rethrow;
} on Object catch (error) {
  ctx.emit(Broken(error));
  rethrow;
}
```

Once a job has accepted cancellation, its outcome remains `Cancelled`
even if the body catches it. A catch block can still execute unwanted
work, such as retrying the operation. For a final failure state, prefer
the `onError` parameter of `run` rather than writing that correction
inside a broad catch.

## Errors in state rules

```dart
// A rule answers; it does not throw to refuse.
canStart: (state) => state.free > 0,
```

Where a rule throws anyway decides who hears about it:

| Where it throws | What happens |
| --- | --- |
| A start rule | The job fails and the queue continues. |
| A rule at a context checkpoint | The body receives the error. |
| Re-evaluation after a state update | Reported; it does not itself cancel the running body. |
| A check that also controls a final state handler | The handler is disabled. |

Re-evaluation errors fall back to the controller's creation zone when no
error hook and no `SoloBase.errorHandler` answers for them. In the root
Dart zone, an unhandled error can terminate the application. Install
error reporting and observe job outcomes according to your application's
needs.

## Background work and logs

```dart
// Work with a life of its own: the job neither waits for it nor cancels
// it, and its errors still reach the job's hooks.
ctx.unattended(() => analytics.send('zoom'));

// Application data for the log hooks and observers.
ctx.log(('zoom', zoom));

// And the engine's own trace, when the queue itself needs watching.
SoloBase.debug = print;
```

`ctx.unattended(action)` starts work that the job does not wait for or
cancel. Its errors are reported through the job's error hooks, even after
the job finishes, with the same zone fallback when no handler is installed.
Use it for work with an independent lifetime. Starting children from
this work is prohibited. A captured context still belongs to the original
job: `emit` can work while that job is active, but is rejected after
cancellation or completion. The background operation does not extend
the context's lifetime. A bare `unawaited(future)` does not provide
the error routing of `unattended`.

`ctx.log(data)` forwards application data to log hooks and observers as
it is, so a listener that wants a line makes one. `SoloBase.debug`
additionally traces the controller's internal queue and lifecycle
operations.
