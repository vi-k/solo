# Mixins

`SoloListenable` makes a controller a `ValueListenable`, and so a `Listenable`
as well. The framework's `ValueListenableBuilder`, `ListenableBuilder` and
`AnimatedBuilder` take the controller as it is, and the package README shows
the first of them in
[The controller as a `ValueListenable`](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.md#the-controller-as-a-valuelistenable).
The builders of this package, `SoloBuilder` and `SoloSelector`, take any
controller, with the mixin or without it. This page is about three things
around the mixin:

- [A controller with both deliveries](#a-controller-with-both-deliveries):
  `SoloListenable` combines with `SoloStream` of `solo`, in either order. One
  change then has two error routes, and `close()` waits for every subscriber of
  `stream`.
- [A screen built on the stream](#a-screen-built-on-the-stream): a badge over
  `stream` that must show the state from its first frame.
- [A base class without Flutter](#a-base-class-without-flutter): a base the
  app's controllers share, in a package with no Flutter in it, keeps its report
  of a listener's failure when the controllers mix `SoloListenable` in.

The lines under a block of code are what a run of it shows: the text on the
screen after each step, or where a listener's failure was reported.

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
      enqueue<SessionState, void>((ctx) async => ctx.emit(SignedIn(name)));
}
```

Both deliveries are live, on their own schedules: the listener behind
`ValueListenableBuilder` fires synchronously, inside the change, and the
`stream` event arrives a microtask later. The order of the two mixins makes no
difference: neither overrides a member the other does.

The combination costs two things. One change has two error routes: a listener's
failure goes to `FlutterError`, and a failure of a `stream` subscriber goes to
the zone it subscribed in. And `await close()` waits until every subscriber of
`stream` has taken its done event, where a controller with `SoloListenable`
alone waits for none of its listeners. On a controller with both, an
`await for` over the `stream` holds `close()` while its body is still awaiting.
`pending` is a `SoloPendingStream` all that time, and
[What is holding the controller](https://github.com/vi-k/solo/blob/main/packages/solo/doc/diagnostics.md#what-is-holding-the-controller)
on the diagnostics page of `solo` shows how to ask for it.

## A screen built on the stream

The requirement is the ordinary one: a badge shows the state of the session it
is given, from its first frame. `Session` above has a `stream`, and the
framework has a widget that takes one.

### The first attempt

```dart
// The first attempt: the badge waits for the next change.
class SessionBadge extends StatelessWidget {
  final Session session;

  const SessionBadge(this.session, {super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<SessionState>(
    stream: session.stream,
    builder: (context, snapshot) => Text(switch (snapshot.data) {
      SignedIn(:final name) => 'signed in as $name',
      SignedOut() => 'signed out',
      null => 'nothing yet',
    }),
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
them. So the badge waits for a change to show what was true before it was
built. The state is there all along: `currentState` holds `SignedIn` in the
same builder that renders `nothing yet`.

A screen sees this every time it is built anew — its route pushed, a tab
switched away and back. Each time, the wait is as long as the next change,
which for a session can be the rest of the day. Closing makes the wait endless:
after `close()` the stream is done and no event is ever coming, while
`currentState` still holds the state the badge never showed.

```text
mounted over a session signed in as Ada: nothing yet
after close(): nothing yet
```

### The second attempt

`initialData` hands the builder a state to open with, and the state the session
is in is `currentState`:

```dart
// The second attempt: handed another session, the badge keeps old data.
StreamBuilder<SessionState>(
  stream: session.stream,
  initialData: session.currentState,
  builder: (context, snapshot) => Text(switch (snapshot.requireData) {
    SignedIn(:final name) => 'signed in as $name',
    SignedOut() => 'signed out',
  }),
),
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
badge shows Bob over Cy's session until that session changes. With
`key: ObjectKey(session)` next to `initialData`, the `StreamBuilder` is built
anew for another session and reads `initialData` again, and the badge shows Cy
at once: two arguments for every widget over the stream to carry.

### A builder that takes the controller

A builder of this package takes the controller rather than a delivery, so there
is nothing to pass for the first frame:

```dart
SoloBuilder<SessionState>(
  solo: session,
  builder: (context, state, _) => Text(switch (state) {
    SignedIn(:final name) => 'signed in as $name',
    SignedOut() => 'signed out',
  }),
),
```

```text
mounted over a session signed in as Ada: signed in as Ada
after Bob signs in: signed in as Bob
handed another session, signed in as Cy: signed in as Cy
```

`SoloBuilder` reads `currentState` in `build` and moves to a controller it is
handed. The badge therefore shows the state of the session it is given from the
first frame, and from the frame it is handed another. So does
`ValueListenableBuilder`, which `Session` fits because it mixes
`SoloListenable` in: with `valueListenable: session` it shows the same three
lines. The `stream` is for what is not a widget: a log, a bridge into code that
takes a `Stream`, a test that wants the whole sequence of changes.

## A base class without Flutter

A base class the app's controllers share can live in a package with no Flutter
in it. That package depends on `solo`, and the leaf, a controller of the app
that extends the base, mixes `SoloListenable` in. What every controller shares
goes into the base, and here that is a report of a listener's failure to the
app's own log, `AppLog`. `Profile` and `Empty` in the code below are the states
of
[Usage](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.md#usage)
in the package README.

### The first attempt

The engine has a hook for this failure, and the base overrides it:

```dart
// The first attempt: the override of the mixin wins over the base.
// A package of your own, without Flutter.
import 'package:meta/meta.dart';
import 'package:solo/solo.dart';

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
failure. A mixin sits above the class written before `with`, so a call of the
hook starts at the leaf and goes down in this order: `ProfileController`,
`SoloListenable`, `AppController`, `Solo`. The first `onListenerError` on the
way is the one that runs, here the one in `SoloListenable`, so its override
wins, with a report through `FlutterError`, and the base's override never runs.
The analyzer says nothing about it. Nor does `super` reach the base from the
leaf: `super` there is the mixin, and an override that only calls it is one the
analyzer calls unnecessary.

### A report under another name

The base keeps its report in a method of another name, which no mixin
overrides, and its own hook calls that:

```dart
// A package of your own, without Flutter.
import 'package:meta/meta.dart';
import 'package:solo/solo.dart';

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

The base's hook reports for a controller that mixes nothing in, and the hook of
`ProfileController` sends the failures of its own listeners to the same place.
A leaf that wants the report through `FlutterError` as well calls
`super.onListenerError` next to `reportListenerError`. `@protected` is repeated
on every override because Dart does not inherit it: left off, the hook is a
public member of that class and of every class that inherits the override. The
annotation comes from `package:meta`, which neither `solo` nor this package
exports: the package without Flutter depends on `meta` for it, and in the app
`package:flutter/foundation.dart` exports it.

That override is the leaf's to write, and a leaf that mixes `SoloListenable` in
without it reports through `FlutterError` as in the first attempt, with the
analyzer as silent. An app with several controllers writes it once, in a class
of its own between the base and the leaves:

```dart
// The app.
abstract class ListenableController<S extends Object> extends AppController<S>
    with SoloListenable {
  ListenableController(super.initialState);

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      reportListenerError(error, stackTrace);
}

final class ProfileController extends ListenableController<Profile> {
  ProfileController() : super(Empty());
}
```

A class sits above the mixins it mixes in, so the override of
`ListenableController` is the one that runs, in every leaf that extends it:
`ProfileController` here reports to `AppLog` and not through `FlutterError`. A
base with Flutter in it mixes `SoloListenable` in itself and keeps its own
override the same way. Mix it in once, though: mixed in again on a leaf over
such a class, it sits above that override and silences it as in the first
attempt.

Four leaves of this section side by side, each chain from the leaf down, with
the `onListenerError` that runs in bold:

| `ProfileController` | Chain from the leaf down | Report |
| --- | --- | --- |
| `extends AppController with SoloListenable` | `ProfileController` → **`SoloListenable`** → `AppController` → `Solo` | `FlutterError` |
| the same, with an override of its own | **`ProfileController`** → `SoloListenable` → `AppController` → `Solo` | `AppLog` |
| `extends ListenableController` | `ProfileController` → **`ListenableController`** → `SoloListenable` → `AppController` → `Solo` | `AppLog` |
| `extends ListenableController with SoloListenable` | `ProfileController` → **`SoloListenable`** → `ListenableController` → `SoloListenable` → `AppController` → `Solo` | `FlutterError` |
