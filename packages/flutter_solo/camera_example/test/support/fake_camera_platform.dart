import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A [CameraPlatform] with durations instead of hardware.
///
/// It covers the calls this app makes: opening, a picture, the flash, a
/// recording with a switch of the camera, and releasing. Zoom, exposure,
/// focus and the preview pause are not overridden and throw
/// `UnimplementedError`. [log] holds one line for the
/// start and one for the end of every call that takes time on a phone, so
/// the order of the lines is the order in which the platform was asked.
/// The tests run on the fake clock of `testWidgets`: a call that takes
/// time finishes when the test pumps that long.
class FakeCameraPlatform extends CameraPlatform {
  /// The cameras `availableCameras` reports: the back one first.
  List<CameraDescription> cameras = const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
    CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 270,
    ),
  ];

  /// How long an opening takes.
  Duration openTime = const Duration(milliseconds: 100);

  /// How long a picture takes.
  Duration captureTime = const Duration(milliseconds: 300);

  /// How long a switch of the camera during a recording takes.
  Duration switchTime = const Duration(milliseconds: 150);

  /// How long releasing a camera takes.
  Duration disposeTime = const Duration(milliseconds: 50);

  /// How long stopping a recording takes.
  Duration stopTime = const Duration(milliseconds: 100);

  /// When set, an opening ends with this exception instead of an event.
  PlatformException? failOpen;

  /// The calls the platform got, in order.
  final List<String> log = [];

  final Map<int, _Camera> _cameras = {};
  int _lastId = 0;
  int? _recording;

  /// How many cameras were created and are not released yet.
  int get openCameras => _cameras.length;

  /// The platform takes the camera from the app, as another app would.
  void closeFromOutside(int cameraId) {
    _cameras[cameraId]?.closing.add(CameraClosingEvent(cameraId));
  }

  /// The platform reports a failure of the camera.
  void failFromOutside(int cameraId, String description) {
    _cameras[cameraId]?.errors.add(CameraErrorEvent(cameraId, description));
  }

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    final id = ++_lastId;
    _cameras[id] = _Camera(cameraDescription);
    log.add('create ${cameraDescription.lensDirection.name} #$id');
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    log.add('initialize #$cameraId start');
    await Future<void>.delayed(openTime);
    final failure = failOpen;
    if (failure != null) throw failure;
    log.add('initialize #$cameraId end');
    // Without this event `CameraController.initialize` never completes.
    _cameras[cameraId]?.initialized.add(
      CameraInitializedEvent(
        cameraId,
        640,
        480,
        ExposureMode.auto,
        false,
        FocusMode.auto,
        false,
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _cameras[cameraId]?.initialized.stream ?? const Stream.empty();

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _cameras[cameraId]?.errors.stream ?? const Stream.empty();

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      _cameras[cameraId]?.closing.stream ?? const Stream.empty();

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<XFile> takePicture(int cameraId) async {
    log.add('capture #$cameraId start');
    await Future<void>.delayed(captureTime);
    log.add('capture #$cameraId end');
    return XFile('/fake/picture-$cameraId.jpg');
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    log.add('flash #$cameraId ${mode.name}');
  }

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    _recording = options.cameraId;
    log.add('record #${options.cameraId} start');
  }

  @override
  Future<void> setDescriptionWhileRecording(
    CameraDescription description,
  ) async {
    final id = _recording;
    final direction = description.lensDirection.name;
    log.add('switch #$id $direction start');
    await Future<void>.delayed(switchTime);
    log.add('switch #$id $direction end');
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    log.add('stop #$cameraId start');
    await Future<void>.delayed(stopTime);
    _recording = null;
    log.add('record #$cameraId end');
    return XFile('/fake/video-$cameraId.mp4');
  }

  @override
  Future<void> dispose(int cameraId) async {
    log.add('dispose #$cameraId start');
    await Future<void>.delayed(disposeTime);
    _cameras.remove(cameraId);
    if (_recording == cameraId) _recording = null;
    log.add('dispose #$cameraId end');
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();
}

/// The streams of one camera. They stay open after `dispose`: the
/// controller waits on `first` of some of them, and a closed stream would
/// make that wait throw `No element`.
class _Camera {
  _Camera(this.description);

  final CameraDescription description;
  final initialized = StreamController<CameraInitializedEvent>.broadcast();
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final closing = StreamController<CameraClosingEvent>.broadcast();
}
