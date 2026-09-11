# solo

`solo` manages state and asynchronous work in Dart. A controller holds
the current state and processes jobs one at a time. Each job can declare
which states allow it to start and continue, and callers can await its
result or request cancellation.

Use it for screens, sessions and devices where operations share state
and need an explicit order. The package has no Flutter dependency.
[`flutter_solo`](https://pub.dev/packages/flutter_solo) adds a controller
that implements `ValueListenable` for Flutter widgets.

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
`package:solo/solo.dart`, gives access to both APIs. You do not need to
learn the underlying package before using the examples below.

## Quick start

A controller exposes methods for application operations. Here, `load()`
loads a profile name and reports progress through four immutable states:

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

`run<ProfileState, String>` creates and queues a job. `ProfileState` is
the state type its body can work with; `String` is its result type.
The body receives a context, `ctx`, which provides state updates and
cancellation-aware waiting:

- `ctx.emit` updates the controller's state.
- `ctx.wait` waits for the API response, or throws `Cancelled` if the job
  accepts cancellation while waiting.
- `onError` returns the state to publish if the job fails.
- `onCancel` returns the state to publish if a started job is cancelled.

The state handlers run after the body and its cleanup. In this example,
the state becomes `Loaded` on success, `Failure` on error, or `Initial`
on cancellation. Failure and cancellation remain the job's outcome even
when a handler updates the state.

`Policy.droppable` and `key: 'load'` make repeated calls share the queued
or running load. A second call returns the existing job. Once that job
finishes, another call can start a new load.

The caller uses the returned `Job<String>` to await this particular load:

```dart
Future<void> main() async {
  final profile = ProfileController(ProfileApi());
  final subscription = profile.stream.listen(print);
  try {
    final job = profile.load();
    profile.load(); // the existing job is returned

    print(await job.value);
    if (profile.state case Loaded(:final name)) {
      print(name);
    }
  } finally {
    await subscription.cancel();
    await profile.close();
  }
}
```

`profile.state` is available synchronously. `profile.stream` broadcasts
changes asynchronously. `job.value` returns the loaded name, or throws
the job's error or `Cancelled`. The `finally` block releases the listener
and closes the controller even if loading fails.

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

`cancel()` waits for the job to finish, including cleanup if it started.
A job cancelled before its body starts does not call `onCancel`.
Jobs can start child jobs as part of their work; the starting job is
their parent and waits for them before finishing.
The next queued job starts only after the previous job finishes its body,
children, cleanup and state handler.

The guides below explain results, queue policies and cancellation in
more detail. In particular, cancellation of a job does not automatically
stop an API request that has already been sent.

## The dozen calls

Everything reached for day to day, in one controller. `PlayerState`,
`Api` and `Device` belong to the application; the rest is the package.

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
          // Cleanup runs in reverse order, on every outcome.
          ctx.onDispose(handle.close);
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

Also on the [documentation site](https://docs.yet-another.dev/solo/), with search.

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
| [Flutter](doc/flutter.md) | `SoloListenable`, owning a controller, rebuilding a screen |
| [Camera example](doc/camera.md) | One controller with rules, cleanup and a device |
| [solo and bloc, side by side](doc/vs-bloc.md) | Ten scenarios in both packages |

## Recipes

Situations that come up, and what to reach for. Each one is explained on
the page named beside it.

| Situation | Reach for | Where |
| --- | --- | --- |
| Only the last of a burst of commands matters | `accumulate` with a `merge` that keeps the incoming value | [Commands where only the last one counts](doc/accumulation.md) |
| Typing into a search box | `accumulate` with `AccumulationTiming.debounce` | [Event accumulation](doc/accumulation.md) |
| A later request must not be dropped as a duplicate of an earlier one | a record key, `(Op.load, id)` | [Jobs and the queue](doc/jobs.md) |
| Queued work is made pointless by what just arrived | `queue.removeWhere` before submitting, or `cancelAll()` if it may be running | [Commands where only the last one counts](doc/accumulation.md) |
| A last batch has to go out before the screen goes away | `close(mode: SoloCloseMode.drain)` | [Cancellation](doc/cancellation.md) |
| `close()` does not come back | `SoloBase.pending` | [Errors and observation](doc/errors.md) |
| A journal needs to say which operation changed the state | `SoloTransition` in `onChange` | [Errors and observation](doc/errors.md) |
| A step must not be interrupted halfway | `ctx.join` for a call, `ctx.uncancellable` for a step | [Cancellation](doc/cancellation.md) |
| A resource opened by a call nobody waited for still has to close | `dispose` or `discard` on `ctx.wait` and `ctx.join` | [Resources and cleanup](doc/resources.md) |
| A widget rebuilds for state it does not use | `select` on `SoloListenable` | [Flutter](doc/flutter.md) |

## Coming from bloc

Callers invoke controller methods and receive a job for each operation.
Queue policy is selected per call, and all root jobs share one queue.
[solo and bloc, side by side](doc/vs-bloc.md) holds the API
correspondences and compares ten application scenarios with
implementations in both packages.

The package does not include retry policies, built-in timeouts, worker
pools, dependency injection, persistence or state equality filtering.
If work needs cancellation and cleanup but no state rules or controller
queue, [async_job](https://pub.dev/packages/async_job) can be used directly.
For a value with no asynchronous lifecycle, a `ValueNotifier` may suffice.
