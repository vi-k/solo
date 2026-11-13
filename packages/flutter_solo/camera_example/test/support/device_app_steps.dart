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

/// `CameraSession` before "Rapid taps of the torch": the flash button sets
/// the mode on the platform whatever the torch, and the queue has one key.
final class SessionBeforeTorch extends Solo<CameraState> {
  /// Takes every picture the camera makes.
  final void Function(XFile file) onCaptured;

  SessionBeforeTorch({required this.onCaptured}) : super(const Closed());

  /// "Rapid taps": takes a picture and hands it to [onCaptured].
  Job<XFile?> takePicture() => enqueue<Ready, XFile?>(
    key: _Op.takePicture,
    policy: Policy.droppable,
    (ctx) async {
      final file = await ctx.join(ctx.state.camera.takePicture);
      onCaptured(file);
      return file;
    },
  );

  /// "Rapid taps": moves the flash to its next mode.
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
}

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
    final Ready(:camera, :flash, :recording, :torch) = ctx.state;
    if (!recording) return null;
    final file = await ctx.join(camera.stopVideoRecording);
    ctx.emit(
      Ready(camera: camera, flash: flash, recording: false, torch: torch),
    );
    onCaptured(file);
    return file;
  });
}

/// `CameraSession` before "A denied permission": a failed opening is
/// [Broken] whatever its code, and it is let go even when the platform has
/// created no camera.
final class SessionBeforeDenied extends Solo<CameraState> {
  SessionBeforeDenied() : super(const Closed());

  /// Opens the camera of [description], as `open()` and `resume()` do.
  Job<void> openCamera(CameraDescription description) =>
      enqueue<CameraState, void>((ctx) => _initialize(ctx, description));

  /// "Losing the camera": creates the camera of [description] on the
  /// platform and opens it; a camera that fails to open is [Broken] and
  /// let go.
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

  /// Stands for the method of `CameraSession`, which did not change; the
  /// steps are not run.
  void _watch(CameraController camera) {}

  /// Stands for the method of `CameraSession`, which did not change; the
  /// steps are not run.
  void _letGo(CameraController camera) {}
}

/// The keys of [SessionBeforeTorch].
enum _Op { takePicture }
