import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_solo_camera_example/camera_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/support/device_app_attempts.dart';
import 'support/probe.dart';

/// The first attempts of `doc/device-app.md` on a real camera.
///
/// Nothing here expects: every probe writes down what the phone did, and
/// the probes report reads the lines. A line `ACTION <name>` asks the host
/// for what a test cannot do from inside the app:
/// `integration_test/support/answer_actions.py` follows the output of the
/// run and answers `home`, `home-and-back` and `other-camera` by bringing
/// another app to the front and this one back, with `adb` on Android and
/// with `xcrun devicectl` on iOS, and `deny` with `adb`. The permission
/// probe runs only with `--dart-define=probePermissions=true`, after the
/// host took the permission away.
///
/// Run from the app's folder:
/// `flutter test integration_test/attempts_test.dart -d <device>`; an
/// iPhone needs `flutter run -t integration_test/attempts_test.dart`,
/// which `flutter test` cannot replace for a wireless one. The script's
/// docstring has its usage.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final phone = CameraPlatform.instance;
  late ProbeJournal journal;
  late RecordingCameraPlatform platform;
  late List<CameraDescription> cameras;
  final navigator = GlobalKey<NavigatorState>();
  var lifecycle = AppLifecycleState.resumed;
  final permissions = const bool.fromEnvironment('probePermissions');

  setUp(() async {
    // On iOS the device log drops lines under load; the file keeps them.
    journal = ProbeJournal(
      file: File('${Directory.systemTemp.path}/attempts-journal.txt'),
    );
    platform = RecordingCameraPlatform(phone, journal);
    CameraPlatform.instance = platform;
    cameras = await availableCameras();
    journal.note('cameras ${cameras.map((c) => c.lensDirection.name)}');
  });

  tearDown(() async {
    await platform.stopWatching();
    CameraPlatform.instance = phone;
  });

  /// Pumps for [time], writing down every exception the framework caught.
  ///
  /// A hidden app gets no frames, so a pump would wait for good; then the
  /// time passes without them.
  Future<void> settle(WidgetTester tester, Duration time) async {
    final end = DateTime.now().add(time);
    do {
      if (lifecycle == AppLifecycleState.resumed ||
          lifecycle == AppLifecycleState.inactive) {
        await tester.pump(const Duration(milliseconds: 50));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final caught = tester.takeException();
      if (caught != null) journal.note('exception ${'$caught'.split('\n')}');
    } while (DateTime.now().isBefore(end));
  }

  /// Waits without frames, which do not come while the app is hidden.
  Future<bool> waitFor(bool Function() done, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }

  Future<void> start(WidgetTester tester) async {
    final listener = AppLifecycleListener(
      onStateChange: (state) {
        lifecycle = state;
        journal.note('lifecycle ${state.name}');
      },
    );
    addTearDown(listener.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Center(child: Text('home'))),
      ),
    );
  }

  CameraController? cameraOnScreen() {
    final previews = find.byType(CameraPreview).evaluate();
    if (previews.isEmpty) return null;
    return (previews.last.widget as CameraPreview).controller;
  }

  /// Writes down what the screen shows.
  void look(WidgetTester tester) {
    final camera = cameraOnScreen();
    final value = camera?.value;
    final errors = find.byKey(const Key('error')).evaluate();
    journal.note(
      'screen ${value == null ? 'no preview' : 'preview '
                '${value.description.lensDirection.name} '
                'flash ${value.flashMode.name} '
                'recording ${value.isRecordingVideo} '
                'errorDescription ${value.errorDescription}'}'
      '${errors.isEmpty ? '' : ' error "${(errors.last.widget as Text).data}"'}',
    );
  }

  /// Opens [screen] over the home screen and waits for its preview.
  Future<void> open(
    WidgetTester tester,
    Widget Function(List<CameraDescription>, void Function(XFile)) screen,
  ) async {
    journal.note('screen open');
    // The route lives as long as the screen; the push is not awaited.
    // ignore: unawaited_futures
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: screen(cameras, journal.captured)),
      ),
    );
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (find.byType(CameraPreview).evaluate().isEmpty &&
        find.byKey(const Key('error')).evaluate().isEmpty &&
        DateTime.now().isBefore(end)) {
      await settle(tester, const Duration(milliseconds: 100));
    }
    look(tester);
  }

  /// Taps [button]. What the press starts runs in a zone that writes
  /// down its uncaught errors: on a phone an error the screen does not
  /// catch is a finding, not the end of the run.
  Future<void> tap(WidgetTester tester, String button) async {
    journal.note('tap $button');
    await runZonedGuarded(
      () => tester.tap(find.byKey(Key(button)).last),
      (e, _) => journal.note('uncaught ${'$e'.split('\n').take(2)}'),
    );
    await tester.pump();
  }

  Future<void> pop(WidgetTester tester) async {
    journal.note('screen pop');
    navigator.currentState!.pop();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    journal.note('finish');
    navigator.currentState!.popUntil((route) => route.isFirst);
    await settle(tester, const Duration(seconds: 2));
  }

  group('section 1, quick taps', () {
    testWidgets('three flash taps one frame apart', (tester) async {
      await start(tester);
      await open(tester, (c, f) => EagerButtons(cameras: c, onCaptured: f));
      journal.note('ACTION screenshot');
      await settle(tester, const Duration(seconds: 2));
      await tap(tester, 'flash');
      await tap(tester, 'flash');
      await tap(tester, 'flash');
      await settle(tester, const Duration(seconds: 2));
      look(tester);
      await finish(tester);
    });

    testWidgets('three flash taps 150 ms apart', (tester) async {
      await start(tester);
      await open(tester, (c, f) => EagerButtons(cameras: c, onCaptured: f));
      for (var i = 0; i < 3; i++) {
        await tap(tester, 'flash');
        await settle(tester, const Duration(milliseconds: 150));
      }
      await settle(tester, const Duration(seconds: 2));
      look(tester);
      await finish(tester);
    });

    testWidgets('a second shot during the first', (tester) async {
      await start(tester);
      await open(tester, (c, f) => EagerButtons(cameras: c, onCaptured: f));
      await tap(tester, 'shutter');
      await tap(tester, 'shutter');
      await settle(tester, const Duration(seconds: 4));
      look(tester);
      await finish(tester);
    });

    testWidgets('a switch of the camera during a shot', (tester) async {
      await start(tester);
      await open(tester, (c, f) => EagerButtons(cameras: c, onCaptured: f));
      await tap(tester, 'shutter');
      await tap(tester, 'switch');
      await settle(tester, const Duration(seconds: 5));
      look(tester);
      await tap(tester, 'shutter');
      await settle(tester, const Duration(seconds: 4));
      look(tester);
      await finish(tester);
    });
  });

  group('the torch, quick taps', () {
    /// Opens a [FlippingTorch] on the first camera, with no screen: the
    /// probe reads the calls of the platform, not the picture.
    Future<FlippingTorch> openTorch(WidgetTester tester) async {
      await start(tester);
      journal.note('torch open');
      final torch = FlippingTorch()..open(cameras.first);
      await waitFor(
        () => torch.currentState is Ready,
        const Duration(seconds: 20),
      );
      journal.note('state ${torch.currentState.runtimeType}');
      return torch;
    }

    void toggle(FlippingTorch torch) {
      journal.note('tap torch');
      torch.toggleTorch();
    }

    /// Lets the camera go once the torch is out: on the Galaxy a torch
    /// left lit would keep the plugin's flag up for the next probe.
    Future<void> close(WidgetTester tester, FlippingTorch torch) async {
      if (torch.currentState case Ready(torch: true)) {
        toggle(torch);
        await settle(tester, const Duration(seconds: 1));
      }
      journal.note('finish');
      journal.note('release ${(await torch.release().done).runtimeType}');
      await torch.close();
      await settle(tester, const Duration(seconds: 1));
    }

    testWidgets('off and on while the torch lights', (tester) async {
      final torch = await openTorch(tester);
      toggle(torch);
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (!journal.lines.any((l) => l.endsWith(' torch start')) &&
          DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      toggle(torch);
      toggle(torch);
      await settle(tester, const Duration(seconds: 2));
      journal.note('state torch ${(torch.currentState as Ready).torch}');
      await close(tester, torch);
    });

    testWidgets('on and off during a shot', (tester) async {
      final torch = await openTorch(tester);
      journal.note('tap shutter');
      torch.takePicture();
      toggle(torch);
      toggle(torch);
      await settle(tester, const Duration(seconds: 3));
      journal.note('state torch ${(torch.currentState as Ready).torch}');
      await close(tester, torch);
    });
  });

  group('section 2, a switch during a recording', () {
    testWidgets('a switch in the middle of a recording', (tester) async {
      await start(tester);
      await open(
        tester,
        (c, f) => SwitchWhileRecording(cameras: c, onCaptured: f),
      );
      await tap(tester, 'record');
      await settle(tester, const Duration(milliseconds: 1500));
      await tap(tester, 'switch');
      await settle(tester, const Duration(milliseconds: 1500));
      look(tester);
      await tap(tester, 'stop');
      await settle(tester, const Duration(seconds: 3));
      look(tester);
      await finish(tester);
    });

    testWidgets('a stop during the switch', (tester) async {
      await start(tester);
      await open(
        tester,
        (c, f) => SwitchWhileRecording(cameras: c, onCaptured: f),
      );
      await tap(tester, 'record');
      await settle(tester, const Duration(milliseconds: 1500));
      await tap(tester, 'switch');
      await tap(tester, 'stop');
      await settle(tester, const Duration(seconds: 4));
      look(tester);
      await finish(tester);
    });
  });

  group('section 3, leaving the screen', () {
    testWidgets('leaving during a shot', (tester) async {
      await start(tester);
      await open(tester, (c, f) => LeavingShutter(cameras: c, onCaptured: f));
      await tap(tester, 'shutter');
      await pop(tester);
      await settle(tester, const Duration(seconds: 4));
      await finish(tester);
    });

    // The trace of the page puts the two together: a shot, back, and the
    // screen opened again at once.
    testWidgets('leaving during a shot and opening again at once', (
      tester,
    ) async {
      await start(tester);
      await open(tester, (c, f) => LeavingShutter(cameras: c, onCaptured: f));
      await tap(tester, 'shutter');
      await pop(tester);
      await open(tester, (c, f) => LeavingShutter(cameras: c, onCaptured: f));
      await settle(tester, const Duration(seconds: 4));
      look(tester);
      journal.note('ACTION screenshot');
      await settle(tester, const Duration(seconds: 2));
      await tap(tester, 'shutter');
      await settle(tester, const Duration(seconds: 4));
      look(tester);
      await finish(tester);
    });

    testWidgets('opening again before the release', (tester) async {
      await start(tester);
      await open(tester, (c, f) => LeavingShutter(cameras: c, onCaptured: f));
      await pop(tester);
      await open(tester, (c, f) => LeavingShutter(cameras: c, onCaptured: f));
      await settle(tester, const Duration(seconds: 2));
      look(tester);
      journal.note('ACTION screenshot');
      await settle(tester, const Duration(seconds: 2));
      await tap(tester, 'shutter');
      await settle(tester, const Duration(seconds: 4));
      look(tester);
      await finish(tester);
    });
  });

  group('section 4, the app leaves the foreground', () {
    Future<void> leave(WidgetTester tester, String action) async {
      await start(tester);
      await open(tester, (c, f) => ReadmeLifecycle(cameras: c, onCaptured: f));
      await tap(tester, 'record');
      await settle(tester, const Duration(milliseconds: 1500));
      journal.note('ACTION $action');
      final left = await waitFor(
        () => lifecycle == AppLifecycleState.paused,
        const Duration(seconds: 30),
      );
      journal.note('left $left');
      final back = await waitFor(
        () => lifecycle == AppLifecycleState.resumed,
        const Duration(seconds: 30),
      );
      journal.note('back $back');
      await settle(tester, const Duration(seconds: 3));
      look(tester);
      journal.note('ACTION screenshot');
      await settle(tester, const Duration(seconds: 2));
      await tap(tester, 'stop');
      await settle(tester, const Duration(seconds: 2));
      look(tester);
      await tap(tester, 'record');
      await settle(tester, const Duration(seconds: 2));
      await tap(tester, 'stop');
      await settle(tester, const Duration(seconds: 2));
      look(tester);
      await finish(tester);
    }

    testWidgets(
      'home during a recording, back after seconds',
      (tester) => leave(tester, 'home'),
      skip: permissions,
    );

    testWidgets(
      'home during a recording, back at once',
      (tester) => leave(tester, 'home-and-back'),
      skip: permissions,
    );
  });

  group('section 5, losing the camera', () {
    testWidgets('another app takes the camera', (tester) async {
      await start(tester);
      await open(tester, (c, f) => ErrorListener(cameras: c, onCaptured: f));
      journal.note('ACTION other-camera');
      final left = await waitFor(
        () => lifecycle == AppLifecycleState.paused,
        const Duration(seconds: 30),
      );
      journal.note('left $left');
      final back = await waitFor(
        () => lifecycle == AppLifecycleState.resumed,
        const Duration(seconds: 30),
      );
      journal.note('back $back');
      await settle(tester, const Duration(seconds: 3));
      look(tester);
      await tap(tester, 'shutter');
      await settle(tester, const Duration(seconds: 4));
      look(tester);
      await finish(tester);
    }, skip: permissions);
  });

  group('section 6, no permission', () {
    testWidgets('opening without the permission, three times', (tester) async {
      await start(tester);
      for (var i = 0; i < 3; i++) {
        journal.note('ACTION deny');
        await open(
          tester,
          (c, f) => PermissionMessages(cameras: c, onCaptured: f),
        );
        await settle(tester, const Duration(seconds: 3));
        look(tester);
        await pop(tester);
        await settle(tester, const Duration(seconds: 1));
      }
      await finish(tester);
    }, skip: !permissions);
  });
}
