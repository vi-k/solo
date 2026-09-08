@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

/// A controller that writes what its own hook was told.
///
/// Declared here and not taken from `support/`: `TestSolo` is a `final
/// class`, and these tests need two controllers whose `onError` can be
/// told apart by name.
final class _Recorder extends Solo<TestState> {
  _Recorder(this.name, this.lines) : super(const Initial());

  final String name;
  final List<String> lines;

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      lines.add('$name.onError [${job.key}] $error');
}

void main() {
  test('a job created inside unattended work is reported once, by itself',
      () {
    final lines = <String>[];
    final zone = <String>[];
    fakeAsync((async) {
      final host = _Recorder('host', lines);
      final other = _Recorder('other', lines);
      _inZone(zone, () {
        host.run<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() {
            // A job of the other controller, started from the background
            // of this one. Its failure is its own: it goes to the hook of
            // the controller that made it, and, unobserved, to the zone
            // the body runs in — not to the hook of the job that started
            // the work.
            other.run<TestState, void>(
              key: 'stray',
              (c) async => throw StateError('stray boom'),
            );
          });
          await ctx.wait(() => delay(1));
        });
      });
      async.flushTimers();
      host.close();
      other.close();
      async.flushTimers();
    });
    expect(lines, ['other.onError [stray] Bad state: stray boom']);
    expect(zone, ['Bad state: stray boom']);
  });
}

void _inZone(List<String> errors, void Function() body) {
  Zone.current
      .fork(
        specification: ZoneSpecification(
          handleUncaughtError: (self, parent, zone, error, stackTrace) =>
              errors.add('$error'),
        ),
      )
      .run<void>(body);
}
