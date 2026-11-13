import 'dart:io';

import 'package:camera/camera.dart';
// Deprecated from Flutter 3.47 for package:material_ui, whose releases
// since 0.0.2 need Flutter 3.44; the floor is Flutter 3.38.1.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import 'camera_screen.dart';

/// The app: the home screen, and the camera screen over it.
///
/// The coordinator above the navigator keeps the `scopeKey` of the camera
/// screen: a camera screen opens the camera only once the one before it
/// has let the camera go.
class CameraApp extends StatelessWidget {
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) => const AsyncScopeCoordinator(
    child: MaterialApp(title: 'Camera', home: HomeScreen()),
  );
}

/// The home screen: it opens the camera screen and shows the last picture
/// or video the camera made.
///
/// It outlives the camera screen, so a picture taken just before the
/// camera screen left still reaches it.
class HomeScreen extends StatefulWidget {
  /// The camera screen the button opens; the tests put the same app on
  /// another controller through it.
  final Widget Function({required void Function(XFile file) onCaptured}) camera;

  const HomeScreen({super.key, this.camera = CameraScreen.new});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  XFile? _last;

  void _captured(XFile file) {
    if (mounted) setState(() => _last = file);
  }

  void _openCamera() {
    // The route lives as long as the screen; nothing waits for its result.
    // ignore: unawaited_futures
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Camera')),
          body: widget.camera(onCaptured: _captured),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _last;
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: last == null
            ? const Text('No picture yet.')
            : Image.file(
                File(last.path),
                key: const Key('last-shot'),
                errorBuilder: (context, error, stackTrace) => Text(last.name),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('open-camera'),
        onPressed: _openCamera,
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}
