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

/// How long a camera about to be released has to stop its recording.
///
/// A Galaxy A55 stopped a recording in 1.1 s when the app left, and as
/// long on a camera another app had taken; a stop that takes longer than
/// this loses the file, and the camera is let go. The owner of the screen
/// waits for the release for `CameraScreen.releaseTimeout`, 20 s, and this
/// bound keeps the stop well inside it. The bound is for this stop alone:
/// a command already under way in the queue before the release is waited
/// for whole.
const releaseStopTimeout = Duration(seconds: 3);

/// How long a stop of the record button has before the camera counts as
/// lost.
///
/// The stops of the button took 16 to 195 ms on the phones, and 1.1 s on
/// a Galaxy A55 when the app went to the background during one. On that
/// Galaxy a screen that went off in the middle of the start of a recording
/// left CameraX without its video encoder, and a stop after that never
/// ended. The bound is that of [releaseStopTimeout], for the same stops.
const stopTimeout = Duration(seconds: 3);

/// Stops the recording of [camera] for the record button; a stop that
/// has not ended within [stopTimeout] fails as a stop that fails does,
/// with a [CameraException].
///
/// A stop that ends after the bound hands its file to no one.
Future<XFile> stopInTime(CameraController camera) =>
    camera.stopVideoRecording().timeout(
      stopTimeout,
      onTimeout: () => throw CameraException(
        'stopTimeout',
        'The recording did not stop in ${stopTimeout.inSeconds} s.',
      ),
    );

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
