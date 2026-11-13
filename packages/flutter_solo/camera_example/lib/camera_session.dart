import 'package:camera/camera.dart';
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

  /// Opens the first camera of the device.
  Job<void> open() => enqueue<CameraState, void>((ctx) async {
    ctx.emit(const Opening());
    final cameras = await ctx.join(availableCameras);
    if (cameras.isEmpty) {
      ctx.emit(const NoCamera());
      return;
    }
    final camera = CameraController(cameras.first, ResolutionPreset.medium);
    await ctx.join(camera.initialize);
    ctx.emit(
      Ready(camera: camera, flash: camera.value.flashMode, recording: false),
    );
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
}

/// The keys of the commands whose policy looks at them.
enum _Op { takePicture }
