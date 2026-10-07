// The model of `README.md`, as the page declares it under "Usage": the
// states, the controller and the view, under the two imports the block
// shows and nothing else. `test/readme_rakes_test.dart` runs it.
//
// What the page takes as the application's own stands below the page's
// code: the API behind the controller and the fake of the "Testing" section.

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
        ifFailed: (state, error, stackTrace) => Empty(),
        ifCancelled: (state, cancelled) => Empty(),
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

/// The API behind the controller, which the page takes as the
/// application's own: it answers [delay] after the call, with the name or
/// with [error].
class ProfileApi {
  /// How long a call takes.
  final Duration delay;

  /// What `fetchName` throws instead of answering, when it is set.
  final Object? error;

  /// Every name `saveName` was given, in the order the calls came back.
  final saved = <String>[];

  /// What the calls did, in order.
  final trace = <String>[];

  /// An API that answers [delay] after the call.
  ProfileApi({this.delay = const Duration(milliseconds: 10), this.error});

  /// The name of the profile.
  Future<String> fetchName() async {
    trace.add('fetch begins');
    await Future<void>.delayed(delay);
    trace.add('fetch ends');
    final error = this.error;
    if (error != null) {
      // The fake throws whatever the test handed it.
      // ignore: only_throw_errors
      throw error;
    }

    return 'Ada Lovelace';
  }

  /// Stores [name].
  Future<void> saveName(String name) async {
    trace.add('save begins');
    await Future<void>.delayed(delay);
    saved.add(name);
    trace.add('save ends');
  }
}

/// The fake of "Testing": "it answers with the name ten milliseconds after
/// the call".
class FakeApi extends ProfileApi {
  /// The fake as the page uses it.
  FakeApi({super.delay, super.error});
}

/// [state], the way a test writes it down.
String show(Profile state) => switch (state) {
      Empty() => 'Empty',
      Loading() => 'Loading',
      Loaded(:final name) => 'Loaded($name)',
    };
