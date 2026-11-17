import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_solo_camera_example/camera_bloc.dart';
import 'package:flutter_solo_camera_example/camera_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/camera_cases.dart';
import 'support/fake_camera_platform.dart';

/// Drives a [CameraBloc] through the cases of the camera screen.
final class BlocDriver implements CameraDriver {
  BlocDriver(
    void Function(XFile file) onCaptured, {
    void Function(Object error)? onUnanswered,
  }) : bloc = onUnanswered == null
           ? CameraBloc(onCaptured: onCaptured)
           // The handlers run in the zone the bloc is made in, and an error
           // of a handler goes on to that zone.
           : runZonedGuarded(
               () => CameraBloc(onCaptured: onCaptured),
               (error, stackTrace) => onUnanswered(error),
             )!;

  final CameraBloc bloc;

  @override
  CameraState get currentState => bloc.state;

  @override
  Widget get view =>
      BlocProvider.value(value: bloc, child: const BlocCameraView());

  @override
  void open() => bloc.add(const OpenCamera());

  @override
  void takePicture() => bloc.add(const TakePicture());

  @override
  void cycleFlash() => bloc.add(const CycleFlash());

  @override
  void toggleTorch() => bloc.add(const ToggleTorch());

  @override
  void switchCamera() => bloc.add(const SwitchCamera());

  @override
  void startRecording() => bloc.add(const StartRecording());

  @override
  void stopRecording() => bloc.add(const StopRecording());

  @override
  Future<void> release() async {
    await bloc.release();
    await bloc.close();
  }

  @override
  Future<void> close() => bloc.close();

  /// The bloc runs the event of the release to its end before it closes.
  @override
  Matcher get releaseCutByClose => isNull;
}

void main() {
  group('the camera screen', () => controllerCases(BlocDriver.new));
  group('the app', () => appCases('bloc'));

  testWidgets('an event after close changes nothing', (tester) async {
    final platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final bloc = CameraBloc(onCaptured: (file) {})..add(const OpenCamera());
    await tester.pump(platform.openTime);
    // Closed without a release, as after a release that failed: the camera
    // is still there, and the state the bloc stops at stays.
    unawaited(bloc.close());
    await tester.pump();
    platform.failFromOutside(1, 'camera error');
    await tester.pump();
    await tester.pump();

    expect(bloc.state, isA<Ready>());
    expect(tester.takeException(), isNull);
    final camera = (bloc.state as Ready).camera;
    final released = camera.dispose();
    await tester.pump(platform.disposeTime);
    await released;
  });
}
