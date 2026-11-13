/// The page `doc/device-app.md` held to the app.
///
/// Every `dart` block of the page stands in the files of the app or of its
/// tests; every trace the page quotes is a run of lines of a [Journal] of
/// the same situation; every sentence a test checks is held to the page
/// through [_says]. A section adds its checks here: its answer held to
/// `lib/` with `under:` its heading, its first attempt to
/// `support/device_app_attempts.dart`.
library;

import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
// Deprecated from Flutter 3.47 for package:material_ui, whose releases
// since 0.0.2 need Flutter 3.44; the floor is Flutter 3.38.1.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo_camera_example/camera_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_app_attempts.dart';
import 'support/fake_camera_platform.dart';
import 'support/journal.dart';
import 'support/page_code.dart';

const _doc = '../doc/device-app.md';
const _intro = '# A device app';
const _rapid = '## Rapid taps';
const _first = '### The first attempt';
const _queue = '### One queue for the buttons';
const _recording = '## A switch during a recording';
const _recordingQueue = '### The recording in the queue';

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
        codeMissingFrom(_doc, 'lib/camera_session.dart', under: _queue),
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
