// The code of "The states on the way" in `doc/testing.md`, verbatim, on a
// controller the page does not show: the page's own without the line
// `ctx.emit(const Loading());`. The first attempt of the section passes on
// it, and the answer fails, which is what the section says of them. The
// controller has the page's name, which is why it has a library to itself.
import 'package:solo/solo.dart';
import 'package:test/test.dart' hide test;

import 'testing_page_fixtures.dart' hide ProfileController;
import 'testing_stubs.dart';

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => enqueue<ProfileState, String>(
    key: 'load',
    policy: Policy.droppable,
    ifFailed: (state, error, stackTrace) => Failure(error),
    ifCancelled: (state, cancelled) => const Initial(),
    (ctx) async {
      final name = await ctx.abandonable(api.fetchName);
      ctx.emit(Loaded(name));
      return name;
    },
  );
}

/// The first attempt: the test of "Awaiting the outcome", on this
/// controller. It passes.
final lastStateAlone = test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;

  expect(outcome, isA<Done<String>>());
  expect(
    profile.currentState,
    isA<Loaded>().having((state) => state.name, 'name', 'Ada Lovelace'),
  );

  await profile.close();
});

/// The answer, on this controller. It fails: the list holds `Loaded` alone.
final listened = test('load shows Loading, then the name', () async {
  final profile = ProfileController(FakeProfileApi());
  final states = <ProfileState>[];
  profile.addListener(() => states.add(profile.currentState));

  await profile.load().done;

  expect(states, [isA<Loading>(), isA<Loaded>()]);

  await profile.close();
});
