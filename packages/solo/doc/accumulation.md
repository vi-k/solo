# Accumulating events before a job starts

Several events can share one queued job. `collect` keeps every event in a
list; `accumulate` combines each event with a single accumulated value.
Both return a `SoloAccumulator<E, T>`. Create it once in your controller,
then call its `add(event)` method from the controller's public methods.

The accumulator owns the input of a queued job. Adding an event does not
run the handler or change controller state. When the queue takes the job
for execution, its input is fixed. The handler receives that input and
an ordinary `SoloContext<S, W>`; it changes state through `ctx.emit`.

## Combining settings changes

A patch describes which settings to change. A new value for a field
replaces the previous one; fields absent from the new patch are kept.
Here, the settings themselves cannot be null, so a null patch field
means "leave this field unchanged". A nullable setting that can be
cleared needs a separate way to represent whether the patch has a value.

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
  );

  SettingsController(this._api, Settings initial) : super(initial);

  SoloJob<void> update(SettingsPatch patch) => _updates.add(patch);
}
```

The first event becomes the accumulated value without calling `merge`.
Each following event calls `merge(accumulated, incoming)` synchronously
from `add`, before the handler starts. Only its result is kept. `false`
is a specified value and is preserved by the example's merge function.

Call these methods before yielding to the queue:

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

With the default policy, these calls share one `SoloJob<void>`. Its
handler saves one snapshot with all three changes, then emits that
snapshot. State still has its initial value before the handler runs.
Observing `.done` reports `Done`, `Failed` or `Cancelled` without throwing.

If saving fails, the state is unchanged and the group fails. Retrying
the failed changes is the caller's decision; a later independent patch
does not automatically include them. This example assumes one writer
and an API future that completes when the write has actually ended.
`join` keeps the queue slot until that future completes, even after
cancellation. A client timeout alone does not establish that a server
has stopped writing. Cancellation can also prevent the final `emit`
after the server has accepted the write.

## Collecting log entries

Logs need their individual entries and order. `collect` appends events
to a private list and gives the handler an unmodifiable snapshot at
execution time. It preserves duplicate events and does not copy the
entire list on every addition. The entries themselves are not cloned;
use immutable event objects.

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
  );

  LogController(this._api) : super(0);

  SoloJob<void> logEvent(LogEntry entry) => _logs.add(entry);
}
```

Three calls before execution send one list of three entries. This
controller's state counts entries whose send operation completed and
whose handler reached `emit`. The next section explains why this example
chooses `join` as its accumulation policy.

Collecting entries does not guarantee delivery. A failed send, a
cancelled group or controller shutdown can leave them unsent. Durable
storage, retries and a final send on shutdown require an application
protocol beyond this accumulator.

## Choosing where events join

Both factories accept an `AccumulationPolicy`, fixed when the accumulator
is created. Consider events `A1`, `B`, `A2` added while the current job
keeps the queue occupied. A belongs to one accumulator; B is another job.

| Policy | Queue after the additions | Handle for A2 |
| --- | --- | --- |
| `adjacent` (default) | `[A1, B, A2]` | A new job |
| `replace` | `[B, A(A1 + A2)]` | A new job; A1's job is cancelled |
| `join` | `[A(A1 + A2), B]` | A1's existing job |

`adjacent` accepts into the group only when it is at the queue's tail.
`replace` and `join` find the last queued group of the same accumulator,
looking past other jobs. Those other jobs stay in the queue. In `join`,
A2 is processed before B even though it arrived later. In `replace`,
A1's processing is deferred until after B. Choose the policy according
to which ordering your handler requires.

`replace` transfers all accumulated data into a new queued job and adds
the incoming event. It creates a new handle even when the old group was
already at the tail. The old job completes with `Cancelled`, a
`ManualCancelReason`, `started: false`, and the description
`replaced by accumulated group`. The new group is in the queue before
the old job's finish and cancellation callbacks run. Those callbacks can
add, cancel or close again, so the returned new handle may already be
cancelled by the time the outer `add` returns.

Replacement is mandatory for a queued group, including one configured
with `cancellable: false`. It never cancels a running group. The ordinary
queue's `Policy.replace` has its own existing cancellation rules;
`AccumulationPolicy` is a separate enum.

The accumulator's identity determines which groups can combine. Two
accumulators with the same `key` remain separate. The key still labels
their jobs for the ordinary queue's search and policies. Creating a new
accumulator on every call prevents events from joining an existing one.

## Start, cancellation and errors

All three policies operate on queued groups. A group stops accepting
events when it is taken from the queue, before `canStart` and `onStart`.
Events added from either callback go to a later group. The handler gets
the configured working type and rules, and the queue waits for its
children and cleanup just as it does for any other `SoloJob`.

An accumulator creates no job until the first event. There is no timer
or debounce window. If each group finishes before the next event arrives,
each event starts a separate job. A `join` policy's search can scan the
queue; `adjacent` only checks its tail. `replace` also searches the queue.

In `adjacent` and `join`, additions to one group share one handle,
result and cancellation. Cancelling it affects the whole group. In
`replace`, old handles remain cancelled; they do not forward to the new
job, and cancelling an already replaced handle does not cancel its
successor. Await the new handle to observe the transferred work.

`merge` must be synchronous and pure. It must not mutate either argument
or call into the controller. If it throws, `add` throws the same error
and the existing group remains unchanged; even `replace` keeps the old
job. Calling the same accumulator's `add` from within its `merge` throws
`StateError`. The engine also checks that the target group is still
eligible after the callback, before committing the result.

`canStart`, `keepWhile` and cancellation apply to the whole job. A start
rule can cancel all of its accumulated input. The handler's result and
errors follow the ordinary `Job` contract; accepted cancellation still
takes precedence over a later value or error. The accumulator does not
roll back partial external effects or resend failed input automatically.

`close()` drops queued groups and cancels or waits for the running job
under the usual rules. It does not send a final batch. An `add` after
closing returns a new job already completed with `Cancelled(closed)`;
it does not call `merge` or the handler. Once a group completes, its
internal input storage is released. A handler, result or error that
retains the input still owns those references.
