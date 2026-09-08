@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

/// A controller that writes what its own hook was told.
///
/// Declared here and not taken from `support/`: `TestSolo` is a `final
/// class`, and these tests need two controllers whose `onError` can be
/// told apart by name.
final class _Recorder extends Solo<TestState> {
  final String name;
  final List<String> lines;

  _Recorder(this.name, this.lines) : super(const Initial());

  void set(TestState state) => externalSetState(state);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      lines.add('$name.onError [${job.key}] $error');
}

void main() {
  test('a job created inside unattended work is reported once, by itself', () {
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

  test('a late failure arrives after the controller has closed', () {
    final lines = <String>[];
    SoloBase.observer = _Watcher(lines);
    try {
      fakeAsync((async) {
        final solo = _Watched(lines)
          ..run<TestState, void>(key: 'j', (ctx) async {
            ctx.unattended(() async {
              await delay(30);
              throw StateError('late boom');
            });
            await ctx.wait(() => delay(5));
          });
        async.elapse(const Duration(milliseconds: 10));
        solo.close();
        async.flushTimers();
      });
    } finally {
      SoloBase.observer = null;
    }
    // The real closing event lives on the observer, not on the
    // controller: a line written after `await super.close()` would fix
    // the order against the future, not against `onClose`.
    expect(lines, [
      'finish j Done(null)',
      'observer.onClose',
      'error j Bad state: late boom',
    ]);
  });

  test('unattended work outlives close until the cleanup stops it', () {
    var ticks = 0;
    fakeAsync((async) {
      final solo = TestSolo()
        ..run<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() {
            final timer = Timer.periodic(
              const Duration(milliseconds: 10),
              (_) => ticks++,
            );
            ctx.onDispose(timer.cancel);
          });
          await ctx.wait(() => delay(5));
        });
      async.elapse(const Duration(milliseconds: 100));
      expect(ticks, 0, reason: 'the cleanup stopped the timer with the job');
      solo.close();
      async.flushTimers();
    });
  });

  test('without a cleanup the work goes on ticking after close', () {
    var ticks = 0;
    late final Timer timer;
    fakeAsync((async) {
      final solo = TestSolo()
        ..run<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() {
            timer = Timer.periodic(
              const Duration(milliseconds: 10),
              (_) => ticks++,
            );
          });
          await ctx.wait(() => delay(5));
        });
      async.elapse(const Duration(milliseconds: 50));
      final beforeClose = ticks;
      solo.close();
      async.elapse(const Duration(milliseconds: 50));
      expect(ticks, greaterThan(beforeClose));
      // Cancelled by hand, and `flushTimers` is never called here: an
      // unstopped periodic timer under it runs to the one-hour guard and
      // fails the test instead of proving anything.
      timer.cancel();
    });
  });

  test('unattended does not look at the rules', () {
    late final Outcome<void>? outcome;
    var started = false;
    fakeAsync((async) {
      final solo = TestSolo();
      final job = solo.run<TestState, void>(
        key: 'j',
        keepWhile: (state) => state is! Working,
        (ctx) async {
          // The emit breaks this job's own rule; the member is in the
          // group that does not look, so it neither throws nor cancels.
          ctx
            ..emit(const Working())
            ..unattended(() => started = true);
        },
      );
      async.flushTimers();
      outcome = job.outcome;
      solo.close();
      async.flushTimers();
    });
    expect(started, isTrue);
    expect(outcome, isA<Done<void>>());
  });

  test("the job's own cancellation by the rules is filtered", () {
    final lines = <String>[];
    fakeAsync((async) {
      final solo = _Recorder('solo', lines)
        ..run<TestState, void>(
          key: 'j',
          keepWhile: (state) => state is! Working,
          (ctx) async {
            ctx.unattended(() async {
              await ctx.wait(() => delay(50));
            });
            await ctx.wait(() => delay(100));
          },
        );
      async.elapse(const Duration(milliseconds: 5));
      solo.set(const Working());
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(lines, isEmpty);
  });

  test('a fresh Cancelled(rules) from a leaked context reaches the observer',
      () {
    final lines = <String>[];
    fakeAsync((async) {
      final solo = _Recorder('solo', lines)
        ..run<TestState, void>(
          key: 'j',
          keepWhile: (state) => state is! Working,
          (ctx) async {
            ctx.unattended(() async {
              await delay(30);
              // The job is long over and the state has left the rule:
              // this read builds a cancellation of its own, and the
              // filter lets it through — there is nobody left to cancel.
              ctx.state;
            });
          },
        );
      async.elapse(const Duration(milliseconds: 10));
      solo.set(const Working());
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(lines, ['solo.onError [j] Cancelled(rules: keepWhile)']);
  });
}

final class _Watched extends Solo<TestState> {
  final List<String> lines;

  _Watched(this.lines) : super(const Initial());

  @override
  void onFinish(Job<Object?> job) =>
      lines.add('finish ${job.key} ${job.outcome}');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      lines.add('error ${job.key} $error');
}

final class _Watcher extends SoloObserver {
  final List<String> lines;

  _Watcher(this.lines);

  @override
  void onClose(SoloBase<Object> solo) => lines.add('observer.onClose');
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
