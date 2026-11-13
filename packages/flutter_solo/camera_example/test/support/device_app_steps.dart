/// The earlier versions of the answers of `doc/device-app.md`: a method a
/// later section changed, the way an earlier section quotes it.
///
/// The page test holds the block of that earlier section to this file.
/// The trace of the section still comes from `CameraSession`, since the
/// change does not touch what the section runs.
library;

import 'package:camera/camera.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo_camera_example/camera_state.dart';

/// `CameraSession` before "Losing the camera": the switch does not follow
/// the errors of the next camera, and a failed stop leaves the state
/// recording.
final class SessionBeforeLosing extends Solo<CameraState> {
  /// Takes every video the camera makes.
  final void Function(XFile file) onCaptured;

  SessionBeforeLosing({required this.onCaptured}) : super(const Closed());

  /// "Rapid taps": moves to the next camera of the device.
  Job<void> switchCamera() => enqueue<Ready, void>((ctx) async {
    final cameras = await ctx.join(availableCameras);
    final camera = ctx.state.camera;
    final at = cameras.indexWhere((c) => c.name == camera.description.name);
    final next = cameras[(at + 1) % cameras.length];
    await ctx.join(() => camera.setDescription(next));
  });

  /// "A switch during a recording": stops the video and hands it to
  /// [onCaptured].
  Job<XFile?> stopRecording() => enqueue<Ready, XFile?>((ctx) async {
    final Ready(:camera, :flash, :recording) = ctx.state;
    if (!recording) return null;
    final file = await ctx.join(camera.stopVideoRecording);
    ctx.emit(Ready(camera: camera, flash: flash, recording: false));
    onCaptured(file);
    return file;
  });
}
