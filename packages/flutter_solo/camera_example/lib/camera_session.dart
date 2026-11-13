import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_solo/flutter_solo.dart';

import 'camera_state.dart';

/// The controller of the camera screen: it owns the plugin's
/// [CameraController], and its commands run one at a time.
///
/// A picture or a video goes up through [onCaptured], to a screen that
/// outlives this one.
final class CameraSession extends Solo<CameraState> {
  /// Takes every picture and video the camera makes.
  final void Function(XFile file) onCaptured;

  CameraSession({required this.onCaptured}) : super(const Closed());

  /// The camera [suspend] let go, for [resume] to open again.
  CameraDescription? _suspended;

  /// The errors the platform reports for the open camera.
  StreamSubscription<CameraErrorEvent>? _errors;

  /// Opens the first camera of the device; with a camera open already it
  /// does nothing.
  Job<void> open() => enqueue<CameraState, void>((ctx) async {
    if (ctx.state is Ready) return;
    ctx.emit(const Opening());
    final cameras = await ctx.join(availableCameras);
    if (cameras.isEmpty) {
      ctx.emit(const NoCamera());
      return;
    }
    await _initialize(ctx, cameras.first);
  });

  /// Takes a picture and hands it to [onCaptured]; a tap during a shot
  /// gets the shot that is under way.
  Job<XFile?> takePicture() => enqueue<Ready, XFile?>(
    key: _Op.takePicture,
    policy: Policy.droppable,
    (ctx) async {
      final file = await ctx.join(ctx.state.camera.takePicture);
      onCaptured(file);
      return file;
    },
  );

  /// Moves the flash to its next mode: off, auto, always, and off again.
  ///
  /// The platform has one setting for the flash and the torch: while the
  /// torch is on, the mode waits in the state, and [toggleTorch] sets it
  /// when it puts the torch out.
  Job<void> cycleFlash() => enqueue<Ready, void>((ctx) async {
    final Ready(:camera, :flash, :recording, :torch) = ctx.state;
    final next = switch (flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    if (!torch) await ctx.join(() => camera.setFlashMode(next));
    ctx.emit(
      Ready(camera: camera, flash: next, recording: recording, torch: torch),
    );
  });

  /// The torch the latest tap asked for, and its job, until that job ends.
  ({bool on, Job<void> job})? _torchAsked;

  /// Turns the torch on or off: a tap asks for the opposite of the tap
  /// before it, or of the torch when no tap waits.
  ///
  /// Only the latest tap waits in the queue, and its job calls nothing
  /// when the torch is already where the tap asks: taps faster than the
  /// camera neither blink the torch nor flash it.
  Job<void> toggleTorch() {
    final lit = switch (currentState) {
      Ready(:final torch) => torch,
      _ => false,
    };
    final on = !(_torchAsked?.on ?? lit);
    final job = enqueue<Ready, void>(
      key: _Op.torch,
      policy: Policy.keepLatest,
      (ctx) async {
        final Ready(:camera, :flash, :recording, :torch) = ctx.state;
        if (on == torch || !hasTorch(camera.description)) return;
        await ctx.join(() => camera.setFlashMode(on ? FlashMode.torch : flash));
        ctx.emit(
          Ready(camera: camera, flash: flash, recording: recording, torch: on),
        );
      },
    );
    _torchAsked = (on: on, job: job);
    job.whenFinished((_) {
      if (identical(_torchAsked?.job, job)) _torchAsked = null;
    });
    return job;
  }

  /// Moves to the next camera of the device.
  ///
  /// Without a recording the plugin releases the camera before it opens the
  /// next one, so a switch that fails is [Broken], as a failed opening is.
  /// The camera it opens starts with a flash mode of its own, while the
  /// controller keeps the one it had, so the switch sets the mode of the
  /// button again, or lights the torch again. A lit torch goes out before
  /// the switch, while its camera is open (see [release]), and stays out
  /// on a camera without one. During a recording the camera it had goes on
  /// recording, with the torch, and a failure stays the error of the job.
  Job<void> switchCamera() => enqueue<Ready, void>((ctx) async {
    final cameras = await ctx.join(availableCameras);
    final Ready(:camera, :flash, :recording, :torch) = ctx.state;
    final at = cameras.indexWhere((c) => c.name == camera.description.name);
    final next = cameras[(at + 1) % cameras.length];
    if (torch && !(recording && hasTorch(next))) {
      await ctx.join(() => camera.setFlashMode(flash));
      ctx.emit(Ready(camera: camera, flash: flash, recording: recording));
    }
    try {
      await ctx.join(() => camera.setDescription(next));
    } on CameraException catch (error) {
      if (recording) rethrow;
      ctx.emit(Broken(error));
      _letGo(camera);
      return;
    }
    _watch(camera);
    if (!recording) {
      final lit = torch && hasTorch(next);
      await ctx.join(() => camera.setFlashMode(lit ? FlashMode.torch : flash));
      if (lit) {
        ctx.emit(
          Ready(camera: camera, flash: flash, recording: false, torch: true),
        );
      }
    }
  });

  /// Starts a video; a tap during a recording adds nothing.
  Job<void> startRecording() => enqueue<Ready, void>((ctx) async {
    final Ready(:camera, :flash, :recording, :torch) = ctx.state;
    if (recording) return;
    await ctx.join(camera.startVideoRecording);
    ctx.emit(
      Ready(camera: camera, flash: flash, recording: true, torch: torch),
    );
  });

  /// Stops the video and hands it to [onCaptured]; with no recording it
  /// gives `null`.
  ///
  /// A stop that fails leaves the plugin's controller recording for good,
  /// so the camera is [Broken] and let go.
  Job<XFile?> stopRecording() => enqueue<Ready, XFile?>((ctx) async {
    final Ready(:camera, :flash, :recording, :torch) = ctx.state;
    if (!recording) return null;
    final XFile file;
    try {
      file = await ctx.join(camera.stopVideoRecording);
    } on CameraException catch (error) {
      ctx.emit(Broken(error));
      _letGo(camera);
      return null;
    }
    ctx.emit(
      Ready(camera: camera, flash: flash, recording: false, torch: torch),
    );
    onCaptured(file);
    return file;
  });

  /// Stops a recording and hands it to [onCaptured], then frees the camera
  /// on the platform: the app has left the screen.
  ///
  /// The state is [Closed] before the release starts: a preview built on a
  /// controller being disposed throws. A lit torch goes out before it, as
  /// in [release]. A stop that fails still lets the camera go, and its
  /// error is the error of the job.
  Job<void> suspend() => enqueue<CameraState, void>((ctx) async {
    if (ctx.state case Ready(
      :final camera,
      :final flash,
      :final recording,
      :final torch,
    )) {
      _suspended = camera.description;
      try {
        if (recording) onCaptured(await ctx.join(camera.stopVideoRecording));
        if (torch) await ctx.join(() => camera.setFlashMode(flash));
      } finally {
        ctx.emit(const Closed());
        await ctx.join(camera.dispose);
      }
    }
  });

  /// Opens the camera that [suspend] let go: the app is back on the screen.
  Job<void> resume() => enqueue<CameraState, void>((ctx) async {
    final description = _suspended;
    if (description == null) return;
    _suspended = null;
    ctx.emit(const Opening());
    await _initialize(ctx, description);
  });

  /// Frees the camera on the platform; the job ends once the platform has.
  ///
  /// The owner awaits it before [close]: a release started from `onClose`
  /// would not be waited for.
  ///
  /// A lit torch goes out first, while its camera is open:
  /// `camera_android_camerax` keeps the torch on for the platform rather
  /// than for a camera, and would take the next camera's torch as lit. A
  /// camera the platform lost goes without that.
  Job<void> release() => enqueue<CameraState, void>((ctx) async {
    if (ctx.state case Ready(:final camera, :final flash, :final torch)) {
      try {
        if (torch) await ctx.join(() => camera.setFlashMode(flash));
      } finally {
        await ctx.join(camera.dispose);
      }
    }
    ctx.emit(const Closed());
  });

  @override
  void onClose() => unawaited(_errors?.cancel());

  /// Creates the camera of [description] on the platform and opens it.
  ///
  /// A permission the app does not have is [Denied], and any other failure
  /// is [Broken]. A camera the platform has created is let go; a create
  /// that failed leaves the plugin's controller on [_noCamera], with
  /// nothing to let go.
  Future<void> _initialize(
    SoloContext<CameraState, CameraState> ctx,
    CameraDescription description,
  ) async {
    final camera = CameraController(description, ResolutionPreset.medium);
    try {
      await ctx.join(camera.initialize);
    } on CameraException catch (error) {
      final code = error.code;
      ctx.emit(_denials.contains(code) ? Denied(code) : Broken(error));
      if (camera.cameraId != _noCamera) {
        _letGo(camera);
      }
      return;
    }
    _watch(camera);
    ctx.emit(
      Ready(camera: camera, flash: camera.value.flashMode, recording: false),
    );
  }

  /// Follows the errors of [camera] in place of those of the camera before
  /// it: the id changes with every opening and with a switch without a
  /// recording.
  void _watch(CameraController camera) {
    unawaited(_errors?.cancel());
    _errors = CameraPlatform.instance
        .onCameraError(camera.cameraId)
        .listen((event) => _lose(event.description));
  }

  /// The platform says the open camera failed: the state shows it at once,
  /// and the camera is let go.
  void _lose(String description) {
    if (currentState case Ready(:final camera)) {
      externalSetState(Broken(description));
      _letGo(camera);
    }
  }

  /// Frees [camera], which the state no longer holds, in a job of its own
  /// ahead of everything waiting in the queue: a [release] that waits there
  /// finds no camera in [Broken] and would end before this one.
  void _letGo(CameraController camera) => enqueueJob(
    job<CameraState, void>((ctx) => ctx.join(camera.dispose)),
    first: true,
  );
}

/// The keys of the commands whose policy looks at them.
enum _Op { takePicture, torch }

/// The `cameraId` of the plugin's controller until the platform has
/// created its camera: `CameraController.kUninitializedCameraId`, which the
/// plugin keeps for its own tests.
const _noCamera = -1;

/// The codes of the plugin's `CameraException` for a permission the app
/// does not have, as its README lists them.
const _denials = {
  'CameraAccessDenied',
  'CameraAccessDeniedWithoutPrompt',
  'CameraAccessRestricted',
  'AudioAccessDenied',
  'AudioAccessDeniedWithoutPrompt',
  'AudioAccessRestricted',
};
