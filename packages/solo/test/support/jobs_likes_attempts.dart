// The first and the second attempt of the recipe of `doc/jobs.md` under "A
// tap that does not wait for a reload", verbatim: every piece of the code
// under those headings is a run of lines of this file, and
// `likes_recipe_test.dart` runs it. The page shows the methods on their own;
// here each version stands in a class.
import 'package:solo/solo.dart';

import 'jobs_likes_stubs.dart';

/// The first attempt: a reload and a like in one controller.
final class QueuedFeed extends Solo<Feed> {
  final FeedApi api;

  QueuedFeed(this.api) : super(const Feed([]));

  Job<Feed> reload() =>
      enqueue<Feed, Feed>(key: 'reload', policy: Policy.droppable, (ctx) async {
        final feed = await ctx.abandonable(api.fetchFeed);
        ctx.emit(feed);
        return feed;
      });

  Job<void> like(String postId, {required bool liked}) =>
      enqueue<Feed, void>(key: ('like', postId), (ctx) async {
        ctx.emit(ctx.state.withLiked(postId, liked: liked));
        await ctx.join(() => api.setLiked(postId, liked: liked));
      });
}

/// The second attempt: the reload of the first, and a like around the
/// queue.
final class AroundTheQueueFeed extends Solo<Feed> {
  final FeedApi api;

  AroundTheQueueFeed(this.api) : super(const Feed([]));

  Job<Feed> reload() =>
      enqueue<Feed, Feed>(key: 'reload', policy: Policy.droppable, (ctx) async {
        final feed = await ctx.abandonable(api.fetchFeed);
        ctx.emit(feed);
        return feed;
      });

  Future<void> like(String postId, {required bool liked}) async {
    externalSetState(currentState.withLiked(postId, liked: liked));
    await api.setLiked(postId, liked: liked);
  }
}
