import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

/// The Usage fragment of README.md, with a fake API and a screen around it.
void main() => runApp(const MaterialApp(home: ProfileScreen()));

/// A fake profile service: slow, and failing every third call.
class ProfileApi {
  int _calls = 0;

  Future<String> fetchName() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (++_calls % 3 == 0) {
      throw StateError('the network is having a day');
    }

    return 'Ada Lovelace';
  }
}

sealed class Profile {}

final class Empty extends Profile {}

final class Loading extends Profile {}

final class Loaded extends Profile {
  final String name;

  Loaded(this.name);
}

/// One state, one job over it, and a policy for the second tap.
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

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final controller = ProfileController(ProfileApi());

  @override
  void dispose() {
    // Nothing closes the controller for you, and closing it cancels the
    // job that is still in flight: leaving the screen is that cheap.
    unawaited(controller.close());
    super.dispose();
  }

  Future<void> _load() async {
    switch (await controller.load().done) {
      case Done(:final value):
        _say('hello $value');
      case Failed(:final error):
        _say('$error');
      case Cancelled():
        break; // left the screen, or a second tap while the first ran
    }
  }

  void _say(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('flutter_solo')),
        body: Center(
          child: ValueListenableBuilder<Profile>(
            valueListenable: controller,
            builder: (context, state, _) => switch (state) {
              Empty() => TextButton(
                  onPressed: _load,
                  child: const Text('Load'),
                ),
              Loading() => const CircularProgressIndicator(),
              Loaded(:final name) => Text(name),
            },
          ),
        ),
      );
}
