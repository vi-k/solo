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
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo_camera_example/camera_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_camera_platform.dart';
import 'support/journal.dart';
import 'support/page_code.dart';

const _doc = '../doc/device-app.md';
const _intro = '# A device app';

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

/// The part of the page under [heading], up to the next heading.
String _part(String heading) {
  for (final part in _parts) {
    if (part.split('\n').first == heading) return part;
  }
  throw StateError('$_doc has no "$heading"');
}

/// The headings whose trace a test has read through [_traceUnder].
final _traced = <String>{};

/// The lines of the one `text` block under [heading]: a trace the page
/// quotes.
List<String> _traceUnder(String heading) {
  _traced.add(heading);
  final blocks = RegExp(
    r'```text\n(.*?)\n```',
    dotAll: true,
  ).allMatches(_part(heading)).toList();
  if (blocks.length != 1) {
    throw StateError(
      '$_doc has ${blocks.length} traces under "$heading", not one',
    );
  }
  return blocks.single.group(1)!.split('\n');
}

/// Holds the part under [heading] to [sentence]: its prose, the breaks of
/// its lines aside.
void _says(String heading, String sentence) => expect(
  _part(heading)
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
        _intro,
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
        for (final part in _parts)
          if (part.contains('```text\n')) part.split('\n').first,
      });
    });
  });
}
