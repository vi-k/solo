// The code of `doc/errors.md`, verbatim, less the first attempts and the
// two blocks under "Answering for an error", which stand in
// `errors_page_answering.dart`: the page shows two versions of one class,
// and a library holds one. Every piece of the other blocks is a run of lines
// of this file, and `errors_rakes_test.dart` runs it. The page shows
// observers, a method of a controller and a few statements on their own;
// here the statements stand in functions and in bodies of methods, marked
// "Not on the page".
// ignore_for_file: unreachable_from_main
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:solo/solo.dart';

import 'errors_stubs.dart';
import 'test_solo.dart';

/// "Reporting an error".
final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  // ...the jobs from the quick start...
  /// Not on the page: the job of the quick start in the README.
  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        ifFailed: (state, error, stackTrace) => Failure(error),
        ifCancelled: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.abandonable(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      reportCrash(error, stackTrace);
}

/// "Watching every controller".
final class LoggingObserver extends SoloObserver {
  @override
  void onStart(Solo<Object> solo, Job<Object?> job) => print('$job started');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      print('$job finished ${job.outcome}');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      print('${transition.job ?? 'external'}: ${transition.current}');
}

void main() {
  Solo.observer = LoggingObserver();
}

/// "What is holding the controller". Not on the page: the function around
/// the statement.
void closeWithTimeout(Solo<Object> controller) {
  unawaited(controller.close().timeout(
        const Duration(seconds: 5),
        onTimeout: () => log('closing is held by ${controller.pending}'),
        // ignore: require_trailing_commas
      ));
}

final class Hangs extends SoloObserver {
  // An Expando holds its key weakly, so a job takes its timer with it.
  final _timers = Expando<Timer>('hang');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) => _timers[job] = Timer(
        const Duration(seconds: 5),
        () => log('${job.key} is still running: ${solo.pending}'),
      );

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) => _timers[job]?.cancel();
}

/// "Stamping the cancellation".
final class SlowCancellations extends SoloObserver {
  // An Expando holds its key weakly, so a job takes its stamp with it and
  // there is nothing to clean up.
  final _markedAt = Expando<DateTime>('cancellation');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) {
    // whenCancelled fires when the job accepts the cancellation, not when
    // cancel() was called: an open ctx.uncancellable section ends first.
    job.whenCancelled((_) => _markedAt[job] = clock.now());
  }

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) {
    final markedAt = _markedAt[job];
    if (markedAt == null) return;
    final delay = clock.now().difference(markedAt);
    if (delay > const Duration(milliseconds: 50)) {
      log('${job.key} ran ${delay.inMilliseconds} ms past its cancellation');
    }
  }
}

/// "A cancellation that never lands".
final class StuckCancellations extends SoloObserver {
  final _timers = Expando<Timer>('cancellation');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) => job.whenCancelled(
        (_) => _timers[job] = Timer(
          const Duration(seconds: 5),
          () => log('${job.key} has not stopped: ${solo.pending}'),
        ),
      );

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) => _timers[job]?.cancel();
}

/// Not on the page: the function around the statement.
void installAll() {
  Solo.observer = SoloObserver.all([
    LoggingObserver(),
    Hangs(),
    SlowCancellations(),
    StuckCancellations(),
  ]);
}

/// "Observing the outcome". Not on the page: the function around the
/// statement.
void loadAndIgnore(ProfileController profile) {
  profile.load().ignoreFailure();
}

/// "Letting cancellation through", and the log hook of "Logs".
final class Camera extends Solo<CameraState>
    with OpenSolo<CameraState>, Desk<CameraState> {
  final Hardware hw;

  Camera(this.hw) : super(const Closed());

  /// Not on the page: the method around the statements.
  SoloJob<void> open(double zoom) => run<CameraState, void>(
        key: 'open',
        (ctx) async {
          try {
            await ctx.join(hw.open);
            await ctx.join(() => hw.setZoom(zoom));
          } on Object catch (error) {
            ctx.check();
            await hw.reset();
            ctx.emit(Broken(error));
            rethrow;
          }
        },
      );

  /// Not on the page: a job around [sendZoom], [logZoom] or [logLazily].
  SoloJob<void> zoomTo(
    double zoom,
    void Function(JobContext ctx, double zoom) then,
  ) =>
      run<CameraState, void>(key: 'zoom', (ctx) async => then(ctx, zoom));

  @override
  void onLog(Job<Object?> job, Object? message) {
    if (!logger.isLoggable(Level.FINE)) return;
    logger.fine(message is Object? Function() ? message() : message);
  }
}

/// "Work with a life of its own". Not on the page: the function around the
/// statement.
void sendZoom(JobContext ctx, double zoom) {
  // Work with a life of its own: the job neither waits for it nor cancels
  // it, and its errors still reach the job's hooks.
  ctx.unattended(() => analytics.send('zoom'));
}

/// "Logs". Not on the page: the functions around the statements.
void logZoom(JobContext ctx, double zoom) {
  // Application data for the log hooks and observers.
  ctx.log(('zoom', zoom));
}

void logLazily(JobContext ctx, double zoom) {
  // A line that costs something to build: log the callback, not the line.
  ctx.log(() => 'zoom to $zoom on ${device.describe()}');
}

void traceTheEngine() {
  // And the engine's own trace, when the queue itself needs watching.
  Solo.debug = print;
}

void traceTheCore() {
  // And the core's trace of each job: start, errors, cancellation, outcome.
  Job.debug = print;
}

/// "A rule answers".
final class Pool extends Solo<Slots> with OpenSolo<Slots>, Desk<Slots> {
  Pool(super.initialState);

  /// Not on the page: the method around the rule, and a state handler for
  /// the tests to see whether it runs.
  SoloJob<void> take({
    Slots Function(Slots state, Cancelled cancelled)? ifCancelled,
  }) =>
      run<Slots, void>(
        key: 'take',
        // A rule answers; it does not throw to refuse.
        canStart: (state) => state.free > 0,
        ifCancelled: ifCancelled,
        (ctx) async => stage.trace.add('take ran'),
      );
}
