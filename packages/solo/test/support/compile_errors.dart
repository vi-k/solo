// `packages/async_job/test/support/compile_errors.dart` is a copy of this file:
// the packages share no test code. A change to one goes to the other.

import 'dart:convert';
import 'dart:io';

/// The errors the analyzer reports for [code], one message for each.
///
/// [code] is a whole library that imports what it uses. It is written to
/// a directory of its own under the system's temporary one, next to the
/// package configuration of the package under test with every path made
/// absolute: the tree of the package stays as it is, and a `dart analyze`
/// of the package that runs beside the test does not find the file.
/// Warnings and hints are not errors and are left out.
Future<List<String>> compileErrors(String code) => _analyze(code, 'ERROR');

/// The warnings the analyzer reports for [code], each as its code and its
/// message: `unused_result: ...`. Read the way [compileErrors] reads errors.
Future<List<String>> compileWarnings(String code) =>
    _analyze(code, 'WARNING', withCode: true);

Future<List<String>> _analyze(
  String code,
  String severity, {
  bool withCode = false,
}) async {
  final directory = await Directory.systemTemp.createTemp('compile_errors');
  try {
    final config = File('.dart_tool/package_config.json').absolute;
    final json =
        jsonDecode(await config.readAsString()) as Map<String, Object?>;
    final packages = json['packages']! as List<Object?>;
    for (final package in packages.cast<Map<String, Object?>>()) {
      package['rootUri'] =
          config.parent.uri.resolve(package['rootUri']! as String).toString();
    }
    await Directory('${directory.path}/.dart_tool').create();
    await File('${directory.path}/.dart_tool/package_config.json')
        .writeAsString(jsonEncode(json));
    await File('${directory.path}/attempt.dart').writeAsString(code);
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['analyze', '--format=machine', directory.path],
    );
    // A line of the machine format: severity, type, code, file, line,
    // column, length and the message, set apart by `|`; a `|` of the message
    // comes escaped.
    final found = [
      for (final line in LineSplitter.split('${result.stdout}'))
        if (line.startsWith('$severity|'))
          [
            if (withCode) '${line.split('|')[2].toLowerCase()}:',
            line.split('|').skip(7).join('|').replaceAll(r'\|', '|').trim(),
          ].join(' '),
    ];
    // The analyzer exits with 0, with 2 on a warning and with 3 on an error;
    // any other code means it did not run, and so does a 3 with no error to
    // show.
    if (result.exitCode > 3 ||
        severity == 'ERROR' && found.isEmpty && result.exitCode > 2) {
      throw StateError('dart analyze exited with ${result.exitCode}: '
          '${result.stderr}${result.stdout}');
    }
    return found;
  } finally {
    await directory.delete(recursive: true);
  }
}
