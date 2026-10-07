// The code of `doc/camera.md` under the headings that are neither a first
// nor a second attempt, verbatim: every piece of it is a run of lines of
// this file or of the example's own `lib/src/`, and
// `camera_rakes_test.dart` runs it. The page shows each version as a method
// or a few statements on their own; here each stands in a mixin, a class
// or a function.
import 'package:solo/solo.dart';
import 'package:solo_example/solo_example.dart';

/// The example's own methods, for the versions of the page to stand on:
/// the camera has to be open, zooming or shooting before a version of
/// `dispose` can be tried. `camera_rakes_test.dart` holds each of them to
/// `lib/src/camera_controller.dart`.
mixin CameraParts on Solo<CameraState> {
  /// The hardware the controller drives.
  FakeCameraHardware get hw;

  Job<void> init() => run<NotDisposed, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        canStart: (state) => state is Initial,
        ifFailed: (state, error, stackTrace) => Broken(error),
        ifCancelled: (state, cancelled) => Broken(cancelled),
        (ctx) async {
          ctx.emit(const Preparing());
          await ctx.join(hw.open);
          ctx.emit(const Ready());
        },
      );

  Job<void> reopen() => run<NotDisposed, void>(
        key: CameraKey.reopen,
        policy: Policy.droppable,
        canStart: (state) => state is Ready || state is Broken,
        ifFailed: (state, error, stackTrace) => Broken(error),
        ifCancelled: (state, cancelled) => Broken(cancelled),
        (ctx) async {
          final zoom = switch (ctx.state) {
            Ready(:final zoom) => zoom,
            _ => 1.0,
          };
          await ctx.run(_closeCameraJob());
          ctx.emit(const Preparing());
          await ctx.join(hw.open);
          await ctx.join(() => hw.setZoom(zoom));
          ctx.emit(Ready(zoom: zoom));
        },
      );

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

  Job<void> _closeCameraJob() => job<NotDisposed, void>(
        key: CameraKey.closeCamera,
        cancellable: false,
        (ctx) async => hw.close(),
      );
}

/// "A working type wide enough": the opening before it has its handlers.
final class WideInit extends Solo<CameraState> with CameraParts {
  @override
  final FakeCameraHardware hw;

  WideInit(this.hw) : super(const Initial());

  @override
  Job<void> init() => run<NotDisposed, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        canStart: (state) => state is Initial,
        (ctx) async {
          ctx.emit(const Preparing());
          await ctx.join(hw.open);
          ctx.emit(const Ready());
        },
      );
}

/// "Checking in the body": the disposal before it takes the listener off.
mixin CheckedDisposal on CameraParts {
  Job<void> dispose() {
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
          await ctx.run(_closeCameraJob());
        }
        ctx.emit(const Disposed());
      },
    );
  }
}

/// The controller of "Checking in the body", with no listener on the
/// hardware.
final class CheckingInTheBody extends Solo<CameraState>
    with CameraParts, CheckedDisposal {
  @override
  final FakeCameraHardware hw;

  CheckingInTheBody(this.hw) : super(const Initial());
}

/// "Awaiting the disposal": the code that calls the example.
Future<void> awaitingTheDisposal() async {
  final camera = CameraController(FakeCameraHardware());
  await camera.init().value;

  camera.setZoom(2); // no await needed, and no lint about it

  // ignore: unused_local_variable
  final photo = await camera.takePhoto().value;

  switch (await camera.dispose().done) {
    case Done():
      print('disposed');
      await camera.close();
    case Cancelled(:final reason):
      print('cancelled: $reason');
    case Failed(:final error):
      print('failed: $error');
  }
}
