import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_solo_camera_example/camera_lights.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone whose behaviour [FakeCameraPlatform] copies where the two
/// phones of the probes differ.
///
/// `android` is a Galaxy A55 on Android 17 with `camera_android_camerax`
/// 0.7.6+1; `iphone` is an iPhone 13 mini on iOS 27.0.1 with
/// `camera_avfoundation` 0.11.1. What each phone did is in
/// `docs/records/2026-11/2026-11-13-device-app-probes-report.md`.
enum FakePhone { android, iphone }

/// A [CameraPlatform] with durations instead of hardware.
///
/// It covers the calls this app makes: opening, a picture, the flash and the
/// torch, a recording with a switch of the camera, and releasing. Zoom,
/// exposure, focus and the preview pause are not overridden and throw
/// `UnimplementedError`. [log] holds one line for the start and one for the end
/// of every call that takes time on a phone, so the order of the lines is the
/// order in which the platform was asked. The tests run on the fake clock of
/// `testWidgets`: a call that takes time finishes when the test pumps that
/// long. A recording has a third line, `record #N started`, when the start of
/// the recording completes: `record #N start` is the call, `record #N end` the
/// end of the stop. An error a test sends through [failFromOutside] is the line
/// `camera #N error`.
///
/// Where a call meets another one, the fake does what the phones did; each
/// such rule names the phone it was seen on, and [phone] picks between
/// the two where they differ.
///
/// The fake answers the channel of `CameraLights` as well, from [lights]:
/// the app asks the platform which cameras have a torch and a flash.
class FakeCameraPlatform extends CameraPlatform {
  /// A fake that answers the channel of `CameraLights` until the next fake
  /// takes it.
  FakeCameraPlatform() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(CameraLights.channel, _answerLights);
  }

  /// The text of a denied camera on Android, from
  /// `createCameraWithSettings`: the only
  /// code the Galaxy gives, the first time and after "don't ask again".
  static CameraException get deniedOnAndroid => CameraException(
    'CameraAccessDenied',
    'Camera access permission was denied.',
  );

  /// The text of the first denial of the camera on the iPhone.
  static CameraException get deniedOnIphone => CameraException(
    'CameraAccessDenied',
    'User denied the camera access request.',
  );

  /// The text of every later opening on the iPhone after a denial: the
  /// system asks no more.
  static CameraException get deniedWithoutPromptOnIphone => CameraException(
    'CameraAccessDeniedWithoutPrompt',
    'User has previously denied the camera access request. '
        'Go to Settings to enable camera access.',
  );

  /// The text of a denied microphone on the iPhone, with the camera
  /// allowed.
  static CameraException get audioDeniedOnIphone => CameraException(
    'AudioAccessDenied',
    'User denied the audio access request.',
  );

  /// The error event the Galaxy sends when another app takes the camera
  /// (the system camera, full screen); no closing event comes with it.
  static const String takenOnAndroid =
      'The camera was already in use, possibly by a higher-priority '
      'camera client.';

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

  /// What the channel of `CameraLights` answers for each camera, by its
  /// name; a camera left out gets no answer. The back camera of [cameras]
  /// has a torch and a flash, the front one a flash alone, as the first
  /// two cameras of an iPhone 13 mini.
  Map<String, ({bool torch, bool flash})> lights = const {
    'back': (torch: true, flash: true),
    'front': (torch: false, flash: true),
  };

  /// When set, the channel of `CameraLights` gives this in place of an
  /// answer: a `PlatformException` as a failing platform would, or a
  /// `MissingPluginException` as a platform without the app's handler.
  Exception? failLights;

  /// The phone the fake copies where the phones differ.
  FakePhone phone = FakePhone.android;

  /// Copies [which] whole: sets [phone] to it, and puts its cameras in
  /// [cameras] and its answer in [lights], as `availableCameras` and the
  /// channel gave them on that phone.
  ///
  /// A Galaxy A55 has a flash unit on camera `0` alone, its first back
  /// camera; `1` and `3` are front cameras, `2` the second back one. An
  /// iPhone 13 mini has a torch on its back cameras and a flash on all
  /// three.
  void useCamerasOf(FakePhone which) {
    phone = which;
    const none = (torch: false, flash: false);
    switch (which) {
      case FakePhone.android:
        cameras = const [
          CameraDescription(
            name: '0',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90,
          ),
          CameraDescription(
            name: '1',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 270,
          ),
          CameraDescription(
            name: '2',
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90,
          ),
          CameraDescription(
            name: '3',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 270,
          ),
        ];
        lights = const {
          '0': (torch: true, flash: true),
          '1': none,
          '2': none,
          '3': none,
        };
      case FakePhone.iphone:
        cameras = const [
          CameraDescription(
            name: _iphoneBack,
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90,
          ),
          CameraDescription(
            name: _iphoneFront,
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 90,
          ),
          CameraDescription(
            name: _iphoneWide,
            lensDirection: CameraLensDirection.back,
            sensorOrientation: 90,
          ),
        ];
        lights = const {
          _iphoneBack: (torch: true, flash: true),
          _iphoneFront: (torch: false, flash: true),
          _iphoneWide: (torch: true, flash: true),
        };
    }
  }

  /// How long an opening takes.
  Duration openTime = const Duration(milliseconds: 100);

  /// How long a picture takes: from 0.5 to 3.9 s on the Galaxy, from 0.2
  /// to 0.6 s on the iPhone.
  Duration captureTime = const Duration(milliseconds: 300);

  /// How long a switch of the camera during a recording takes.
  Duration switchTime = const Duration(milliseconds: 150);

  /// How long releasing a camera takes.
  Duration disposeTime = const Duration(milliseconds: 50);

  /// How long starting a recording takes: about a second on the Galaxy.
  /// The iPhone starts one in 27 to 183 ms in a profile build; in a debug
  /// build the first recording of the process took 6 to 12.6 s, and a
  /// later one 25 to 138 ms.
  Duration recordStartTime = const Duration(seconds: 1);

  /// How long stopping a recording takes.
  Duration stopTime = const Duration(milliseconds: 100);

  /// How long lighting the torch takes: `setFlashMode(FlashMode.torch)`,
  /// with the lines `flash #N torch start` and `flash #N torch end`. Any
  /// other mode is set at once, with one line, and puts the torch out.
  Duration torchTime = const Duration(milliseconds: 50);

  /// Galaxy: the torch flag of `camera_android_camerax` 0.7.6+1, one for
  /// the platform rather than one for a camera. Only `setFlashMode` changes
  /// it: neither a release nor a new camera puts it down.
  bool _torchEnabled = false;

  /// When set, an opening ends with this exception instead of an event.
  PlatformException? failOpen;

  /// When set, a stop of a recording ends with this error, after
  /// [stopTime], and the platform has no recording left: a
  /// [CameraException] as the plugin gives, or any other error as a bug
  /// would. A knob for the tests, not a rule of a phone.
  Object? failStop;

  /// When set, a stop of a recording never ends. A knob for the tests, not
  /// a rule of a phone.
  bool hangStop = false;

  /// When set, setting the flash mode never ends, with the line
  /// `flash #<id> <mode> start`: a platform stuck after a stop that hung.
  /// A knob for the tests, not a rule of a phone.
  bool hangFlash = false;

  /// When set, a switch during a recording ends with this exception, after
  /// [switchTime], and the recording stays on the camera it had. A knob for
  /// the tests, not a rule of a phone.
  CameraException? failSwitch;

  /// When set, creating a camera throws this, as both phones do without
  /// the permission: the denial comes from `createCameraWithSettings`,
  /// not from `initialize`. See [deniedOnAndroid] and the others for the
  /// texts. The line of a create that failed is `create back failed`, with
  /// no id: no camera was created.
  CameraException? failCreate;

  /// The calls the platform got, in order.
  final List<String> log = [];

  final Map<int, _Camera> _cameras = {};
  int _lastId = 0;
  int? _recording;

  /// The camera the iPhone's plugin holds: it has one at a time.
  int? _current;

  /// A switch of the camera during a recording that has not ended.
  Future<void>? _switching;

  /// How many cameras were created and are not released yet.
  int get openCameras => _cameras.length;

  /// Whether the preview of the camera shows a picture: the camera is
  /// open, and no rule below has taken its picture away.
  bool hasPicture(int cameraId) {
    final camera = _cameras[cameraId];
    return camera != null && !camera.closed && !camera.previewLost;
  }

  /// Whether the torch of the camera is on: the last mode it was set to is
  /// `FlashMode.torch`.
  bool torchOn(int cameraId) => _cameras[cameraId]?.torch ?? false;

  /// The platform takes the camera from the app, as another app would.
  void closeFromOutside(int cameraId) {
    _cameras[cameraId]?.closing.add(CameraClosingEvent(cameraId));
  }

  /// The platform reports a failure of the camera.
  ///
  /// Galaxy: a recording on the camera goes on, and a stop after the error
  /// ends it as usual, in about 1.1 s there, with the file whole.
  void failFromOutside(int cameraId, String description) {
    final camera = _cameras[cameraId];
    if (camera == null) return;
    log.add('camera #$cameraId error');
    camera.errors.add(CameraErrorEvent(cameraId, description));
  }

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    final failure = failCreate;
    if (failure != null) {
      log.add('create ${cameraDescription.lensDirection.name} failed');
      throw failure;
    }
    final id = ++_lastId;
    final camera = _Camera(cameraDescription);
    // A camera whose release failed stays open (see `dispose`) but is
    // left out: what the Galaxy does with a camera opened after that was
    // not filmed, and counting it would mark every later camera.
    final others = _cameras.values
        .where((c) => !c.closed && !c.releaseFailed)
        .toList();
    switch (phone) {
      case FakePhone.android:
        // Galaxy: a camera opened before the previous one was released
        // works for pictures, but its preview is empty once the previous
        // one is released, and its own dispose then fails.
        if (others.isNotEmpty) camera.openedOverAnother = true;
      case FakePhone.iphone:
        // iPhone: the plugin holds one camera; creating a new one closes
        // the previous one.
        for (final other in others) {
          other.closed = true;
        }
    }
    _cameras[id] = camera;
    _current = id;
    log.add('create ${cameraDescription.lensDirection.name} #$id');
    if (phone == FakePhone.android) {
      // Galaxy: the plugin creates a camera by unbinding the ones open,
      // and a picture in progress on them fails as the camera is created.
      for (final MapEntry(:key, :value) in _cameras.entries) {
        if (key != id) _loseCapture(key, value);
      }
    }
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
  Future<XFile> takePicture(int cameraId) {
    log.add('capture #$cameraId start');
    final camera = _cameras[cameraId];
    final shot = Completer<XFile>();
    if (camera == null || camera.closed) {
      // iPhone: a picture asked of a camera the plugin no longer holds
      // never completes.
      return shot.future;
    }
    final timer = Timer(captureTime, () {
      camera.capture = null;
      log.add('capture #$cameraId end');
      shot.complete(XFile('/fake/picture-$cameraId.jpg'));
    });
    camera.capture = _Capture(shot, timer);
    return shot.future;
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    if (hangFlash) {
      log.add('flash #$cameraId ${mode.name} start');
      return Completer<void>().future;
    }
    final camera = _cameras[cameraId];
    final hasTorch = camera != null && _lightsOf(camera.description).torch;
    if (phone == FakePhone.android && _torchEnabled) {
      if (mode == FlashMode.torch) {
        // Galaxy, from the plugin's source: with the flag up the torch is
        // taken as lit, and the call returns at once.
        log.add('flash #$cameraId torch skipped');
        return;
      }
      // Galaxy, from the plugin's source: any other mode first puts the
      // torch out on the camera open now. A camera without one refuses,
      // and the plugin reports that as an error of the camera; the text is
      // CameraX's, the event was not filmed.
      _torchEnabled = false;
      if (!hasTorch && camera != null) {
        log.add('camera #$cameraId error');
        camera.errors.add(
          CameraErrorEvent(
            cameraId,
            'java.lang.IllegalStateException: No flash unit',
          ),
        );
      }
    }
    if (mode != FlashMode.torch) {
      log.add('flash #$cameraId ${mode.name}');
      camera?.torch = false;
      return;
    }
    log.add('flash #$cameraId torch start');
    // Both plugins: the flash mode and the torch are one setting, and
    // `camera_avfoundation` 0.11.1 refuses the torch to a camera without
    // one. Which cameras have one is in [lights].
    if (!hasTorch) {
      log.add('flash #$cameraId torch failed');
      throw PlatformException(
        code: 'setFlashModeFailed',
        message: 'Device does not support torch mode',
      );
    }
    await Future<void>.delayed(torchTime);
    camera.torch = true;
    _torchEnabled = true;
    log.add('flash #$cameraId torch end');
  }

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    final id = options.cameraId;
    log.add('record #$id start');
    await Future<void>.delayed(recordStartTime);
    final camera = _cameras[id];
    if (camera == null || camera.closed) {
      switch (phone) {
        case FakePhone.android:
          throw UnsupportedError(
            'Not filmed on the Galaxy: a camera released while its '
            'recording was starting.',
          );
        case FakePhone.iphone:
          // iPhone: a camera released while its recording was starting;
          // the start still completes, and the controller, now on the
          // next camera, believes it records. No `started` line.
          return;
      }
    }
    _recording = id;
    log.add('record #$id started');
    // Galaxy: the camera rebinds to start a recording and sends a closing
    // event, though it stays open.
    if (phone == FakePhone.android) closeFromOutside(id);
  }

  @override
  Future<void> setDescriptionWhileRecording(
    CameraDescription description,
  ) async {
    final id = _recording;
    final direction = description.lensDirection.name;
    log.add('switch #$id $direction start');
    final switched = Future<void>.delayed(switchTime);
    _switching = switched;
    await switched;
    if (identical(_switching, switched)) _switching = null;
    final failure = failSwitch;
    if (failure != null) {
      log.add('switch #$id $direction failed');
      throw failure;
    }
    log.add('switch #$id $direction end');
    // Both plugins, from their source: the next camera's torch is dark.
    // `camera_android_camerax` 0.7.6+1 unbinds the camera and binds the
    // next one, its torch flag left as it was; `camera_avfoundation`
    // 0.11.1 takes a new capture device and sets no torch on it.
    _cameras[id]
      ?..description = description
      ..torch = false;
    // Galaxy: the switch rebinds the camera and sends a closing event.
    if (id != null && phone == FakePhone.android) closeFromOutside(id);
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    log.add('stop #$cameraId start');
    if (hangStop) return Completer<XFile>().future;
    // Both phones: a stop asked during a switch ends after the switch.
    await _switching;
    if (_recording == null) {
      switch (phone) {
        case FakePhone.android:
          throw UnsupportedError(
            'Not filmed on the Galaxy: a stop with no recording on the '
            'platform side.',
          );
        case FakePhone.iphone:
          // iPhone: a stop with no recording on the platform side.
          throw PlatformException(
            code: 'Error -1008',
            message: 'Video is not recording!',
            details: 'NSCocoaErrorDomain',
          );
      }
    }
    final id = _recording!;
    await Future<void>.delayed(stopTime);
    final failure = failStop;
    if (failure != null) {
      _recording = null;
      log.add('stop #$cameraId failed');
      throw failure;
    }
    _recording = null;
    log.add('record #$cameraId end');
    // Galaxy: the camera rebinds after the recording and sends a closing
    // event.
    if (phone == FakePhone.android) closeFromOutside(id);
    return XFile('/fake/video-$cameraId.mp4');
  }

  @override
  Future<void> dispose(int cameraId) async {
    log.add('dispose #$cameraId start');
    final camera = _cameras[cameraId];
    switch (phone) {
      case FakePhone.android:
        // Galaxy: releasing the camera under a picture loses the picture.
        if (camera != null) _loseCapture(cameraId, camera);
        await Future<void>.delayed(disposeTime);
        if (camera != null && camera.openedOverAnother) {
          // Galaxy: the camera opened over another one cannot release
          // its preview; it stays open.
          camera.releaseFailed = true;
          throw PlatformException(
            code: 'IllegalStateException',
            message:
                'java.lang.IllegalStateException: '
                'releaseFlutterSurfaceTexture() cannot be called if the '
                'flutterSurfaceProducer for the camera preview has not yet '
                'been initialized.',
          );
        }
        _cameras.remove(cameraId);
        for (final other in _cameras.values) {
          // Galaxy: see `createCameraWithSettings`.
          if (other.openedOverAnother) other.previewLost = true;
        }
      case FakePhone.iphone:
        // iPhone: the release waits for a picture in progress (the
        // plugin's session queue). The picture reaches the controller,
        // but a `CameraController` disposed meanwhile throws in debug
        // when `takePicture` writes its `value`.
        await camera?.capture?.shot.future;
        await Future<void>.delayed(disposeTime);
        // iPhone: the plugin releases the camera it holds, whatever the
        // id; a newer camera is closed by the release of an older one.
        final current = _cameras[_current];
        if (current != null) current.closed = true;
        _current = null;
        _cameras.remove(cameraId);
    }
    if (_recording == cameraId) _recording = null;
    log.add('dispose #$cameraId end');
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  /// The answer of [lights] for [camera]: none for a camera left out.
  ({bool torch, bool flash}) _lightsOf(CameraDescription camera) =>
      lights[camera.name] ?? (torch: false, flash: false);

  /// Answers the channel of `CameraLights`: the names of the cameras in,
  /// what each can light out.
  Future<Object?> _answerLights(MethodCall call) async {
    final failure = failLights;
    if (failure != null) throw failure;
    return {
      for (final name in (call.arguments as List<Object?>).cast<String>())
        if (lights[name] case final light?)
          name: {'torch': light.torch, 'flash': light.flash},
    };
  }

  /// Galaxy: a picture in progress on camera [id] fails: an error event,
  /// then the capture throws. The line of the rule is `capture #N failed`.
  void _loseCapture(int id, _Camera camera) {
    final capture = camera.capture;
    if (capture == null) return;
    capture.timer.cancel();
    camera.capture = null;
    camera.errors.add(
      CameraErrorEvent(
        id,
        'Image capture failed due to the camera being closed.',
      ),
    );
    log.add('capture #$id failed');
    capture.shot.completeError(
      PlatformException(
        code: 'ImageCaptureException',
        message:
            'androidx.camera.core.ImageCaptureException: '
            'Camera is closed.',
      ),
    );
  }
}

/// The names of the cameras of an iPhone 13 mini: the wide back camera,
/// the front one, and the ultra wide back one.
const _iphoneBack = 'com.apple.avfoundation.avcapturedevice.built-in_video:0';
const _iphoneFront = 'com.apple.avfoundation.avcapturedevice.built-in_video:1';
const _iphoneWide = 'com.apple.avfoundation.avcapturedevice.built-in_video:5';

/// A picture in progress: the future the caller waits on and the timer
/// that completes it.
class _Capture {
  _Capture(this.shot, this.timer);

  final Completer<XFile> shot;
  final Timer timer;
}

/// The streams and the state of one camera. The streams stay open after
/// `dispose`: the controller waits on `first` of some of them, and a
/// closed stream would make that wait throw `No element`.
class _Camera {
  _Camera(this.description);

  /// The camera it opened, or the one a switch during a recording moved
  /// it to.
  CameraDescription description;
  final initialized = StreamController<CameraInitializedEvent>.broadcast();
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final closing = StreamController<CameraClosingEvent>.broadcast();

  /// The picture in progress, if any.
  _Capture? capture;

  /// The torch is on.
  bool torch = false;

  /// iPhone: the plugin no longer holds this camera.
  bool closed = false;

  /// Galaxy: created while another camera was open.
  bool openedOverAnother = false;

  /// Galaxy: the preview went empty.
  bool previewLost = false;

  /// Galaxy: `dispose` threw and the camera stayed open.
  bool releaseFailed = false;
}
