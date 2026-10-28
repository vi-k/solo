import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

/// The packages whose real sources a test file can import.
///
/// The rules recognize async_job and solo by name, so the tests read the
/// sources of the packages themselves: a rename there fails a test here
/// rather than silencing a rule.
const _packages = [
  'async_job',
  'solo',
  'meta',
  'fake_async',
  'clock',
  'collection',
];

/// The `lib/` files of each package in [_packages], read once per run.
final Map<String, Map<String, String>> _sources = {
  for (final name in _packages) name: _read(name),
};

Map<String, String> _read(String name) {
  final lib = Isolate.resolvePackageUriSync(Uri.parse('package:$name/'));
  if (lib == null) throw StateError('package:$name is not resolvable');
  final dir = Directory.fromUri(lib);
  return {
    for (final file in dir.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart'))
        file.path.substring(dir.path.length): file.readAsStringSync(),
  };
}

/// A test of one rule against code that imports the real packages.
abstract class RuleTest extends AnalysisRuleTest {
  /// The rule under test.
  AbstractAnalysisRule get underTest;

  @override
  void setUp() {
    rule = underTest;
    // The packages go in before super.setUp, which writes the package
    // configuration: a package added later is not seen.
    for (final MapEntry(key: name, value: files) in _sources.entries) {
      final builder = newPackage(name);
      for (final MapEntry(key: path, value: content) in files.entries) {
        builder.addFile('lib/$path', content);
      }
    }
    super.setUp();
  }

  /// Asserts that the rule reports [code] exactly at [spans], each the text
  /// of the node it reports, found in [code] in this order.
  ///
  /// A span may mark the reported part of a longer text with `[[` and `]]`:
  /// `'on [[Object]] catch'` expects the diagnostic at `Object` of the first
  /// `on Object catch`.
  Future<void> assertAt(String code, List<String> spans) {
    var from = 0;
    final expected = [
      for (final span in spans)
        () {
          final start = span.indexOf('[[');
          final text = span.replaceAll('[[', '').replaceAll(']]', '');
          final found = code.indexOf(text, from);
          if (found < 0) throw ArgumentError('$text is not in the code');
          from = found + 1;
          if (start < 0) return lint(found, text.length);
          return lint(found + start, span.indexOf(']]') - start - 2);
        }(),
    ];
    return assertDiagnostics(code, expected);
  }
}
