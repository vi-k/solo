// The first attempts of `doc/lanes.md`, verbatim: every piece of the code
// under a "The first attempt" heading is a run of lines of this file, and
// `lanes_rakes_test.dart` runs it. The page shows a method or a field of a
// controller on its own; here each version stands in a class of its own,
// with the rest of its controller taken from the answers.
import 'package:solo/solo.dart';

import 'lanes_page.dart' show Feed, Mark;
import 'lanes_stubs.dart';

final class Gate extends Solo<Permit> {
  Gate() : super((start: true, keep: true));

  Job<void> refresh(Future<Permit> Function() read) =>
      enqueue<Permit, void>((ctx) async => ctx.emit(await ctx.join(read)));
}

final class Worker extends Solo<Permit> {
  final Gate gate;

  Worker(this.gate) : super(gate.currentState) {
    gate.addListener(_sync);
  }

  void _sync() => externalSetState(gate.currentState);

  Job<void> run(Future<void> Function() step) => enqueue<Permit, void>(
    canStart: (s) => s.start,
    keepWhile: (s) => s.keep,
    (ctx) => ctx.join(step),
  );

  // Called once, when the last job of the worker is over.
  @override
  void onClose() => gate.removeListener(_sync);
}

/// The feed whose like writes a copy of the state it read before the wait.
final class CopyingFeed extends SoloLanes<Feed> {
  final FeedApi api;
  int _confirmations = 0;

  late final SoloLane<Feed> _reload;
  late final SoloLane<Feed> _likes;

  CopyingFeed(this.api) : super(const Feed()) {
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
        final feed = ctx.state;
        ctx.emit(feed.mark(postId, Mark(liked)));
        await ctx.join(() => api.setLiked(postId, liked: liked));
        ctx.emit(feed.mark(postId, Mark(liked, ++_confirmations)));
      });
}

/// The feed whose reload writes the answer of the server as the whole
/// state.
final class SnapshotFeed extends SoloLanes<Feed> {
  final FeedApi api;
  int _confirmations = 0;

  late final SoloLane<Feed> _reload;
  late final SoloLane<Feed> _likes;

  SnapshotFeed(this.api) : super(const Feed()) {
    _reload = lane('reload');
    _likes = lane('likes');
  }

  Job<void> reload() => _reload.enqueue<Feed, void>(
    key: 'reload',
    policy: Policy.droppable,
    (ctx) async {
      final posts = await ctx.abandonable(api.fetchPosts);
      ctx.emit(Feed(posts: posts));
    },
  );

  Job<void> setLiked(String postId, {required bool liked}) =>
      _likes.enqueue<Feed, void>((ctx) async {
        ctx.emit(ctx.state.mark(postId, Mark(liked)));
        await ctx.join(() => api.setLiked(postId, liked: liked));
        ctx.emit(ctx.state.mark(postId, Mark(liked, ++_confirmations)));
      });
}

final class Studio {
  final Camera camera;
  final Notice? notice;

  const Studio(this.camera, [this.notice]);
}

/// The studio over a class with fields.
final class ClassStudioController extends SoloLanes<Studio> {
  final Device device;

  late final SoloLane<Studio> _camera;

  ClassStudioController(this.device) : super(const Studio(Ready())) {
    _camera = lane('camera');
  }

  Job<void> shoot() => _camera.enqueue<Studio, void>(
    canStart: (studio) => studio.camera is Ready,
    (ctx) async {
      await ctx.join(device.focus);
      final zoom = (ctx.state.camera as Ready).zoom;
      final photo = await ctx.join(() => device.shoot(zoom));
      ctx.emit(Studio(ctx.state.camera, Notice(photo)));
    },
  );

  /// Not on the page: the camera reports what the device did.
  void reflect(Camera camera) =>
      externalSetState(Studio(camera, currentState.notice));
}

final class FeedController extends SoloLanes<Feed> {
  final FeedApi api;
  int _confirmations = 0;

  late final _reload = lane('reload');
  late final _likes = lane('likes');

  FeedController(this.api) : super(const Feed());

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
