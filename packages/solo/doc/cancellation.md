# Cancellation

Cancellation is cooperative. Dart cannot interrupt an arbitrary `await`,
and marking a job cancelled does not stop its underlying I/O. Context
methods provide checkpoints so the body can respond to cancellation.

`ctx.join(action)` calls the operation and waits for its result. Before
starting it and before returning a successful result, it checks the job's
cancellation and state rules. For example, `ctx.join(Database.open)`
opens the database and returns it only after those checks succeed.

Use `ctx.wait(action)` when cancellation should end the wait immediately.
It also calls the operation and returns its result on success. Choose the
method according to what may happen to that operation:

| Method | If the job accepts cancellation while waiting |
| --- | --- |
| `ctx.wait(action)` | Throws `Cancelled` without waiting for the operation to finish. |
| `ctx.join(action)` | Waits for the operation; checks cancellation before returning a successful result. |
| `ctx.uncancellable(action)` | Holds ordinary cancellation until the action finishes; the next checkpoint throws it. |

If an operation awaited by `join` fails, its error is thrown into the
body even if the job has accepted cancellation. The job's final outcome
still remains `Cancelled`. The cancellation check after `join` applies
to successful operation results.

`wait` suits a request whose result can be abandoned. The request can
continue after the job has finished and the next job has started.
`join` suits work that must finish before the queue proceeds, such as a
device command or resource release. Neither method stops the operation
itself.

## Stopping the underlying operation

Use `ctx.onCancel(callback)` to connect job cancellation to an operation's
own cancellation mechanism. This callback runs synchronously when the job
is marked cancelled. Combine it with `join` when the next job must wait
for the operation to stop.

For a player whose API accepts a cancellation token:

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

The token requests that the player stop seeking. `join` waits for that
request to finish, so a replacement seek starts only afterwards. This
depends on the player's API actually responding to the token.

`ctx.onCancel` returns a function that unregisters the callback. It is a
cancellation signal for the operation, whereas the `onCancel` parameter
of `run` computes a final controller state after the job's cleanup.

## Protecting a step or a whole job

Use `ctx.uncancellable(action)` for a step that must complete once started,
such as committing a transaction. Manual cancellation, parent cancellation
and closing are held while the action runs. The job is not marked by
those requests yet, so its cancellation callbacks and child cancellation
cascade are also delayed.

When the outermost section finishes, a held request is applied. The next
checkpoint throws `Cancelled`; ordinary code immediately after the call
can still execute. Keep all required work inside the section and always
await it. An unawaited section can outlive the job and lose a held request.
Sections can nest.

`cancellable: false` on a job refuses these requests altogether. Queue
removal normally preserves such jobs, but `force: true` and `close()`
can discard them before they start. `close()` waits for a running
non-cancellable job.

Neither mechanism disables state rules. A job whose `W` or `keepWhile`
no longer matches is still cancelled. A job that must work in every state
needs the base type `S` and no `keepWhile` restriction.

## Ordinary await and context lifetime

Use context waiting methods for operations during the body, and
`ctx.check()` between steps of a loop that has no asynchronous operation
to wrap. A plain `await` does not respond to job cancellation and can
delay completion and `close()` indefinitely.

Plain `await` is appropriate when intentionally waiting through
cancellation, including inside cleanup or inside an `uncancellable`
section. Cancellation-aware waiting methods reject a job that is already
cancelled, so they cannot perform its cleanup.

Do not retain a context to start work after its job ends. Methods such as
`emit`, `run`, `each`, `wait`, `join` and `uncancellable` then throw
`StateError`. Reads and `check` remain available after normal completion;
after cancellation they still throw `Cancelled`. During registered cleanup,
state reads and body operations are unavailable. Capture the resources
needed for cleanup in its closure. `log`, `job`, cleanup registration,
`disown` and `unattended` remain available during cleanup. `log` itself
does not throw on cancellation or completion.

## Cancellation details

`Cancelled` includes `reason`, `started`, an optional `description` and
the cancellation stack trace. `started: false` means the body never ran.
Reasons extend `CancelReason`. The built-in types include
`ManualCancelReason`, `ParentCancelReason`, `HandlerCancelReason`,
`ChainCancelReason`, `RulesCancelReason` and `ClosedCancelReason`.
Inspect the type; `name` is a display label, not an equality key.

You can extend `CancelReason` to carry application data, then pass it to
`job.cancel(reason: reason)` or throw
`Cancelled.by(reason: reason, started: true)` inside a body. Propagation
between jobs retains the original cancellation in the reason's `cause`.

`job.whenCancelled(callback)` registers a synchronous listener and returns
a function to unregister it. It fires when a running job accepts
cancellation or a job is dropped before starting. If a body cancels itself,
it fires after the body and children finish, before cleanup. Registration
after cancellation calls the listener immediately. Successful and failed
jobs release these listeners without calling them. An asynchronous
callback is not awaited; callback errors use the same reporting path as
`ctx.onCancel` errors.

## Cancelling and closing a controller

`cancelAll()` clears cancellable queued jobs, requests cancellation of the
running job and waits for it to finish. The controller continues accepting
work. `cancelAll(force: true)` also removes non-cancellable queued jobs;
`force` does not change whether the running job accepts cancellation.

`close()` stops accepting work, cancels every queued job with
`Cancelled(closed)` and requests cancellation of the running job. It waits
for that job, including children and cleanup, even if cancellation is
refused. Repeated calls return the same future. Later submissions return
already cancelled jobs rather than throwing, so callers do not need an
`isClosed` check before submitting.

Closing does not itself release resources owned by your application or
select a final application state. Put that work in a controller method
and await it before `close()`, as in the [camera example](camera.md). A state
handler of the cancelled job may still update state while closing.

Do not await `close()` or `cancelAll()` from the current job's body or
cleanup: either would wait for the very job making the call. A body can
finish by returning or cancel itself by throwing `Cancelled('reason')`.

### Closing with the queue run

`close()` drops what is queued. When the work already accepted has to
happen first — a last batch of events on its way out, a save that was
just asked for — close with a drain:

```dart
await controller.close(mode: SoloCloseMode.drain);
```

No new root job is taken from the call onwards, and the ones already in
the queue run by the usual rules: in order, with their children, their
cleanup, and an accumulation window waited out where there is one. A
plain `close()` over a running drain stops it where it is, and the same
future everybody holds completes after that.

Running the queue is not a promise of delivery. A drained job can still
fail or be turned down by its rules. A buffer that keeps events until the
sending is confirmed is built on top of this, not inside it.
