import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_solo_camera_example/camera_app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_camera_platform.dart';

void main() {
  late FakeCameraPlatform platform;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
  });

  /// Pumps until [finder] finds a widget: a scope of scopo builds its ready
  /// branch some frames after its initialization ends.
  Future<void> until(WidgetTester tester, Finder finder) async {
    for (var frame = 0; frame < 50 && finder.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsOneWidget);
  }

  /// Opens the camera screen from the home screen.
  Future<void> openCamera(WidgetTester tester) async {
    await tester.pumpWidget(const CameraApp());
    await tester.tap(find.byKey(const Key('open-camera')));
    await tester.pumpAndSettle();
  }

  /// Goes back to the home screen and lets the camera go.
  Future<void> goBack(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pump(platform.disposeTime);
  }

  testWidgets('the home screen shows the last shot', (tester) async {
    await openCamera(tester);
    await until(tester, find.byKey(const Key('shutter')));
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pump(platform.captureTime);
    await goBack(tester);

    expect(find.byKey(const Key('last-shot')), findsOneWidget);
    expect(platform.openCameras, 0);
  });

  testWidgets('a device without a camera says so', (tester) async {
    platform.cameras = const [];
    await openCamera(tester);
    await until(tester, find.textContaining('no camera'));

    expect(find.byKey(const Key('shutter')), findsNothing);
    await goBack(tester);
    expect(platform.openCameras, 0);
  });
}
