# solo

One job at a time: sequential jobs with exclusive state ownership,
declarative rules and cooperative cancellation. Pure Dart, no Flutter
dependency; [`flutter_solo`](https://pub.dev/packages/flutter_solo) adds the
`ValueListenable` face.

## Why

`solo` grew out of six complaints about bloc:

1. the event queue cannot be managed;
2. when every event is `sequential`, a single one of them cannot be made
   `restartable` without moving it to a separate queue;
3. events running in parallel write to one and the same state;
4. after cancellation the handler keeps running until it checks
   `emit.isDone` itself;
5. you cannot await your own event: the `stream` tells you the state
   changed, not who changed it;
6. from the outside you want to call a method, not build an event and
   `add` it.

## Install

```sh
dart pub add solo
```

For Flutter, take `flutter_solo` instead — it re-exports all of `solo`:

```sh
flutter pub add flutter_solo
```

## Quick start

A camera controller. The state is a sealed hierarchy; `NotDisposed` is a
union interface that jobs can declare as their working type:

```dart
sealed class CameraState {
  const CameraState();
}

sealed class NotDisposed extends CameraState {
  const NotDisposed();
}

final class Initial extends NotDisposed {
  const Initial();
}

final class Preparing extends NotDisposed {
  const Preparing();
}

final class Ready extends NotDisposed {
  final double zoom;
  final bool paused;

  const Ready({this.zoom = 1, this.paused = false});

  Ready copyWith({double? zoom, bool? paused}) =>
      Ready(zoom: zoom ?? this.zoom, paused: paused ?? this.paused);
}

final class Disposed extends CameraState {
  const Disposed();
}
```

The controller is a plain class with plain methods. Each method builds a
job and hands it to the queue; the handle it returns is not a `Future`, so
calling the method without `await` is legal and raises no lint:

```dart
enum CameraKey { init, closeCamera, setZoom, takePhoto, dispose }

final class CameraController extends Solo<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

  Job<void> init() => run<NotDisposed, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        canStart: (state) => state is Initial,
        (ctx) async {
          ctx.emit(const Preparing());
          await ctx.guard(hw.open);
          ctx.emit(const Ready());
        },
      );

  Job<void> setZoom(double zoom) => run<Ready, void>(
        key: CameraKey.setZoom,
        policy: Policy.replace,
        describe: () => 'zoom: $zoom',
        canStart: (state) => !state.paused,
        (ctx) async {
          await ctx.guard(() => hw.setZoom(zoom));
          ctx.emit(ctx.state.copyWith(zoom: zoom));
        },
      );

  Job<Photo> takePhoto() => run<Ready, Photo>(
        key: CameraKey.takePhoto,
        policy: Policy.droppable,
        canStart: (state) => !state.paused,
        (ctx) async {
          final photo = await ctx.guard(hw.capture);
          queue.clear();
          ctx.log('captured $photo');
          return photo;
        },
      );

  Job<void> _closeCameraJob() => job<NotDisposed, void>(
        key: CameraKey.closeCamera,
        cancellable: false,
        (ctx) async => hw.close(),
      );

  Job<void> dispose() {
    queue.clear(force: true);
    current?.cancel();
    return run<CameraState, void>(
      key: CameraKey.dispose,
      policy: Policy.droppable,
      cancellable: false,
      (ctx) async {
        if (ctx.state is Disposed) {
          return;
        }
        if (ctx.state is! Initial) {
          await ctx.run(_closeCameraJob()).done;
        }
        ctx.emit(const Disposed());
      },
    );
  }
}
```

From the outside:

```dart
final camera = CameraController(FakeCameraHardware());
await camera.init().done;

camera.setZoom(2); // no await needed, and no lint about it

final photo = await camera.takePhoto().value;

switch (await camera.dispose().done) {
  case Done():
    print('disposed');
  case Cancelled(:final reason):
    print('cancelled: $reason');
  case Failed(:final error):
    print('failed: $error');
}

await camera.close();
```

Jobs run one after another, in queue order, and never overlap. A `setZoom`
added while an earlier `setZoom` still waits in the queue throws that queued
one away and takes its place; a `setZoom` that already started is left to
finish — that is `Policy.replace`. A `takePhoto` added while a shot is in
flight returns the shot already running instead of queueing a second one —
that is `Policy.droppable`. `dispose` clears the queue, cancels whatever
runs, and then runs itself as a job that nothing can cancel.

## Concepts

**State.** One immutable object of type `S`, usually a sealed hierarchy
with union interfaces (`NotDisposed`, `Initialized`) so that jobs can
declare a working type wider than a single class. `solo.state` is readable
by anyone at any time; only jobs write.

**Controller.** The owner of the state and of the queue. The hierarchy is
linear: `SoloBase<S>` is the engine and `state`; `Solo<S>` adds a broadcast
`stream`; `SoloListenable<S>` in `flutter_solo` adds `ValueListenable`.
They differ only in how a change is delivered.

**Job.** A unit of work: an `async` body `Future<T> Function(JobContext)`,
an optional `key`, rules, and a handle `Job<T>`. `job(...)` builds one
without queueing it, `add(job, policy: ...)` queues it, `run(...)` does
both in one call. At most one root job runs at a time, and while it runs no
other job of this controller touches the state.

**Working type `W`.** The subtype of `S` a job agrees to work with. The
body sees `ctx.state` already narrowed to `W`. The type is checked before
the job starts, on every state change while it runs, and on every read
through the context.

**Rules.** `canStart` is checked once, when the job is taken from the
queue; failing it drops the job with `Cancelled(rules, 'canStart')` and
`started: false`. `keepWhile` is checked continuously — and also before the
start, together with `canStart`: a job whose invariant is already broken
never starts, instead of starting and dying on its first read.

**Cancellation.** Cooperative: Dart cannot interrupt somebody else's
`await`. A cancelled job learns about it the next time it touches the
context — every `JobContext` member except `log` and `job` throws the job's
`Cancelled` once the job is marked. After a bare `await`, call
`ctx.check()`. To wait for something and give up on cancellation at once,
wrap it in `ctx.guard(() => ...)`: the guard returns as soon as either the
action or the cancellation arrives.

**Children.** `ctx.run(child)` starts a job right now, bypassing the queue,
as a child of the current one. The parent finishes only after all of its
children. `ctx.run(child).done` gives the outcome and never throws;
`ctx.run(child).value` gives the value and throws the child's `Cancelled`
or error into the parent's body.

**External state.** `externalSetState(next)` sets the state from outside
any job: a hardware listener, a forced transition. Every running job except
the one that emitted is re-evaluated against the new state immediately; the
emitting job is checked lazily, on its next read.

**Outcomes.** `Outcome<T>` is sealed, so a `switch` over its three cases is
exhaustive: `Done` carries the returned `value`, `Failed` carries `error`
and `stackTrace`, `Cancelled` carries a `reason`, a `started` flag, an
optional `description` and the stack trace of the cancellation itself. The
reason is a `CancelReason`: `manual`, `rules`, `closed`, `parent`,
`handler`. `job.done` completes with the outcome and never throws;
`job.value` completes with the value or throws; `job.whenCancelled`
completes the moment the job is marked cancelled, before the body finishes;
`job.cancel()` cancels and waits for the job to actually finish.

**Queue and policies.** `queue` is a first-class object visible to
subclasses: `jobs`, `remove`, `removeWhere`, `clear`, `lastWhere`. The three
removing methods skip `cancellable: false` jobs unless given `force: true`,
and none of them touches the running job. Policies are sugar over the common
case of one key: `sequential` appends; `droppable` returns the queued or
running job with the same key and drops the new one; `replace` removes
queued jobs with the same key; `restart` additionally cancels the running
one without waiting for it. `add(job, first: true)` puts a job at the head.

**Stream.** `Solo.stream` is a broadcast stream of every state change, in
order, delivered on the next microtask — the stream is asynchronous. The
source of truth is `state`: by the time an event arrives, `state` may
already be newer. Equality is not checked; each change is one event. In
`flutter_solo`, `SoloListenable` listeners are called synchronously,
in subscription order, while the stream event is still on its way.

## Rules that are not visible in signatures

`cancellable: false` protects a job from actors: a manual `cancel`, a
`clear` without `force`, the cancellation of its parent, `close`. It does
not protect it from reality: if the state stopped matching `W` or
`keepWhile`, the job is cancelled anyway, because there is nothing left for
it to read. A non-cancellable job that must survive any state needs the
base type `S` and no `keepWhile`.

`emit` is trusted, reads are checked. The emitted state is not verified
against the rules of the job that emitted it — otherwise a `close` job
declared as `run<NotClosed, void>` would cancel itself the moment it
emitted `Closed()`.

`ctx.run(child)` returns a handle, not a value. `await ctx.run(child).value`
throws into the parent; `switch (await ctx.run(child).done)` does not. A
forgotten `await` breaks nothing: the parent waits for its children in any
case.

A job handed to `ctx.run` becomes a child even if it is dropped before it
starts. It is registered as a child first, and only then checked against
the rules, so a parent always accounts for every job it tried to run.

`add` on a closed controller does not throw. It returns a job that is
already finished with `Cancelled(closed)`, so call sites need no
`isClosed` check.

Any policy other than `sequential` with `key == null` throws
`ArgumentError`, not an `assert`: in release mode `null == null` is true
and `replace` would wipe every keyless job in the queue.

`ctx.emit` and `ctx.run` after the job has finished throw `StateError`. A
context that leaked out of its job — captured by a closure nobody awaited —
must not write the state outside the critical section. Reads (`state`,
`stateAs`, `check`, `guard`, `log`) after the job finished are allowed.

`close()` awaited from inside the current job's body never completes: it
waits for that very body. The same holds for `cancelAll()`. Cancel from the
inside by returning or by throwing `Cancelled('why')`.

From inside a job body the whole surface of the `Solo` subclass is visible,
so there is no `ctx.solo`.

## Recipes

**Timeout.** The engine knows nothing about timeouts; `guard` plus
`Future.timeout` is the whole recipe. On a timeout the body throws, and the
job ends up `Failed`:

```dart
Job<void> connect() => run<Idle, void>(
      key: 'connect',
      (ctx) async {
        await ctx.guard(
          () => hw.open().timeout(const Duration(seconds: 5)),
        );
        ctx.emit(const Connected());
      },
    );
```

**Debounce.** Also outside the engine: hold a `Timer` in the controller and
start the job when it fires. Combine it with `Policy.restart`, so that a job
still running for the previous input is cancelled rather than awaited:

```dart
import 'dart:async';

final class Search extends Solo<SearchState> {
  Timer? _debounce;

  Search() : super(const SearchState.idle());

  void query(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      run<SearchState, void>(
        key: 'query',
        policy: Policy.restart,
        describe: () => text,
        (ctx) async {
          final results = await ctx.guard(() => api.search(text));
          ctx.emit(SearchState.results(results));
        },
      );
    });
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
```

**Hooks.** A controller can override `onStart`, `onFinish`, `onError`,
`onLog` and `onChange` to react to its own jobs:

```dart
final class CameraController extends Solo<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

  // ...the jobs above...

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    reportCrash(error, stackTrace);
  }
}
```

**Observer.** `SoloObserver` is the cross-cutting version of the same five
hooks plus `onCreate` and `onClose`: analytics, error reporting, one log for
every controller in the process. The engine calls the observer before the
controller's own hook, and independently of it — a subclass that forgets
`super` does not switch the observer off:

```dart
final class LoggingObserver extends SoloObserver {
  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job finished ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      print('state: $current');
}

void main() {
  SoloBase.observer = LoggingObserver();
}
```

To trace the engine itself rather than the jobs, set
`SoloBase.debug = print`.

## Flutter

`flutter_solo` adds `SoloListenable<S> extends Solo<S> implements
ValueListenable<S>`, and re-exports all of `solo`. The only change to the
controller is its base class — the jobs above stay exactly as they are, and
the controller then goes straight into `ValueListenableBuilder`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

final class CameraController extends SoloListenable<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

  // ...the jobs above...
}

class CameraView extends StatelessWidget {
  const CameraView({super.key, required this.camera});

  final CameraController camera;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<CameraState>(
        valueListenable: camera,
        builder: (context, state, _) => switch (state) {
          Ready(:final zoom) => Text('zoom $zoom'),
          _ => const CircularProgressIndicator(),
        },
      );
}
```

`value` and `state` are the same object. There is no setter on purpose: a
`ValueNotifier` face would be a hole in the ownership guarantee.

## Example

[`example/`](example) is a runnable package: a fake camera whose hardware
answers late and may break on its own, the controller above in full, four
tests over an ordered journal, and `bin/main.dart` that prints the same
journal in real time.

```sh
cd example
dart run bin/main.dart
dart test
```
