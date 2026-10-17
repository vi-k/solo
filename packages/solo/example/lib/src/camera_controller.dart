import 'dart:math';

import 'package:solo/solo.dart';

import 'camera_state.dart';
import 'fake_camera_hardware.dart';

/// Job keys. Metadata for groups of jobs hangs on the enum.
enum CameraKey {
  /// [CameraController.init].
  init,

  /// [CameraController.reopen].
  reopen,

  /// The child job that closes the hardware.
  closeCamera,

  /// [CameraController.pause].
  pause,

  /// [CameraController.resume].
  resume,

  /// [CameraController.setZoom].
  setZoom,

  /// [CameraController.setFocusPoint].
  setFocusPoint,

  /// [CameraController.resetFocusPoint].
  resetFocusPoint,

  /// [CameraController.takePhoto].
  takePhoto,

  /// [CameraController.dispose].
  dispose;

  /// Whether a job with this key changes the focus point.
  bool get touchesFocus => this == setFocusPoint || this == resetFocusPoint;
}

/// A camera whose hardware may change the state on its own.
final class CameraController extends Solo<CameraState> {
  /// The hardware this controller drives.
  final FakeCameraHardware hw;

  /// Creates a controller over [hw] and subscribes to its failures.
  CameraController(this.hw) : super(const Initial()) {
    hw.onError = (error) => externalSetState(Broken(error));
  }

  /// Takes the listener off a controller that is closed without a disposal.
  /// Past the end of closing, a report of the hardware would make
  /// [externalSetState] throw, and throw into the hardware's own callback.
  /// [dispose] takes the listener off earlier, for a reason of its own.
  @override
  void onClose() => hw.onError = null;

  /// Opens the hardware once. `W` is [NotDisposed], not [Initial]: the body
  /// emits [Preparing] and must still be allowed to read the context.
  ///
  /// An opening that fails or is cancelled lands in [Broken], the state
  /// [reopen] starts from. Left in [Preparing], the camera could not be
  /// opened again: `init` wants [Initial], `reopen` [Ready] or [Broken].
  ///
  /// A failure the hardware reports while it opens is a [NotDisposed] as
  /// well, so the working type lets it by. `keepWhile` does not: the report
  /// cancels the opening, and a job its rules cancelled leaves the reported
  /// [Broken] alone.
  Job<void> init() => run<NotDisposed, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        canStart: (state) => state is Initial,
        keepWhile: (state) => state is! Broken,
        ifFailed: (state, error, stackTrace) => Broken(error),
        ifCancelled: (state, cancelled) => Broken(cancelled),
        (ctx) async {
          ctx.emit(const Preparing());
          await ctx.join(hw.open);
          ctx.emit(const Ready());
        },
      );

  /// Closes and reopens the hardware, restoring the zoom. The close runs as
  /// a `cancellable: false` child: once started it always completes. A
  /// reopening that fails or is cancelled lands in [Broken], as [init] does.
  ///
  /// A failure reported while the hardware opens or the zoom is restored
  /// ends the reopening and stays, as in [init]. Until the body writes
  /// [Preparing] the rule lets [Broken] by: the reopening starts from it,
  /// and a failure reported while the hardware closes is the one it is
  /// there to undo. The flag goes up before that write, so a report made
  /// while the write is delivered is refused as well; the write itself is
  /// the job's own and asks none of its rules.
  Job<void> reopen() {
    var opening = false;
    return run<NotDisposed, void>(
      key: CameraKey.reopen,
      policy: Policy.droppable,
      canStart: (state) => state is Ready || state is Broken,
      keepWhile: (state) => !opening || state is! Broken,
      ifFailed: (state, error, stackTrace) => Broken(error),
      ifCancelled: (state, cancelled) => Broken(cancelled),
      (ctx) async {
        final zoom = switch (ctx.state) {
          Ready(:final zoom) => zoom,
          _ => 1.0,
        };
        // `run` throws what the close threw: hardware that is still open
        // must not be reopened over in silence.
        await ctx.run(_closeCameraJob());
        opening = true;
        ctx.emit(const Preparing());
        await ctx.join(hw.open);
        await ctx.join(() => hw.setZoom(zoom));
        ctx.emit(Ready(zoom: zoom));
      },
    );
  }

  Job<void> _closeCameraJob() => job<NotDisposed, void>(
        key: CameraKey.closeCamera,
        cancellable: false,
        (ctx) async => hw.close(),
      );

  /// Pauses the preview; a paused camera takes no commands.
  Job<void> pause() => run<Ready, void>(
        key: CameraKey.pause,
        policy: Policy.droppable,
        canStart: (state) => !state.paused,
        (ctx) async => ctx.emit(ctx.state.copyWith(paused: true)),
      );

  /// Resumes the preview.
  Job<void> resume() => run<Ready, void>(
        key: CameraKey.resume,
        policy: Policy.droppable,
        canStart: (state) => state.paused,
        (ctx) async => ctx.emit(ctx.state.copyWith(paused: false)),
      );

  /// Only the last requested zoom matters: `replace` drops queued ones.
  Job<void> setZoom(double zoom) => run<Ready, void>(
        key: CameraKey.setZoom,
        policy: Policy.replace,
        describe: () => 'zoom: $zoom',
        canStart: (state) => !state.paused,
        (ctx) async {
          await ctx.join(() => hw.setZoom(zoom));
          ctx.emit(ctx.state.copyWith(zoom: zoom));
        },
      );

  /// Replaces queued focus jobs of both kinds: a group of keys, so the
  /// queue is managed directly instead of through a policy.
  Job<void> setFocusPoint(Point<double> point) {
    queue.removeWhere(
      (job) => job.key is CameraKey && (job.key! as CameraKey).touchesFocus,
    );
    return run<Ready, void>(
      key: CameraKey.setFocusPoint,
      describe: () => '$point',
      canStart: (state) => !state.paused,
      (ctx) async {
        await ctx.join(() => hw.setFocusPoint(point));
        ctx.emit(ctx.state.copyWith(focusPoint: point));
      },
    );
  }

  /// Restores automatic focus, replacing queued focus jobs of both kinds.
  Job<void> resetFocusPoint() {
    queue.removeWhere(
      (job) => job.key is CameraKey && (job.key! as CameraKey).touchesFocus,
    );
    return run<Ready, void>(
      key: CameraKey.resetFocusPoint,
      canStart: (state) => !state.paused,
      (ctx) async {
        await ctx.join(() => hw.setFocusPoint(null));
        ctx.emit(Ready(zoom: ctx.state.zoom, paused: ctx.state.paused));
      },
    );
  }

  /// One shot at a time; requests queued during the shot are dropped.
  Job<Photo> takePhoto() => run<Ready, Photo>(
        key: CameraKey.takePhoto,
        policy: Policy.droppable,
        canStart: (state) => !state.paused,
        (ctx) async {
          final photo = await ctx.join(hw.capture);
          queue.clear();
          ctx.log('captured $photo');
          return photo;
        },
      );

  /// Clears the way: drops the queued commands, cancels the current job,
  /// closes the hardware. Await it, then call [close] to release the
  /// controller.
  Job<void> dispose() {
    // The source of external states goes first: the disposal below decides
    // the final state, and a `Broken` reported after it would replace
    // `Disposed`. `onClose` comes too late for that report: the controller
    // is closed after the disposal, not by it.
    hw.onError = null;
    // Not `force`: an earlier disposal still in the queue is not
    // cancellable, so it survives the clear, and `droppable` below hands it
    // to this call too. Forced out, it would end `Cancelled` for its caller
    // while this one did the disposing.
    queue.clear();
    current?.cancel();
    return run<CameraState, void>(
      key: CameraKey.dispose,
      policy: Policy.droppable,
      cancellable: false,
      (ctx) async {
        if (ctx.state is Disposed) {
          return;
        }
        if (ctx.state is! Initial) {
          // `run` throws what the close threw: hardware that is still open
          // is not a disposal, and `Disposed` here would say it was.
          await ctx.run(_closeCameraJob());
        }
        ctx.emit(const Disposed());
      },
    );
  }
}
