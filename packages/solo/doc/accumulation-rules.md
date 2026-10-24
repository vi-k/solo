# Accumulation rules

[Accumulating events before a job starts](accumulation.md) gives four recipes.
This page gives the rules behind them: when a group is ready, which group an
event joins, and how a group's job starts, is cancelled, fails and ends on
`close()`. Its code takes two controllers of the recipes: `SettingsController`
of
[Settings saved on every flip of a switch](accumulation.md#settings-saved-on-every-flip-of-a-switch)
and `LogController` of
[One request per log line](accumulation.md#one-request-per-log-line).

The lines under the code are what the code prints.

## Choosing when a group is ready

Both factories accept an optional `timing`. The setting controls when a group
may start; `collect` still keeps every accepted event, and `accumulate` keeps
whatever its `merge` returns. For example,
`merge: (accumulated, incoming) => incoming` keeps only the latest value.

| | `debounce(duration)` | `throttle(duration)` | `throttle(duration, startAtOnce: false)` |
| --- | --- | --- | --- |
| The first group is ready | after `duration` with no new event | at once | after `duration` |
| An addition | restarts the timer | does not extend the timer | does not extend the timer |
| The wait is measured from | the last accepted event | the previous actual start | the previous start, or the moment the group appeared |

`AccumulationTiming.debounce(duration)` waits for a pause after the last
accepted event in each group. Every addition restarts the timer, even when
`merge` returns an unchanged value. With a 200 ms window, events at 0, 60 and
120 ms make the group ready at 320 ms. When the debounce timer fires, the group
is sealed even if another job is running. Later events form a new group; they
cannot change the sealed input. `collect` takes its snapshot then, and not
again. Continuous input can keep an open group waiting indefinitely. That wait
is the point in the search recipe: the request goes out when the typing stops.
The same wait is the reason the log collector takes a throttle instead: entries
that all have to arrive cannot wait on a pause that may never come.

`AccumulationTiming.throttle(duration)` allows the first group to start
immediately, then waits at least `duration` between actual starts of the same
accumulator. Additions during the interval gather in an open group without
extending the timer. When the interval ends, queued input is ready without
needing another event. The group accepts events until the queue takes it for
execution. An interval that passes with no event creates no job, and the group
of the next event is ready at once: the interval is counted from the previous
start, and it has run out.

`startAtOnce: false` counts the interval before the first group as well. When a
group of the accumulator appears, what it waits for depends on what the
accumulator already has:

- Nothing of its own queued or running, and no interval running: the group
  starts the interval when it appears and becomes ready when the interval ends,
  carrying everything written meanwhile.
- Nothing of its own queued or running, and an interval still running from the
  previous start: the group becomes ready when that interval ends. An interval
  already running is never restarted.
- Another group of its own, queued or running: the new group starts no interval
  and waits for the one that the start of the other group renews.

So a group that has waited its interval out and needs only the execution slot
is not pushed back by a later event, whatever the policy does with that event.
An interval that passes with no event leaves nothing running, and the next
group counts a whole interval from its own appearance.

Starting at once has a price when nothing is running. The queue takes the first
group on the next microtask, so a burst that does not fit in one synchronous
turn is split: the first event goes on its own and the rest wait out the whole
interval. A burst written while a job of the controller is running stays
together, however many turns it takes: under a throttle the group is sealed
when the queue takes it, and the queue cannot take it until that job ends.

Waiting has a price of its own. A single event on an idle accumulator is held
for the whole interval, and `close(mode: SoloCloseMode.drain)` waits with it —
a plain `close()` drops it. Take `startAtOnce: false` where the rate matters
more than the latency of the first event, as the log recipe does, and leave the
default where the first event is what the user is waiting for.

- **What uses an interval.** The start is the transition to running, before
  `onStart`. A group rejected by start rules consumes no throttle interval;
  cancellation from `onStart` does. With `startAtOnce: false` a refusal leaves
  the accumulator with nothing queued, so the next group to appear counts a
  full interval of its own from the moment it appears.
- **A slot held by another job.** If a group starts at 0 ms with a 200 ms
  interval, but another job holds the slot until 500 ms, the next group starts
  at 500 ms and the one after that cannot start before 700 ms. If the group's
  own handler, children or cleanup outlast the interval, the next group can
  start as soon as they finish.
- **What the queue shows.** Waiting groups stay visible in `queue.jobs`. The
  queue takes the first ready job in list order, allowing ready jobs to pass
  waiting groups. The list can therefore be nonempty while no job is running.
  Timing does not occupy the execution slot; once a handler starts, the queue
  waits for its children and cleanup before starting another root job.
- **Zero and negative durations.** Omitting `timing`, or passing
  `Duration.zero`, makes groups ready immediately and creates no timers,
  whatever `startAtOnce` says. Negative durations throw `ArgumentError`.
- **Timers.** A timing configuration can be shared by several accumulators;
  each accumulator has its own groups and throttle interval. Timer callbacks
  follow Dart's event-loop order: an event processed before a debounce callback
  can restart the timer; an event processed after it belongs to a new group. A
  busy event loop can delay callbacks and starts.

## Choosing where events join

```dart
// Three calls in a row: the queue takes nothing between them. Where A2
// lands is the policy's decision.
final a1 = settings.update(const SettingsPatch(theme: 'dark'));
settings.reload(); // B, an ordinary job of its own
final a2 = settings.update(const SettingsPatch(language: 'ru'));
```

Both factories accept an `AccumulationPolicy`, fixed when the accumulator is
created.

| Policy | Queue after the additions | Handle for A2 |
| --- | --- | --- |
| `adjacent` | `[A1, B, A2]` | A new job |
| `replace` | `[B, A(A1 + A2)]` | A1's existing job, moved behind B |
| `join` (default) | `[A(A1 + A2), B]` | A1's existing job |

`adjacent` adjoins an event to a group only when that group is at the queue's
tail. `replace` moves a group's job to the tail: it finds the last open queued
group of the same accumulator, looking past other jobs, and moves that job
behind them, so A ends up behind B. `join` joins the event to that same group
where it stands, so A keeps its place before B. Either way B stays in the
queue: the search only looks past it. Execution also depends on readiness: a
ready B can pass A while A waits for timing.

`join` is the default so that a group does not depend on what else is queued.
An entry written while another job waits in the queue still belongs in the
batch that is already there. Under `adjacent` it would start a second group
behind that job, and a throttle would hold that group for another interval: two
requests for entries written moments apart. The same two events would be one
group or two depending on what else the controller happened to be doing, which
is a decision no caller made. What `join` gives up is the boundary: the batch
keeps its place ahead of the job that arrived between.

Take `adjacent` where that boundary is the point:

- where `merge` throws away what it replaces and a job queued between two
  events has to run between them, as the command recipe does;
- where such a job changes what the accumulated input means.

Policies use the current queue. If B has already run, a waiting A may again be
at the tail, so a later event can join it with `adjacent`. Already separate
groups are never combined retroactively. A sealed debounce group is ineligible
for all three policies.

`replace` moves the job of the group it found to the tail, with the incoming
event added to that group. The handle is the one every addition to this group
got, the events already accepted stay in it, and a group that is already at the
tail keeps the place it has. Nothing is cancelled on the way, so no
cancellation callback runs in the middle of the move. `Solo.debug`, the
engine's own trace from [Logs](diagnostics.md#logs) on the diagnostics page,
says `move <job> to the tail`; there is no observer event, because no job
started or finished.

The move starts a fresh debounce window and preserves the accumulator's
throttle interval. It applies to a queued group, including one configured with
`cancellable: false` — a move is not a removal, and the flag has nothing to
refuse. A running group is never moved: it stops accepting events when the
queue takes it. The ordinary queue's `Policy.replace` has its own cancellation
rules; `AccumulationPolicy` is a separate enum.

The accumulator's identity determines which groups can combine. Two
accumulators with the same `key` remain separate. The key still labels their
jobs for the ordinary queue's search and policies. Creating a new accumulator
on every call prevents events from joining an existing one.

## Start, cancellation and errors

```dart
final group = logs.logEvent(const LogEntry('checkout opened'));
final same = logs.logEvent(const LogEntry('cart shown'));

// Everyone who added to this group holds the same handle...
print(identical(group, same));

// ...so cancelling it cancels the whole group, and each of them reads the
// same outcome.
await group.cancel();
switch (await same.done) {
  case Done():
    print('sent');
  case Failed(:final error):
    print('failed: $error');
  case Cancelled(:final reason):
    print('cancelled: $reason');
}
```

```text
true
cancelled: manual
```

Additions to one group share one handle, result and cancellation under every
policy, and cancelling it affects the whole group. `replace` moves the job
rather than building another, so the handle outlives the move: cancelling it
cancels the group wherever the job now stands, and there is no second handle to
await.

For the same reason a plain `then` on the group's job throws `StateError`, on
the first event as well. Each caller continues the job through `shared()`,
`group.shared().then(...)`, and cancelling what `shared()` returned ends that
branch alone. See
[A handle for each branch](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/chains.md#a-handle-for-each-branch).

All three policies operate on queued groups. A group stops accepting events
when debounce seals it or when it is taken from the queue, before `canStart`
and `onStart`. Events added from either callback go to a later group. The
handler runs with the configured working type and rules, and the group's job is
an ordinary job to the queue in every other way.

An accumulator creates no job until the first event. Without timing, if each
group finishes before the next event arrives, each event starts a separate job.
A `join` policy's search can scan the queue; `adjacent` only checks its tail.
`replace` also searches the queue.

`merge` must be synchronous and pure:

- It must not mutate either argument or call into the controller.
- If it throws, `add` throws the same error and the existing group, its job and
  its timer remain unchanged.
- Calling the same accumulator's `add` from within its `merge` throws
  `StateError`.
- After the callback the engine looks for the group again and writes the result
  only if the search finds the same group: if `merge` has cancelled its job or
  closed the controller, `add` throws `StateError`.

`canStart`, `keepWhile` and cancellation apply to the whole job, and the rules
themselves are in [State and rules](state.md#state-and-rules) on the state
page. A start rule that turns the job down cancels everything the group has
accumulated. The handler's result and errors follow the ordinary `Job`
contract; accepted cancellation still takes precedence over a later value or
error. The accumulator does not roll back partial external effects or resend
failed input automatically.

The recipe
[Settings saved on every flip of a switch](accumulation.md#settings-saved-on-every-flip-of-a-switch)
assumes one writer and an API future that completes when the write has actually
ended. `ctx.join` keeps the execution slot until that future completes, even
after cancellation, and that is what stops the next write from starting on top
of this one. A client timeout alone does not establish that a server has
stopped writing. A `save` that completes its future on a timeout hands the slot
back while the server is still writing, and the next group's write goes out
over an unfinished one. Which of the two the server keeps is then no longer the
queue's decision, and the screen and the server can end up disagreeing for
good. Cancellation can also prevent the final `emit` after the server has
accepted the write.

A deadline given to the accumulator with `timeout` is a cancellation, not a
client timeout: `ctx.join` keeps the slot until `save` completes, so the next
write still waits for this one to end. What the deadline costs is the final
`emit`. A group past its deadline is cancelled while the server is still
writing, ends `Cancelled(timeout)` once the write is stored, and never reaches
its `emit`. The state keeps the old settings, and the next group applies its
patch to them and writes the old values back over the change.

A group that writes a state of its own while it runs leaves that state behind
when it fails or is cancelled: once the cancellation is accepted `emit` throws,
and a `close()` in the middle of an upload leaves `Uploading(3)` for good. The
state handlers `ifFailed` and `ifCancelled` take it back, as they do for `job`.
They are not the handler of the group: a group calls one of them at most once,
however many events it holds, after its handler, its children and its cleanup.
The table
[Handler eligibility and errors](state.md#handler-eligibility-and-errors) on
the state page holds for the group as for any job:

```dart
sealed class UploadState {
  const UploadState();
}

final class Waiting extends UploadState {
  const Waiting();
}

final class Uploading extends UploadState {
  final int photos;

  const Uploading(this.photos);
}

final class UploadFailed extends UploadState {
  final Object error;

  const UploadFailed(this.error);
}

final class PhotoUploader extends Solo<UploadState> {
  final Future<void> Function(List<String> photos) _send;
  late final _photos = collect<UploadState, String, void>(
    (ctx, photos) async {
      ctx.emit(Uploading(photos.length));
      await ctx.abandonable(() => _send(photos));
      ctx.emit(const Waiting());
    },
    key: 'upload',
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 200)),
    ifFailed: (state, error, stackTrace) => UploadFailed(error),
    ifCancelled: (state, cancelled) => const Waiting(),
  );

  PhotoUploader(this._send) : super(const Waiting());

  Job<void> addPhoto(String path) => _photos.add(path);
}
```

```text
uploading: Uploading(3)
after close(): Waiting
a failed upload: UploadFailed(Bad state: offline)
```

A group that never starts calls neither state handler: one cancelled in its
window or while it waits in the queue, dropped by `clear`, still waiting when
the controller closes, or turned down by `canStart`. A group that `canStart`
has let through has started, even before its handler is called: a cancellation
in `onStart` calls `ifCancelled`, and the handler never sees the events.

Cancelling a queued debounce group removes its timer. Removing or clearing
throttle groups preserves an already started interval, so adding another event
cannot bypass the limit. That timer expires once; it is renewed when a group
actually starts, and with `startAtOnce: false` also when a group appears on an
accumulator that has none of its own queued or running.

`close()` cancels every timing timer, drops queued groups and cancels or waits
for the running job under the usual rules. It sends no final batch: a group
still waiting for its window is dropped, and its job, the one handle every
addition to it got, completes with `Cancelled(closed)`.
`close(mode: SoloCloseMode.drain)` is the other choice — it waits the
accumulation window out and runs the groups already queued, by the rules in
[Cancelling and closing a controller](cancellation.md#cancelling-and-closing-a-controller)
on the cancellation page. Neither mode takes anything new: an `add` after
`close()` returns a new job already completed with `Cancelled(closed)`; it does
not call `merge` or the handler. That holds under a drain for a group still
waiting for its window: an event is new data, so it does not join the group,
and the group goes out as it was at the `close`. A `Policy.droppable` call gets
its queued job back under a drain because it adds no work, and an event would
add some. Whatever the last batch has to carry is added before `close`. Once a
group completes, its internal input storage is released. A handler, result or
error that retains the input still owns those references.
