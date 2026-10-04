// The first and the second attempts of `doc/camera.md`, verbatim: every
// piece of the code under a "The first attempt" or "The second attempt"
// heading is a run of lines of this file or of
// `camera_attempts_listener.dart`, and `camera_rakes_test.dart` runs it. The
// page shows each as a method or a few statements on their own; here each
// version stands in a class or a function.
import 'package:solo/solo.dart';
import 'package:solo_example/solo_example.dart';

import 'camera_page.dart';

/// The first attempt of "Opening the camera": the working type named after
/// the state the job starts from.
final class NarrowInit extends Solo<CameraState> with CameraParts {
  @override
  final FakeCameraHardware hw;

  NarrowInit(this.hw) : super(const Initial());

  @override
  Job<void> init() => run<Initial, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        (ctx) async {
          ctx.emit(const Preparing());
          await ctx.join(hw.open);
          ctx.emit(const Ready());
        },
      );
}

/// The first attempt of "An opening that fails": the landing written as a
/// catch. The page shows the body alone; the rest of the method is the
/// answer of the section above.
final class CatchingInit extends Solo<CameraState> with CameraParts {
  @override
  final FakeCameraHardware hw;

  CatchingInit(this.hw) : super(const Initial());

  @override
  Job<void> init() => run<NotDisposed, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        canStart: (state) => state is Initial,
        (ctx) async {
          ctx.emit(const Preparing());
          try {
            await ctx.join(hw.open);
          } on Object catch (error) {
            ctx.emit(Broken(error));
            rethrow;
          }
          ctx.emit(const Ready());
        },
      );
}

/// The first attempt of "Only the last zoom": the default policy.
final class QueuedZoom extends Solo<CameraState> with CameraParts {
  @override
  final FakeCameraHardware hw;

  QueuedZoom(this.hw) : super(const Initial());

  @override
  Job<void> setZoom(double zoom) => run<Ready, void>(
        key: CameraKey.setZoom,
        describe: () => 'zoom: $zoom',
        (ctx) async {
          await ctx.join(() => hw.setZoom(zoom));
          ctx.emit(ctx.state.copyWith(zoom: zoom));
        },
      );
}

/// The first attempt of "Disposing of the camera": a disposal queued like
/// any other job.
base class QueuedDisposal extends Solo<CameraState> with CameraParts {
  @override
  final FakeCameraHardware hw;

  QueuedDisposal(this.hw) : super(const Initial());

  Job<void> dispose() => run<CameraState, void>(
        key: CameraKey.dispose,
        policy: Policy.droppable,
        cancellable: false,
        canStart: (state) => state is! Disposed,
        (ctx) async {
          if (ctx.state is! Initial) {
            await ctx.run(_closeCameraJob());
          }
          ctx.emit(const Disposed());
        },
      );

  Job<void> _closeCameraJob() => job<NotDisposed, void>(
        key: CameraKey.closeCamera,
        cancellable: false,
        (ctx) async => hw.close(),
      );
}

/// The second attempt of the same section: the way cleared, `Disposed`
/// still refused by `canStart`.
final class ClearingDisposal extends QueuedDisposal {
  ClearingDisposal(super.hw);

  @override
  Job<void> dispose() {
    queue.clear();
    current?.cancel();
    return run<CameraState, void>(
      key: CameraKey.dispose,
      policy: Policy.droppable,
      cancellable: false,
      canStart: (state) => state is! Disposed,
      (ctx) async {
        if (ctx.state is! Initial) {
          await ctx.run(_closeCameraJob());
        }
        ctx.emit(const Disposed());
      },
    );
  }
}

/// The first attempt of "Closing the controller": the disposal and the
/// close in the same turn.
Future<void> closingInTheSameTurn(CameraController camera) async {
  camera.dispose();
  await camera.close();
}

/// The second attempt of the same section: the close that runs the queue.
Future<void> closingWithADrain(CameraController camera) async {
  camera.dispose();
  await camera.close(mode: SoloCloseMode.drain);
}
