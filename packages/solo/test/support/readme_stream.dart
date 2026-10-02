// The block of `README.md` that mixes `SoloStream` into the controller of
// the quick start. The page elides the body as "same as above"; here it is
// the body of that controller, line for line. `readme_rakes_test` runs it.
import 'package:solo/solo.dart';

import 'readme_quick_start.dart'
    show Failure, Initial, Loaded, Loading, ProfileApi, ProfileState;

final class ProfileController extends Solo<ProfileState> with SoloStream {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        onError: (state, error, stackTrace) => Failure(error),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}
