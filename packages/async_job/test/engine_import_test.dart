import 'dart:io';

import 'package:test/test.dart';

// Which import carries the protocol of an engine is a fact of the export
// directives: both libraries hand out the very same classes, so no call
// made at runtime can tell them apart. The guard reads the two files.
List<String> _exports(String path) =>
    RegExp("^export '[^']+'[^;]*;", multiLine: true)
        .allMatches(File(path).readAsStringSync())
        .map((match) => match[0]!)
        .toList();

void main() {
  test('the main import leaves the engine protocol out', () {
    expect(_exports('lib/async_job.dart'), [
      "export 'src/job_base.dart' hide JobBase, JobContextBase, JobStatus;",
    ]);
  });

  test('engine.dart carries the protocol and everything else', () {
    expect(_exports('lib/engine.dart'), [
      "export 'async_job.dart';",
      "export 'src/job_base.dart' show JobBase, JobContextBase, JobStatus;",
    ]);
  });
}
