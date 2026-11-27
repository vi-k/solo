@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/lanes_epoch.dart' as epochs;
import 'support/lanes_first_attempts.dart' as first;
import 'support/lanes_page.dart' as page;
import 'support/lanes_pool.dart' as pooled;
import 'support/lanes_pool_stubs.dart' as server;
import 'support/lanes_pool_stubs.dart' show Photo;
import 'support/lanes_stubs.dart';
import 'support/page_code.dart';

/// The sentinel of `doc/lanes.md`.
///
/// The code of the page stands verbatim in `test/support/lanes_*.dart`: the
/// first attempts in one file, the answers in another, and the section on
/// the epoch, whose feed has a field the others lack, in a third. The tests
/// below run that code, hold the traces the page quotes under its `text`
/// fences to what the code prints, and pin what its prose and its table of
/// cases say. What the page states of the engine and its code does not show
/// is pinned on the controllers of this file.

String _page() => File('doc/lanes.md').readAsStringSync();

/// Holds the page to [phrase]: the test that calls this runs what the phrase
/// says. Whitespace is folded, so a phrase is found wherever its lines were
/// broken.
void _says(String phrase) => expect(
  _page().replaceAll(RegExp(r'\s+'), ' '),
  contains(phrase),
  reason: 'doc/lanes.md no longer says this',
);

/// What the page quotes under its `text` fences, in order, line by line.
List<List<String>> _quotes() => [
  for (final block in RegExp(
    r'```text\n(.*?)\n```',
    dotAll: true,
  ).allMatches(_page()))
    block.group(1)!.split('\n'),
];

/// Runs [scenario] under fake time and returns what it said, each line with
/// the time it was said at. Errors that reach the zone go to [errors].
List<String> _trace(
  void Function(FakeAsync async, void Function(String line) say) scenario, {
  List<Object>? errors,
}) {
  final trace = <String>[];
  fakeAsync((async) {
    void say(String line) =>
        trace.add('${async.elapsed.inMilliseconds} ms: $line');
    if (errors == null) {
      scenario(async, say);
    } else {
      runZonedGuarded(() => scenario(async, say), (e, s) => errors.add(e));
    }
    async.flushTimers();
  });
  return trace;
}

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// The feed as the listener of the page prints it: the posts, and the marks
/// over them with the numbers of their confirmations.
String _feed(page.Feed feed) {
  final posts = feed.posts.isEmpty ? 'none' : feed.posts.join(', ');
  final marks = feed.marks.isEmpty
      ? 'none'
      : [
          for (final MapEntry(key: id, value: mark) in feed.marks.entries)
            [
              id,
              if (mark.liked) 'liked' else 'unliked',
              if (mark.confirmation case final number?) '#$number',
            ].join(' '),
        ].join(', ');
  return 'posts $posts; marks $marks';
}

/// The scenario of "Two queues over one state": a step of 100 ms at 0 ms,
/// the permit withdrawn at 30 ms, a second step at 40 ms, the permit back
/// and a third step at 150 ms.
List<String> _permitTrace(
  Job<void> Function(Future<Permit> Function() read) Function() refresh,
  Job<void> Function(Future<void> Function() step) Function() run,
) => _trace((async, say) {
  final doRefresh = refresh();
  final doRun = run();
  var steps = 0;
  void go() {
    final number = ++steps;
    doRun(() async {
      say('step $number started');
      await Future<void>.delayed(_ms(100));
      say('step $number ended');
    }).whenFinished((outcome) => say('run $number: $outcome'));
  }

  void permit(Permit permit) {
    say('refresh $permit');
    doRefresh(() async => permit);
  }

  go();
  async.elapse(_ms(30));
  permit((start: false, keep: false));
  async.elapse(_ms(10));
  go();
  async.elapse(_ms(110));
  permit((start: true, keep: true));
  async.flushMicrotasks();
  go();
});

/// The feeds of the page, under one face for the scenarios.
typedef _Feed = ({
  SoloController<page.Feed> controller,
  Job<void> Function() reload,
  Job<void> Function(String postId, {required bool liked}) setLiked,
});

_Feed _copying(FeedApi api) {
  final feed = first.CopyingFeed(api);
  return (controller: feed, reload: feed.reload, setLiked: feed.setLiked);
}

_Feed _reading(FeedApi api) {
  final feed = page.ReadingFeed(api);
  return (controller: feed, reload: feed.reload, setLiked: feed.setLiked);
}

_Feed _snapshot(FeedApi api) {
  final feed = first.SnapshotFeed(api);
  return (controller: feed, reload: feed.reload, setLiked: feed.setLiked);
}

_Feed _recipe(FeedApi api) {
  final feed = page.FeedController(api);
  return (controller: feed, reload: feed.reload, setLiked: feed.setLiked);
}

/// [make] over a server that writes to the trace, with a listener that
/// prints the state.
_Feed _listened(
  _Feed Function(FeedApi api) make,
  void Function(String line) say,
) {
  final feed = make(FeedApi(say));
  final controller = feed.controller;
  controller.addListener(() => say(_feed(controller.currentState)));
  return feed;
}

/// The like of the epoch with a correction, as a job of the recipe has one.
final class _CorrectedEpochs extends SoloLanes<epochs.Feed> {
  late final SoloLane<epochs.Feed> account;
  late final SoloLane<epochs.Feed> likes;
  final corrections = <String>[];

  _CorrectedEpochs() : super(const epochs.Feed()) {
    account = lane('account');
    likes = lane('likes');
  }

  SoloJob<void> like(Completer<void> server) {
    final epoch = currentState.epoch;
    return likes.enqueue<epochs.Feed, void>(
      keepWhile: (feed) => feed.epoch == epoch,
      ifCancelled: (feed, cancelled) {
        corrections.add('ifCancelled');
        return feed;
      },
      (ctx) => ctx.join(() => server.future),
    );
  }

  void signOut() => account.enqueue<epochs.Feed, void>(
    (ctx) async => ctx.emit(epochs.Feed(epoch: ctx.state.epoch + 1)),
  );

  void write() => account.enqueue<epochs.Feed, void>(
    (ctx) async => ctx.emit(ctx.state.mark('p9', const page.Mark(true))),
  );
}

/// The like of the epoch, and a sign-out that carries the marks over to the
/// new epoch.
final class _CarryingEpochs extends SoloLanes<epochs.Feed> {
  final FeedApi api;
  late final SoloLane<epochs.Feed> account;
  late final SoloLane<epochs.Feed> likes;

  _CarryingEpochs(this.api) : super(const epochs.Feed()) {
    account = lane('account');
    likes = lane('likes');
  }

  SoloJob<void> like(String postId) {
    final epoch = currentState.epoch;
    return likes.enqueue<epochs.Feed, void>(
      keepWhile: (feed) => feed.epoch == epoch,
      (ctx) async {
        ctx.emit(ctx.state.mark(postId, const page.Mark(true)));
        await ctx.join(() => api.setLiked(postId, liked: true));
        ctx.emit(ctx.state.mark(postId, const page.Mark(true, 1)));
      },
    );
  }

  void signOut() => account.enqueue<epochs.Feed, void>(
    (ctx) async => ctx.emit(
      epochs.Feed(epoch: ctx.state.epoch + 1, marks: ctx.state.marks),
    ),
  );
}

/// The like of the epoch with `ctx.abandonable` in place of `ctx.join`.
final class _AbandoningEpochs extends SoloLanes<epochs.Feed> {
  final FeedApi api;
  late final SoloLane<epochs.Feed> account;
  late final SoloLane<epochs.Feed> likes;

  _AbandoningEpochs(this.api) : super(const epochs.Feed()) {
    account = lane('account');
    likes = lane('likes');
  }

  SoloJob<void> like(String postId) {
    final epoch = currentState.epoch;
    return likes.enqueue<epochs.Feed, void>(
      keepWhile: (feed) => feed.epoch == epoch,
      (ctx) => ctx.abandonable(() => api.setLiked(postId, liked: true)),
    );
  }

  void signOut() => account.enqueue<epochs.Feed, void>(
    (ctx) async => ctx.emit(epochs.Feed(epoch: ctx.state.epoch + 1)),
  );
}

/// The shot of the class studio with a `keepWhile` beside its `canStart`.
final class _KeepingClassStudio extends SoloLanes<first.Studio> {
  final Device device;
  late final SoloLane<first.Studio> camera;

  _KeepingClassStudio(this.device) : super(const first.Studio(Ready())) {
    camera = lane('camera');
  }

  SoloJob<void> shoot() => camera.enqueue<first.Studio, void>(
    canStart: (studio) => studio.camera is Ready,
    keepWhile: (studio) => studio.camera is Ready,
    (ctx) async {
      await ctx.join(device.focus);
      final zoom = (ctx.state.camera as Ready).zoom;
      final photo = await ctx.join(() => device.shoot(zoom));
      ctx.emit(first.Studio(ctx.state.camera, Notice(photo)));
    },
  );

  void reflect(Camera camera) =>
      externalSetState(first.Studio(camera, currentState.notice));
}

/// Two lanes over a number, `a` declared before `b`, and a log of starts.
final class _Two extends SoloLanes<int> {
  final log = <String>[];
  late final SoloLane<int> a;
  late final SoloLane<int> b;

  _Two() : super(0) {
    a = lane('a');
    b = lane('b');
  }

  List<SoloLane<int>> get declared => lanes;

  SoloLane<int> declare(String name) => lane(name);

  @override
  void onStart(Job<Object?> job) => log.add('start ${job.key}');
}

/// The state of a feed that a reload takes through `Loading`.
sealed class _Load {
  const _Load();
}

final class _Loading extends _Load {
  const _Loading();
}

final class _Loaded extends _Load {
  const _Loaded();
}

/// A reload lane that writes `Loading`, and a likes lane whose jobs need
/// `Loaded`.
final class _Loads extends SoloLanes<_Load> {
  late final SoloLane<_Load> reload;
  late final SoloLane<_Load> likes;

  _Loads() : super(const _Loaded()) {
    reload = lane('reload');
    likes = lane('likes');
  }
}

/// The uploads of "A pool of places", under one face for the scenarios:
/// the worker of the first attempt, or `null` for the pool, and what the
/// controller says of its uploads after the taps, or `null` for the worker.
typedef _Uploads = ({
  SoloController<page.Feed> controller,
  Job<Photo> Function(String file) upload,
  SoloJob<Object?>? Function() worker,
  String? Function() counts,
});

_Uploads _worker(server.FeedApi api) {
  final feed = first.WorkerFeed(api);
  return (
    controller: feed,
    upload: feed.upload,
    worker: () => feed.worker,
    counts: () => null,
  );
}

_Uploads _pooled(server.FeedApi api) {
  final feed = pooled.FeedController(api);
  return (
    controller: feed,
    upload: feed.upload,
    worker: () => null,
    counts: () => 'uploading ${feed.uploading}, waiting ${feed.waiting}',
  );
}

/// The scenario of "A pool of places": four photos picked at 0 ms, the
/// third cancelled at once when [cancelThird], a drain asked for at 20 ms,
/// and the rest of a minute; then whatever is still left without an end.
List<String> _uploadsTrace(
  _Uploads Function(server.FeedApi api) make, {
  required bool cancelThird,
  List<Object>? errors,
}) => _trace((async, say) {
  final uploads = make(server.FeedApi(say));
  // The worker of the first attempt starts in the turn after the
  // constructor.
  async.flushMicrotasks();
  uploads.worker()?.whenFinished((outcome) => say('worker: $outcome'));
  final jobs = <String, Job<Photo>>{};
  for (final file in ['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg']) {
    final job = jobs[file] = uploads.upload(file)
      ..whenFinished((outcome) => say('$file: $outcome'));
    if (cancelThird && file == 'c.jpg') job.cancel();
  }
  async.flushMicrotasks();
  if (uploads.counts() case final counts?) say(counts);
  async.elapse(_ms(20));
  say('close(mode: drain)');
  final controller = uploads.controller;
  controller.close(mode: SoloCloseMode.drain).then((_) => say('closed'));
  async.elapse(const Duration(minutes: 1) - _ms(20));
  for (final MapEntry(key: file, value: job) in jobs.entries) {
    if (job.outcome == null) say('$file: no outcome');
  }
  if (!controller.isFinished) say('closing is held by ${controller.pending}');
}, errors: errors);

/// The marks of a feed, as the listener of the likes in "A pool of places"
/// prints them: the posts play no part there.
String _marks(page.Feed feed) => 'marks ${_feed(feed).split('; marks ').last}';

/// The likes of "A pool of places" in one lane, as the likes lane of "A
/// merge" runs them.
final class _LaneLikes extends SoloLanes<page.Feed> {
  final server.FeedApi api;
  late final SoloLane<page.Feed> likes;

  _LaneLikes(this.api) : super(const page.Feed()) {
    likes = lane('likes');
  }

  Job<void> setLiked(String postId, {required bool liked}) =>
      likes.enqueue<page.Feed, void>(key: postId, (ctx) async {
        ctx.emit(ctx.state.mark(postId, page.Mark(liked)));
        await ctx.join(() => api.setLiked(postId, liked: liked));
      });
}

/// The taps of the likes in "A pool of places": a like of `p1` at 10 ms,
/// which the server takes two seconds over, its unlike at 20 ms, and a like
/// of `p2` at 150 ms.
List<String> _likesTrace<C extends SoloController<page.Feed>>(
  C Function(server.FeedApi api) make,
  Job<void> Function(C feed, String postId, {required bool liked}) setLiked,
) => _trace((async, say) {
  final feed = make(server.FeedApi(say)..slow.add('like p1'));
  feed.addListener(() => say(_marks(feed.currentState)));
  async.elapse(_ms(10));
  setLiked(feed, 'p1', liked: true);
  async.elapse(_ms(10));
  setLiked(feed, 'p1', liked: false);
  async.elapse(_ms(130));
  setLiked(feed, 'p2', liked: true);
});

/// A pool over a number between two lanes, in the order `before`, `places`,
/// `after`, and a log of the starts of root jobs.
final class _Places extends SoloLanes<int> {
  final log = <String>[];
  late final SoloLane<int> before;
  late final SoloPool<int> places;
  late final SoloLane<int> after;

  _Places({int concurrency = 2}) : super(0) {
    before = lane('before');
    places = pool('places', concurrency: concurrency);
    after = lane('after');
  }

  List<SoloPool<int>> get declared => pools;

  SoloPool<int> declare(String name, {int concurrency = 1}) =>
      pool(name, concurrency: concurrency);

  SoloLane<int> declareLane(String name) => lane(name);

  @override
  void onStart(Job<Object?> job) => log.add('start ${job.key}');
}

void main() {
  tearDown(() {
    Solo.observer = null;
    Solo.debug = null;
  });

  group('Two queues over one state', () {
    test('two controllers carry the permit through a copy', () {
      _says(
        'A step of 100 ms starts at 0 ms, the server withdraws the permit at '
        '30 ms, a second step is asked for at 40 ms, and the permit comes back '
        'at 150 ms with a third',
      );
      late first.Gate gate;
      late first.Worker worker;
      final trace = _permitTrace(() {
        gate = first.Gate();
        worker = first.Worker(gate);
        return gate.refresh;
      }, () => worker.run);
      expect(trace, _quotes()[0]);
    });

    test('two lanes print the same trace', () {
      _says('The same steps and refreshes print the same trace.');
      late page.Station station;
      final trace = _permitTrace(() {
        station = page.Station();
        return station.refresh;
      }, () => station.run);
      expect(trace, _quotes()[0]);
    });

    test('the step under join runs to its end after keep went', () {
      _says(
        'The first step runs to its end at 100 ms, though `keep` went at 30 ms',
      );
      expect(_quotes()[0], containsAllInOrder(['100 ms: step 1 ended']));
    });

    test('restart cancels the running job of its own lane only', () {
      _says(
        'A `Policy` looks for its key in its own lane only, so `restart` '
        'cancels the running job of its own lane and leaves the other lanes '
        'alone.',
      );
      fakeAsync((async) {
        final two = _Two();
        final gate = Completer<void>();
        final inA = two.a.enqueue<int, void>(key: 'k', (ctx) => gate.future);
        final inB = two.b.enqueue<int, void>(key: 'k', (ctx) => gate.future);
        async.flushMicrotasks();
        two.a.enqueue<int, void>(
          key: 'k',
          policy: Policy.restart,
          (ctx) async {},
        );
        async.flushMicrotasks();

        expect(inA.isCancelled, isTrue);
        expect(inB.isCancelled, isFalse);
        gate.complete();
        two.close().ignore();
        async.flushMicrotasks();
      });
    });

    test('a lane refuses a job of another lane', () {
      _says(
        'A lane queues only the jobs it made: a job of another lane or of '
        'another controller is refused with an `ArgumentError`.',
      );
      final two = _Two();
      expect(
        () => two.b.enqueueJob(two.a.job<int, void>((ctx) async {})),
        throwsArgumentError,
      );
    });
  });

  group("A write that keeps the other lane's work", () {
    void tapLate(FakeAsync async, _Feed feed) {
      feed.reload();
      async.elapse(_ms(1980));
      feed.setLiked('p1', liked: true);
    }

    test('a copy read before the wait drops the posts of the reload', () {
      _says('The reload is sent at 0 ms, and a like is tapped at 1980 ms');
      final trace = _trace(
        (async, say) => tapLate(async, _listened(_copying, say)),
      );
      expect(trace, _quotes()[1]);
      expect(trace.last, endsWith('posts none; marks p1 liked #1'));
    });

    test('a read at the write keeps them', () {
      final trace = _trace(
        (async, say) => tapLate(async, _listened(_reading, say)),
      );
      expect(trace, _quotes()[2]);
    });

    List<String> overWrites(_Feed Function(FeedApi api) make) {
      final lines = <String>[];
      Solo.debug = lines.add;
      try {
        _trace((async, say) => tapLate(async, _listened(make, say)));
      } finally {
        Solo.debug = null;
      }
      return [
        for (final line in lines)
          if (line.contains('emit over')) line,
      ];
    }

    test('Solo.debug names the write over the reload, and only that one', () {
      _says(
        'with [`Solo.debug`](diagnostics.md#logs) set, the second `emit` '
        'of the first attempt comes with a line',
      );
      _says(
        'A job that has not read the state gets none, and neither does '
        'the read at the write.',
      );
      expect(overWrites(_copying), _quotes()[3]);
      expect(overWrites(_reading), isEmpty);
    });
  });

  group('A snapshot from the server', () {
    test('the answer as the whole state takes the mark away', () {
      _says('The reload is sent at 0 ms, and a like is tapped at 100 ms');
      final trace = _trace((async, say) {
        final feed = _listened(_snapshot, say);
        feed.reload();
        async.elapse(_ms(100));
        feed.setLiked('p1', liked: true);
      });
      expect(trace, _quotes()[4]);
    });

    test('the merge keeps it until a reload sent after it', () {
      _says('The same taps, and a second reload sent at 2100 ms');
      final trace = _trace((async, say) {
        final feed = _listened(_recipe, say);
        feed.reload();
        async.elapse(_ms(100));
        feed.setLiked('p1', liked: true);
        async.elapse(_ms(2000));
        feed.reload();
      });
      expect(trace, _quotes()[5]);
    });

    test('a failed like puts back the mark it found, and nothing reaches '
        'the zone', () {
      _says(
        'when the like fails or is cancelled, `ifFailed` or `ifCancelled` '
        'puts it back: the post shows what it showed before the tap',
      );
      _says('and it does not go on to the zone');
      final errors = <Object>[];
      late page.FeedController feed;
      _trace((async, say) {
        final api = FeedApi(say);
        feed = page.FeedController(api)..setLiked('p1', liked: true);
        async.elapse(_ms(100));
        api.failNext = true;
        feed.setLiked('p1', liked: false);
      }, errors: errors);

      expect(errors, isEmpty);
      final mark = feed.currentState.marks['p1']!;
      expect((mark.liked, mark.confirmation), (true, 1));
    });

    test('a cancelled like puts back the mark it found', () {
      _says(
        'when the like fails or is cancelled, `ifFailed` or `ifCancelled` '
        'puts it back',
      );
      late page.FeedController feed;
      late Job<void> unlike;
      page.Mark? during;
      _trace((async, say) {
        feed = page.FeedController(FeedApi(say))..setLiked('p1', liked: true);
        async.elapse(_ms(100));
        unlike = feed.setLiked('p1', liked: false);
        async.elapse(_ms(10));
        during = feed.currentState.marks['p1'];
        feed.close().ignore();
      });

      expect(during?.liked, isFalse);
      expect(unlike.outcome, isA<Cancelled>());
      final mark = feed.currentState.marks['p1']!;
      expect((mark.liked, mark.confirmation), (true, 1));
    });

    test('a like waits for no reload, and the like of a second post waits '
        'for the first', () {
      _says('A like does not wait for a reload.');
      _says(
        'A like of a second post still waits for the first: there is one '
        'likes lane.',
      );
      final trace = _trace((async, say) {
        final feed = page.FeedController(FeedApi(say))..reload();
        async.elapse(_ms(100));
        feed
          ..setLiked('p1', liked: true)
          ..setLiked('p2', liked: true);
      });
      expect(trace, [
        '0 ms: reload sent',
        '100 ms: like p1 sent',
        '150 ms: like p1 confirmed',
        '150 ms: like p2 sent',
        '200 ms: like p2 confirmed',
        '2000 ms: reload answered',
      ]);
    });
  });

  group('Work that a new epoch makes stale', () {
    test('a sign-out cancels the like at once, and the next at its start', () {
      _says(
        'A like of `p1` is sent at 0 ms, a like of `p2` waits behind it, and '
        'the user signs out at 10 ms',
      );
      _says(
        'The new epoch cancels the like of `p1` at 10 ms, at the write that '
        'changes it',
      );
      _says('`keepWhile` is asked at the start too, and its body never runs.');
      late SoloJob<void> p1;
      late SoloJob<void> p2;
      var cancelledAtTheChange = false;
      final trace = _trace((async, say) {
        final feed = epochs.EpochFeedController(FeedApi(say));
        p1 = feed.like('p1') as SoloJob<void>
          ..whenFinished((outcome) => say('like p1: $outcome'));
        p2 = feed.like('p2') as SoloJob<void>
          ..whenFinished((outcome) => say('like p2: $outcome'));
        async.elapse(_ms(10));
        say('sign out');
        feed.signOut();
        async.flushMicrotasks();
        cancelledAtTheChange = p1.isCancelled && p1.outcome == null;
      });

      expect(trace, _quotes()[6]);
      expect(cancelledAtTheChange, isTrue);
      expect(
        p2.outcome,
        isA<Cancelled>().having((c) => c.started, 'started', isFalse),
      );
    });

    test('a job its rules cancelled gets no ifCancelled', () {
      _says('a job its rules cancelled gets no `ifCancelled`');
      fakeAsync((async) {
        final feed = _CorrectedEpochs();
        final server = Completer<void>();
        final like = feed.like(server);
        async.flushMicrotasks();
        feed.signOut();
        async.flushMicrotasks();
        server.complete();
        async.flushMicrotasks();

        expect(like.outcome, isA<Cancelled>());
        expect(feed.corrections, isEmpty);
      });
    });

    test('the sign-out takes down the mark the like put up', () {
      _says(
        'Nothing of the like takes down the mark it put up at 0 ms. The '
        'sign-out does: it writes the new epoch as a new `Feed`, whose marks '
        'are empty.',
      );
      _says(
        'A sign-out that carried the marks over to the new epoch would leave '
        'the mark of `p1` on its way for good.',
      );
      fakeAsync((async) {
        final feed = epochs.EpochFeedController(FeedApi((_) {}))..like('p1');
        async.flushMicrotasks();
        expect(feed.currentState.marks['p1']?.confirmation, isNull);
        expect(feed.currentState.marks['p1']?.liked, isTrue);
        async.elapse(_ms(10));
        feed.signOut();
        async.elapse(_ms(100));
        expect(feed.currentState.marks, isEmpty);
      });
      fakeAsync((async) {
        final feed = _CarryingEpochs(FeedApi((_) {}))..like('p1');
        async.elapse(_ms(10));
        feed.signOut();
        async.elapse(_ms(100));
        final mark = feed.currentState.marks['p1'];
        expect(mark?.liked, isTrue);
        expect(mark?.confirmation, isNull);
      });
    });

    test('a write that keeps the epoch cancels nobody', () {
      _says('A write that keeps the epoch cancels nobody.');
      fakeAsync((async) {
        final feed = _CorrectedEpochs();
        final server = Completer<void>();
        final like = feed.like(server);
        async.flushMicrotasks();
        feed.write();
        async.flushMicrotasks();
        server.complete();
        async.flushMicrotasks();

        expect(like.outcome, isA<Done<void>>());
      });
    });

    test('the like holds its lane, and close, until the server answers', () {
      _says(
        'The like of `p1` holds the likes lane until the server answers at 50 '
        'ms, and a `close()` called at 10 ms completes then.',
      );
      final trace = _trace((async, say) {
        final feed = epochs.EpochFeedController(FeedApi(say))..like('p1');
        async.elapse(_ms(10));
        feed.signOut();
        async.flushMicrotasks();
        feed.close().then((_) => say('closed'));
      });
      expect(trace, [
        '0 ms: like p1 sent',
        '50 ms: like p1 confirmed',
        '50 ms: closed',
      ]);
    });

    test('abandonable lets the job go, and the request runs on', () {
      _says(
        'with `ctx.abandonable` instead of `ctx.join` the job lets go at '
        'once, while the request runs on at the server',
      );
      final trace = _trace((async, say) {
        final feed = _AbandoningEpochs(FeedApi(say));
        feed.like('p1').whenFinished((outcome) => say('like p1: $outcome'));
        async.elapse(_ms(10));
        feed.signOut();
        async.flushMicrotasks();
        feed.close().then((_) => say('closed'));
      });
      expect(trace, [
        '0 ms: like p1 sent',
        '10 ms: like p1: Cancelled(rules: keepWhile)',
        '10 ms: closed',
        '50 ms: like p1 confirmed',
      ]);
    });
  });

  group('Rules by type on a record state', () {
    void offDuringFocus(
      FakeAsync async,
      void Function(String line) say,
      Job<void> Function() shoot,
      void Function() off,
    ) {
      shoot().whenFinished((outcome) => say('shoot: $outcome'));
      async.elapse(_ms(30));
      say('camera off');
      off();
    }

    test('on a class, the cast throws after the focus', () {
      _says('The device reports `Off` at 30 ms, during the focus');
      _says(
        'The shot ends `Failed` with a `TypeError` that nobody answers for.',
      );
      final errors = <Object>[];
      final trace = _trace((async, say) {
        final studio = first.ClassStudioController(Device(say));
        offDuringFocus(
          async,
          say,
          studio.shoot,
          () => studio.reflect(const Off()),
        );
      }, errors: errors);

      expect(trace, _quotes()[7]);
      expect(errors, [isA<TypeError>()]);
    });

    test('on a class, a keepWhile cancels the shot, and the cast stays', () {
      _says(
        'A `keepWhile` with the same test cancels the shot, and the cast '
        'stays.',
      );
      final errors = <Object>[];
      final trace = _trace((async, say) {
        final studio = _KeepingClassStudio(Device(say));
        offDuringFocus(
          async,
          say,
          studio.shoot,
          () => studio.reflect(const Off()),
        );
      }, errors: errors);

      expect(trace.last, '50 ms: shoot: Cancelled(rules: keepWhile)');
      expect(errors, isEmpty);
    });

    test('on a record, W cancels the shot', () {
      final errors = <Object>[];
      final trace = _trace((async, say) {
        final studio = page.StudioController(Device(say));
        offDuringFocus(
          async,
          say,
          studio.shoot,
          () => studio.reflect(const Off()),
        );
      }, errors: errors);

      expect(trace, _quotes()[8]);
      expect(errors, isEmpty);
    });

    test('the acceptance does not wait for a shot', () {
      _says('so the acceptance does not wait for a shot');
      fakeAsync((async) {
        final studio = page.StudioController(Device((_) {}))..shoot();
        async.elapse(_ms(160));
        final notice = studio.currentState.notice!;
        studio.shoot();
        async.elapse(_ms(10));
        studio.accept(notice);
        async.flushMicrotasks();

        expect(studio.currentState.notice, isNull);
        expect(studio.currentState.camera, isA<Ready>());
        async.flushTimers();
        expect(studio.currentState.notice, isNotNull);
      });
    });
  });

  group('A pool of places', () {
    test('the worker falls on an upload cancelled before it comes to it', () {
      _says(
        'Four photos are picked at 0 ms, the user cancels the third at once, '
        'and a drain is asked for at 20 ms',
      );
      _says(
        'The body of the worker fails, and the error goes to the zone. The '
        'worker ends at 100 ms, once its children `a.jpg` and `b.jpg` have, '
        'and the drain closes the controller.',
      );
      final errors = <Object>[];
      final trace = _uploadsTrace(_worker, cancelThird: true, errors: errors);

      expect(trace, _quotes()[9]);
      expect(errors, [isA<StateError>()]);
    });

    test('the worker sends every upload at once and holds a drain', () {
      _says('Without the cancellation, the same four photos');
      _says(
        'All four go to the server at once: nothing holds the uploads to two. '
        'And the drain never ends',
      );
      final trace = _uploadsTrace(_worker, cancelThird: false);

      expect(trace, _quotes()[10]);
    });

    test('a pool sends two at a time, and its drain ends', () {
      _says('The same four photos, the third cancelled at once');
      _says(
        'The drain runs the queue out and completes once no job of the pool '
        'runs.',
      );
      expect(_uploadsTrace(_pooled, cancelThird: true), _quotes()[11]);
      final whole = _uploadsTrace(_pooled, cancelThird: false);
      expect(whole, containsAllInOrder(['200 ms: closed']));
      expect(whole.where((line) => line.contains('sent')), [
        '0 ms: upload a.jpg sent',
        '0 ms: upload b.jpg sent',
        '100 ms: upload c.jpg sent',
        '100 ms: upload d.jpg sent',
      ]);
    });

    test('a child takes no place', () {
      _says(
        'A child of a job of the pool takes no place: `concurrency` counts the '
        'root jobs.',
      );
      fakeAsync((async) {
        final places = _Places(concurrency: 1);
        final gate = Completer<void>();
        var children = 0;
        final root = places.places.enqueue<int, void>(key: 'root', (ctx) async {
          await [
            for (var i = 0; i < 3; i++)
              ctx.run(
                ctx.child<void>((child) async {
                  children++;
                  await gate.future;
                }),
              ),
          ].wait;
        });
        async.flushMicrotasks();

        expect(children, 3);
        expect(places.places.running, [same(root)]);
        gate.complete();
        async.flushMicrotasks();
        expect(root.outcome, isA<Done<void>>());
      });
    });

    test('running lists the jobs in the order they started', () {
      _says(
        'It has `running`, the jobs that run now in the order they started, '
        'so `uploading` reads `running.length`.',
      );
      _says(
        'Code that reads neither member takes a `SoloQueueOwner`, which a lane '
        'and a pool both are.',
      );
      fakeAsync((async) {
        final places = _Places();
        final gate = Completer<void>();
        final first = places.places.enqueue<int, void>(
          key: 'first',
          (ctx) => gate.future,
        );
        final second = places.places.enqueue<int, void>(
          key: 'second',
          (ctx) => gate.future,
        );
        async.flushMicrotasks();

        expect(places.places.running, [same(first), same(second)]);
        expect(places.places, isNot(isA<SoloLane<int>>()));
        expect(places.places, isA<SoloQueueOwner<int>>());
        expect(places.before, isA<SoloQueueOwner<int>>());
        gate.complete();
        async.flushMicrotasks();
      });
    });

    test('a held key waits, and the likes of other keys go past it', () {
      _says(
        'The like of `p1` is tapped at 10 ms and takes the server two '
        'seconds, the unlike of `p1` is tapped at 20 ms, and the like of `p2` '
        'at 150 ms',
      );
      _says(
        'The like of `p2` takes a free place at 150 ms and goes past the '
        'unlike of `p1`: in one likes lane it would be sent at 2060 ms, after '
        'both.',
      );
      _says(
        'the body writes the mark, and the body starts at 2010 ms, so the '
        'heart stays lit for two seconds after the tap',
      );
      _says(
        'It waits until that job ends, and the jobs behind it with other keys '
        'go past it while a place is free.',
      );
      final trace = _likesTrace(
        pooled.FeedController.new,
        (feed, postId, {required liked}) => feed.setLiked(postId, liked: liked),
      );
      expect(trace, _quotes()[12]);

      final inOneLane = _likesTrace(
        _LaneLikes.new,
        (feed, postId, {required liked}) => feed.setLiked(postId, liked: liked),
      );
      expect(inOneLane.where((line) => line.contains('sent')), [
        '10 ms: like p1 sent',
        '2010 ms: unlike p1 sent',
        '2060 ms: like p2 sent',
      ]);
    });

    test('one key for every job runs them one at a time, in order', () {
      _says(
        'The key keeps the order under `Policy.sequential` too, the policy a '
        'call takes by default, though in a `Solo` and in a lane that policy '
        'ignores keys. So one key given to every job of a pool runs them one '
        'at a time, in the order of the queue.',
      );
      fakeAsync((async) {
        final places = _Places(concurrency: 3);
        final gates = [for (var i = 0; i < 3; i++) Completer<void>()];
        final jobs = [
          for (final (index, gate) in gates.indexed)
            places.places.enqueue<int, void>(
              key: 'one',
              describe: () => '$index',
              (ctx) => gate.future,
            ),
        ];
        for (final (index, gate) in gates.indexed) {
          async.flushMicrotasks();
          expect(places.places.running, [same(jobs[index])]);
          gate.complete();
        }
        async.flushMicrotasks();
        expect(places.places.running, isEmpty);
      });
    });

    test('droppable and restart look into the pool as into a lane', () {
      _says(
        'The other policies look into the pool as into a lane: `droppable` '
        'hands out the job of the key that waits or runs, and `restart` '
        'cancels the running job of the key, and the new job starts once that '
        'one ends.',
      );
      fakeAsync((async) {
        // Three places: the job of another key takes the second, and the
        // third stays free, so a job that waits waits for its key.
        final places = _Places(concurrency: 3);
        final gate = Completer<void>();
        final unwound = Completer<void>();
        final running = places.places.enqueue<int, void>(key: 'k', (ctx) async {
          try {
            await ctx.abandonable(() => gate.future);
          } finally {
            await unwound.future;
          }
        });
        async.flushMicrotasks();
        expect(
          places.places.enqueue<int, void>(
            key: 'k',
            policy: Policy.droppable,
            (ctx) async {},
          ),
          same(running),
          reason: 'with nothing queued, the running job of the key',
        );
        final waiting = places.places.enqueue<int, void>(
          key: 'k',
          (ctx) async {},
        );
        expect(
          places.places.enqueue<int, void>(
            key: 'k',
            policy: Policy.droppable,
            (ctx) async {},
          ),
          same(waiting),
          reason: 'the queue is asked from its tail first',
        );
        final other = places.places.enqueue<int, void>(
          key: 'other',
          policy: Policy.droppable,
          (ctx) => ctx.abandonable(() => gate.future),
        );
        expect(other, isNot(anyOf(same(running), same(waiting))));
        async.flushMicrotasks();
        expect(places.places.running, [same(running), same(other)]);

        var started = false;
        final restarted = places.places.enqueue<int, void>(
          key: 'k',
          policy: Policy.restart,
          (ctx) async => started = true,
        );
        async.flushMicrotasks();
        expect(running.isCancelled, isTrue);
        expect(running.outcome, isNull, reason: 'it is still unwinding');
        expect(waiting.outcome, isA<Cancelled>());
        expect(started, isFalse, reason: 'a place is free, the key is not');
        unwound.complete();
        async.flushMicrotasks();
        expect(running.outcome, isA<Cancelled>());
        expect(started, isTrue);
        expect(restarted.outcome, isA<Done<void>>());
        places.close().ignore();
        gate.complete();
        async.flushMicrotasks();
      });
    });

    test('a job awaiting its own pool waits for good, or for a place', () {
      _says(
        'A job that awaits a job it queued under its own key in its own pool '
        'waits for good at once: it holds the key itself. Under another key, '
        'or with none, it gets the job while a place is free, and once every '
        'place is taken by jobs that wait so, none of them moves.',
      );
      _says('It waits for good: it holds the key itself.');
      _says(
        'It gets the job while a place is free; once every place is taken by '
        'jobs that wait so, they wait for good.',
      );
      _says(
        'the `await_own_queue` lint of '
        '[solo_lints](https://pub.dev/packages/solo_lints) reports a wait for '
        'a job of the own pool whatever the key',
      );
      fakeAsync((async) {
        final places = _Places(concurrency: 3);
        final own = places.places.enqueue<int, void>(key: 'a', (ctx) async {
          await places.places.enqueue<int, void>(key: 'a', (ctx) async {}).done;
        });
        final other = places.places.enqueue<int, void>(key: 'b', (ctx) async {
          await places.places.enqueue<int, void>((ctx) async {}).done;
        });
        async.elapse(const Duration(seconds: 100));

        expect(own.outcome, isNull);
        expect(other.outcome, isA<Done<void>>());
        places.close().ignore();
        async.flushMicrotasks();
      });
      fakeAsync((async) {
        final places = _Places();
        final waiting = [
          for (final (key, inner) in [('a', 'c'), ('b', 'd')])
            places.places.enqueue<int, void>(key: key, (ctx) async {
              await places.places
                  .enqueue<int, void>(key: inner, (ctx) async {})
                  .done;
            }),
        ];
        async.elapse(const Duration(seconds: 100));

        expect([for (final job in waiting) job.outcome], [null, null]);
        expect(places.places.queue.length, 2);
        places.close().ignore();
        async.flushMicrotasks();
      });
    });

    test('a write of one job of a pool asks the rules of the others', () {
      _says(
        'To a job of a pool, a write of another job of the same pool is what a '
        'write of another lane is',
      );
      fakeAsync((async) {
        final places = _Places();
        final gate = Completer<void>();
        final watching = places.places.enqueue<int, void>(
          key: 'watching',
          keepWhile: (state) => state == 0,
          (ctx) => ctx.abandonable(() => gate.future),
        );
        places.places.enqueue<int, void>(
          key: 'writing',
          (ctx) async => ctx.emit(1),
        );
        async.flushMicrotasks();

        expect(watching.outcome, isA<Cancelled>());
      });
    });

    test('close and a drain take a pool as one queue with several jobs', () {
      _says(
        '`close` clears the queue of a pool and asks every running job of it '
        'to cancel, and a drain of a pool ends once its queue is empty and '
        'none of its jobs runs.',
      );
      fakeAsync((async) {
        final places = _Places();
        final running = [
          for (final key in ['a', 'b'])
            places.places.enqueue<int, void>(
              key: key,
              (ctx) => ctx.abandonable(() => Completer<void>().future),
            ),
        ];
        final queued = places.places.enqueue<int, void>((ctx) async {});
        async.flushMicrotasks();
        var closed = false;
        places.close().then((_) => closed = true);
        async.flushMicrotasks();

        expect([for (final job in running) job.isCancelled], [true, true]);
        expect(queued.outcome, isA<Cancelled>());
        expect(closed, isTrue);
      });
      fakeAsync((async) {
        final places = _Places();
        final jobs = [
          for (final ms in [10, 30, 15])
            places.places.enqueue<int, void>(
              (ctx) => Future<void>.delayed(_ms(ms)),
            ),
        ];
        async.flushMicrotasks();
        var closed = false;
        places.close(mode: SoloCloseMode.drain).then((_) => closed = true);
        async.elapse(_ms(29));
        expect(closed, isFalse);
        expect(jobs.last.outcome, isA<Done<void>>());
        async.elapse(_ms(1));
        expect(closed, isTrue);
      });
    });
  });

  group('Declaring lanes', () {
    test('a late final lane read after the constructor throws', () {
      _says('so the first `reload()` throws whenever it comes');
      fakeAsync((async) {
        final feed = first.FeedController(FeedApi((_) {}));
        async.flushMicrotasks();
        expect(
          feed.reload,
          throwsA(
            isA<StateError>().having((e) => '$e', 'text', _quotes()[13].single),
          ),
        );
      });
    });

    test('a read with the constructor gets through until the first job', () {
      _says(
        'a screen that writes `FeedController(api)..reload()` declares the '
        'reload lane and queues its job, and the first `setLiked` throws all '
        'the same',
      );
      fakeAsync((async) {
        final feed = first.FeedController(FeedApi((_) {}))..reload();
        expect(
          () => feed.setLiked('p1', liked: true),
          throwsA(
            isA<StateError>().having((e) => '$e', 'text', _quotes()[14].single),
          ),
        );
        feed.close().ignore();
        async.flushTimers();
      });
    });

    test('lanes are declared in order, and a name of a lane throws', () {
      _says(
        '`lane` throws a `StateError` for a name the controller has a lane of '
        'already',
      );
      _says('the order of these lines: the order `lanes` gives them in.');
      final two = _Two();
      expect([for (final lane in two.declared) lane.name], ['a', 'b']);
      expect(() => two.declare('a'), throwsStateError);
    });

    test('a job tells its lane, and a job of a Solo has none', () {
      _says(
        'A job tells the lane it runs in with `job.lane`, a `SoloLaneId` with '
        'that name, and a job of a `Solo` has none.',
      );
      fakeAsync((async) {
        final two = _Two();
        final job = two.b.enqueue<int, void>((ctx) async {});
        final solo = _Plain();
        final plain = solo.run();
        async.flushMicrotasks();

        expect(job.lane, same(two.b.id));
        expect(job.lane!.name, 'b');
        expect(plain.lane, isNull);
      });
    });

    test('a pool is declared as a lane, and the pump walks both in order', () {
      _says(
        'A pool is declared the same way, by `pool` in the constructor body, '
        'and `pools` gives the pools in the order of their lines.',
      );
      _says(
        'The pump walks the lanes and the pools together, in the order they '
        'were declared.',
      );
      _says(
        '`pool` throws as `lane` does, for a name of a lane or a pool the '
        'controller has already and once the set is sealed, and it throws an '
        '`ArgumentError` for a `concurrency` below one.',
      );
      _says(
        'A job of a pool tells the pool with `job.lane`: the places have no id '
        'of their own.',
      );
      fakeAsync((async) {
        final places = _Places();
        expect(places.declared, [same(places.places)]);
        expect(() => places.declare('places'), throwsStateError);
        expect(() => places.declare('before'), throwsStateError);
        expect(() => places.declareLane('places'), throwsStateError);
        expect(
          () => places.declare('none', concurrency: 0),
          throwsArgumentError,
        );
        final jobs = [
          places.after.enqueue<int, void>(key: 'after', (ctx) async {}),
          places.places.enqueue<int, void>(key: 'places', (ctx) async {}),
          places.before.enqueue<int, void>(key: 'before', (ctx) async {}),
        ];
        async.flushMicrotasks();

        expect(places.log, ['start before', 'start places', 'start after']);
        expect(jobs[1].lane, same(places.places.id));
        expect(() => places.declare('late'), throwsStateError);
      });
    });
  });

  group('The table of cases', () {
    test('a job queued from the synchronous part of another lane starts '
        'before control goes back to the event loop', () {
      _says(
        'If the other lane is free, it starts the job before control goes '
        'back to the event loop; how that start falls among the microtasks '
        'of the same turn is not promised.',
      );
      // Both orders of declaration, and only the promise: the pass of the
      // pump the start falls in is left to the engine.
      for (final (from, into) in [('a', 'b'), ('b', 'a')]) {
        fakeAsync((async) {
          final two = _Two();
          SoloLane<int> named(String name) => name == 'a' ? two.a : two.b;
          final gate = Completer<void>();
          named(from).enqueue<int, void>(key: from, (ctx) {
            named(into).enqueue<int, void>(key: into, (ctx) => gate.future);
            return gate.future;
          });
          Timer.run(() => two.log.add('event loop'));
          async.elapse(Duration.zero);

          expect(two.log, ['start $from', 'start $into', 'event loop']);
          gate.complete();
          two.close().ignore();
          async.flushMicrotasks();
        });
      }
    });

    test('a write outside the W of a job of another lane cancels it, running '
        'or at its start', () {
      _says(
        'A reload lane that writes `Loading` cancels every like with '
        '`W = Loaded`: the like that runs is cancelled at the write, and a '
        'like that comes to its start while the state is `Loading` never runs '
        'its body.',
      );
      _says(
        'The like that runs is cancelled at the write, and a like that comes '
        'to its start while the state is `Loading` is cancelled before its '
        'body runs.',
      );
      fakeAsync((async) {
        final loads = _Loads();
        final server = Completer<void>();
        var bodies = 0;
        SoloJob<void> like() => loads.likes.enqueue<_Loaded, void>((ctx) {
          bodies++;
          return ctx.join(() => server.future);
        });
        final running = like();
        final next = like();
        async.flushMicrotasks();
        expect(bodies, 1);

        loads.reload.enqueue<_Load, void>(
          (ctx) async => ctx.emit(const _Loading()),
        );
        async.flushMicrotasks();
        expect(running.isCancelled, isTrue);
        server.complete();
        async.flushMicrotasks();

        Matcher cancelled({required bool started}) => isA<Cancelled>()
            .having((c) => c.started, 'started', started)
            .having((c) => c.reason, 'reason', isA<RulesCancelReason>());
        expect(running.outcome, cancelled(started: true));
        expect(next.outcome, cancelled(started: false));
        expect(bodies, 1);
      });
    });

    test('a write of one lane cancels a cancellable: false job of another', () {
      _says(
        'And the rules go past `cancellable: false`, so a write of one lane '
        'cancels a command to a device that runs in another.',
      );
      _says(
        'The job is cancelled all the same: the rules go past '
        '`cancellable: false`, as `externalSetState` does in a `Solo`.',
      );
      fakeAsync((async) {
        final two = _Two();
        final gate = Completer<void>();
        final command = two.b.enqueue<int, void>(
          cancellable: false,
          keepWhile: (state) => state == 0,
          (ctx) => ctx.join(() => gate.future),
        );
        async.flushMicrotasks();
        two.a.enqueue<int, void>((ctx) async => ctx.emit(1));
        async.flushMicrotasks();
        // At the write itself: the command still waits on its join, and no
        // check of its own has come yet.
        expect(command.isCancelled, isTrue);
        expect(gate.isCompleted, isFalse);
        gate.complete();
        async.flushMicrotasks();

        expect(
          command.outcome,
          isA<Cancelled>().having(
            (c) => c.reason,
            'reason',
            isA<RulesCancelReason>(),
          ),
        );
      });
    });

    test('a job waits for a job of another lane, and for good for its own', () {
      _says('It waits while the other lane runs that job.');
      _says('It waits for good: a lane runs one job at a time.');
      fakeAsync((async) {
        final two = _Two();
        final across = two.a.enqueue<int, void>(key: 'across', (ctx) async {
          await two.b.enqueue<int, void>((ctx) async {}).done;
        });
        async.flushMicrotasks();
        expect(across.outcome, isA<Done<void>>());

        final own = two.a.enqueue<int, void>(key: 'own', (ctx) async {
          await two.a.enqueue<int, void>((ctx) async {}).done;
        });
        async.elapse(const Duration(seconds: 100));
        expect(own.outcome, isNull);
        two.close().ignore();
        async.flushTimers();
      });
    });

    test('a circle of waits across lanes hangs both', () {
      _says(
        'A job of lane A awaits a job it queued in lane B, which awaits a job '
        'it queued in lane A',
      );
      _says(
        'Both wait for good: the job in B waits for one queued in A behind the '
        'job that waits for it.',
      );
      fakeAsync((async) {
        final two = _Two();
        SoloJob<void>? inB;
        SoloJob<void>? backInA;
        final inA = two.a.enqueue<int, void>((ctx) async {
          inB = two.b.enqueue<int, void>((ctx) async {
            backInA = two.a.enqueue<int, void>((ctx) async {});
            await backInA!.done;
          });
          await inB!.done;
        });
        async.elapse(const Duration(seconds: 100));

        expect(inB, isNotNull);
        expect(backInA, isNotNull);
        expect(
          [inA.outcome, inB!.outcome, backInA!.outcome],
          [null, null, null],
        );
        two.close().ignore();
        async.flushTimers();
      });
    });

    test('a job that awaits close or cancelAll waits for itself', () {
      _says('It waits for itself: both wait for the jobs of every lane.');
      for (final stop in <Future<void> Function(_Two two)>[
        (two) => two.close(),
        (two) => two.cancelAll(),
      ]) {
        fakeAsync((async) {
          final two = _Two();
          final waiting = two.a.enqueue<int, void>((ctx) async => stop(two));
          async.elapse(const Duration(seconds: 100));
          expect(waiting.outcome, isNull);
          expect(two.isFinished, isFalse);
        });
      }
    });

    test('close clears every lane, asks the running jobs to cancel and ends '
        'with the last', () {
      _says(
        'The queues of every lane are cleared, and the running job of every '
        'lane is asked to cancel; a `cancellable: false` job turns that down '
        'and runs on. `close` completes when the last of them ends',
      );
      fakeAsync((async) {
        final two = _Two();
        final aGate = Completer<void>();
        final bGate = Completer<void>();
        final a = two.a.enqueue<int, void>(
          (ctx) => ctx.join(() => aGate.future),
        );
        final b = two.b.enqueue<int, void>(
          cancellable: false,
          (ctx) => ctx.join(() => bGate.future),
        );
        final queued = two.b.enqueue<int, void>((ctx) async {});
        async.flushMicrotasks();
        var closed = false;
        two.close().then((_) => closed = true);
        async.flushMicrotasks();

        expect(a.isCancelled, isTrue);
        expect(b.isCancelled, isFalse, reason: 'it turned the close down');
        expect(queued.outcome, isA<Cancelled>());
        aGate.complete();
        async.flushMicrotasks();
        expect(closed, isFalse);
        bGate.complete();
        async.flushMicrotasks();
        expect(b.outcome, isA<Done<void>>());
        expect(closed, isTrue);
      });
    });

    test('a drain runs every lane out', () {
      _says(
        'Every lane runs its queue out, and `close` completes when all of '
        'them are empty.',
      );
      fakeAsync((async) {
        final two = _Two();
        final aGate = Completer<void>();
        final a = two.a.enqueue<int, void>((ctx) => aGate.future);
        final b = two.b.enqueue<int, void>(
          (ctx) => Future<void>.delayed(_ms(10)),
        );
        final queued = two.b.enqueue<int, void>((ctx) async {});
        async.flushMicrotasks();
        var closed = false;
        two.close(mode: SoloCloseMode.drain).then((_) => closed = true);
        async.elapse(_ms(20));

        expect(b.outcome, isA<Done<void>>());
        expect(queued.outcome, isA<Done<void>>());
        expect(closed, isFalse);
        aGate.complete();
        async.flushMicrotasks();
        expect(a.outcome, isA<Done<void>>());
        expect(closed, isTrue);
      });
    });

    test('a continuation into another lane during a drain is cancelled', () {
      _says(
        'The continuation ends `Cancelled(closed)`: a closed controller takes '
        'no new root job, whichever lane asks.',
      );
      fakeAsync((async) {
        final two = _Two();
        final gate = Completer<void>();
        SoloJob<void>? continuation;
        two.a.enqueue<int, void>((ctx) async {
          await ctx.join(() => gate.future);
          continuation = two.b.enqueue<int, void>((ctx) async {});
        });
        async.flushMicrotasks();
        two.close(mode: SoloCloseMode.drain).ignore();
        gate.complete();
        async.flushMicrotasks();

        expect(
          continuation?.outcome,
          isA<Cancelled>().having(
            (c) => c.reason,
            'reason',
            isA<ClosedCancelReason>(),
          ),
        );
      });
    });

    test('a droppable continuation during a drain gets the accepted job', () {
      _says(
        'A `droppable` continuation whose key the other lane has accepted gets '
        'that job, as it would before the close.',
      );
      fakeAsync((async) {
        final two = _Two();
        final aGate = Completer<void>();
        final bGate = Completer<void>();
        final accepted = two.b.enqueue<int, void>(
          key: 'sync',
          policy: Policy.droppable,
          (ctx) => ctx.join(() => bGate.future),
        );
        SoloJob<void>? continuation;
        two.a.enqueue<int, void>((ctx) async {
          await ctx.join(() => aGate.future);
          continuation = two.b.enqueue<int, void>(
            key: 'sync',
            policy: Policy.droppable,
            (ctx) async {},
          );
        });
        async.flushMicrotasks();
        two.close(mode: SoloCloseMode.drain).ignore();
        aGate.complete();
        async.flushMicrotasks();

        expect(continuation, same(accepted));
        bGate.complete();
        async.flushMicrotasks();
        expect(continuation?.outcome, isA<Done<void>>());
      });
    });

    test('an unlike failed after a reload puts back no mark', () {
      _says(
        'The correction puts back no mark: the posts say what the server held '
        'when the reload was sent, an unlike from another device included.',
      );
      // The like is confirmed before the reload is sent, and the unlike
      // fails after the reload answered. [elsewhere] unlikes on the server
      // from another device right after the like.
      List<String> unlikeFailing({required bool elsewhere}) {
        final shown = <String>[];
        _trace((async, say) {
          final api = FeedApi((_) {});
          final feed = page.FeedController(api);
          void show() => shown.add(_feed(feed.currentState));
          feed.setLiked('p1', liked: true);
          async.elapse(_ms(100));
          if (elsewhere) api.liked.remove('p1');
          feed.reload();
          async.elapse(_ms(1980));
          api.failNext = true;
          feed.setLiked('p1', liked: false);
          async.elapse(_ms(20));
          show();
          async.elapse(_ms(30));
          show();
        });
        return shown;
      }

      expect(unlikeFailing(elsewhere: false), [
        'posts p1 liked, p2; marks p1 unliked',
        'posts p1 liked, p2; marks none',
      ]);
      expect(unlikeFailing(elsewhere: true), [
        'posts p1, p2; marks p1 unliked',
        'posts p1, p2; marks none',
      ]);
    });
  });

  group('The page', () {
    test('six sections open with a first attempt', () {
      expect(
        RegExp(r'^### The first attempt$', multiLine: true).allMatches(_page()),
        hasLength(6),
      );
    });

    test('quotes fifteen traces', () {
      expect(_quotes(), hasLength(15));
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/lanes.md'), isEmpty);
    });

    // Each version under its own file: a line of an answer turned into the
    // line of a first attempt would still be found among all of them.
    const answers = 'test/support/lanes_page.dart';
    const attempts = 'test/support/lanes_first_attempts.dart';
    const epochFile = 'test/support/lanes_epoch.dart';
    const poolFile = 'test/support/lanes_pool.dart';
    const holders = {
      '### The first attempt': attempts,
      '### Two lanes': answers,
      '### A read at the write': answers,
      '### A merge': answers,
      '## Work that a new epoch makes stale': epochFile,
      '### W on a record': answers,
      '### A pool': poolFile,
      '### In the constructor body': answers,
    };
    for (final MapEntry(key: heading, value: holder) in holders.entries) {
      test('the code under "$heading" is a run of lines of $holder', () {
        expect(
          codeMissingFrom('doc/lanes.md', holder, under: heading),
          isEmpty,
        );
      });
    }

    test(
      'every piece of code on the page is a run of lines of these files',
      () {
        expect(
          codeMissingFrom(
            'doc/lanes.md',
            answers,
            alsoIn: [attempts, epochFile, poolFile],
          ),
          isEmpty,
        );
      },
    );

    test('every heading with code under it is held to a file', () {
      final withCode = [
        for (final part in _page().split(RegExp('^(?=#)', multiLine: true)))
          if (part.contains('```dart')) part.split('\n').first,
      ];
      expect(withCode.toSet(), holders.keys.toSet());
    });
  });
}

/// A controller with one queue, for the lane of a job of a `Solo`.
final class _Plain extends Solo<int> {
  _Plain() : super(0);

  SoloJob<void> run() => enqueue<int, void>((ctx) async {});
}
