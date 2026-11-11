// The answers of `doc/lanes.md`, verbatim, less the first attempts and the
// epoch: every piece of the code under the answer headings is a run of lines
// of this file, and `lanes_rakes_test.dart` runs it. The page shows the like
// that reads at the write as a method on its own; here it stands in a class
// of its own, beside the reload of the recipe.
import 'package:solo/solo.dart';

import 'lanes_stubs.dart';

final class Station extends SoloLanes<Permit> {
  late final SoloLane<Permit> _gate;
  late final SoloLane<Permit> _work;

  Station() : super((start: true, keep: true)) {
    _gate = lane('gate');
    _work = lane('work');
  }

  Job<void> refresh(Future<Permit> Function() read) => _gate
      .enqueue<Permit, void>((ctx) async => ctx.emit(await ctx.join(read)));

  Job<void> run(Future<void> Function() step) => _work.enqueue<Permit, void>(
    canStart: (s) => s.start,
    keepWhile: (s) => s.keep,
    (ctx) => ctx.join(step),
  );
}

/// The feed with the like of "A write that keeps the other lane's work":
/// it reads the state where it writes.
final class ReadingFeed extends SoloLanes<Feed> {
  final FeedApi api;
  int _confirmations = 0;

  late final SoloLane<Feed> _reload;
  late final SoloLane<Feed> _likes;

  ReadingFeed(this.api) : super(const Feed()) {
    _reload = lane('reload');
    _likes = lane('likes');
  }

  Job<void> reload() => _reload.enqueue<Feed, void>(
    key: 'reload',
    policy: Policy.droppable,
    (ctx) async {
      final seen = _confirmations;
      final posts = await ctx.abandonable(api.fetchPosts);
      ctx.emit(ctx.state.withPosts(posts).settled(seen));
    },
  );

  Job<void> setLiked(String postId, {required bool liked}) =>
      _likes.enqueue<Feed, void>((ctx) async {
        ctx.emit(ctx.state.mark(postId, Mark(liked)));
        await ctx.join(() => api.setLiked(postId, liked: liked));
        ctx.emit(ctx.state.mark(postId, Mark(liked, ++_confirmations)));
      });
}

/// A like the screen shows over the feed.
final class Mark {
  final bool liked;

  /// The number of the confirmation, or `null` while the like is on its way.
  final int? confirmation;

  const Mark(this.liked, [this.confirmation]);
}

final class Feed {
  final List<Post> posts;
  final Map<String, Mark> marks;

  const Feed({this.posts = const [], this.marks = const {}});

  Feed withPosts(List<Post> posts) => Feed(posts: posts, marks: marks);

  Feed mark(String postId, Mark? mark) => Feed(
    posts: posts,
    marks: {
      for (final MapEntry(:key, :value) in marks.entries)
        if (key != postId) key: value,
      postId: ?mark,
    },
  );

  /// Drops the marks of the likes the server had confirmed when a reload
  /// was sent after [seen] confirmations; a like on its way keeps its mark.
  Feed settled(int seen) => Feed(
    posts: posts,
    marks: {
      for (final MapEntry(:key, :value) in marks.entries)
        if (value.confirmation == null || value.confirmation! > seen)
          key: value,
    },
  );
}

final class FeedController extends SoloLanes<Feed> {
  final FeedApi api;
  int _confirmations = 0;

  late final SoloLane<Feed> _reload;
  late final SoloLane<Feed> _likes;

  FeedController(this.api) : super(const Feed()) {
    _reload = lane('reload');
    _likes = lane('likes');
  }

  Job<void> reload() => _reload.enqueue<Feed, void>(
    key: 'reload',
    policy: Policy.droppable,
    (ctx) async {
      final seen = _confirmations;
      final posts = await ctx.abandonable(api.fetchPosts);
      ctx.emit(ctx.state.withPosts(posts).settled(seen));
    },
  );

  Job<void> setLiked(String postId, {required bool liked}) {
    Mark? before;
    return _likes.enqueue<Feed, void>(
      ifFailed: (feed, error, stackTrace) => feed.mark(postId, before),
      ifCancelled: (feed, cancelled) => feed.mark(postId, before),
      isExpectedError: (error) => error is ApiException,
      (ctx) async {
        before = ctx.state.marks[postId];
        ctx.emit(ctx.state.mark(postId, Mark(liked)));
        await ctx.join(() => api.setLiked(postId, liked: liked));
        ctx.emit(ctx.state.mark(postId, Mark(liked, ++_confirmations)));
      },
    );
  }
}

typedef Studio = ({Camera camera, Notice? notice});

final class StudioController extends SoloLanes<Studio> {
  final Device device;

  late final SoloLane<Studio> _camera;
  late final SoloLane<Studio> _notices;

  StudioController(this.device) : super((camera: const Ready(), notice: null)) {
    _camera = lane('camera');
    _notices = lane('notices');
  }

  Job<void> shoot() =>
      _camera.enqueue<({Ready camera, Notice? notice}), void>((ctx) async {
        await ctx.join(device.focus);
        // W says the camera is Ready, and so does ctx.state.
        final zoom = ctx.state.camera.zoom;
        final photo = await ctx.join(() => device.shoot(zoom));
        ctx.emit((camera: ctx.state.camera, notice: Notice(photo)));
      });

  /// Not on the page: the camera reports what the device did, as
  /// `externalSetState` reflects a fact on the state page.
  void reflect(Camera camera) =>
      externalSetState((camera: camera, notice: currentState.notice));

  Job<void> accept(Notice notice) =>
      _notices.enqueue<Studio, void>((ctx) async {
        if (identical(ctx.state.notice, notice)) {
          ctx.emit((camera: ctx.state.camera, notice: null));
        }
      });
}
