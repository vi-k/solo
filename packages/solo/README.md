# solo

`solo` manages state and asynchronous work in Dart. A controller holds the
current state and processes jobs one at a time. Each job can declare which
states allow it to start and continue, and callers can await its result or
request cancellation.

Use it for screens, sessions and devices where operations share state and need
an explicit order. The package has no Flutter dependency.
[`flutter_solo`](https://pub.dev/packages/flutter_solo) adds `SoloListenable`,
a mixin that makes a controller a `ValueListenable` for Flutter widgets.

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

## Quick start

A controller exposes methods for application operations. Here, `load()` loads a
profile name and reports progress through four immutable states:

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

final class Failure extends ProfileState {
  final Object error;

  const Failure(this.error);
}
```

The example API returns a name after a short delay. Replace it with your
application's API client:

```dart
class ProfileApi {
  Future<String> fetchName() => Future.delayed(
        const Duration(milliseconds: 20),
        () => 'Ada Lovelace',
      );
}

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        onError: (state, error, stackTrace) => Failure(error),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.abandonable(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}
```

`run<ProfileState, String>` creates and queues a job. `ProfileState` is the
job's working type `W`: the states its body works with, which may be narrower
than the controller's state type `S`. `String` is the job's result type. The
body receives a context, `ctx`, which provides state updates and
cancellation-aware waiting:

- `ctx.emit` updates the controller's state.
- `ctx.abandonable` waits for the API response, or throws `Cancelled` if the
  job accepts cancellation while waiting.

Two parameters of `run` give the state to publish when the job does not
succeed:

- `onError` returns the state to publish if the job fails.
- `onCancel` returns the state to publish if a started job is cancelled.

The state handlers run after the body and its cleanup. In this example, the
state becomes `Loaded` on success, `Failure` on error, or `Initial` on
cancellation. The job's outcome stays `Failed` or `Cancelled` even when a
handler updates the state.

`Policy.droppable` and `key: 'load'` make repeated calls share the queued or
running load. A second call returns the existing job. Once that job finishes,
another call can start a new load.

The caller uses the returned `Job<String>` to await this particular load:

```dart
Future<void> main() async {
  final profile = ProfileController(ProfileApi());
  void onChange() => print(profile.currentState);
  profile.addListener(onChange);
  try {
    final job = profile.load();
    profile.load(); // the existing job is returned

    print(await job.value);
    if (profile.currentState case Loaded(:final name)) {
      print(name);
    }
  } finally {
    profile.removeListener(onChange);
    await profile.close();
  }
}
```

`profile.currentState` is available synchronously, and `addListener` calls back
synchronously too, inside the change itself. `job.value` returns the loaded
name, or throws the job's error or `Cancelled`. The `finally` block removes the
listener and closes the controller even if loading fails.

For a broadcast `stream` as well, delivered on the next microtask, mix in
`SoloStream`:

```dart
final class ProfileController extends Solo<ProfileState> with SoloStream {
  // ...same as above...
}
```

See [Observing state](doc/state.md#observing-state) on the state page for the
full delivery picture, including `SoloListenable` from `flutter_solo`.

Cancellation uses the same job object. This separate example requests
cancellation immediately, so the job is still in the queue:

```dart
Future<void> cancelLoading() async {
  final profile = ProfileController(ProfileApi());
  final job = profile.load();

  await job.cancel();
  print(job.outcome); // Cancelled(manual)
  await profile.close();
}
```

`cancel()` waits for the job to finish, including cleanup if it started. A job
cancelled before its body starts does not call `onCancel`. Jobs can start child
jobs as part of their work; the starting job is their parent and waits for them
before finishing. The next queued job starts only after the previous job
finishes its body, children, cleanup and state handler.

The guides below explain results, queue policies and cancellation in more
detail. In particular, cancellation of a job does not automatically stop an API
request that has already been sent.

## Why `currentState` and not `state`

Say `ProfileController` also holds `session`, another controller, and the
profile API takes the user: `fetchName(user)`. A method that reloads a loaded
profile:

```dart
Job<String> reload() => run<Loaded, String>(
      (ctx) async {
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
      },
    );
```

A job body is a closure inside a method of the controller, so every member of
the controller is in scope there. `ctx.state` is a checkpoint. Before it reads,
it checks that the job has not been cancelled and that its rules still hold:
the working type, here `Loaded`, and the `keepWhile` rule of a job that has
one, like `play` below. A plain read named `state` would look exactly like
`ctx.state`, and a body that typed it out of habit would read past a
cancellation it was supposed to honour: no `Cancelled`, no check of the rules,
and the whole of `S` instead of `W`, with no `name` to read. The controller's
own read is named `currentState`: a bare `state` in a body does not compile,
and nobody types `currentState` by habit where a checkpoint is meant.

Outside a job `currentState` is the read to use. Inside one it stays right for
a different controller: `session.currentState` above is somebody else's
snapshot, and this job's rules have nothing to say about it.

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
  Job<Track> play(String id) => run<PlayerState, Track>(
        // Any object is a key. This one keys the operation, not a track.
        key: _Op.play,
        // A new play cancels the one running under the same key.
        policy: Policy.restart,
        // A rule: asked before the start, and on every change of state
        // while the body runs, except one the body makes with `ctx.emit`.
        keepWhile: (state) => state is! Disconnected,
        // The state to publish when the job fails or is cancelled. A
        // cancellation by the rule publishes nothing: `Disconnected` stays.
        onError: (state, error, stackTrace) => const Idle(),
        onCancel: (state, cancelled) => const Idle(),
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
          // A child job: the device reads the download in, and the stream
          // ends when the track starts. `value` waits for that.
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

  // The callback is removed before the state is final: after that,
  // `externalSetState` would throw.
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

## Guides

Also on the [documentation site](https://docs.yet-another.dev/solo/), with
search.

| Page | What it covers |
| --- | --- |
| [Jobs and the queue](doc/jobs.md) | Submitting work, outcomes, keys, queue policies |
| [State](doc/state.md) | Emitting, rules, observing, external changes, state after failure |
| [Cancellation](doc/cancellation.md) | `abandonable`, `join`, `pause`, `uncancellable`, stopping the operation, closing |
| [Resources and cleanup](doc/resources.md) | `onDispose`, `dispose` and `discard`, transfer, ordering |
| [Children and streams](doc/children.md) | Child jobs, chains, steps in a row |
| [Streams](doc/streams.md) | `ctx.each` in a controller, following another controller |
| [Event accumulation](doc/accumulation.md) | `collect`, `accumulate`, debounce and throttle |
| [Errors and observation](doc/errors.md) | `SoloObserver`, `errorHandler`, `pending`, logs |
| [Testing](doc/testing.md) | Awaiting outcomes, fake time, timeouts |
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
| `close()` does not come back | `controller.pending` | [What is holding the controller](doc/errors.md#what-is-holding-the-controller) |
| A journal needs to say which operation changed the state | `SoloTransition` in `onChange` | [Watching every controller](doc/errors.md#watching-every-controller) |
| A call must finish before the queue goes on | `ctx.join` | [Cancellation](doc/cancellation.md) |
| A step of several calls must not be interrupted halfway | `ctx.uncancellable` | [Protecting a step or a whole job](doc/cancellation.md#protecting-a-step-or-a-whole-job) |
| A resource opened by a call nobody waited for still has to close | `dispose` or `discard` on `ctx.abandonable` and `ctx.join` | [Taking a resource from a call](doc/resources.md#taking-a-resource-from-a-call) |
| A widget rebuilds for state it does not use | `SoloSelector` from `flutter_solo` | [Selecting one value](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.md#selecting-one-value) |
| The queue has to stand still for a while | a job waiting on a `Completer` at the head of it | [Pausing the queue](doc/jobs.md#pausing-the-queue) |
| A stream event arrives a microtask late, and that is too late | `addListener`, which calls back inside the change | [Observing state](doc/state.md#observing-state) |

## Coming from bloc

Callers invoke controller methods and receive a job for each operation. Queue
policy is selected per call, and all root jobs share one queue.
[solo and bloc, side by side](doc/vs-bloc.md) holds the API correspondences and
compares eleven application scenarios with implementations in both packages.

The package does not include retry policies, built-in timeouts, worker pools,
dependency injection, persistence or state equality filtering. If work needs
cancellation and cleanup but no state rules or controller queue,
[async_job](https://pub.dev/packages/async_job) can be used directly. For a
value with no asynchronous lifecycle, a `ValueNotifier` may suffice.
