import 'dart:io';

import 'package:test/test.dart';

// `@protected` is a fact for the analyzer alone: a call from outside the
// class compiles and runs the same with it or without it, so no test that
// makes the call can tell the two apart. The guard reads the declarations.
void main() {
  test('the five members operations are built from are protected', () {
    final source = File('lib/src/solo.dart').readAsStringSync();
    for (final name in ['job', 'add', 'run', 'collect', 'accumulate']) {
      expect(
        source,
        contains(RegExp(r'@protected\s+Solo\w*<[^>]*> ' '$name<')),
        reason: '$name is protected',
      );
    }
  });
}
