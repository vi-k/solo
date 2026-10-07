// The code of `doc/testing.md` that its tests test and test with, verbatim:
// the controller and the fake of the introduction, and the journal of "The
// order of what happened". The states and `ProfileApi` are those of the
// quick start of `README.md`, which the page takes its controller from.
import 'package:solo/solo.dart';

import 'readme_quick_start.dart'
    show Failure, Initial, Loaded, Loading, ProfileApi, ProfileState;

export 'readme_quick_start.dart'
    show Failure, Initial, Loaded, Loading, ProfileApi, ProfileState;

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        ifFailed: (state, error, stackTrace) => Failure(error),
        ifCancelled: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.abandonable(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}

class FakeProfileApi implements ProfileApi {
  final String name;
  final Object? error;

  FakeProfileApi({this.name = 'Ada Lovelace', this.error});

  @override
  Future<String> fetchName() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final error = this.error;
    // ignore: only_throw_errors
    if (error != null) throw error;
    return name;
  }
}

final class Journal extends SoloObserver {
  final lines = <String>[];

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} started');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} ${job.outcome}');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      lines.add('state: ${transition.current.runtimeType}');
}
