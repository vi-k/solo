# Flutter

Mix `SoloListenable` from `flutter_solo` into the controller. It makes a
`Solo<S>` a `ValueListenable<S>` as well, and adds no `stream` — a widget
rebuilds from `value`, and an operation's result is awaited through its `Job`.
The profile controller keeps the same states and `load` method:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

final class ProfileController extends Solo<ProfileState> with SoloListenable {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  // ...the jobs from the quick start...
}
```

A screen can own its controller: create it in `initState` and close it in
`dispose`. A shared controller can instead live in your existing dependency
container, such as `provider`, `get_it` or an `InheritedWidget`. The code that
owns it is responsible for closing it; `flutter_solo` does not provide a
`SoloProvider` or close controllers automatically.

`ValueListenableBuilder` rebuilds when state changes. To navigate or show a
message after a particular operation, await that job's outcome at the call
site. Check `mounted` after waiting before using the widget's context. Here,
`ProfilePage` is the destination screen in the application:

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
          child: ValueListenableBuilder<ProfileState>(
            valueListenable: profile,
            builder: (context, state, _) => state is Loading
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

`value` and `currentState` refer to the same object. There is no value setter;
controller jobs perform updates through their context. `ListenableBuilder` and
`AnimatedBuilder` also accept the controller when the builder does not need the
state value itself.

A controller that is not a `ValueListenable` — a plain `Solo` of your own, or
one `with SoloStream` — has `SoloBuilder` instead: it takes any `Solo` and
builds the same subtree from the same state. Two things differ, and both are
about where that state comes from. It reads `currentState` in `build`, where
`ValueListenableBuilder` builds from a copy that every notification refreshes.
And it compares controllers by identity: handed a new controller whose `==`
says it is the old one, `SoloBuilder` moves to it and `ValueListenableBuilder`
stays with the old. When the screen watches one value out of a larger state,
`SoloSelectBuilder` rebuilds only when that value changes and leaves the rest
of the state alone:

```dart
SoloSelectBuilder<ProfileState, bool>(
  solo: profile,
  selector: (state) => state is Loading,
  builder: (context, loading, _) => loading
      ? const CircularProgressIndicator()
      : ElevatedButton(
          onPressed: _open,
          child: const Text('Open profile'),
        ),
)
```

Hold the picking function in a field or a `static` where the parent rebuilds
often: it is compared by identity, so an inline closure is a new one every
build, and each of those builds makes a new selection.

## A controller with both deliveries

`SoloListenable` combines with `SoloStream` when a screen needs the widget side
and a broadcast `stream` at once:

```dart
sealed class SessionState {
  const SessionState();
}

final class SignedOut extends SessionState {
  const SignedOut();
}

final class SignedIn extends SessionState {
  final String name;

  const SignedIn(this.name);
}

final class Session extends Solo<SessionState> with SoloStream, SoloListenable {
  Session(super.initialState);

  Job<void> signIn(String name) =>
      run<SessionState, void>((ctx) async => ctx.emit(SignedIn(name)));
}
```

Both deliveries are live, on their own schedules: the listener behind
`ValueListenableBuilder` fires synchronously, inside the change, and the
`stream` event arrives a microtask later. The combination has a cost: a
listener failure goes to `FlutterError`, a stream failure to the zone -- one
change, two error routes; a rebuild and a stream event are two separate
reactions to one change, where a widget reading only `value` had one; and
`await close()` now waits for the stream's own subscribers too, which a plain
`SoloListenable` never did.

## A screen built on the stream

The requirement is the ordinary one: from its first frame, the screen shows the
state the controller is in. `Session` above has a `stream`, and the framework
has a widget that takes one.

### The first attempt

```dart
class SessionBadge extends StatelessWidget {
  final Session session;

  const SessionBadge(this.session, {super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<SessionState>(
        stream: session.stream,
        builder: (context, snapshot) => Text(
          switch (snapshot.data) {
            SignedIn(:final name) => 'signed in as $name',
            SignedOut() => 'signed out',
            null => 'nothing yet',
          },
        ),
      );
}
```

The `null` case is there because the type has one, and it is the case the
screen opens with:

```text
mounted over a session signed in as Ada: nothing yet
after Bob signs in: signed in as Bob
```

A broadcast stream replays nothing. A subscriber hears the changes that come
after it subscribed, and the state the controller was already in is not one of
them, so the badge waits for a change to show what was true before it was
built. The session is not what is wrong here: `currentState` holds `SignedIn`
all along, in the same builder that renders `nothing yet`.

A screen sees this every time it is built anew — a push and a pop, a tab
switched away and back — and the wait is as long as the next change, which for
a session can be the rest of the day. Closing takes the state away for good:
after `close()` the stream is done and no event is ever coming.

```text
mounted over a session signed in as Ada: nothing yet
after close(): nothing yet
```

### The state a screen needs is `currentState`

```dart
StreamBuilder<SessionState>(
  stream: session.stream,
  initialData: session.currentState,
  builder: (context, snapshot) => Text(
    switch (snapshot.data) {
      SignedIn(:final name) => 'signed in as $name',
      SignedOut() => 'signed out',
      null => 'nothing yet',
    },
  ),
)
```

```text
mounted over a session signed in as Ada: signed in as Ada
after Bob signs in: signed in as Bob
```

`snapshot.data` and `currentState` differ in where they come from.
`snapshot.data` is what the stream delivered to this subscriber; `currentState`
is the state the controller is in now, and `initialData` is what hands the
subscriber that state at the moment it subscribes.

A builder of this package takes the controller rather than a delivery, so the
gap never opens and there is nothing to pass for the first frame:

```dart
SoloBuilder<SessionState>(
  solo: session,
  builder: (context, state, _) => Text(
    switch (state) {
      SignedIn(:final name) => 'signed in as $name',
      SignedOut() => 'signed out',
    },
  ),
)
```

```text
mounted over a session signed in as Ada: signed in as Ada
after Bob signs in: signed in as Bob
```

The state has no `null` case now, because a controller always has a state. The
`stream` is for what is not a widget: a log, a bridge into code that takes a
`Stream`, a test that wants the whole sequence of changes.

## A base class without Flutter

A base class the app's controllers share can live in a package with no Flutter
in it, and the leaf mixes `SoloListenable` in:

```dart
// A package of your own, without Flutter.
abstract class AppController<S extends Object> extends Solo<S> {
  AppController(super.initialState);

  // ...what every controller of the app shares...
}

// The app.
final class ProfileController extends AppController<ProfileState>
    with SoloListenable {
  ProfileController() : super(const Initial());
}
```

Where the mixin sits decides whose `onListenerError` reports a listener's
failure. On the leaf, as here, it overrides the base: a base that overrides
`onListenerError` loses to the mixin's report through `FlutterError`, and the
leaf cannot reach the base's version through `super` either — that lands in the
mixin. A base that wants its own report keeps it in a method of another name,
and the leaf's `onListenerError` calls that. A base that mixes `SoloListenable`
in itself keeps its own override: a class sits above the mixins it mixes in.
Mix it in once, though, in the base or in the leaf: mixed in again on a leaf
over such a base, it sits above the base's override and silences it the same
way.
