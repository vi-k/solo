// The code of `doc/testing.md` under "isExpectedError", verbatim: the `load`
// of the page's controller with an `isExpectedError`, and the test of the
// section, which drives it. It stands in a file of its own, because
// `testing_page_fixtures.dart` holds the same controller without the
// predicate, and a library holds one class of a name. `test` is the one of
// `testing_stubs.dart`, and `testing_rakes_test` runs it as a test of its
// suite.
import 'package:solo/solo.dart';
import 'package:test/test.dart' hide test;

import 'testing_page_fixtures.dart' hide ProfileController;
import 'testing_stubs.dart';

/// `### isExpectedError`: the controller of the page, its `load` naming the
/// error the API throws when the network is down. The page shows the `load`.
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

/// `### isExpectedError`: the test of the first attempt, on this controller.
final failureExpected = test('a failed load shows the failure', () async {
  final profile = ProfileController(
    FakeProfileApi(error: const ApiException('no network')),
  );

  // ignore: cascade_invocations
  profile.load();
  await profile.close(mode: SoloCloseMode.drain);

  expect(profile.currentState, isA<Failure>());
});
