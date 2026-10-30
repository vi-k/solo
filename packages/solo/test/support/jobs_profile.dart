// The code of `doc/jobs.md` under "The profile controller", verbatim:
// the controller the pages of the package build on. The README and the
// tests of the pages run it.
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

final class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}

class ProfileApi {
  Future<String> fetchName() =>
      Future.delayed(const Duration(milliseconds: 20), () => 'Ada Lovelace');
}

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
