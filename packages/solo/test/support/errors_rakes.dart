// What the tests of `doc/errors.md` and `doc/diagnostics.md` share: a page
// read for its phrases, tables and quotes, a run under fake time, and the
// observers and controllers that say which of their hooks ran.

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'errors_stubs.dart';
import 'test_solo.dart';

/// A page of `doc/`, read for what its prose, tables and quotes say.
final class DocPage {
  final String path;

  const DocPage(this.path);

  String get source => File(path).readAsStringSync();

  /// The page with every run of whitespace turned into one space, so that a
  /// phrase is found wherever its lines were broken.
  String get prose => source.replaceAll(RegExp(r'\s+'), ' ');

  /// Holds the page to [phrase]: the test that calls this runs what the
  /// phrase says, so a page that stops saying it leaves the test with
  /// nothing to stand for.
  void says(String phrase) => expect(
        prose,
        contains(phrase),
        reason: '$path no longer says this',
      );

  /// The rows of the table under [header], first cell to second.
  Map<String, String> rows(String header) {
    final lines = source.split('\n');
    final start = lines.indexOf(header);
    if (start < 0) {
      throw StateError('$path has no table "$header"');
    }

    return {
      for (final line
          in lines.skip(start + 2).takeWhile((l) => l.startsWith('|')))
        line.split('|')[1].trim(): line.split('|')[2].trim(),
    };
  }

  /// The lines the page quotes under a `text` fence, block by block.
  List<List<String>> get quoted => [
        for (final block
            in RegExp(r'```text\n(.*?)\n```', dotAll: true).allMatches(source))
          block.group(1)!.split('\n'),
      ];
}

const errorsPage = DocPage('doc/errors.md');

const diagnosticsPage = DocPage('doc/diagnostics.md');

/// Asserts that the table of where each error goes has this row.
void errorsRow(String error, String hears, String answers) =>
    errorsPage.says('| $error | $hears | $answers |');

/// An observer that keeps what `onError` told it.
final class Watching extends SoloObserver {
  final heard = <String>[];

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      heard.add('${job.key}: ${text(error)}');
}

/// An observer that says when each of its hooks runs, and may throw from
/// one of them.
final class Saying extends SoloObserver {
  final String name;
  final List<String> into;
  final String? throwOn;

  Saying(this.name, this.into, {this.throwOn});

  void _say(String hook) {
    into.add('$name.$hook');
    if (hook == throwOn) throw StateError('$name.$hook threw');
  }

  @override
  void onCreate(Solo<Object> solo) => _say('onCreate');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) => _say('onStart');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) => _say('onFinish');

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      _say('onError');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      _say('onChange');

  @override
  void onLog(Solo<Object> solo, Job<Object?> job, Object? message) =>
      _say('onLog');

  @override
  void onClose(Solo<Object> solo) => _say('onClose');
}

/// A controller that overrides every hook the page names, calls `super` in
/// none of them and may throw from one.
final class EveryHook extends Solo<int> with OpenSolo<int> {
  final List<String> into;
  final String? throwOn;

  EveryHook(this.into, {this.throwOn}) : super(0);

  void _say(String hook) {
    into.add('controller.$hook');
    if (hook == throwOn) throw StateError('controller.$hook threw');
  }

  @override
  void onStart(Job<Object?> job) => _say('onStart');

  @override
  void onFinish(Job<Object?> job) => _say('onFinish');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _say('onError');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _say('onUnanswered');

  @override
  void onLog(Job<Object?> job, Object? message) => _say('onLog');

  @override
  void onChange(SoloTransition<int> transition) => _say('onChange');

  @override
  void onClose() => _say('onClose');

  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      _say('onListenerError');
}

/// What a run under fake time left behind: the errors that reached its zone
/// uncaught and the lines it printed.
final class Ran {
  final errors = <String>[];
  final printed = <String>[];
}

/// Runs [body] under fake time, in a zone of its own. Nothing is asserted
/// inside: an `expect` that failed in there would be one more error of the
/// zone.
Ran runFaked(void Function(FakeAsync async) body) {
  final ran = Ran();
  fakeAsync((async) {
    runZonedGuarded(
      () => body(async),
      (error, stackTrace) => ran.errors.add(text(error)),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => ran.printed.add(line),
      ),
    );
    async.flushTimers();
  });

  return ran;
}

/// Runs [body] in a zone of its own and returns what reached it uncaught.
List<String> zoneOf(void Function() body) {
  final errors = <String>[];
  runZonedGuarded(body, (error, stackTrace) => errors.add(text(error)));

  return errors;
}

/// Ends [call] of a stub the way it would end on its own, and lets whatever
/// waited for it go on.
void endCall(FakeAsync async, String call) {
  stage.end(call);
  async.flushMicrotasks();
}

/// A job that waits on a call named `op` through `ctx.abandonable`.
SoloJob<void> waits(Bench bench, String key) => bench.enqueue<int, void>(
      key: key,
      (ctx) => ctx.abandonable(() => stage.start<void>('op', null)),
    );
