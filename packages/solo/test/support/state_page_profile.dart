// The code of `doc/state.md` about the profile, verbatim, less the first
// attempts: the handlers and the load with its rule. Every piece of those
// blocks is a run of lines of this file, and `state_rakes_test.dart` runs
// it. The page shows the handlers as a bare call of `run`; here the call
// stands in a method.
import 'package:solo/solo.dart';

import 'state_profile_stubs.dart';

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  /// Not on the page: a fact from outside, the way the device reports one.
  void reflect(ProfileState state) => externalSetState(state);

  /// The block under "The handlers".
  Job<String> loadWithHandlers() => run<ProfileState, String>(
        // Both compute a state and nothing else. They run after the body,
        // children and cleanup, and the outcome is already fixed.
        onError: (state, error, stackTrace) => Failure(error),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );

  /// The block under "The rules" of "Preserving an incompatible external
  /// state".
  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        keepWhile: (state) => state is! Disconnected,
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
