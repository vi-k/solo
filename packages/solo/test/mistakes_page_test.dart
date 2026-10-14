import 'dart:io';

import 'package:test/test.dart';

import 'support/page_code.dart';

/// `doc/mistakes.md` against the sections it points to.
///
/// Each section of the page shows the right way in a few lines of the
/// answer of another page and links to the section that holds it. Its
/// code has to stand under the answer's heading there, so the two cannot
/// part, and in the file the tests of that page run, so the lines are run
/// code.

const _page = 'doc/mistakes.md';

/// A section of the page: the answer it quotes, the file that holds that
/// answer, and the links the section gives. The first link leads to the
/// section the answer stands in.
typedef _Source = ({
  String answer,
  String holder,
  List<String> links,
});

const _sources = <String, _Source>{
  '## Waiting through the context': (
    answer: '### Each wait in its place',
    holder: 'test/support/cancellation_page.dart',
    links: ['cancellation.md#ordinary-await-and-context-lifetime'],
  ),
  '## Registering a release on the call': (
    answer: '### The release travels with the call',
    holder: 'test/support/resources_page.dart',
    links: ['resources.md#taking-a-resource-from-a-call'],
  ),
  '## Letting cancellation through a catch': (
    answer: '### Letting cancellation through',
    holder: 'test/support/errors_page.dart',
    links: ['errors.md#catching-errors-inside-a-body'],
  ),
  '## Steps as children': (
    answer: '### Two children in a row',
    holder: 'test/support/children_page.dart',
    links: [
      'children.md#steps-in-a-row',
      'cancellation.md#closing-from-a-job',
    ],
  ),
  '## Answering for every failure': (
    answer: '### Observing the outcome',
    holder: 'test/support/errors_page.dart',
    links: ['errors.md#handled-and-unhandled-failures'],
  ),
  '## Moving the clock in fakeAsync': (
    answer: '### Elapsing instead of awaiting',
    holder: 'test/support/testing_page.dart',
    links: ['testing.md#awaiting-inside-fakeasync'],
  ),
  '## A key for each request': (
    answer: '#### The record key',
    holder: 'test/support/jobs_page.dart',
    links: ['jobs.md#a-key-for-each-request'],
  ),
};

/// The parts of [text] that open with a heading, by the heading line.
Map<String, String> _sections(String text) => {
      for (final part in text.split(RegExp('^(?=#)', multiLine: true)))
        part.split('\n').first: part,
    };

/// The anchor of [heading], as `tool/check_links.py` makes it.
String _slug(String heading) => heading
    .replaceFirst(RegExp('^#+ '), '')
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\w\s-]'), '')
    .replaceAll(RegExp(r'\s+'), '-');

/// The part of [text] under [heading], with the deeper headings in it, up
/// to the next heading of its level or above.
String _under(String text, String heading) {
  final level = heading.indexOf(' ');
  final lines = text.split('\n');
  final start = lines.indexOf(heading);
  final rest = lines.skip(start + 1).takeWhile((line) {
    final match = RegExp('^(#+) ').firstMatch(line);
    return match == null || match.group(1)!.length > level;
  });
  return [heading, ...rest].join('\n');
}

void main() {
  final text = File(_page).readAsStringSync();
  final sections = _sections(text);
  late Directory scratch;

  setUpAll(() {
    scratch = Directory.systemTemp.createTempSync('mistakes_page_test');
  });
  tearDownAll(() {
    scratch.deleteSync(recursive: true);
  });

  test('has no fence the checks do not read', () {
    expect(strayFences(_page), isEmpty);
  });

  test('every section is one of the sections below', () {
    expect(
      [
        for (final heading in sections.keys)
          if (heading.startsWith('## ')) heading,
      ],
      unorderedEquals(_sources.keys),
    );
  });

  for (final MapEntry(key: heading, value: source) in _sources.entries) {
    final [link, ...] = source.links;
    final page = 'doc/${link.split('#').first}';
    group(heading, () {
      test('links to ${source.links.join(' and ')}', () {
        final section = sections[heading]!;
        for (final link in source.links) {
          expect(section, contains(']($link)'));
        }
      });

      test('the answer stands in the section of $link', () {
        final anchor = link.split('#').last;
        final text = File(page).readAsStringSync();
        final target = [
          for (final line in text.split('\n'))
            if (line.startsWith('#') && _slug(line) == anchor) line,
        ];
        expect(target, hasLength(1));
        final section = _under(text, target.single).split('\n');
        expect(section, contains(source.answer));
      });

      test('quotes "${source.answer}" of $page', () {
        final answer = _sections(File(page).readAsStringSync())[source.answer];
        if (answer == null) {
          throw StateError('$page has no "${source.answer}"');
        }
        // The answer's code in a file of its own, for the page helper that
        // matches pieces of a page against the lines of a file.
        final index = _sources.keys.toList().indexOf(heading);
        final code = [
          for (final block in RegExp(r'```dart\n(.*?)\n```', dotAll: true)
              .allMatches(answer))
            block.group(1),
        ];
        final file = File('${scratch.path}/$index.dart')
          ..writeAsStringSync(code.join('\n'));
        expect(codeMissingFrom(_page, file.path, under: heading), isEmpty);
      });

      test('is a run of lines of ${source.holder}', () {
        expect(codeMissingFrom(_page, source.holder, under: heading), isEmpty);
      });
    });
  }
}
