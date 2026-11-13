/// The expectations of the camera screen, for both controllers that run it.
///
/// `CameraSession` of the app runs them in `camera_session_test.dart` and
/// `camera_screen_test.dart`; `CameraBloc`, the app's controller on bloc,
/// runs the same ones in `bloc_camera_test.dart`. A case drives the
/// controller through [CameraDriver], or the whole app through its
/// buttons, and looks at the platform, the state and the screen; what a
/// controller returns from a command is its own, and its own test file
/// checks it.
library;

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
// Deprecated from Flutter 3.47 for package:material_ui, whose releases
// since 0.0.2 need Flutter 3.44; the floor is Flutter 3.38.1.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_solo_camera_example/camera_app.dart';
import 'package:flutter_solo_camera_example/camera_bloc.dart';
import 'package:flutter_solo_camera_example/camera_screen.dart';
import 'package:flutter_solo_camera_example/camera_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_camera_platform.dart';

/// A controller of the camera screen as the cases drive it: the commands of
/// `CameraSession`, each sent without waiting for it, and the state.
abstract interface class CameraDriver {
  /// The state the screen shows.
  CameraState get currentState;

  /// The part of the screen that shows the controller and listens to the
  /// lifecycle of the app.
  Widget get view;

  void open();
  void takePicture();
  void cycleFlash();
  void toggleTorch();
  void switchCamera();
  void startRecording();
  void stopRecording();

  /// Lets the camera go and closes the controller, as the camera screen
  /// does when it leaves; the future ends once the platform has let the
  /// camera go.
  Future<void> release();
}

/// Makes a [CameraDriver] whose controller hands every picture and video
/// to [onCaptured]. With [onUnanswered], an error of a command nobody
/// waits for goes there rather than to the zone of the test.
typedef MakeDriver =
    CameraDriver Function(
      void Function(XFile file) onCaptured, {
      void Function(Object error)? onUnanswered,
    });

/// Turns the real event loop once, for the `close()` of a bloc to end.
///
/// The bloc waits for the cancel of the subscriptions of its handlers, and
/// a subscription with nothing to wait for answers with a future the SDK
/// made in the root zone. The fake clock of `testWidgets` does not run the
/// callbacks of that zone; the real event loop does.
Future<void> letCloseEnd(WidgetTester tester) => tester.runAsync(() async {});

/// Registers the cases that drive the controller [make] gives.
void controllerCases(MakeDriver make) {
  late FakeCameraPlatform platform;
  late List<XFile> captured;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    captured = [];
  });

  /// Releases the camera of [controller] and closes it, the way the camera
  /// screen does when it leaves.
  Future<void> finish(WidgetTester tester, CameraDriver controller) async {
    final released = controller.release();
    await tester.pump(platform.disposeTime);
    await letCloseEnd(tester);
    await released;
  }

  /// Shows the view of [controller], which listens to the lifecycle of the
  /// app, and opens the camera.
  Future<CameraDriver> openShown(
    WidgetTester tester, {
    void Function(Object error)? onUnanswered,
  }) async {
    final controller = make(captured.add, onUnanswered: onUnanswered);
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: controller.view),
    );
    controller.open();
    await tester.pump(platform.openTime);
    return controller;
  }

  testWidgets('open shows the preview', (tester) async {
    final controller = await openShown(tester);

    expect(controller.currentState, isA<Ready>());
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(platform.log.take(3), [
      'create back #1',
      'initialize #1 start',
      'initialize #1 end',
    ]);
    await tester.pumpWidget(const SizedBox());
    await finish(tester, controller);
  });

  testWidgets('no camera on the device', (tester) async {
    platform.cameras = const [];
    final controller = make(captured.add);
    controller.open();
    await tester.pump();

    expect(controller.currentState, isA<NoCamera>());
    expect(platform.openCameras, 0);
    await finish(tester, controller);
  });

  testWidgets('a picture goes to onCaptured', (tester) async {
    final controller = make(captured.add);
    controller.open();
    await tester.pump(platform.openTime);
    controller.takePicture();
    await tester.pump(platform.captureTime);

    expect(captured.map((file) => file.path), ['/fake/picture-1.jpg']);
    expect(
      platform.log,
      containsAllInOrder(['capture #1 start', 'capture #1 end']),
    );
    await finish(tester, controller);
  });

  group('rapid taps', () {
    testWidgets('flash taps apply in order', (tester) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      // The plugin's controller starts with the flash on auto.
      expect((controller.currentState as Ready).flash, FlashMode.auto);
      controller
        ..cycleFlash()
        ..cycleFlash()
        ..cycleFlash();
      await tester.pump();

      expect(platform.log.where((l) => l.startsWith('flash')), [
        'flash #1 always',
        'flash #1 off',
        'flash #1 auto',
      ]);
      expect((controller.currentState as Ready).flash, FlashMode.auto);
      await finish(tester, controller);
    });

    testWidgets('a shot during a shot is dropped', (tester) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller
        ..takePicture()
        ..takePicture();
      await tester.pump(platform.captureTime);

      expect(platform.log.where((l) => l == 'capture #1 start'), hasLength(1));
      expect(captured, hasLength(1));
      await finish(tester, controller);
    });

    testWidgets('a shot after a shot is taken', (tester) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller.takePicture();
      await tester.pump(platform.captureTime);
      controller.takePicture();
      await tester.pump(platform.captureTime);

      expect(platform.log.where((l) => l == 'capture #1 start'), hasLength(2));
      expect(captured, hasLength(2));
      await finish(tester, controller);
    });

    testWidgets('a switch during a shot waits for it', (tester) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller
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
      await finish(tester, controller);
    });

    testWidgets('a tap while the camera opens waits for it', (tester) async {
      final controller = make(captured.add);
      controller
        ..open()
        ..takePicture();
      await tester.pump(platform.openTime);
      await tester.pump(platform.captureTime);

      expect(
        platform.log,
        containsAllInOrder(['initialize #1 end', 'capture #1 start']),
      );
      expect(captured, hasLength(1));
      await finish(tester, controller);
    });
  });

  group('the torch', () {
    /// The calls of the flash and the torch the platform got.
    Iterable<String> flashes() =>
        platform.log.where((line) => line.startsWith('flash '));

    bool torch(CameraDriver controller) =>
        (controller.currentState as Ready).torch;

    testWidgets('on, then off and on while it lights: one call', (
      tester,
    ) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      expect(torch(controller), isFalse);
      controller.toggleTorch();
      await tester.pump(platform.torchTime ~/ 2);
      expect(platform.log.last, 'flash #1 torch start');
      controller
        ..toggleTorch()
        ..toggleTorch();
      await tester.pump(platform.torchTime);
      await tester.pump();

      expect(flashes(), ['flash #1 torch start', 'flash #1 torch end']);
      expect(torch(controller), isTrue);
      expect(platform.torchOn(1), isTrue);
      await finish(tester, controller);
    });

    testWidgets('on and off during a shot: no call', (tester) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller
        ..takePicture()
        ..toggleTorch()
        ..toggleTorch();
      await tester.pump(platform.captureTime);
      await tester.pump();

      expect(platform.log, contains('capture #1 end'));
      expect(flashes(), isEmpty);
      expect(torch(controller), isFalse);
      await finish(tester, controller);
    });

    testWidgets('three taps from off while a recording starts: one call', (
      tester,
    ) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller
        ..startRecording()
        ..toggleTorch()
        ..toggleTorch()
        ..toggleTorch();
      await tester.pump(platform.recordStartTime);
      await tester.pump(platform.torchTime);
      await tester.pump();

      expect(flashes(), ['flash #1 torch start', 'flash #1 torch end']);
      expect(torch(controller), isTrue);
      expect((controller.currentState as Ready).recording, isTrue);
      controller.stopRecording();
      await tester.pump(platform.stopTime);
      expect((controller.currentState as Ready).recording, isFalse);
      expect(torch(controller), isTrue);
      await finish(tester, controller);
    });

    testWidgets('a recording keeps the torch on', (tester) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller
        ..toggleTorch()
        ..startRecording();
      await tester.pump(platform.torchTime);
      await tester.pump(platform.recordStartTime);
      expect((controller.currentState as Ready).recording, isTrue);
      expect(torch(controller), isTrue);
      controller.stopRecording();
      await tester.pump(platform.stopTime);

      expect((controller.currentState as Ready).recording, isFalse);
      expect(torch(controller), isTrue);
      expect(flashes(), ['flash #1 torch start', 'flash #1 torch end']);
      await finish(tester, controller);
    });

    testWidgets('the flash waits while the torch is on', (tester) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller.toggleTorch();
      await tester.pump(platform.torchTime);
      controller.cycleFlash();
      await tester.pump();

      expect(flashes(), ['flash #1 torch start', 'flash #1 torch end']);
      expect((controller.currentState as Ready).flash, FlashMode.always);
      expect(torch(controller), isTrue);
      controller.toggleTorch();
      await tester.pump();
      expect(flashes().last, 'flash #1 always');
      expect(torch(controller), isFalse);
      expect(platform.torchOn(1), isFalse);
      await finish(tester, controller);
    });

    testWidgets('a tap that finds the camera lost leaves the next its own', (
      tester,
    ) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller
        ..startRecording()
        ..toggleTorch();
      await tester.pump(platform.recordStartTime ~/ 2);
      platform.failFromOutside(1, FakeCameraPlatform.takenOnAndroid);
      await tester.pump(platform.recordStartTime);
      await tester.pump(platform.disposeTime);
      expect(controller.currentState, isA<Broken>());
      controller.open();
      await tester.pump(platform.openTime);
      controller.toggleTorch();
      await tester.pump(platform.torchTime);

      expect(flashes(), ['flash #2 torch start', 'flash #2 torch end']);
      expect(torch(controller), isTrue);
      await finish(tester, controller);
    });

    testWidgets('a switch to a camera without a torch puts it out', (
      tester,
    ) async {
      final controller = await openShown(tester);
      final button = find.byKey(const Key('torch'));
      expect(find.byIcon(Icons.flashlight_off), findsOneWidget);
      await tester.tap(button);
      await tester.pump(platform.torchTime);
      await tester.pump();
      expect(find.byIcon(Icons.flashlight_on), findsOneWidget);
      controller.switchCamera();
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);
      await tester.pump();

      final front = controller.currentState as Ready;
      expect(front.camera.description.lensDirection, CameraLensDirection.front);
      expect(front.torch, isFalse);
      expect(button, findsNothing);
      expect(flashes(), [
        'flash #1 torch start',
        'flash #1 torch end',
        'flash #2 auto',
      ]);
      controller.switchCamera();
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);
      await tester.pump();

      final back = controller.currentState as Ready;
      expect(back.camera.description.lensDirection, CameraLensDirection.back);
      expect(back.torch, isFalse);
      expect(button, findsOneWidget);
      expect(find.byIcon(Icons.flashlight_off), findsOneWidget);
      expect(flashes().last, 'flash #3 auto');
      expect(platform.torchOn(3), isFalse);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });
  });

  group('the flash after a switch', () {
    // The plugin opens the next camera with a flash mode of its own: on an
    // iPhone 13 mini `auto`, while the controller keeps the mode it had.
    testWidgets('a switch gives the next camera the mode of the button', (
      tester,
    ) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller
        ..cycleFlash()
        ..switchCamera();
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);
      await tester.pump();

      expect(
        platform.log,
        containsAllInOrder(['flash #1 always', 'initialize #2 end']),
      );
      expect(platform.log.last, 'flash #2 always');
      expect((controller.currentState as Ready).flash, FlashMode.always);
      await finish(tester, controller);
    });

    testWidgets('a switch during a recording leaves the flash', (tester) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller
        ..cycleFlash()
        ..startRecording()
        ..switchCamera()
        ..stopRecording();
      await tester.pump(platform.recordStartTime);
      await tester.pump(platform.switchTime);
      await tester.pump(platform.stopTime);

      expect(platform.log.where((l) => l.startsWith('flash ')), [
        'flash #1 always',
      ]);
      expect((controller.currentState as Ready).flash, FlashMode.always);
      await finish(tester, controller);
    });
  });

  group('a switch during a recording', () {
    testWidgets('recording goes on across a switch', (tester) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller
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
      expect((controller.currentState as Ready).recording, isFalse);
      await finish(tester, controller);
    });

    testWidgets('stop during a switch waits for it', (tester) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller.startRecording();
      await tester.pump(platform.recordStartTime);
      expect((controller.currentState as Ready).recording, isTrue);
      controller
        ..switchCamera()
        ..stopRecording();
      await tester.pump(platform.switchTime);
      await tester.pump(platform.stopTime);

      expect(
        platform.log,
        containsAllInOrder(['switch #1 front end', 'stop #1 start']),
      );
      expect(captured, hasLength(1));
      await finish(tester, controller);
    });

    testWidgets('a switch while the recording starts waits for it (iPhone)', (
      tester,
    ) async {
      platform.phone = FakePhone.iphone;
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller
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
      controller.stopRecording();
      await tester.pump(platform.stopTime);

      expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
      expect(platform.log, contains('record #1 end'));
      await finish(tester, controller);
    });

    testWidgets('a second tap of record or of stop adds nothing', (
      tester,
    ) async {
      final controller = make(captured.add);
      controller.open();
      await tester.pump(platform.openTime);
      controller
        ..startRecording()
        ..startRecording();
      await tester.pump(platform.recordStartTime);
      controller
        ..stopRecording()
        ..stopRecording();
      await tester.pump(platform.stopTime);

      expect(platform.log.where((l) => l == 'record #1 start'), hasLength(1));
      expect(platform.log.where((l) => l == 'stop #1 start'), hasLength(1));
      expect(captured, hasLength(1));
      await finish(tester, controller);
    });
  });

  group('the app leaves the foreground', () {
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
      final controller = await openShown(tester);
      controller.startRecording();
      await tester.pump(platform.recordStartTime);
      lifecycle(tester, leave);
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);

      expect(captured, hasLength(1));
      expect(captured.single.path, '/fake/video-1.mp4');
      expect(platform.openCameras, 0);
      expect(controller.currentState, isA<Closed>());
      expect(
        platform.log,
        containsAllInOrder(['record #1 end', 'dispose #1 start']),
      );
      lifecycle(tester, back);
      await tester.pump(platform.openTime);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('coming back opens after the release', (tester) async {
      final controller = await openShown(tester);
      controller.startRecording();
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
      expect(controller.currentState, isA<Ready>());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('a failed stop still lets the camera go', (tester) async {
      final unanswered = <Object>[];
      platform.failStop = CameraException('stopFailed', 'The stop failed.');
      final controller = await openShown(tester, onUnanswered: unanswered.add);
      controller.startRecording();
      await tester.pump(platform.recordStartTime);
      lifecycle(tester, leave);
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);

      expect(captured, isEmpty);
      expect(platform.openCameras, 0);
      expect(controller.currentState, isA<Closed>());
      // The failure stays the error of the command, which nobody awaits.
      expect(unanswered, [isA<CameraException>()]);
      lifecycle(tester, back);
      await tester.pump(platform.openTime);

      expect(
        controller.currentState,
        isA<Ready>().having((s) => s.recording, 'recording', isFalse),
      );
      expect(platform.openCameras, 1);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('coming back opens the camera that was let go', (tester) async {
      final controller = await openShown(tester);
      controller.switchCamera();
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
      expect(controller.currentState, isA<Ready>());
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('a permission dialog during open releases nothing', (
      tester,
    ) async {
      final controller = make(captured.add);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: controller.view,
        ),
      );
      controller.open();
      await tester.pump(platform.openTime ~/ 2);
      lifecycle(tester, back);
      await tester.pump(platform.openTime);
      await tester.pump(platform.disposeTime);

      expect(platform.log.where((l) => l.startsWith('dispose')), isEmpty);
      expect(controller.currentState, isA<Ready>());
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });
  });

  group('the camera is lost', () {
    final retry = find.byKey(const Key('retry'));

    /// The platform reports [description] for the camera [id]; the event
    /// comes after the frame it is sent in, and the next frame shows it.
    Future<void> fail(WidgetTester tester, int id, String description) async {
      platform.failFromOutside(id, description);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a camera taken away shows the failure', (tester) async {
      final controller = await openShown(tester);
      // The Galaxy reports a camera taken by another app as an error, with
      // no closing event.
      await fail(tester, 1, FakeCameraPlatform.takenOnAndroid);

      expect(
        controller.currentState,
        isA<Broken>().having(
          (s) => s.error,
          'error',
          FakeCameraPlatform.takenOnAndroid,
        ),
      );
      expect(retry, findsOneWidget);
      await tester.pump(platform.disposeTime);
      expect(platform.log, contains('dispose #1 end'));
      expect(platform.openCameras, 0);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('a platform error shows the failure (iPhone)', (tester) async {
      platform.phone = FakePhone.iphone;
      final controller = await openShown(tester);
      await fail(tester, 1, 'camera error');

      expect(controller.currentState, isA<Broken>());
      await tester.pump(platform.disposeTime);
      expect(platform.openCameras, 0);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('a second error of a lost camera changes nothing', (
      tester,
    ) async {
      final controller = await openShown(tester);
      platform
        ..failFromOutside(1, FakeCameraPlatform.takenOnAndroid)
        ..failFromOutside(1, 'a second failure');
      await tester.pump(platform.disposeTime);

      expect(
        controller.currentState,
        isA<Broken>().having(
          (s) => s.error,
          'error',
          FakeCameraPlatform.takenOnAndroid,
        ),
      );
      expect(platform.log.where((l) => l == 'dispose #1 start'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('commands waiting in the queue skip a lost camera', (
      tester,
    ) async {
      final controller = await openShown(tester);
      controller
        ..takePicture()
        ..cycleFlash();
      await fail(tester, 1, FakeCameraPlatform.takenOnAndroid);
      await tester.pump(platform.captureTime);
      await tester.pump(platform.disposeTime);

      expect(controller.currentState, isA<Broken>());
      expect(platform.log, isNot(contains(startsWith('flash'))));
      // The picture under way ends after the loss and is not handed on.
      expect(platform.log, contains('capture #1 end'));
      expect(captured, isEmpty);
      expect(platform.openCameras, 0);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('a camera lost while a recording starts stays lost', (
      tester,
    ) async {
      final controller = await openShown(tester);
      controller.startRecording();
      await tester.pump(platform.recordStartTime ~/ 2);
      await fail(tester, 1, FakeCameraPlatform.takenOnAndroid);
      await tester.pump(platform.recordStartTime);
      await tester.pump(platform.disposeTime);

      // The start ends after the loss, and the state still says the loss.
      expect(platform.log, contains('record #1 started'));
      expect(controller.currentState, isA<Broken>());
      expect(retry, findsOneWidget);
      expect(platform.openCameras, 0);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('an error of the camera after a switch shows', (tester) async {
      final controller = await openShown(tester);
      controller.switchCamera();
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);
      expect(platform.log, contains('initialize #2 end'));
      await fail(tester, 2, 'camera error');

      expect(controller.currentState, isA<Broken>());
      await tester.pump(platform.disposeTime);
      expect(platform.openCameras, 0);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('a failed switch without a recording is a failure', (
      tester,
    ) async {
      final controller = await openShown(tester);
      // Without a recording the switch releases the camera, then opens the
      // next one, which fails.
      platform.failOpen = PlatformException(
        code: 'CameraError',
        message: 'The camera failed to open.',
      );
      controller.switchCamera();
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);
      await tester.pump(platform.disposeTime);

      expect(controller.currentState, isA<Broken>());
      expect(
        platform.log,
        containsAllInOrder([
          'dispose #1 end',
          'create front #2',
          'dispose #2 end',
        ]),
      );
      expect(platform.openCameras, 0);
      platform.failOpen = null;
      await tester.pump();
      await tester.tap(retry);
      await tester.pump(platform.openTime);

      expect(controller.currentState, isA<Ready>());
      expect(platform.openCameras, 1);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('a failed switch during a recording keeps the camera', (
      tester,
    ) async {
      final unanswered = <Object>[];
      platform.failSwitch = CameraException('switchFailed', 'It failed.');
      final controller = await openShown(tester, onUnanswered: unanswered.add);
      controller.startRecording();
      await tester.pump(platform.recordStartTime);
      controller.switchCamera();
      await tester.pump(platform.switchTime);

      // The recording goes on from the camera it had, and the state says so.
      expect(
        controller.currentState,
        isA<Ready>().having((s) => s.recording, 'recording', isTrue),
      );
      expect(platform.log, isNot(contains(startsWith('dispose'))));
      expect(unanswered, [isA<CameraException>()]);
      platform.failSwitch = null;
      controller.stopRecording();
      await tester.pump(platform.stopTime);
      expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('retry opens again', (tester) async {
      final controller = await openShown(tester);
      await fail(tester, 1, FakeCameraPlatform.takenOnAndroid);
      await tester.tap(retry);
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);

      expect(controller.currentState, isA<Ready>());
      expect(
        platform.log,
        containsAllInOrder(['dispose #1 end', 'create back #2']),
      );
      expect(platform.openCameras, 1);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('retry twice opens one camera', (tester) async {
      final controller = await openShown(tester);
      await fail(tester, 1, FakeCameraPlatform.takenOnAndroid);
      // The second tap comes before the frame that takes the button away.
      await tester.tap(retry);
      await tester.tap(retry);
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);
      await tester.pump(platform.openTime);

      expect(controller.currentState, isA<Ready>());
      expect(platform.openCameras, 1);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets("the Galaxy's closing events leave the camera ready", (
      tester,
    ) async {
      final controller = await openShown(tester);
      // On the Galaxy's rules the recording, the switch and the stop each
      // send a closing event, and the camera stays open.
      controller
        ..startRecording()
        ..switchCamera()
        ..stopRecording();
      await tester.pump(platform.recordStartTime);
      await tester.pump(platform.switchTime);
      await tester.pump(platform.stopTime);

      expect(captured, hasLength(1));
      expect(
        controller.currentState,
        isA<Ready>().having((s) => s.recording, 'recording', isFalse),
      );
      expect(platform.log, isNot(contains(startsWith('dispose'))));
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('a failed opening shows the failure and lets go', (
      tester,
    ) async {
      platform.failOpen = PlatformException(
        code: 'CameraError',
        message: 'The camera failed to open.',
      );
      final controller = await openShown(tester);
      await tester.pump(platform.disposeTime);

      expect(
        controller.currentState,
        isA<Broken>().having(
          (s) => s.error,
          'error',
          isA<CameraException>().having((e) => e.code, 'code', 'CameraError'),
        ),
      );
      expect(retry, findsOneWidget);
      expect(platform.log, contains('dispose #1 end'));
      expect(platform.openCameras, 0);
      platform.failOpen = null;
      await tester.tap(retry);
      await tester.pump(platform.openTime);

      expect(controller.currentState, isA<Ready>());
      expect(platform.openCameras, 1);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('a failed stop shows the failure and lets go', (tester) async {
      platform.failStop = CameraException('stopFailed', 'The stop failed.');
      final controller = await openShown(tester);
      controller.startRecording();
      await tester.pump(platform.recordStartTime);
      controller.stopRecording();
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);

      expect(controller.currentState, isA<Broken>());
      expect(captured, isEmpty);
      expect(platform.log, contains('dispose #1 end'));
      expect(platform.openCameras, 0);
      platform.failStop = null;
      await tester.tap(retry);
      await tester.pump(platform.openTime);

      expect(
        controller.currentState,
        isA<Ready>().having((s) => s.recording, 'recording', isFalse),
      );
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('a camera lost while the screen leaves is let go', (
      tester,
    ) async {
      final controller = await openShown(tester);
      await tester.pumpWidget(const SizedBox());
      controller.takePicture();
      // The screen leaves during the picture, and the camera is lost
      // before the picture ends. The next screen opens its camera once the
      // release is over, and the platform's release takes whatever camera
      // is open: the lost one has to be released by then.
      late final List<String> atRelease;
      final released = controller.release().then((_) {
        atRelease = [...platform.log];
      });
      platform.failFromOutside(1, FakeCameraPlatform.takenOnAndroid);
      await tester.pump(platform.captureTime);
      await tester.pump(platform.disposeTime);
      await letCloseEnd(tester);
      await released;

      expect(atRelease, contains('dispose #1 end'));
      expect(platform.openCameras, 0);
      expect(controller.currentState, isA<Closed>());
    });
  });

  group('a denied permission', () {
    final retry = find.byKey(const Key('retry'));

    /// The codes of a permission error the plugin's README lists.
    const deniedCodes = [
      'CameraAccessDenied',
      'CameraAccessDeniedWithoutPrompt',
      'CameraAccessRestricted',
      'AudioAccessDenied',
      'AudioAccessDeniedWithoutPrompt',
      'AudioAccessRestricted',
    ];

    for (final code in deniedCodes) {
      testWidgets('$code explains what to allow', (tester) async {
        // Both phones deny from `createCameraWithSettings`.
        platform.failCreate = CameraException(code, 'Denied.');
        final controller = await openShown(tester);
        await tester.pump();

        expect(
          controller.currentState,
          isA<Denied>().having((s) => s.code, 'code', code),
        );
        expect(
          find.textContaining(
            code.startsWith('Audio') ? 'microphone' : 'camera',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('Settings'),
          code.endsWith('WithoutPrompt') ? findsOneWidget : findsNothing,
        );
        expect(
          find.textContaining('policy'),
          code.endsWith('Restricted') ? findsOneWidget : findsNothing,
        );
        expect(retry, code.endsWith('Denied') ? findsOneWidget : findsNothing);
        // No camera was created, and none is released.
        expect(platform.log, isNot(contains(startsWith('dispose'))));
        expect(platform.openCameras, 0);
        await tester.pumpWidget(const SizedBox());
        await finish(tester, controller);
        expect(platform.log, isNot(contains(startsWith('dispose'))));
      });
    }

    testWidgets('retry asks again, and the next answer shows (iPhone)', (
      tester,
    ) async {
      platform
        ..phone = FakePhone.iphone
        ..failCreate = FakeCameraPlatform.deniedOnIphone;
      final controller = await openShown(tester);
      await tester.pump();
      platform.failCreate = FakeCameraPlatform.deniedWithoutPromptOnIphone;
      await tester.tap(retry);
      await tester.pump();
      await tester.pump();

      expect(
        controller.currentState,
        isA<Denied>().having(
          (s) => s.code,
          'code',
          'CameraAccessDeniedWithoutPrompt',
        ),
      );
      expect(find.textContaining('Settings'), findsOneWidget);
      expect(retry, findsNothing);
      expect(platform.log, ['create back failed', 'create back failed']);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('retry after the permission is given opens the camera', (
      tester,
    ) async {
      platform.failCreate = FakeCameraPlatform.deniedOnAndroid;
      final controller = await openShown(tester);
      await tester.pump();
      platform.failCreate = null;
      await tester.tap(retry);
      await tester.pump(platform.openTime);

      expect(controller.currentState, isA<Ready>());
      expect(platform.openCameras, 1);
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });

    testWidgets('a failed create that is no denial is a failure, and '
        'nothing is let go', (tester) async {
      // The Galaxy's answer to a second opening while its dialog is up.
      platform.failCreate = CameraException(
        'CameraPermissionsRequestOngoing',
        'Another request is ongoing and multiple requests cannot be '
            'handled at once.',
      );
      final controller = await openShown(tester);
      await tester.pump(platform.disposeTime);

      expect(controller.currentState, isA<Broken>());
      expect(retry, findsOneWidget);
      expect(platform.log, isNot(contains(startsWith('dispose'))));
      await tester.pumpWidget(const SizedBox());
      await finish(tester, controller);
    });
  });
}

/// Registers the cases that run the app, the home screen with a camera
/// screen over it, through its buttons, with [controller] picked on the
/// switch of the home screen: `solo` or `bloc`.
void appCases(String controller) {
  late FakeCameraPlatform platform;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
  });

  /// Puts the app on the screen and picks [controller] on its switch.
  Future<void> startApp(WidgetTester tester) async {
    await tester.pumpWidget(const CameraApp());
    await tester.tap(find.byKey(Key('controller-$controller')));
    await tester.pumpAndSettle();
  }

  /// Pumps until [finder] finds a widget: a scope of scopo builds its ready
  /// branch some frames after its initialization ends, and a scope that
  /// waits on its `scopeKey` waits for the screen before it to close.
  Future<void> until(WidgetTester tester, Finder finder) async {
    for (var frame = 0; frame < 50 && finder.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      await letCloseEnd(tester);
    }
    expect(finder, findsOneWidget);
  }

  /// Opens the camera screen from the home screen, on [controller].
  Future<void> openCamera(WidgetTester tester) async {
    await startApp(tester);
    await tester.tap(find.byKey(const Key('open-camera')));
    await tester.pumpAndSettle();
    expect(
      find.byType(controller == 'bloc' ? BlocCameraScreen : CameraScreen),
      findsOneWidget,
    );
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

  testWidgets('the flash and the switch buttons reach the camera', (
    tester,
  ) async {
    await openCamera(tester);
    await until(tester, find.byIcon(Icons.flash_auto));
    await tester.tap(find.byKey(const Key('flash')));
    await tester.pump();

    expect(find.byIcon(Icons.flash_on), findsOneWidget);
    expect(platform.log, contains('flash #1 always'));
    await tester.tap(find.byKey(const Key('switch')));
    await tester.pump(platform.disposeTime);
    await tester.pump(platform.openTime);

    expect(
      platform.log,
      containsAllInOrder([
        'dispose #1 start',
        'dispose #1 end',
        'create front #2',
        'initialize #2 end',
      ]),
    );
    await goBack(tester);
    expect(platform.openCameras, 0);
  });

  testWidgets('the torch button reaches the camera', (tester) async {
    await openCamera(tester);
    await until(tester, find.byIcon(Icons.flashlight_off));
    await tester.tap(find.byKey(const Key('torch')));
    await tester.pump(platform.torchTime);
    await tester.pump();

    expect(find.byIcon(Icons.flashlight_on), findsOneWidget);
    expect(platform.torchOn(1), isTrue);
    await tester.tap(find.byKey(const Key('torch')));
    await tester.pump();

    expect(find.byIcon(Icons.flashlight_off), findsOneWidget);
    expect(platform.log.last, 'flash #1 auto');
    await goBack(tester);
    expect(platform.openCameras, 0);
  });

  testWidgets('the record button starts and stops a video', (tester) async {
    await openCamera(tester);
    await until(tester, find.byIcon(Icons.videocam));
    await tester.tap(find.byKey(const Key('record')));
    await tester.pump(platform.recordStartTime);
    await tester.pump();

    expect(find.byIcon(Icons.stop), findsOneWidget);
    await tester.tap(find.byKey(const Key('record')));
    await tester.pump(platform.stopTime);
    await tester.pump();

    expect(find.byIcon(Icons.videocam), findsOneWidget);
    await goBack(tester);

    expect(
      platform.log,
      containsAllInOrder(['record #1 start', 'stop #1 start', 'record #1 end']),
    );
    expect(find.byKey(const Key('last-shot')), findsOneWidget);
    expect(platform.openCameras, 0);
  });

  testWidgets('a shot started before leaving reaches home', (tester) async {
    // A picture on the Galaxy takes from 0.5 to 3.4 s, longer than the
    // pop of a route takes to remove the screen.
    platform.captureTime = const Duration(seconds: 1);
    await openCamera(tester);
    await until(tester, find.byKey(const Key('shutter')));
    await tester.tap(find.byKey(const Key('shutter')));
    await tester.pump();
    await goBack(tester);
    await tester.pump(platform.captureTime);
    await tester.pump(platform.disposeTime);

    expect(find.byKey(const Key('last-shot')), findsOneWidget);
    expect(
      platform.log,
      containsAllInOrder(['capture #1 end', 'dispose #1 start']),
    );
    expect(platform.openCameras, 0);
  });

  testWidgets('a new camera screen waits for the old one', (tester) async {
    await openCamera(tester);
    await until(tester, find.byKey(const Key('shutter')));
    await tester.pageBack();
    await tester.pump();
    await tester.tap(find.byKey(const Key('open-camera')));
    await tester.pumpAndSettle();
    await tester.pump(platform.disposeTime);
    await until(tester, find.byKey(const Key('shutter')));

    expect(
      platform.log,
      containsAllInOrder(['dispose #1 end', 'create back #2']),
    );
    expect(platform.openCameras, 1);
    expect(platform.hasPicture(2), isTrue);
    await goBack(tester);
    expect(platform.openCameras, 0);
  });

  testWidgets('leaving while the camera opens', (tester) async {
    // Longer than the pop of a route takes to remove the screen.
    platform.openTime = const Duration(seconds: 1);
    await startApp(tester);
    await tester.tap(find.byKey(const Key('open-camera')));
    await tester.pump();
    // The route is offstage on its first frame, its back button with it.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(platform.log.last, 'initialize #1 start');
    await tester.pump(platform.openTime);
    await tester.pump(platform.disposeTime);

    expect(
      platform.log,
      containsAllInOrder(['initialize #1 end', 'dispose #1 start']),
    );
    expect(platform.log.where((l) => l == 'dispose #1 start'), hasLength(1));
    expect(platform.openCameras, 0);
    expect(tester.takeException(), isNull);
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
