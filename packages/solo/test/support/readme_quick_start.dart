// The code of `README.md` under "Quick start", verbatim: every block of the
// section but the one that mixes in `SoloStream`, whose body is elided on
// the page. `readme_rakes_test` runs it.
// ignore_for_file: unreachable_from_main

import 'package:solo/solo.dart';

sealed class ProfileState {
  const ProfileState();
}

final class Initial extends ProfileState {
  const Initial();
}

final class Loading extends ProfileState {
  const Loading();
}

final class Loaded extends ProfileState {
  final String name;

  const Loaded(this.name);
}

final class Failure extends ProfileState {
  final Object error;

  const Failure(this.error);
}

class ProfileApi {
  Future<String> fetchName() => Future.delayed(
        const Duration(milliseconds: 20),
        () => 'Ada Lovelace',
      );
}

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
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}

Future<void> main() async {
  final profile = ProfileController(ProfileApi());
  void onChange() => print(profile.currentState);
  profile.addListener(onChange);
  try {
    final job = profile.load();
    profile.load(); // the existing job is returned

    print(await job.value);
    if (profile.currentState case Loaded(:final name)) {
      print(name);
    }
  } finally {
    profile.removeListener(onChange);
    await profile.close();
  }
}

Future<void> cancelLoading() async {
  final profile = ProfileController(ProfileApi());
  final job = profile.load();

  await job.cancel();
  print(job.outcome); // Cancelled(manual)
  await profile.close();
}
