import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo_camera_example/camera_screen.dart';
import 'package:flutter_solo_camera_example/camera_session.dart';
import 'package:flutter_solo_camera_example/camera_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_camera_platform.dart';

void main() {
  late FakeCameraPlatform platform;
  late List<XFile> captured;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    captured = [];
  });

  /// Releases the camera of [session] and closes it, the way the camera
  /// screen does when it leaves.
  Future<void> finish(WidgetTester tester, CameraSession session) async {
    final released = session.release().done;
    await tester.pump(platform.disposeTime);
    expect(await released, isA<Done<void>>());
    await session.close();
  }

  testWidgets('open shows the preview', (tester) async {
    final session = CameraSession(onCaptured: captured.add);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CameraView(session: session),
      ),
    );
    session.open();
    await tester.pump(platform.openTime);

    expect(session.currentState, isA<Ready>());
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(platform.log.take(3), [
      'create back #1',
      'initialize #1 start',
      'initialize #1 end',
    ]);
    await tester.pumpWidget(const SizedBox());
    await finish(tester, session);
  });

  testWidgets('no camera on the device', (tester) async {
    platform.cameras = const [];
    final session = CameraSession(onCaptured: captured.add);
    session.open();
    await tester.pump();

    expect(session.currentState, isA<NoCamera>());
    expect(platform.openCameras, 0);
    await finish(tester, session);
  });

  testWidgets('a picture goes to onCaptured', (tester) async {
    final session = CameraSession(onCaptured: captured.add);
    session.open();
    await tester.pump(platform.openTime);
    final shot = session.takePicture().value;
    await tester.pump(platform.captureTime);

    expect((await shot)?.path, '/fake/picture-1.jpg');
    expect(captured.map((file) => file.path), ['/fake/picture-1.jpg']);
    expect(
      platform.log,
      containsAllInOrder(['capture #1 start', 'capture #1 end']),
    );
    await finish(tester, session);
  });

  testWidgets('release waits for the platform', (tester) async {
    final session = CameraSession(onCaptured: captured.add);
    session.open();
    await tester.pump(platform.openTime);
    final done = session.release().done;
    await tester.pump(platform.disposeTime);

    expect(await done, isA<Done<void>>());
    await session.close();
    expect(
      platform.log,
      containsAllInOrder(['dispose #1 start', 'dispose #1 end']),
    );
    expect(platform.log.where((l) => l == 'dispose #1 start'), hasLength(1));
    expect(platform.openCameras, 0);
    expect(session.currentState, isA<Closed>());
  });
}
