// The code of `README.md` under "Why `currentState` and not `state`",
// verbatim, in the controller the section assumes: the one of the quick
// start, holding `session` as well, with an API that takes the user.
// `readme_rakes_test` runs it.
import 'package:solo/solo.dart';

import 'readme_quick_start.dart' show Loaded, ProfileState;
import 'readme_stubs.dart';

final class ProfileController extends Solo<ProfileState> {
  final NameApi api;
  final Session session;

  ProfileController(this.api, this.session, super.initialState);

  /// A fact from outside, the way a source of the application reports one.
  void reflect(ProfileState state) => externalSetState(state);

  Job<String> reload() => run<Loaded, String>(
        (ctx) async {
          // Another controller's snapshot: a plain read, and the name says
          // as much.
          final user = session.currentState.user;
          final name = await ctx.abandonable(() => api.fetchName(user));
          // This job's own state: a checkpoint that throws `Cancelled` if
          // the job has been cancelled or the state is no longer `Loaded`.
          if (ctx.state.name != name) {
            ctx.emit(Loaded(name));
          }
          return name;
        },
      );
}
