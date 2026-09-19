import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

/// The model and the job of the README's Usage, with a state to fall back
/// to, on a screen that answers every way a load can end: with a name,
/// with a failure, cancelled, or handed to a tap that came while it ran.
void main() => runApp(MaterialApp(home: ProfileScreen(api: ProfileApi())));

/// A fake profile service: slow, and failing every third call.
class ProfileApi {
  int _calls = 0;

  /// How many times [fetchName] has been called.
  int get calls => _calls;

  Future<String> fetchName() async {
    final call = ++_calls;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (call % 3 == 0) {
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

/// One state, one job over it, a policy for the second tap, and the state
/// to fall back to when the job does not get to the end.
final class ProfileController extends Solo<Profile> with SoloListenable {
  final ProfileApi api;

  ProfileController(this.api) : super(Empty());

  Job<String> load() => run<Profile, String>(
        key: 'load',
        policy: Policy.droppable, // a second tap gets the first job
        (ctx) async {
          ctx.emit(Loading());
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));

          return name;
        },
        // Without these a load that fails or is cancelled leaves the state
        // on Loading: a spinner, and nothing on the screen to tap.
        onError: (state, error, stackTrace) => Empty(),
        onCancel: (state, cancelled) => Empty(),
      );
}

class ProfileScreen extends StatefulWidget {
  final ProfileApi api;

  const ProfileScreen({required this.api, super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final controller = ProfileController(widget.api);

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
        break; // the Cancel button, or close() when the screen went away
    }
  }

  void _say(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('flutter_solo'),
          actions: [
            // There in every state, so it can be tapped while a load runs:
            // the policy hands that tap the running job, and both taps hear
            // the one outcome.
            IconButton(
              onPressed: _load,
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: ValueListenableBuilder<Profile>(
            valueListenable: controller,
            builder: (context, state, _) => switch (state) {
              Empty() => TextButton(
                  onPressed: _load,
                  child: const Text('Load'),
                ),
              Loading() => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    TextButton(
                      onPressed: controller.cancelAll,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              Loaded(:final name) => Text(name),
            },
          ),
        ),
      );
}
