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

  /// Takes a picture and hands it to [onCaptured].
  Job<XFile?> takePicture() => enqueue<Ready, XFile?>((ctx) async {
    final file = await ctx.join(ctx.state.camera.takePicture);
    onCaptured(file);
    return file;
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
