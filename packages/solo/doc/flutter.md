# Flutter

Use `SoloListenable<S>` from `flutter_solo` as the controller base class.
It extends `SoloBase<S>` and implements `ValueListenable<S>`; it has no
`stream` — a widget rebuilds from `value`, and an operation's result is
awaited through its `Job`. The profile controller keeps the same states
and `load` method:

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

A screen can own its controller: create it in `initState` and close it
in `dispose`. A shared controller can instead live in your existing
dependency container, such as `provider`, `get_it` or an `InheritedWidget`.
The code that owns it is responsible for closing it; `flutter_solo` does
not provide a `SoloProvider` or close controllers automatically.

`ValueListenableBuilder` rebuilds when state changes. To navigate or show
a message after a particular operation, await that job's outcome at the
call site. Check `mounted` after waiting before using the widget's context.
Here, `ProfilePage` is the destination screen in the application:

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
controller jobs perform updates through their context. `ListenableBuilder`
and `AnimatedBuilder` also accept the controller when the builder does
not need the state value itself.
