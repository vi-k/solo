# flutter_solo

State management for Flutter: sequential jobs over one state, exclusive
ownership, cooperative cancellation, and rebuilds through `SoloBuilder` or
`ValueListenable`.

A controller owns a state and runs jobs over it one at a time. `SoloBuilder`
rebuilds a widget on every change of that state. Mix `SoloListenable` into the
controller, and it is a `ValueListenable` of its state as well, so it drops
straight into `ValueListenableBuilder`, `ListenableBuilder`, `AnimatedBuilder`
and `Listenable.merge`.

The [documentation site](https://docs.yet-another.dev/flutter_solo/) carries
this page and the guides of the packages below it.

## Why

A screen has a lifecycle, and so does the work on it. A load must be dropped
when the user leaves, a save must not be cut in half, and a second tap must not
start a second request. `setState` and `ChangeNotifier` give you somewhere to
keep the state and say nothing about the work. `Bloc` schedules the work and
asks for an event class per call; `Cubit` keeps plain methods and schedules
nothing.

Here a method stays a method, and it hands back a handle:

```dart
final job = controller.load();

await job.cancel(); // returns when the job has actually stopped
print(job.outcome); // Cancelled(manual)
```

What the engine holds to:

- One root job of a controller at a time, so two of them never write the same
  state.
- Rules instead of flags: a job declares the states it works with and the
  condition it lives under, and it is cancelled when they stop holding.
- A cancellation the caller can ask for: the next checkpoint of the context
  throws it, and a body that never reaches one still ends `Cancelled` and
  writes no state of its own.
- An outcome for every job, one of `Done`, `Failed` and `Cancelled`, which is
  what a screen has to show anyway.

The long argument, eleven scenarios solved in bloc first and then here, is in
[solo and bloc, side by side](https://github.com/vi-k/solo/blob/main/packages/solo/doc/vs-bloc.md).

What is not here: no `SoloProvider` and no code generation, no dependency
injection, no persistence, and no parallel root jobs. Dependencies are left out
deliberately: they are passed by other means and packages, such as
[scopo](https://pub.dev/packages/scopo). Nor would a provider close a
controller any better than a `State` does, as
[The controller's life](#the-controllers-life) shows. One job at a time is
deliberate too, hence the `solo` in the name: it is the subject of the package,
not a limit of its engine.

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

The package's own part arrives with the same import: the mixin
`SoloListenable`, the widgets `SoloBuilder`, `SoloSelector` and `SoloListener`
with its `SoloListenerMode`, and the class `SoloSelection`. A second import
next door adds `select` and `listen` as methods, with the subscriptions
`listen` hands back:

```dart
import 'package:flutter_solo/listenable.dart';
```

[Methods from a second import](#methods-from-a-second-import) says why it is a
second one.

The analyzer plugin [solo_lints](https://pub.dev/packages/solo_lints) reports
most of the
[common mistakes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/mistakes.md)
of `solo` in the code. Name it in `analysis_options.yaml`:

```yaml
plugins:
  solo_lints: ^0.2.0
```

That turns on its warnings; the lints are turned on by name, as its
[Install](https://github.com/vi-k/solo/blob/main/packages/solo_lints/README.md#install)
section shows. From Flutter 3.44 on, `flutter analyze` shows none of its
diagnostics: run `dart analyze` or read them in the editor.

## Usage

`ProfileApi` stands for the app's own service: `fetchName()` returns a
`Future<String>`, and `saveName(name)` a `Future<void>`. A call of
`fetchName()` that fails throws an `ApiException`.

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

final class ProfileController extends Solo<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(Empty());

  Job<String> load() => enqueue<Profile, String>(
    key: 'load',
    policy: Policy.droppable, // a second tap returns the first job
    (ctx) async {
      ctx.emit(Loading());
      final name = await ctx.abandonable(api.fetchName);
      ctx.emit(Loaded(name));

      return name;
    },
    isExpectedError: (error) => error is ApiException,
    // Without these a load that fails or is cancelled leaves the state
    // on Loading: a spinner, and nothing on the screen to tap.
    ifFailed: (state, error, stackTrace) => Empty(),
    ifCancelled: (state, cancelled) => Empty(),
  );

  Job<void> save() => enqueue<Loaded, void>(
    key: 'save',
    (ctx) => ctx.join(() => api.saveName(ctx.state.name)),
  );
}

class ProfileView extends StatelessWidget {
  final ProfileController controller;

  const ProfileView({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => SoloBuilder<Profile>(
    solo: controller,
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

`enqueue<Profile, String>` says the job works with `Profile` states and returns
a `String`. `save` narrows that to `Loaded`: it does not start in any other
state, it ends `Cancelled` there, and its body reads a `Loaded` with a `name`
in it. Inside a body:

- `ctx.emit` is the only way to write the state.
- `ctx.abandonable` awaits like `await`, except that it gives up the moment the
  job is cancelled.
- `ctx.join` waits its call out either way, so a save is not cut in half.

`ifFailed` and `ifCancelled` are the way back. They say what state a load that
failed or was cancelled leaves behind. Without them the screen would keep the
spinner of a job that is no longer running.

They answer on the screen and not for the caller. The button drops the job that
`load` hands back. A failure nobody reads goes on to the zone even after
`ifFailed` has put `Empty` on the screen, unless `load` names it in
`isExpectedError` or `Solo.unansweredHandler` answers for it. `load` names
`ApiException`, so a call that fails goes no further than `Empty`: the screen
is all the answer it needs. A bug is not an `ApiException`, and it goes on: in
an app towards `PlatformDispatcher.onError`, in a widget test into the test,
which fails. [Outcomes](#outcomes) has the rule. The full API, with rules, the
queue, children and observers, is documented in
[solo](https://pub.dev/packages/solo).

`SoloBuilder` is what draws the state: it takes the controller as `solo`,
rebuilds on every change of the state and hands `child` through untouched. The
table gives every way to follow a controller, and the sections below take the
others apart:

| What the screen needs | What to take |
| --- | --- |
| A widget drawn from the whole state | `SoloBuilder`, or `ValueListenableBuilder` with `SoloListenable` |
| A widget that rebuilds only when one value changes | `SoloSelector` |
| That value as a `ValueListenable` a `State` holds | `SoloSelection` |
| One widget over two controllers | `Listenable.merge` in a `ListenableBuilder`, with `SoloListenable` |
| A callback on every change, outside `build` | `listen` from the second import, with `SoloListenable` |
| A reaction to every change, cancelled with the screen | `SoloListener` |

## The controller as a `ValueListenable`

The framework has builders of its own, and they take a `ValueListenable`. Mix
`SoloListenable` into the controller, and it is one:

```dart
final class ProfileController extends Solo<Profile> with SoloListenable {
  // ...same as above...
}
```

The state is its `value`, and `ValueListenableBuilder` takes the controller as
it is:

```dart
ValueListenableBuilder<Profile>(
  valueListenable: controller,
  builder: (context, state, _) => Text(switch (state) {
    Empty() => 'no profile',
    Loading() => 'loading',
    Loaded(:final name) => name,
  }),
),
```

`ListenableBuilder` and `AnimatedBuilder` take it the same way, and
`Listenable.merge` joins it with other listenables. A widget over two profiles
rebuilds when either of them changes:

```dart
ListenableBuilder(
  listenable: Listenable.merge([left, right]),
  builder: (context, _) => Text(
    left.value.canSave && right.value.canSave ? 'both loaded' : 'waiting',
  ),
),
```

`SoloBuilder` goes on taking it, as it takes any controller: with the mixin,
without it, or `with SoloStream`. One thing sets it apart from
`ValueListenableBuilder`: it compares controllers by identity. Given a new
controller that equals the old one by `==` but not by `identical`,
`SoloBuilder` moves to it, and `ValueListenableBuilder` goes on listening to
the old one.

In a type position, write the type argument out, `SoloListenable<Profile>`: the
analyzer lets a bare `SoloListenable` through as a `SoloListenable<Object>`.

The sections below on selecting and listening take the controller with the
mixin.

A controller with both a `stream` and `SoloListenable`, a screen built on that
stream, and a base class of controllers with no Flutter in it are on a page of
their own, [Mixins](doc/mixins.md).

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
),
```

The button drops the job that `save` hands back, on purpose, and so does
`SaveButton` below. A save that fails leaves the state `Loaded`, and nothing on
the screen says so. `save` has no `ifFailed`, so its failure goes on to the
zone, with no `Solo.unansweredHandler` set, in an app towards
`PlatformDispatcher.onError`. `ignoreFailure()` would leave it unheard. A
screen that tells the user waits for `save().done`, as in
[Outcomes](#outcomes).

The rules of `SoloSelector`:

- Picks count as changed when they are `!=`, unless `changed:` answers that
  question itself.
- The selector runs once for every change of the state, so keep it a cheap pick
  that gives the same answer for the same state.
- `solo` is any controller, a `ValueListenable` or not.

`changed:` is handed two picks: the last one the widget accepted, as
`previous`, and the new one. The builder has usually been given `previous`, but
not always. When two changes come before a frame and the first is accepted, the
second is put against it, and the builder has not seen it yet. So where the
screen ends up depends on the changes alone, not on how they fall into frames.

The selector and `changed:` can be closures written in place, as the selector
is above. Such a closure is a new one on every build of the parent, and it may
pick something else. So the widget picks once more and puts the pick to
`changed:`. It moves no subscription for that. `changed:` still compares
against the last pick the widget accepted.

Where a listenable of the picked value is what you need, the same pick is made
by an object, a `SoloSelection`, and a `State` holds it in a field:

```dart
class _SaveButtonState extends State<SaveButton> {
  late SoloSelection<Profile, bool> canSave = _select();

  SoloSelection<Profile, bool> _select() =>
      SoloSelection(widget.controller, (state) => state.canSave);

  @override
  void didUpdateWidget(SaveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
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
inside `build` is a new object on every build. The builder under it then
unsubscribes from the old one and subscribes to the new, and each new selection
starts from a pick of its own, so the pick a change is compared against starts
over on every build.

The initializer of the field runs once, though, and reads `widget.controller`
as it is at that moment. The `State` outlives the widget: a parent that
rebuilds can hand it a new `SaveButton` with another controller. Without
`didUpdateWidget` the button would go on taking its permission from the old
controller while its tap went to the new one. The field and its
`didUpdateWidget` are what `SoloSelector` spares you: the widget that picks
needs no `State`.

The source is subscribed to only while the selection has listeners, and there
is nothing to dispose of. A selection outlives its source harmlessly: `value`
keeps reading the final state of a closed controller.

The constructor takes a `ValueListenable`: here, the controller with
`SoloListenable`. For a controller without the mixin,
`SoloSelection.from(controller, selector)` builds the same selection. A
`ValueListenable` that is not a controller is picked from the same way, with a
`SoloSelection` under a `ValueListenableBuilder`: `SoloSelector` takes only a
controller.

The selector of a selection runs inside the change that triggered it, so it
should only pick: over a controller with `SoloListenable` it must not change
the state, start a job or close the controller.

While somebody listens, the selection picks once per change, and a listener
reads the very pick that decided whether to notify. With nobody listening,
`value` picks every time and keeps nothing it picked. A source that changes its
value in place keeps the object, so a listener the source calls ahead of the
selection reads the pick from before the change. A `solo` controller with an
immutable state never meets this.

## Listening without keeping the callback

A `State` wants to be told of every change and handed the new state, so it
listens with a closure that reads it.

### The first attempt

```dart
// The first attempt: dispose() removes nothing; the listener stays.
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
that is gone, until the controller is closed.

### A method instead of the closure

```dart
void _onChange() => _onState(widget.controller.value);

@override
void initState() {
  super.initState();
  widget.controller.addListener(_onChange);
}

@override
void dispose() {
  widget.controller.removeListener(_onChange);
  super.dispose();
}
```

A method can be named in both places. `removeListener` compares with `==`: a
method named twice is equal to itself, and a closure written twice is not. The
cost is a method for every listener, and for every `addListener` a
`removeListener` that `dispose()` must not leave out.

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

`listen` works on any `Listenable`: a controller with `SoloListenable`, a
selection, a `ScrollController` of the framework's own. Cancelling goes by
three rules:

- Cancelling twice does nothing the second time.
- A group that has been cancelled cancels what it is handed rather than keeping
  it.
- If one member refuses to let go, the others are cancelled all the same, and
  every failure goes to `FlutterError.reportError`.

Cancelling a group never throws. Its place is `dispose()`, and an exception out
of there costs the elements behind it in that frame their own `dispose()`,
listeners and all.

What `initState` subscribes to stays subscribed when the widget is handed
another controller. A `State` whose source can be replaced cancels the group in
`didUpdateWidget` and takes its subscriptions again, into a new group: the
cancelled one would cancel them on the spot.

## Reacting to a change

A screen shows a snack bar when the connection is lost, whoever lost it.
`connection` is a controller of the app's own: its state is `Connection.online`
or `Connection.offline`, and the app writes it from wherever it learns of the
network.

### The first attempt

```dart
// The first attempt: the snack bar is shown from inside a build.
SoloBuilder<Connection>(
  solo: connection,
  builder: (context, state, child) {
    if (state == Connection.offline) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No connection')));
    }

    return child!;
  },
  child: ProfileView(controller: controller),
),
```

`SoloBuilder` is where the screen meets the state, so the call goes in its
builder. The builder runs inside a build, and a snack bar changes the state of
the `ScaffoldMessenger` above it, which a build may not do: a debug build stops
there with "The showSnackBar() method cannot be called during build." Nor does
a builder run once per change. It runs whenever the framework builds the widget
again, and every such build while the connection is offline makes the call
again.

### A reaction outside the build

```dart
SoloListener<Connection>(
  solo: connection,
  listenWhen: (previous, current) =>
      previous == Connection.online && current == Connection.offline,
  listener: (ctx, context, state) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No connection')));
  },
  child: ProfileView(controller: controller),
),
```

`SoloListener` runs `listener` for every change that `listenWhen` lets through,
handed the state of that change, and builds `child` as it is. The reaction
starts on a microtask after the change, outside any build, so it may show a
snack bar or push a route whoever wrote the state, the build of another widget
included. The state the widget subscribes at starts no reaction. Without
`listenWhen` every change reacts, the same state written again included; this
one says what a loss is, a step from online to offline.

The reaction is a job of the core and takes a `JobContext` first. The widget
cancels it when it leaves the tree, and the cancellation is cooperative, as the
next section shows. A failure of `listenWhen` or of a reaction goes to
`FlutterError`, whether the controller has `SoloListenable` or not.

The widget is for changes this screen did not make. The outcome of a job the
screen started is waited for on its `done`, as [Outcomes](#outcomes) shows, and
news that has to outlive the screen goes on a board of its own, as
[A notice the screen accepts](https://github.com/vi-k/solo/blob/main/packages/solo/doc/state.md#a-notice-the-screen-accepts)
on the state page of `solo` shows.

## A reaction the next change replaces

A search field writes what the user types to `query`, a controller of a
`String`, and the suggestions under it follow the latest text.
`api.suggest(text)` stands for the app's own call, which returns a
`Future<List<String>>`. The screen loads the suggestions in a reaction, and
`SoloListenerMode.restart` cancels the reaction to the old text when a new text
comes:

```dart
SoloListener<String>(
  solo: query,
  mode: SoloListenerMode.restart,
  listener: _suggest,
  child: SuggestionList(suggestions: _suggestions),
),
```

The mode says what a change does while an earlier reaction runs. `concurrent`,
the default, starts the next reaction beside it, `sequential` queues the
change, `droppable` drops it, and `keepLatest` keeps only the latest change
waiting. `restart` keeps the latest too and cancels the running reaction
without waiting for it. The next reaction starts when the cancelled one ends,
and when that is depends on how the reaction waits.

### The first attempt

```dart
// The first attempt: the replaced load runs to its end, and the next waits.
Future<void> _suggest(
  JobContext ctx,
  BuildContext context,
  String text,
) async {
  final found = await api.suggest(text);
  setState(() => _suggestions = found);
}
```

The cancellation is cooperative, and a plain `await` is no checkpoint. The load
for the old text runs to its end and its `setState` puts the old suggestions
up; only then does the reaction to the new text start. Every letter waits out
the load of the letter before it. Leaving the screen cancels the reaction the
same way, and the `setState` after the `await` then comes to a `State` that is
gone: the reaction fails, and the failure goes to `FlutterError`.

### Waiting with `ctx.join`

```dart
Future<void> _suggest(
  JobContext ctx,
  BuildContext context,
  String text,
) async {
  final found = await ctx.join(() => api.suggest(text));
  setState(() => _suggestions = found);
}
```

`ctx.join` is how a job waits for a call, and once the reaction is cancelled it
throws `Cancelled`: the old suggestions no longer come up, and a screen that
has left meets no `setState`. But it waits its call out first, which is what
keeps a save whole, so the next reaction starts as late as before.

### A wait that gives up

```dart
Future<void> _suggest(
  JobContext ctx,
  BuildContext context,
  String text,
) async {
  await ctx.pause(const Duration(milliseconds: 300));
  final found = await ctx.abandonable(() => api.suggest(text));
  setState(() => _suggestions = found);
}
```

`ctx.abandonable` stops waiting the moment the reaction is cancelled. The next
reaction starts at once, and the load for the old text ends with nobody waiting
for it. `ctx.pause` ends at once as well, so a letter typed within 300
milliseconds of the one before cancels the reaction before it loads anything.

`abandonable` leaves the old request running. A client that can stop its
request takes a token instead: `ctx.onCancel` cancels the token with the
reaction, and `ctx.join` waits only as long as the client takes to stop. The
error such a client throws when stopped is named once in
`Job.isCancellationError`, or every stop goes to `FlutterError` as a failure.
[A token through `onCancel`](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/cancellation.md#a-token-through-oncancel)
on the cancellation page of `async_job` shows both.

## Methods from a second import

`select` and `listen` arrive with an import of their own, next to the one the
rest of the package comes from:

```dart
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';

final canSave = controller.select((state) => state.canSave);
final subscription = canSave.listen(() => _onCanSave(canSave.value));
```

They are extensions on the framework's own `ValueListenable` and `Listenable`,
where another package's `select` and `listen` sit too. Two extensions with the
same member name on one type are ambiguous at every call site. A package
carrying them into every file that imports it would break a neighbour it never
heard of. The import is the choice.

Without it the methods are gone and what they do is not:

- `SoloSelection(controller, (state) => state.canSave)` is the same selection;
- `SoloSelector` needs no method at all;
- `addListener` with a callback you keep yourself is what `listen` does for
  you.

`SoloSubscription` and `SoloSubscriptions` come with the second import only. A
controller of your own with a `select` method keeps it, because an extension
always steps aside for a member.

## The controller's life

Nothing closes a controller for you. There is no `SoloProvider`: a controller
is an object, and it lives wherever the rest of your objects live.

A provider would add nothing to what follows. A `State`, a `ScopeModel` of
scopo and a `Provider` of `package:provider` all close the controller from a
synchronous `dispose`, and the controller is a plain object any of them can
hold; `BlocProvider` does the same with `bloc.close()`. None of them can wait
for the close to end, because `close()` is asynchronous: it waits for the
running job to stop, and with `SoloCloseMode.drain` for the queue as well.
Waiting for it takes an asynchronous lifecycle, such as `AsyncDataScope` of
scopo below, and scopo serves any object, a bloc included.

```dart
import 'dart:async';

class _ProfileScreenState extends State<ProfileScreen> {
  final controller = ProfileController(ProfileApi());

  @override
  void initState() {
    super.initState();
    controller.load();
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

`close()` cancels whatever is queued or running. A running body stops at its
next context call, which is what makes leaving the screen cheap; a running job
made with `cancellable: false` turns the cancellation down and runs to its end,
and a queued one is dropped. Once the close is over, it drops every listener
and stops notifying for good. Until then the listeners still hear what the
closing jobs write, from `ifCancelled` or from the body of a job that turned
the cancellation down. The screen does not wait for that: `SoloBuilder` lets go
of the controller in its own `dispose`. `close()` is safe on either side of
`super.dispose()`. Even with `SoloListenable` a controller is not a
`ChangeNotifier`: the method is `close()`, not `dispose()`, and it returns a
`Future` that completes when the job has actually stopped.

A controller shared by several screens lives where the other objects they share
live: a `get_it` registration, an `InheritedWidget` above those screens, a
scope of [scopo](https://pub.dev/packages/scopo), a field of the app object. It
is closed there, once.

A scope of scopo can also take the place of the `State` above. `ScopeModel`
creates the controller once it is mounted and hands it to `dispose` when it
leaves the tree, and the subtree reads it with `ScopeModel.of`:

```dart
import 'dart:async';

import 'package:scopo/scopo.dart';

ScopeModel<ProfileController>(
  create: (context) => ProfileController(ProfileApi())..load(),
  dispose: (controller) => unawaited(controller.close()),
  builder: (context) => ProfileView(
    controller: ScopeModel.of<ProfileController>(context, listen: false),
  ),
),
```

That `dispose` is synchronous, as in a `State`, and nothing waits for the
close. Where an asynchronous scope of scopo above it has to wait, put the
controller in `AsyncDataScope`. It awaits the future `disposeData` returns, and
a parent asynchronous scope of scopo is released only after its children:

```dart
AsyncDataScope<ProfileController>(
  initData: (context, ctx) async {
    final controller = ProfileController(ProfileApi());
    final unregister = ctx.onDiscard(controller.close);
    await ctx.abandonable(() => controller.load().value);
    unregister(); // from here on, disposeData closes it

    return controller;
  },
  disposeData: (controller) => controller.close(),
  progressBuilder: (context, _) => const CircularProgressIndicator(),
  errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
  builder: (context, controller) => ProfileView(controller: controller),
),
```

The scope is ready once the profile is loaded: until then it shows
`progressBuilder`, and a load that fails is what `errorBuilder` shows. Until it
is returned, the controller belongs to the body alone, since the scope hands
`disposeData` only a value it was given. `ctx.onDiscard` closes it on the two
other paths: a failed load, and a scope removed while it loads, where
`ctx.abandonable` stops waiting at once and the close cancels the load. The
registration goes at the handover, with no wait between it and the return.

What the parent releases outlives the jobs of the controller, a save it waits
out with `ctx.join` included. Under `ScopeModel` the parent releases it while
that save is still running. Both waits have a bound, `disposeScopeTimeout` of
the scope and `waitForChildrenTimeout` of its parent, three seconds by default.
Past it scopo reports the expiry and goes on with the release, as if it had not
waited at all. `ScopeTimeout.none` takes the bound off for one scope. A screen
further down reads the controller with
`AsyncDataScope.of<ProfileController>(context, listen: false).data`.

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

`done` never throws. `value` gives the value, rethrows the failure of a job
that failed and throws the `Cancelled` of one that was cancelled. `mounted`
after an `await` is the usual Flutter rule, and it applies here too.

A job nobody looks at is not silent. An unobserved `Failed` reaches the zone
that created the job, unless the job names its error in `isExpectedError`. So a
fire-and-forget call takes one of two forms. A job that names its expected
errors, as `load` names `ApiException`, needs nothing more: the call is
`controller.load()`, and a bug still reaches the zone. A call that needs no
outcome at all ends with `ignoreFailure()`: it says the outcome is nobody's
business, even when a bug ended the job.

The same road carries the errors no outcome holds, such as the failure of work
a body handed to `ctx.unattended`. A controller that overrides `onUnanswered`,
or a `Solo.unansweredHandler`, answers for them instead, and for an unobserved
`Failed` as well.
[Where each error goes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/errors.md#where-each-error-goes)
on the errors page of `solo` has the table of them. A `SoloObserver` sees such
a failure and does not take it: watching is not answering.

In a Flutter app an error that reaches the zone travels the zones outwards:

1. An error zone of your own around `runApp` sees it first.
2. Past that it reaches `PlatformDispatcher.instance.onError`, if you set one.
3. With none set, or when the callback returns `false`, the embedder gets the
   error, and its fallback is to print it.

What comes after is the embedder's business. The documentation of `onError`
promises nothing about the process, which may exit or stop responding after the
callback. A plain Dart program differs in one thing: an unhandled error ends
it, with exit code 255. That is the standalone VM's own reaction, not
Flutter's.

## Notes

| A failure of | Where it goes |
| --- | --- |
| A listener of a controller with `SoloListenable` | To `FlutterError.reportError`, as [A base class without Flutter](doc/mixins.md#a-base-class-without-flutter) on the mixins page shows. |
| A listener of a controller without it | To the zone, as [Where each error goes](https://github.com/vi-k/solo/blob/main/packages/solo/doc/errors.md#where-each-error-goes) on the errors page of `solo` has it: `SoloBuilder` and `SoloSelector` take such a controller, but `FlutterError.onError` never hears of a failure of its listeners. |
| A listener of a selection | Through `FlutterError`, whether the controller has `SoloListenable` or not: a selection reports its own listeners. |
| The selector of a selection | The controller's route, one of the two rows above: the selector runs inside a listener of the controller. |
| `listenWhen` or a reaction of `SoloListener` | Through `FlutterError`, whether the controller has `SoloListenable` or not: the widget reports them itself. |

| Question | Answer |
| --- | --- |
| When do listeners run? | Synchronously, in subscription order, on every state change. With `SoloListenable`, `value` and `currentState` are the same object. A reaction of `SoloListener` starts on a microtask after the change; its `listenWhen` runs with the listeners. There is no `stream` unless `SoloStream` is mixed in: the builders listen to the controller itself. |
| Are equal states filtered? | No. `emit` of a state equal to the current one still notifies: the listeners are the engine's own, and the engine compares nothing. A frame may swallow several of them, a listener will not. A selection filters its own value, which is the one a widget usually cares about, as [Selecting one value](#selecting-one-value) shows. |
| Several controllers on one screen? | Each with its own builder, as expected. `Listenable.merge([a, b])` in a `ListenableBuilder` covers the case where one widget depends on two; it takes controllers with `SoloListenable`, as [The controller as a `ValueListenable`](#the-controller-as-a-valuelistenable) shows. Work of one screen that must not wait for another goes to a controller of its own: [A tap that does not wait for a reload](https://github.com/vi-k/solo/blob/main/packages/solo/doc/jobs.md#a-tap-that-does-not-wait-for-a-reload). |
| Can I set `value`? | There is no setter. The state belongs to the jobs; a `ValueNotifier` face with a setter would give it away. |
| How do I test a screen? | On the fake clock of `testWidgets`: a timer a job waits on, such as the delay of a fake API, fires only when the test moves the clock. [Testing](doc/testing.md) has the three rules that follow from it. |

## Versions

| A change | Comes in |
| --- | --- |
| A fix that keeps the public API | a patch release, such as `1.0.1` |
| A new class, member or optional parameter | a minor release, such as `1.1.0` |
| A removed or renamed member, a changed signature or documented behaviour | a major release, such as `2.0.0` |
| A new value of an enum or a new subclass of a sealed class | a major release, such as `2.0.0` |

From 1.0.0 on, `flutter_solo` follows semantic versioning: the constraint
`^1.0.0` takes every minor and patch release, and they keep code written
against 1.0.0 working, but for the cases below. The public API is what
`package:flutter_solo/flutter_solo.dart` and
`package:flutter_solo/listenable.dart` export; the text of error messages and
of debug output is not part of it. A member that goes away is first marked
`@Deprecated` in a minor release, with the name to use instead, and is removed
in the next major one.

A minor release can add a member to a mixin you build on, such as
`SoloListenable`, and a member of the same name in your own code then stops
compiling. It can add a member to an interface you implement for a mock, such
as `JobContext` or `SoloContext`, and a fake that implements it by hand, rather
than through `noSuchMethod`, then stops compiling too. The changelog of such a
release names the members it adds. A new top-level name can clash with the same
name imported from another package, until one of the imports hides it with
`hide`.

`flutter_solo` re-exports `solo`, so a major release of `solo` or `async_job`
comes with a major release of `flutter_solo`.

## solo

[solo](https://pub.dev/packages/solo) is the controller itself: the queue and
its policies, the working type of a job, `canStart` and `keepWhile`, children,
observers, the waiting family and the rest of the API. This package re-exports
all of it, `SoloStream` included, whose broadcast `stream` is for what is not a
widget. If you are not writing widgets, take `solo` instead: it is pure Dart.
