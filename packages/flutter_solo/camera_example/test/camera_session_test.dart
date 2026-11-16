import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo_camera_example/camera_screen.dart';
import 'package:flutter_solo_camera_example/camera_session.dart';
import 'package:flutter_solo_camera_example/camera_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/camera_cases.dart';
import 'support/fake_camera_platform.dart';
import 'support/journal.dart';

/// Drives a [CameraSession] through the cases of the camera screen.
final class SessionDriver implements CameraDriver {
  SessionDriver(
    void Function(XFile file) onCaptured, {
    void Function(Object error)? onUnanswered,
  }) : session = CameraSession(onCaptured: onCaptured) {
    if (onUnanswered != null) {
      Solo.unansweredHandler = (solo, job, error, stackTrace) =>
          onUnanswered(error);
      addTearDown(() => Solo.unansweredHandler = null);
    }
  }

  final CameraSession session;

  @override
  CameraState get currentState => session.currentState;

  @override
  Widget get view => CameraView(session: session);

  @override
  void open() => session.open();

  @override
  void takePicture() => session.takePicture();

  @override
  void cycleFlash() => session.cycleFlash();

  @override
  void toggleTorch() => session.toggleTorch();

  @override
  void switchCamera() => session.switchCamera();

  @override
  void startRecording() => session.startRecording();

  @override
  void stopRecording() => session.stopRecording();

  @override
  Future<void> release() async {
    // The release ends while the test pumps, where `expect` may not run.
    switch (await session.release().done) {
      case Done():
        await session.close();
      case final Cancelled cancelled:
        throw cancelled;
      case Failed(:final error, :final stackTrace):
        Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> close() => session.close();

  /// The close cancels the job of the release, once the camera is let go.
  @override
  Matcher get releaseCutByClose => isA<Cancelled>();
}

void main() {
  group('the camera screen', () => controllerCases(SessionDriver.new));

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

  /// Opens the camera of a new session.
  Future<CameraSession> opened(WidgetTester tester) async {
    final session = CameraSession(onCaptured: captured.add);
    session.open();
    await tester.pump(platform.openTime);
    return session;
  }

  group('what a job gives', () {
    testWidgets('a picture is the value of the job', (tester) async {
      final session = await opened(tester);
      final shot = session.takePicture().value;
      await tester.pump(platform.captureTime);

      expect((await shot)?.path, '/fake/picture-1.jpg');
      await finish(tester, session);
    });

    testWidgets('a second tap gets the shot under way', (tester) async {
      final session = await opened(tester);
      final first = session.takePicture().value;
      final second = session.takePicture().value;
      await tester.pump(platform.captureTime);

      // The second tap gets the shot of the first, not a cancellation.
      expect((await first)?.path, '/fake/picture-1.jpg');
      expect((await second)?.path, '/fake/picture-1.jpg');
      await finish(tester, session);
    });

    testWidgets('a lost shot ends cancelled by the rules', (tester) async {
      final unanswered = <Object>[];
      Solo.unansweredHandler = (solo, job, error, stackTrace) =>
          unanswered.add(error);
      addTearDown(() => Solo.unansweredHandler = null);
      final session = await opened(tester);
      final shot = session.takePicture();
      Object? valueError;
      shot.value.then<void>(
        (_) {},
        onError: (Object e) {
          valueError = e;
        },
      );
      await tester.pump(platform.captureTime ~/ 2);
      // The Galaxy once the app is hidden: an error of the camera, and the
      // picture fails a turn later.
      platform.closeOnHide(1);
      await tester.pump();
      await tester.pump();
      // The job ends once the lost camera is let go.
      await tester.pump(platform.disposeTime);

      expect(platform.log, contains('capture #1 failed'));
      expect(session.currentState, isA<Broken>());
      // No `null`: the state is no longer `Ready`, and the job ends with
      // the cancellation of its rules.
      expect(
        shot.outcome,
        isA<Cancelled>()
            .having((c) => c.reason, 'reason', isA<RulesCancelReason>())
            .having((c) => c.description, 'description', 'is not Ready'),
      );
      expect(valueError, isA<Cancelled>());
      expect(unanswered, isEmpty);
      expect(captured, isEmpty);
      await finish(tester, session);
    });

    testWidgets('a stop with no recording gives null', (tester) async {
      final session = await opened(tester);
      session.startRecording();
      await tester.pump(platform.recordStartTime);
      final first = session.stopRecording().value;
      final second = session.stopRecording().value;
      await tester.pump(platform.stopTime);

      expect((await first)?.path, '/fake/video-1.mp4');
      expect(await second, isNull);
      await finish(tester, session);
    });

    testWidgets('a failed stop ends done', (tester) async {
      platform.failStop = CameraException('stopFailed', 'The stop failed.');
      final session = await opened(tester);
      session.startRecording();
      await tester.pump(platform.recordStartTime);
      final stopped = session.stopRecording().done;
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);

      expect(await stopped, isA<Done<XFile?>>());
      expect(session.currentState, isA<Broken>());
      await finish(tester, session);
    });
  });

  testWidgets('an event after close changes nothing', (tester) async {
    final session = await opened(tester);
    // Closed without a release, as after a release that failed: the camera
    // is still there, and the state the session stops at stays.
    await session.close();
    await tester.pump();
    platform.failFromOutside(1, 'camera error');
    await tester.pump();
    await tester.pump();

    expect(session.currentState, isA<Ready>());
    expect(tester.takeException(), isNull);
    final camera = (session.currentState as Ready).camera;
    final released = camera.dispose();
    await tester.pump(platform.disposeTime);
    await released;
  });

  testWidgets('release waits for the platform', (tester) async {
    final journal = Journal(platform);
    Solo.observer = journal;
    final session = await opened(tester);
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
