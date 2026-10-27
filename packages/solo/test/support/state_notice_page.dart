// The answer of "A notice the screen accepts" in `doc/state.md`, verbatim:
// every piece of its blocks is a run of lines of this file, and
// `notice_recipe_test.dart` runs it. The page shows `shoot` of the camera
// on its own; here it stands in its class, with what the tests need of the
// board between the page's pieces.
import 'package:solo/solo.dart';

import 'state_camera_stubs.dart';

final class Notice {
  final int photo;

  Notice(this.photo);
}

final class NoticeBoard {
  final Notice? notice;

  const NoticeBoard([this.notice]);
}

final class Notices extends Solo<NoticeBoard> {
  Notices() : super(const NoticeBoard());

  Job<void> post(Notice notice) =>
      enqueue<NoticeBoard, void>((ctx) async => ctx.emit(NoticeBoard(notice)));

  /// Not on the page: an acceptance that names no notice.
  Job<void> acceptAny() =>
      enqueue<NoticeBoard, void>((ctx) async => ctx.emit(const NoticeBoard()));

  Job<void> accept(Notice notice) => enqueue<NoticeBoard, void>((ctx) async {
        // Only the notice the screen showed: a newer one stays.
        if (identical(ctx.state.notice, notice)) ctx.emit(const NoticeBoard());
      });
}

/// Not on the page: the camera, handed the board.
final class Camera extends Solo<CameraState> {
  final Device device;

  final Notices notices;

  Camera(this.device, this.notices) : super(const Ready());

  Job<void> shoot() => enqueue<Ready, void>((ctx) async {
        final photo = await ctx.join(device.shoot);
        notices.post(Notice(photo));
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
