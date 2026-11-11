// The code of `doc/lanes.md` under "Work that a new epoch makes stale",
// verbatim: every piece of it is a run of lines of this file, and
// `lanes_rakes_test.dart` runs it. The feed of that section carries an
// epoch, so it stands here with a feed of its own; the page shows the two
// methods on their own.
import 'package:solo/solo.dart';

import 'lanes_page.dart' show Mark;
import 'lanes_stubs.dart';

/// The marks of the likes, and the epoch they were made in.
final class Feed {
  final int epoch;
  final Map<String, Mark> marks;

  const Feed({this.epoch = 0, this.marks = const {}});

  Feed mark(String postId, Mark? mark) => Feed(
    epoch: epoch,
    marks: {
      for (final MapEntry(:key, :value) in marks.entries)
        if (key != postId) key: value,
      postId: ?mark,
    },
  );
}

final class EpochFeedController extends SoloLanes<Feed> {
  final FeedApi api;
  int _confirmations = 0;

  late final SoloLane<Feed> _account;
  late final SoloLane<Feed> _likes;

  EpochFeedController(this.api) : super(const Feed()) {
    _account = lane('account');
    _likes = lane('likes');
  }

  Job<void> signOut() => _account.enqueue<Feed, void>(
    // A new epoch: the work of the lanes for the last user is stale.
    (ctx) async => ctx.emit(Feed(epoch: ctx.state.epoch + 1)),
  );

  Job<void> like(String postId) {
    final epoch = currentState.epoch;
    return _likes.enqueue<Feed, void>(
      keepWhile: (feed) => feed.epoch == epoch,
      (ctx) async {
        ctx.emit(ctx.state.mark(postId, const Mark(true)));
        await ctx.join(() => api.setLiked(postId, liked: true));
        // Not reached once the epoch has changed.
        ctx.emit(ctx.state.mark(postId, Mark(true, ++_confirmations)));
      },
    );
  }
}
