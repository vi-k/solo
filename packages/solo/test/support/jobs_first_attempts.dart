// The first attempts of `doc/jobs.md`, and the second one of its pause,
// verbatim: every piece of the code under a "The first attempt" or "The
// second attempt" heading is a run of lines of this file, and
// `jobs_rakes_test.dart` runs it. The page shows each as methods on their
// own; here each version stands in a class.
import 'dart:async';

import 'package:solo/solo.dart';

import 'jobs_stubs.dart';
import 'test_solo.dart';

enum _Op { load, pause }

/// The first attempt of "A key for each request": the key of the method.
final class SharedKeyController extends Solo<CameraState>
    with OpenSolo<CameraState>, Workbench {
  SharedKeyController() : super(const Ready());

  SoloJob<Profile> load(String id) => run<Ready, Profile>(
        key: _Op.load,
        policy: Policy.droppable,
        (ctx) => ctx.wait(() => api.load(id)),
      );
}

/// The first attempt of "Pausing the queue": the gate goes where `run` puts
/// it, and `resume` alone clears the field.
final class TailGateController extends Solo<CameraState>
    with OpenSolo<CameraState>, Workbench {
  TailGateController() : super(const Ready());

  Completer<void>? _gate;

  bool get isPaused => _gate != null;

  void pause() {
    if (_gate != null) return;
    final gate = _gate = Completer<void>();
    run<CameraState, void>(
      key: _Op.pause,
      (ctx) => ctx.wait(() => gate.future),
    );
  }

  void resume() {
    _gate?.complete();
    _gate = null;
  }
}

/// The second attempt of "Pausing the queue": the gate goes in first, and
/// its body clears the field.
final class BodyGateController extends Solo<CameraState>
    with OpenSolo<CameraState>, Workbench {
  BodyGateController() : super(const Ready());

  Completer<void>? _gate;

  bool get isPaused => _gate != null;

  void pause() {
    if (_gate != null) return;
    final gate = _gate = Completer<void>();
    add(
      job<CameraState, void>(key: _Op.pause, (ctx) async {
        // Cancellation is not a resume, and a cancelled gate is not a pause.
        ctx.onCancel(() => _gate = null);
        await ctx.wait(() => gate.future);
      }),
      first: true,
    );
  }

  void resume() {
    _gate?.complete();
    _gate = null;
  }
}
