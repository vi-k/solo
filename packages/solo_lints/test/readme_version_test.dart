import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('every block of the README asks for the version of this package', () {
    final version = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    final readme = File('README.md').readAsStringSync();
    final named = [
      for (final match in RegExp(
        r'^  solo_lints:(?: |\n    version: )(\S+)$',
        multiLine: true,
      ).allMatches(readme))
        match.group(1),
    ];

    // The short block in Install and the long one with diagnostics.
    expect(named, hasLength(2));
    expect(named, everyElement('^$version'));
  });
}
