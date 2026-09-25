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
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}
```

`run<ProfileState, String>` creates and queues a job. `ProfileState` is the
state type its body can work with; `String` is its result type. The body
receives a context, `ctx`, which provides state updates and cancellation-aware
waiting:

- `ctx.emit` updates the controller's state.
- `ctx.wait` waits for the API response, or throws `Cancelled` if the job
  accepts cancellation while waiting.
- `onError` returns the state to publish if the job fails.
- `onCancel` returns the state to publish if a started job is cancelled.

The state handlers run after the body and its cleanup. In this example, the
state becomes `Loaded` on success, `Failure` on error, or `Initial` on
cancellation. Failure and cancellation remain the job's outcome even when a
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

Mix in `SoloStream` instead for a broadcast `stream`, delivered on the next
microtask:

```dart
final class ProfileController extends Solo<ProfileState> with SoloStream {
  // ...same as above...
}
```

See [Observing state](doc/state.md#observing-state) on the state page for the
full delivery picture, including `SoloListenable` from `flutter_solo`.

Cancellation uses the same job object. This separate example requests
cancellation immediately, so the job may still be in the queue:

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

A method of `ProfileController` that also watches a session:

```dart
Job<String> reload() => run<ProfileState, String>(
      (ctx) async {
        // Another controller's snapshot: a plain read, and the name says
        // as much.
        final user = session.currentState.user;
        final name = await ctx.wait(() => api.fetchName(user));
        // This job's own state: a checkpoint that throws `Cancelled` if
        // the load lost the state while it waited.
        if (ctx.state case Loading()) {
          ctx.emit(Loaded(name));
        }
        return name;
      },
    );
```

A job body is a closure inside a method of the controller, so every member of
the controller is in scope there. A plain read named `state` would look exactly
like `ctx.state`, and a body that typed it out of habit would read past a
cancellation it was supposed to honour: no `Cancelled`, no `keepWhile` check,
and the whole of `S` instead of the job's working type `W`. Nobody writes
`currentState` by habit where a checkpoint is meant, so what used to be a
silent read is a compile error.

Outside a job `currentState` is the read to use. Inside one it stays right for
a different controller: `session.currentState` above is somebody else's
snapshot, and this job's rules have nothing to say about it.

## The dozen calls

Everything reached for day to day, in one controller. `PlayerState`, `Api` and
`Device` belong to the application; the rest is the package.

```dart
enum _Op { play }

final class Player extends Solo<PlayerState> {
  final Api api;
  final Device device;

  Player(this.api, this.device) : super(const Idle());

  /// A job on the controller's queue. Root jobs run one at a time.
  SoloJob<Track> play(String id) => run<PlayerState, Track>(
        // Any object is a key. A record keys one request, not an operation.
        key: (_Op.play, id),
        // A new play cancels the one running under the same key.
        policy: Policy.restart,
        // Rules: checked before the start, and at every checkpoint after.
        canStart: (state) => state is! Disconnected,
        keepWhile: (state) => state is! Disconnected,
        (ctx) async {
          // The only way to change state. There is no setter outside.
          ctx.emit(const Loading());
          // Cancellation ends this wait at once; the request may go on.
          final track = await ctx.wait(() => api.fetch(id));
          // This one is waited out whatever happens, and the value is
          // released if the job ends before the body could take it.
          final handle = await ctx.join(
            () => device.open(track),
            dispose: (handle) => handle.close(),
          );
          // Cleanup runs in reverse order, on every outcome: playback
          // stops, then the handle closes. Register each release once.
          ctx.onDispose(device.stop);
          // A child job: the parent waits for it before it finishes.
          ctx.each(device.position, (childCtx, position) async {
            childCtx.emit(Playing(track, position));
          });
          return track;
        },
      );

  /// Events that share one queued job: only the last volume matters.
  late final _volume = accumulate<PlayerState, double, void>(
    (ctx, value) => ctx.join(() => device.setVolume(value)),
    merge: (previous, incoming) => incoming,
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 50)),
  );

  SoloJob<void> setVolume(double value) => _volume.add(value);
}
```

At the call site a job is a handle: await its outcome, or cancel it.

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
// Run what is already queued, then stop accepting work.
await player.close(mode: SoloCloseMode.drain);
```

## Guides

Also on the [documentation site](https://docs.yet-another.dev/solo/), with
search.

| Page | What it covers |
| --- | --- |
| [Jobs and the queue](doc/jobs.md) | Submitting work, outcomes, keys, queue policies |
| [State](doc/state.md) | Emitting, rules, observing, external changes, state after failure |
| [Cancellation](doc/cancellation.md) | `wait`, `join`, `uncancellable`, stopping the operation, closing |
| [Resources and cleanup](doc/resources.md) | `onDispose`, `dispose` and `discard`, transfer, ordering |
| [Children and streams](doc/children.md) | Child jobs, streams, following another controller |
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
| A later request must not be dropped as a duplicate of an earlier one | a record key, `(Op.load, id)` | [Queue and policies](doc/jobs.md#queue-and-policies) |
| Queued work is made pointless by what just arrived | `queue.removeWhere` before submitting, or `cancelAll()` if it may be running | [When they are separate jobs after all](doc/accumulation.md#when-they-are-separate-jobs-after-all) |
| A last batch has to go out before the screen goes away | `close(mode: SoloCloseMode.drain)` | [Cancelling and closing a controller](doc/cancellation.md#cancelling-and-closing-a-controller) |
| `close()` does not come back | `Solo.pending` | [What is holding the controller](doc/errors.md#what-is-holding-the-controller) |
| A journal needs to say which operation changed the state | `SoloTransition` in `onChange` | [Watching every controller](doc/errors.md#watching-every-controller) |
| A step must not be interrupted halfway | `ctx.join` for a call, `ctx.uncancellable` for a step | [Protecting a step or a whole job](doc/cancellation.md#protecting-a-step-or-a-whole-job) |
| A resource opened by a call nobody waited for still has to close | `dispose` or `discard` on `ctx.wait` and `ctx.join` | [Taking a resource from a call](doc/resources.md#taking-a-resource-from-a-call) |
| A widget rebuilds for state it does not use | `SoloSelector` from `flutter_solo` | [Selecting one value](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.md#selecting-one-value) |
| The queue has to stand still for a while | a job waiting on a `Completer` at the head of it | [Pausing the queue](doc/jobs.md#pausing-the-queue) |
| A stream event arrives a microtask late, and that is too late | `publish` on a `Solo` subclass, notifying inside the change | [A delivery of your own](doc/state.md#a-delivery-of-your-own) |

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
