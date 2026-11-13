import 'package:camera/camera.dart';
// Deprecated from Flutter 3.47 for package:material_ui, whose releases
// since 0.0.2 need Flutter 3.44; the floor is Flutter 3.38.1.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:scopo/scopo.dart';

import 'camera_session.dart';
import 'camera_state.dart';

/// The camera screen: a scope that owns a [CameraSession] for as long as
/// the screen is there.
///
/// The scope opens the camera when it comes in. When it leaves, it waits
/// for the camera to be released on the platform, and closes the session
/// after that; a release that failed is closed all the same, and its error
/// goes on to the scope. A camera screen opened again waits on the
/// `scopeKey` for that release before it opens the camera; the key needs
/// the [AsyncScopeCoordinator] that `CameraApp` puts above the navigator.
class CameraScreen extends StatelessWidget {
  /// How long a camera screen waits for the one before it to let the
  /// camera go, and how long a leaving one waits for its release.
  ///
  /// The release waits in the queue behind the command under way: a
  /// picture takes up to 3.4 s on a Galaxy A55, and a recording up to
  /// 2.5 s to start on an iPhone 13 mini. With scopo's default of 3 s
  /// either wait could end first and hand the camera on unreleased.
  static const releaseTimeout = Duration(seconds: 10);

  /// Takes every picture and video the camera makes.
  final void Function(XFile file) onCaptured;

  const CameraScreen({super.key, required this.onCaptured});

  @override
  Widget build(BuildContext context) => AsyncDataScope<CameraSession>(
    scopeKey: CameraScreen,
    scopeKeyTimeout: releaseTimeout,
    disposeScopeTimeout: releaseTimeout,
    initData: (context, ctx) async =>
        CameraSession(onCaptured: onCaptured)..open(),
    disposeData: (session) async {
      try {
        await session.release().value;
      } finally {
        await session.close();
      }
    },
    progressBuilder: (context, progress) => const SizedBox.expand(),
    errorBuilder: (context, error, stackTrace, progress) =>
        Center(child: Text('$error')),
    builder: (context, session) => CameraView(session: session),
  );
}

/// What the camera screen shows for each state of [session].
///
/// While it is there, it lets the camera go when the app is hidden and
/// opens it again when the app is shown.
class CameraView extends StatefulWidget {
  final CameraSession session;

  const CameraView({super.key, required this.session});

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => widget.session.suspend(),
      onShow: () => widget.session.resume(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SoloBuilder<CameraState>(
    solo: widget.session,
    builder: (context, state, _) => switch (state) {
      Closed() => const SizedBox.expand(),
      Opening() => const Center(child: CircularProgressIndicator()),
      NoCamera() => const Center(child: Text('This device has no camera.')),
      Ready(:final camera, :final flash, :final recording) => Column(
        children: [
          Expanded(child: Center(child: CameraPreview(camera))),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                key: const Key('flash'),
                onPressed: widget.session.cycleFlash,
                icon: Icon(switch (flash) {
                  FlashMode.off => Icons.flash_off,
                  FlashMode.auto => Icons.flash_auto,
                  _ => Icons.flash_on,
                }),
              ),
              IconButton(
                key: const Key('shutter'),
                onPressed: widget.session.takePicture,
                icon: const Icon(Icons.camera),
              ),
              IconButton(
                key: const Key('record'),
                onPressed: recording
                    ? widget.session.stopRecording
                    : widget.session.startRecording,
                icon: Icon(recording ? Icons.stop : Icons.videocam),
              ),
              IconButton(
                key: const Key('switch'),
                onPressed: widget.session.switchCamera,
                icon: const Icon(Icons.cameraswitch),
              ),
            ],
          ),
        ],
      ),
      Broken(:final error) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('The camera failed: $error'),
            TextButton(
              key: const Key('retry'),
              onPressed: widget.session.open,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      Denied(:final code) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_denial(code)),
            if (code.endsWith('Denied'))
              TextButton(
                key: const Key('retry'),
                onPressed: widget.session.open,
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    },
  );
}

/// What the screen asks for the [code] of a denial: the device to allow,
/// and where the user can allow it.
String _denial(String code) {
  final device = code.startsWith('Audio') ? 'microphone' : 'camera';
  if (code.endsWith('WithoutPrompt')) {
    return 'Allow the app to use the $device in Settings.';
  }
  if (code.endsWith('Restricted')) {
    return 'The policy of this device does not let the app use the $device.';
  }
  return 'Allow the app to use the $device.';
}
