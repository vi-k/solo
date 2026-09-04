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

  /// Opens the hardware once. `W` is [NotDisposed], not [Initial]: the body
  /// emits [Preparing] and must still be allowed to read the context.
  Job<void> init() => run<NotDisposed, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        canStart: (state) => state is Initial,
        (ctx) async {
          ctx.emit(const Preparing());
          await ctx.wait(hw.open);
          ctx.emit(const Ready());
        },
      );

  /// Closes and reopens the hardware, restoring the zoom. The close runs as
  /// a `cancellable: false` child: once started it always completes.
  Job<void> reopen() => run<NotDisposed, void>(
        key: CameraKey.reopen,
        policy: Policy.droppable,
        canStart: (state) => state is Ready || state is Broken,
        (ctx) async {
          final zoom = switch (ctx.state) {
            Ready(:final zoom) => zoom,
            _ => 1.0,
          };
          await ctx.run(_closeCameraJob()).done;
          ctx.emit(const Preparing());
          try {
            await ctx.wait(hw.open);
            await ctx.wait(() => hw.setZoom(zoom));
          } on Cancelled {
            rethrow;
          } on Object catch (error) {
            ctx.emit(Broken(error));
            rethrow;
          }
          ctx.emit(Ready(zoom: zoom));
        },
      );

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
          await ctx.wait(() => hw.setZoom(zoom));
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
        await ctx.wait(() => hw.setFocusPoint(point));
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
        await ctx.wait(() => hw.setFocusPoint(null));
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
          final photo = await ctx.wait(hw.capture);
          queue.clear();
          ctx.log('captured $photo');
          return photo;
        },
      );

  /// Forces the way: clears the queue, cancels the current job, closes the
  /// hardware. Call [close] afterwards to release the controller.
  Job<void> dispose() {
    queue.clear(force: true);
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
          await ctx.run(_closeCameraJob()).done;
        }
        ctx.emit(const Disposed());
      },
    );
  }
}
