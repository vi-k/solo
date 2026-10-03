// What the profile code of `doc/state.md` takes from the quick start of the
// README: the profile states and the API. `Disconnected` is the page's own:
// its block under "Preserving an incompatible external state" adds the class
// to these states, in the same library, and it stands here verbatim.
import 'dart:async';

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

final class Disconnected extends ProfileState {
  const Disconnected();
}

/// A profile state, the way a journal would write it.
String describe(ProfileState state) => switch (state) {
      Initial() => 'Initial',
      Loading() => 'Loading',
      Loaded(:final name) => 'Loaded($name)',
      Failure(:final error) => 'Failure($error)',
      Disconnected() => 'Disconnected',
    };

/// The API of the quick start, answering when the test says so.
class ProfileApi {
  final _answer = Completer<String>();

  /// How many times the name was asked for.
  int calls = 0;

  Future<String> fetchName() {
    calls++;
    return _answer.future;
  }

  /// The request comes back with [name].
  void answer(String name) => _answer.complete(name);

  /// The request fails with [error].
  void fail(Object error) => _answer.completeError(error);
}
