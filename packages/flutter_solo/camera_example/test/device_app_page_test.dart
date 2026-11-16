/// The page `doc/device-app.md` held to the app.
///
/// Every `dart` block of the page stands in the files of the app or of its
/// tests; every trace the page quotes is a run of lines of a [Journal] of
/// the same situation; every sentence a test checks is held to the page
/// through [_says]. A section adds its checks here: its answer held to
/// `lib/` with `under:` its heading, its first attempt to
/// `support/device_app_attempts.dart`; a block a later section changed
/// stands in `support/device_app_steps.dart`.
library;

import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
// Deprecated from Flutter 3.47 for package:material_ui, whose releases
// since 0.0.2 need Flutter 3.44; the floor is Flutter 3.38.1.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo_camera_example/camera_app.dart';
import 'package:flutter_solo_camera_example/camera_bloc.dart';
import 'package:flutter_solo_camera_example/camera_screen.dart';
import 'package:flutter_solo_camera_example/camera_session.dart';
import 'package:flutter_solo_camera_example/camera_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/camera_cases.dart';
import 'support/device_app_attempts.dart';
import 'support/fake_camera_platform.dart';
import 'support/journal.dart';
import 'support/page_code.dart';

const _doc = '../doc/device-app.md';

/// The earlier versions of the answers, for a section a later one changed.
const _steps = 'test/support/device_app_steps.dart';
const _intro = '# A device app';
const _rapid = '## Rapid taps';
const _first = '### The first attempt';
const _queue = '### One queue for the buttons';
const _torch = '## Rapid taps of the torch';
const _latest = '### The latest tap in the queue';
const _recording = '## A switch during a recording';
const _recordingQueue = '### The recording in the queue';
const _leaving = '## Leaving the screen';
const _release = '### A release the next screen waits for';
const _background = '## Going to the background';
const _suspend = '### A suspend in the queue';
const _losing = '## Losing the camera';
const _failure = '### A failure in the state';
const _denied = '## A denied permission';
const _explained = '### A denial the screen explains';
const _testing = '## Testing the app';
const _onBloc = '## The same screen on bloc';

/// The bloc of the section on bloc.
const _bloc = 'lib/camera_bloc.dart';

/// Home during a recording and back, as both phones report it.
const _homeAndBack = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

/// The Dart files a block of the page may stand in: the app, its tests and
/// their support, but for the helper that does the checking.
List<String> get _files => [
  for (final (directory, ending) in const [
    ('lib', '.dart'),
    ('test', '_test.dart'),
    ('test/support', '.dart'),
  ])
    for (final file in Directory(directory).listSync().whereType<File>())
      if (file.path.endsWith(ending) && !file.path.endsWith('page_code.dart'))
        file.path,
]..sort();

/// The parts of the page, each from a heading up to the next one.
List<String> get _parts =>
    File(_doc).readAsStringSync().split(RegExp('^(?=#)', multiLine: true));

/// The parts of the page by the section and the `###` heading they stand
/// under, the heading `null` for the part of the section itself: the
/// sections share their `###` headings, so a heading alone names none.
List<((String, String?), String)> get _placed {
  final placed = <((String, String?), String)>[];
  var section = '';
  for (final part in _parts) {
    final first = part.split('\n').first;
    if (first.startsWith('###')) {
      placed.add(((section, first), part));
    } else {
      section = first;
      placed.add(((section, null), part));
    }
  }
  return placed;
}

/// The part of the page under [heading] of [section], up to the next
/// heading; the part under [section] itself when no heading is named.
String _part(String section, [String? heading]) {
  for (final (place, part) in _placed) {
    if (place == (section, heading)) return part;
  }
  throw StateError('$_doc has no "${heading ?? section}" under "$section"');
}

/// The parts whose trace a test has read through [_traceUnder].
final _traced = <(String, String?)>{};

/// The lines of the one `text` block under [heading] of [section]: a trace
/// the page quotes.
List<String> _traceUnder(String section, [String? heading]) {
  _traced.add((section, heading));
  final blocks = RegExp(
    r'```text\n(.*?)\n```',
    dotAll: true,
  ).allMatches(_part(section, heading)).toList();
  if (blocks.length != 1) {
    throw StateError(
      '$_doc has ${blocks.length} traces under "${heading ?? section}" '
      'of "$section", not one',
    );
  }
  return blocks.single.group(1)!.split('\n');
}

/// Holds [part] to [sentence]: its prose, the breaks of its lines aside.
void _says(String part, String sentence) => expect(
  part
      .replaceAll(RegExp('```.*?```', dotAll: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' '),
  contains(sentence),
);

void main() {
  late FakeCameraPlatform platform;

  setUp(() {
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
  });
  tearDown(() => Solo.observer = null);

  group('the introduction', () {
    testWidgets('the trace is the opening of the camera', (tester) async {
      final journal = Journal(platform);
      Solo.observer = journal;
      final session = CameraSession(onCaptured: (XFile file) {});
      session.open();
      await tester.pump(platform.openTime);

      _says(
        _part(_intro),
        'A call on the camera is a line, or two for a call that takes '
        'time, where it starts and where it ends; a change of the state is '
        'a line too.',
      );
      expect(journal.lines, containsRun(_traceUnder(_intro)));
      final released = session.release().done;
      await tester.pump(platform.disposeTime);
      expect(await released, isA<Done<void>>());
      await session.close();
    });
  });

  group('rapid taps', () {
    testWidgets('the first attempt loses the shot to a switch', (tester) async {
      final journal = Journal(platform);
      final captured = <XFile>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EagerButtons(
              cameras: platform.cameras,
              onCaptured: captured.add,
            ),
          ),
        ),
      );
      await tester.pump(platform.openTime);
      await tester.tap(find.byKey(const Key('shutter')));
      await tester.tap(find.byKey(const Key('switch')));
      await tester.pump(const Duration(seconds: 1));

      expect(
        codeMissingFrom(
          _doc,
          'test/support/device_app_attempts.dart',
          under: _first,
        ),
        isEmpty,
      );
      expect(journal.lines, containsRun(_traceUnder(_rapid, _first)));
      expect(captured, isEmpty);
      const shown =
          'ImageCaptureException: androidx.camera.core.ImageCaptureException: '
          'Camera is closed.';
      expect(find.text(shown), findsOneWidget);
      _says(_part(_rapid, _first), shown);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(platform.disposeTime);
    });

    testWidgets('the queue keeps the shot and holds the switch', (
      tester,
    ) async {
      final journal = Journal(platform);
      Solo.observer = journal;
      final captured = <XFile>[];
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      session
        ..takePicture()
        ..takePicture()
        ..switchCamera();
      await tester.pump(platform.captureTime);
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);

      expect(
        codeMissingFrom(
          _doc,
          'lib/camera_session.dart',
          alsoIn: [_steps],
          under: _queue,
        ),
        isEmpty,
      );
      expect(journal.lines, containsRun(_traceUnder(_rapid, _queue)));
      expect(platform.log.where((l) => l == 'capture #1 start'), hasLength(1));
      expect(captured, hasLength(1));
      final released = session.release().done;
      await tester.pump(platform.disposeTime);
      expect(await released, isA<Done<void>>());
      await session.close();
    });
  });

  group('rapid taps of the torch', () {
    /// A shot with on and off tapped during it, then on, off and on, the
    /// last two while the torch lights.
    Future<void> tapTorch(
      WidgetTester tester, {
      required void Function() shoot,
      required void Function() toggle,
    }) async {
      shoot();
      toggle();
      toggle();
      await tester.pump(platform.captureTime);
      await tester.pump(platform.torchTime);
      toggle();
      await tester.pump(platform.torchTime ~/ 2);
      toggle();
      toggle();
      await tester.pump(platform.torchTime);
      await tester.pump(platform.torchTime);
    }

    testWidgets('the first attempt blinks the torch and flashes it', (
      tester,
    ) async {
      final journal = Journal(platform);
      Solo.observer = journal;
      final torch = FlippingTorch()..open(platform.cameras.first);
      await tester.pump(platform.openTime);
      await tapTorch(
        tester,
        shoot: torch.takePicture,
        toggle: torch.toggleTorch,
      );

      expect(
        codeMissingFrom(
          _doc,
          'test/support/device_app_attempts.dart',
          under: _first,
        ),
        isEmpty,
      );
      expect(journal.lines, containsRun(_traceUnder(_torch, _first)));
      expect(platform.torchOn(1), isTrue);
      final released = torch.release().done;
      await tester.pump(platform.disposeTime);
      expect(await released, isA<Done<void>>());
      await torch.close();
    });

    testWidgets('the latest tap calls once, or not at all', (tester) async {
      final journal = Journal(platform);
      Solo.observer = journal;
      final session = CameraSession(onCaptured: (XFile file) {});
      session.open();
      await tester.pump(platform.openTime);
      await tapTorch(
        tester,
        shoot: session.takePicture,
        toggle: session.toggleTorch,
      );

      expect(
        codeMissingFrom(
          _doc,
          'lib/camera_session.dart',
          alsoIn: ['lib/camera_state.dart', 'lib/camera_screen.dart'],
          under: _latest,
        ),
        isEmpty,
      );
      expect(journal.lines, containsRun(_traceUnder(_torch, _latest)));
      expect(platform.log.where((line) => line.startsWith('flash ')), [
        'flash #1 torch start',
        'flash #1 torch end',
      ]);
      expect((session.currentState as Ready).torch, isTrue);
      _says(
        _part(_torch, _latest),
        'The two taps during the shot leave no line: off took the place of '
        'on in the queue and found the torch off.',
      );
      final released = session.release().done;
      await tester.pump(platform.disposeTime);
      expect(await released, isA<Done<void>>());
      await session.close();
    });

    testWidgets('a tap dropped at its start leaves the next tap its target', (
      tester,
    ) async {
      final session = CameraSession(onCaptured: (XFile file) {});
      session.open();
      await tester.pump(platform.openTime);
      session
        ..startRecording()
        ..toggleTorch();
      await tester.pump(platform.recordStartTime ~/ 2);
      platform.failFromOutside(1, FakeCameraPlatform.takenOnAndroid);
      await tester.pump(platform.recordStartTime);
      await tester.pump(platform.disposeTime);
      expect(session.currentState, isA<Broken>());
      session.open();
      await tester.pump(platform.openTime);
      session.toggleTorch();
      await tester.pump(platform.torchTime);

      expect(platform.log, isNot(contains('flash #1 torch start')));
      expect(platform.log, contains('flash #2 torch end'));
      expect((session.currentState as Ready).torch, isTrue);
      _says(
        _part(_torch, _latest),
        '`whenFinished` forgets the target once the job of the latest tap has '
        'ended: when it has run, and when it was dropped at its start because '
        'the camera was no longer `Ready`.',
      );
      final released = session.release().done;
      await tester.pump(platform.disposeTime);
      expect(await released, isA<Done<void>>());
      await session.close();
    });
  });

  group('a switch during a recording', () {
    testWidgets('the first attempt loses the recording to a switch', (
      tester,
    ) async {
      platform.phone = FakePhone.iphone;
      final journal = Journal(platform);
      final captured = <XFile>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwitchWhileRecording(
              cameras: platform.cameras,
              onCaptured: captured.add,
            ),
          ),
        ),
      );
      await tester.pump(platform.openTime);
      await tester.tap(find.byKey(const Key('record')));
      await tester.pump(platform.recordStartTime ~/ 2);
      await tester.tap(find.byKey(const Key('switch')));
      await tester.pump(platform.recordStartTime);
      await tester.tap(find.byKey(const Key('stop')));
      await tester.pump(platform.stopTime);

      expect(
        codeMissingFrom(
          _doc,
          'test/support/device_app_attempts.dart',
          under: _first,
        ),
        isEmpty,
      );
      expect(journal.lines, containsRun(_traceUnder(_recording, _first)));
      expect(captured, isEmpty);
      const shown = 'Error -1008: Video is not recording!';
      expect(find.text(shown), findsOneWidget);
      _says(_part(_recording, _first), shown);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(platform.disposeTime);
    });

    testWidgets('the queue holds the switch and the stop', (tester) async {
      platform.phone = FakePhone.iphone;
      final journal = Journal(platform);
      Solo.observer = journal;
      final captured = <XFile>[];
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      session
        ..startRecording()
        ..switchCamera();
      await tester.pump(platform.recordStartTime);
      await tester.pump(platform.switchTime ~/ 2);
      session.stopRecording();
      await tester.pump(platform.switchTime);
      await tester.pump(platform.stopTime);

      expect(
        codeMissingFrom(
          _doc,
          'lib/camera_session.dart',
          alsoIn: [_steps],
          under: _recordingQueue,
        ),
        isEmpty,
      );
      expect(
        journal.lines,
        containsRun(_traceUnder(_recording, _recordingQueue)),
      );
      expect(captured, hasLength(1));
      expect(journal.lines, isNot(contains(startsWith('dispose'))));
      _says(
        _part(_recording, _recordingQueue),
        'The trace has no `dispose` line: the switch releases no camera, and '
        'the recording goes on from the front one. The stop starts once the '
        'switch has ended and gives one file.',
      );
      final released = session.release().done;
      await tester.pump(platform.disposeTime);
      expect(await released, isA<Done<void>>());
      await session.close();
    });
  });

  group('leaving the screen', () {
    testWidgets('the first attempt loses the shot and opens two cameras', (
      tester,
    ) async {
      // A picture on the Galaxy takes from 0.5 to 3.9 s, longer than the
      // pop of a route takes to remove the screen.
      platform.captureTime = const Duration(seconds: 1);
      final journal = Journal(platform);
      final captured = <XFile>[];
      final uncaught = <Object>[];
      final navigator = GlobalKey<NavigatorState>();
      Route<void> screen() => MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: LeavingShutter(
            cameras: platform.cameras,
            onCaptured: captured.add,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox.expand()),
      );
      // The routes live as long as their screens; nothing awaits them.
      // ignore: unawaited_futures
      navigator.currentState!.push(screen());
      await tester.pumpAndSettle();
      await tester.pump(platform.openTime);
      // The shot throws once the release takes the camera from under it,
      // in the zone the tap ran in.
      await runZonedGuarded(
        () => tester.tap(find.byKey(const Key('shutter'))),
        (e, _) => uncaught.add(e),
      );
      navigator.currentState!.pop();
      // ignore: unawaited_futures
      navigator.currentState!.push(screen());
      await tester.pumpAndSettle();
      await tester.pump(platform.captureTime);

      expect(
        codeMissingFrom(
          _doc,
          'test/support/device_app_attempts.dart',
          under: _first,
        ),
        isEmpty,
      );
      expect(journal.lines, containsRun(_traceUnder(_leaving, _first)));
      expect(captured, isEmpty);
      // The screen caught the `CameraException` of the lost shot.
      expect(uncaught, isEmpty);
      _says(
        _part(_leaving, _first),
        'the picture fails with `Camera is closed.` as the second camera is '
        'created. The fake platform does the same. The screen catches that '
        '`CameraException`, though it has left by then.',
      );
      expect(platform.hasPicture(2), isFalse);
      navigator.currentState!.pop();
      await runZonedGuarded(() async {
        await tester.pumpAndSettle();
        await tester.pump(platform.disposeTime);
      }, (e, _) => uncaught.add(e));
      expect('${uncaught.last}', contains('IllegalStateException'));
      _says(
        _part(_leaving, _first),
        'its own release throws `IllegalStateException`.',
      );
      expect(platform.openCameras, 1);
    });

    testWidgets('the first attempt, not opened again, throws in debug', (
      tester,
    ) async {
      platform.captureTime = const Duration(seconds: 1);
      final captured = <XFile>[];
      final uncaught = <Object>[];
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox.expand()),
      );
      // The route lives as long as its screen; nothing awaits it.
      // ignore: unawaited_futures
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: LeavingShutter(
              cameras: platform.cameras,
              onCaptured: captured.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(platform.openTime);
      // The shot throws once the release takes the camera from under it,
      // in the zone the tap ran in.
      await runZonedGuarded(
        () => tester.tap(find.byKey(const Key('shutter'))),
        (e, _) => uncaught.add(e),
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pump(platform.captureTime);

      expect(
        platform.log,
        containsAllInOrder([
          'capture #1 start',
          'dispose #1 start',
          'capture #1 failed',
          'dispose #1 end',
        ]),
      );
      expect(platform.log, isNot(contains(startsWith('create back #2'))));
      expect(captured, isEmpty);
      const thrown = 'A CameraController was used after being disposed.';
      expect(uncaught.map((e) => '$e'), [contains(thrown)]);
      _says(
        _part(_leaving, _first),
        'When the screen is not opened again, the Galaxy ends the picture at '
        'the release instead.',
      );
      _says(_part(_leaving, _first), thrown);
    });

    testWidgets('the release waits for the shot, the next screen for it', (
      tester,
    ) async {
      platform.captureTime = const Duration(seconds: 1);
      final journal = Journal(platform);
      Solo.observer = journal;
      final shutter = find.byKey(const Key('shutter'));
      final openCamera = find.byKey(const Key('open-camera'));
      // A scope of scopo builds its ready branch some frames after its
      // initialization ends.
      Future<void> untilShutter() async {
        for (var i = 0; i < 50 && shutter.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await tester.pumpWidget(const CameraApp());
      await tester.tap(openCamera);
      await tester.pumpAndSettle();
      await untilShutter();
      await tester.tap(shutter);
      await tester.pump();
      await tester.pageBack();
      await tester.pump();
      await tester.tap(openCamera);
      await tester.pumpAndSettle();
      await tester.pump(platform.captureTime);
      await tester.pump(platform.disposeTime);
      await untilShutter();

      expect(
        codeMissingFrom(
          _doc,
          'lib/camera_screen.dart',
          alsoIn: [
            'lib/camera_app.dart',
            'lib/camera_session.dart',
            'lib/camera_state.dart',
          ],
          under: _release,
        ),
        isEmpty,
      );
      expect(journal.lines, containsRun(_traceUnder(_leaving, _release)));
      expect(platform.openCameras, 1);
      expect(platform.hasPicture(2), isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pump(platform.disposeTime);
      expect(find.byKey(const Key('last-shot')), findsOneWidget);
      _says(
        _part(_leaving, _release),
        'The release starts once the picture has ended, and the picture '
        'goes up to the home screen.',
      );
      expect(platform.openCameras, 0);
    });

    testWidgets('a recording stops before the release and reaches home', (
      tester,
    ) async {
      final captured = <XFile>[];
      final session = CameraSession(onCaptured: captured.add);
      session
        ..open()
        ..startRecording();
      await tester.pump(platform.openTime);
      await tester.pump(platform.recordStartTime);
      final released = session.release().done;
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);

      expect(await released, isA<Done<void>>());
      expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
      expect(
        platform.log,
        containsAllInOrder([
          'stop #1 start',
          'record #1 end',
          'dispose #1 start',
        ]),
      );
      _says(
        _part(_leaving, _release),
        'A recording under way stops first, and the video goes up to the home '
        'screen.',
      );
      expect(releaseStopTimeout, const Duration(seconds: 3));
      _says(
        _part(_leaving, _release),
        '`stopBeforeRelease` gives up after 3 s,',
      );
      await session.close();
    });

    testWidgets('a close during the stop of a release waits for it', (
      tester,
    ) async {
      final captured = <XFile>[];
      final session = CameraSession(onCaptured: captured.add);
      session
        ..open()
        ..startRecording();
      await tester.pump(platform.openTime);
      await tester.pump(platform.recordStartTime);
      final released = session.release().done;
      await tester.pump(platform.stopTime ~/ 2);
      final closed = session.close();
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);
      await closed;

      expect(await released, isA<Cancelled>());
      expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
      expect(
        platform.log,
        containsAllInOrder(['record #1 end', 'dispose #1 end']),
      );
      expect(platform.openCameras, 0);
      _says(
        _part(_leaving, _release),
        'a `close()` during the stop cancels the job only once the camera is '
        'released.',
      );
    });

    testWidgets('a stop out of time leaves the torch and releases', (
      tester,
    ) async {
      final session = CameraSession(onCaptured: (XFile file) {});
      session
        ..open()
        ..toggleTorch()
        ..startRecording();
      await tester.pump(platform.openTime);
      await tester.pump(platform.torchTime);
      await tester.pump(platform.recordStartTime);
      platform
        ..hangStop = true
        ..hangFlash = true;
      final released = session.release().done;
      await tester.pump(releaseStopTimeout);
      await tester.pump(platform.disposeTime);

      // Checked before the wait: a release that hangs would never end it.
      expect(platform.log, contains('dispose #1 end'));
      expect(await released, isA<Done<void>>());
      expect(
        platform.log.skipWhile((l) => l != 'stop #1 start'),
        isNot(contains(startsWith('flash'))),
      );
      _says(
        _part(_leaving, _release),
        'After a stop that ran out of time the release leaves a lit torch '
        'alone:',
      );
      await session.close();
    });
  });

  group('going to the background', () {
    for (final phone in FakePhone.values) {
      testWidgets('the first attempt loses the recording (${phone.name})', (
        tester,
      ) async {
        platform.phone = phone;
        final journal = Journal(platform);
        final captured = <XFile>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReadmeLifecycle(
                cameras: platform.cameras,
                onCaptured: captured.add,
              ),
            ),
          ),
        );
        await tester.pump(platform.openTime);
        await tester.tap(find.byKey(const Key('record')));
        await tester.pump(platform.recordStartTime);
        for (final state in _homeAndBack) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump(platform.disposeTime);
        }
        await tester.pump(platform.openTime);
        await tester.tap(find.byKey(const Key('stop')));
        await tester.pump(platform.stopTime);

        expect(
          codeMissingFrom(
            _doc,
            'test/support/device_app_attempts.dart',
            under: _first,
          ),
          isEmpty,
        );
        expect(journal.lines, containsRun(_traceUnder(_background, _first)));
        expect(captured, isEmpty);
        expect(platform.log, isNot(contains(startsWith('stop'))));
        _says(
          _part(_background, _first),
          'The trace has no `stop` line: the recording does not reach the '
          'home screen.',
        );
        expect(platform.hasPicture(2), isTrue);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(platform.disposeTime);
      });
    }

    for (final phone in FakePhone.values) {
      testWidgets('the suspend stops the recording, the resume waits '
          '(${phone.name})', (tester) async {
        platform.phone = phone;
        final journal = Journal(platform);
        Solo.observer = journal;
        final record = find.byKey(const Key('record'));
        // A scope of scopo builds its ready branch some frames after its
        // initialization ends.
        Future<void> untilRecord() async {
          for (var i = 0; i < 50 && record.evaluate().isEmpty; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        await tester.pumpWidget(const CameraApp());
        await tester.tap(find.byKey(const Key('open-camera')));
        await tester.pumpAndSettle();
        await untilRecord();
        await tester.tap(record);
        await tester.pump(platform.recordStartTime);
        _homeAndBack.forEach(tester.binding.handleAppLifecycleStateChanged);
        await tester.pump(platform.stopTime);
        await tester.pump(platform.disposeTime);
        await tester.pump(platform.openTime);
        await untilRecord();

        expect(
          codeMissingFrom(
            _doc,
            'lib/camera_session.dart',
            alsoIn: ['lib/camera_screen.dart'],
            under: _suspend,
          ),
          isEmpty,
        );
        expect(journal.lines, containsRun(_traceUnder(_background, _suspend)));
        expect(platform.openCameras, 1);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pump(platform.disposeTime);
        final shown = tester.widget<Image>(find.byKey(const Key('last-shot')));
        expect((shown.image as FileImage).file.path, '/fake/video-1.mp4');
        _says(
          _part(_background, _suspend),
          'The stop comes before the release, and the recording goes up to '
          'the home screen. The camera opens again once the release has '
          'ended:',
        );
        // Coming back at once draws frames during the release, and the
        // emit after the release would leave the preview on them.
        expect(tester.takeException(), isNull);
        _says(
          _part(_background, _suspend),
          '`suspend()` emits `Closed` before the release starts, and the screen '
          'takes the preview down: a preview built on a controller that is being '
          'released throws `buildPreview() was called on a disposed '
          'CameraController.`',
        );
        expect(platform.openCameras, 0);
      });
    }

    testWidgets('a permission dialog during the opening releases nothing', (
      tester,
    ) async {
      final session = CameraSession(onCaptured: (XFile file) {});
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CameraView(session: session),
        ),
      );
      session.open();
      await tester.pump(platform.openTime ~/ 2);
      // The lifecycle of a permission dialog on both phones.
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(platform.openTime);
      await tester.pump(platform.disposeTime);

      expect(platform.log, isNot(contains(startsWith('dispose'))));
      expect(platform.openCameras, 1);
      _says(
        _part(_background, _suspend),
        'A dialog that comes while the camera opens releases nothing, and '
        'the camera opens.',
      );
      await tester.pumpWidget(const SizedBox());
      final released = session.release().done;
      await tester.pump(platform.disposeTime);
      expect(await released, isA<Done<void>>());
      await session.close();
    });
  });

  group('losing the camera', () {
    testWidgets('the first attempt keeps the first error, misses the second', (
      tester,
    ) async {
      final journal = Journal(platform);
      final captured = <XFile>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorListener(
              cameras: platform.cameras,
              onCaptured: captured.add,
            ),
          ),
        ),
      );
      await tester.pump(platform.openTime);
      platform.failFromOutside(1, FakeCameraPlatform.takenOnAndroid);
      await tester.pump();
      await tester.tap(find.byKey(const Key('shutter')));
      await tester.pump(platform.captureTime);
      platform.failFromOutside(1, 'A second failure.');
      await tester.pump();

      expect(
        codeMissingFrom(
          _doc,
          'test/support/device_app_attempts.dart',
          under: _first,
        ),
        isEmpty,
      );
      expect(journal.lines, containsRun(_traceUnder(_losing, _first)));
      expect(captured, hasLength(1));
      final shown = 'Camera error ${FakeCameraPlatform.takenOnAndroid}';
      expect(find.text(shown), findsOneWidget);
      _says(
        _part(_losing, _first),
        'The picture comes through, and the screen still says `$shown` The '
        'second error leaves no mark:',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(platform.disposeTime);
    });

    testWidgets('the failure is the state, and retry opens again', (
      tester,
    ) async {
      final journal = Journal(platform);
      Solo.observer = journal;
      final retry = find.byKey(const Key('retry'));
      final shutter = find.byKey(const Key('shutter'));
      // A scope of scopo builds its ready branch some frames after its
      // initialization ends.
      Future<void> untilShutter() async {
        for (var i = 0; i < 50 && shutter.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await tester.pumpWidget(const CameraApp());
      await tester.tap(find.byKey(const Key('open-camera')));
      await tester.pumpAndSettle();
      await untilShutter();
      platform.failFromOutside(1, FakeCameraPlatform.takenOnAndroid);
      // The event comes after the frame it is sent in.
      await tester.pump();
      await tester.pump();
      expect(
        find.text('The camera failed: ${FakeCameraPlatform.takenOnAndroid}'),
        findsOneWidget,
      );
      await tester.tap(retry);
      await tester.tap(retry);
      await tester.pump(platform.disposeTime);
      await tester.pump(platform.openTime);
      await untilShutter();

      expect(
        codeMissingFrom(
          _doc,
          'lib/camera_session.dart',
          alsoIn: ['lib/camera_screen.dart', 'lib/camera_state.dart', _steps],
          under: _failure,
        ),
        isEmpty,
      );
      expect(journal.lines, containsRun(_traceUnder(_losing, _failure)));
      expect(platform.openCameras, 1);
      _says(
        _part(_losing, _failure),
        'The opening starts once the lost camera is released, and the second '
        'tap leaves no line.',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pump(platform.disposeTime);
      expect(platform.openCameras, 0);
    });

    testWidgets('a recording on a lost camera stops and reaches home', (
      tester,
    ) async {
      final captured = <XFile>[];
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      session.startRecording();
      await tester.pump(platform.recordStartTime);
      platform.failFromOutside(1, FakeCameraPlatform.takenOnAndroid);
      await tester.pump();
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);

      expect(session.currentState, isA<Broken>());
      expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
      expect(
        platform.log,
        containsAllInOrder([
          'stop #1 start',
          'record #1 end',
          'dispose #1 start',
        ]),
      );
      _says(
        _part(_losing, _failure),
        'A recording under way when the camera is lost stops before the '
        'release, and the video goes to the home screen.',
      );
      _says(
        _part(_losing, _failure),
        '`_letGo` stops the recording with `stopBeforeRelease`, the stop of '
        '`release()`,',
      );
      await session.close();
    });

    testWidgets('a close during the stop of a lost camera waits for it', (
      tester,
    ) async {
      final captured = <XFile>[];
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      session.startRecording();
      await tester.pump(platform.recordStartTime);
      platform.failFromOutside(1, FakeCameraPlatform.takenOnAndroid);
      await tester.pump();
      await tester.pump(platform.stopTime ~/ 2);
      final closed = session.close();
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);
      await closed;

      expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
      expect(
        platform.log,
        containsAllInOrder(['record #1 end', 'dispose #1 end']),
      );
      expect(platform.openCameras, 0);
      _says(
        _part(_losing, _failure),
        'a `close()` during the stop cancels the job only once the camera is '
        'released,',
      );
    });

    testWidgets('a stop the loss cuts short still reaches home', (
      tester,
    ) async {
      final captured = <XFile>[];
      final session = CameraSession(onCaptured: captured.add);
      session.open();
      await tester.pump(platform.openTime);
      session.startRecording();
      await tester.pump(platform.recordStartTime);
      final stopped = session.stopRecording().done;
      await tester.pump(platform.stopTime ~/ 2);
      platform.failFromOutside(1, FakeCameraPlatform.takenOnAndroid);
      await tester.pump();
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);

      expect(await stopped, isA<Cancelled>());
      expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
      _says(
        _part(_losing, _failure),
        '`join` hands that file to `discard`, and the video still reaches '
        'the home screen.',
      );
      await session.close();
    });

    testWidgets('a stop the loss cuts short reaches home on bloc', (
      tester,
    ) async {
      final captured = <XFile>[];
      final bloc = CameraBloc(onCaptured: captured.add)
        ..add(const OpenCamera());
      await tester.pump(platform.openTime);
      bloc.add(const StartRecording());
      await tester.pump(platform.recordStartTime);
      bloc.add(const StopRecording());
      await tester.pump(platform.stopTime ~/ 2);
      platform.failFromOutside(1, FakeCameraPlatform.takenOnAndroid);
      await tester.pump();
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);

      expect(bloc.state, isA<Broken>());
      expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
      _says(
        _part(_onBloc),
        '`_stopRecording` and `_suspend` hand it to `onCaptured` whatever '
        'the state.',
      );
      final closed = bloc.close();
      await letCloseEnd(tester);
      await closed;
    });

    testWidgets("the Galaxy's closing events are not a failure", (
      tester,
    ) async {
      final session = CameraSession(onCaptured: (XFile file) {});
      session.open();
      await tester.pump(platform.openTime);
      session
        ..startRecording()
        ..switchCamera()
        ..stopRecording();
      await tester.pump(platform.recordStartTime);
      await tester.pump(platform.switchTime);
      await tester.pump(platform.stopTime);

      expect(session.currentState, isA<Ready>());
      _says(
        _part(_losing, _failure),
        'The session does not listen to `onCameraClosing`. A Galaxy A55 sends '
        'a closing event when a recording starts, at a switch during a '
        'recording and after a stop,',
      );
      final released = session.release().done;
      await tester.pump(platform.disposeTime);
      expect(await released, isA<Done<void>>());
      await session.close();
    });

    testWidgets('a failed stop is a failure, and the camera is let go', (
      tester,
    ) async {
      platform.failStop = CameraException('stopFailed', 'The stop failed.');
      final session = CameraSession(onCaptured: (XFile file) {});
      session.open();
      await tester.pump(platform.openTime);
      session.startRecording();
      await tester.pump(platform.recordStartTime);
      final stopped = session.stopRecording().done;
      await tester.pump(platform.stopTime);
      await tester.pump(platform.disposeTime);

      expect(session.currentState, isA<Broken>());
      expect(await stopped, isA<Done<XFile?>>());
      expect(platform.openCameras, 0);
      _says(
        _part(_losing, _failure),
        'once it has emitted `Broken` its own calls through `ctx` give up '
        'with `Cancelled`, so the release goes to a job of its own here too.',
      );
      await session.close();
    });
  });

  group('a denied permission', () {
    final retry = find.byKey(const Key('retry'));

    /// Opens the first attempt twice, leaving it in between, with the
    /// platform denying the camera with [denials] in turn; gives what the
    /// screen said each time.
    Future<List<String>> openTwice(
      WidgetTester tester,
      List<CameraException> denials,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox.expand()),
      );
      final shown = <String>[];
      for (final denial in denials) {
        platform.failCreate = denial;
        // The route lives as long as its screen; nothing awaits it.
        // ignore: unawaited_futures
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: PermissionMessages(
                cameras: platform.cameras,
                onCaptured: (XFile file) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        shown.add(tester.widget<Text>(find.byKey(const Key('error'))).data!);
        expect(find.byType(TextButton), findsNothing);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await tester.pump(platform.disposeTime);
      }
      return shown;
    }

    testWidgets('the first attempt says the same twice (Galaxy)', (
      tester,
    ) async {
      final journal = Journal(platform);
      // The Galaxy denies with the same code after "don't ask again".
      final shown = await openTwice(tester, [
        FakeCameraPlatform.deniedOnAndroid,
        FakeCameraPlatform.deniedOnAndroid,
      ]);

      expect(
        codeMissingFrom(
          _doc,
          'test/support/device_app_attempts.dart',
          under: _first,
        ),
        isEmpty,
      );
      expect(journal.lines, containsRun(_traceUnder(_denied, _first)));
      expect(shown, [
        'You have denied camera access.',
        'You have denied camera access.',
      ]);
      _says(
        _part(_denied, _first),
        'Both openings say `You have denied camera access.`, and the screen '
        'has nothing that asks again:',
      );
      _says(
        _part(_denied, _first),
        'and the controller sends the platform `dispose` for the camera `-1`:',
      );
    });

    testWidgets('the first attempt sends the iPhone to Settings', (
      tester,
    ) async {
      platform.phone = FakePhone.iphone;
      final shown = await openTwice(tester, [
        FakeCameraPlatform.deniedOnIphone,
        FakeCameraPlatform.deniedWithoutPromptOnIphone,
      ]);

      expect(shown.last, 'Please go to Settings app to enable camera access.');
      _says(
        _part(_denied, _first),
        'On an iPhone 13 mini the second opening says '
        '`Please go to Settings app to enable camera access.`',
      );
    });

    testWidgets('the screen explains, and retry asks again (iPhone)', (
      tester,
    ) async {
      platform
        ..phone = FakePhone.iphone
        ..failCreate = FakeCameraPlatform.deniedOnIphone;
      final journal = Journal(platform);
      Solo.observer = journal;
      final session = CameraSession(onCaptured: (XFile file) {});
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CameraView(session: session),
        ),
      );
      session.open();
      await tester.pump();
      await tester.pump();
      expect(find.text('Allow the app to use the camera.'), findsOneWidget);
      platform.failCreate = FakeCameraPlatform.deniedWithoutPromptOnIphone;
      await tester.tap(retry);
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Allow the app to use the camera in Settings.'),
        findsOneWidget,
      );
      expect(retry, findsNothing);
      await tester.pumpWidget(const SizedBox());
      final released = session.release().done;
      await tester.pump(platform.disposeTime);
      expect(await released, isA<Done<void>>());
      await session.close();

      expect(
        codeMissingFrom(
          _doc,
          'lib/camera_session.dart',
          alsoIn: ['lib/camera_screen.dart'],
          under: _explained,
        ),
        isEmpty,
      );
      expect(journal.lines, containsRun(_traceUnder(_denied, _explained)));
      expect(platform.log, isNot(contains(startsWith('dispose'))));
      _says(
        _part(_denied, _explained),
        'The trace has no `dispose` line: no camera was created, and the '
        'release of the screen finds none.',
      );
    });

    testWidgets("retry on the Galaxy after \"don't ask again\" asks nothing", (
      tester,
    ) async {
      platform.failCreate = FakeCameraPlatform.deniedOnAndroid;
      final session = CameraSession(onCaptured: (XFile file) {});
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CameraView(session: session),
        ),
      );
      session.open();
      await tester.pump();
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        await tester.tap(retry);
        await tester.pump();
        await tester.pump();
        expect(
          session.currentState,
          isA<Denied>().having((s) => s.code, 'code', 'CameraAccessDenied'),
        );
        expect(find.text('Allow the app to use the camera.'), findsOneWidget);
        expect(retry, findsOneWidget);
      }
      expect(platform.log, everyElement('create back failed'));
      _says(
        _part(_denied, _explained),
        "After \"deny and don't ask again\" Retry asks nothing: the opening "
        'fails without a dialog with the same code, and the screen comes '
        'back with the same text and the same button.',
      );
      await tester.pumpWidget(const SizedBox());
      final released = session.release().done;
      await tester.pump(platform.disposeTime);
      expect(await released, isA<Done<void>>());
      await session.close();
    });
  });

  group('testing the app', () {
    test('the blocks are the fake and the cases of the app', () {
      expect(
        codeMissingFrom(
          _doc,
          'test/support/camera_cases.dart',
          alsoIn: [
            'test/support/fake_camera_platform.dart',
            'test/camera_session_test.dart',
          ],
          under: _testing,
        ),
        isEmpty,
      );
      _says(
        _part(_testing),
        "On the Galaxy's a `dispose` under a picture loses the picture, with "
        "the line `capture #N failed`; on the iPhone's the `dispose` waits "
        'for the picture.',
      );
    });
  });

  group('the same screen on bloc', () {
    /// The rows of the table.
    List<String> rows() {
      return [
        '| Rapid taps | `on<CameraCommand>` with `sequential()`; `_shooting`, '
            'set in `add` | the queue of `Solo`; `Policy.droppable` on the '
            'key of `takePicture` | nothing more |',
        '| Rapid taps of the torch | the target and the number of the tap, '
            'set in `add`; `SetTorch`, which the handler skips when a later '
            'tap has passed it | `Policy.keepLatest` on the key of '
            '`toggleTorch`; the target taken at the tap; `whenFinished` | '
            'nothing more |',
        '| A switch during a recording | the same handler | the same queue '
            '| nothing more |',
        '| Leaving the screen | `Release` with a `Completer`; `_letGo` with '
            '`leaving`; `AsyncDataScope` with a `scopeKey`; '
            '`BlocProvider.value` | '
            '`release()`; `AsyncDataScope` with a `scopeKey` | bloc: '
            '`letCloseEnd`, for `close()` |',
        '| Going to the background | `Suspend` and `Resume` in the queue | '
            '`suspend()` and `resume()` in the queue | for a stop that '
            'breaks, bloc: the bloc made in `runZonedGuarded`; solo: '
            '`Solo.unansweredHandler` |',
        '| Losing the camera | `on<CameraLost>` of its own; '
            'a check of the state after every `await`; `LetGo` in the '
            'queue; `_camera` and `_lost`; `close()` that cancels `_errors` | '
            '`externalSetState`; `ctx.join` at every `await` of a command on '
            '`Ready`; `_letGo` with `first: true`; `onClose` that cancels '
            '`_errors` | for a failed switch during a recording, bloc: the '
            'bloc made in `runZonedGuarded`; solo: `Solo.unansweredHandler` |',
        '| A denied permission | `_initialize`, which awaits `dispose` '
            'itself | `_initialize`, with `_letGo` | nothing more |',
      ];
    }

    test('the blocks are the bloc', () {
      expect(
        codeMissingFrom(
          _doc,
          _bloc,
          alsoIn: ['test/support/camera_cases.dart'],
          under: _onBloc,
        ),
        isEmpty,
      );
    });

    test('the table holds every situation', () {
      for (final row in rows()) {
        _says(_part(_onBloc), row);
      }
    });

    test('every name in the table stands in the code', () {
      final code = [
        _bloc,
        'test/bloc_camera_test.dart',
        'lib/camera_session.dart',
        'lib/camera_screen.dart',
        'test/camera_session_test.dart',
        'test/support/camera_cases.dart',
      ].map((file) => File(file).readAsStringSync()).join('\n');
      for (final row in rows()) {
        for (final name in RegExp('`([^`]+)`').allMatches(row)) {
          expect(code, contains(name.group(1)), reason: row);
        }
      }
    });

    testWidgets('close ends after a turn of the real event loop', (
      tester,
    ) async {
      final bloc = CameraBloc(onCaptured: (XFile file) {});
      var closed = false;
      unawaited(bloc.close().then((_) => closed = true));
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(seconds: 1));
      }
      // The clock alone does not end it.
      expect(closed, isFalse);
      await letCloseEnd(tester);
      await tester.pump();

      expect(closed, isTrue);
      _says(
        _part(_onBloc),
        'Under `testWidgets` that `close()` ends only after a turn of the '
        'real event loop.',
      );
    });

    test(
      'a cancel with nothing to wait for answers with one shared future',
      () {
        // The future the SDK made in the root zone, the same for every such
        // subscription.
        final first = StreamController<int>.broadcast().stream.listen(null);
        final second = StreamController<int>.broadcast().stream.listen(null);
        expect(identical(first.cancel(), second.cancel()), isTrue);
        _says(
          _part(_onBloc),
          'a subscription with nothing to wait for answers with a future the '
          'SDK made in the root zone.',
        );
      },
    );
  });

  group('the page', () {
    test('every block of the page stands in the app or its tests', () {
      expect(
        codeMissingFrom(_doc, 'lib/camera_session.dart', alsoIn: _files),
        isEmpty,
      );
    });

    test('no stray fences', () => expect(strayFences(_doc), ['```sh']));

    // Runs last: the tests above have read their traces by now.
    test('every trace of the page is held to a run', () {
      expect(_traced, {
        for (final (place, part) in _placed)
          if (part.contains('```text\n')) place,
      });
    });
  });
}
