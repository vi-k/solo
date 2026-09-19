# Mixins

`SoloListenable` is the one mixin the
[README](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.md)
needs: it makes a controller a `ValueListenable`, and the builders of the
framework take it from there. This page is about what sits around it —
`SoloStream` beside it, a screen built on that stream, and a base class of
controllers with no Flutter to mix it into.

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
final class ProfileController extends AppController<Profile>
    with SoloListenable {
  ProfileController() : super(Empty());
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
