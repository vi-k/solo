// What the code of "A pool of places" in `doc/lanes.md` takes for granted:
// the server behind the feed, which takes uploads of photos besides likes.
// It writes what it does to a log the test hands it, as the server of
// `lanes_stubs.dart` does, and a like of its own can be told to be slow.
import 'dart:async';

/// A photo the server has stored.
final class Photo {
  final String file;

  const Photo(this.file);

  @override
  String toString() => 'Photo($file)';
}

/// The server behind the feed of "A pool of places". A like answers a
/// twentieth of a second after the request, or two seconds for a call named
/// in [slow]; an upload is stored a tenth of a second after the request,
/// which is all the photo it returns says.
final class FeedApi {
  /// Where the server writes what it did.
  final void Function(String line) log;

  /// The calls that take two seconds, once each: `like p1`, `unlike p2`.
  final slow = <String>{};

  FeedApi(this.log);

  Future<void> setLiked(String postId, {required bool liked}) async {
    final what = '${liked ? 'like' : 'unlike'} $postId';
    log('$what sent');
    await Future<void>.delayed(
      slow.remove(what)
          ? const Duration(seconds: 2)
          : const Duration(milliseconds: 50),
    );
    log('$what confirmed');
  }

  Future<Photo> upload(String file) async {
    log('upload $file sent');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return Photo(file);
  }
}
