import 'dart:io';

import 'package:test/test.dart';

import 'support/page_code.dart';

/// `doc/mistakes.md` and its translation against the sections they point
/// to.
///
/// Each section of the page shows a mistake and then the right way, each
/// in a few lines of the section its first link leads to: the mistake from
/// an attempt there, the right way from the answer. The mistake stands
/// under `Don't do this:` and opens with a `// Wrong: ` line, the right way
/// stands under `Do this:`. Each block has to stand whole, as one run of
/// lines, under its heading on the other page, so the two cannot part, and
/// in the file the tests of that page run, so the lines are run code. The
/// translation has its own words for the two lines and the mark, and the
/// same code: `tool/check_translations.py` holds that.

const _page = 'doc/mistakes.md';
const _translation = '../../docs/ru/solo/mistakes.md';

/// Whether the repository is around the package. The translation lives
/// beside the package, and the archive `dart pub publish` uploads has
/// none of it: run from that archive, the checks of the translation are
/// skipped.
final _inRepository = Directory('../../docs/ru').existsSync();

/// The line over the mistake, the line over the right way and the first
/// line of the code of a mistake, in the language of a page.
typedef _Words = ({String dont, String doThis, String wrong});

const _english =
    (dont: "Don't do this:", doThis: 'Do this:', wrong: '// Wrong: ');
const _russian = (
  dont: 'Так не делайте:',
  doThis: 'Делайте так:',
  wrong: '// Неверно: ',
);

/// A section of the page: the attempt it quotes and the file that holds
/// that attempt, the answer it quotes and the file that holds that answer,
/// and the links the section gives. The first link leads to the section
/// the attempt and the answer stand in.
typedef _Source = ({
  String attempt,
  String attemptHolder,
  String answer,
  String answerHolder,
  List<String> links,
});

const _sources = <String, _Source>{
  '## Waiting through the context': (
    attempt: '### The first attempt',
    attemptHolder: 'test/support/cancellation_first_attempts.dart',
    answer: '### Each wait in its place',
    answerHolder: 'test/support/cancellation_page.dart',
    links: ['cancellation.md#ordinary-await-and-context-lifetime'],
  ),
  '## Registering a release on the call': (
    attempt: '### The first attempt',
    attemptHolder: 'test/support/resources_first_attempts.dart',
    answer: '### The release travels with the call',
    answerHolder: 'test/support/resources_page.dart',
    links: ['resources.md#taking-a-resource-from-a-call'],
  ),
  '## Letting cancellation through a catch': (
    attempt: '### The first attempt',
    attemptHolder: 'test/support/errors_first_attempts.dart',
    answer: '### Letting cancellation through',
    answerHolder: 'test/support/errors_page.dart',
    links: ['errors.md#catching-errors-inside-a-body'],
  ),
  '## Steps as children': (
    attempt: '### The second attempt',
    attemptHolder: 'test/support/children_first_attempts.dart',
    answer: '### Two children in a row',
    answerHolder: 'test/support/children_page.dart',
    links: [
      'children.md#steps-in-a-row',
      'cancellation.md#closing-from-a-job',
    ],
  ),
  '## Answering for every failure': (
    attempt: '### The first attempt',
    attemptHolder: 'test/support/errors_first_attempts.dart',
    answer: '### Observing the outcome',
    answerHolder: 'test/support/errors_page.dart',
    links: ['errors.md#handled-and-unhandled-failures'],
  ),
  '## Moving the clock in fakeAsync': (
    attempt: '### The first attempt',
    attemptHolder: 'test/support/testing_first_attempts.dart',
    answer: '### Elapsing instead of awaiting',
    answerHolder: 'test/support/testing_page.dart',
    links: ['testing.md#awaiting-inside-fakeasync'],
  ),
  '## A key for each request': (
    attempt: '#### The first attempt',
    attemptHolder: 'test/support/jobs_first_attempts.dart',
    answer: '#### The record key',
    answerHolder: 'test/support/jobs_page.dart',
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
  if (start < 0) {
    throw StateError('no "$heading"');
  }
  final rest = lines.skip(start + 1).takeWhile((line) {
    final match = RegExp('^(#+) ').firstMatch(line);
    return match == null || match.group(1)!.length > level;
  });
  return [heading, ...rest].join('\n');
}

/// Every way [section] fails to show a mistake and then the right way in
/// the [words] of its page: the mistake under `dont`, opening with `wrong`,
/// and the right way under `doThis`.
List<String> _shapeMissing(String section, _Words words) {
  // A fence with no blank line in front of it is not one of the blocks.
  final fences = '```dart'.allMatches(section).length;
  final blocks = _blocks(section);
  final labels = [for (final block in blocks) block.label];
  return [
    if (fences != 2) '$fences dart blocks, not 2',
    if (labels.join('|') != '${words.dont}|${words.doThis}')
      'the lines over the blocks are $labels',
    if (blocks.isEmpty || !blocks.first.code.startsWith(words.wrong))
      'the mistake does not open with "${words.wrong}"',
  ];
}

/// The `dart` blocks of [text], each with the line in front of it.
List<({String label, String code})> _blocks(String text) => [
      for (final match in RegExp(
        r'^([^\n]*)\n\n```dart\n(.*?)\n```',
        multiLine: true,
        dotAll: true,
      ).allMatches(text))
        (label: match.group(1)!, code: match.group(2)!),
    ];

/// The section of the page [link] leads to, with the deeper headings in it.
String _linked(String link) {
  final [path, anchor] = link.split('#');
  final text = File('doc/$path').readAsStringSync();
  final headings = [
    for (final line in text.split('\n'))
      if (line.startsWith('#') && _slug(line) == anchor) line,
  ];
  if (headings.length != 1) {
    throw StateError('doc/$path has ${headings.length} headings of #$anchor');
  }
  return _under(text, headings.single);
}

void main() {
  final text = File(_page).readAsStringSync();
  final sections = _sections(text);
  final translation =
      _inRepository ? File(_translation).readAsStringSync() : null;
  const outside = 'the translation is not in the archive of the package';
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

  test(
    'the translation shows each mistake, then the right way',
    skip: translation == null ? outside : null,
    () {
      final parts = [
        for (final MapEntry(key: heading, value: part)
            in _sections(translation ?? '').entries)
          if (heading.startsWith('## ')) (heading, part),
      ];
      expect(parts, hasLength(_sources.length));
      for (final (heading, part) in parts) {
        expect(_shapeMissing(part, _russian), isEmpty, reason: heading);
      }
    },
  );

  for (final MapEntry(key: heading, value: source) in _sources.entries) {
    final [link, ...] = source.links;
    final page = 'doc/${link.split('#').first}';
    group(heading, () {
      // The code of the section, the mistake first.
      List<String> code() => [
            for (final block in _blocks(sections[heading]!)) block.code,
          ];

      // [code] in a page of its own, for the page helper that matches the
      // pieces of a page against the lines of a file. The blank lines go:
      // the helper cuts a block into pieces at them and finds each piece
      // on its own, and the block has to stand whole.
      String quoted(String name, String code) {
        final whole = [
          for (final line in code.split('\n'))
            if (line.trim().isNotEmpty) line,
        ].join('\n');
        return (File('${scratch.path}/$name.md')
              ..writeAsStringSync('```dart\n$whole\n```\n'))
            .path;
      }

      // The code under [subheading] of the linked section, in a file of
      // its own.
      String held(String name, String subheading) {
        final part = _under(_linked(link), subheading);
        return (File('${scratch.path}/$name.dart')
              ..writeAsStringSync(
                [
                  for (final block
                      in RegExp(r'```dart\n(.*?)\n```', dotAll: true)
                          .allMatches(part))
                    block.group(1),
                ].join('\n'),
              ))
            .path;
      }

      // The mistake and the right way, each in a page of its own.
      final index = _sources.keys.toList().indexOf(heading);
      String mistakePage() {
        final [wrong, ...] = code();
        final unmarked = wrong.replaceFirst(
          RegExp('^${RegExp.escape(_english.wrong)}.*\n'),
          '',
        );
        return quoted('$index-wrong', unmarked);
      }

      String rightWayPage() {
        final [_, ...right] = code();
        return quoted('$index-right', right.join('\n'));
      }

      test('links to ${source.links.join(' and ')}', () {
        final section = sections[heading]!;
        for (final link in source.links) {
          expect(section, contains(']($link)'));
        }
      });

      test('shows the mistake, then the right way', () {
        expect(_shapeMissing(sections[heading]!, _english), isEmpty);
      });

      test('the attempt and the answer stand in the section of $link', () {
        final section = _linked(link).split('\n');
        expect(section, containsAll([source.attempt, source.answer]));
      });

      test('quotes "${source.attempt}" of $page', () {
        final attempt = held('$index-attempt', source.attempt);
        expect(codeMissingFrom(mistakePage(), attempt), isEmpty);
      });

      test('quotes "${source.answer}" of $page', () {
        final answer = held('$index-answer', source.answer);
        expect(codeMissingFrom(rightWayPage(), answer), isEmpty);
      });

      test('the mistake is not the answer, nor the right way the attempt', () {
        final attempt = held('$index-attempt', source.attempt);
        final answer = held('$index-answer', source.answer);
        expect(codeMissingFrom(mistakePage(), answer), isNotEmpty);
        expect(codeMissingFrom(rightWayPage(), attempt), isNotEmpty);
      });

      test('the mistake is a run of lines of ${source.attemptHolder}', () {
        expect(codeMissingFrom(mistakePage(), source.attemptHolder), isEmpty);
      });

      test('the right way is a run of lines of ${source.answerHolder}', () {
        expect(
          codeMissingFrom(rightWayPage(), source.answerHolder),
          isEmpty,
        );
      });
    });
  }
}
