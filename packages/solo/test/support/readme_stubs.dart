// What the code of `README.md` takes for granted: the application around
// the player and the session it reads. Each test sets the stage first, so
// a stub can take its time, fail, or report a fact of the device.
import 'dart:async';

import 'package:solo/solo.dart';

/// How the stubs behave in the test at hand, and what they saw.
final class Stage {
  final trace = <String>[];

  int fetchTake = 10;
  Object? fetchError;
  int downloadTake = 10;
  int closeTake = 0;
  int stopTake = 5;
  int loadStep = 10;
  int volumeTake = 5;
  int nameTake = 10;
  String name = 'Ada King';
}

Stage stage = Stage();

Future<void> _delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// The states of the player.
sealed class PlayerState {
  const PlayerState();
}

/// Nothing is loading.
final class Idle extends PlayerState {
  const Idle();

  @override
  String toString() => 'Idle';
}

/// A play has started and the device has nothing to read yet.
final class Loading extends PlayerState {
  const Loading();

  @override
  String toString() => 'Loading';
}

/// The device reads a download in.
final class Buffering extends PlayerState {
  final Track track;
  final int percent;

  const Buffering(this.track, this.percent);

  @override
  String toString() => 'Buffering($track, $percent)';
}

/// The device plays [track].
final class Playing extends PlayerState {
  final Track track;

  const Playing(this.track);

  @override
  String toString() => 'Playing($track)';
}

/// The device is gone.
final class Disconnected extends PlayerState {
  const Disconnected();

  @override
  String toString() => 'Disconnected';
}

/// A track the API knows.
final class Track {
  final String id;

  const Track(this.id);

  @override
  String toString() => 'Track($id)';
}

/// A download of a track, open until it is closed.
final class Download {
  final Track track;

  Download(this.track);

  Future<void> close() async {
    if (stage.closeTake > 0) {
      await _delay(stage.closeTake);
    }
    stage.trace.add('download of $track closed');
  }
}

/// The API the player fetches tracks from.
class Api {
  Future<Track> fetch(String id) async {
    stage.trace.add('fetch $id begins');
    await _delay(stage.fetchTake);
    if (stage.fetchError case final error?) {
      // ignore: only_throw_errors
      throw error;
    }
    stage.trace.add('fetch $id ends');
    return Track(id);
  }

  Future<Download> download(Track track) async {
    stage.trace.add('download of $track begins');
    await _delay(stage.downloadTake);
    stage.trace.add('download of $track opened');
    return Download(track);
  }
}

/// A device that plays a track on its own once it has read it in.
class Device {
  void Function()? onDisconnect;

  /// What the device plays now.
  Track? playing;

  /// The volumes it was set to, in order.
  final volumes = <double>[];

  Future<void> stop() async {
    stage.trace.add('device stops');
    await _delay(stage.stopTake);
    if (playing case final track?) {
      stage.trace.add('device stopped $track');
    }
    playing = null;
  }

  /// Reads [download] in, a half at a time; the stream ends when the
  /// track starts.
  Stream<int> load(Download download) async* {
    stage.trace.add('device loads ${download.track}');
    for (final percent in [50, 100]) {
      await _delay(stage.loadStep);
      yield percent;
    }
    playing = download.track;
    stage.trace.add('device plays ${download.track}');
  }

  Future<void> setVolume(double value) async {
    await _delay(stage.volumeTake);
    volumes.add(value);
    stage.trace.add('volume $value');
  }

  /// What the device does when its cable is pulled.
  void pullCable() => onDisconnect?.call();
}

/// The state of the session another controller holds.
final class SessionState {
  final String user;

  const SessionState(this.user);
}

/// The other controller the profile reads.
final class Session extends Solo<SessionState> {
  Session(super.initialState);
}

/// The profile API that takes the user.
class NameApi {
  final users = <String>[];

  /// Runs once the answer has reached the job that asked for it, before
  /// its body goes on.
  void Function()? afterAnswer;

  Future<String> fetchName(String user) {
    users.add(user);
    final answer = _delay(stage.nameTake).then((_) => stage.name);
    if (afterAnswer case final after?) {
      // Registered a turn after the call, so after the listener of the job
      // that waits for the answer: the answer is in its hands already.
      scheduleMicrotask(() => answer.then((_) => after()));
    }
    return answer;
  }
}
