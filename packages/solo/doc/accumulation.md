# Accumulating events before a job starts

Several events can share one queued job. `collect` keeps every event in a list;
`accumulate` combines each event with a single accumulated value. Both return a
`SoloAccumulator<E, T>`. Create it once in your controller, then call its
`add(event)` method from the controller's public methods.

The accumulator owns the input of a queued job. Adding an event does not run
the handler or change controller state. The group accepts events until it is
sealed: when debounce expires, or when the queue takes the job for execution
with other timing settings. The handler receives that input and an ordinary
`SoloContext<S, W>`; it changes state through `ctx.emit`.

## Accumulators and policies

```dart
// One list per group: every accepted event is kept, in order.
late final _logs = collect<Ready, LogEntry, void>(
  (ctx, events) => ctx.join(() => sink.write(events)),
);

// One value per group: merge decides what survives.
late final _patches = accumulate<Ready, Patch, void>(
  (ctx, patch) => ctx.join(() => store.apply(patch)),
  merge: (previous, incoming) => previous.merge(incoming),
  // Find this accumulator's open group anywhere in the queue and keep
  // its position, instead of looking only at the tail.
  policy: AccumulationPolicy.join,
);

SoloJob<void> log(LogEntry entry) => _logs.add(entry);
```

`accumulate` combines events with a synchronous `merge` function, which decides
what to retain; keeping only the latest value is one possible choice. Only the
queued job's handler updates controller state. A running group does not accept
new input, and groups can combine only when they belong to the same
accumulator.

| Accumulation policy | How input joins queued work |
| --- | --- |
| `AccumulationPolicy.adjacent` | Join a compatible group only at the queue's tail. |
| `AccumulationPolicy.join` | Join an existing queued group at its current position. |
| `AccumulationPolicy.replace` | Transfer input to a new job at the tail and cancel the old group. |

## Debounce and throttle

```dart
final class Search extends Solo<SearchState> {
  final SearchApi api;
  late final _queries = accumulate<SearchState, String, void>(
    (ctx, text) async {
      final results = await ctx.wait(() => api.search(text));
      ctx.emit(SearchState.results(results));
    },
    merge: (previous, incoming) => incoming,
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 300)),
    policy: AccumulationPolicy.join,
    key: 'query',
  );

  Search(this.api) : super(const SearchState.idle());

  SoloJob<void> query(String text) => _queries.add(text);
}
```

Set `timing` to delay a group's eligibility to start:

- `AccumulationTiming.debounce(duration)` waits for a pause in input.
- `AccumulationTiming.throttle(duration)` limits how often groups start,
  measuring the interval from the previous group's actual start.

These delays do not occupy the running job's position. Waiting groups remain in
`queue` and let other ready jobs pass. The handlers themselves still run one at
a time. Timing does not discard input: `collect` keeps accepted events and
`accumulate` keeps what `merge` returns. Without `timing`, or with
`Duration.zero`, groups are ready immediately.

The search controller above retains the latest query and waits for 300 ms
without new input before starting it. `SearchApi` and `SearchState` are
application types.

A search that has already started finishes before the next one starts. The
returned job exposes the outcome and cancellation, like other jobs. Closing
cancels waiting groups rather than flushing them. The sections below work
through grouping, ordering and the outcomes returned to individual callers.

## Combining settings changes

A patch describes which settings to change. A new value for a field replaces
the previous one; fields absent from the new patch are kept. Here, the settings
themselves cannot be null, so a null patch field means "leave this field
unchanged". A nullable setting that can be cleared needs a separate way to
represent whether the patch has a value.

```dart
import 'package:solo/solo.dart';

class Settings {
  final bool notifications;
  final String theme;
  final String language;

  const Settings({
    required this.notifications,
    required this.theme,
    required this.language,
  });
}

class SettingsPatch {
  final bool? notifications;
  final String? theme;
  final String? language;

  const SettingsPatch({
    this.notifications,
    this.theme,
    this.language,
  });

  SettingsPatch merge(SettingsPatch incoming) => SettingsPatch(
        notifications: incoming.notifications ?? notifications,
        theme: incoming.theme ?? theme,
        language: incoming.language ?? language,
      );

  Settings apply(Settings current) => Settings(
        notifications: notifications ?? current.notifications,
        theme: theme ?? current.theme,
        language: language ?? current.language,
      );
}

abstract interface class SettingsApi {
  Future<void> save(Settings settings);
}

class SettingsController extends Solo<Settings> {
  final SettingsApi _api;
  late final _updates = accumulate<Settings, SettingsPatch, void>(
    (ctx, patch) async {
      final next = patch.apply(ctx.state);
      await ctx.join(() => _api.save(next));
      ctx.emit(next);
    },
    merge: (accumulated, incoming) => accumulated.merge(incoming),
    key: 'settings',
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 200)),
  );

  SettingsController(this._api, Settings initial) : super(initial);

  SoloJob<void> update(SettingsPatch patch) => _updates.add(patch);
}
```

The first event becomes the accumulated value without calling `merge`. Each
following event calls `merge(accumulated, incoming)` synchronously from `add`,
before the handler starts. Only its result is kept. `false` is a specified
value and is preserved by the example's merge function.

For example, make three changes in one group:

```dart
Future<void> changeSettings(SettingsApi api, Settings initial) async {
  final controller = SettingsController(api, initial);
  try {
    final first = controller.update(
      const SettingsPatch(notifications: true),
    );
    final second = controller.update(const SettingsPatch(theme: 'dark'));
    final third = controller.update(const SettingsPatch(language: 'ru'));

    final outcomes = await Future.wait([
      first.done,
      second.done,
      third.done,
    ]);
    for (final outcome in outcomes) {
      print(outcome);
    }
  } finally {
    await controller.close();
  }
}
```

With the default policy, these calls share one `SoloJob<void>`. Its handler
saves one snapshot with all three changes, then emits that snapshot after 200
ms without another change. State still has its initial value before the handler
runs. Other ready jobs can run during the pause. Observing `.done` reports
`Done`, `Failed` or `Cancelled` without throwing.

If saving fails, the state is unchanged and the group fails. Retrying the
failed changes is the caller's decision; a later independent patch does not
automatically include them. This example assumes one writer and an API future
that completes when the write has actually ended. `join` keeps the queue slot
until that future completes, even after cancellation. A client timeout alone
does not establish that a server has stopped writing. Cancellation can also
prevent the final `emit` after the server has accepted the write.

## Commands where only the last one counts

A queue holding `resume` and then `pause` is about to do two things that cancel
each other out, and a `resume` arriving now makes the whole pair pointless: the
end of it is what a single `resume` would have reached. Nothing has to be taken
back, because an accumulator never creates the jobs to take back. `merge` keeps
the incoming command and drops the one it had:

```dart
import 'package:solo/solo.dart';

enum Command { resume, pause }

sealed class Playback {
  const Playback();
}

final class Playing extends Playback {
  const Playing();
}

final class Paused extends Playback {
  const Paused();
}

abstract interface class PlayerDevice {
  Future<void> resume();

  Future<void> pause();
}

final class Player extends Solo<Playback> {
  final PlayerDevice device;

  late final _transport = accumulate<Playback, Command, void>(
    key: 'transport',
    merge: (accumulated, incoming) => incoming,
    (ctx, command) async {
      switch (command) {
        case Command.resume:
          await ctx.join(device.resume);
          ctx.emit(const Playing());
        case Command.pause:
          await ctx.join(device.pause);
          ctx.emit(const Paused());
      }
    },
  );

  Player(this.device) : super(const Paused());

  SoloJob<void> resume() => _transport.add(Command.resume);

  SoloJob<void> pause() => _transport.add(Command.pause);
}
```

Three calls in a row — `resume`, `pause`, `resume` — leave one job in the
queue, and all three return the same handle. The device is told to resume once.
Nothing was queued and cancelled on the way.

This works because the commands are absolute: each one says what the end state
is, so the last one is the answer. Commands that build on each other — "ten
seconds further on" — are merged by adding them up, not by replacing.

`adjacent`, the default policy, joins a group only at the queue's tail, so a
job of another kind added between two commands is a boundary and the merging
stops there. That is what keeps the order with the rest of the work;
`AccumulationPolicy.join` gives it up and joins the group where it stands.

### When they are separate jobs after all

Where `resume` and `pause` are genuinely different operations rather than one
command with a value, they are ordinary jobs with keys of their own, and
`Policy.replace` does not help: it removes jobs with the same key, and these
two do not share one. The controller's own queue is what removes them:

```dart
SoloJob<void> resume() {
  queue.removeWhere(
    (job) => job.key == Command.resume || job.key == Command.pause,
  );

  return run<Playback, void>(key: Command.resume, (ctx) async {
    await ctx.join(device.resume);
    ctx.emit(const Playing());
  });
}
```

The queue never touches the running job: a `pause` that has already started
runs to its end whatever is removed behind it. Reach for `cancelAll()` — it
clears the queue and cancels the current job — or give both commands one key
and `Policy.restart`. Jobs created with `cancellable: false` are skipped unless
`force: true` is given.

## Collecting log entries

Logs need their individual entries and order. `collect` appends events to a
private list and gives the handler an unmodifiable snapshot at the moment the
group is sealed. It preserves duplicate events and does not copy the entire
list on every addition. The entries themselves are not cloned; use immutable
event objects.

```dart
import 'package:solo/solo.dart';

class LogEntry {
  final String message;

  const LogEntry(this.message);
}

abstract interface class LogApi {
  Future<void> send(List<LogEntry> entries);
}

class LogController extends Solo<int> {
  final LogApi _api;
  late final _logs = collect<int, LogEntry, void>(
    (ctx, entries) async {
      await ctx.join(() => _api.send(entries));
      ctx.emit(ctx.state + entries.length);
    },
    key: 'logs',
    policy: AccumulationPolicy.join,
    timing: AccumulationTiming.throttle(const Duration(seconds: 1)),
  );

  LogController(this._api) : super(0);

  SoloJob<void> logEvent(LogEntry entry) => _logs.add(entry);
}
```

Three calls before execution send one list of three entries. The first group is
ready immediately; later groups start at least one second apart. Entries
received during that interval are kept for the next group. This controller's
state counts entries whose send operation completed and whose handler reached
`emit`. The policy section explains why this example chooses `join` as its
accumulation policy.

Collecting entries does not guarantee delivery. A failed send, a cancelled
group or controller shutdown can leave them unsent. Durable storage, retries
and a final send on shutdown require an application protocol beyond this
accumulator.

## Choosing when a group is ready

```dart
// A pause in the input: every add restarts the 200 ms timer.
late final _queries = accumulate<Ready, String, void>(
  (ctx, text) => ctx.wait(() => api.search(text)),
  merge: (previous, incoming) => incoming,
  timing: AccumulationTiming.debounce(const Duration(milliseconds: 200)),
);

// A ceiling on how often groups start, measured from the actual start.
late final _metrics = collect<Ready, Metric, void>(
  (ctx, events) => ctx.join(() => api.send(events)),
  timing: AccumulationTiming.throttle(const Duration(seconds: 5)),
);
```

Both factories accept an optional `timing`. The setting controls when a group
may start; `collect` still keeps every accepted event, and `accumulate` keeps
whatever its `merge` returns. For example,
`merge: (previous, incoming) => incoming` keeps only the latest value.

`AccumulationTiming.debounce(duration)` waits for a pause after the last
accepted event in each group. Every addition restarts the timer, even when
`merge` returns an unchanged value. With a 200 ms interval, events at 0, 60 and
120 ms make the group ready at 320 ms. Continuous input can keep an open group
waiting indefinitely. When the timer fires, the group is sealed even if another
job is running. Later events form a new group; they cannot change the sealed
input. `collect` makes its unmodifiable snapshot once, when sealing.

`AccumulationTiming.throttle(duration)` allows the first group to start
immediately, then waits at least `duration` between actual starts of the same
accumulator. Additions during the interval gather in an open group without
extending the timer. When the interval ends, queued input is ready without
needing another event. The group accepts events until the queue takes it for
execution. No job is created for an empty interval.

The start is the transition to running, before `onStart`. A group rejected by
start rules consumes no throttle interval; cancellation from `onStart` does. If
a group starts at 0 ms with a 200 ms interval, but another job holds the slot
until 500 ms, the next group starts at 500 ms and the one after that cannot
start before 700 ms. If the group's own handler, children or cleanup outlast
the interval, the next group can start as soon as they finish.

Waiting groups stay visible in `queue.jobs`. The queue takes the first ready
job in list order, allowing ready jobs to pass waiting groups. The list can
therefore be nonempty while no job is running. Timing does not occupy the
execution slot; once a handler starts, the queue waits for its children and
cleanup before starting another root job.

Omitting `timing`, or passing `Duration.zero`, makes groups ready immediately
and creates no timers. Negative durations throw `ArgumentError`. A timing
configuration can be shared by several accumulators; each accumulator has its
own groups and throttle interval. Timer callbacks follow Dart's event-loop
order: an event processed before a debounce callback can restart the timer; an
event processed after it belongs to a new group. A busy event loop can delay
callbacks and starts.

## Choosing where events join

```dart
// All three while the current job still keeps the queue occupied:
settings.change(a1); // A1, into this accumulator
settings.save();     // B, an ordinary job of its own
settings.change(a2); // A2 -- where it lands is the policy's decision
```

Both factories accept an `AccumulationPolicy`, fixed when the accumulator is
created.

| Policy | Queue after the additions | Handle for A2 |
| --- | --- | --- |
| `adjacent` (default) | `[A1, B, A2]` | A new job |
| `replace` | `[B, A(A1 + A2)]` | A new job; A1's job is cancelled |
| `join` | `[A(A1 + A2), B]` | A1's existing job |

`adjacent` accepts into the group only when it is at the queue's tail.
`replace` and `join` find the last open queued group of the same accumulator,
looking past other jobs. Those other jobs stay in the queue. In `join`, A
retains its position before B; `replace` moves A behind B. Execution also
depends on readiness: a ready B can pass A while A waits for timing.

Policies use the current queue. If B has already run, a waiting A may again be
at the tail, so a later event can join it with `adjacent`. Already separate
groups are never combined retroactively. A sealed debounce group is ineligible
for all three policies.

`replace` transfers all accumulated data into a new queued job and adds the
incoming event. It creates a new handle even when the old group was already at
the tail. The old job completes with `Cancelled`, a `ManualCancelReason`,
`started: false`, and the description `replaced by accumulated group`. The new
group is in the queue before the old job's finish and cancellation callbacks
run. Those callbacks can add, cancel or close again, so the returned new handle
may already be cancelled by the time the outer `add` returns. A replacement
starts a fresh debounce interval; it preserves the accumulator's throttle
interval.

Replacement is mandatory for a queued group, including one configured with
`cancellable: false`. It never cancels a running group. The ordinary queue's
`Policy.replace` has its own existing cancellation rules; `AccumulationPolicy`
is a separate enum.

The accumulator's identity determines which groups can combine. Two
accumulators with the same `key` remain separate. The key still labels their
jobs for the ordinary queue's search and policies. Creating a new accumulator
on every call prevents events from joining an existing one.

## Start, cancellation and errors

```dart
final group = settings.report(metric);

// Everyone who added to this group holds the same handle...
switch (await group.done) {
  case Done():
    print('sent');
  case Failed(:final error):
    print('failed: $error');
  case Cancelled(:final reason):
    print('cancelled: $reason');
}

// ...and cancelling it cancels the whole group.
await group.cancel();
```

All three policies operate on queued groups. A group stops accepting events
when debounce seals it or when it is taken from the queue, before `canStart`
and `onStart`. Events added from either callback go to a later group. The
handler gets the configured working type and rules, and the queue waits for its
children and cleanup just as it does for any other `SoloJob`.

An accumulator creates no job until the first event. Without timing, if each
group finishes before the next event arrives, each event starts a separate job.
A `join` policy's search can scan the queue; `adjacent` only checks its tail.
`replace` also searches the queue.

In `adjacent` and `join`, additions to one group share one handle, result and
cancellation. Cancelling it affects the whole group. In `replace`, old handles
remain cancelled; they do not forward to the new job, and cancelling an already
replaced handle does not cancel its successor. Await the new handle to observe
the transferred work.

`merge` must be synchronous and pure. It must not mutate either argument or
call into the controller. If it throws, `add` throws the same error and the
existing group and timer remain unchanged; even `replace` keeps the old job.
Calling the same accumulator's `add` from within its `merge` throws
`StateError`. The engine also checks that the target group is still eligible
after the callback, before committing the result.

`canStart`, `keepWhile` and cancellation apply to the whole job. A start rule
can cancel all of its accumulated input. The handler's result and errors follow
the ordinary `Job` contract; accepted cancellation still takes precedence over
a later value or error. The accumulator does not roll back partial external
effects or resend failed input automatically.

Cancelling a queued debounce group removes its timer. Removing or clearing
throttle groups preserves an already started interval, so adding another event
cannot bypass the limit. That timer expires once and is not renewed until
another group starts.

`close()` cancels every timing timer, drops queued groups and cancels or waits
for the running job under the usual rules. It does not send a final batch. An
`add` after closing returns a new job already completed with
`Cancelled(closed)`; it does not call `merge` or the handler. Once a group
completes, its internal input storage is released. A handler, result or error
that retains the input still owns those references.
