// The code of `doc/jobs.md`, verbatim, less the first attempts: every piece
// of those blocks is a run of lines of this file, and `jobs_rakes_test.dart`,
// `droppable_recipe_test.dart` and `queue_pause_recipe_test.dart` run it. The
// page shows the methods of one controller on their own; here each stands in
// a class, and a method the page writes more than once has a class for each
// version.
import 'dart:async';

import 'package:solo/solo.dart';

import 'jobs_stubs.dart';
import 'readme_quick_start.dart' show ProfileController;
import 'test_solo.dart';

enum _Op { load, save, zoom, seek, stop, pause }

/// The block under "Jobs and results", on the controller of the quick start.
Future<void> readOutcome(ProfileController profile) async {
  switch (await profile.load().done) {
    case Done(:final value):
      print('loaded $value');
    case Failed(:final error):
      print('not loaded: $error');
    case Cancelled(:final reason):
      print('gave up: $reason');
  }
}

/// The block under "Creating and scheduling jobs".
final class Assembling extends Solo<CameraState>
    with OpenSolo<CameraState>, Workbench {
  Assembling() : super(const Ready());

  /// The two steps of the page; the job they make is handed back.
  Job<void> saveInTwoSteps() {
    // Assembled now, queued after: two steps, for a job to hold on to.
    final saving = job<Ready, void>(
      key: _Op.save,
      (ctx) => ctx.join(store.save),
    );
    add(saving);
    return saving;
  }

  // Or both at once, which is what a controller method normally does.
  Job<void> setZoom(double zoom) => run<Ready, void>(
        key: _Op.zoom,
        // Lazy, and only for diagnostics: built when a log asks for it.
        describe: () => 'zoom: $zoom',
        (ctx) => ctx.join(() => camera.zoom(zoom)),
      );
}

/// The policies, the record key, `stop()` and the pause that works.
final class CameraController extends Solo<CameraState>
    with OpenSolo<CameraState>, Workbench {
  CameraController([super.initialState = const Ready()]);

  // sequential, the default: one after another, in the order asked for.
  Job<void> save() =>
      run<Ready, void>(key: _Op.save, (ctx) => ctx.join(store.save));

  // droppable: a second load of the same profile returns the first job.
  Job<Profile> load(String id) => run<Ready, Profile>(
        key: (_Op.load, id),
        policy: Policy.droppable,
        (ctx) => ctx.abandonable(() => api.load(id)),
      );

  // replace: the queued zoom goes, a running one is left alone.
  Job<void> setZoom(double zoom) => run<Ready, void>(
        key: _Op.zoom,
        policy: Policy.replace,
        (ctx) => ctx.join(() => camera.zoom(zoom)),
      );

  // restart: the same, and the running one is asked to stop as well.
  Job<void> seek(Duration position) => run<Ready, void>(
        key: _Op.seek,
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          // Wait for the device to stop before the next seek starts.
          await ctx.join(() => camera.seek(position, cancelToken: token));
        },
      );

  /// Not on the page: the seek the page warns about, a `join` around a call
  /// the request cannot reach.
  Job<void> seekWithoutToken(Duration position) => run<Ready, void>(
        key: _Op.seek,
        policy: Policy.restart,
        (ctx) => ctx.join(() => camera.seek(position)),
      );

  /// Not on the page: the other way in the page names, `ctx.abandonable`.
  Job<void> seekLetGo(Duration position) => run<Ready, void>(
        key: _Op.seek,
        policy: Policy.restart,
        (ctx) => ctx.abandonable(() => camera.seek(position)),
      );

  /// Not on the page: a seek that refuses to be cancelled.
  Job<void> seekToTheEnd(Duration position) => run<Ready, void>(
        key: _Op.seek,
        cancellable: false,
        (ctx) => ctx.join(() => camera.seek(position)),
      );

  Job<void> stop() {
    // What is waiting right now.
    print(queue.length);
    // Drop what this command makes pointless...
    queue.removeWhere((job) => job.key == _Op.zoom);
    // ...and jump the line with the stop itself.
    return add(
      job<Ready, void>(key: _Op.stop, (ctx) => ctx.join(camera.stop)),
      first: true,
    );
  }

  Completer<void>? _gate;

  bool get isPaused => _gate != null;

  void pause() {
    if (_gate != null) return;
    final gate = _gate = Completer<void>();
    add(
      job<CameraState, void>(
        key: _Op.pause,
        (ctx) => ctx.abandonable(() => gate.future),
      ),
      first: true,
    ).whenCancelled((_) {
      // Cancellation is not a resume, and a cancelled gate is not a pause.
      // The field may hold a newer gate by now, and that one stays.
      if (identical(_gate, gate)) _gate = null;
    });
  }

  void resume() {
    _gate?.complete();
    _gate = null;
  }
}

/// The block under "The record key" that tells a method whose job it was
/// handed.
final class CountingController extends Solo<CameraState>
    with OpenSolo<CameraState>, Workbench {
  CountingController() : super(const Ready());

  /// Not on the page: the jobs that have an outcome, in the order they got
  /// it. A job dropped before its start is one of them.
  final finished = <Job<Object?>>[];

  int duplicates = 0;

  Job<Profile> load(String id) {
    final mine = job<Ready, Profile>(
      key: (_Op.load, id),
      (ctx) => ctx.abandonable(() => api.load(id)),
    );
    final taken = add(mine, policy: Policy.droppable);
    if (!identical(taken, mine)) {
      // `mine` was dropped and has already ended with `Cancelled(duplicate)`;
      // `taken` is the load that was there before this call.
      duplicates++;
    }
    return taken;
  }

  @override
  void onFinish(Job<Object?> job) => finished.add(job);
}
