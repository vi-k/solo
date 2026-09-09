# flutter_solo

State management for Flutter: sequential jobs over one state, exclusive
ownership, cooperative cancellation, and rebuilds through
`ValueListenable`.

`SoloListenable<S>` is a controller that owns a state and runs jobs over
it one at a time, and it is a `ValueListenable<S>` at the same time — so
it drops straight into `ValueListenableBuilder`, `ListenableBuilder`,
`AnimatedBuilder` and `Listenable.merge`.

## Why

A screen has a lifecycle, and so does the work on it: a load that must be
dropped when the user leaves, a save that must not be cut in half, a
second tap that must not start a second request. `setState` and
`ChangeNotifier` give you somewhere to keep the state and say nothing
about the work; bloc gives you the work and asks for an event class per
call.

Here a method stays a method, and it hands back a handle:

```dart
final job = profile.load();

await job.cancel();  // returns when the job has actually stopped
print(job.outcome);  // Cancelled(manual)
```

What the engine holds to:

- one root job of a controller at a time, in queue order, so two of them
  never write the same state;
- rules instead of flags — a job declares the states it works with and the
  condition it lives under, and it is cancelled when they stop holding;
- a cancellation the caller can ask for and the body cannot walk past by
  forgetting a check;
- an outcome for every job — `Done`, `Failed` or `Cancelled` — which is
  what a screen has to show anyway.

The long argument, ten scenarios solved in bloc first and then here, is
in [solo and bloc, side by side](https://github.com/vi-k/solo/blob/main/packages/solo/doc/vs-bloc.md).

What is not here: no `SoloProvider` and no code generation, no dependency
injection, no persistence, and no parallel root jobs — one at a time is
the subject of the package, not a limit of its engine.

## Install

```sh
flutter pub add flutter_solo
```

One dependency is all it takes: `flutter_solo` re-exports the whole of
[solo](https://pub.dev/packages/solo), which re-exports the whole of
[async_job](https://pub.dev/packages/async_job). `Solo`, `SoloContext`, `Job`,
`Outcome`, `Policy` and `ValueListenable` all arrive with

```dart
import 'package:flutter_solo/flutter_solo.dart';
```

and `SoloListenable` is the single class this package adds on top.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

sealed class Profile {}

final class Empty extends Profile {}

final class Loading extends Profile {}

final class Loaded extends Profile {
  final String name;

  Loaded(this.name);
}

final class ProfileController extends SoloListenable<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(Empty());

  Job<String> load() => run<Profile, String>(
        key: 'load',
        policy: Policy.droppable, // a second tap returns the first job
        (ctx) async {
          ctx.emit(Loading());
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));

          return name;
        },
      );
}

class ProfileView extends StatelessWidget {
  final ProfileController controller;

  const ProfileView({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Profile>(
        valueListenable: controller,
        builder: (context, state, _) => switch (state) {
          Empty() => TextButton(
              onPressed: controller.load,
              child: const Text('Load'),
            ),
          Loading() => const CircularProgressIndicator(),
          Loaded(:final name) => Text(name),
        },
      );
}
```

`run<Profile, String>` says the job works with `Profile` states and
returns a `String`; inside the body `ctx.emit` is the only way to write
the state, and `ctx.wait` awaits like `await` except that it gives up the
moment the job is cancelled. The full API — rules, the queue, children,
observers — is documented in [solo](https://pub.dev/packages/solo).

## The controller's life

Nothing closes a controller for you. There is no `SoloProvider`: a
controller is an object, and it lives wherever the rest of your objects
live.

```dart
class _ProfileScreenState extends State<ProfileScreen> {
  final controller = ProfileController(ProfileApi());

  @override
  void initState() {
    super.initState();
    controller.load().ignore();
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProfileView(controller: controller);
}
```

`close()` cancels whatever is running — the body stops at its next context
call, which is what makes leaving the screen cheap — drops every listener
and stops notifying for good. It is safe on either side of
`super.dispose()`. `SoloListenable` is not a `ChangeNotifier`: the method
is `close()`, not `dispose()`, and it returns a `Future` that completes
when the job has actually stopped.

A controller shared by several screens lives where your other singletons
live — a `get_it` registration, an `InheritedWidget`, a field of the app
object — and is closed there, once.

## Outcomes

A job hands back a handle, so the screen can wait for the end of the work
it started:

```dart
Future<void> _load() async {
  switch (await controller.load().done) {
    case Done(:final value):
      if (mounted) _toast('hello $value');
    case Failed(:final error):
      if (mounted) _toast('$error');
    case Cancelled():
      break; // left the screen, or a second tap while the first ran
  }
}
```

`done` never throws; `value` gives the value and rethrows the failure.
`mounted` after an `await` is the usual Flutter rule and it applies here
too. A job nobody looks at is not silent: an unobserved `Failed` reaches
the zone that created the job, so a fire-and-forget call is
`controller.load().ignore()` — the `ignore()` is what says the outcome is
nobody's business. The same road carries a failure of work handed to
`ctx.unattended` when neither `onError` nor a `SoloObserver` took it.

What "to the zone" means in a Flutter app: the error travels the zones
outwards, so an error zone of your own around `runApp` sees it first; past
that it reaches `PlatformDispatcher.instance.onError` if you set one, and
the engine's log if you did not. What happens next is that callback's
business and the embedder's — the framework does not promise to carry on,
and `PlatformDispatcher.onError` may end the process. What is *not* the
answer here is the `EXIT=255` of a plain Dart program: that one is the
VM's own reaction to an unhandled error, and it is not Flutter's.

## Testing

`testWidgets` runs on a fake clock: a job waiting on a timer stays there
until the test moves time itself, and the frame is always one behind the
state. `pumpAndSettle` does both — it runs the clock out and rebuilds:

```dart
testWidgets('the profile appears', (tester) async {
  final controller = ProfileController(FakeApi());
  addTearDown(controller.close);
  await tester.pumpWidget(
    MaterialApp(home: ProfileView(controller: controller)),
  );

  await tester.tap(find.text('Load'));
  await tester.pumpAndSettle();

  expect(find.text('Ada Lovelace'), findsOneWidget);
});
```

The handle is the precise version of the same thing, for a test that has
to know the job ended rather than that the screen went quiet:

```dart
final job = controller.load();
await tester.pump(const Duration(milliseconds: 20)); // let the clock run
await job.done;
await tester.pump(); // the frame that shows the last state
```

`await job.done` on its own is a deadlock if the work waits on a timer:
nothing inside `testWidgets` advances the clock but the test. What also
does not work is starting a job and pumping once — the state moves on a
microtask after that pump, and whether the expectation sees it depends on
how much was queued.

One Flutter-specific trap: an unobserved `Failed` fails the test itself,
and `tester.takeException()` does not catch it — the error goes to the
zone of the test, not through `FlutterError.onError`. Either await the
outcome or call `ignore()`.

## Notes

- Listeners are called synchronously, in subscription order, on every
  state change. `Solo`'s `stream` still works and arrives a microtask
  later; `value` and `state` are the same object.
- Equal states are not filtered: `emit` of a state equal to the current
  one still notifies, the way `Solo` does. A frame may swallow several of
  them, a listener will not.
- Several controllers on one screen work as expected, each with its own
  builder, and `Listenable.merge([a, b])` in a `ListenableBuilder` covers
  the case where one widget depends on two.
- There is no setter for `value`. The state belongs to the jobs; a
  `ValueNotifier` face with a setter would give it away.

## solo

[solo](https://pub.dev/packages/solo) is the controller itself: the
queue and its policies, the working type of a job, `canStart` and
`keepWhile`, children, observers, the waiting family and the rest of the
API this package inherits whole. If you are not writing widgets, take it
instead — it is pure Dart.
