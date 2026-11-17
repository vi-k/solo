import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_solo_camera_example/camera_app.dart';
import 'package:flutter_solo_camera_example/camera_bloc.dart';
import 'package:flutter_solo_camera_example/camera_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/camera_cases.dart';
import 'support/fake_camera_platform.dart';

void main() {
  late FakeCameraPlatform platform;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
  });

  /// Pumps until [finder] finds a widget, as `appCases` does.
  Future<void> until(WidgetTester tester, Finder finder) async {
    for (var frame = 0; frame < 50 && finder.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      await letCloseEnd(tester);
    }
    expect(finder, findsOneWidget);
  }

  final shutter = find.byKey(const Key('shutter'));

  /// Leaves the camera screen and, while it is still leaving, picks
  /// [controller] on the switch and opens the camera screen again.
  Future<void> reopenOn(WidgetTester tester, String controller) async {
    await tester.pageBack();
    await tester.pump();
    await tester.tap(find.byKey(Key('controller-$controller')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('open-camera')));
    await tester.pumpAndSettle();
    await tester.pump(platform.disposeTime);
    await until(tester, shutter);
  }

  testWidgets('a screen on either controller waits for the one before it', (
    tester,
  ) async {
    await tester.pumpWidget(const CameraApp());
    await tester.tap(find.byKey(const Key('open-camera')));
    await tester.pumpAndSettle();
    await until(tester, shutter);
    // Solo is the default.
    expect(find.byType(CameraView), findsOneWidget);

    await reopenOn(tester, 'bloc');
    expect(find.byType(BlocCameraView), findsOneWidget);
    expect(
      platform.log,
      containsAllInOrder(['dispose #1 end', 'create back #2']),
    );
    expect(platform.openCameras, 1);

    await reopenOn(tester, 'solo');
    expect(find.byType(CameraView), findsOneWidget);
    expect(
      platform.log,
      containsAllInOrder(['dispose #2 end', 'create back #3']),
    );
    expect(platform.openCameras, 1);
    expect(platform.hasPicture(3), isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pump(platform.disposeTime);
    await letCloseEnd(tester);
    expect(platform.openCameras, 0);
  });
}
