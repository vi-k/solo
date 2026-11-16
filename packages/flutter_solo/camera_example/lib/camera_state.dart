import 'dart:async';

import 'package:camera/camera.dart';

/// What the camera screen shows.
sealed class CameraState {
  const CameraState();
}

/// No camera is open: before the first opening and after a release.
final class Closed extends CameraState {
  const Closed();
}

/// The camera is being opened.
final class Opening extends CameraState {
  const Opening();
}

/// The device has no camera.
final class NoCamera extends CameraState {
  const NoCamera();
}

/// The camera is open and takes commands.
///
/// [flash] is the mode of the flash button; [torch] says the torch is on,
/// and it is off when a camera opens.
final class Ready extends CameraState {
  final CameraController camera;
  final FlashMode flash;
  final bool recording;
  final bool torch;

  const Ready({
    required this.camera,
    required this.flash,
    required this.recording,
    this.torch = false,
  });
}

/// The camera failed, and opening it again may help.
final class Broken extends CameraState {
  final Object error;

  const Broken(this.error);
}

/// The app may not use the camera or the microphone; [code] is the code
/// of the plugin's `CameraException`.
final class Denied extends CameraState {
  final String code;

  const Denied(this.code);
}

/// Whether [camera] has a torch. The plugin cannot say: the screen gives
/// the torch to the back camera, and to no other.
bool hasTorch(CameraDescription camera) =>
    camera.lensDirection == CameraLensDirection.back;

/// How long a camera about to be released has to stop its recording.
///
/// A Galaxy A55 stopped a recording in 1.1 s when the app left, and as
/// long on a camera another app had taken; a stop that takes longer than
/// this loses the file, and the camera is let go. The owner of the screen
/// waits for the release for `CameraScreen.releaseTimeout`, 20 s, and this
/// bound keeps the stop well inside it.
const releaseStopTimeout = Duration(seconds: 3);

/// Stops the recording of [camera], which is about to be released, and
/// hands its file to [onCaptured]; a stop that fails or takes longer than
/// [releaseStopTimeout] hands nothing.
///
/// Gives `false` for a stop that ran out of time: the platform has not
/// answered, and a call to it before the release could hang as well.
Future<bool> stopBeforeRelease(
  CameraController camera,
  void Function(XFile file) onCaptured,
) async {
  final XFile file;
  try {
    file = await camera.stopVideoRecording().timeout(releaseStopTimeout);
  } on CameraException {
    return true;
  } on TimeoutException {
    return false;
  }
  onCaptured(file);
  return true;
}
