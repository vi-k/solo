/// The first attempts of `doc/device-app.md`: a screen on a bare
/// [CameraController], written the way the plugin's README and its example
/// lead to.
///
/// One widget per section, but for the torch. The buttons call the
/// controller at once, without a queue; the switch of the camera is `setDescription`; leaving the screen
/// is `dispose()` in `State.dispose`; the lifecycle follows "Handling
/// Lifecycle states" of the README; errors are the example's: a caught
/// [CameraException] and `value.errorDescription` are shown as text. Zoom
/// and exposure, which the example reads right after `initialize`, are left
/// out: this app has no controls for them.
///
/// The buttons have the keys `shutter`, `flash`, `switch`, `record` and
/// `stop`; the shown error has the key `error`.
///
/// The torch's attempt builds on the answer of the section before it: the
/// queue of `CameraSession`, where a tap of the torch is a job like a tap of
/// the flash.
library;

import 'package:camera/camera.dart';
// Deprecated from Flutter 3.47 for package:material_ui, whose releases
// since 0.0.2 need Flutter 3.44; the floor is Flutter 3.38.1.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo_camera_example/camera_state.dart';

/// Section 1, quick taps: the flash, the shutter and the switch of the
/// camera call the controller as soon as they are pressed.
class EagerButtons extends StatefulWidget {
  const EagerButtons({
    super.key,
    required this.cameras,
    required this.onCaptured,
  });

  final List<CameraDescription> cameras;
  final void Function(XFile file) onCaptured;

  @override
  State<EagerButtons> createState() => _EagerButtonsState();
}

class _EagerButtonsState extends State<EagerButtons> {
  late final CameraController camera = CameraController(
    widget.cameras.first,
    ResolutionPreset.medium,
  );
  String? error;

  @override
  void initState() {
    super.initState();
    camera.addListener(() {
      if (mounted) setState(() {});
    });
    camera.initialize().catchError(show);
  }

  @override
  void dispose() {
    camera.dispose();
    super.dispose();
  }

  Future<void> cycleFlash() async {
    final next = switch (camera.value.flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await camera.setFlashMode(next);
    } on CameraException catch (e) {
      show(e);
    }
  }

  Future<void> shoot() async {
    // A capture is already pending, do nothing.
    if (camera.value.isTakingPicture) return;
    try {
      widget.onCaptured(await camera.takePicture());
    } on CameraException catch (e) {
      show(e);
    }
  }

  Future<void> switchCamera() async {
    final next = widget.cameras.firstWhere(
      (c) => c.name != camera.value.description.name,
    );
    try {
      await camera.setDescription(next);
    } on CameraException catch (e) {
      show(e);
    }
  }

  void show(Object e) {
    if (!mounted) return;
    setState(() => error = describe(e));
  }

  @override
  Widget build(BuildContext context) => CameraLayout(
    camera: camera,
    error: error,
    buttons: {'flash': cycleFlash, 'shutter': shoot, 'switch': switchCamera},
  );
}

/// The torch: each tap is a job in the one queue of the buttons that flips
/// the torch, the way a tap of the flash moves the flash on.
final class FlippingTorch extends Solo<CameraState> {
  FlippingTorch() : super(const Closed());

  /// Opens the camera of [description], as `open()` of `CameraSession`
  /// does when nothing fails.
  Job<void> open(CameraDescription description) => enqueue<CameraState, void>((
    ctx,
  ) async {
    final camera = CameraController(description, ResolutionPreset.medium);
    await ctx.join(camera.initialize);
    ctx.emit(
      Ready(camera: camera, flash: camera.value.flashMode, recording: false),
    );
  });

  /// Takes a picture: a command that holds the queue for a while.
  Job<XFile> takePicture() =>
      enqueue<Ready, XFile>((ctx) => ctx.join(ctx.state.camera.takePicture));

  Job<void> toggleTorch() => enqueue<Ready, void>((ctx) async {
    final Ready(:camera, :flash, :recording, :torch) = ctx.state;
    await ctx.join(() => camera.setFlashMode(torch ? flash : FlashMode.torch));
    ctx.emit(
      Ready(camera: camera, flash: flash, recording: recording, torch: !torch),
    );
  });

  /// Lets the camera go, as `release()` of `CameraSession` does.
  Job<void> release() => enqueue<CameraState, void>((ctx) async {
    if (ctx.state case Ready(:final camera)) {
      await ctx.join(camera.dispose);
    }
    ctx.emit(const Closed());
  });
}

/// Section 2, switching the camera during a recording: `setDescription`
/// while the controller records.
class SwitchWhileRecording extends StatefulWidget {
  const SwitchWhileRecording({
    super.key,
    required this.cameras,
    required this.onCaptured,
  });

  final List<CameraDescription> cameras;
  final void Function(XFile file) onCaptured;

  @override
  State<SwitchWhileRecording> createState() => _SwitchWhileRecordingState();
}

class _SwitchWhileRecordingState extends State<SwitchWhileRecording> {
  late final CameraController camera = CameraController(
    widget.cameras.first,
    ResolutionPreset.medium,
  );
  String? error;

  @override
  void initState() {
    super.initState();
    camera.addListener(() {
      if (mounted) setState(() {});
    });
    camera.initialize().catchError(show);
  }

  @override
  void dispose() {
    camera.dispose();
    super.dispose();
  }

  Future<void> record() async {
    // A recording is already started, do nothing.
    if (camera.value.isRecordingVideo) return;
    try {
      await camera.startVideoRecording();
    } on CameraException catch (e) {
      show(e);
    }
  }

  Future<void> switchCamera() async {
    final next = widget.cameras.firstWhere(
      (c) => c.name != camera.value.description.name,
    );
    try {
      await camera.setDescription(next);
    } on CameraException catch (e) {
      show(e);
    }
  }

  Future<void> stop() async {
    if (!camera.value.isRecordingVideo) return;
    try {
      widget.onCaptured(await camera.stopVideoRecording());
    } on CameraException catch (e) {
      show(e);
    }
  }

  void show(Object e) {
    if (!mounted) return;
    setState(() => error = describe(e));
  }

  @override
  Widget build(BuildContext context) => CameraLayout(
    camera: camera,
    error: error,
    buttons: {'record': record, 'switch': switchCamera, 'stop': stop},
  );
}

/// Section 3, leaving the screen while the picture is not ready: the
/// screen releases its camera in `State.dispose` and hands the picture up
/// through [onCaptured], which outlives the screen.
class LeavingShutter extends StatefulWidget {
  const LeavingShutter({
    super.key,
    required this.cameras,
    required this.onCaptured,
  });

  final List<CameraDescription> cameras;
  final void Function(XFile file) onCaptured;

  @override
  State<LeavingShutter> createState() => _LeavingShutterState();
}

class _LeavingShutterState extends State<LeavingShutter> {
  late final CameraController camera = CameraController(
    widget.cameras.first,
    ResolutionPreset.medium,
  );
  String? error;

  @override
  void initState() {
    super.initState();
    camera.addListener(() {
      if (mounted) setState(() {});
    });
    camera.initialize().catchError(show);
  }

  @override
  void dispose() {
    camera.dispose();
    super.dispose();
  }

  Future<void> shoot() async {
    // A capture is already pending, do nothing.
    if (camera.value.isTakingPicture) return;
    try {
      widget.onCaptured(await camera.takePicture());
    } on CameraException catch (e) {
      show(e);
    }
  }

  void show(Object e) {
    if (!mounted) return;
    setState(() => error = describe(e));
  }

  @override
  Widget build(BuildContext context) =>
      CameraLayout(camera: camera, error: error, buttons: {'shutter': shoot});
}

/// Section 4, the app leaves the foreground during a recording: the
/// lifecycle of the README, which releases the camera on `inactive` and
/// makes a new controller on `resumed`.
class ReadmeLifecycle extends StatefulWidget {
  const ReadmeLifecycle({
    super.key,
    required this.cameras,
    required this.onCaptured,
  });

  final List<CameraDescription> cameras;
  final void Function(XFile file) onCaptured;

  @override
  State<ReadmeLifecycle> createState() => _ReadmeLifecycleState();
}

class _ReadmeLifecycleState extends State<ReadmeLifecycle>
    with WidgetsBindingObserver {
  CameraController? controller;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCameraController(widget.cameras.first);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCameraController(cameraController.description);
    }
  }

  Future<void> _initializeCameraController(
    CameraDescription cameraDescription,
  ) async {
    final cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
    );
    controller = cameraController;
    cameraController.addListener(() {
      if (mounted) setState(() {});
    });
    try {
      await cameraController.initialize();
    } on CameraException catch (e) {
      show(e);
    }
    if (mounted) setState(() {});
  }

  Future<void> record() async {
    final camera = controller;
    if (camera == null || camera.value.isRecordingVideo) return;
    try {
      await camera.startVideoRecording();
    } on CameraException catch (e) {
      show(e);
    }
  }

  Future<void> stop() async {
    final camera = controller;
    if (camera == null || !camera.value.isRecordingVideo) return;
    try {
      widget.onCaptured(await camera.stopVideoRecording());
    } on CameraException catch (e) {
      show(e);
    }
  }

  void show(Object e) {
    if (!mounted) return;
    setState(() => error = describe(e));
  }

  @override
  Widget build(BuildContext context) => CameraLayout(
    camera: controller,
    error: error,
    buttons: {'record': record, 'stop': stop},
  );
}

/// Section 5, losing the camera: the example's listener, which shows
/// `value.errorDescription` when the controller has one. The example shows
/// it in a snack bar; here it stays on the screen as the shown error.
class ErrorListener extends StatefulWidget {
  const ErrorListener({
    super.key,
    required this.cameras,
    required this.onCaptured,
  });

  final List<CameraDescription> cameras;
  final void Function(XFile file) onCaptured;

  @override
  State<ErrorListener> createState() => _ErrorListenerState();
}

class _ErrorListenerState extends State<ErrorListener> {
  late final CameraController camera = CameraController(
    widget.cameras.first,
    ResolutionPreset.medium,
  );
  String? error;

  @override
  void initState() {
    super.initState();
    camera.addListener(() {
      if (mounted) setState(() {});
      if (camera.value.hasError) {
        show('Camera error ${camera.value.errorDescription}');
      }
    });
    camera.initialize().catchError(show);
  }

  @override
  void dispose() {
    camera.dispose();
    super.dispose();
  }

  Future<void> shoot() async {
    // A capture is already pending, do nothing.
    if (camera.value.isTakingPicture) return;
    try {
      widget.onCaptured(await camera.takePicture());
    } on CameraException catch (e) {
      show(e);
    }
  }

  void show(Object e) {
    if (!mounted) return;
    setState(() => error = describe(e));
  }

  @override
  Widget build(BuildContext context) =>
      CameraLayout(camera: camera, error: error, buttons: {'shutter': shoot});
}

/// Section 6, no permission: the example's catch around `initialize`, one
/// message for each code the README lists.
class PermissionMessages extends StatefulWidget {
  const PermissionMessages({
    super.key,
    required this.cameras,
    required this.onCaptured,
  });

  final List<CameraDescription> cameras;
  final void Function(XFile file) onCaptured;

  @override
  State<PermissionMessages> createState() => _PermissionMessagesState();
}

class _PermissionMessagesState extends State<PermissionMessages> {
  late final CameraController camera = CameraController(
    widget.cameras.first,
    ResolutionPreset.medium,
  );
  String? error;

  @override
  void initState() {
    super.initState();
    camera.addListener(() {
      if (mounted) setState(() {});
    });
    open();
  }

  @override
  void dispose() {
    camera.dispose();
    super.dispose();
  }

  Future<void> open() async {
    try {
      await camera.initialize();
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          show('You have denied camera access.');
        case 'CameraAccessDeniedWithoutPrompt':
          // iOS only
          show('Please go to Settings app to enable camera access.');
        case 'CameraAccessRestricted':
          // iOS only
          show('Camera access is restricted.');
        case 'AudioAccessDenied':
          show('You have denied audio access.');
        case 'AudioAccessDeniedWithoutPrompt':
          // iOS only
          show('Please go to Settings app to enable audio access.');
        case 'AudioAccessRestricted':
          // iOS only
          show('Audio access is restricted.');
        default:
          show(e);
      }
    }
  }

  void show(Object e) {
    if (!mounted) return;
    setState(() => error = describe(e));
  }

  @override
  Widget build(BuildContext context) =>
      CameraLayout(camera: camera, error: error, buttons: const {});
}

/// The text a screen shows for [e]: the code and the description of a
/// [CameraException], as the example's `_showCameraException` does.
String describe(Object e) => switch (e) {
  CameraException(:final code, :final description) => '$code: $description',
  _ => '$e',
};

/// The preview, the last error over the buttons, and a row of buttons
/// keyed by their names.
class CameraLayout extends StatelessWidget {
  const CameraLayout({
    super.key,
    required this.camera,
    required this.error,
    required this.buttons,
  });

  final CameraController? camera;
  final String? error;
  final Map<String, VoidCallback> buttons;

  @override
  Widget build(BuildContext context) {
    final camera = this.camera;
    final error = this.error;
    return Column(
      children: [
        Expanded(
          child: camera != null && camera.value.isInitialized
              ? CameraPreview(camera)
              : const SizedBox.expand(),
        ),
        if (error != null) Text(error, key: const Key('error')),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final MapEntry(:key, :value) in buttons.entries)
              TextButton(key: Key(key), onPressed: value, child: Text(key)),
          ],
        ),
      ],
    );
  }
}
