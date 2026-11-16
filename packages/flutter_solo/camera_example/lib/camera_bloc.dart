/// The camera screen on bloc: the same states, the same buttons and the
/// same platform as `CameraSession` and `CameraScreen`, with bloc's own
/// means in place of solo's.
///
/// The switch of the home screen opens the camera screen on either.
library;

import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
// Deprecated from Flutter 3.47 for package:material_ui, whose releases
// since 0.0.2 need Flutter 3.44; the floor is Flutter 3.38.1.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scopo/scopo.dart';

import 'camera_lights.dart';
import 'camera_screen.dart';
import 'camera_state.dart';

sealed class CameraEvent {
  const CameraEvent();
}

/// A command of the screen. The commands share one handler and run one at
/// a time, in the order they came.
sealed class CameraCommand extends CameraEvent {
  const CameraCommand();
}

final class OpenCamera extends CameraCommand {
  const OpenCamera();
}

final class TakePicture extends CameraCommand {
  const TakePicture();
}

final class CycleFlash extends CameraCommand {
  const CycleFlash();
}

final class SwitchCamera extends CameraCommand {
  const SwitchCamera();
}

/// A tap of the torch button. [CameraBloc.add] turns it into a [SetTorch]
/// with the torch the tap asks for: the opposite of the tap before it, or
/// of the torch when no tap waits.
final class ToggleTorch extends CameraEvent {
  const ToggleTorch();
}

/// Turns the torch [on], for the tap numbered [tap]; a later tap
/// supersedes it.
final class SetTorch extends CameraCommand {
  final bool on;
  final int tap;

  const SetTorch(this.on, this.tap);
}

final class StartRecording extends CameraCommand {
  const StartRecording();
}

final class StopRecording extends CameraCommand {
  const StopRecording();
}

final class Suspend extends CameraCommand {
  const Suspend();
}

final class Resume extends CameraCommand {
  const Resume();
}

/// Stops a recording and frees the camera on the platform; [done]
/// completes once the platform has, for the owner to wait on.
final class Release extends CameraCommand {
  final Completer<void> done;

  Release(this.done);
}

/// Frees a camera the platform said is lost, after the command under way.
final class LetGo extends CameraCommand {
  const LetGo();
}

/// The platform says the open camera failed.
final class CameraLost extends CameraEvent {
  final String description;

  const CameraLost(this.description);
}

/// The controller of the camera screen on bloc: it owns the plugin's
/// [CameraController], and its commands run one at a time.
class CameraBloc extends Bloc<CameraEvent, CameraState> {
  /// Takes every picture and video the camera makes.
  final void Function(XFile file) onCaptured;

  CameraBloc({required this.onCaptured}) : super(const Closed()) {
    // One handler for every command: a switch waits for the shot under way,
    // a stop for the switch, and a release for whatever runs.
    on<CameraCommand>(_run, transformer: sequential());
    // A failure has a handler of its own, with the concurrent transformer:
    // it shows at once, not after the command under way.
    on<CameraLost>(_lose);
  }

  /// The camera the platform holds for this bloc, lost or not: a [Release]
  /// that runs after a loss still finds it, before the [LetGo] of the loss.
  CameraController? _camera;

  /// The platform lost [_camera]: [_letGo] stops its recording first.
  bool _lost = false;

  /// What the cameras of the phone can light, as the platform said at the
  /// last [OpenCamera]: the screen shows the buttons of the flash and the
  /// torch by it.
  CameraLights get lights => _lights;
  CameraLights _lights = CameraLights.none;

  /// The camera [Suspend] let go, for [Resume] to open again.
  CameraDescription? _suspended;

  /// The errors the platform reports for the open camera.
  StreamSubscription<CameraErrorEvent>? _errors;

  /// A [TakePicture] waits in the queue or runs: a tap during a shot is
  /// dropped. The flag is set in [add], since `sequential()` reads an event
  /// only when the one before it is over.
  bool _shooting = false;

  /// The torch the latest [ToggleTorch] asked for, until its [SetTorch]
  /// has run, and the number of the latest tap.
  bool? _torchAsked;
  int _torchTaps = 0;

  @override
  void add(CameraEvent event) {
    if (event is TakePicture) {
      if (_shooting) return;
      _shooting = true;
    }
    if (event is ToggleTorch) {
      final lit = switch (state) {
        Ready(:final torch) => torch,
        _ => false,
      };
      final on = !(_torchAsked ?? lit);
      _torchAsked = on;
      super.add(SetTorch(on, ++_torchTaps));
      return;
    }
    super.add(event);
  }

  /// Stops a recording and frees the camera; the future ends once the
  /// platform has.
  Future<void> release() {
    final release = Release(Completer());
    add(release);
    return release.done.future;
  }

  /// Stops listening to the platform: an error after [close] would add an
  /// event to a closed bloc, which throws.
  @override
  Future<void> close() {
    unawaited(_errors?.cancel());
    return super.close();
  }

  Future<void> _run(CameraCommand command, Emitter<CameraState> emit) async {
    try {
      switch (command) {
        case OpenCamera():
          await _open(emit);
        case TakePicture():
          await _takePicture();
        case CycleFlash():
          await _cycleFlash(emit);
        case SetTorch():
          await _setTorch(command, emit);
        case SwitchCamera():
          await _switchCamera(emit);
        case StartRecording():
          await _startRecording(emit);
        case StopRecording():
          await _stopRecording(emit);
        case Suspend():
          await _suspend(emit);
        case Resume():
          await _resume(emit);
        case Release(:final done):
          try {
            await _letGo(leaving: true);
            emit(const Closed());
            done.complete();
          } catch (error, stackTrace) {
            done.completeError(error, stackTrace);
          }
        case LetGo():
          await _letGo();
      }
    } finally {
      if (command is TakePicture) _shooting = false;
      if (command is SetTorch && command.tap == _torchTaps) {
        _torchAsked = null;
      }
    }
  }

  Future<void> _open(Emitter<CameraState> emit) async {
    if (state is Ready) return;
    emit(const Opening());
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      emit(const NoCamera());
      return;
    }
    _lights = await CameraLights.ask(cameras);
    await _initialize(cameras.first, emit);
  }

  // Each command on a ready camera keeps the state it started from and
  // looks again after every await: a loss changes the state in between,
  // and a command that goes on would put the lost camera back on screen.

  Future<void> _takePicture() async {
    final ready = state;
    if (ready is! Ready) return;
    final file = await ready.camera.takePicture();
    if (state != ready) return;
    onCaptured(file);
  }

  /// While the torch is on, the mode waits in the state: the platform has
  /// one setting for the flash and the torch. On a camera without a flash
  /// the mode waits as well, and a switch sets it on a camera with one.
  Future<void> _cycleFlash(Emitter<CameraState> emit) async {
    final ready = state;
    if (ready is! Ready) return;
    final Ready(:camera, :flash, :recording, :torch) = ready;
    final next = switch (flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    if (!torch && lights.flash(camera.description)) {
      await camera.setFlashMode(next);
    }
    if (state != ready) return;
    emit(
      Ready(camera: camera, flash: next, recording: recording, torch: torch),
    );
  }

  /// A [SetTorch] that a later tap superseded calls nothing, and nor does
  /// one that finds the torch where it asks.
  Future<void> _setTorch(SetTorch command, Emitter<CameraState> emit) async {
    final ready = state;
    if (command.tap != _torchTaps || ready is! Ready) return;
    final Ready(:camera, :flash, :recording, :torch) = ready;
    if (command.on == torch || !lights.torch(camera.description)) return;
    await camera.setFlashMode(command.on ? FlashMode.torch : flash);
    if (state != ready) return;
    emit(
      Ready(
        camera: camera,
        flash: flash,
        recording: recording,
        torch: command.on,
      ),
    );
  }

  /// Without a recording the plugin releases the camera before it opens the
  /// next one, so a switch that fails is [Broken]; during a recording the
  /// camera goes on recording, and the failure goes on to the zone. A
  /// camera without a flash gets no mode of the flash.
  Future<void> _switchCamera(Emitter<CameraState> emit) async {
    var ready = state;
    if (ready is! Ready) return;
    final cameras = await availableCameras();
    if (state != ready) return;
    final Ready(:camera, :flash, :recording, :torch) = ready;
    final at = cameras.indexWhere((c) => c.name == camera.description.name);
    final next = cameras[(at + 1) % cameras.length];
    // A lit torch goes out while its camera is open (see [_putTorchOut]);
    // during a recording a camera with a torch keeps it.
    if (torch && !(recording && lights.torch(next))) {
      await camera.setFlashMode(flash);
      if (state != ready) return;
      ready = Ready(camera: camera, flash: flash, recording: recording);
      emit(ready);
    }
    try {
      await camera.setDescription(next);
    } on CameraException catch (error) {
      if (state != ready) return;
      if (recording) rethrow;
      emit(Broken(error));
      await _letGo();
      return;
    }
    if (state != ready) return;
    _watch(camera);
    // The camera the plugin opens starts with a flash mode of its own.
    if (recording) return;
    if (torch && lights.torch(next)) {
      await camera.setFlashMode(FlashMode.torch);
      if (state != ready) return;
      emit(Ready(camera: camera, flash: flash, recording: false, torch: true));
    } else if (lights.flash(next)) {
      await camera.setFlashMode(flash);
    }
  }

  Future<void> _startRecording(Emitter<CameraState> emit) async {
    final ready = state;
    if (ready is! Ready || ready.recording) return;
    await ready.camera.startVideoRecording();
    if (state != ready) return;
    emit(
      Ready(
        camera: ready.camera,
        flash: ready.flash,
        recording: true,
        torch: ready.torch,
      ),
    );
  }

  /// A stop that fails leaves the plugin's controller recording for good,
  /// so the camera is [Broken] and let go. A stop the loss of the camera
  /// cuts short still hands its video on.
  Future<void> _stopRecording(Emitter<CameraState> emit) async {
    final ready = state;
    if (ready is! Ready || !ready.recording) return;
    final XFile file;
    try {
      file = await ready.camera.stopVideoRecording();
    } on CameraException catch (error) {
      if (state != ready) return;
      emit(Broken(error));
      await _letGo();
      return;
    }
    if (state != ready) {
      onCaptured(file);
      return;
    }
    emit(
      Ready(
        camera: ready.camera,
        flash: ready.flash,
        recording: false,
        torch: ready.torch,
      ),
    );
    onCaptured(file);
  }

  /// The state is [Closed] before the release starts: a preview built on a
  /// controller being disposed throws. The stop is that of a release, and a
  /// lit torch goes out after it unless the stop ran out of time. An error
  /// the stop does not catch still lets the camera go, and goes on to the
  /// zone.
  Future<void> _suspend(Emitter<CameraState> emit) async {
    final ready = state;
    if (ready is! Ready) return;
    _suspended = ready.camera.description;
    try {
      final stopped =
          !ready.recording || await stopBeforeRelease(ready.camera, onCaptured);
      if (stopped) await _putTorchOut();
    } finally {
      emit(const Closed());
      await _letGo();
    }
  }

  Future<void> _resume(Emitter<CameraState> emit) async {
    final description = _suspended;
    if (description == null) return;
    _suspended = null;
    emit(const Opening());
    await _initialize(description, emit);
  }

  /// A permission the app does not have is [Denied], and any other failure
  /// is [Broken]. A camera the platform has created is let go; a create
  /// that failed leaves the plugin's controller on [_noCamera].
  Future<void> _initialize(
    CameraDescription description,
    Emitter<CameraState> emit,
  ) async {
    final camera = CameraController(description, ResolutionPreset.medium);
    try {
      await camera.initialize();
    } on CameraException catch (error) {
      final code = error.code;
      emit(_denials.contains(code) ? Denied(code) : Broken(error));
      if (camera.cameraId != _noCamera) await camera.dispose();
      return;
    }
    _camera = camera;
    _watch(camera);
    emit(
      Ready(camera: camera, flash: camera.value.flashMode, recording: false),
    );
  }

  /// Follows the errors of [camera] in place of those of the camera before
  /// it: the id changes with every opening and with a switch without a
  /// recording.
  void _watch(CameraController camera) {
    unawaited(_errors?.cancel());
    _errors = CameraPlatform.instance
        .onCameraError(camera.cameraId)
        .listen((event) => add(CameraLost(event.description)));
  }

  /// The state shows the failure at once; the camera is let go after the
  /// command under way, which may still be using it.
  void _lose(CameraLost event, Emitter<CameraState> emit) {
    if (state is! Ready) return;
    emit(Broken(event.description));
    _lost = true;
    add(const LetGo());
  }

  /// Puts a lit torch out while its camera is open:
  /// `camera_android_camerax` keeps the torch on for the platform rather
  /// than for a camera, and would take the next camera's torch as lit. A
  /// camera the platform lost goes without that.
  Future<void> _putTorchOut() async {
    if (state case Ready(:final camera, :final flash, torch: true)) {
      await camera.setFlashMode(flash);
    }
  }

  /// Frees the camera the platform holds for this bloc, if there is one.
  ///
  /// A camera that records stops first when it is lost or the screen is
  /// [leaving], and its video goes to [onCaptured]: released under a
  /// recording, the Galaxy's camera went on recording sound into the file.
  /// A screen that leaves puts a lit torch out after that, unless the stop
  /// ran out of time. A stop that throws still lets the camera go.
  Future<void> _letGo({bool leaving = false}) async {
    final camera = _camera;
    final lost = _lost;
    _camera = null;
    _lost = false;
    if (camera == null) return;
    try {
      var stopped = true;
      if ((lost || leaving) && camera.value.isRecordingVideo) {
        stopped = await stopBeforeRelease(camera, onCaptured);
      }
      if (leaving && stopped) await _putTorchOut();
    } finally {
      await camera.dispose();
    }
  }
}

/// The `cameraId` of the plugin's controller until the platform has
/// created its camera.
const _noCamera = -1;

/// The codes of the plugin's `CameraException` for a permission the app
/// does not have, as its README lists them.
const _denials = {
  'CameraAccessDenied',
  'CameraAccessDeniedWithoutPrompt',
  'CameraAccessRestricted',
  'AudioAccessDenied',
  'AudioAccessDeniedWithoutPrompt',
  'AudioAccessRestricted',
};

/// The camera screen on bloc: a scope that owns a [CameraBloc] for as long
/// as the screen is there.
///
/// `BlocProvider` closes the bloc it made without waiting, and knows
/// nothing of the screen before it: the scope of scopo waits for the
/// release and holds the next screen on the `scopeKey` of [CameraScreen],
/// so a camera screen on either controller waits for the one before it.
class BlocCameraScreen extends StatelessWidget {
  /// Takes every picture and video the camera makes.
  final void Function(XFile file) onCaptured;

  const BlocCameraScreen({super.key, required this.onCaptured});

  @override
  Widget build(BuildContext context) => AsyncDataScope<CameraBloc>(
    scopeKey: CameraScreen,
    scopeKeyTimeout: CameraScreen.releaseTimeout,
    disposeScopeTimeout: CameraScreen.releaseTimeout,
    initData: (context, ctx) async =>
        CameraBloc(onCaptured: onCaptured)..add(const OpenCamera()),
    disposeData: (bloc) async {
      try {
        await bloc.release();
      } finally {
        await bloc.close();
      }
    },
    progressBuilder: (context, progress) => const SizedBox.expand(),
    errorBuilder: (context, error, stackTrace, progress) =>
        Center(child: Text('$error')),
    builder: (context, bloc) =>
        BlocProvider.value(value: bloc, child: const BlocCameraView()),
  );
}

/// What the camera screen shows for each state of the [CameraBloc] above
/// it.
///
/// While it is there, it lets the camera go when the app is hidden and
/// opens it again when the app is shown.
class BlocCameraView extends StatefulWidget {
  const BlocCameraView({super.key});

  @override
  State<BlocCameraView> createState() => _BlocCameraViewState();
}

class _BlocCameraViewState extends State<BlocCameraView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => context.read<CameraBloc>().add(const Suspend()),
      onShow: () => context.read<CameraBloc>().add(const Resume()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<CameraBloc>();
    return BlocBuilder<CameraBloc, CameraState>(
      builder: (context, state) => switch (state) {
        Closed() => const SizedBox.expand(),
        Opening() => const Center(child: CircularProgressIndicator()),
        NoCamera() => const Center(child: Text('This device has no camera.')),
        Ready(:final camera, :final flash, :final recording, :final torch) =>
          Column(
            children: [
              Expanded(child: Center(child: CameraPreview(camera))),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // A switch changes the camera and leaves the state: the
                  // plugin's controller says which camera it holds.
                  ValueListenableBuilder<CameraValue>(
                    valueListenable: camera,
                    builder: (context, value, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (bloc.lights.flash(value.description))
                          IconButton(
                            key: const Key('flash'),
                            onPressed: () => bloc.add(const CycleFlash()),
                            icon: Icon(switch (flash) {
                              FlashMode.off => Icons.flash_off,
                              FlashMode.auto => Icons.flash_auto,
                              _ => Icons.flash_on,
                            }),
                          ),
                        if (bloc.lights.torch(value.description))
                          IconButton(
                            key: const Key('torch'),
                            onPressed: () => bloc.add(const ToggleTorch()),
                            icon: Icon(
                              torch
                                  ? Icons.flashlight_on
                                  : Icons.flashlight_off,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('shutter'),
                    onPressed: () => bloc.add(const TakePicture()),
                    icon: const Icon(Icons.camera),
                  ),
                  IconButton(
                    key: const Key('record'),
                    onPressed: () => bloc.add(
                      recording
                          ? const StopRecording()
                          : const StartRecording(),
                    ),
                    icon: Icon(recording ? Icons.stop : Icons.videocam),
                  ),
                  IconButton(
                    key: const Key('switch'),
                    onPressed: () => bloc.add(const SwitchCamera()),
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
                onPressed: () => bloc.add(const OpenCamera()),
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
                  onPressed: () => bloc.add(const OpenCamera()),
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      },
    );
  }
}

/// What the screen asks for the [code] of a denial, as `CameraView` does.
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
