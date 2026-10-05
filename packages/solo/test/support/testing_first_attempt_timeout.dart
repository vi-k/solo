// The first attempt of "Timeouts" in `doc/testing.md`, verbatim: the three
// lines of the deadline in the body of `load`, and the test that sees what
// they do. The controller is the page's with those lines in place of its
// `abandonable`, under the page's own name, which is why it has a library to
// itself.
import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart' hide test;

import 'testing_page_fixtures.dart' hide ProfileController;
import 'testing_stubs.dart';

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        onError: (state, error, stackTrace) => Failure(error),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.abandonable(
            () => api.fetchName().timeout(const Duration(milliseconds: 5)),
          );
          ctx.emit(Loaded(name));
          return name;
        },
      );

  /// A job behind `load` in the queue, for the test of what the queue
  /// waits for.
  Job<void> next() => run<ProfileState, void>(key: 'next', (ctx) async {});
}

/// The test of the first attempt. It passes: it shows what the deadline
/// leaves behind.
final deadlineOnTheCall = test('the deadline ends the job, not the call', () {
  fakeAsync((async) {
    final profile = ProfileController(FakeProfileApi());

    final job = profile.load()..ignore();
    async.elapse(const Duration(milliseconds: 5));

    expect(job.outcome, isA<Failed>());
    expect(async.pendingTimers, hasLength(1));

    async.elapse(const Duration(milliseconds: 15));
    expect(async.pendingTimers, isEmpty);

    profile.close();
    async.flushTimers();
  });
});
