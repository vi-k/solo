// What the recipe of `doc/jobs.md` under "A tap that does not wait for a
// reload" takes for granted: the feed, its posts and the server behind them.
// The server answers a reload two seconds after the request, with the likes
// it held when the request came; it answers a like a twentieth of a second
// after the request and holds the like from then on.
import 'dart:async';

/// A post of the feed, as the server sent it.
final class Post {
  final String id;
  final bool liked;

  const Post(this.id, {required this.liked});
}

/// The posts of the feed, as the last reload brought them.
final class Feed {
  final List<Post> posts;

  const Feed(this.posts);

  /// The feed with one post liked or not.
  Feed withLiked(String postId, {required bool liked}) => Feed([
    for (final post in posts)
      Post(post.id, liked: post.id == postId ? liked : post.liked),
  ]);

  /// Whether the post of [postId] is liked here.
  bool likes(String postId) =>
      posts.firstWhere((post) => post.id == postId).liked;
}

/// What a call of the server throws when it fails.
final class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}

/// The server behind the feed. [now] tells the time of the test, which the
/// trace writes each line with.
final class FeedApi {
  final Duration Function() now;

  /// What the server did, in order.
  final trace = <String>[];

  /// The posts the server holds a like of.
  final liked = <String>{};

  /// How long a like takes, in milliseconds.
  int likeTake = 50;

  /// Whether the next like fails.
  bool failNext = false;

  FeedApi(this.now);

  void _log(String line) => trace.add('${now().inMilliseconds} ms: $line');

  Future<Feed> fetchFeed() async {
    final held = {...liked};
    _log('reload sent');
    await Future<void>.delayed(const Duration(seconds: 2));
    _log('reload answered');
    return Feed([
      for (final id in ['p1', 'p2']) Post(id, liked: held.contains(id)),
    ]);
  }

  Future<void> setLiked(String postId, {required bool liked}) async {
    _log('${liked ? 'like' : 'unlike'} $postId sent');
    await Future<void>.delayed(Duration(milliseconds: likeTake));
    if (failNext) {
      failNext = false;
      _log('${liked ? 'like' : 'unlike'} $postId failed');
      throw const ApiException('offline');
    }
    if (liked) {
      this.liked.add(postId);
    } else {
      this.liked.remove(postId);
    }
    _log('${liked ? 'like' : 'unlike'} $postId confirmed');
  }
}
