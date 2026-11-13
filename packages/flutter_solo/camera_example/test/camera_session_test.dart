import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo_camera_example/camera_screen.dart';
import 'package:flutter_solo_camera_example/camera_session.dart';
import 'package:flutter_solo_camera_example/camera_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_camera_platform.dart';
import 'support/journal.dart';

void main() {
  late FakeCameraPlatform platform;
  late List<XFile> captured;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    captured = [];
  });
  tearDown(() => Solo.observer = null);

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

  group('rapid taps', () {
    testWidgets('flash taps apply in order', (tester) async {
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      // The plugin's controller starts with the flash on auto.
      expect((session.currentState as Ready).flash, FlashMode.auto);
      session
        ..cycleFlash()
        ..cycleFlash()
        ..cycleFlash();
      await tester.pump();

      expect(platform.log.where((l) => l.startsWith('flash')), [
        'flash #1 always',
        'flash #1 off',
        'flash #1 auto',
      ]);
      expect((session.currentState as Ready).flash, FlashMode.auto);
      await finish(tester, session);
    });

    testWidgets('a shot during a shot is dropped', (tester) async {
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      final first = session.takePicture().value;
      final second = session.takePicture().value;
      await tester.pump(platform.captureTime);

      expect(platform.log.where((l) => l == 'capture #1 start'), hasLength(1));
      expect(captured, hasLength(1));
      // The second tap gets the shot of the first, not a cancellation.
      expect((await first)?.path, '/fake/picture-1.jpg');
      expect((await second)?.path, '/fake/picture-1.jpg');
      await finish(tester, session);
    });

    testWidgets('a switch during a shot waits for it', (tester) async {
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      session
        ..takePicture()
        ..switchCamera();
      await tester.pump(platform.captureTime);
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);

      expect(
        platform.log,
        containsAllInOrder([
          'capture #1 end',
          'dispose #1 start',
          'dispose #1 end',
          'create front #2',
          'initialize #2 end',
        ]),
      );
      expect(platform.log, isNot(contains('capture #1 failed')));
      expect(captured, hasLength(1));
      await finish(tester, session);
    });

    testWidgets('a tap while the camera opens waits for it', (tester) async {
      final session = CameraSession(onCaptured: captured.add);
      session
        ..open()
        ..takePicture();
      await tester.pump(platform.openTime);
      await tester.pump(platform.captureTime);

      expect(
        platform.log,
        containsAllInOrder(['initialize #1 end', 'capture #1 start']),
      );
      expect(captured, hasLength(1));
      await finish(tester, session);
    });
  });

  group('a switch during a recording', () {
    testWidgets('recording goes on across a switch', (tester) async {
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      session
        ..startRecording()
        ..switchCamera()
        ..stopRecording();
      await tester.pump(platform.recordStartTime);
      await tester.pump(platform.switchTime);
      await tester.pump(platform.stopTime);

      expect(
        platform.log,
        containsAllInOrder([
          'record #1 start',
          'switch #1 front end',
          'record #1 end',
        ]),
      );
      expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
      expect((session.currentState as Ready).recording, isFalse);
      await finish(tester, session);
    });

    testWidgets('stop during a switch waits for it', (tester) async {
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      session.startRecording();
      await tester.pump(platform.recordStartTime);
      expect((session.currentState as Ready).recording, isTrue);
      session
        ..switchCamera()
        ..stopRecording();
      await tester.pump(platform.switchTime);
      await tester.pump(platform.stopTime);

      expect(
        platform.log,
        containsAllInOrder(['switch #1 front end', 'stop #1 start']),
      );
      expect(captured, hasLength(1));
      await finish(tester, session);
    });

    testWidgets('a switch while the recording starts waits for it (iPhone)', (
      tester,
    ) async {
      platform.phone = FakePhone.iphone;
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      session
        ..startRecording()
        ..switchCamera();
      await tester.pump(platform.recordStartTime);
      await tester.pump(platform.switchTime);

      expect(
        platform.log,
        containsAllInOrder([
          'record #1 start',
          'record #1 started',
          'switch #1 front start',
          'switch #1 front end',
        ]),
      );
      expect(platform.log, isNot(contains(startsWith('dispose'))));
      final stopped = session.stopRecording().done;
      await tester.pump(platform.stopTime);

      expect(await stopped, isA<Done<XFile?>>());
      expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
      expect(platform.log, contains('record #1 end'));
      await finish(tester, session);
    });

    testWidgets('a second tap of record or of stop adds nothing', (
      tester,
    ) async {
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      session
        ..startRecording()
        ..startRecording();
      await tester.pump(platform.recordStartTime);
      final first = session.stopRecording().value;
      final second = session.stopRecording().value;
      await tester.pump(platform.stopTime);

      expect(platform.log.where((l) => l == 'record #1 start'), hasLength(1));
      expect(platform.log.where((l) => l == 'stop #1 start'), hasLength(1));
      expect((await first)?.path, '/fake/video-1.mp4');
      expect(await second, isNull);
      expect(captured, hasLength(1));
      await finish(tester, session);
    });
  });

  group('the app leaves the foreground', () {
    /// Shows the view of [session], which listens to the lifecycle of the
    /// app, and opens the camera.
    Future<CameraSession> openShown(WidgetTester tester) async {
      final session = CameraSession(onCaptured: captured.add);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CameraView(session: session),
        ),
      );
      session.open();
      await tester.pump(platform.openTime);
      return session;
    }

    /// Takes the app through [states] as the platform reports them, all at
    /// once.
    void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
      for (final state in states) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    const leave = [AppLifecycleState.inactive, AppLifecycleState.hidden];
    const back = [AppLifecycleState.inactive, AppLifecycleState.resumed];

    testWidgets('recording is kept when the app leaves', (tester) async {
      final session = await openShown(tester);
      session.startRecording();
      await tester.pump(platform.recordStartTime);
      lifecycle(tester, leave);
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);

      expect(captured, hasLength(1));
      expect(captured.single.path, '/fake/video-1.mp4');
      expect(platform.openCameras, 0);
      expect(session.currentState, isA<Closed>());
      expect(
        platform.log,
        containsAllInOrder(['record #1 end', 'dispose #1 start']),
      );
      lifecycle(tester, back);
      await tester.pump(platform.openTime);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, session);
    });

    testWidgets('coming back opens after the release', (tester) async {
      final session = await openShown(tester);
      session.startRecording();
      await tester.pump(platform.recordStartTime);
      // Shown again at once, the view draws frames during the release: the
      // end of the recording rebuilds the preview, which must be gone.
      lifecycle(tester, [...leave, ...back]);
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);

      expect(
        platform.log,
        containsAllInOrder(['dispose #1 end', 'create back #2']),
      );
      expect(platform.openCameras, 1);
      expect(session.currentState, isA<Ready>());
      await tester.pumpWidget(const SizedBox());
      await finish(tester, session);
    });

    testWidgets('coming back opens the camera that was let go', (tester) async {
      final session = await openShown(tester);
      session.switchCamera();
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);
      lifecycle(tester, [...leave, ...back]);
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);

      expect(
        platform.log,
        containsAllInOrder([
          'create front #2',
          'dispose #2 end',
          'create front #3',
        ]),
      );
      expect(session.currentState, isA<Ready>());
      await tester.pumpWidget(const SizedBox());
      await finish(tester, session);
    });

    testWidgets('a permission dialog during open releases nothing', (
      tester,
    ) async {
      final session = CameraSession(onCaptured: captured.add);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CameraView(session: session),
        ),
      );
      session.open();
      await tester.pump(platform.openTime ~/ 2);
      lifecycle(tester, back);
      await tester.pump(platform.openTime);
      await tester.pump(platform.disposeTime);

      expect(platform.log.where((l) => l.startsWith('dispose')), isEmpty);
      expect(session.currentState, isA<Ready>());
      await tester.pumpWidget(const SizedBox());
      await finish(tester, session);
    });
  });

  testWidgets('release waits for the platform', (tester) async {
    final journal = Journal(platform);
    Solo.observer = journal;
    final session = CameraSession(onCaptured: captured.add);
    session.open();
    await tester.pump(platform.openTime);
    var released = false;
    final done = session.release().done..then((_) => released = true);
    await tester.pump(platform.disposeTime - const Duration(milliseconds: 1));

    expect(released, isFalse);
    expect(session.currentState, isA<Ready>());
    await tester.pump(const Duration(milliseconds: 1));
    expect(released, isTrue);
    expect(await done, isA<Done<void>>());
    await session.close();
    expect(
      journal.lines,
      containsAllInOrder([
        'dispose #1 start',
        'dispose #1 end',
        'state Closed',
      ]),
    );
    expect(platform.log.where((l) => l == 'dispose #1 start'), hasLength(1));
    expect(platform.openCameras, 0);
    expect(session.currentState, isA<Closed>());
  });
}
