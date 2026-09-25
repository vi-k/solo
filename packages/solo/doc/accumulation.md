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

## Recipes

Four controllers, each with more events arriving than there is work worth
doing. What differs is what survives: the last value, a merge of all of them,
or every event in a list.

Each recipe opens with the version the controller's own vocabulary leads to —
what you write when you reach for `run` and stop there. Where the obvious fix
is worth seeing on its own, a second attempt follows it. The traces under them
are what that code prints when it runs.

### A search that fires on every keystroke

A search box asks the server for results while the user types. Every keystroke
is an event, and only the last one is worth a request.

#### The first attempt

The controller's vocabulary says `run`, so every keystroke gets a job:

```dart
final class QueuedSearch extends Solo<SearchState> {
  final SearchApi api;

  QueuedSearch(this.api) : super(const SearchState.idle());

  SoloJob<void> query(String text) => run<SearchState, void>(
        key: 'query',
        (ctx) async {
          final results = await ctx.wait(() => api.search(text));
          ctx.emit(SearchState.results(results));
        },
      );
}
```

Typing `solo`, one character every 50 ms, against a server that answers in 100
ms:

```
the server was asked 4 times: [s, so, sol, solo]
at 100 ms the screen shows [hits for s]
at 200 ms the screen shows [hits for so]
at 300 ms the screen shows [hits for sol]
at 400 ms the screen shows [hits for solo]
```

The queue is doing its job, and that is the problem. Each request waits for the
one before it, so the answer to `solo` arrives 400 ms after the first
keystroke — four round trips, not one. On the way the screen answers three
words the user had already typed past.

#### The second attempt

`Policy.restart` cancels the job that is running when the next one arrives; the
queue's own policies are in [Queue and policies](jobs.md#queue-and-policies) on
the jobs page. Only the method changes:

```dart
SoloJob<void> query(String text) => run<SearchState, void>(
      key: 'query',
      policy: Policy.restart,
      (ctx) async {
        final results = await ctx.wait(() => api.search(text));
        ctx.emit(SearchState.results(results));
      },
    );
```

```
the server was asked 4 times: [s, so, sol, solo]
at 250 ms the screen shows [hits for solo]
```

Nothing stale reaches the screen now, and the answer comes sooner because the
requests overlap instead of queueing. The server was still asked four times:
cancelling a job does not unsend what it has already sent. `ctx.join` in place
of `ctx.wait` would not unsend them either; it holds the controller's slot
until the answer returns, so how many requests go out depends on how much
faster the server is than the typing.

#### The accumulator

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

```
the server was asked 1 time: [solo]
at 550 ms the screen shows [hits for solo]
```

One request. `merge` keeps the incoming text and drops what it had, so the
group carries the latest query; the debounce holds the group until the typing
stops for 300 ms. That pause is what it costs: the answer arrives later than
either attempt above, and it is the only answer sent.

`SearchApi` and `SearchState` are application types. A group that has already
started finishes before the next one starts, and the returned job exposes the
outcome and cancellation, like other jobs. What finishes there is the job:
cancelling one ends its waiting, not the request it has already sent, so that
request can still be in flight when the next group starts.

### Settings saved on every flip of a switch

A settings screen has a switch, a theme picker and a language picker. Each
change is an event, and the server wants one write rather than three.

`SettingsPatch` describes which settings to change. A new value for a field
replaces the previous one; fields absent from the new patch are kept. Here the
settings themselves cannot be null, so a null field in the patch means "leave
this one alone". A nullable setting that can be cleared needs a separate way to
say whether the patch carries a value.

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

  Future<Settings> load();
}
```

#### The first attempt

Every change is a job, and the job writes:

```dart
final class EagerSettingsController extends Solo<Settings> {
  final SettingsApi _api;

  EagerSettingsController(this._api, Settings initial) : super(initial);

  SoloJob<void> update(SettingsPatch patch) => run<Settings, void>(
        key: 'settings',
        (ctx) async {
          final next = patch.apply(ctx.state);
          await ctx.join(() => _api.save(next));
          ctx.emit(next);
        },
      );
}
```

The switch, then the theme, then the language, 20 ms apart, against a server
that takes 100 ms to write:

```
the server was written to 3 times:
  notifications: true, theme: light, language: en
  notifications: true, theme: dark, language: en
  notifications: true, theme: dark, language: ru
the screen ends up with notifications: true, theme: dark, language: ru
```

The screen is right at the end, and the cost is on the wire: three round trips
for one visit to the settings, and the two in the middle publish settings the
user never chose. Another device reading between them finds the light theme
after its owner has already picked the dark one.

#### The second attempt

`Policy.restart` removes the queued writes with that key and asks the running
one to stop. Only the method changes:

```dart
SoloJob<void> update(SettingsPatch patch) => run<Settings, void>(
      key: 'settings',
      policy: Policy.restart,
      (ctx) async {
        final next = patch.apply(ctx.state);
        await ctx.join(() => _api.save(next));
        ctx.emit(next);
      },
    );
```

```
the server was written to 2 times:
  notifications: true, theme: light, language: en
  notifications: false, theme: light, language: ru
the screen ends up with notifications: false, theme: light, language: ru
```

The switch went back off and the theme went back to light. Each job reads the
state it starts with and writes a whole `Settings`, so a job that replaces
another does not inherit what that one was going to change — it overwrites it
from a state where it never happened. The first of the two writes is the one
restart asked to stop, and it went out all the same: `ctx.join` waits for the
call it made, and `_api.save` has no way to hear the request to stop. Two of
the user's three changes are gone, from the server and from the screen both,
and nothing failed.

#### The accumulator

```dart
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

  SoloJob<void> reload() => run<Settings, void>(
        key: 'reload',
        (ctx) async => ctx.emit(await ctx.wait(_api.load)),
      );
}
```

```
the server was written to 1 time:
  notifications: true, theme: dark, language: ru
the screen ends up with notifications: true, theme: dark, language: ru
```

`merge` combines the patches instead of choosing between them, so nothing the
user did is dropped, and the group carries all three changes into one write.

The screen also reads the settings back from the server, and `reload` is an
ordinary job rather than an accumulated one. This accumulator takes the default
policy, `join`, so a `reload` queued between two flips is not a boundary: the
flips are one group and one write whatever else the queue was doing. The policy
section says when to take `adjacent` instead.

The first event becomes the accumulated value without calling `merge`. Each
following event calls `merge(accumulated, incoming)` synchronously from `add`,
before the handler starts. Only its result is kept.

The three calls hand back one job, and awaiting it once is awaiting all three:

```dart
Future<void> changeSettings(SettingsApi api, Settings initial) async {
  final controller = SettingsController(api, initial);
  try {
    final first = controller.update(
      const SettingsPatch(notifications: true),
    );
    final second = controller.update(const SettingsPatch(theme: 'dark'));
    final third = controller.update(const SettingsPatch(language: 'ru'));

    print(identical(first, second) && identical(second, third));
    print(await first.done);
  } finally {
    await controller.close();
  }
}
```

```
true
Done(null)
```

Its handler saves one snapshot with all three changes, then emits that snapshot
after 200 ms without another change. State still has its initial value before
the handler runs. Other ready jobs can run during the pause. Observing `.done`
reports `Done`, `Failed` or `Cancelled` without throwing.

If saving fails, the state is unchanged and the group fails. Retrying the
failed changes is the caller's decision; a later independent patch does not
automatically include them. This example assumes one writer and an API future
that completes when the write has actually ended. `join` keeps the queue slot
until that future completes, even after cancellation, and that is what stops
the next write from starting on top of this one. A client timeout alone does
not establish that a server has stopped writing: a `save` that completes its
future on a timeout hands the slot back while the server is still writing, the
next group's write goes out over an unfinished one, and which of the two the
server keeps is no longer the queue's decision — the screen and the server can
end up disagreeing for good. Cancellation can also prevent the final `emit`
after the server has accepted the write.

### One request per log line

An application writes log entries one at a time and the server takes them in
batches. Every entry has to arrive, and in the order it was written.

```dart
import 'package:solo/solo.dart';

class LogEntry {
  final String message;

  const LogEntry(this.message);
}

abstract interface class LogApi {
  Future<void> send(List<LogEntry> entries);
}
```

#### The first attempt

Every line is a job, and the job sends:

```dart
final class EagerLogController extends Solo<int> {
  final LogApi _api;

  EagerLogController(this._api) : super(0);

  SoloJob<void> logEvent(LogEntry entry) => run<int, void>(
        key: 'logs',
        (ctx) async {
          await ctx.join(() => _api.send([entry]));
          ctx.emit(ctx.state + 1);
        },
      );
}
```

Three lines written while one screen transition is handled, then one more half
a second later, against a server that takes 100 ms per request:

```
the server got 4 requests:
  [opened]
  [loaded]
  [shown]
  [tapped]
the three lines of the transition cost 3 of them
the counter says 4
```

Four lines, four requests. The queue is what keeps them in order, and it is
also what makes them wait: each send starts only when the one before it has
finished, so a burst of logging turns into a chain of round trips that outlives
the event that produced it.

#### The accumulator

`collect` appends events to a private list and gives the handler an
unmodifiable snapshot at the moment the group is sealed: every entry, in the
order it was written. The snapshot copies the list, not the entries in it, so
an entry changed after `add` is sent changed — use immutable event objects.

```dart
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

```
the server got 2 requests:
  [opened, loaded, shown]
  [tapped]
the three lines of the transition cost 1 of them
the counter says 4
```

The three lines of the transition travel together. The fourth arrives after the
throttle interval has passed, so it goes on its own rather than waiting for
company — the interval is a floor under the rate, not a delay added to every
entry.

A buffer you keep yourself would batch them too. What `collect` adds is that
the buffer is the job's input: the entries are sealed into the group the queue
takes, the caller gets the same `SoloJob` every other addition got, and
`close()` drops the group instead of leaving a list and a timer behind.

This controller's state counts entries whose send operation completed and whose
handler reached `emit`. The policy section explains why `join` is the default
this example spells out, and the timing section explains what a throttle
interval measures from.

Collecting entries does not guarantee delivery. A failed send, a cancelled
group or a plain `close()` can leave them unsent; `close()` with
`SoloCloseMode.drain` sends what is already queued. Durable storage and retries
require an application protocol beyond this accumulator.

### Commands where only the last one counts

A player puts resume and pause on one button, and the user taps it faster than
the device answers.

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
```

#### The first attempt

Each command is a job of its own:

```dart
final class QueuedPlayer extends Solo<Playback> {
  final PlayerDevice device;

  QueuedPlayer(this.device) : super(const Paused());

  SoloJob<void> resume() => run<Playback, void>(
        key: Command.resume,
        (ctx) async {
          await ctx.join(device.resume);
          ctx.emit(const Playing());
        },
      );

  SoloJob<void> pause() => run<Playback, void>(
        key: Command.pause,
        (ctx) async {
          await ctx.join(device.pause);
          ctx.emit(const Paused());
        },
      );
}
```

Three taps in a row — resume, pause, resume — against a device that takes 100
ms to obey:

```
the device heard 3 commands:
  resume at 0 ms
  pause at 100 ms
  resume at 200 ms
the button gave back a job for every tap
the player settles Playing at 300 ms
```

The player ends up where the last tap asked, and gets there by doing what no
tap asked for: it plays, stops, and plays again, and the stop in the middle is
something the user hears. Three round trips to the device, and 300 ms before it
settles.

#### The accumulator

A queue holding `resume` and then `pause` is about to do two things that cancel
each other out, and a `resume` arriving now makes the whole pair pointless: the
end of it is what a single `resume` would have reached. `merge` keeps the
incoming command and drops the one it had:

```dart
final class Player extends Solo<Playback> {
  final PlayerDevice device;

  late final _transport = accumulate<Playback, Command, void>(
    key: 'transport',
    policy: AccumulationPolicy.adjacent,
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

```
the device heard 1 command:
  resume at 0 ms
the button gave back one job
the player settles Playing at 100 ms
```

Three calls in a row leave one job in the queue, and all three return the same
handle. The device is told to resume once. Nothing was queued and cancelled on
the way.

This works because the commands are absolute: each one says what the end state
is, so the last one is the answer. Commands that build on each other — "ten
seconds further on" — are merged by adding them up, not by replacing.

`adjacent` joins a group only at the queue's tail, so a job of another kind
added between two commands is a boundary and the merging stops there. That is
what keeps the order with the rest of the work, and why this recipe names the
policy instead of taking the default: `join` joins the group where it stands,
and here that would drop the `resume` the user tapped and leave the device with
the `pause` alone.

#### When they are separate jobs after all

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

Removing and adding gives the shape of `AccumulationPolicy.replace`: the
command ends up at the tail, behind whatever was queued between. What differs
is the handle — the queue has to build a new job, where the accumulator moves
the one it already has. The queue can remove a job and it can add one, but it
cannot change what a queued job will do, so the place `join` keeps is not
reachable this way — keeping it means holding the command outside the job,
which is what an accumulator does with the input inside it.

The queue never touches the running job: a `pause` that has already started
runs to its end whatever is removed behind it. Reach for `cancelAll()` — it
clears the queue and cancels the current job — or give both commands one key
and `Policy.restart`. Jobs created with `cancellable: false` are skipped unless
`force: true` is given.

## Reference

These sections work through grouping, ordering and the outcomes returned to
individual callers.

### Choosing when a group is ready

Both factories accept an optional `timing`. The setting controls when a group
may start; `collect` still keeps every accepted event, and `accumulate` keeps
whatever its `merge` returns. For example,
`merge: (previous, incoming) => incoming` keeps only the latest value.

| | `debounce(duration)` | `throttle(duration)` | `throttle(duration, startAtOnce: false)` |
| --- | --- | --- | --- |
| The first group is ready | after `duration` with no new event | at once | after `duration` |
| An addition | restarts the timer | does not extend it | does not extend it |
| The wait is measured from | the last accepted event | the previous actual start | the previous start, or where the group appeared |

`AccumulationTiming.debounce(duration)` waits for a pause after the last
accepted event in each group. Every addition restarts the timer, even when
`merge` returns an unchanged value. With a 200 ms interval, events at 0, 60 and
120 ms make the group ready at 320 ms. Continuous input can keep an open group
waiting indefinitely. That wait is the point in the search recipe — the request
goes out when the typing stops — and the reason the log collector takes a
throttle instead: entries that all have to arrive cannot wait on a pause that
may never come. When the timer fires, the group is sealed even if another job
is running. Later events form a new group; they cannot change the sealed input.
`collect` takes its snapshot then, and not again.

`AccumulationTiming.throttle(duration)` allows the first group to start
immediately, then waits at least `duration` between actual starts of the same
accumulator. Additions during the interval gather in an open group without
extending the timer. When the interval ends, queued input is ready without
needing another event. The group accepts events until the queue takes it for
execution. No job is created for an empty interval.

`startAtOnce: false` counts the interval before the first group as well. An
accumulator with nothing of its own queued or running starts its interval where
the group appears, and the group becomes ready when the interval ends, carrying
everything written meanwhile. That condition is the whole of it: an interval
already running is never restarted, and neither is one restarted by a group
that appears beside a group that is waiting in the queue or running. So a group
that has waited its interval out and needs only the execution slot is not
pushed back by a later event, whatever the policy does with that event.

Starting at once has a price on an idle accumulator. Nothing is running, so the
queue takes the first group on the next microtask, and a burst that does not
fit in one synchronous turn is split: the first event goes on its own and the
rest wait out the whole interval. While another job occupies the queue the
burst gathers in one group instead, which is the log recipe's own scenario —
its entries are written while a screen transition is being handled.

Waiting has a price of its own. A single event on an idle accumulator is held
for the whole interval, and `close(mode: SoloCloseMode.drain)` waits with it —
a plain `close()` drops it. Take `startAtOnce: false` where the rate matters
more than the latency of the first event, and leave the default where the first
event is what the user is waiting for.

The start is the transition to running, before `onStart`. A group rejected by
start rules consumes no throttle interval; cancellation from `onStart` does.
With `startAtOnce: false` a refusal leaves the accumulator with nothing queued,
so the next group to appear counts its own full interval from where it appears,
not what was left of the refused one's. If a group starts at 0 ms with a 200 ms
interval, but another job holds the slot until 500 ms, the next group starts at
500 ms and the one after that cannot start before 700 ms. If the group's own
handler, children or cleanup outlast the interval, the next group can start as
soon as they finish.

Waiting groups stay visible in `queue.jobs`. The queue takes the first ready
job in list order, allowing ready jobs to pass waiting groups. The list can
therefore be nonempty while no job is running. Timing does not occupy the
execution slot; once a handler starts, the queue waits for its children and
cleanup before starting another root job.

Omitting `timing`, or passing `Duration.zero`, makes groups ready immediately
and creates no timers, whatever `startAtOnce` says. Negative durations throw
`ArgumentError`. A timing configuration can be shared by several accumulators;
each accumulator has its own groups and throttle interval. Timer callbacks
follow Dart's event-loop order: an event processed before a debounce callback
can restart the timer; an event processed after it belongs to a new group. A
busy event loop can delay callbacks and starts.

### Choosing where events join

```dart
// All three while the current job still keeps the queue occupied. Where A2
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

`adjacent` accepts into the group only when it is at the queue's tail.
`replace` and `join` find the last open queued group of the same accumulator,
looking past other jobs. Those other jobs stay in the queue. In `join`, A
retains its position before B; `replace` moves A behind B. Execution also
depends on readiness: a ready B can pass A while A waits for timing.

`join` is the default for that reason. An entry written while another job waits
in the queue still belongs in the batch that is already there; under `adjacent`
it would start a second group behind that job, and a throttle would hold that
group for another interval — two requests for entries written moments apart.
The same two events would be one group or two depending on what else the
controller happened to be doing, which is a decision no caller made. What
`join` gives up is the boundary: the batch keeps its place ahead of the job
that arrived between.

Take `adjacent` where that boundary is the point: where `merge` throws away
what it replaces and a job queued between two events has to run between them,
as the command recipe does, or where such a job changes what the accumulated
input means.

Policies use the current queue. If B has already run, a waiting A may again be
at the tail, so a later event can join it with `adjacent`. Already separate
groups are never combined retroactively. A sealed debounce group is ineligible
for all three policies.

`replace` adds the incoming event to the group it found and moves that group's
job to the tail. The handle is the one every addition to this group got, the
events already accepted stay in it, and a group that is already at the tail
keeps the place it has. Nothing is cancelled on the way, so no cancellation
callback runs in the middle of the move. The engine's debug trace says
`move <job> to the tail`; there is no observer event, because no job started or
finished.

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

### Start, cancellation and errors

```dart
final group = logs.logEvent(const LogEntry('checkout opened'));

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
handler gets the configured working type and rules, and is an ordinary
`SoloJob` to the queue in every other way.

An accumulator creates no job until the first event. Without timing, if each
group finishes before the next event arrives, each event starts a separate job.
A `join` policy's search can scan the queue; `adjacent` only checks its tail.
`replace` also searches the queue.

Additions to one group share one handle, result and cancellation under every
policy, and cancelling it affects the whole group. `replace` moves the job
rather than building another, so the handle outlives the move: cancelling it
cancels the group wherever the job now stands, and there is no second handle to
await.

`merge` must be synchronous and pure. It must not mutate either argument or
call into the controller. If it throws, `add` throws the same error and the
existing group, its job and its timer remain unchanged. Calling the same
accumulator's `add` from within its `merge` throws `StateError`. The engine
also checks that the target group is still eligible after the callback, before
committing the result.

`canStart`, `keepWhile` and cancellation apply to the whole job, and the rules
themselves are in [State and rules](state.md#state-and-rules) on the state
page. A start rule can cancel all of its accumulated input. The handler's
result and errors follow the ordinary `Job` contract; accepted cancellation
still takes precedence over a later value or error. The accumulator does not
roll back partial external effects or resend failed input automatically.

Cancelling a queued debounce group removes its timer. Removing or clearing
throttle groups preserves an already started interval, so adding another event
cannot bypass the limit. That timer expires once; it is renewed when a group
actually starts, and with `startAtOnce: false` also when a group appears on an
accumulator that has none of its own queued or running.

`close()` cancels every timing timer, drops queued groups and cancels or waits
for the running job under the usual rules. It sends no final batch: a group
still waiting for its window is dropped, and the jobs it handed out complete
with `Cancelled(closed)`. `close(mode: SoloCloseMode.drain)` is the other
choice — it waits the accumulation window out and runs the groups already
queued, by the rules in
[Cancelling and closing a controller](cancellation.md#cancelling-and-closing-a-controller)
on the cancellation page. Neither mode takes anything new: an `add` after
`close()` returns a new job already completed with `Cancelled(closed)`; it does
not call `merge` or the handler. Once a group completes, its internal input
storage is released. A handler, result or error that retains the input still
owns those references.
