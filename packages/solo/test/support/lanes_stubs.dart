// What the code of `doc/lanes.md` takes for granted: the permit of the
// gate, the server behind the feed, and the camera behind the studio. The
// server and the camera write what they do to a log the test hands them,
// so a test reads one trace of the server, the camera and the controller.
import 'dart:async';

/// What the gate says of the work: whether a step may start, and whether
/// a running one may go on.
typedef Permit = ({bool start, bool keep});

/// A post of the feed, as the server sent it.
final class Post {
  final String id;
  final bool liked;

  const Post(this.id, {required this.liked});

  @override
  String toString() => liked ? '$id liked' : id;
}

/// What a call of the server throws when it fails.
final class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}

/// The server behind the feed. A reload answers two seconds after the
/// request, with the likes the server held when the request came; a like
/// answers a twentieth of a second after the request, and the server holds
/// it from then on.
final class FeedApi {
  /// Where the server writes what it did.
  final void Function(String line) log;

  /// The posts the server holds a like of.
  final liked = <String>{};

  /// Whether the next like fails.
  bool failNext = false;

  FeedApi(this.log);

  Future<List<Post>> fetchPosts() async {
    final held = {...liked};
    log('reload sent');
    await Future<void>.delayed(const Duration(seconds: 2));
    log('reload answered');
    return [
      for (final id in ['p1', 'p2']) Post(id, liked: held.contains(id)),
    ];
  }

  Future<void> setLiked(String postId, {required bool liked}) async {
    final what = liked ? 'like' : 'unlike';
    log('$what $postId sent');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (failNext) {
      failNext = false;
      log('$what $postId failed');
      throw const ApiException('offline');
    }
    if (liked) {
      this.liked.add(postId);
    } else {
      this.liked.remove(postId);
    }
    log('$what $postId confirmed');
  }
}

/// The states of the camera.
sealed class Camera {
  const Camera();
}

/// The camera is on and takes shots.
final class Ready extends Camera {
  final int zoom;

  const Ready([this.zoom = 1]);

  @override
  String toString() => 'Ready';
}

/// The camera is off.
final class Off extends Camera {
  const Off();

  @override
  String toString() => 'Off';
}

/// A notice of a stored photo, shown until the user closes it.
final class Notice {
  final int photo;

  Notice(this.photo);

  @override
  String toString() => 'Notice($photo)';
}

/// The camera device: focusing takes a twentieth of a second, a shot a
/// tenth.
final class Device {
  /// Where the device writes what it did.
  final void Function(String line) log;

  int _photos = 0;

  Device(this.log);

  Future<void> focus() async {
    log('focus started');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    log('focus done');
  }

  Future<int> shoot(int zoom) async {
    log('shot at zoom $zoom started');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    log('photo ${++_photos} stored');
    return _photos;
  }
}
