// The block of `doc/errors.md` under "Naming the expected errors",
// verbatim: the job of the quick start with its `isExpectedError`. It stands
// in a file of its own, because `errors_page.dart` holds the same job
// without the predicate, and a library holds one class of a name.
// `errors_rakes_test.dart` runs it.
import 'package:solo/solo.dart';

import 'errors_stubs.dart';

/// "Naming the expected errors". Not on the page: the controller around the
/// job, the one of the quick start, with no reporting hook of its own.
final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => enqueue<ProfileState, String>(
    key: 'load',
    policy: Policy.droppable,
    ifFailed: (state, error, stackTrace) => Failure(error),
    isExpectedError: (error) => error is ApiException,
    ifCancelled: (state, cancelled) => const Initial(),
    (ctx) async {
      ctx.emit(const Loading());
      final name = await ctx.abandonable(api.fetchName);
      ctx.emit(Loaded(name));
      return name;
    },
  );
}
