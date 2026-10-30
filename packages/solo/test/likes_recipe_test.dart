@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/jobs_likes.dart';
import 'support/jobs_likes_attempts.dart';
import 'support/jobs_likes_stubs.dart';

/// The recipe of `doc/jobs.md` under "A tap that does not wait for a
/// reload": what each version does to a like tapped during a reload.

/// The alternative the recipe names in one sentence: the wait for the
/// server in a job of its own, outside the queue, and the publication of
/// the feed a short job of the queue, as under "A delayed start".
final class _DelayedPublishFeed extends Solo<Feed> {
  final FeedApi api;

  _DelayedPublishFeed(this.api) : super(const Feed([]));

  void reload() {
    Job<Feed>((ctx) => ctx.abandonable(api.fetchFeed)).whenFinished((outcome) {
      if (outcome case Done(:final value)) {
        enqueue<Feed, void>((ctx) async => ctx.emit(value));
      }
    });
  }

  Job<void> like(String postId, {required bool liked}) =>
      enqueue<Feed, void>((ctx) async {
        ctx.emit(ctx.state.withLiked(postId, liked: liked));
        await ctx.join(() => api.setLiked(postId, liked: liked));
      });
}

/// Holds `doc/jobs.md` to [phrase]: the test that calls this runs what the
/// phrase says. Whitespace is folded, so a phrase is found wherever its lines
/// were broken.
void _says(String phrase) => expect(
  File(
    'doc/jobs.md',
  ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ').contains(phrase),
  isTrue,
  reason: 'doc/jobs.md no longer says: $phrase',
);

void main() {
  test('the server of the recipe answers as its first paragraph says', () {
    _says('its `fetchFeed()` answers two seconds after the request');
    _says(
      'its `setLiked` answers a twentieth of a second after the request, or '
      'throws an `ApiException` when the request fails',
    );
    fakeAsync((async) {
      final api = FeedApi(() => async.elapsed);
      unawaited(api.fetchFeed());
      unawaited(api.setLiked('p1', liked: true));
      async.flushTimers();
      api.failNext = true;
      Object? thrown;
      unawaited(
        api.setLiked('p2', liked: true).catchError((Object e) {
          thrown = e;
        }),
      );
      async.flushTimers();
      expect(api.trace, [
        '0 ms: reload sent',
        '0 ms: like p1 sent',
        '50 ms: like p1 confirmed',
        '2000 ms: reload answered',
        '2000 ms: like p2 sent',
        '2050 ms: like p2 failed',
      ]);
      expect(thrown, isA<ApiException>());
    });
  });

  group('The first attempt', () {
    test('droppable drops a second reload while one is on its way', () {
      _says('`droppable` drops a second reload while one is on its way');
      fakeAsync((async) {
        final api = FeedApi(() => async.elapsed);
        final feed = QueuedFeed(api);
        final first = feed.reload();
        async.elapse(const Duration(milliseconds: 100));
        expect(feed.reload(), same(first));
        async.flushTimers();
        expect(api.trace, ['0 ms: reload sent', '2000 ms: reload answered']);
        feed.close().ignore();
        async.flushTimers();
      });
    });

    test('a like tapped during the reload is shown and sent after it', () {
      _says(
        'A like tapped 100 ms into the reload starts when the reload has '
        'ended. The heart lights at 2000 ms, and the like reaches the server '
        'then.',
      );
      fakeAsync((async) {
        final api = FeedApi(() => async.elapsed);
        final feed = QueuedFeed(api);
        final shown = <String>[];
        feed.addListener(
          () => shown.add(
            '${async.elapsed.inMilliseconds} ms: '
            '${feed.currentState.posts.map((p) => '${p.id} ${p.liked}')}',
          ),
        );
        feed.reload();
        async.elapse(const Duration(milliseconds: 100));
        feed.like('p1', liked: true);
        async.flushTimers();
        expect(api.trace, [
          '0 ms: reload sent',
          '2000 ms: reload answered',
          '2000 ms: like p1 sent',
          '2050 ms: like p1 confirmed',
        ]);
        expect(shown, [
          '2000 ms: (p1 false, p2 false)',
          '2000 ms: (p1 true, p2 false)',
        ]);
        feed.close().ignore();
        async.flushTimers();
      });
    });
  });

  group('The second attempt', () {
    test('the like goes at once, and the reload takes it off the screen', () {
      _says(
        'the heart lights at 100 ms, and the server confirms the like at '
        '150 ms. But the reload asked the server at 0 ms, before the like, '
        'and at 2000 ms it publishes what it was told',
      );
      fakeAsync((async) {
        final api = FeedApi(() => async.elapsed);
        final feed = AroundTheQueueFeed(api)..reload();
        async.flushTimers();
        api.trace.clear();
        final start = async.elapsed.inMilliseconds;
        feed.reload();
        async.elapse(const Duration(milliseconds: 100));
        unawaited(feed.like('p1', liked: true));
        expect(feed.currentState.likes('p1'), isTrue, reason: 'at once');
        async.elapse(const Duration(milliseconds: 1900));
        expect(api.trace, [
          '$start ms: reload sent',
          '${start + 100} ms: like p1 sent',
          '${start + 150} ms: like p1 confirmed',
          '${start + 2000} ms: reload answered',
        ]);
        expect(api.liked, {'p1'}, reason: 'the server holds the like');
        expect(feed.currentState.likes('p1'), isFalse);

        feed.reload();
        async.flushTimers();
        expect(feed.currentState.likes('p1'), isTrue, reason: 'next reload');
        feed.close().ignore();
        async.flushTimers();
      });
    });
  });

  group('A controller for the likes', () {
    late FeedApi api;
    late LikesController likes;
    late FeedController feed;

    /// What the screen shows of each post.
    String screen() => [
      for (final post in feed.currentState.posts)
        '${post.id} ${shownLiked(post, likes.currentState)}',
    ].join(', ');

    void open(FakeAsync async) {
      api = FeedApi(() => async.elapsed);
      likes = LikesController(api);
      feed = FeedController(api, likes)..reload();
      async.flushTimers();
      api.trace.clear();
    }

    void closeAll(FakeAsync async) {
      feed.close().ignore();
      likes.close().ignore();
      async.flushTimers();
    }

    test('a like tapped during the reload goes at once and stays shown', () {
      _says(
        '| A like during a reload | The heart lights at once, and the like '
        'reaches the server at once. The reload publishes the feed without '
        'the like, and the mark stays over it. |',
      );
      _says(
        '| The next reload | The feed brings the like, and the mark goes. |',
      );
      fakeAsync((async) {
        open(async);
        final start = async.elapsed.inMilliseconds;
        feed.reload();
        async.elapse(const Duration(milliseconds: 100));
        likes.setLiked('p1', liked: true);
        async.flushMicrotasks();
        expect(screen(), 'p1 true, p2 false', reason: 'at once');
        async.elapse(const Duration(milliseconds: 1900));
        expect(api.trace, [
          '$start ms: reload sent',
          '${start + 100} ms: like p1 sent',
          '${start + 150} ms: like p1 confirmed',
          '${start + 2000} ms: reload answered',
        ]);
        expect(feed.currentState.likes('p1'), isFalse, reason: 'stale');
        expect(screen(), 'p1 true, p2 false');
        expect(likes.currentState.byPost.keys, ['p1'], reason: 'kept');

        feed.reload();
        async.flushTimers();
        expect(feed.currentState.likes('p1'), isTrue);
        expect(likes.currentState.byPost, isEmpty, reason: 'settled');
        expect(screen(), 'p1 true, p2 false');
        closeAll(async);
      });
    });

    test('a like confirmed before the reload is sent is settled by it', () {
      _says(
        '| A like confirmed, then a reload sent | That reload settles the '
        'mark. |',
      );
      fakeAsync((async) {
        open(async);
        likes.setLiked('p1', liked: true);
        async.elapse(const Duration(milliseconds: 100));
        feed.reload();
        async.flushTimers();
        expect(likes.currentState.byPost, isEmpty);
        expect(screen(), 'p1 true, p2 false');
        closeAll(async);
      });
    });

    test('settle waits behind a slow like and keeps its numbered mark', () {
      _says(
        '`settle` stands in the same queue behind the likes, so every mark it '
        'meets has its number',
      );
      fakeAsync((async) {
        open(async);
        api.likeTake = 3000;
        likes.setLiked('p1', liked: true);
        feed.reload();
        async.elapse(const Duration(milliseconds: 2500));
        expect(likes.currentState.byPost['p1']?.confirmation, isNull);
        expect(screen(), 'p1 true, p2 false');
        async.flushTimers();
        expect(likes.currentState.byPost['p1']?.confirmation, 1);
        expect(screen(), 'p1 true, p2 false');
        closeAll(async);
      });
    });

    test('a like and an unlike of one post go in order', () {
      _says(
        '| A like and an unlike of one post | The server gets them in that '
        'order. |',
      );
      fakeAsync((async) {
        open(async);
        likes
          ..setLiked('p1', liked: true)
          ..setLiked('p1', liked: false);
        async.flushTimers();
        expect(api.trace.map((line) => line.split(': ').last), [
          'like p1 sent',
          'like p1 confirmed',
          'unlike p1 sent',
          'unlike p1 confirmed',
        ]);
        expect(api.liked, isEmpty);
        expect(screen(), 'p1 false, p2 false');
        closeAll(async);
      });
    });

    test('a failed like takes its mark back, and nothing reaches the zone', () {
      _says(
        '| The like fails | The post shows what it showed before the tap, and '
        'nothing reaches the zone. |',
      );
      fakeAsync((async) {
        open(async);
        final errors = <Object>[];
        late Job<void> job;
        runZonedGuarded(() {
          api.failNext = true;
          job = likes.setLiked('p1', liked: true);
        }, (error, stackTrace) => errors.add(error));
        async.flushMicrotasks();
        expect(screen(), 'p1 true, p2 false', reason: 'shown at once');
        async.flushTimers();
        expect(job.outcome, isA<Failed>());
        expect(screen(), 'p1 false, p2 false');
        expect(likes.currentState.byPost, isEmpty);
        expect(errors, isEmpty);
        closeAll(async);
      });
    });

    test('a failed unlike brings back the confirmed like', () {
      _says('a failed unlike brings back a confirmed like');
      fakeAsync((async) {
        open(async);
        likes.setLiked('p1', liked: true);
        async.flushTimers();
        api.failNext = true;
        likes.setLiked('p1', liked: false);
        async.flushTimers();
        expect(screen(), 'p1 true, p2 false');
        expect(likes.currentState.byPost['p1']?.confirmation, 1);
        closeAll(async);
      });
    });

    test('a like of another post waits behind a slow one', () {
      _says(
        '| A like of another post during a slow one | It waits for the first '
        'to be confirmed. |',
      );
      _says('For a request of a twentieth of a second that is acceptable');
      fakeAsync((async) {
        open(async);
        api.likeTake = 500;
        final start = async.elapsed.inMilliseconds;
        likes.setLiked('p1', liked: true);
        async.elapse(const Duration(milliseconds: 10));
        likes.setLiked('p2', liked: true);
        async.elapse(const Duration(milliseconds: 10));
        expect(screen(), 'p1 true, p2 false', reason: 'p2 waits');
        async.flushTimers();
        expect(api.trace, [
          '$start ms: like p1 sent',
          '${start + 500} ms: like p1 confirmed',
          '${start + 500} ms: like p2 sent',
          '${start + 1000} ms: like p2 confirmed',
        ]);
        closeAll(async);
      });
    });

    test('a cancelled like takes its mark back until a reload', () {
      _says(
        '| The like is cancelled | Once its request has answered, the post '
        'shows what it showed before the tap, until a reload brings the '
        "server's word. |",
      );
      fakeAsync((async) {
        open(async);
        api.likeTake = 500;
        likes.setLiked('p1', liked: true);
        async.elapse(const Duration(milliseconds: 100));
        expect(screen(), 'p1 true, p2 false');
        likes.cancelAll().ignore();
        async.flushMicrotasks();
        expect(screen(), 'p1 true, p2 false', reason: 'the request is out');
        async.elapse(const Duration(milliseconds: 400));
        expect(api.liked, {'p1'}, reason: 'the server took the like');
        expect(screen(), 'p1 false, p2 false');
        expect(likes.currentState.byPost, isEmpty);
        feed.reload();
        async.flushTimers();
        expect(screen(), 'p1 true, p2 false');
        closeAll(async);
      });
    });

    test('a second tap on a post waits for its like, and its mark too', () {
      _says(
        '| A second tap on the post while its like is on its way | It waits '
        'for the first like to be confirmed, and the heart answers it then. |',
      );
      fakeAsync((async) {
        open(async);
        api.likeTake = 300;
        final start = async.elapsed.inMilliseconds;
        likes.setLiked('p1', liked: true);
        async.elapse(const Duration(milliseconds: 10));
        likes.setLiked('p1', liked: false);
        async.elapse(const Duration(milliseconds: 10));
        expect(screen(), 'p1 true, p2 false', reason: 'the tap waits');
        async.elapse(const Duration(milliseconds: 280));
        expect(screen(), 'p1 false, p2 false', reason: 'the first confirmed');
        async.flushTimers();
        expect(api.trace, [
          '$start ms: like p1 sent',
          '${start + 300} ms: like p1 confirmed',
          '${start + 300} ms: unlike p1 sent',
          '${start + 600} ms: unlike p1 confirmed',
        ]);
        closeAll(async);
      });
    });

    test('a screen that flips the heart takes the value from its last tap', () {
      _says(
        'a screen that flips the heart takes the new value from its own last '
        'tap rather than from `shownLiked`: a third tap during the wait would '
        'read the heart the second tap has not turned yet and repeat the '
        'second tap',
      );

      /// Taps the heart of p1 three times, 10 ms apart, with the value
      /// [next] gives.
      void tapThrice(FakeAsync async, bool Function() next) {
        for (var i = 0; i < 3; i++) {
          likes.setLiked('p1', liked: next());
          async.elapse(const Duration(milliseconds: 10));
        }
        async.flushTimers();
      }

      fakeAsync((async) {
        open(async);
        api.likeTake = 300;
        tapThrice(
          async,
          () => !shownLiked(feed.currentState.posts.first, likes.currentState),
        );
        expect(
          api.trace
              .map((line) => line.split(': ').last)
              .where((line) => line.endsWith('sent')),
          ['like p1 sent', 'unlike p1 sent', 'unlike p1 sent'],
          reason: 'the third tap repeats the second',
        );
        expect(api.liked, isEmpty);
        closeAll(async);
      });
      fakeAsync((async) {
        open(async);
        api.likeTake = 300;
        var tapped = false;
        tapThrice(async, () => tapped = !tapped);
        expect(api.liked, {'p1'});
        expect(screen(), 'p1 true, p2 false');
        closeAll(async);
      });
    });
  });

  group('The alternative of "A delayed start"', () {
    test('the like goes at once, and the reload still takes it off', () {
      _says(
        'A like in the same controller then goes at once, but the reload '
        'still publishes what the server held before the like',
      );
      _says(
        '`ctx.unattended` does not help: a like that calls it waits in '
        'the queue first.',
      );
      fakeAsync((async) {
        final api = FeedApi(() => async.elapsed);
        final feed = _DelayedPublishFeed(api)..reload();
        async.flushTimers();
        api.trace.clear();
        final start = async.elapsed.inMilliseconds;
        feed.reload();
        async.elapse(const Duration(milliseconds: 100));
        feed.like('p1', liked: true);
        async.elapse(const Duration(milliseconds: 1900));
        expect(api.trace, [
          '$start ms: reload sent',
          '${start + 100} ms: like p1 sent',
          '${start + 150} ms: like p1 confirmed',
          '${start + 2000} ms: reload answered',
        ]);
        expect(api.liked, {'p1'});
        expect(feed.currentState.likes('p1'), isFalse);
        feed.close().ignore();
        async.flushTimers();
      });
    });
  });
}
