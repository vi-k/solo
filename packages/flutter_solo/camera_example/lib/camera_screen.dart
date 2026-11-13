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
/// goes on to the scope.
class CameraScreen extends StatelessWidget {
  /// Takes every picture and video the camera makes.
  final void Function(XFile file) onCaptured;

  const CameraScreen({super.key, required this.onCaptured});

  @override
  Widget build(BuildContext context) => AsyncDataScope<CameraSession>(
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
class CameraView extends StatelessWidget {
  final CameraSession session;

  const CameraView({super.key, required this.session});

  @override
  Widget build(BuildContext context) => SoloBuilder<CameraState>(
    solo: session,
    builder: (context, state, _) => switch (state) {
      Closed() => const SizedBox.expand(),
      Opening() => const Center(child: CircularProgressIndicator()),
      NoCamera() => const Center(child: Text('This device has no camera.')),
      Ready(:final camera, :final flash) => Column(
        children: [
          Expanded(child: Center(child: CameraPreview(camera))),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                key: const Key('flash'),
                onPressed: session.cycleFlash,
                icon: Icon(switch (flash) {
                  FlashMode.off => Icons.flash_off,
                  FlashMode.auto => Icons.flash_auto,
                  _ => Icons.flash_on,
                }),
              ),
              IconButton(
                key: const Key('shutter'),
                onPressed: session.takePicture,
                icon: const Icon(Icons.camera),
              ),
              const IconButton(
                key: Key('record'),
                onPressed: null,
                icon: Icon(Icons.videocam),
              ),
              IconButton(
                key: const Key('switch'),
                onPressed: session.switchCamera,
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
              onPressed: session.open,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      Denied(:final code) => Center(child: Text(code)),
    },
  );
}
