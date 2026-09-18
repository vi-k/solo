# Cancellation

Cancellation is cooperative. Dart cannot interrupt an arbitrary `await`, and
marking a job cancelled does not stop its underlying I/O. The context gives the
body checkpoints to answer at, and the one you pick decides what happens to the
operation behind it:

```dart
(ctx) async {
  // The wait ends the moment cancellation is accepted. The request may
  // still be in flight; whatever it returns is dropped.
  final name = await ctx.wait(() => api.load(id));

  // Waited out whatever happens, and only afterwards does the
  // cancellation come out in place of the value.
  final handle = await ctx.join(() => device.open());
  ctx.onDispose(handle.close);

  // Nothing marks the job at all while this runs.
  await ctx.uncancellable(() => payment.commit());

  // Nothing to wrap: a checkpoint standing on its own.
  ctx.check();
  print(name);
}
```

| Method | If the job accepts cancellation while waiting |
| --- | --- |
| `ctx.wait(action)` | Throws `Cancelled` without waiting for the operation to finish. |
| `ctx.join(action)` | Waits for the operation to finish, then throws `Cancelled` in place of a successful result. |
| `ctx.uncancellable(action)` | Holds ordinary cancellation until the action finishes, then returns its result without throwing `Cancelled`; code after it runs until the next checkpoint, which throws it. |
| `ctx.check()` | Throws `Cancelled` when the job is already cancelled or its rules no longer hold. |

`wait` suits a request whose result can be abandoned. The request can continue
after the job has finished and the next job has started. `join` suits work that
must finish before the queue proceeds, such as a device command or opening a
device. Neither method stops the operation itself.

After a cancellation, a successful result of `join` turns into `Cancelled`, as
the table says; a failure does not. If the operation fails, `join` throws the
operation's own error, even after the job has accepted cancellation, so the
cancellation does not hide the failure. The job's final outcome is still
`Cancelled`.

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
        await ctx.wait(() => _player.seek(position));
        ctx.emit(ctx.state.copyWith(position: position));
      },
    );
```

`restart` cancels the running job, and `wait` lets go of the call at that
moment: the job ends and the next one starts. The seek it let go of is still
running on the device. Drag through three positions and all three seeks are on
the device at once — three starts, then three ends. What the device makes of
that is up to the device. The state says the last position all the same: only
the last job gets as far as `emit`, so the screen shows the position the user
asked for, whatever the device actually did.

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
cancellation mechanism; the callback runs synchronously when the job is marked
cancelled. The token asks the player to stop seeking, and `join` waits for it
to stop, so a replacement seek starts right after the one it replaces has
stopped, not at the end of it. This depends on the player's API actually
responding to the token. One that ignores it puts you back at the second
attempt: the seek dragged past runs to its end, and only then does the next one
start.

`ctx.onCancel` returns a function that unregisters the callback. It is a
cancellation signal for the operation, whereas the `onCancel` parameter of
`run` computes a final controller state after the job's cleanup.

## Protecting a step or a whole job

A payment, its receipt on the screen and its journal entry go together: once
the payment has gone through, the receipt has to be shown and the entry
written, whatever the job is asked in the meantime.

### The first attempt

```dart
SoloJob<void> commit(String entry) => run<Ready, void>((ctx) async {
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
SoloJob<void> commit(String entry) => run<Ready, void>((ctx) async {
      // The whole step waited out as one call.
      await ctx.join(() async {
        final receipt = await payment.commit();
        ctx.emit(ctx.state.copyWith(receipt: receipt));
        await journal.write(entry);
      });
    });
```

Both calls are now inside what `join` waits out, but the job is marked the
moment the cancellation arrives, not when the step is over. The step goes on as
the code of a cancelled job: the `emit` inside it is a checkpoint and throws,
and the entry is lost once more.

### One section for the step

```dart
SoloJob<void> commit(String entry) => run<Ready, void>((ctx) async {
      await ctx.uncancellable(() async {
        final receipt = await payment.commit();
        ctx.emit(ctx.state.copyWith(receipt: receipt));
        await journal.write(entry);
      });
      // ...the rest of the job, which cancellation can still stop.
    });
```

Manual cancellation, parent cancellation and closing are held while an
`uncancellable` action runs. The job is not marked by those requests yet, so a
checkpoint inside the section does not throw on them — the receipt reaches the
state — and its cancellation callbacks and child cancellation cascade are
delayed as well.

When the outermost section finishes, a held request is applied. The next
checkpoint throws `Cancelled`; ordinary code immediately after the call can
still execute. Keep all required work inside the section and always await it.
An unawaited section can outlive the job and lose a held request. Sections can
nest.

### A whole job

```dart
// A job that turns down every request it is allowed to turn down.
SoloJob<void> flush() => run<Ready, void>(
      cancellable: false,
      (ctx) => device.flush(),
    );
```

`cancellable: false` on a job refuses these requests altogether. While such a
job waits in the queue, `queue.remove`, `queue.removeWhere`, `queue.clear` and
`cancelAll()` leave it in place; called with `force: true`, they take it out.
`close()` drops it from the queue too, and waits for it once it is running.

Neither mechanism disables state rules. A job whose `W` or `keepWhile` no
longer matches is still cancelled. A job that must work in every state needs
the base type `S` and no `keepWhile` restriction.

## Ordinary await and context lifetime

An upload writes its chunks one at a time. Cancelled, it should stop after the
chunk in flight, and however it ends, the device buffer has to be flushed.

### The first attempt

```dart
SoloJob<void> upload(List<int> chunks) => run<Ready, void>((ctx) async {
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
`await`, which answers to nothing: `close()` during the second chunk waits for
the third and the fourth as well. The cleanup waits with `join`, which belongs
to the body, and the body is over by the time cleanup runs: `join` throws
`StateError`, the error reaches the controller's `onError` hook, and the flush
never happens. That does not depend on how the job ended — an upload that
finished `Done` leaves the buffer unflushed as well.

### Each wait in its place

```dart
SoloJob<void> upload(List<int> chunks) => run<Ready, void>((ctx) async {
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

`join` checks the cancellation before its operation as well as after it, so two
of them in a row leave no gap. `ctx.check()` is for the gaps nothing else
checks: after a plain `await` or an `uncancellable` section, when what follows
is not another checkpoint.

Do not retain a context to start work after its job ends. Methods such as
`emit`, `run`, `each`, `wait`, `join` and `uncancellable` then throw
`StateError`. Reads and `check` remain available after normal completion; after
cancellation they still throw `Cancelled`. During registered cleanup, state
reads and body operations are unavailable. Capture the resources needed for
cleanup in its closure. `log`, `job`, cleanup registration, `disown` and
`unattended` remain available during cleanup. `log` itself does not throw on
cancellation or completion.

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
  case Cancelled(:final reason, :final started):
    print('cancelled by ${reason.name}, started: $started');
  case _:
}
```

`Cancelled` includes `reason`, `started`, an optional `description` and the
cancellation stack trace. `started: false` means the body never ran. Reasons
extend `CancelReason`. The built-in types include `ManualCancelReason`,
`ParentCancelReason`, `HandlerCancelReason`, `ChainCancelReason`,
`RulesCancelReason` and `ClosedCancelReason`. Inspect the type; `name` is a
display label, not an equality key. Propagation between jobs retains the
original cancellation in the reason's `cause`.

`job.whenCancelled(callback)` registers a synchronous listener and returns a
function to unregister it. It fires when a running job accepts cancellation or
a job is dropped before starting. If a body cancels itself, it fires after the
body and children finish, before cleanup. Registration after cancellation calls
the listener immediately. Successful and failed jobs release these listeners
without calling them. An asynchronous callback is not awaited; callback errors
use the same reporting path as `ctx.onCancel` errors.

## Cancelling and closing a controller

A screen sends a batch of log lines per event. When the screen goes away, the
batches already queued still have to go out.

### The first attempt

```dart
logs.send(first);
logs.send(second);
logs.send(third);

// The screen goes away.
await logs.close();
```

`close()` cancels every queued job with `Cancelled(closed)` and requests
cancellation of the running one. The second and third batches never go out. The
first does, because it was already in flight, but its outcome is
`Cancelled(closed)` all the same: the job accepted the cancellation before the
batch arrived, and the outcome records that, not the delivery.

### Three ways to stop

```dart
// Clear the queue and stop the running job; the controller stays open.
await logs.cancelAll();

// The same, and nothing new is accepted afterwards.
await logs.close();

// Or run what is already queued first, and close after it.
await logs.close(mode: SoloCloseMode.drain);
```

`cancelAll()` clears cancellable queued jobs, requests cancellation of the
running job and waits for it to finish. The controller continues accepting
work. `cancelAll(force: true)` also removes non-cancellable queued jobs;
`force` does not change whether the running job accepts cancellation.

`close()` stops accepting work, cancels every queued job with
`Cancelled(closed)` and requests cancellation of the running job. It waits for
that job, including children and cleanup, even if cancellation is refused.
Repeated calls return the same future. Later submissions return already
cancelled jobs rather than throwing, so callers do not need an `isClosed` check
before submitting.

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
`close()`, as in the [camera example](camera.md), where `dispose()` closes the
hardware and emits `Disposed`. A state handler of the cancelled job may still
update state while closing.

### Closing from a job

Signing out ends the session: a call to the server, and then the controller
closes.

#### The first attempt

```dart
SoloJob<void> logout() => run<Ready, void>((ctx) async {
      await ctx.join(api.logout);
      await close();
    });
```

This never comes back. `close()` waits for the running job, including its
children and cleanup, and the running job is this one, waiting for `close()`.
`cancelAll()` waits the same way, and so does either of them awaited from the
job's cleanup. A body that only has to end itself needs no controller call at
all: it returns, or cancels itself by throwing `Cancelled('reason')`.

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
way, so the API hears a call nobody wanted. The [camera example](camera.md)
keeps the same order with its `dispose()`, but there the window stays empty:
the only place that submits work is the caller, waiting on that very line.

#### Queue the job and drain

```dart
Future<void> logout() async {
  run<Ready, void>((ctx) => ctx.join(api.logout));
  await close(mode: SoloCloseMode.drain);
}
```

Draining waits for the job the same way, and the door is shut from the `close`
line onwards: a job submitted while the call is in flight comes back
`Cancelled(closed)` without reaching the API at all. Whatever stood in the
queue before runs in either version — the logout job is queued behind it, and
the method waits its turn.
