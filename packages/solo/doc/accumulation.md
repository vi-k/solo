# Accumulating events before a job starts

Several events can share one queued job. `collect` keeps every event in a list;
`accumulate` combines each event with a single accumulated value.

Where to start, by what the controller needs; the last three rows lead to
[Accumulation rules](accumulation-rules.md):

| The controller needs | Read |
| --- | --- |
| One of four common cases: a search box, settings saved on every flip, log lines sent in batches, commands where only the last counts | [Recipes](#recipes), whose table names what reaches the work and the accumulator of each |
| A group that starts after a pause in the events, at a limited rate, or at once | [Choosing when a group is ready](accumulation-rules.md#choosing-when-a-group-is-ready): `timing` |
| An event that joins a queued group, or starts a group of its own behind another job | [Choosing where events join](accumulation-rules.md#choosing-where-events-join): `AccumulationPolicy` |
| One handle for every caller of a group, and how its job starts, is cancelled, fails and ends on `close()` | [Start, cancellation and errors](accumulation-rules.md#start-cancellation-and-errors) |

## Recipes

Four controllers, each with more events arriving than there is work worth
doing. What differs is what survives: the last value, a merge of all of them,
or every event in a list.

| Recipe | What reaches the work | The accumulator |
| --- | --- | --- |
| [A search that fires on every keystroke](#a-search-that-fires-on-every-keystroke) | The last query, after a pause in the typing | `accumulate`, a `merge` that keeps `incoming`, `debounce` |
| [Settings saved on every flip of a switch](#settings-saved-on-every-flip-of-a-switch) | One patch merged from every flip | `accumulate`, a `merge` that combines the patches, `debounce` |
| [One request per log line](#one-request-per-log-line) | Every entry, in at most one request a second | `collect`, `throttle` with `startAtOnce: false` |
| [Commands where only the last one counts](#commands-where-only-the-last-one-counts) | The last of the commands tapped in a row | `accumulate`, a `merge` that keeps `incoming`, `policy: adjacent` |

Under each version of a controller is what the scenario above it leads to: what
reaches the server or the device, and what the controller's state ends up as.

`collect` and `accumulate` both take three type arguments, `<W, E, T>`: the
working type `W`, as in `enqueue`, the event type `E` and the result type `T`,
and return a `SoloAccumulator<E, T>`. Create it once in your controller, then
call its `add(event)` method from the controller's public methods.

The accumulator owns the input of a queued job. Adding an event does not run
the handler or change controller state. The events that share one job are a
group. A group accepts events until it is sealed: when its debounce window
expires, or, under a throttle or with no timing at all, when the queue takes
the job to run it. The handler receives that input and an ordinary
`SoloContext<S, W>`; it changes state through `ctx.emit`.

### A search that fires on every keystroke

A search box asks the server for results while the user types. Every keystroke
is an event, and only the last one is worth a request.

```dart
import 'package:solo/solo.dart';

class SearchState {
  final List<String> results;

  const SearchState.idle() : results = const [];

  const SearchState.results(this.results);
}

abstract interface class SearchApi {
  Future<List<String>> search(String text);
}
```

#### The first attempt

The controller's vocabulary says `enqueue`, so every keystroke gets a job:

```dart
// The first attempt: every keystroke waits for the one before.
final class QueuedSearch extends Solo<SearchState> {
  final SearchApi api;

  QueuedSearch(this.api) : super(const SearchState.idle());

  Job<void> query(String text) => enqueue<SearchState, void>(
        key: 'query',
        (ctx) async {
          final results = await ctx.abandonable(() => api.search(text));
          ctx.emit(SearchState.results(results));
        },
      );
}
```

Typing `solo`, one character every 50 ms, against a server that answers in 100
ms:

```text
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
// The second attempt: the server is still asked four times.
Job<void> query(String text) => enqueue<SearchState, void>(
      key: 'query',
      policy: Policy.restart,
      (ctx) async {
        final results = await ctx.abandonable(() => api.search(text));
        ctx.emit(SearchState.results(results));
      },
    );
```

```text
the server was asked 4 times: [s, so, sol, solo]
at 250 ms the screen shows [hits for solo]
```

Nothing stale reaches the screen now, and the answer comes sooner because the
requests overlap instead of queueing. The server was still asked four times:
cancelling a job does not unsend what it has already sent. `ctx.join` in place
of `ctx.abandonable` would not unsend them either. It holds the controller's
one execution slot until the answer returns, so how many requests go out
depends on how much faster the server is than the typing.

#### The accumulator

```dart
final class Search extends Solo<SearchState> {
  final SearchApi api;
  late final _queries = accumulate<SearchState, String, void>(
    (ctx, text) async {
      final results = await ctx.abandonable(() => api.search(text));
      ctx.emit(SearchState.results(results));
    },
    merge: (accumulated, incoming) => incoming,
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 300)),
    policy: AccumulationPolicy.join,
    key: 'query',
  );

  Search(this.api) : super(const SearchState.idle());

  Job<void> query(String text) => _queries.add(text);
}
```

```text
the server was asked 1 time: [solo]
at 550 ms the screen shows [hits for solo]
```

One request. `merge` keeps the incoming text and drops what it had, so the
group carries the latest query; the debounce holds the group until the typing
stops for 300 ms. That pause is what it costs: the answer arrives later than
either attempt above, and it is the only answer sent. `policy` spells out the
default, `join`;
[Choosing where events join](accumulation-rules.md#choosing-where-events-join)
says what a policy decides.

A group that has already started finishes before the next one starts, and the
returned job exposes the outcome and cancellation, like other jobs. What
finishes there is the job: cancelling one ends its waiting, not the request it
has already sent, so that request can still be in flight when the next group
starts.

Every call of `query` that lands in one group returns the same job, so a plain
`then` on it throws `StateError`; a caller continues it through `shared()`.
`merge` runs inside `add` and has to be synchronous and pure. Both rules, with
what happens when they are broken, are in
[Start, cancellation and errors](accumulation-rules.md#start-cancellation-and-errors)
on the accumulation rules page.

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
// The first attempt: every change is a write of its own.
final class EagerSettingsController extends Solo<Settings> {
  final SettingsApi _api;

  EagerSettingsController(this._api, Settings initial) : super(initial);

  Job<void> update(SettingsPatch patch) => enqueue<Settings, void>(
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

```text
the server was written to 3 times:
  notifications: true, theme: light, language: en
  notifications: true, theme: dark, language: en
  notifications: true, theme: dark, language: ru
the screen ends up with notifications: true, theme: dark, language: ru
```

The screen is right at the end, and the cost is on the wire: three round trips
for one visit to the settings. The first two publish settings the user has
already moved on from. Another device reading between them finds the light
theme after its owner has already picked the dark one.

#### The second attempt

`Policy.restart` removes the queued writes with that key and asks the running
one to stop. Only the method changes:

```dart
// The second attempt: a restart overwrites the change it replaced.
Job<void> update(SettingsPatch patch) => enqueue<Settings, void>(
      key: 'settings',
      policy: Policy.restart,
      (ctx) async {
        final next = patch.apply(ctx.state);
        await ctx.join(() => _api.save(next));
        ctx.emit(next);
      },
    );
```

```text
the server was written to 2 times:
  notifications: true, theme: light, language: en
  notifications: false, theme: light, language: ru
the screen ends up with notifications: false, theme: light, language: ru
```

The switch went back off and the theme went back to light. Each job reads the
state it starts with and writes a whole `Settings`. So a job that replaces
another does not inherit what that one was going to change: it overwrites it
from a state where it never happened. The first of the two writes is the one
restart asked to stop, and it went out all the same. `ctx.join` waits for the
call it made, and `_api.save` has no way to hear the request to stop. Two of
the user's three changes are gone, from the server and from the screen both,
and nothing failed.

#### The accumulator

```dart
final class SettingsController extends Solo<Settings> {
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

  Job<void> update(SettingsPatch patch) => _updates.add(patch);

  Job<void> reload() => enqueue<Settings, void>(
        key: 'reload',
        (ctx) async => ctx.emit(await ctx.abandonable(_api.load)),
      );
}
```

```text
the server was written to 1 time:
  notifications: true, theme: dark, language: ru
the screen ends up with notifications: true, theme: dark, language: ru
```

`merge` combines the patches instead of choosing between them, so nothing the
user did is dropped, and the group carries all three changes into one write.

The screen also reads the settings back from the server, and `reload` is an
ordinary job rather than an accumulated one. This accumulator takes the default
policy, `join`, so a `reload` queued between two flips is not a boundary: the
flips are one group and one write whatever else the queue was doing.
[Choosing where events join](accumulation-rules.md#choosing-where-events-join)
says when to take `adjacent` instead.

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

```text
true
Done(null)
```

After 200 ms without another change the handler saves one snapshot with all
three changes, and emits it once the write has ended. Until the handler runs,
the state keeps its initial value, and other ready jobs can run during the
pause. Observing `.done` reports `Done`, `Failed` or `Cancelled` without
throwing.

If saving fails, the state is unchanged and the group fails. Retrying the
failed changes is the caller's decision; a later independent patch does not
automatically include them. This example assumes one writer and an API future
that completes when the write has actually ended. `ctx.join` keeps the
execution slot until that future completes, even after cancellation, and that
is what stops the next write from starting on top of this one. A client timeout
alone does not establish that a server has stopped writing. A `save` that
completes its future on a timeout hands the slot back while the server is still
writing, and the next group's write goes out over an unfinished one. Which of
the two the server keeps is then no longer the queue's decision, and the screen
and the server can end up disagreeing for good. Cancellation can also prevent
the final `emit` after the server has accepted the write.

A deadline given to the accumulator with `timeout` is a cancellation, not a
client timeout: `ctx.join` keeps the slot until `save` completes, so the next
write still waits for this one to end. What the deadline costs is the final
`emit`. A group past its deadline is cancelled while the server is still
writing, ends `Cancelled(timeout)` once the write is stored, and never reaches
its `emit`. The state keeps the old settings, and the next group applies its
patch to them and writes the old values back over the change.

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
// The first attempt: every line is a round trip of its own.
final class EagerLogController extends Solo<int> {
  final LogApi _api;

  EagerLogController(this._api) : super(0);

  Job<void> logEvent(LogEntry entry) => enqueue<int, void>(
        key: 'logs',
        (ctx) async {
          await ctx.join(() => _api.send([entry]));
          ctx.emit(ctx.state + 1);
        },
      );
}
```

Three lines written one after another by the code that handles a screen
transition, then one more two seconds later, against a server that takes 100 ms
per request:

```text
the server got 4 requests:
  [opened] at 0 ms
  [loaded] at 100 ms
  [shown] at 200 ms
  [tapped] at 2000 ms
the three lines of the transition cost 3 of them
the counter says 4
```

Four lines, four requests. The queue is what keeps them in order, and it is
also what makes them wait: each send starts only when the one before it has
finished. A burst of logging thus turns into a chain of round trips that
outlives the event that produced it.

#### The accumulator

`collect` appends events to a private list and gives the handler an
unmodifiable snapshot at the moment the group is sealed: every entry, in the
order it was written. The snapshot copies the list, not the entries in it, so
an entry changed after `add` is sent changed — use immutable event objects.

```dart
final class LogController extends Solo<int> {
  final LogApi _api;
  late final _logs = collect<int, LogEntry, void>(
    (ctx, entries) async {
      await ctx.join(() => _api.send(entries));
      ctx.emit(ctx.state + entries.length);
    },
    key: 'logs',
    policy: AccumulationPolicy.join,
    timing: AccumulationTiming.throttle(
      const Duration(seconds: 1),
      startAtOnce: false,
    ),
  );

  LogController(this._api) : super(0);

  Job<void> logEvent(LogEntry entry) => _logs.add(entry);
}
```

```text
the server got 2 requests:
  [opened, loaded, shown] at 1000 ms
  [tapped] at 3000 ms
the three lines of the transition cost 1 of them
the counter says 4
```

The three lines of the transition travel together. With `startAtOnce: false`
the interval starts at the first of them and the group waits it out, so lines
written within that second stay together, however many turns the code takes to
write them. With the default (`startAtOnce: true`) the first line would go at
once, and the rest of a transition written over more than one turn would follow
a second later. The fourth line is written when no interval is running, so it
starts one of its own and waits it out: a line written alone reaches the server
a second late.

A buffer you keep yourself would batch them too. What `collect` adds is that
the buffer is the job's input:

- the entries are sealed into the group the queue takes;
- the caller gets the same `Job` every other addition to that group got;
- `close()` drops the group instead of leaving a list and a timer behind.

This controller's state counts entries whose send operation completed and whose
handler reached `emit`. The working type `int` is that whole state, so the
handler starts whatever the count is and reads it as `ctx.state`.
[Choosing where events join](accumulation-rules.md#choosing-where-events-join)
explains why `join` is the default this example spells out.
[Choosing when a group is ready](accumulation-rules.md#choosing-when-a-group-is-ready)
explains what a throttle interval is measured from in each of its two modes,
and what each of them costs.

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
// The first attempt: every tap reaches the device.
final class QueuedPlayer extends Solo<Playback> {
  final PlayerDevice device;

  QueuedPlayer(this.device) : super(const Paused());

  Job<void> resume() => enqueue<Playback, void>(
        key: Command.resume,
        (ctx) async {
          await ctx.join(device.resume);
          ctx.emit(const Playing());
        },
      );

  Job<void> pause() => enqueue<Playback, void>(
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

```text
the device heard 3 commands:
  resume at 0 ms
  pause at 100 ms
  resume at 200 ms
the button gave back a job for every tap
the player settles Playing at 300 ms
```

The player ends up where the last tap asked, and gets there the long way: it
plays, stops, and plays again, and the stop in the middle is something the user
hears. Three round trips to the device, and 300 ms before it settles.

#### The accumulator

A queue holding `resume` and then `pause` is about to do two things that cancel
each other out. A `resume` arriving now makes the whole pair pointless: the end
of it is what a single `resume` would have reached. `merge` keeps the incoming
command and drops the one it had:

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

  Job<void> resume() => _transport.add(Command.resume);

  Job<void> pause() => _transport.add(Command.pause);
}
```

```text
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

`adjacent` adjoins an event to a group only at the queue's tail, so a job of
another kind added between two commands is a boundary and the merging stops
there. Three taps in a row have no such job between them, and `join`, the
default, would merge them the same way. The two part when the player has other
work queued. With a job of another kind between a `resume` and a `pause`,
`join` folds the `pause` into the group ahead of that job. So the device never
hears the `resume`, and it pauses before the job runs. `adjacent` sends the
`resume`, lets the job run and then sends the `pause`, in the order of the
calls, and that is why this recipe names the policy instead of taking the
default.

#### When they are separate jobs after all

Where `resume` and `pause` are genuinely different operations rather than one
command with a value, they are ordinary jobs with keys of their own.
`Policy.replace` does not help: it removes jobs with the same key, and these
two do not share one. The controller's own queue is what removes them:

```dart
Job<void> resume() {
  queue.removeWhere(
    (job) => job.key == Command.resume || job.key == Command.pause,
  );

  return enqueue<Playback, void>(key: Command.resume, (ctx) async {
    await ctx.join(device.resume);
    ctx.emit(const Playing());
  });
}
```

Removing and adding gives the shape of `AccumulationPolicy.replace`: the
command ends up at the tail, behind whatever was queued between. What differs
is the handle — this way a new job has to be built, where the accumulator moves
the one it already has. The queue can remove a job and it can add one, but it
cannot change what a queued job will do. So the place `AccumulationPolicy.join`
keeps is not reachable this way. Keeping it means holding the command outside
the job, where the job reads it when it starts, and that is what an accumulator
does for its job.

The queue never touches the running job: a `pause` that has already started
runs to its end whatever is removed behind it. To cancel the running job as
well, reach for `cancelAll()` — it clears the whole queue and cancels the
current job — or give both commands one key and `Policy.restart`. `removeWhere`
skips jobs created with `cancellable: false` unless `force: true` is given.
