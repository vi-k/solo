import 'dart:io';

import 'package:camera/camera.dart';
// Deprecated from Flutter 3.47 for package:material_ui, whose releases
// since 0.0.2 need Flutter 3.44; the floor is Flutter 3.38.1.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'camera_screen.dart';

/// The app: the home screen, and the camera screen over it.
class CameraApp extends StatelessWidget {
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'Camera', home: HomeScreen());
}

/// The home screen: it opens the camera screen and shows the last picture
/// or video the camera made.
///
/// It outlives the camera screen, so a picture taken just before the
/// camera screen left still reaches it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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
          body: CameraScreen(onCaptured: _captured),
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
