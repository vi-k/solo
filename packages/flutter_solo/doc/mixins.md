# Mixins

`SoloListenable` makes a controller a `ValueListenable`, and so a `Listenable`
as well: the framework's `ValueListenableBuilder`, `ListenableBuilder` and
`AnimatedBuilder` take the controller as it is, and the
[README](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.md)
builds its screen on the first of them. The builders of this package,
`SoloBuilder` and `SoloSelector`, take any controller, with the mixin or
without it. This page is about what sits around `SoloListenable` — `SoloStream`
of `solo` beside it, a screen built on that stream, and a base class of
controllers in a package without Flutter, where `SoloListenable` cannot go.

The lines under the code are what it prints when it runs. Two sections open
with the version the vocabulary of the framework and of the engine leads to — a
widget that takes a stream, a hook named after the failure it reports — and
show what that code does. Where the version that repairs it still falls short,
it stands as a second attempt, and the version to use follows under its own
heading. The section on both deliveries has nothing to trip over and opens with
the answer.

## A controller with both deliveries

`SoloListenable` combines with `SoloStream` when a controller that feeds
widgets also hands a broadcast `stream` to code that takes one:

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
`stream` event arrives a microtask later. The combination costs two things. One
change has two error routes: a listener's failure goes to `FlutterError`, and a
failure of a `stream` subscriber goes to the zone it subscribed in. And
`await close()` waits until every subscriber of `stream` has taken its done
event, which a plain `SoloListenable` does not do: an `await for` over
`session.stream` holds `close()` while its body is still awaiting.

## A screen built on the stream

The requirement is the ordinary one: the badge shows the state of the session
it is given, from its first frame. `Session` above has a `stream`, and the
framework has a widget that takes one.

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

A screen sees this every time it is built anew — its route pushed, a tab
switched away and back — and the wait is as long as the next change, which for
a session can be the rest of the day. Closing takes the state away for good:
after `close()` the stream is done and no event is ever coming.

```text
mounted over a session signed in as Ada: nothing yet
after close(): nothing yet
```

### The second attempt

`initialData` hands the builder a state to open with, and the state the session
is in is `currentState`:

```dart
StreamBuilder<SessionState>(
  stream: session.stream,
  initialData: session.currentState,
  builder: (context, snapshot) => Text(
    switch (snapshot.requireData) {
      SignedIn(:final name) => 'signed in as $name',
      SignedOut() => 'signed out',
    },
  ),
)
```

The data of a snapshot and `currentState` differ in where they come from. The
data is what the stream delivered to this subscriber, or `initialData` until it
delivers something; `currentState` is the state the controller is in now.
`initialData` hands the subscriber that state at the moment it subscribes, so
the snapshot has data from the first frame, and `requireData` reads it with no
`null` case to write. The fault shows when the badge is handed another session:

```text
mounted over a session signed in as Ada: signed in as Ada
after Bob signs in: signed in as Bob
handed another session, signed in as Cy: signed in as Bob
```

`StreamBuilder` reads `initialData` once, when it is first built. Handed a new
stream, it subscribes to it and keeps the data the old one delivered, so the
badge shows Bob over Cy's session until that session changes.

### A builder that takes the controller

A builder of this package takes the controller rather than a delivery, so there
is nothing to pass for the first frame:

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
handed another session, signed in as Cy: signed in as Cy
```

`SoloBuilder` reads `currentState` in `build` and moves to a controller it is
handed, so the badge shows the state of the session it is given from the first
frame, and from the frame it is handed another. The `stream` is for what is not
a widget: a log, a bridge into code that takes a `Stream`, a test that wants
the whole sequence of changes.

## A base class without Flutter

A base class the app's controllers share can live in a package with no Flutter
in it, and the leaf mixes `SoloListenable` in. What every controller shares
goes into the base, and here that is a report of a listener's failure to the
app's own log, `AppLog`.

### The first attempt

The engine has a hook for this failure, and the base overrides it:

```dart
// A package of your own, without Flutter.
abstract class AppController<S extends Object> extends Solo<S> {
  AppController(super.initialState);

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      AppLog.error(error, stackTrace);
}

// The app.
final class ProfileController extends AppController<Profile>
    with SoloListenable {
  ProfileController() : super(Empty());
}
```

A listener of `ProfileController` throws, and the report goes past the base:

```text
AppLog: nothing
FlutterError: Bad state: the listener blew up
```

Where the mixin sits decides whose `onListenerError` reports a listener's
failure. A mixin sits above the class it is mixed into, here above
`AppController`, so its override wins, with a report through `FlutterError`,
and the base's override never runs. The analyzer says nothing about it. Nor
does `super` reach the base from the leaf: `super` there is the mixin, and an
override that only calls it is one the analyzer calls unnecessary.

### A report under another name

The base keeps its report in a method of another name, which no mixin
overrides, and its own hook calls that:

```dart
// A package of your own, without Flutter.
abstract class AppController<S extends Object> extends Solo<S> {
  AppController(super.initialState);

  @protected
  void reportListenerError(Object error, StackTrace stackTrace) =>
      AppLog.error(error, stackTrace);

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      reportListenerError(error, stackTrace);
}

// The app.
final class ProfileController extends AppController<Profile>
    with SoloListenable {
  ProfileController() : super(Empty());

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      reportListenerError(error, stackTrace);
}
```

```text
AppLog: Bad state: the listener blew up
FlutterError: nothing
```

The base's hook reports for a controller that mixes nothing in, and the leaf's
hook sends its failures to the same place. A leaf that wants the report through
`FlutterError` as well calls `super.onListenerError` next to
`reportListenerError`. `@protected` is repeated on every override because Dart
does not inherit it: left off, the hook becomes a public member of every
controller of the app.

A base with Flutter in it mixes `SoloListenable` in itself and keeps its own
override: a class sits above the mixins it mixes in. Mix it in once, though:
mixed in again on a leaf over such a base, it sits above the base's override
and silences it the same way.
