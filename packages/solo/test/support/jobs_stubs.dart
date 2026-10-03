// What the code of `doc/jobs.md` takes for granted: the states of the
// camera, the device, the store and the api its methods call, and the
// profile a load returns. Each test sets the stage first, so a stub can take
// its time or fail. `Workbench` is what the tests need of a controller of
// the page beside the page's own members.
import 'dart:async';

import 'package:solo/solo.dart';

/// How the stubs behave in the test at hand, and what they did.
final class Stage {
  /// What the device, the store, the api and the jobs did, in order.
  final trace = <String>[];

  /// How long the device takes over a seek, in milliseconds.
  int seekTake = 1000;

  /// How long the device takes over a zoom or a stop.
  int commandTake = 100;

  /// What `store.save` fails with, if it has to.
  Error? saveError;
}

Stage stage = Stage();

Future<void> _delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// The states of the camera.
sealed class CameraState {
  const CameraState();
}

/// The camera is on and takes commands.
final class Ready extends CameraState {
  const Ready();

  @override
  String toString() => 'Ready';
}

/// The device is gone: a state outside `Ready`.
final class Disconnected extends CameraState {
  const Disconnected();

  @override
  String toString() => 'Disconnected';
}

/// What `api.load` answers with.
final class Profile {
  final String id;

  const Profile(this.id);

  @override
  String toString() => 'Profile($id)';
}

/// What the device takes to stop an operation it has begun.
final class CancelToken {
  bool isCancelled = false;

  void cancel() {
    stage.trace.add('token cancelled');
    isCancelled = true;
  }
}

/// The hardware. A seek asks its token every ten milliseconds and stops
/// when the token says so.
final class Device {
  Future<void> zoom(double zoom) => _command('zoom $zoom');

  Future<void> stop() => _command('stop');

  Future<void> seek(Duration position, {CancelToken? cancelToken}) async {
    final name = 'seek ${position.inSeconds}';
    stage.trace.add('$name begins');
    for (var spent = 0; spent < stage.seekTake; spent += 10) {
      if (cancelToken?.isCancelled ?? false) {
        stage.trace.add('$name stopped by its token');
        return;
      }
      await _delay(10);
    }
    stage.trace.add('$name ends');
  }

  Future<void> _command(String name) async {
    stage.trace.add('$name begins');
    await _delay(stage.commandTake);
    stage.trace.add('$name ends');
  }
}

/// Where the camera keeps what it saves.
final class Store {
  Future<void> save() async {
    stage.trace.add('save begins');
    await _delay(50);
    final error = stage.saveError;
    if (error != null) {
      throw error;
    }
    stage.trace.add('save ends');
  }
}

/// The server the profiles are loaded from.
final class Api {
  Future<Profile> load(String id) async {
    stage.trace.add('load $id begins');
    await _delay(100);
    stage.trace.add('load $id ends');
    return Profile(id);
  }
}

final camera = Device();
final store = Store();
final api = Api();

/// What the tests need of a controller of the page beside the page's own
/// members: work that takes its time, and a look at the queue.
mixin Workbench on Solo<CameraState> {
  /// Work that takes [take] milliseconds in any state of the camera, or in
  /// `Ready` alone, and writes its start and its end to the trace.
  SoloJob<void> work(String name, {int take = 100, bool inReady = false}) {
    Future<void> body(SoloContext<CameraState, CameraState> ctx) async {
      stage.trace.add('$name starts');
      await ctx.wait(() => _delay(take));
      stage.trace.add('$name ends');
    }

    return inReady
        ? run<Ready, void>(key: name, body)
        : run<CameraState, void>(key: name, body);
  }

  /// The keys of what waits in the queue, in order.
  List<String> get waiting => [for (final job in queue.jobs) '${job.key}'];

  /// The key of the running root job, or `null`.
  String? get runningKey => current == null ? null : '${current!.key}';

  /// What the `onError` hook of this controller was told.
  final hookHeard = <String>[];

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      hookHeard.add('$job: $error');
}
