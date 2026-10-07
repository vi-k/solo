# Cancellation

Cancellation is cooperative: the body of a job stops at a checkpoint of its
context, and the checkpoint you pick decides what happens to the operation
behind it. The checkpoints are those of `async_job`, and
[its cancellation page](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cancellation.md)
takes each of them apart.

| Method | If the job accepts cancellation while waiting |
| --- | --- |
| `ctx.abandonable(action)` | Throws `Cancelled` without waiting for the operation to finish. |
| `ctx.join(action)` | Waits for the operation to finish, then throws `Cancelled` in place of a successful result. |
| `ctx.uncancellable(action)` | Holds ordinary cancellation until the action finishes, then returns its result without throwing `Cancelled`; code after it runs until the next checkpoint, which throws it. |
| `ctx.pause(duration)` | Throws `Cancelled` at once, and cancels its timer. |
| `ctx.check()` | Throws `Cancelled` when the job is already cancelled or its rules no longer hold. |

A controller adds two things. Its queue waits for the running job, so the
choice of a checkpoint is also a choice of when the next job starts.
`abandonable` suits a request whose result can be abandoned: the request can
continue after the job has finished and the next job has started. `join` suits
work that must finish before the queue proceeds, such as a device command or
opening a device.

And a job of a controller is cancelled in two ways. A request — `cancel()`, the
cancellation of a parent, `close()`, a deadline given with `timeout` — is the
ordinary cancellation of the table: an `uncancellable` section holds it back,
and a job created with `cancellable: false` refuses it. The other kind comes
from the job's own state rules, and neither a section nor `cancellable: false`
stops it. Both are taken apart below.

Four sections below open with the version this vocabulary leads to — the method
whose name sounds like the requirement, or a plain `await` — and say what it
does instead of what it was meant to do. Where the next version repairs that
and brings a fault of its own, it stands as a second attempt. The version that
works follows under its own heading.

## Stopping the underlying operation

A player seeks while the user drags the slider, and every new position replaces
the last. The device has to be done with one seek before the next starts, and
the position the user lands on must not wait for the ones dragged past.

### The first attempt

```dart
Job<void> seek(Duration position) => run<Ready, void>(
      key: 'seek',
      policy: Policy.restart,
      (ctx) async {
        // Ends the moment the next seek cancels this one.
        await ctx.abandonable(() => _player.seek(position));
        ctx.emit(ctx.state.copyWith(position: position));
      },
    );
```

`restart` cancels the running job, and `abandonable` lets go of the call at
that moment: the job ends and the next one starts. The seek it let go of is
still running on the device. Drag through three positions and all three seeks
are on the device at once — three starts, then three ends. What the device
makes of that is up to the device. The state says the last position all the
same: only the last job gets as far as `emit`, so the screen shows the position
the user asked for, whatever the device actually did.

### The second attempt

```dart
Job<void> seek(Duration position) => run<Ready, void>(
      key: 'seek',
      policy: Policy.restart,
      (ctx) async {
        // Waited out, so the device never runs two seeks at once.
        await ctx.join(() => _player.seek(position));
        ctx.emit(ctx.state.copyWith(position: position));
      },
    );
```

The device no longer gets two seeks at once, but nothing tells it that a seek
is obsolete. The seek the user dragged past runs to its end; the job queued
behind it is removed by `restart` before it starts; only then does the last
seek begin. The job that waited the first seek out still ends `Cancelled`:
waiting the call out does not make its result count.

### The token

```dart
Job<void> seek(Duration position) => run<Ready, void>(
      key: 'seek',
      policy: Policy.restart,
      (ctx) async {
        final token = CancelToken();
        ctx.onCancel(token.cancel);
        // Wait for the device to stop before another seek starts.
        await ctx.join(() => _player.seek(position, cancelToken: token));
        ctx.emit(ctx.state.copyWith(position: position));
      },
    );
```

`ctx.onCancel(callback)` connects job cancellation to an operation's own
cancellation mechanism, here the `CancelToken` of the player's API, which is
not a type of this package; the callback runs synchronously when the job
accepts the cancellation. The token asks the player to stop seeking, and `join`
waits for it to stop, so a replacement seek starts right after the one it
replaces has stopped, not at the end of it. This depends on the player's API
actually responding to the token. One that ignores it puts you back at the
second attempt: the seek dragged past runs to its end, and only then does the
next one start.

A player that stops its seek by throwing hands that error to `join`, and `join`
throws it as it is. The job still ends `Cancelled`, and the controller's
`onError` hook is told of an error for every seek dragged past. Put the call in
a `try` and make `ctx.check()` the first line of its `catch`, and the
cancellation comes out instead of the player's error:
[Asking the job](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cancellation.md#asking-the-job)
on the cancellation page of `async_job` has that `catch`.

`ctx.onCancel` returns a function that unregisters the callback. Its namesake,
the `onCancel` parameter of `run`, is a state handler: it computes the state
the controller is left in once the cancelled job has cleaned up.
[State after failure or cancellation](state.md#state-after-failure-or-cancellation)
on the state page is about it.

## Protecting a step or a whole job

A payment, its receipt on the screen and its journal entry go together: once
the payment has gone through, the receipt has to be shown and the entry
written, whatever the job is asked in the meantime.

### The first attempt

```dart
Job<void> commit(String entry) => run<Ready, void>((ctx) async {
      // Each call waited out, whatever happens.
      final receipt = await ctx.join(() => payment.commit());
      ctx.emit(ctx.state.copyWith(receipt: receipt));
      await ctx.join(() => journal.write(entry));
    });
```

`join` does wait the payment out, and then, as the table above says, throws
`Cancelled` in place of the result. Cancel the job during the payment: the
payment goes through, and neither the receipt nor the entry follows. The money
is taken with nothing to show for it.

Plain `await` on the calls fares no better: the `emit` between them is a
checkpoint, and on the cancelled job it throws.

### The second attempt

```dart
Job<void> commit(String entry) => run<Ready, void>((ctx) async {
      // The whole step waited out as one call.
      await ctx.join(() async {
        final receipt = await payment.commit();
        ctx.emit(ctx.state.copyWith(receipt: receipt));
        await journal.write(entry);
      });
    });
```

Both calls are now inside what `join` waits out, but the job accepts the
cancellation the moment it arrives, not when the step is over. The step goes on
as the code of a cancelled job: the `emit` inside it is a checkpoint and
throws, and the entry is lost once more.

### One section for the step

```dart
Job<void> commit(String entry) => run<Ready, void>((ctx) async {
      await ctx.uncancellable(() async {
        final receipt = await payment.commit();
        ctx.emit(ctx.state.copyWith(receipt: receipt));
        await journal.write(entry);
      });
      // ...the rest of the job, which cancellation can still stop.
    });
```

Manual cancellation, parent cancellation and closing are held while an
`uncancellable` action runs. The job does not accept those requests yet, so a
checkpoint inside the section does not throw on them — the receipt reaches the
state — and its cancellation callbacks and child cancellation cascade are
delayed as well.

When the outermost section finishes, the job accepts the request it held. The
next checkpoint throws `Cancelled`; ordinary code immediately after the call
can still execute. Keep all required work inside the section and always await
it. An unawaited section can outlive the job and lose a held request. Sections
can nest.

### A whole job

```dart
// A job that turns down every request it is allowed to turn down.
Job<void> flush() => run<Ready, void>(
      cancellable: false,
      (ctx) => device.flush(),
    );
```

`cancellable: false` on a job refuses the requests a section holds — manual
cancellation, parent cancellation and closing — altogether. While such a job
waits in the queue, `queue.remove`, `queue.removeWhere`, `queue.clear` and
`cancelAll()` leave it in place; called with `force: true`, they take it out.
`close()` drops it from the queue too, and waits for it once it is running.

Neither a section nor `cancellable: false` holds back the state rules of a job.
Its working type — the first type argument of `run`, `Ready` on this page — and
its `keepWhile` cancel it when the state stops fitting them, inside a section
too: if the state leaves `Ready` while `commit` above waits for the payment,
the next line of the section throws, and neither the receipt nor the entry
follows. A job that must go on in every state takes the whole state type of the
controller as its working type, and no `keepWhile`.
[State and rules](state.md#state-and-rules) on the state page is about both.

## Ordinary await and context lifetime

An upload writes its chunks one at a time. Cancelled, it should stop after the
chunk in flight, and however it ends, the device buffer has to be flushed.

### The first attempt

```dart
Job<void> upload(List<int> chunks) => run<Ready, void>((ctx) async {
      ctx.onDispose(() async {
        // The flush must finish before the queue moves on.
        await ctx.join(() => device.flush());
      });
      for (final chunk in chunks) {
        await device.write(chunk);
      }
    });
```

Each half uses the wait the other half needed. The loop waits with a plain
`await`, which answers to nothing: `close()` during the second of four chunks
waits for the third and the fourth as well. The cleanup waits with `join`,
which belongs to the body, and the body is over by the time cleanup runs:
`join` throws `StateError`, and the flush never happens. That does not depend
on how the job ended — an upload that finished `Done` leaves the buffer
unflushed as well. The error is told to the controller's `onError` hook and
then handed to `Solo.errorHandler`, or to the zone when no handler is set;
[Answering for an error](errors.md#answering-for-an-error) on the errors page
has the whole route.

### Each wait in its place

```dart
Job<void> upload(List<int> chunks) => run<Ready, void>((ctx) async {
      ctx.onDispose(() async {
        // Cleanup runs after the body, where the waiting methods are
        // gone: a plain await is the wait that works here.
        await device.flush();
      });
      for (final chunk in chunks) {
        // Checks before the write and after it.
        await ctx.join(() => device.write(chunk));
      }
    });
```

A plain `await` does not respond to job cancellation and can delay completion
and `close()` indefinitely. It is the right wait where waiting through
cancellation is the point: inside cleanup and inside an `uncancellable`
section. Cleanup runs after the body has ended, whatever the outcome, and the
waiting methods belong to the body: in a disposer they throw `StateError` even
for a job that ended `Done`.

A delay written as `await Future.delayed(...)` is such a plain `await`: a
cancelled job sits it out to its end, and `close()` waits with it.
`ctx.pause(duration)` is the delay that is a checkpoint: it ends the moment the
job accepts a cancellation, and its timer is cancelled with it.
[Letting time pass](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cancellation.md#letting-time-pass)
on the cancellation page of `async_job` compares the three ways to wait for
time.

`join` checks the cancellation before its operation as well as after it, so two
of them in a row leave no gap. `ctx.check()` is for the gaps nothing else
checks: after a plain `await` or an `uncancellable` section, when what follows
is not another checkpoint.

Do not retain a context to start work after its job ends. Methods such as
`emit`, `run`, `each`, `abandonable`, `join`, `pause` and `uncancellable` then
throw `StateError`. Reads and `check` remain available once the job is over,
and they remain checkpoints: after a cancellation they throw that `Cancelled`,
and after any other outcome they still ask the rules of the job. During
registered cleanup, state reads and body operations are unavailable. Capture
the resources needed for cleanup in its closure. `log`, `job`, cleanup
registration, `disown` and `unattended` remain available during cleanup. `log`
itself does not throw on cancellation or completion.

## Cancellation details

A reason of your own carries application data through the cancellation:

```dart
final class OutOfRange extends CancelReason {
  final Duration position;

  const OutOfRange(this.position);

  @override
  String get name => 'out of range';
}

// From outside the job:
await job.cancel(reason: OutOfRange(position));

// From inside its body:
throw Cancelled.by(reason: OutOfRange(position), started: true);

// And on the way out:
switch (job.outcome) {
  case Cancelled(reason: OutOfRange(:final position)):
    print('out of range at $position');
  case Cancelled(:final reason, :final started):
    print('cancelled by ${reason.name}, started: $started');
  case _:
}
```

`Cancelled` includes `reason`, `started`, an optional `description` and the
cancellation stack trace. `started: false` means the body never ran. Reasons
extend `CancelReason`. The built-in types are `ManualCancelReason`,
`ParentCancelReason`, `HandlerCancelReason`, `ChainCancelReason`,
`SiblingCancelReason`, `RulesCancelReason`, `ClosedCancelReason`,
`DuplicateCancelReason`, `ReplacedCancelReason` and `TimeoutCancelReason`.
Inspect the type, as the first case above does; `name` is a display label, not
an equality key. Propagation between jobs retains the original cancellation in
the reason's `cause`.

`job.whenCancelled(callback)` registers a synchronous listener and returns a
function to unregister it. The listener is called when a running job accepts
cancellation, from outside or from a body that throws `Cancelled`, or when a
job is dropped before starting. Registered on a job that is cancelled already,
it is called immediately; registered while the cancellation is still passing to
the children, it is called in its turn, after the listeners registered before
it. Successful and failed jobs release these listeners without calling them.
What a listener throws goes the way an error of cleanup goes, to the `onError`
hook and on to `Solo.errorHandler` or the zone, and so does what a
`ctx.onCancel` callback throws. An `async` listener is not awaited, and an
error of its future goes straight to the zone, past the hook.

## A deadline of a job

A seek the device has not finished in two seconds should stop, and the screen
should show the player offline. A seek the user dragged past leaves the state
as it is.

```dart
Job<void> seek(Duration position) => run<Ready, void>(
      key: 'seek',
      policy: Policy.restart,
      timeout: const Duration(seconds: 2),
      onCancel: (state, cancelled) =>
          cancelled.reason is TimeoutCancelReason ? const Offline() : state,
      (ctx) async {
        final token = CancelToken();
        ctx.onCancel(token.cancel);
        await ctx.join(() => _player.seek(position, cancelToken: token));
        ctx.emit(ctx.state.copyWith(position: position));
      },
    );
```

`timeout` gives the job a deadline of its own, and when it runs out the job is
cancelled the way `restart` cancels it: the token stops the seek, `join` waits
for the device, and the job ends `Cancelled(timeout)`. The deadline is a
cancellation of `async_job` with a `TimeoutCancelReason`, and
[A deadline](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cancellation.md#a-deadline)
on the cancellation page of `async_job` takes it apart.

A deadline that runs out is not the `TimeoutException` of `Future.timeout`.
With `.timeout(...)` on the call of `_player.seek` the exception is thrown into
the body, the job ends `Failed`, and it is the `onError:` of `run` that maps
the state. The `timeout:` of `run` ends the job `Cancelled`, so `onCancel:`
maps the state and `onError:` is not called. `onCancel:` takes every
cancellation, and a handler that is to tell the deadline from a seek dragged
past branches on the reason, as the one above does. `value` of such a job
throws that `Cancelled`, and a clause `on TimeoutException` around it catches
nothing.

The deadline is counted from the start of the body, not from the call: the time
a job waits in the queue does not count, and neither does the window of a
`collect` or an `accumulate`, whose deadline is one of each job they queue. A
deadline cancels its own job alone: the jobs queued behind it stay, and the
next one starts once this one has cleaned up. A call with `Policy.droppable`
that finds a live job with its key returns that job, and the `timeout` of the
call is lost with the rest of the call.

## Cancelling and closing a controller

A screen sends a batch of log lines per event. When the screen goes away, the
batches already queued still have to go out.

### The first attempt

```dart
logs.send(first);
logs.send(second);
logs.send(third);

// The first batch is on its way when the screen goes away.
await logs.close();
```

`close()` cancels every queued job with `Cancelled(closed)` and requests
cancellation of the running one. The second and third batches never go out. The
first does, because it was already in flight, but its outcome is
`Cancelled(closed)` all the same: the job accepted the cancellation before the
batch arrived, and the outcome records that, not the delivery.

### Three ways to stop

```dart
// Clear the queue and cancel the running job; the controller stays open.
await logs.cancelAll();

// The same, and nothing new is accepted afterwards.
await logs.close();

// Or run what is already queued first, and close after it.
await logs.close(mode: SoloCloseMode.drain);
```

`cancelAll()` clears cancellable queued jobs, requests cancellation of the
running job and waits for it to finish. The jobs it ends carry
`Cancelled(manual)`, or the reason passed as `cancelAll(reason: ...)`. The
controller continues accepting work. `cancelAll(force: true)` also removes
non-cancellable queued jobs; `force` does not change whether the running job
accepts cancellation.

`close()` stops accepting work, cancels every queued job with
`Cancelled(closed)` and requests cancellation of the running job. It waits for
that job, including children and cleanup, even if cancellation is refused;
`pending` says what it is waiting for, as
[What is holding the controller](errors.md#what-is-holding-the-controller) on
the errors page shows. Repeated calls return the same future. Later submissions
return already cancelled jobs rather than throwing, so callers do not need an
`isClosed` check before submitting.

`SoloCloseMode.drain` closes by running the queue instead of dropping it, and
that is the whole fix the first attempt needs: the three batches go out in
order, each ends `Done`, and the future `close()` returned completes after the
third. No new root job is taken from the call onwards, and the ones already in
the queue run by the usual rules: in order, with their children, their cleanup,
and an accumulation window waited out where there is one. A plain `close()`
over a running drain stops it, and the future
`close(mode: SoloCloseMode.drain)` returned completes after that. Running the
queue is not a promise of delivery: a drained job can still fail or be turned
down by its rules, and a buffer that keeps events until the sending is
confirmed is built on top of this, not inside it.

Closing publishes no state of its own: the controller stays on the state
published last, and once closing has finished that state can no longer change.
Resources owned by your application are not released either. Put the teardown
and the state the screen ends on in a controller method and await it before
`close()`, as in [Awaiting the disposal](camera.md#awaiting-the-disposal) of
the camera example, where `dispose()` closes the hardware and emits `Disposed`.
A state handler of the cancelled job may still update state while closing.

### Closing from a job

Signing out ends the session: a call to the server, and then the controller
closes.

#### The first attempt

```dart
Job<void> logout() => run<Ready, void>((ctx) async {
      await ctx.join(api.logout);
      await close();
    });
```

This never comes back. `close()` waits for the running job, including its
children and cleanup, and the running job is this one, waiting for `close()`.
`cancelAll()` waits the same way, and so does either of them awaited from the
job's cleanup. A body that only has to end itself needs no controller call at
all: it returns, or cancels itself by throwing `Cancelled('reason')`. The throw
cancels the job the way `cancel()` does: the cancellation passes to its
children, and its `ctx.onCancel` callbacks run.

#### The second attempt

```dart
Future<void> logout() async {
  await run<Ready, void>((ctx) => ctx.join(api.logout)).done;
  await close();
}
```

The job makes the call, and the method closes the controller once that job is
over. This one comes back, and it leaves a window open: the controller takes
work until the `close()` line. A job submitted while the call to the server is
in flight is accepted, starts once the logout is over and is cancelled on the
way, so the API hears a call nobody wanted. The camera example keeps the same
order with its `dispose()` in
[Awaiting the disposal](camera.md#awaiting-the-disposal), but there the window
stays empty: the only place that submits work is the caller, waiting on that
very line.

#### Queue the job and drain

```dart
Future<void> logout() async {
  run<Ready, void>((ctx) => ctx.join(api.logout)).ignoreFailure();
  await close(mode: SoloCloseMode.drain);
}
```

Draining waits for the job the same way, and the door is shut from the `close`
line onwards: a job submitted while the call is in flight comes back
`Cancelled(closed)` without reaching the API at all. Whatever stood in the
queue before runs in either version — the logout job goes to the end of it, and
the method waits its turn.

`ignoreFailure()` stands where the second attempt read `done`. Nobody waits for
the outcome of this job, and without `ignoreFailure()` a logout that fails
would reach the zone as an unhandled error. The controller's `onError` hook
hears that failure in either version, and the controller closes all the same.
