import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_camera_platform.dart';

void main() {
  testWidgets('the fake logs an opening and a shot', (tester) async {
    final platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final cameras = await availableCameras();
    final camera = CameraController(cameras.first, ResolutionPreset.low);
    final opened = camera.initialize();
    await tester.pump(platform.openTime);
    await opened;
    final shot = camera.takePicture();
    await tester.pump(platform.captureTime);
    await shot;
    final closed = camera.dispose();
    await tester.pump(platform.disposeTime);
    await closed;
    expect(platform.log, [
      'create back #1',
      'initialize #1 start',
      'initialize #1 end',
      'capture #1 start',
      'capture #1 end',
      'dispose #1 start',
      'dispose #1 end',
    ]);
    expect(platform.openCameras, 0);
  });

  testWidgets('the fake logs the flash, a switch and a recording', (
    tester,
  ) async {
    final platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final cameras = await availableCameras();
    final camera = CameraController(cameras.first, ResolutionPreset.low);
    final opened = camera.initialize();
    await tester.pump(platform.openTime);
    await opened;
    await camera.setFlashMode(FlashMode.auto);
    final recording = camera.startVideoRecording();
    await tester.pump(platform.recordStartTime);
    await recording;
    final switched = camera.setDescription(cameras.last);
    await tester.pump(platform.switchTime);
    await switched;
    final stopped = camera.stopVideoRecording();
    await tester.pump(platform.stopTime);
    await stopped;
    expect(platform.log, [
      'create back #1',
      'initialize #1 start',
      'initialize #1 end',
      'flash #1 auto',
      'record #1 start',
      'record #1 started',
      'switch #1 front start',
      'switch #1 front end',
      'stop #1 start',
      'record #1 end',
    ]);
    final closed = camera.dispose();
    await tester.pump(platform.disposeTime);
    await closed;
  });

  testWidgets('the torch takes time, and the back camera alone has one', (
    tester,
  ) async {
    final platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final cameras = await availableCameras();
    final camera = CameraController(cameras.first, ResolutionPreset.low);
    final opened = camera.initialize();
    await tester.pump(platform.openTime);
    await opened;
    final lit = camera.setFlashMode(FlashMode.torch);
    await tester.pump(platform.torchTime);
    await lit;
    expect(platform.torchOn(1), isTrue);
    await camera.setFlashMode(FlashMode.auto);
    expect(platform.torchOn(1), isFalse);
    final switched = camera.setDescription(cameras.last);
    await tester.pump(platform.disposeTime);
    await tester.pump(platform.openTime);
    await switched;
    final front = expectLater(
      camera.setFlashMode(FlashMode.torch),
      throwsA(
        isA<CameraException>().having(
          (e) => e.description,
          'description',
          'Device does not support torch mode',
        ),
      ),
    );
    await tester.pump(platform.torchTime);
    await front;
    expect(platform.log.where((l) => l.startsWith('flash ')), [
      'flash #1 torch start',
      'flash #1 torch end',
      'flash #1 auto',
      'flash #2 torch start',
      'flash #2 torch failed',
    ]);
    expect(platform.torchOn(2), isFalse);
    final closed = camera.dispose();
    await tester.pump(platform.disposeTime);
    await closed;
  });

  testWidgets('a failed opening has no end line and reaches initialize', (
    tester,
  ) async {
    final platform = FakeCameraPlatform()
      ..failOpen = PlatformException(code: 'CameraAccessDenied');
    CameraPlatform.instance = platform;
    final cameras = await availableCameras();
    final camera = CameraController(cameras.first, ResolutionPreset.low);
    final opened = camera.initialize();
    final failure = expectLater(
      opened,
      throwsA(
        isA<CameraException>().having(
          (e) => e.code,
          'code',
          'CameraAccessDenied',
        ),
      ),
    );
    await tester.pump(platform.openTime);
    await failure;
    expect(platform.log, ['create back #1', 'initialize #1 start']);
    expect(platform.openCameras, 1);
  });

  testWidgets('the outside events reach a listener', (tester) async {
    final platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final cameras = await availableCameras();
    final camera = CameraController(cameras.first, ResolutionPreset.low);
    final opened = camera.initialize();
    await tester.pump(platform.openTime);
    await opened;
    final closing = platform.onCameraClosing(1).first;
    final errors = platform.onCameraError(1).first;
    platform.closeFromOutside(1);
    platform.failFromOutside(1, 'taken');
    expect((await closing).cameraId, 1);
    expect((await errors).description, 'taken');
    expect(camera.value.errorDescription, 'taken');
    expect(platform.log.last, 'camera #1 error');
    final closed = camera.dispose();
    await tester.pump(platform.disposeTime);
    await closed;
  });

  test('an unknown camera has quiet streams', () async {
    final platform = FakeCameraPlatform();
    expect(await platform.onCameraClosing(-1).isEmpty, isTrue);
    expect(await platform.onCameraError(-1).isEmpty, isTrue);
    expect(await platform.onCameraInitialized(-1).isEmpty, isTrue);
  });
}
