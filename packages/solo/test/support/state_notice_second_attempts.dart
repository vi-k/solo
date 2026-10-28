// The second attempt of "A notice the screen accepts" in `doc/state.md`,
// verbatim: every piece of its block is a run of lines of this file, and
// `notice_recipe_test.dart` runs it. The page gives `Ready` a field for the
// notice, so this file holds states of its own; the page shows `shoot` and
// `accept` on their own, and here they stand in their class.
import 'package:solo/solo.dart';

import 'state_camera_stubs.dart' show Device, store;

/// Not on the page: the states of the camera.
sealed class CameraState {
  const CameraState();
}

/// Not on the page: the camera is on and takes commands, and [notice] is
/// the photo the notice tells of, or `null`.
final class Ready extends CameraState {
  final int zoom;

  final int? notice;

  const Ready({this.zoom = 1, this.notice});

  Ready withNotice(int? notice) => Ready(zoom: zoom, notice: notice);

  @override
  String toString() => 'Ready(zoom: $zoom, notice: $notice)';
}

/// Not on the page: the device is gone.
final class Disconnected extends CameraState {
  const Disconnected();

  @override
  String toString() => 'Disconnected';
}

final class Camera extends Solo<CameraState> {
  final Device device;

  Camera(this.device) : super(const Ready());

  Job<void> shoot() => enqueue<Ready, void>((ctx) async {
    final photo = await ctx.join(device.shoot);
    ctx.emit(ctx.state.withNotice(photo));
  });

  Job<void> accept() =>
      enqueue<Ready, void>((ctx) async => ctx.emit(ctx.state.withNotice(null)));

  /// Not on the page: the acceptance put ahead of the waiting jobs.
  Job<void> acceptFirst() => enqueueJob(
    job<Ready, void>((ctx) async => ctx.emit(ctx.state.withNotice(null))),
    first: true,
  );

  /// Not on the page: the acceptance the prose names, written at once.
  void acceptAtOnce() {
    final state = currentState;
    if (state is Ready) externalSetState(state.withNotice(null));
  }

  /// Not on the page: a fact of the device, written at once.
  void reflect(CameraState state) => externalSetState(state);

  /// Not on the page: a body that reads the state before a wait and writes
  /// a copy of it after.
  Job<void> zoomTo(int zoom) => enqueue<Ready, void>((ctx) async {
    final state = ctx.state;
    await ctx.join(() => device.setZoom(zoom));
    ctx.emit(Ready(zoom: zoom, notice: state.notice));
  });

  /// Not on the page: the recording of "The rules", less its `canStart`
  /// and `keepWhile`: it runs for as long as the frames come.
  Job<void> record() => enqueue<Ready, void>(
    key: 'record',
    (ctx) => ctx.each(device.frames, (child, frame) async {
      await child.join(() => store(frame));
    }).value,
  );
}
