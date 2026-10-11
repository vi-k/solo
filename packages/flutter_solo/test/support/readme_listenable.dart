// The controller of "The controller as a `ValueListenable`" of `README.md`:
// the class of "Usage" with `SoloListenable` mixed in. The page writes its
// body as `// ...same as above...`; a library cannot, so the body stands
// here in full, and `test/readme_rakes_test.dart` holds it to the one in
// `readme_profile.dart`.

import 'package:flutter_solo/flutter_solo.dart';

import 'readme_profile.dart' show Empty, Loaded, Loading, Profile, ProfileApi;

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
