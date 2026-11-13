import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
// Deprecated from Flutter 3.47 for package:material_ui, whose releases
// since 0.0.2 need Flutter 3.44; the floor is Flutter 3.38.1.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_app_attempts.dart';
import 'support/fake_camera_platform.dart';

/// The first attempts that broke on a phone, on the fake platform, with
/// the phone's outcome as the expectation. Each test names the phone; the
/// probes report, `2026-11-13-device-app-probes-report.md`, has the runs.
void main() {
  late FakeCameraPlatform platform;
  late List<XFile> captured;
  late List<Object> uncaught;
  final navigator = GlobalKey<NavigatorState>();

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    captured = [];
    uncaught = [];
  });

  Future<void> start(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Center(child: Text('home'))),
    ),
  );

  /// Pushes [screen] over the home screen and lets the camera open.
  Future<void> open(
    WidgetTester tester,
    Widget Function(List<CameraDescription>, void Function(XFile)) screen,
  ) async {
    // The route lives as long as the screen; the push is not awaited.
    // ignore: unawaited_futures
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: screen(platform.cameras, captured.add)),
      ),
    );
    await tester.pump();
    await tester.pump(platform.openTime);
  }

  /// Taps [button]; what the press starts keeps its uncaught errors in
  /// [uncaught], to be checked outside the zone.
  Future<void> tap(WidgetTester tester, String button) async {
    await runZonedGuarded(
      () => tester.tap(find.byKey(Key(button)).last),
      (e, _) => uncaught.add(e),
    );
    await tester.pump();
  }

  /// Pops the screen with its release, which runs in a zone that keeps
  /// the uncaught errors of `State.dispose` in [uncaught].
  Future<void> pop(WidgetTester tester) async {
    navigator.currentState!.pop();
    await runZonedGuarded(() async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
    }, (e, _) => uncaught.add(e));
  }

  /// Leaves every screen and lets their releases end.
  Future<void> finish(WidgetTester tester) async {
    navigator.currentState!.popUntil((route) => route.isFirst);
    await runZonedGuarded(() async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
    }, (e, _) => uncaught.add(e));
  }

  String? shownError() {
    final errors = find.byKey(const Key('error')).evaluate();
    return errors.isEmpty ? null : (errors.last.widget as Text).data;
  }

  group('section 1, quick taps', () {
    testWidgets('a switch during a shot loses the picture (Galaxy)', (
      tester,
    ) async {
      await start(tester);
      await open(tester, (c, f) => EagerButtons(cameras: c, onCaptured: f));
      await tap(tester, 'shutter');
      await tap(tester, 'switch');
      await tester.pump(const Duration(seconds: 1));
      expect(captured, isEmpty);
      expect(
        shownError(),
        'ImageCaptureException: androidx.camera.core.ImageCaptureException: '
        'Camera is closed.',
      );
      expect(
        platform.log,
        containsAllInOrder([
          'capture #1 start',
          'dispose #1 start',
          'capture #1 failed',
          'dispose #1 end',
          'create front #2',
        ]),
      );
      await finish(tester);
    });
  });

  group('section 2, a switch during a recording', () {
    testWidgets('a switch while the recording starts loses it (iPhone)', (
      tester,
    ) async {
      platform.phone = FakePhone.iphone;
      await start(tester);
      await open(
        tester,
        (c, f) => SwitchWhileRecording(cameras: c, onCaptured: f),
      );
      await tap(tester, 'record');
      await tester.pump(platform.recordStartTime ~/ 2);
      await tap(tester, 'switch');
      await tester.pump(const Duration(seconds: 2));
      await tap(tester, 'stop');
      await tester.pump(const Duration(seconds: 1));
      expect(captured, isEmpty);
      expect(shownError(), 'Error -1008: Video is not recording!');
      expect(
        platform.log,
        containsAllInOrder([
          'record #1 start',
          'dispose #1 start',
          'create front #2',
          'stop #2 start',
        ]),
      );
      expect(platform.log, isNot(contains(startsWith('switch'))));
      expect(platform.log, isNot(contains('record #1 started')));
      await finish(tester);
    });
  });

  group('section 3, leaving the screen', () {
    testWidgets('leaving during a shot loses the picture (Galaxy)', (
      tester,
    ) async {
      // The Galaxy took from 0.5 to 3.4 s for a picture, longer than the
      // pop of a route takes to release the screen.
      platform.captureTime = const Duration(seconds: 1);
      await start(tester);
      await open(tester, (c, f) => LeavingShutter(cameras: c, onCaptured: f));
      await tap(tester, 'shutter');
      await pop(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(captured, isEmpty);
      expect(
        platform.log,
        containsAllInOrder(['capture #1 start', 'capture #1 failed']),
      );
      expect(
        uncaught.map((e) => '$e'),
        contains(contains('A CameraController was used after being disposed.')),
      );
      await finish(tester);
    });

    testWidgets('leaving during a long shot loses the picture in debug '
        '(iPhone)', (tester) async {
      // On the iPhone the shot (0.2 to 0.6 s) ended before the pop did;
      // a longer one ends after the controller was disposed.
      platform
        ..phone = FakePhone.iphone
        ..captureTime = const Duration(seconds: 1);
      await start(tester);
      await open(tester, (c, f) => LeavingShutter(cameras: c, onCaptured: f));
      await tap(tester, 'shutter');
      await pop(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(captured, isEmpty);
      expect(
        platform.log,
        containsAllInOrder([
          'capture #1 start',
          'dispose #1 start',
          'capture #1 end',
          'dispose #1 end',
        ]),
      );
      expect(
        uncaught.map((e) => '$e'),
        contains(contains('A CameraController was used after being disposed.')),
      );
      await finish(tester);
    });

    Future<void> reopen(WidgetTester tester) async {
      await start(tester);
      await open(tester, (c, f) => LeavingShutter(cameras: c, onCaptured: f));
      navigator.currentState!.pop();
      await open(tester, (c, f) => LeavingShutter(cameras: c, onCaptured: f));
      await runZonedGuarded(
        () => tester.pumpAndSettle(),
        (e, _) => uncaught.add(e),
      );
    }

    testWidgets('opening again before the release (Galaxy)', (tester) async {
      await reopen(tester);
      expect(
        platform.log,
        containsAllInOrder(['create back #2', 'dispose #1 start']),
      );
      expect(platform.hasPicture(2), isFalse);
      await tap(tester, 'shutter');
      await tester.pump(platform.captureTime);
      expect(captured, hasLength(1));
      await pop(tester);
      expect(
        uncaught.map((e) => '$e'),
        contains(contains('IllegalStateException')),
      );
      expect(platform.openCameras, 1);
      await finish(tester);
    });

    testWidgets('opening again before the release (iPhone)', (tester) async {
      platform.phone = FakePhone.iphone;
      await reopen(tester);
      expect(
        platform.log,
        containsAllInOrder(['create back #2', 'dispose #1 start']),
      );
      expect(platform.hasPicture(2), isFalse);
      await tap(tester, 'shutter');
      await tester.pump(const Duration(seconds: 5));
      expect(captured, isEmpty);
      expect(platform.log.last, 'capture #2 start');
      await pop(tester);
      await finish(tester);
    });
  });

  group('section 4, the app leaves the foreground', () {
    for (final phone in FakePhone.values) {
      testWidgets('home during a recording loses it (${phone.name})', (
        tester,
      ) async {
        platform.phone = phone;
        await start(tester);
        await open(
          tester,
          (c, f) => ReadmeLifecycle(cameras: c, onCaptured: f),
        );
        await tap(tester, 'record');
        await tester.pump(platform.recordStartTime);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(platform.openTime);
        await tap(tester, 'stop');
        await tester.pump(const Duration(seconds: 1));
        expect(captured, isEmpty);
        expect(
          platform.log,
          containsAllInOrder([
            'record #1 start',
            'dispose #1 start',
            'dispose #1 end',
            'create back #2',
          ]),
        );
        expect(platform.log, isNot(contains('stop #1 start')));
        await finish(tester);
      });
    }
  });

  group('section 5, losing the camera', () {
    testWidgets('the first error stays and a second is not seen (Galaxy)', (
      tester,
    ) async {
      await start(tester);
      await open(tester, (c, f) => ErrorListener(cameras: c, onCaptured: f));
      platform.failFromOutside(1, FakeCameraPlatform.takenOnAndroid);
      await tester.pump();
      // The Galaxy gave the camera back by itself; a shot works.
      await tap(tester, 'shutter');
      await tester.pump(platform.captureTime);
      expect(captured, hasLength(1));
      // The controller listens to the first error event only.
      platform.failFromOutside(1, 'a second failure');
      await tester.pump();
      expect(shownError(), 'Camera error ${FakeCameraPlatform.takenOnAndroid}');
      await finish(tester);
    });
  });

  group('section 6, no permission', () {
    testWidgets('a denial with and without the dialog reads the same '
        '(Galaxy)', (tester) async {
      // The Galaxy gives the same code from `createCameraWithSettings`
      // the first time and after "don't ask again".
      platform.failCreate = FakeCameraPlatform.deniedOnAndroid;
      await start(tester);
      final shown = <String?>[];
      for (var i = 0; i < 2; i++) {
        await open(
          tester,
          (c, f) => PermissionMessages(cameras: c, onCaptured: f),
        );
        shown.add(shownError());
        await pop(tester);
      }
      expect(shown, [
        'You have denied camera access.',
        'You have denied camera access.',
      ]);
      await finish(tester);
    });
  });
}
