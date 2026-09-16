# Flutter

Use `SoloListenable<S>` from `flutter_solo` as the controller base class. It
extends `Solo<S>` and implements `ValueListenable<S>`; it has no `stream` — a
widget rebuilds from `value`, and an operation's result is awaited through its
`Job`. The profile controller keeps the same states and `load` method:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

final class ProfileController extends SoloListenable<ProfileState> {
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
one `with SoloStream` — has `SoloBuilder` instead: it takes any `Solo` and is
`ValueListenableBuilder` in every other respect. When the screen watches one
value out of a larger state, `SoloSelectBuilder` rebuilds only when that value
changes and leaves the rest of the state alone:

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
final class Session extends SoloListenable<SessionState>
    with SoloStream<SessionState> {
  Session(super.initialState);
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
