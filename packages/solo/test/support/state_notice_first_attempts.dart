// The first attempt of "A notice the screen accepts" in `doc/state.md`,
// verbatim: every piece of its block is a run of lines of this file, and
// `notice_recipe_test.dart` runs it. The page adds `Saved` to the states of
// the camera, which are sealed, so this file holds states of its own; the
// page shows `shoot` and `accept` on their own, and here they stand in
// their class.
import 'package:solo/solo.dart';

import 'state_camera_stubs.dart' show Device, store;

/// Not on the page: the states of the camera, less what this section does
/// not touch.
sealed class CameraState {
  const CameraState();
}

/// Not on the page: the camera is on and takes commands.
final class Ready extends CameraState {
  final int zoom;

  const Ready({this.zoom = 1});

  @override
  String toString() => 'Ready(zoom: $zoom)';
}

final class Saved extends CameraState {
  final int photo;

  const Saved(this.photo);
}

final class Camera extends Solo<CameraState> {
  final Device device;

  Camera(this.device) : super(const Ready());

  Job<void> shoot() => enqueue<Ready, void>((ctx) async {
    final photo = await ctx.join(device.shoot);
    ctx.emit(Saved(photo));
  });

  Job<void> accept() =>
      enqueue<Saved, void>((ctx) async => ctx.emit(const Ready()));

  /// Not on the page: the variant the prose names, which writes the notice
  /// and takes it back at once.
  Job<void> shootAndPass() => enqueue<Ready, void>((ctx) async {
    final photo = await ctx.join(device.shoot);
    ctx
      ..emit(Saved(photo))
      ..emit(const Ready());
  });

  /// Not on the page: the recording of "The rules", less its `canStart`
  /// and `keepWhile`: it runs for as long as the frames come.
  Job<void> record() => enqueue<Ready, void>(
    key: 'record',
    (ctx) => ctx.each(device.frames, (child, frame) async {
      await child.join(() => store(frame));
    }).value,
  );

  /// Not on the page: the zoom, set at once.
  Job<void> zoomTo(int zoom) =>
      enqueue<Ready, void>((ctx) async => ctx.emit(Ready(zoom: zoom)));
}
