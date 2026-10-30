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

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => enqueue((ctx) async {
    ctx.emit(const Loading());
    final name = await ctx.abandonable(api.fetchName);
    ctx.emit(Loaded(name));
    return name;
  });
}

Future<void> main() async {
  final profile = ProfileController(ProfileApi());
  profile.addListener(
    () => print(switch (profile.currentState) {
      Initial() => 'initial',
      Loading() => 'loading',
      Loaded(:final name) => 'loaded $name',
    }),
  );

  print(await profile.load().value);

  // The user pulls to refresh, then cancels the refresh before the answer.
  final refresh = profile.load();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await refresh.cancel();
  print(refresh.outcome);

  await profile.close();
}

/// The API the quick start of the README describes in words: it
/// answers after 20 ms.
class ProfileApi {
  Future<String> fetchName() =>
      Future.delayed(const Duration(milliseconds: 20), () => 'Ada Lovelace');
}
