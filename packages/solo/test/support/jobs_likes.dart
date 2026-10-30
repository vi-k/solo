// The answer of the recipe of `doc/jobs.md` under "A tap that does not wait
// for a reload", verbatim: every piece of the code under "A controller for
// the likes" is a run of lines of this file, and `likes_recipe_test.dart`
// runs it.
import 'package:solo/solo.dart';

import 'jobs_likes_stubs.dart';

/// A like the screen shows over the feed.
final class Mark {
  final bool liked;

  /// The number of the confirmation, or `null` while the like is on its way.
  final int? confirmation;

  const Mark(this.liked, [this.confirmation]);
}

final class Marks {
  final Map<String, Mark> byPost;

  const Marks([this.byPost = const {}]);

  Marks put(String postId, Mark? mark) => Marks({
    for (final MapEntry(:key, :value) in byPost.entries)
      if (key != postId) key: value,
    postId: ?mark,
  });
}

final class LikesController extends Solo<Marks> {
  final FeedApi api;
  int _confirmations = 0;

  LikesController(this.api) : super(const Marks());

  /// How many likes the server has confirmed so far.
  int get confirmations => _confirmations;

  Job<void> setLiked(String postId, {required bool liked}) {
    Mark? before;
    return enqueue<Marks, void>(
      // No confirmation: the post shows what it showed before the tap.
      ifFailed: (marks, error, stackTrace) => marks.put(postId, before),
      ifCancelled: (marks, cancelled) => marks.put(postId, before),
      isExpectedError: (error) => error is ApiException,
      (ctx) async {
        before = ctx.state.byPost[postId];
        ctx.emit(ctx.state.put(postId, Mark(liked)));
        await ctx.join(() => api.setLiked(postId, liked: liked));
        ctx.emit(ctx.state.put(postId, Mark(liked, ++_confirmations)));
      },
    );
  }

  /// Drops the marks that a reload sent after [seen] confirmations brings.
  Job<void> settle(int seen) => enqueue<Marks, void>((ctx) async {
    final kept = {
      for (final MapEntry(key: postId, value: mark) in ctx.state.byPost.entries)
        if (mark.confirmation! > seen) postId: mark,
    };
    if (kept.length < ctx.state.byPost.length) ctx.emit(Marks(kept));
  });
}

final class FeedController extends Solo<Feed> {
  final FeedApi api;
  final LikesController likes;

  FeedController(this.api, this.likes) : super(const Feed([]));

  Job<Feed> reload() =>
      enqueue<Feed, Feed>(key: 'reload', policy: Policy.droppable, (ctx) async {
        final seen = likes.confirmations;
        final feed = await ctx.abandonable(api.fetchFeed);
        ctx.emit(feed);
        likes.settle(seen);
        return feed;
      });
}

/// Whether the screen shows [post] liked.
bool shownLiked(Post post, Marks marks) =>
    marks.byPost[post.id]?.liked ?? post.liked;
