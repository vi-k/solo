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
      expect(trace, _quotes()[3]);
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
      expect(trace, _quotes()[4]);
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

      expect(trace, _quotes()[5]);
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

      expect(trace, _quotes()[6]);
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

      expect(trace, _quotes()[7]);
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

  group('Declaring lanes', () {
    test('a late final lane read after the constructor throws', () {
      _says('so the first `reload()` throws whenever it comes');
      fakeAsync((async) {
        final feed = first.FeedController(FeedApi((_) {}));
        async.flushMicrotasks();
        expect(
          feed.reload,
          throwsA(
            isA<StateError>().having((e) => '$e', 'text', _quotes()[8].single),
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
            isA<StateError>().having((e) => '$e', 'text', _quotes()[9].single),
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
      _says(
        'the order `lanes` gives them in and a pass of the pump walks them in',
      );
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
  });

  group('The table of cases', () {
    test('a job queued from the synchronous part of another lane starts in '
        'this pass if its lane comes later, in the next if earlier', () {
      _says(
        'The other lane starts it in the same pass of the pump if it was '
        'declared later, and in the next pass if it was declared earlier.',
      );
      for (final (from, into, expected) in [
        ('a', 'b', ['start a', 'start b', 'tick']),
        ('b', 'a', ['start b', 'tick', 'start a']),
      ]) {
        fakeAsync((async) {
          final two = _Two();
          SoloLane<int> named(String name) => name == 'a' ? two.a : two.b;
          final gate = Completer<void>();
          named(from).enqueue<int, void>(key: from, (ctx) {
            named(into).enqueue<int, void>(key: into, (ctx) => gate.future);
            return gate.future;
          });
          scheduleMicrotask(() => two.log.add('tick'));
          async.flushMicrotasks();

          expect(two.log, expected);
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

    test('close clears and cancels every lane and ends with the last', () {
      _says(
        'The queues of every lane are cleared, the running job of every lane '
        'is cancelled, and `close` completes when the last of them ends.',
      );
      fakeAsync((async) {
        final two = _Two();
        final aGate = Completer<void>();
        final bGate = Completer<void>();
        final a = two.a.enqueue<int, void>(
          (ctx) => ctx.join(() => aGate.future),
        );
        final b = two.b.enqueue<int, void>(
          (ctx) => ctx.join(() => bGate.future),
        );
        final queued = two.b.enqueue<int, void>((ctx) async {});
        async.flushMicrotasks();
        var closed = false;
        two.close().then((_) => closed = true);
        async.flushMicrotasks();

        expect(a.isCancelled && b.isCancelled, isTrue);
        expect(queued.outcome, isA<Cancelled>());
        aGate.complete();
        async.flushMicrotasks();
        expect(closed, isFalse);
        bGate.complete();
        async.flushMicrotasks();
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

    test('an unlike failed after a reload puts back the confirmed mark', () {
      _says(
        'The correction puts back the confirmed mark the unlike found. It '
        'says what the server says, and the next reload takes it away.',
      );
      final shown = <String>[];
      _trace((async, say) {
        final api = FeedApi((_) {});
        final feed = page.FeedController(api);
        void show() => shown.add(_feed(feed.currentState));
        feed.setLiked('p1', liked: true);
        async.elapse(_ms(100));
        feed.reload();
        async.elapse(_ms(1980));
        api.failNext = true;
        feed.setLiked('p1', liked: false);
        async.elapse(_ms(20));
        show();
        async.elapse(_ms(30));
        show();
        feed.reload();
        async.elapse(_ms(2000));
        show();
      });
      expect(shown, [
        'posts p1 liked, p2; marks p1 unliked',
        'posts p1 liked, p2; marks p1 liked #1',
        'posts p1 liked, p2; marks none',
      ]);
    });
  });

  group('The page', () {
    test('five sections open with a first attempt', () {
      expect(
        RegExp(r'^### The first attempt$', multiLine: true).allMatches(_page()),
        hasLength(5),
      );
    });

    test('quotes ten traces', () {
      expect(_quotes(), hasLength(10));
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/lanes.md'), isEmpty);
    });

    // Each version under its own file: a line of an answer turned into the
    // line of a first attempt would still be found among all of them.
    const answers = 'test/support/lanes_page.dart';
    const attempts = 'test/support/lanes_first_attempts.dart';
    const epochFile = 'test/support/lanes_epoch.dart';
    const holders = {
      '### The first attempt': attempts,
      '### Two lanes': answers,
      '### A read at the write': answers,
      '### A merge': answers,
      '## Work that a new epoch makes stale': epochFile,
      '### W on a record': answers,
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
            alsoIn: [attempts, epochFile],
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
