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
final class Ready extends CameraState {
  final CameraController camera;
  final FlashMode flash;
  final bool recording;

  const Ready({
    required this.camera,
    required this.flash,
    required this.recording,
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
