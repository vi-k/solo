import 'dart:io';
import 'dart:mirrors';

import 'package:meta/meta.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// `doc/reference.md` and its translation against the code.
///
/// The page lists every member of five classes in tables, one row a
/// member, under a heading of the class. The members are read from the
/// classes themselves, so a member added to the code and not to the page
/// turns this red, and so does a row left after its member went. A
/// deprecated member is no longer listed. The named parameters of the
/// methods that make jobs stand in a table of their own, each with the
/// methods that take it, read from `Solo` the same way.

const _page = 'doc/reference.md';
const _translation = '../../docs/ru/solo/reference.md';

/// Whether the repository is around the package. The translation lives
/// beside the package, and the archive `dart pub publish` uploads has
/// none of it: run from that archive, the checks of the translation are
/// skipped.
final _inRepository = Directory('../../docs/ru').existsSync();

/// The classes the page lists, each under `## ` and its name.
final _classes = <String, Type>{
  'Solo': Solo,
  'SoloContext': SoloContext,
  'SoloJob': SoloJob,
  'SoloQueue': SoloQueue,
  'SoloAccumulator': SoloAccumulator,
};

/// The methods that make jobs, whose parameters the page lists in a table
/// of their own.
const _makers = ['enqueue', 'job', 'collect', 'accumulate'];

/// Each named parameter of the methods of [_makers], with the methods that
/// take it, as `Solo` declares them.
Map<String, Set<String>> _takenBy() {
  final solo = reflectClass(Solo);
  final takenBy = <String, Set<String>>{};
  for (final maker in _makers) {
    final method = solo.declarations[Symbol(maker)]! as MethodMirror;
    for (final parameter in method.parameters) {
      if (parameter.isNamed) {
        (takenBy[MirrorSystem.getName(parameter.simpleName)] ??= {}).add(maker);
      }
    }
  }
  return takenBy;
}

/// The table of parameters under [heading] in [text]: each parameter with
/// the methods its second cell names.
Map<String, Set<String>> _parameters(String text, String heading) => {
      for (final row in RegExp(r'^\| `(\w+)` \| ([^|]*) \|', multiLine: true)
          .allMatches(_under(text, heading)))
        row.group(1)!: {
          for (final maker in RegExp(r'`(\w+)`').allMatches(row.group(2)!))
            maker.group(1)!,
        },
    };

/// A public member of a class, as the code declares it.
typedef _Member = ({bool isProtected, bool isStatic, bool isConstructor});

/// The public members of [type] that are not deprecated, by name: a
/// setter goes under the name of its getter, and a constructor under the
/// name of the class. A constructor the class does not declare is not
/// listed: the one of an interface is nobody's to call.
Map<String, _Member> _members(Type type) {
  final mirror = reflectClass(type);
  final members = <String, _Member>{};
  for (final declaration in mirror.declarations.values) {
    if (declaration.isPrivate || declaration is TypeVariableMirror) {
      continue;
    }
    final metadata = [for (final m in declaration.metadata) m.reflectee];
    if (metadata.any((m) => m is Deprecated)) {
      continue;
    }
    final isConstructor =
        declaration is MethodMirror && declaration.isConstructor;
    if (isConstructor && declaration.location == null) {
      continue;
    }
    final name = MirrorSystem.getName(declaration.simpleName);
    members[name.endsWith('=') ? name.substring(0, name.length - 1) : name] = (
      isProtected: metadata.any((m) => identical(m, protected)),
      isStatic: switch (declaration) {
        MethodMirror(:final isStatic) => isStatic,
        VariableMirror(:final isStatic) => isStatic,
        _ => false,
      },
      isConstructor: isConstructor,
    );
  }
  return members;
}

/// The parts of [text] that open with a heading, by the heading line.
Map<String, String> _sections(String text) => {
      for (final part in text.split(RegExp('^(?=#)', multiLine: true)))
        part.split('\n').first: part,
    };

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

/// The names in the first cells of the table rows of [text]: `Solo.debug`
/// is `debug`, `ctx.stateAs<T>()` is `stateAs`, `Solo(initialState)` is
/// `Solo`.
List<String> _rows(String text) => [
      for (final match
          in RegExp(r'^\| `(?:\w+\.)?(\w+)', multiLine: true).allMatches(text))
        match.group(1)!,
    ];

/// The first cells of the table rows of [text], whole.
List<String> _cells(String text) => [
      for (final match
          in RegExp(r'^\| (`[^|]*`) \|', multiLine: true).allMatches(text))
        match.group(1)!,
    ];

/// Whether [name] is a member the engine calls for the subclass to
/// override: a hook, named `on…`, or `publish`.
bool _isHook(String name) =>
    name == 'publish' || RegExp('^on[A-Z]').hasMatch(name);

/// The public types `package:solo/solo.dart` exports beside the core's.
Set<String> _exportedTypes() {
  final library = currentMirrorSystem()
      .libraries
      .values
      .singleWhere((l) => '${l.uri}' == 'package:solo/solo.dart');
  final names = <String>{};
  for (final dependency in library.libraryDependencies) {
    final target = dependency.targetLibrary!;
    if (!dependency.isExport || target.uri.scheme != 'package') {
      continue;
    }
    if (target.uri.pathSegments.first != 'solo') {
      continue;
    }
    for (final declaration in target.declarations.values) {
      if (!declaration.isPrivate && declaration is ClassMirror) {
        names.add(MirrorSystem.getName(declaration.simpleName));
      }
    }
    // The mirrors leave out a typedef of a function type and an
    // extension: their names come from the source of the library and of
    // its parts.
    final file = File('lib/${target.uri.pathSegments.skip(1).join('/')}');
    final source = file.readAsStringSync();
    final parts = [
      for (final match
          in RegExp("^part '([^']+)';", multiLine: true).allMatches(source))
        File('${file.parent.path}/${match.group(1)}').readAsStringSync(),
    ];
    final declared = RegExp(
      r'^(?:typedef|extension(?: type)?) ([A-Z]\w*)',
      multiLine: true,
    );
    for (final text in [source, ...parts]) {
      for (final match in declared.allMatches(text)) {
        names.add(match.group(1)!);
      }
    }
  }
  return names;
}

void main() {
  final page = File(_page).readAsStringSync();
  final translation =
      _inRepository ? File(_translation).readAsStringSync() : null;
  const outside = 'the translation is not in the archive of the package';

  // The headings of the tables of other types and of parameters, in the
  // language of the text.
  for (final (path, read, others, parameters) in [
    (_page, page, '## Other types', '## Parameters of a job'),
    (_translation, translation, '## Другие типы', '## Параметры задачи'),
  ]) {
    group(path, skip: read == null ? outside : null, () {
      final text = read ?? '';
      for (final MapEntry(key: name, value: type) in _classes.entries) {
        test('lists every member of $name and nothing else', () {
          final rows = _rows(_under(text, '## $name'));
          expect(rows, unorderedEquals(_members(type).keys));
        });
      }

      test('lists every parameter of the methods that make jobs', () {
        expect(_parameters(text, parameters), _takenBy());
      });

      test('lists under Other types only the types solo exports', () {
        expect(
          _rows(_under(text, others)),
          everyElement(
            allOf(isIn(_exportedTypes()), isNot(isIn(_classes.keys))),
          ),
        );
      });

      test('names every type solo exports beside the core', () {
        // In code, or as the heading of its own table.
        bool names(String type) =>
            RegExp('`${RegExp.escape(type)}\\b').hasMatch(text) ||
            text.split('\n').contains('## $type');
        final missing = [
          for (final type in _exportedTypes())
            if (!names(type)) type,
        ];
        expect(missing, isEmpty);
      });
    });
  }

  group('the tables of Solo', () {
    final members = _members(Solo);
    final solo = _under(page, '## Solo');
    final sections = _sections(solo);
    List<String> rowsOf(String heading) {
      final section = sections['### $heading'];
      if (section == null) {
        throw StateError('$_page has no "### $heading"');
      }
      return _rows(section);
    }

    test('the members set once for the process are the static ones', () {
      expect(
        rowsOf('Set once for the process'),
        unorderedEquals([
          for (final MapEntry(:key, :value) in members.entries)
            if (value.isStatic) key,
        ]),
      );
    });

    test('what a caller sees is plain: no hook, nothing protected', () {
      for (final name in rowsOf('What a caller sees')) {
        final member = members[name];
        expect(member?.isProtected, isFalse, reason: name);
        expect(member?.isStatic, isFalse, reason: name);
        expect(member?.isConstructor, isFalse, reason: name);
        expect(_isHook(name), isFalse, reason: name);
      }
    });

    test('what the subclass uses is protected or the constructor', () {
      for (final name in rowsOf('What the subclass uses')) {
        final member = members[name];
        expect(
          member != null && (member.isProtected || member.isConstructor),
          isTrue,
          reason: name,
        );
        expect(_isHook(name), isFalse, reason: name);
      }
    });

    test('what the subclass overrides is the hooks', () {
      expect(
        rowsOf('What the subclass overrides'),
        unorderedEquals(members.keys.where(_isHook)),
      );
    });

    test('every protected member is in a table of the subclass', () {
      final subclass = {
        ...rowsOf('What the subclass uses'),
        ...rowsOf('What the subclass overrides'),
      };
      for (final MapEntry(:key, :value) in members.entries) {
        if (value.isProtected) {
          expect(subclass, contains(key));
        }
      }
    });
  });

  test(
    'the translation has the rows of the page, cell for cell',
    skip: translation == null ? outside : null,
    () => expect(_cells(translation ?? ''), _cells(page)),
  );
}
