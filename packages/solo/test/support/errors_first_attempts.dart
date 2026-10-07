// The first attempts of `doc/errors.md`, verbatim: every piece of the code
// under a "The first attempt" heading is a run of lines of this file, and
// `errors_rakes_test.dart` runs it. The page shows two observers and three
// fragments; here each fragment stands in a method or a function, marked
// "Not on the page".
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:solo/solo.dart';

import 'errors_stubs.dart';
import 'test_solo.dart';

/// The first attempt of "Why cancellation was slow": the two ends of a job,
/// and the lifetime between them.
final class SlowJobs extends SoloObserver {
  final _startedAt = Expando<DateTime>('start');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      _startedAt[job] = clock.now();

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final startedAt = _startedAt[job];
    if (startedAt == null) return;
    final ran = clock.now().difference(startedAt);
    if (ran > const Duration(milliseconds: 50)) {
      log('${job.key} ran ${ran.inMilliseconds} ms');
    }
  }
}

/// The first attempt of "Handled and unhandled failures": an observer that
/// reports every failure it sees.
final class Failures extends SoloObserver {
  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final outcome = job.outcome;
    if (outcome is Failed) {
      reportCrash(outcome.error, outcome.stackTrace);
    }
  }
}

/// The first attempt of "Catching errors inside a body": one catch for
/// everything that comes out of the camera.
final class BroadCamera extends Solo<CameraState>
    with OpenSolo<CameraState>, Desk<CameraState> {
  final Hardware hw;

  BroadCamera(this.hw) : super(const Closed());

  /// Not on the page: the method around the statements.
  SoloJob<void> open(double zoom) => run<CameraState, void>(
        key: 'open',
        (ctx) async {
          try {
            await ctx.join(hw.open);
            await ctx.join(() => hw.setZoom(zoom));
          } on Object catch (error) {
            await hw.reset();
            ctx.emit(Broken(error));
            rethrow;
          }
        },
      );

  /// Not on the page: a job around [sendZoomUnawaited].
  SoloJob<void> zoomTo(double zoom) => run<CameraState, void>(
        key: 'zoom',
        (ctx) async => sendZoomUnawaited(),
      );
}

/// The first attempt of "Background work and logs". Not on the page: the
/// function around the statement.
void sendZoomUnawaited() {
  unawaited(analytics.send('zoom'));
}

/// The first attempt of "Errors in state rules": a rule that throws to
/// refuse.
final class ThrowingPool extends Solo<Slots> with OpenSolo<Slots>, Desk<Slots> {
  ThrowingPool(super.initialState);

  /// Not on the page: the method around the rule, and a state handler for
  /// the tests to see whether it runs.
  SoloJob<void> take({
    Slots Function(Slots state, Object error, StackTrace stackTrace)? ifFailed,
  }) =>
      run<Slots, void>(
        key: 'take',
        canStart: (state) {
          if (state.free == 0) throw StateError('no free slot');

          return true;
        },
        ifFailed: ifFailed,
        (ctx) async => stage.trace.add('take ran'),
      );
}
