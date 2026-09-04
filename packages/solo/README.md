# solo

State management for controllers with a lifecycle: one job at a time,
exclusive state ownership, declarative rules and cooperative cancellation.
Pure Dart, no Flutter dependency;
[`flutter_solo`](https://pub.dev/packages/flutter_solo) adds the
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

[solo and bloc, side by side](https://github.com/vi-k/solo/blob/main/packages/solo/doc/vs-bloc.md)
takes eight scenarios from different domains, solves each one in bloc
first — the workaround an experienced team would actually write — and then
in `solo`.

## Install

```sh
dart pub add solo
```

For Flutter, take `flutter_solo` instead — it re-exports all of `solo`:

```sh
flutter pub add flutter_solo
```

## Quick start

The state is one immutable object. A single class is enough to start
with; a sealed hierarchy comes later, when the states differ in what they
allow:

```dart
final class Profile {
  final String name;
  final bool loading;

  const Profile({this.name = '', this.loading = false});

  Profile copyWith({String? name, bool? loading}) =>
      Profile(name: name ?? this.name, loading: loading ?? this.loading);

  @override
  String toString() => 'Profile("$name", loading: $loading)';
}
```

The controller is a plain class with plain methods. Each method builds a
job and hands it to the queue; the handle it returns is not a `Future`, so
calling the method without `await` is legal and raises no lint:

```dart
final class ProfileController extends Solo<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Profile());

  Job<String> load() => run<Profile, String>(
        key: 'load',
        policy: Policy.droppable,
        (ctx) async {
          ctx.emit(ctx.state.copyWith(loading: true));
          final name = await ctx.guard(api.fetchName);
          ctx.emit(Profile(name: name));
          return name;
        },
      );
}
```

From the outside:

```dart
final profile = ProfileController(ProfileApi());
final subscription = profile.stream.listen(print);

final job = profile.load();
profile.load(); // droppable: the same job, not a second one

print(await job.value); // Ada Lovelace; a failure is rethrown here
print(profile.state.name); // the same name, straight from the state

await subscription.cancel();
await profile.close();
```

`run<Profile, String>` says that the job works with `Profile` states and
returns a `String`. Inside the body `ctx.emit` is the only way to write
the state, and `ctx.guard` awaits a future the way `await` does, except
that it gives up the moment the job is cancelled. `Policy.droppable` with
`key: 'load'` means that a second `load()` while the first one is still
queued or running returns that first job instead of starting a second.

Reading is free: `profile.state` is the current state, synchronously, for
anyone; `profile.stream` is a broadcast stream of every change, delivered
one microtask later. Only jobs write, one at a time, in queue order, never
overlapping.

`close()` shuts the controller down for good: queued jobs end with
`Cancelled(closed)`, the running one is cancelled, and later calls return
jobs that are already `Cancelled(closed)` instead of throwing.

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
both in one call. `describe: () => 'zoom: $zoom'` labels the job for logs,
the observer and `toString`, which prints `Job(key: label)` instead of
`Job(key)`. At most one root job runs at a time, and while it runs no
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

**What a guard does not do.** It ends the waiting, not the work. The action
runs to its end and its result is dropped on the floor, which is fine for a
read you can abandon and wrong for anything that must actually stop, or
that must not be started twice at once. Hand the cancellation to the work
itself with `ctx.onCancel(callback)`, which fires the moment the job is
marked, and then wait for the work to finish rather than walking away from
it:

```dart
Job<void> seek(Duration position) => run<Ready, void>(
      key: 'seek',
      policy: Policy.restart,
      (ctx) async {
        final token = CancelToken();
        ctx.onCancel(token.cancel);
        // The device stops on its own, and the job ends only once it has,
        // so the next seek never overlaps this one. If the cancellation
        // arrived while it was stopping, the emit below throws Cancelled.
        await _player.seek(position, cancelToken: token);
        ctx.emit(ctx.state.copyWith(position: position));
      },
    );
```

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
`job.cancel()` cancels and waits for the job to actually finish;
`job.ignore()` says that nobody is going to look at the outcome.

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

`cancellable` is the same question asked twice. At creation it is the
answer for the whole job; inside the body `ctx.cancellable` is the answer
right now, and creation only sets where it starts. Close it around a step
that cannot be taken back — a payment on its way to the server, a write
already on the wire — and open it again afterwards. While it is closed a
`cancel` or a `close` is refused rather than remembered, and `close` waits
for the body; the rules are not covered by it either. Put it back in a
`finally` if the step can throw: it is the one context member that never
throws itself.

`emit` is trusted, reads are checked. The emitted state is not verified
against the rules of the job that emitted it — otherwise a `close` job
declared as `run<NotClosed, void>` would cancel itself the moment it
emitted `Closed()`. The next read is checked as usual, though, so a job
that emits itself out of `W` must not touch `ctx` again: emit that state
as the last statement of the body, or the job ends with
`Cancelled(rules, 'is not W')` on its next read.

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
`stateAs`, `check`, `guard`) after a job that finished normally are
allowed; after a cancelled one they still throw its `Cancelled`. `log`
never throws.

`close()` awaited from inside the current job's body never completes: it
waits for that very body. The same holds for `cancelAll()`. Cancel from the
inside by returning or by throwing `Cancelled('why')`.

From inside a job body the whole surface of the `Solo` subclass is visible,
so there is no `ctx.solo`.

## Errors

A job that throws does not break the controller and does not stop the
queue: the error becomes the job's outcome and the next job runs.
`Outcome<T>` is sealed, so one `switch` covers everything that can happen
to a job:

```dart
switch (await profile.load().done) {
  case Done(:final value):
    print('loaded $value');
  case Failed(:final error):
    print('not loaded: $error');
  case Cancelled(:final reason):
    print('gave up: $reason');
}
```

`job.done` never throws. `job.value` gives the value instead, and rethrows
the body's error with its original stack trace, or throws the job's
`Cancelled`. `Cancelled` is not a failure: a job dropped as a duplicate,
cut short by `close`, or one whose state stopped matching its rules ends
that way, and that is normal traffic, not something to report.

Every failure also reaches the hooks, before the outcome is delivered to
whoever waits for it: `onError` on the controller itself, and
`SoloObserver.onError` for the whole process. Install an observer at
startup and every failure of every controller is reported once, in one
place.

A job nobody looks at is not silent. When a job ends with `Failed` and
nothing observed it — no `job.done`, no `job.value`, no `job.ignore()` —
the engine hands the error to the zone the job was created in, through
`Zone.handleUncaughtError`, exactly as Dart does with an unhandled
`Future` error. A fire-and-forget `profile.load();` on its own line still
reports what went wrong.

When the failure is genuinely handled elsewhere — by `onError`, by the
observer — say so:

```dart
profile.load().ignore(); // the counterpart of Future.ignore
```

`ignore()` marks the job as observed without waiting for it.

`Cancelled` never goes to the zone, and neither does an error that arrives
after the job was cancelled: an action that `guard` stopped waiting for
and that fails later is reported to `onError` and stops there.

## Testing

There is no `bloc_test` here and no need for one: the job handle is the
synchronization point. Start a job, await its outcome, then look at the
state.

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;

  expect(outcome, isA<Done<String>>());
  expect(profile.state.name, 'Ada Lovelace');

  await profile.close();
});
```

Use `job.value` instead of `job.done` when the test is about the returned
value, and `await expectLater(profile.load().value, throwsA(...))` when it
is about a failure.

When timing matters — a debounce, a timeout, two jobs racing — wrap the
test in `fakeAsync` and move time by hand. An observer that collects one
ordered journal turns a whole episode into a single `expect`, and that
catches ordering mistakes no final-state check can see:

```dart
final class Journal extends SoloObserver {
  final lines = <String>[];

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      lines.add('state: $current');
}

test('a second load while the first one runs is dropped', () {
  fakeAsync((async) {
    final journal = Journal();
    SoloBase.observer = journal;
    final profile = ProfileController(FakeProfileApi());

    final first = profile.load();
    final second = profile.load();
    expect(identical(first, second), isTrue);

    async.elapse(const Duration(milliseconds: 20));
    expect(journal.lines, [
      'load Cancelled(manual: duplicate)',
      'load started',
      'state: Profile("", loading: true)',
      'state: Profile("Ada Lovelace", loading: false)',
      'load Done(Ada Lovelace)',
    ]);

    profile.close();
    async.flushTimers();
    SoloBase.observer = null;
  });
});
```

`SoloBase.observer` is a global: set it at the start of the test and clear
it at the end. `stream` works with `expectLater(..., emitsInOrder([...]))`
too, but it is asynchronous — after `await job.done` the state is already
the final one, so reading `state` is usually enough.

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
still running for the previous input is cancelled rather than awaited.
Nothing awaits this job, so a failure of `api.search` goes to the zone; see
[Errors](#errors) for the ways out:

```dart
import 'dart:async';

final class Search extends Solo<SearchState> {
  final SearchApi api;

  Timer? _debounce;

  Search(this.api) : super(const SearchState.idle());

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
final class ProfileController extends Solo<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Profile());

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

Hooks are a channel, not a link in the chain: an error thrown by any of
them — a controller's or an observer's — goes to the current zone, the way
Dart reports an unhandled `Future` error, and changes nothing else. The job
ends with the outcome it had, the queue goes on, `close` still completes,
and the hook standing next to the throwing one is still called.

To trace the engine itself rather than the jobs, set
`SoloBase.debug = print`.

## Flutter

`flutter_solo` adds `SoloListenable<S> extends Solo<S> implements
ValueListenable<S>`, and re-exports all of `solo`. The only change to the
controller is its base class — the jobs stay exactly as they are:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

final class ProfileController extends SoloListenable<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Profile());

  // ...the jobs above...
}
```

There is no `SoloProvider`, and nothing closes the controller for you. A
controller that belongs to one screen is created in `initState` and closed
in `dispose`; a controller shared by several screens goes into whatever
you already use for that — `provider`, `get_it`, an `InheritedWidget` —
and is closed there.

A side effect is not a state: awaiting the job is the whole mechanism.
Check `mounted` after the await, as after any `await` in a `State`, and
then decide what to do with the outcome:

```dart
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController profile;

  @override
  void initState() {
    super.initState();
    profile = ProfileController(ProfileApi());
  }

  @override
  void dispose() {
    unawaited(profile.close());
    super.dispose();
  }

  Future<void> _open() async {
    final outcome = await profile.load().done;
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case Done():
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
        );
      case Failed(:final error):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      case Cancelled():
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ValueListenableBuilder<Profile>(
            valueListenable: profile,
            builder: (context, state, _) => state.loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _open,
                    child: const Text('Open profile'),
                  ),
          ),
        ),
      );
}
```

`ListenableBuilder` and `AnimatedBuilder` take the controller too — it is a
`Listenable` — when the builder does not need the value itself. `value` and
`state` are the same object. There is no setter on purpose: a
`ValueNotifier` face would be a hole in the ownership guarantee.

## Coming from bloc

| bloc | solo |
| --- | --- |
| `Bloc<E, S>`, `Cubit<S>` | `Solo<S>`, `SoloListenable<S>` |
| an event class, `on<E>`, `add(E())` | a method returning `Job<T>` |
| an `EventTransformer` | a `Policy` on the job |
| `emit(next)` | `ctx.emit(next)` |
| `if (emit.isDone) return;` | `ctx.check()` or `ctx.guard(...)` |
| `state`, `stream` | `state`, `stream` |
| `BlocObserver` | `SoloObserver` |
| `BlocBuilder`, `BlocSelector` | `ValueListenableBuilder` |
| `BlocListener` | `await job.done` at the call site |
| `BlocProvider` | `initState` plus `dispose` |
| `close()` | `close()` |
| `blocTest` | `test` plus `await job.done` |

The transformers map by name: `sequential()` is `Policy.sequential`,
`droppable()` is `Policy.droppable`, `restartable()` is `Policy.restart`.
`Policy.replace` — drop what is queued, leave what is running — has no
transformer of its own, and a policy is chosen per call rather than per
event type.

Three things have no counterpart on purpose. There is no `concurrent`
transformer: jobs of one controller never overlap, and work that really is
parallel goes inside one job, which awaits it itself. There is nothing
like an `emit` after `close` to guard against: `add` on a closed
controller returns a job that is already `Cancelled(closed)`, so call
sites need no `isClosed` check. And an event is not a value you can hold
on to — a method call gives you the `Job<T>` instead, so the caller can
await exactly the work it started.

## Example

The camera below is the shape of a real controller: several jobs with
different policies, a job that must not be cancelled, and a teardown that
clears the queue before it runs. The state is a sealed hierarchy, and
`NotDisposed` is a union interface that jobs can declare as their working
type:

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

Four things in that controller are worth a sentence each.

**The working type is wider than the start condition.** `init` starts only
from `Initial`, but it is declared `run<NotDisposed, void>`, because its
first line emits `Preparing` and the body keeps reading the context
afterwards. The start condition lives in `canStart`; `W` covers every state
the body walks through.

**`takePhoto` clears the queue.** The commands that piled up while the
shutter was open were aimed at the frame that has just been taken. Once
the capture succeeds they are stale, so the shot throws them away instead
of applying them to the next frame. `queue.clear()` without
`force` leaves `cancellable: false` jobs alone and never touches the
running job — the shot itself.

**`dispose()` is a job; `close()` is the end of the controller.**
`dispose()` puts the hardware back and can be queued, dropped as a
duplicate, and awaited like any other job. `close()` drops the queue,
cancels the running job and refuses everything after it. One does not
imply the other: `close()` alone leaves the camera open. Await the teardown
first, then close.

**A queued `setZoom` is replaced, a running one is not.** `Policy.replace`
removes queued jobs with the same key; the job already running is left to
finish. `Policy.restart` would cancel it as well, and `Policy.droppable` —
what `takePhoto` uses — keeps the running job and drops the newcomer.

[`example/`](example) is a runnable package with this controller extended:
a fake camera whose hardware answers late and may break on its own, a
`Broken` state, `reopen`, `pause`, `resume` and focus jobs, four tests over
an ordered journal, and `bin/main.dart` that prints the same journal in
real time.

```sh
cd example
dart pub get
dart run bin/main.dart
dart test
```
