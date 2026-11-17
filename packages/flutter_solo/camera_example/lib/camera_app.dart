import 'dart:io';

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scopo/scopo.dart';

import 'camera_bloc.dart';
import 'camera_screen.dart';

/// The app: the home screen, and the camera screen over it.
///
/// The coordinator above the navigator keeps the `scopeKey` of the camera
/// screen: a camera screen opens the camera only once the one before it
/// has let the camera go, whichever controller either of them runs on.
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
/// camera screen left still reaches it. Its switch picks the controller of
/// the camera screen it opens: [CameraScreen] on solo, the default, or
/// [BlocCameraScreen] on bloc.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// The controllers the switch of the home screen picks from.
enum _Controller { solo, bloc }

class _HomeScreenState extends State<HomeScreen> {
  XFile? _last;
  _Controller _controller = _Controller.solo;

  void _captured(XFile file) {
    if (mounted) setState(() => _last = file);
  }

  void _openCamera() {
    // Picked on the tap: the route may build its page again after the
    // switch has moved.
    final camera = switch (_controller) {
      _Controller.solo => CameraScreen(onCaptured: _captured),
      _Controller.bloc => BlocCameraScreen(onCaptured: _captured),
    };
    // The route lives as long as the screen; nothing waits for its result.
    // ignore: unawaited_futures
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Camera')),
          body: camera,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _last;
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<_Controller>(
              segments: [
                for (final controller in _Controller.values)
                  ButtonSegment(
                    value: controller,
                    label: Text(
                      controller.name,
                      key: Key('controller-${controller.name}'),
                    ),
                  ),
              ],
              selected: {_controller},
              onSelectionChanged: (selected) =>
                  setState(() => _controller = selected.single),
            ),
          ),
          Expanded(
            child: Center(
              child: last == null
                  ? const Text('No picture yet.')
                  : Image.file(
                      File(last.path),
                      key: const Key('last-shot'),
                      errorBuilder: (context, error, stackTrace) =>
                          Text(last.name),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('open-camera'),
        onPressed: _openCamera,
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}
