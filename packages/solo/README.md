# solo

`solo` manages state and asynchronous work in Dart. A controller holds the
current state and processes jobs one at a time, hence the name. Each job can
declare which states allow it to start and continue, and callers can await its
result or request cancellation.

Use it for screens, sessions and devices where operations share state and need
an explicit order. The package has no Flutter dependency.
[`flutter_solo`](https://pub.dev/packages/flutter_solo) adds the Flutter side:
`SoloListenable`, a mixin that makes a controller a `ValueListenable`, the
widgets `SoloBuilder` and `SoloSelector`, and `listen`, which hands back a
subscription to cancel instead of asking you to keep the callback.

## Install

```sh
dart pub add solo
```

For Flutter, install `flutter_solo`. It re-exports `solo`:

```sh
flutter pub add flutter_solo
```

`solo` re-exports [async_job](https://pub.dev/packages/async_job), which
provides jobs, cancellation and resource cleanup. One import,
`package:solo/solo.dart`, gives access to both APIs. You do not need to learn
the underlying package before using the examples below.

The analyzer plugin [solo_lints](https://pub.dev/packages/solo_lints) reports
most of the [common mistakes](doc/mistakes.md) in the code. Name it in
`analysis_options.yaml`:

```yaml
plugins:
  solo_lints: ^0.1.3
```

That turns on its warnings; the lints are turned on by name, as its
[Install](https://github.com/vi-k/solo/blob/main/packages/solo_lints/README.md#install)
section shows.

## Quick start

A screen loads the name of a profile, and the user pulls to refresh and cancels
the refresh before the answer comes. A controller holds the state of the screen
and runs its jobs one at a time. `ProfileApi` is the application's client, and
its `fetchName()` returns the name:

```dart
import 'package:solo/solo.dart';

sealed class ProfileState {
  const ProfileState();
}

final class Initial extends ProfileState {
  const Initial();
}

final class Loading extends ProfileState {
  const Loading();
}

final class Loaded extends ProfileState {
  final String name;

  const Loaded(this.name);
}

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => enqueue((ctx) async {
    ctx.emit(const Loading());
    final name = await ctx.abandonable(api.fetchName);
    ctx.emit(Loaded(name));
    return name;
  });
}

Future<void> main() async {
  final profile = ProfileController(ProfileApi());
  profile.addListener(
    () => print(switch (profile.currentState) {
      Initial() => 'initial',
      Loading() => 'loading',
      Loaded(:final name) => 'loaded $name',
    }),
  );

  print(await profile.load().value);

  // The user pulls to refresh, then cancels the refresh before the answer.
  final refresh = profile.load();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await refresh.cancel();
  print(refresh.outcome);

  await profile.close();
}
```

`example/bin/quick_start.dart` runs this block with an API that answers after
20 ms. It prints:

```text
loading
loaded Ada Lovelace
Ada Lovelace
loading
Cancelled(manual)
```

`enqueue` queues a job and hands it back. In the body, `ctx.emit` publishes a
state, which the listener hears inside the change, and `ctx.abandonable` waits
for the API and ends the wait at once when the job is cancelled. The caller
awaits `value` or calls `cancel()`, which returns once the job is over. The
wait before `cancel()` lets the refresh start: a job cancelled before its body
runs leaves the state alone. `close()` drops the listener; in Flutter,
`flutter_solo` has the widgets and a `listen` that hands back a subscription.

The cancelled refresh left the controller at `loading`, and nothing takes it
out of there.
[State after failure or cancellation](doc/state.md#state-after-failure-or-cancellation)
starts from this `load` and gives it the state to publish when a job fails or
is cancelled. [The profile controller](doc/jobs.md#the-profile-controller) is
this controller as the guides use it, with the parameters an application adds.

## The dozen calls

Everything reached for day to day, in one controller. `PlayerState` with its
states, `Track`, `Download`, `Api` and `Device` belong to the application; the
rest is the package.

```dart
enum _Op { play }

final class Player extends Solo<PlayerState> {
  final Api api;
  final Device device;

  Player(this.api, this.device) : super(const Idle()) {
    // A fact from outside the queue: published at once, and the rule of
    // the running job is asked about it.
    device.onDisconnect = () => externalSetState(const Disconnected());
  }

  /// A job on the controller's queue. Root jobs run one at a time, and
  /// this one ends when the track starts: the device plays it on its own.
  Job<Track> play(String id) => enqueue<PlayerState, Track>(
    // Any object is a key. This one keys the operation, not a track.
    key: _Op.play,
    // A new play cancels the one running under the same key.
    policy: Policy.restart,
    // A rule: asked before the start, and on every change of state
    // while the body runs, except one the body makes with `ctx.emit`.
    keepWhile: (state) => state is! Disconnected,
    // The state to publish when the job fails or is cancelled. If the
    // job is cancelled by the rule, nothing is published and
    // `Disconnected` stays. A play replaced by a newer one hands back
    // the state it was given, which publishes nothing.
    ifFailed: (state, error, stackTrace) => const Idle(),
    ifCancelled: (state, cancelled) =>
        cancelled.reason is ReplacedCancelReason ? state : const Idle(),
    (ctx) async {
      // The body's way to change state. There is no setter outside.
      ctx.emit(const Loading());
      // Waited out whatever happens: the track playing now stops
      // before another one loads.
      await ctx.join(device.stop);
      // Cancellation ends this wait at once; the request may go on.
      final track = await ctx.abandonable(() => api.fetch(id));
      // Waited out as well. `dispose` closes the download when the
      // job ends, or as soon as the call returns if the job was
      // cancelled meanwhile.
      final download = await ctx.join(
        () => api.download(track),
        dispose: (download) => download.close(),
      );
      // A child job: the device reads the download in, and its stream
      // ends when the track starts. The body awaits its `value` and
      // goes on once the track plays.
      await ctx.each(device.load(download), (childCtx, percent) {
        childCtx.emit(Buffering(track, percent));
      }).value;
      ctx.emit(Playing(track));
      return track;
    },
  );

  /// Events that share one queued job: only the last volume matters.
  late final _volume = accumulate<PlayerState, double, void>(
    (ctx, value) => ctx.join(() => device.setVolume(value)),
    merge: (previous, incoming) => incoming,
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 50)),
  );

  Job<void> setVolume(double value) => _volume.add(value);

  // The callback is removed before the state is final: after that, a call
  // to `externalSetState` would throw a `StateError`.
  @override
  void onClose() => device.onDisconnect = null;
}
```

At the call site a job is a handle: await its outcome, or cancel it as the
quick start does.

```dart
final player = Player(api, device);

final job = player.play('t-1');
switch (await job.done) {
  case Done(:final value):
    print('playing $value');
  case Failed(:final error):
    print('failed: $error');
  case Cancelled(:final reason):
    print('cancelled: $reason');
}

player.setVolume(0.4);
// Stop taking new work now, run what is already queued, then close.
await player.close(mode: SoloCloseMode.drain);
```

`setVolume` hands back a job too, and the call site drops it on purpose:
nothing here can answer for a volume the device refuses. Its failure goes on to
the zone, as
[Handled and unhandled failures](doc/errors.md#handled-and-unhandled-failures)
on the errors page has it, since no `unansweredHandler` is set, and ends this
plain Dart program. A caller that can answer for it reads the job's `done`, as
the call site does for `play`.

## Why `currentState` and not `state`

Say the name in [Quick start](#quick-start) is fetched for the user of the
session. The session is another controller, and `ProfileController` keeps it in
the field `session`. The profile API now takes the user: `fetchName(user)`. A
method that reloads a loaded profile:

```dart
Job<String> reload() => enqueue<Loaded, String>((ctx) async {
  // Another controller's snapshot: a plain read, and the name says
  // as much.
  final user = session.currentState.user;
  final name = await ctx.abandonable(() => api.fetchName(user));
  // This job's own state: a checkpoint that throws `Cancelled` if
  // the job has been cancelled or the state is no longer `Loaded`.
  if (ctx.state.name != name) {
    ctx.emit(Loaded(name));
  }
  return name;
});
```

`enqueue<Loaded, String>` names two types: the job's working type `W`, the
states its body works with, which may be narrower than the controller's state
type `S`, and its result type. Left out, as in the quick start, they are
inferred: `W` is then the whole of `S`, and the result type is what the body
returns.

A job body is a closure inside a method of the controller, so every member of
the controller is in scope there. `ctx.state` is a checkpoint. Before it reads,
it checks that the job has not been cancelled and that its rules still hold:
the working type, here `Loaded`, and the `keepWhile` rule of a job that has
one, like `play` above. A plain read named `state` would look exactly like
`ctx.state`, and a body that typed it out of habit would read past a
cancellation it was supposed to honour: no `Cancelled`, no check of the rules,
and the whole of `S` instead of `W`, with no `name` to read. So the
controller's own read is named `currentState`: a bare `state` in a body does
not compile, and nobody types `currentState` by habit where a checkpoint is
meant.

Outside a job `currentState` is the read to use. Inside one it stays right for
a different controller: `session.currentState` above is somebody else's
snapshot, and this job's rules have nothing to say about it.

## Guides

Also on the [documentation site](https://docs.yet-another.dev/solo/), with
search.

The first three pages are for every controller, in this order: jobs, state,
cancellation. The next five come when a controller needs what they cover:
resources, children, streams, accumulation and its rules. Diagnostics, errors
and testing are for a controller about to ship, the common mistakes are a list
to check against, and the reference names every member with the section that
explains it. Flutter is for a controller behind a screen, the camera example
puts the pages together in one controller, and solo and bloc side by side is
for a reader who comes from bloc.

| Page | What it covers |
| --- | --- |
| [Jobs and the queue](doc/jobs.md) | Submitting work, outcomes, keys, queue policies |
| [State](doc/state.md) | Emitting, rules, observing, external changes, state after failure |
| [Cancellation](doc/cancellation.md) | `abandonable`, `join`, `pause`, `uncancellable`, `timeout`, stopping the operation, closing |
| [Resources and cleanup](doc/resources.md) | `onDispose`, `dispose` and `discard`, transfer, ordering |
| [Children and chains](doc/children.md) | Child jobs, chains, steps in a row |
| [Streams](doc/streams.md) | `ctx.each` in a controller, following another controller |
| [Event accumulation](doc/accumulation.md) | `collect`, `accumulate`, debounce and throttle in four recipes |
| [Accumulation rules](doc/accumulation-rules.md) | When a group is ready, `AccumulationPolicy`, one job for a group and `shared()`, `merge`, `close()` |
| [Diagnostics](doc/diagnostics.md) | `SoloObserver`, `pending`, logs, a slow cancellation |
| [Errors](doc/errors.md) | `onError`, `unansweredHandler`, catching and retrying, `ctx.unattended` |
| [Testing](doc/testing.md) | Awaiting outcomes, fake time, timeouts |
| [Common mistakes](doc/mistakes.md) | Seven mistakes that often pass a first test, and the right way for each |
| [Reference](doc/reference.md) | Every member of `Solo`, its context, jobs, queue and accumulators, with the section that explains it |
| [Flutter](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.md) | The `flutter_solo` package: `SoloListenable`, owning a controller, rebuilding a screen |
| [Camera example](doc/camera.md) | One controller with rules, cleanup and a device |
| [solo and bloc, side by side](doc/vs-bloc.md) | Eleven scenarios in both packages |

## Recipes

Situations that come up, and what to reach for. Each one is explained in the
section linked beside it.

| Situation | Reach for | Where |
| --- | --- | --- |
| Only the last of a burst of commands matters | `accumulate` with a `merge` that keeps the incoming value | [Commands where only the last one counts](doc/accumulation.md#commands-where-only-the-last-one-counts) |
| Typing into a search box | `accumulate` with `AccumulationTiming.debounce` | [A search that fires on every keystroke](doc/accumulation.md#a-search-that-fires-on-every-keystroke) |
| A later request must not be dropped as a duplicate of an earlier one | a record key, `(_Op.load, id)` | [A key for each request](doc/jobs.md#a-key-for-each-request) |
| Queued work is made pointless by what just arrived | `queue.removeWhere` before submitting, or `cancelAll()` if it may be running | [When they are separate jobs after all](doc/accumulation.md#when-they-are-separate-jobs-after-all) |
| A last batch has to go out before the screen goes away | `close(mode: SoloCloseMode.drain)` | [Cancelling and closing a controller](doc/cancellation.md#cancelling-and-closing-a-controller) |
| `close()` does not come back | `controller.pending` | [What is holding the controller](doc/diagnostics.md#what-is-holding-the-controller) |
| A journal needs to say which operation changed the state | `SoloTransition` in `onChange` | [Watching every controller](doc/diagnostics.md#watching-every-controller) |
| A cancelled job must wait for the call it started | `ctx.join` | [Each wait in its place](doc/cancellation.md#each-wait-in-its-place) |
| A call fails now and then and should be tried again | a loop in the body with `ctx.pause` between attempts | [Retrying a failed call](doc/errors.md#retrying-a-failed-call) |
| A step of several calls must not be interrupted halfway | `ctx.uncancellable` | [Protecting a step or a whole job](doc/cancellation.md#protecting-a-step-or-a-whole-job) |
| A resource opened by a call nobody waited for still has to close | `dispose` or `discard` on `ctx.abandonable` and `ctx.join` | [Taking a resource from a call](doc/resources.md#taking-a-resource-from-a-call) |
| A widget rebuilds for state it does not use | `SoloSelector` from `flutter_solo` | [Selecting one value](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.md#selecting-one-value) |
| The queue has to stand still for a while | a job waiting on a `Completer` at the head of it | [Pausing the queue](doc/jobs.md#pausing-the-queue) |
| A job has to start later, and the queue must not wait for it | a `Job` of its own for the wait, cancelled from `cancelAll` and `onClose` | [A delayed start](doc/jobs.md#a-delayed-start) |
| A tap must not wait for a long reload of the same screen | a controller of its own for the taps, and marks the reload settles | [A tap that does not wait for a reload](doc/jobs.md#a-tap-that-does-not-wait-for-a-reload) |
| The screen has to show news until the user closes it, and the camera must go on working | a controller of its own for the notices, and an acceptance that names the notice | [A notice the screen accepts](doc/state.md#a-notice-the-screen-accepts) |
| A stream event arrives a microtask late, and that is too late | `addListener`, which calls back inside the change | [Observing state](doc/state.md#observing-state) |

## Versions

| A change | Comes in |
| --- | --- |
| A fix that keeps the public API | a patch release, such as `1.0.1` |
| A new class, member or optional parameter | a minor release, such as `1.1.0` |
| A removed or renamed member, a changed signature or documented behaviour | a major release, such as `2.0.0` |

From 1.0.0 on, `solo` follows semantic versioning: the constraint `^1.0.0`
takes every minor and patch release, and they keep code written against 1.0.0
working, but for the cases below. The public API is what
`package:solo/solo.dart` and `package:solo/listeners.dart` export; the text of
error messages and of debug output is not part of it. A member that goes away
is first marked `@Deprecated` in a minor release, with the name to use instead,
and is removed in the next major one.

A minor release can add a member to a class you extend, such as `Solo` or
`SoloObserver`, and a member of the same name in your own code then stops
compiling. It can add a member to an interface you implement for a mock, such
as `JobContext` or `SoloContext`, and a fake that implements it by hand, rather
than through `noSuchMethod`, then stops compiling too. The changelog of such a
release names the members it adds. A new top-level name can clash with the same
name imported from another package, until one of the imports hides it with
`hide`.

`solo` re-exports `async_job`, so a major release of `async_job` comes with a
major release of `solo`. `solo` is also an engine on the protocol of
`package:async_job/engine.dart`, which can change in a minor release: each
release of `solo` holds `async_job` to one minor version, and a minor release
of `async_job` comes with a minor release of `solo`. A new minor version of
`async_job` reaches you with that release of `solo`: until it is out, an app
that asks for the new `async_job` itself does not resolve.

## Coming from bloc

Callers invoke controller methods and receive a job for each operation. Queue
policy is selected per call, and all root jobs share one queue.
[solo and bloc, side by side](doc/vs-bloc.md) holds the API correspondences and
compares eleven application scenarios with implementations in both packages.

The package does not include retry policies, worker pools, dependency
injection, persistence or state equality filtering. If work needs cancellation
and cleanup but no state rules or controller queue,
[async_job](https://pub.dev/packages/async_job) can be used directly. For a
value with no asynchronous lifecycle, a `ValueNotifier` may suffice.
