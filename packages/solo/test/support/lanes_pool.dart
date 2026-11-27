// The code of `doc/lanes.md` under "A pool", verbatim: every piece of it is
// a run of lines of this file, and `lanes_rakes_test.dart` runs it. Its
// server takes uploads besides likes, so the feed of that section stands
// here with a server of its own.
import 'package:solo/solo.dart';

import 'lanes_page.dart' show Feed, Mark;
import 'lanes_pool_stubs.dart';

final class FeedController extends SoloLanes<Feed> {
  final FeedApi api;
  int _confirmations = 0;

  late final SoloPool<Feed> _likes;
  late final SoloPool<Feed> _uploads;

  FeedController(this.api) : super(const Feed()) {
    _likes = pool('likes', concurrency: 4);
    _uploads = pool('uploads', concurrency: 2);
  }

  // No key: any two uploads may run together, two at a time.
  Job<Photo> upload(String file) =>
      _uploads.enqueue<Feed, Photo>((ctx) => ctx.join(() => api.upload(file)));

  int get uploading => _uploads.running.length;
  int get waiting => _uploads.queue.length;

  // Likes of different posts run side by side, up to four at once; a like
  // and an unlike of one post run in the order of the taps.
  Job<void> setLiked(String postId, {required bool liked}) =>
      _likes.enqueue<Feed, void>(key: postId, (ctx) async {
        ctx.emit(ctx.state.mark(postId, Mark(liked)));
        await ctx.join(() => api.setLiked(postId, liked: liked));
        ctx.emit(ctx.state.mark(postId, Mark(liked, ++_confirmations)));
      });
}
