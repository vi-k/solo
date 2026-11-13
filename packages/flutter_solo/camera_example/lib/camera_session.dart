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
  Job<void> cycleFlash() => enqueue<Ready, void>((ctx) async {
    final Ready(:camera, :flash, :recording) = ctx.state;
    final next = switch (flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    await ctx.join(() => camera.setFlashMode(next));
    ctx.emit(Ready(camera: camera, flash: next, recording: recording));
  });

  /// Moves to the next camera of the device.
  Job<void> switchCamera() => enqueue<Ready, void>((ctx) async {
    final cameras = await ctx.join(availableCameras);
    final camera = ctx.state.camera;
    final at = cameras.indexWhere((c) => c.name == camera.description.name);
    final next = cameras[(at + 1) % cameras.length];
    await ctx.join(() => camera.setDescription(next));
    _watch(camera);
  });

  /// Starts a video; a tap during a recording adds nothing.
  Job<void> startRecording() => enqueue<Ready, void>((ctx) async {
    final Ready(:camera, :flash, :recording) = ctx.state;
    if (recording) return;
    await ctx.join(camera.startVideoRecording);
    ctx.emit(Ready(camera: camera, flash: flash, recording: true));
  });

  /// Stops the video and hands it to [onCaptured]; with no recording it
  /// gives `null`.
  ///
  /// A stop that fails leaves the plugin's controller recording for good,
  /// so the camera is [Broken] and let go.
  Job<XFile?> stopRecording() => enqueue<Ready, XFile?>((ctx) async {
    final Ready(:camera, :flash, :recording) = ctx.state;
    if (!recording) return null;
    final XFile file;
    try {
      file = await ctx.join(camera.stopVideoRecording);
    } on CameraException catch (error) {
      ctx.emit(Broken(error));
      _letGo(camera);
      return null;
    }
    ctx.emit(Ready(camera: camera, flash: flash, recording: false));
    onCaptured(file);
    return file;
  });

  /// Stops a recording and hands it to [onCaptured], then frees the camera
  /// on the platform: the app has left the screen.
  ///
  /// The state is [Closed] before the release starts: a preview built on a
  /// controller being disposed throws. A stop that fails still lets the
  /// camera go, and its error is the error of the job.
  Job<void> suspend() => enqueue<CameraState, void>((ctx) async {
    if (ctx.state case Ready(:final camera, :final recording)) {
      _suspended = camera.description;
      try {
        if (recording) onCaptured(await ctx.join(camera.stopVideoRecording));
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
  Job<void> release() => enqueue<CameraState, void>((ctx) async {
    if (ctx.state case Ready(:final camera)) {
      await ctx.join(camera.dispose);
    }
    ctx.emit(const Closed());
  });

  @override
  void onClose() => unawaited(_errors?.cancel());

  /// Creates the camera of [description] on the platform and opens it; a
  /// camera that fails to open is [Broken] and let go.
  Future<void> _initialize(
    SoloContext<CameraState, CameraState> ctx,
    CameraDescription description,
  ) async {
    final camera = CameraController(description, ResolutionPreset.medium);
    try {
      await ctx.join(camera.initialize);
    } on CameraException catch (error) {
      ctx.emit(Broken(error));
      _letGo(camera);
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

  /// Frees [camera], which the state no longer holds, in a job of its own.
  void _letGo(CameraController camera) =>
      enqueue<CameraState, void>((ctx) => ctx.join(camera.dispose));
}

/// The keys of the commands whose policy looks at them.
enum _Op { takePicture }
