import 'dart:io';

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';
import 'package:async_job_lints/plugin_api.dart';
import 'package:test/test.dart';

import 'support/recording_registry.dart';
import 'support/rule_base.dart';

/// Every rule the plugin registers, fresh for each run over the blocks.
List<AbstractAnalysisRule> _rules() {
  final registry = RecordingRegistry();
  registerAsyncJobLints(registry);
  return [...registry.warnings, ...registry.lints];
}

/// The start of the function the second dart block replaces in the first.
const _record = 'Job<void> record(';

void main() {
  final page = File('example/example.md').readAsStringSync();
  final yaml = _blocks(page, 'yaml');
  final dart = _blocks(page, 'dart');

  test('the page has one yaml block and two dart blocks', () {
    expect(yaml, hasLength(1));
    expect(dart, hasLength(2));
  });

  // The page is for code on async_job alone; the example of solo_lints shows
  // a controller.
  test('the page does not use solo', () {
    expect(page, isNot(contains('package:solo/')));
  });

  // A reader copies this block first, so it is checked whole: a misspelt key
  // or a key at the wrong depth would turn the plugin or the lint off.
  test('the yaml block names this version and turns on the lint', () {
    final version = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(
      yaml.single,
      'plugins:\n'
      '  async_job_lints:\n'
      '    version: ^$version\n'
      '    diagnostics:\n'
      '      catch_without_check: true\n',
    );
  });

  test('each marked line of the first block is reported, and no other', () {
    final file = dart.first;
    final marked = <String>{
      for (final (index, line) in file.split('\n').indexed)
        if (RegExp(r'// (\w+)$').firstMatch(line) case final match?)
          '${index + 1}: ${match.group(1)}',
    };
    expect(marked, hasLength(3), reason: 'the page names three mistakes');
    return expectLater(_reported(file), completion(marked));
  });

  test('the fixed record is reported by no rule', () {
    final file = dart.first;
    final at = file.indexOf(_record);
    expect(at, isNonNegative, reason: 'the first block has no record');
    expect(dart.last, startsWith(_record));
    final fixed = '${file.substring(0, at)}${dart.last}';
    return expectLater(_reported(fixed), completion(isEmpty));
  });
}

/// The ```[language] blocks of [page], in order.
List<String> _blocks(String page, String language) => [
  for (final match in RegExp(
    '^```$language\\n(.*?)^```\$',
    multiLine: true,
    dotAll: true,
  ).allMatches(page))
    match.group(1)!,
];

/// The lines of [code] the rules report, as `line: rule`.
///
/// Fails when [code] does not compile: a rule never reports an error of the
/// compiler, so an error means the page shows code that does not build.
Future<Set<String>> _reported(String code) async {
  final reported = <String>{};
  final count = _rules().length;
  for (var index = 0; index < count; index++) {
    final run = _Run(_rules()[index])..setUp();
    try {
      run.testFile.writeAsStringSync(code);
      final result = await run.resolveFile(run.testFile.path);
      final errors = [
        for (final d in result.diagnostics)
          if (d.diagnosticCode.severity == DiagnosticSeverity.ERROR &&
              d.diagnosticCode is! LintCode)
            '  ${result.lineInfo.getLocation(d.offset)}: ${d.message}',
      ];
      if (errors.isNotEmpty) fail('the block does not compile:\n$errors');
      for (final d in result.diagnostics) {
        if (run.underTest.diagnosticCodes.contains(d.diagnosticCode)) {
          final line = result.lineInfo.getLocation(d.offset).lineNumber;
          reported.add('$line: ${run.underTest.name}');
        }
      }
    } finally {
      await run.tearDown();
    }
  }
  return reported;
}

/// One rule over one file, with the real async_job in place.
final class _Run extends RuleTest {
  _Run(this.underTest);

  @override
  final AbstractAnalysisRule underTest;
}
