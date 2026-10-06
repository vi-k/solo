# flutter_solo

State management for Flutter: sequential jobs over one state, exclusive
ownership, cooperative cancellation, and rebuilds through `ValueListenable`.

A controller owns a state and runs jobs over it one at a time. Mix
`SoloListenable` into it, and it is a `ValueListenable` of its state at the
same time — so it drops straight into `ValueListenableBuilder`,
`ListenableBuilder`, `AnimatedBuilder` and `Listenable.merge`.

The [documentation site](https://docs.yet-another.dev/flutter_solo/) carries
this page and the guides of the packages below it.

## Why

A screen has a lifecycle, and so does the work on it: a load that must be
dropped when the user leaves, a save that must not be cut in half, a second tap
that must not start a second request. `setState` and `ChangeNotifier` give you
somewhere to keep the state and say nothing about the work. `Bloc` schedules
the work and asks for an event class per call; `Cubit` keeps plain methods and
schedules nothing.

Here a method stays a method, and it hands back a handle:

```dart
final job = controller.load();

await job.cancel(); // returns when the job has actually stopped
print(job.outcome); // Cancelled(manual)
```

What the engine holds to:

- one root job of a controller at a time, in queue order, so two of them never
  write the same state;
- rules instead of flags — a job declares the states it works with and the
  condition it lives under, and it is cancelled when they stop holding;
- a cancellation the caller can ask for and the body cannot walk past by
  forgetting a check;
- an outcome for every job — `Done`, `Failed` or `Cancelled` — which is what a
  screen has to show anyway.

The long argument, eleven scenarios solved in bloc first and then here, is in
[solo and bloc, side by side](https://github.com/vi-k/solo/blob/main/packages/solo/doc/vs-bloc.md).

What is not here: no `SoloProvider` and no code generation, no dependency
injection, no persistence, and no parallel root jobs — one at a time is the
subject of the package, not a limit of its engine.

## Install

```sh
flutter pub add flutter_solo
```

One dependency is all it takes: `flutter_solo` re-exports the whole of
[solo](https://pub.dev/packages/solo), which re-exports the whole of
[async_job](https://pub.dev/packages/async_job). `Solo`, `SoloContext`, `Job`,
`Outcome` and `Policy` all arrive with

```dart
import 'package:flutter_solo/flutter_solo.dart';
```

`SoloListenable` is the mixin this package is about; `SoloBuilder`,
`SoloSelector` and `SoloSelection` come with it, and a second import next door
adds `select` and `listen` as methods, with the subscriptions `listen` hands
back.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

sealed class Profile {
  // What a Save button asks; only a loaded profile has anything to save.
  bool get canSave => this is Loaded;
}

final class Empty extends Profile {}

final class Loading extends Profile {}

final class Loaded extends Profile {
  final String name;

  Loaded(this.name);
}

final class ProfileController extends Solo<Profile> with SoloListenable {
  final ProfileApi api;

  ProfileController(this.api) : super(Empty());

  Job<String> load() => run<Profile, String>(
        key: 'load',
        policy: Policy.droppable, // a second tap returns the first job
        (ctx) async {
          ctx.emit(Loading());
          final name = await ctx.abandonable(api.fetchName);
          ctx.emit(Loaded(name));

          return name;
        },
        // Without these a load that fails or is cancelled leaves the state
        // on Loading: a spinner, and nothing on the screen to tap.
        onError: (state, error, stackTrace) => Empty(),
        onCancel: (state, cancelled) => Empty(),
      );

  Job<void> save() => run<Loaded, void>(
        key: 'save',
        (ctx) => ctx.join(() => api.saveName(ctx.state.name)),
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

`run<Profile, String>` says the job works with `Profile` states and returns a
`String`; `save` narrows that to `Loaded`, so it does not start in any other
state — it ends `Cancelled` there — and its body reads a `Loaded` with a `name`
in it. Inside a body `ctx.emit` is the only way to write the state,
`ctx.abandonable` awaits like `await` except that it gives up the moment the
job is cancelled, and `ctx.join` waits its call out either way — a save is not
cut in half. `onError` and `onCancel` are the way back: they say what state a
load that failed or was cancelled leaves behind, and without them the screen
would keep the spinner of a job that is no longer running. The full API —
rules, the queue, children, observers — is documented in
[solo](https://pub.dev/packages/solo).

## Selecting one value

A widget that needs one field does not have to rebuild for the rest.
`SoloSelector` picks the field and rebuilds only when that field changes:

```dart
SoloSelector<Profile, bool>(
  solo: controller,
  selector: (state) => state.canSave,
  builder: (context, canSave, _) => ElevatedButton(
    onPressed: canSave ? controller.save : null,
    child: const Text('Save'),
  ),
)
```

Picks count as changed when they are `!=`, unless `changed:` answers that
question itself. The selector runs once for every change of the state, so keep
it a cheap pick that gives the same answer for the same state. `solo` is any
controller, a `ValueListenable` or not. The selector is compared by identity
when the parent rebuilds, so an inline closure is a new one on every such build
and makes a new selection each time: one `removeListener`, one `addListener`
and one pick, and with a `changed:` of your own the value it compares against
starts over. Hold the function in a field or a `static` where the parent
rebuilds often.

What the widget holds for you is a `SoloSelection` — a `ValueListenable` of the
picked value — and it is an object like any other where a listenable is what
you need:

```dart
class _SaveButtonState extends State<SaveButton> {
  late SoloSelection<Profile, bool> canSave = _select();

  SoloSelection<Profile, bool> _select() =>
      SoloSelection(widget.controller, (state) => state.canSave);

  @override
  void didUpdateWidget(SaveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      canSave = _select();
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: canSave,
        builder: (context, enabled, _) => ElevatedButton(
          onPressed: enabled ? widget.controller.save : null,
          child: const Text('Save'),
        ),
      );
}
```

Hold the selection in a field, the way `canSave` is held above. One built
inside `build` is a new object on every build: the builder under it
unsubscribes from the old one and subscribes to the new, and the value a
selection holds notifications back with starts over each time. A field is built
from the first widget only, though, and a parent can hand the `State` another
controller: without `didUpdateWidget` the button would go on taking its
permission from the old controller while its tap went to the new one. Both come
with the field that `SoloSelector` spares you. The source is subscribed to only
while the selection has listeners, and there is nothing to dispose of.

## Builders for any controller

`ValueListenableBuilder` needs a `ValueListenable`, and a controller with
`SoloListenable` mixed in is one. A controller without it is not — a plain
`Solo`, or one `with SoloStream` only — and for those `SoloBuilder` takes the
controller itself:

```dart
SoloBuilder<Profile>(
  solo: controller,
  builder: (context, state, _) => Text(
    switch (state) {
      Empty() => 'no profile',
      Loading() => 'loading',
      Loaded(:final name) => name,
    },
  ),
)
```

It rebuilds on every change of the state and hands `child` through untouched.
Besides the controller it takes, one thing sets it apart from
`ValueListenableBuilder`: it compares controllers by identity. Handed a new
controller whose `==` says it is the old one, `SoloBuilder` moves to it and
`ValueListenableBuilder` goes on listening to the old one.

Picking one value out of such a controller needs nothing new. `SoloSelector`
takes any controller, and `SoloSelection.from(controller, selector)` is its
selection without a widget around it, for a `State` field of a controller that
is not a `ValueListenable`.

A controller with both a `stream` and `SoloListenable`, a screen built on that
stream, and a base class of controllers with no Flutter in it are on a page of
their own, [Mixins](doc/mixins.md).

## Listening without keeping the callback

A `State` wants to be told of every change and handed the new state, so it
listens with a closure that reads it.

### The first attempt

```dart
@override
void initState() {
  super.initState();
  widget.controller.addListener(() => _onState(widget.controller.value));
}

@override
void dispose() {
  widget.controller.removeListener(() => _onState(widget.controller.value));
  super.dispose();
}
```

The closure in `dispose()` is spelled like the one in `initState()` and is
another object. `removeListener` has to be given the very callback
`addListener` took; given anything else it removes nothing and says nothing.
The first closure stays registered and goes on being called, over a `State`
that is gone, until the controller is closed. To be given back, the closure
would need a field of its own to live in.

### A subscription that keeps the callback

`listen` keeps the callback instead and hands back a `SoloSubscription`;
`SoloSubscriptions` cancels a group of them at once:

```dart
import 'package:flutter_solo/listenable.dart';

final _listening = SoloSubscriptions();

@override
void initState() {
  super.initState();
  widget.controller
      .listen(() => _onState(widget.controller.value))
      .addTo(_listening);
  canSave.listen(() => _onCanSave(canSave.value)).addTo(_listening);
}

@override
void dispose() {
  _listening.cancel();
  super.dispose();
}
```

`listen` works on any `Listenable` — a controller with `SoloListenable`, a
selection, a `ScrollController` of the framework's own. Cancelling twice does
nothing the second time, and a group that has been cancelled cancels what it is
handed rather than keeping it. If one member refuses to let go, the others are
cancelled all the same and every failure goes to `FlutterError.reportError`.
Cancelling a group never throws: its place is `dispose()`, and an exception out
of there costs the elements behind it in that frame their own `dispose()`,
listeners and all.

What `initState` subscribes to stays subscribed when the widget is handed
another controller. A `State` whose source can be replaced cancels the group in
`didUpdateWidget` and takes its subscriptions again, into a new group: the
cancelled one would cancel them on the spot.

## Methods from a second import

`select` and `listen` arrive with an import of their own, next to the one the
rest of the package comes from:

```dart
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';

final canSave = controller.select((state) => state.canSave);
final subscription = canSave.listen(() => _onCanSave(canSave.value));
```

They are extensions, and they sit on the framework's own `ValueListenable` and
`Listenable` — where another package's `select` and `listen` sit too. Two
extensions with the same member name on one type are ambiguous at every call
site, so a package carrying them into every file that imports it would break a
neighbour it never heard of. The import is the choice.

Without it the methods are gone and what they do is not:
`SoloSelection(controller, (state) => state.canSave)` is the same selection,
`SoloSelector` needs no method at all, and `addListener` with a callback you
keep yourself is what `listen` does for you. `SoloSubscription` and
`SoloSubscriptions` come with the second import only. Being extensions is also
why a controller of your own with a `select` method keeps it: an extension
always steps aside for a member.

## The controller's life

Nothing closes a controller for you. There is no `SoloProvider`: a controller
is an object, and it lives wherever the rest of your objects live.

```dart
import 'dart:async';

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

`close()` cancels whatever is queued or running — a running body stops at its
next context call, which is what makes leaving the screen cheap — drops every
listener and stops notifying for good. It is safe on either side of
`super.dispose()`. `SoloListenable` is not a `ChangeNotifier`: the method is
`close()`, not `dispose()`, and it returns a `Future` that completes when the
job has actually stopped.

A controller shared by several screens lives where your other singletons live —
a `get_it` registration, an `InheritedWidget`, a field of the app object — and
is closed there, once.

## Outcomes

A method hands back its job, so the screen can wait for the end of the work it
started:

```dart
Future<void> _load() async {
  switch (await controller.load().done) {
    case Done(:final value):
      if (mounted) _toast('hello $value');
    case Failed(:final error):
      if (mounted) _toast('$error');
    case Cancelled():
      break; // left the screen, and close() cancelled the job
  }
}
```

`done` never throws; `value` gives the value, rethrows the failure of a job
that failed and throws the `Cancelled` of one that was cancelled. `mounted`
after an `await` is the usual Flutter rule and it applies here too. A job
nobody looks at is not silent: an unobserved `Failed` reaches the zone that
created the job, so a fire-and-forget call is `controller.load().ignore()` —
the `ignore()` is what says the outcome is nobody's business. The same road
carries the errors no outcome holds — the failure of work a body handed to
`ctx.unattended`, say — unless the controller overrides `onUnanswered` or a
`Solo.errorHandler` is set to answer for them:
[Answering for an error](https://github.com/vi-k/solo/blob/main/packages/solo/doc/errors.md#answering-for-an-error)
on the errors page of `solo` has the list. A `SoloObserver` sees such a failure
and does not take it: watching is not answering.

What "to the zone" means in a Flutter app: the error travels the zones
outwards, so an error zone of your own around `runApp` sees it first. Past that
it reaches `PlatformDispatcher.instance.onError` if you set one. With none set,
or when the callback returns `false`, the embedder gets the error, and its
fallback is to print it. What comes after is the embedder's business: the
documentation of `onError` promises nothing about the process, which may exit
or stop responding after the callback. A plain Dart program differs in one
thing: an unhandled error ends it, with exit code 255, and that is the
standalone VM's own reaction, not Flutter's.

## Testing

A widget test starts a load and looks at the screen once the load is over.
`FakeApi` below is the test's own: it answers with the name ten milliseconds
after the call. A plain test would await the job.

### The first attempt

```dart
await controller.load().done;
await tester.pump();
```

The test never gets past the first line: it stands there until its timeout, ten
minutes by default. `testWidgets` runs on a fake clock, and nothing inside it
moves that clock but the test. The ten milliseconds of the fake are a timer, so
the job waits for the test to move time, and the test waits for the job.

### Moving the clock

```dart
testWidgets('the profile appears', (tester) async {
  final controller = ProfileController(FakeApi());
  await tester.pumpWidget(
    MaterialApp(home: ProfileView(controller: controller)),
  );

  await tester.tap(find.text('Load'));
  await tester.pumpAndSettle();

  expect(find.text('Ada Lovelace'), findsOneWidget);
  await controller.close();
});
```

`pumpAndSettle` pumps a frame every hundred milliseconds for as long as another
frame is asked for. The first hundred are more than this fake needs, and a
slower one would be waited for as well, because the spinner of `Loading` keeps
asking for frames. It is the screen that is waited for, not the job: with
nothing animating, `pumpAndSettle` stops after a frame or two, and a load that
takes longer than that is still waiting.

The handle waits for the job itself:

```dart
final done = controller.load().done; // before the job can end
await tester.pump(const Duration(milliseconds: 20)); // let the clock run
final outcome = await done;
```

`pump` with a duration moves the clock and then draws, so the frame it leaves
shows the last state. `done` is read on the first line, before the clock moves,
and the order matters: a `Failed` nobody has asked about is reported as the job
ends, to the zone it was created in. Here that is the zone of the test, which
fails the test on the spot, and `tester.takeException()` has nothing to take
afterwards. A load that fails makes a test red even though it reads `done`, if
it reads it after the pump. A job the test starts and drops says so with
`ignore()`.

Two more things belong to the fake clock. A `pump()` with no duration decides
whether to draw before it runs the microtask a job starts on: after
`controller.load()` and one `pump()` the state has moved and the screen has
not, unless a frame was already asked for, as one is right after a
`MaterialApp` has been pumped. A second `pump()` draws it. And the controller
is closed in the body of the test, not in `addTearDown`: a tear-down runs after
the fake clock has stopped, and a `close()` awaited there with a job still
running — an expectation that failed halfway through a load is enough — never
comes back. The test stands until its timeout, and the test after it fails with
it.

A job given a `timeout` brings a timer of its own, which the core holds until
the job ends. Left running when the body of a `testWidgets` ends, such a job
fails the test with
`A Timer is still pending even after the widget tree was disposed`, where the
same job without a deadline lets the test pass. Closing the controller in the
body, as above, ends the job and takes its timer along.

## Notes

| Question | Answer |
| --- | --- |
| When do listeners run? | Synchronously, in subscription order, on every state change. `value` and `currentState` are the same object. There is no `stream` unless `SoloStream` is mixed in as well: a widget rebuilds from `value`. |
| Are equal states filtered? | No. `emit` of a state equal to the current one still notifies: the listeners are the engine's own, and the engine compares nothing. A frame may swallow several of them, a listener will not. A selection filters its own value, which is the one a widget usually cares about. |
| Several controllers on one screen? | Each with its own builder, as expected. `Listenable.merge([a, b])` in a `ListenableBuilder` covers the case where one widget depends on two. |
| Can I set `value`? | There is no setter. The state belongs to the jobs; a `ValueNotifier` face with a setter would give it away. |

## solo

[solo](https://pub.dev/packages/solo) is the controller itself: the queue and
its policies, the working type of a job, `canStart` and `keepWhile`, children,
observers, the waiting family and the rest of the API, which this package
re-exports whole — `SoloStream` included, whose broadcast `stream` is for what
is not a widget. If you are not writing widgets, take it instead — it is pure
Dart.
