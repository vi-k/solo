@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/page_code.dart';
import 'support/readme_player.dart' as tour;
import 'support/readme_quick_start.dart' as quick;
import 'support/readme_reload.dart' as reload;
import 'support/readme_stream.dart' as streamed;
import 'support/readme_stubs.dart' as stubs;

/// The sentinel of `README.md`.
///
/// The code of the page stands verbatim in `test/support/readme_*.dart`,
/// and the tests below run it: the quick start, the reload of the section on
/// `currentState`, the player of "The dozen calls" and its call site. What
/// the prose and the comments of the page say about that code is pinned
/// here, next to the code it is said of. The bench `tool/flutter_snippets.py`
/// builds the two blocks of declarations of the quick start as well; it
/// checks less, and it needs Flutter.

/// A state of the quick start, the way a journal would write it.
String _profile(quick.ProfileState state) => switch (state) {
      quick.Initial() => 'Initial',
      quick.Loading() => 'Loading',
      quick.Loaded(:final name) => 'Loaded($name)',
      quick.Failure(:final error) => 'Failure($error)',
    };

/// The API of the quick start, saying when its request begins and ends.
class _TracingApi extends quick.ProfileApi {
  final trace = <String>[];

  @override
  Future<String> fetchName() async {
    trace.add('fetch begins');
    final name = await super.fetchName();
    trace.add('fetch ends');
    return name;
  }
}

/// The API of the quick start, offline.
class _FailingApi extends quick.ProfileApi {
  final error = StateError('offline');

  @override
  Future<String> fetchName() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    throw error;
  }
}

/// A controller whose first job fails with a child still running and a
/// cleanup registered, and whose second job is queued behind it.
final class _Ordered extends Solo<int> {
  final trace = <String>[];

  _Ordered() : super(0);

  Job<void> first() => run<int, void>(
        ifFailed: (state, error, stackTrace) {
          trace.add('state handler');
          return state;
        },
        (ctx) async {
          ctx
            ..each(
              Stream<int>.fromFuture(
                Future<int>.delayed(const Duration(milliseconds: 10), () => 1),
              ),
              (child, event) => trace.add('child'),
            )
            ..onDispose(() => trace.add('cleanup'));
          trace.add('body');
          throw StateError('boom');
        },
      );

  Job<void> second() => run<int, void>((ctx) async => trace.add('next job'));
}

/// Two jobs with the rule of `play`: in one the body publishes the state the
/// rule turns down, in the other a child of the body does.
final class _OwnRule extends Solo<stubs.PlayerState> {
  _OwnRule() : super(const stubs.Idle());

  Job<String> body() => run<stubs.PlayerState, String>(
        keepWhile: (state) => state is! stubs.Disconnected,
        (ctx) async {
          ctx.emit(const stubs.Disconnected());
          return 'went on';
        },
      );

  Job<String> child() => run<stubs.PlayerState, String>(
        keepWhile: (state) => state is! stubs.Disconnected,
        (ctx) async {
          await ctx.each(Stream.value(1), (childCtx, _) {
            childCtx.emit(const stubs.Disconnected());
          }).value;
          return 'went on';
        },
      );
}

/// A controller of numbers that sets them from outside.
final class _Numbers extends Solo<int> {
  _Numbers() : super(0);

  void set(int value) => externalSetState(value);
}

/// What [body] printed, run to its end under fake time.
List<String> _printed(Future<void> Function() body) {
  final lines = <String>[];
  var over = false;
  runZoned(
    () => fakeAsync((async) {
      body().then((_) => over = true);
      async.flushTimers();
    }),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  expect(over, isTrue, reason: 'the program runs to its end');
  return lines;
}

String _page() => File('README.md').readAsStringSync();

void main() {
  setUp(() => stubs.stage = stubs.Stage());

  group('Quick start', () {
    test('the first block declares four immutable states', () {
      final block = RegExp(r'```dart\n(.*?)\n```', dotAll: true)
          .firstMatch(_page())!
          .group(1)!;
      final states = RegExp(
        r'^final class (\w+) extends ProfileState \{$',
        multiLine: true,
      ).allMatches(block).map((match) => match.group(1)).toList();
      expect(states, hasLength(4));
      expect(
        _page(),
        contains('reports progress through four immutable states'),
      );
      for (final state in states) {
        expect(block, contains('  const $state('), reason: '$state is const');
      }
      expect(
        RegExp(r'^  (?!final |const )\w', multiLine: true).hasMatch(block),
        isFalse,
        reason: 'every field is final',
      );
    });

    test('main prints what the listener hears, then the name twice', () {
      expect(_printed(quick.main), [
        "Instance of 'Loading'",
        "Instance of 'Loaded'",
        'Ada Lovelace',
        'Ada Lovelace',
      ]);
    });

    test('the listener runs inside the change, before the next line', () {
      fakeAsync((async) {
        final api = _TracingApi();
        final profile = quick.ProfileController(api);
        profile
          ..addListener(
            () => api.trace.add('heard ${_profile(profile.currentState)}'),
          )
          ..load();
        async.flushTimers();
        expect(api.trace, [
          'heard Loading',
          'fetch begins',
          'fetch ends',
          'heard Loaded(Ada Lovelace)',
        ]);
        profile.close().ignore();
        async.flushTimers();
      });
    });

    test('a second call returns the queued job, then the running one', () {
      fakeAsync((async) {
        final profile = quick.ProfileController(quick.ProfileApi());
        final job = profile.load();
        expect(identical(profile.load(), job), isTrue, reason: 'queued');
        async.elapse(const Duration(milliseconds: 10));
        expect(profile.currentState, isA<quick.Loading>());
        expect(identical(profile.load(), job), isTrue, reason: 'running');
        async.flushTimers();
        expect(job.outcome, isA<Done<String>>());

        final next = profile.load();
        expect(identical(next, job), isFalse, reason: 'the load finished');
        async.flushTimers();
        expect(next.outcome, isA<Done<String>>());
        profile.close().ignore();
        async.flushTimers();
      });
    });

    test('an error publishes Failure, and the outcome stays Failed', () {
      fakeAsync((async) {
        final api = _FailingApi();
        final profile = quick.ProfileController(api);
        final job = profile.load();
        Object? thrown;
        job.value.then<void>(
          (_) {},
          onError: (Object error) {
            thrown = error;
          },
        );
        async.flushTimers();
        expect(_profile(profile.currentState), 'Failure(Bad state: offline)');
        expect(job.outcome, isA<Failed>());
        expect(thrown, same(api.error), reason: 'value throws the error');
        profile.close().ignore();
        async.flushTimers();
      });
    });

    test('a started load cancelled publishes Initial; cancel waits for it', () {
      fakeAsync((async) {
        final profile = quick.ProfileController(quick.ProfileApi());
        final job = profile.load();
        async.elapse(const Duration(milliseconds: 10));
        expect(profile.currentState, isA<quick.Loading>());
        Object? thrown;
        job.value.then<void>(
          (_) {},
          onError: (Object error) {
            thrown = error;
          },
        );
        String? stateWhenBack;
        job.cancel().then((_) {
          stateWhenBack = _profile(profile.currentState);
        });
        async.flushTimers();
        expect(stateWhenBack, 'Initial', reason: 'the handler ran first');
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(thrown, isA<Cancelled>(), reason: 'value throws Cancelled');
        profile.close().ignore();
        async.flushTimers();
      });
    });

    test('cancelLoading prints the outcome its comment quotes', () {
      final quote = RegExp(r'print\(job\.outcome\); // (.+)')
          .firstMatch(_page())!
          .group(1)!;
      expect(_printed(quick.cancelLoading), [quote]);
    });

    test('the job cancelled there is still queued, and ifCancelled never runs',
        () {
      fakeAsync((async) {
        final api = _TracingApi();
        final profile = quick.ProfileController(api);
        final heard = <String>[];
        profile.addListener(() => heard.add(_profile(profile.currentState)));
        final job = profile.load();
        expect((job as SoloJob<String>).isQueued, isTrue);
        job.cancel().ignore();
        async.flushTimers();
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(heard, isEmpty, reason: 'neither the body nor ifCancelled ran');
        expect(api.trace, isEmpty);
        profile.close().ignore();
        async.flushTimers();
      });
    });

    test('cancelling a job does not stop the request already sent', () {
      fakeAsync((async) {
        final api = _TracingApi();
        final profile = quick.ProfileController(api);
        final job = profile.load();
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
        async.flushMicrotasks();
        expect(job.outcome, isA<Cancelled>());
        expect(api.trace, ['fetch begins']);
        async.flushTimers();
        expect(api.trace, ['fetch begins', 'fetch ends']);
        profile.close().ignore();
        async.flushTimers();
      });
    });

    test('the next job starts after body, children, cleanup and handler', () {
      fakeAsync((async) {
        final ordered = _Ordered();
        ordered.first().ignoreFailure();
        ordered.second();
        async.flushTimers();
        expect(ordered.trace, [
          'body',
          'child',
          'cleanup',
          'state handler',
          'next job',
        ]);
        ordered.close().ignore();
        async.flushTimers();
      });
    });

    test('SoloStream adds a stream on the next microtask to the listener', () {
      fakeAsync((async) {
        final api = _TracingApi();
        final profile = streamed.ProfileController(api);
        final subscription = profile.stream.listen(
          (state) => api.trace.add('stream ${_profile(state)}'),
        );
        profile
          ..addListener(
            () => api.trace.add('listener ${_profile(profile.currentState)}'),
          )
          ..load();
        async.flushTimers();
        expect(api.trace, [
          'listener Loading',
          'fetch begins',
          'stream Loading',
          'fetch ends',
          'listener Loaded(Ada Lovelace)',
          'stream Loaded(Ada Lovelace)',
        ]);
        subscription.cancel().ignore();
        profile.close().ignore();
        async.flushTimers();
      });
    });
  });

  group('Why currentState and not state', () {
    late stubs.NameApi api;
    late reload.ProfileController profile;
    late List<String> heard;

    void open(quick.ProfileState state) {
      api = stubs.NameApi();
      profile = reload.ProfileController(
        api,
        stubs.Session(const stubs.SessionState('ada')),
        state,
      );
      heard = <String>[];
      profile.addListener(() => heard.add(_profile(profile.currentState)));
    }

    test('the name is fetched for the session user and published', () {
      fakeAsync((async) {
        open(const quick.Loaded('Ada Lovelace'));
        final job = profile.reload();
        async.flushTimers();
        expect(api.users, ['ada']);
        expect('${job.outcome}', 'Done(Ada King)');
        expect(heard, ['Loaded(Ada King)']);
      });
    });

    test('the same name is not published again', () {
      fakeAsync((async) {
        stubs.stage.name = 'Ada Lovelace';
        open(const quick.Loaded('Ada Lovelace'));
        final job = profile.reload();
        async.flushTimers();
        expect('${job.outcome}', 'Done(Ada Lovelace)');
        expect(heard, isEmpty);
      });
    });

    test('outside Loaded the job does not start', () {
      fakeAsync((async) {
        open(const quick.Initial());
        final job = profile.reload();
        async.flushTimers();
        expect('${job.outcome}', 'Cancelled(rules: is not Loaded)');
        expect(api.users, isEmpty);
      });
    });

    test('a state that leaves Loaded during the request cancels it there', () {
      fakeAsync((async) {
        open(const quick.Loaded('Ada Lovelace'));
        final job = profile.reload();
        async.elapse(const Duration(milliseconds: 5));
        profile.reflect(const quick.Initial());
        async.flushMicrotasks();
        expect('${job.outcome}', 'Cancelled(rules: is not Loaded)');
        async.flushTimers();
        expect(heard, ['Initial'], reason: 'nothing is published after it');
      });
    });

    test('a state that leaves Loaded after the answer is caught at the read',
        () {
      fakeAsync((async) {
        open(const quick.Loaded('Ada Lovelace'));
        api.afterAnswer = () => profile.reflect(const quick.Initial());
        final job = profile.reload();
        async.flushTimers();
        expect('${job.outcome}', 'Cancelled(rules: is not Loaded)');
        expect(heard, ['Initial'], reason: 'Ada King is never published');
      });
    });

    test('the controller has no member named state', () {
      open(const quick.Loaded('Ada Lovelace'));
      expect(() => (profile as dynamic).state, throwsNoSuchMethodError);
      expect(profile.currentState, isA<quick.Loaded>());
    });
  });

  group('The dozen calls', () {
    late stubs.Device device;
    late tour.Player player;
    late List<String> states;

    List<String> trace() => stubs.stage.trace;

    void open() {
      device = stubs.Device();
      player = tour.Player(stubs.Api(), device);
      states = <String>[];
      player.addListener(() => states.add('${player.currentState}'));
    }

    void close(FakeAsync async) {
      player.close().ignore();
      async.flushTimers();
    }

    test('play ends when the track starts, and the device plays on', () {
      fakeAsync((async) {
        open();
        final job = player.play('t-1');
        async.flushTimers();
        expect('${job.outcome}', 'Done(Track(t-1))');
        expect(states, [
          'Loading',
          'Buffering(Track(t-1), 50)',
          'Buffering(Track(t-1), 100)',
          'Playing(Track(t-1))',
        ]);
        expect(trace(), [
          'device stops',
          'fetch t-1 begins',
          'fetch t-1 ends',
          'download of Track(t-1) begins',
          'download of Track(t-1) opened',
          'device loads Track(t-1)',
          'device plays Track(t-1)',
          'download of Track(t-1) closed',
        ]);
        expect(device.playing?.id, 't-1');
        close(async);
      });
    });

    test('a volume change goes through while the track plays', () {
      fakeAsync((async) {
        open();
        player.play('t-1');
        async.flushTimers();
        final volume = player.setVolume(0.4);
        async.elapse(const Duration(milliseconds: 60));
        expect(volume.outcome, isA<Done<void>>());
        expect(device.volumes, [0.4]);
        expect(device.playing?.id, 't-1');
        close(async);
      });
    });

    test('root jobs run one at a time: a volume waits for the play', () {
      fakeAsync((async) {
        stubs.stage.downloadTake = 100;
        open();
        player
          ..play('t-1')
          ..setVolume(0.4);
        async.flushTimers();
        expect(
          trace().indexOf('volume 0.4'),
          greaterThan(trace().indexOf('download of Track(t-1) closed')),
        );
        close(async);
      });
    });

    test('a burst of volumes is one job, and only the last one is sent', () {
      fakeAsync((async) {
        open();
        final first = player.setVolume(0.2);
        async.elapse(const Duration(milliseconds: 10));
        final second = player.setVolume(0.3);
        async.elapse(const Duration(milliseconds: 10));
        final third = player.setVolume(0.4);
        expect(identical(first, second) && identical(second, third), isTrue);
        async.elapse(const Duration(milliseconds: 45));
        expect(device.volumes, isEmpty, reason: 'the window is still open');
        async.flushTimers();
        expect(device.volumes, [0.4]);
        close(async);
      });
    });

    test('a new play cancels the one running, whatever its track', () {
      fakeAsync((async) {
        open();
        final first = player.play('t-1');
        async.elapse(const Duration(milliseconds: 20));
        final second = player.play('t-2');
        async.flushTimers();
        expect('${first.outcome}', 'Cancelled(replaced)');
        expect('${second.outcome}', 'Done(Track(t-2))');
        expect(trace(), contains('download of Track(t-1) closed'));
        expect(trace(), isNot(contains('device loads Track(t-1)')));
        expect(states.last, 'Playing(Track(t-2))');
        close(async);
      });
    });

    test('the track playing now stops before another one loads', () {
      fakeAsync((async) {
        open();
        player.play('t-1');
        async.flushTimers();
        trace().clear();
        player.play('t-2');
        async.flushTimers();
        expect(trace().take(3), [
          'device stops',
          'device stopped Track(t-1)',
          'fetch t-2 begins',
        ]);
        expect(device.playing?.id, 't-2');
        close(async);
      });
    });

    test('the stop is waited out whatever happens', () {
      fakeAsync((async) {
        open();
        final job = player.play('t-1');
        async.elapse(const Duration(milliseconds: 2));
        job.cancel().ignore();
        async.flushMicrotasks();
        expect(job.outcome, isNull, reason: 'the device is still stopping');
        async.flushTimers();
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(trace(), ['device stops']);
        expect(states, ['Loading', 'Idle']);
        close(async);
      });
    });

    test('cancellation ends the fetch at once, and the request goes on', () {
      fakeAsync((async) {
        open();
        final job = player.play('t-1');
        async.elapse(const Duration(milliseconds: 8));
        job.cancel().ignore();
        async.flushMicrotasks();
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(trace(), ['device stops', 'fetch t-1 begins']);
        async.flushTimers();
        expect(trace().last, 'fetch t-1 ends');
        expect(states, ['Loading', 'Idle']);
        close(async);
      });
    });

    test('the download is waited out, and closed as soon as it returns', () {
      fakeAsync((async) {
        open();
        final job = player.play('t-1');
        async.elapse(const Duration(milliseconds: 20));
        var back = false;
        job.cancel().then((_) => back = true);
        async.flushMicrotasks();
        expect(back, isFalse, reason: 'the download is still opening');
        async.elapse(const Duration(milliseconds: 5));
        expect(back, isTrue);
        expect(trace().skip(3), [
          'download of Track(t-1) begins',
          'download of Track(t-1) opened',
          'download of Track(t-1) closed',
        ]);
        expect('${job.outcome}', 'Cancelled(manual)');
        close(async);
      });
    });

    test('an error publishes Idle', () {
      fakeAsync((async) {
        stubs.stage.fetchError = StateError('offline');
        open();
        final job = player.play('t-1')..ignoreFailure();
        async.flushTimers();
        expect('${job.outcome}', 'Failed(Bad state: offline)');
        expect(states, ['Loading', 'Idle']);
        close(async);
      });
    });

    test('a disconnect is published at once and cancels the job there', () {
      fakeAsync((async) {
        open();
        final job = player.play('t-1');
        async.elapse(const Duration(milliseconds: 20));
        device.pullCable();
        expect(player.currentState, isA<stubs.Disconnected>());
        expect(job.isCancelled, isTrue, reason: 'cancelled at the change');
        expect(job.outcome, isNull, reason: 'the download is waited out');
        async.flushTimers();
        expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
        expect(states, ['Loading', 'Disconnected'], reason: 'Idle never');
        expect(trace(), contains('download of Track(t-1) closed'));
        close(async);
      });
    });

    test('the rule is asked before the start', () {
      fakeAsync((async) {
        open();
        device.pullCable();
        final job = player.play('t-1');
        async.flushTimers();
        expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
        expect(trace(), isEmpty);
        expect(states, ['Disconnected']);
        close(async);
      });
    });

    test("the rule is asked about a child's emit, not about the body's own",
        () {
      fakeAsync((async) {
        final byBody = _OwnRule();
        final byChild = _OwnRule();
        final ownJob = byBody.body();
        final childJob = byChild.child();
        async.flushTimers();
        expect('${ownJob.outcome}', 'Done(went on)');
        expect(byBody.currentState, isA<stubs.Disconnected>());
        expect('${childJob.outcome}', 'Cancelled(rules: keepWhile)');
        byBody.close().ignore();
        byChild.close().ignore();
        async.flushTimers();
      });
    });

    test('once the body has ended, a disconnect cancels nothing', () {
      fakeAsync((async) {
        stubs.stage.closeTake = 10;
        open();
        final job = player.play('t-1');
        // The track starts at 45 ms, and the download closes until 55.
        async.elapse(const Duration(milliseconds: 50));
        expect(states.last, 'Playing(Track(t-1))');
        expect(job.outcome, isNull, reason: 'the download is still closing');
        device.pullCable();
        async.flushTimers();
        expect('${job.outcome}', 'Done(Track(t-1))');
        expect(states.last, 'Disconnected');
        close(async);
      });
    });

    test('the call site prints what plays, and the volume goes out', () {
      final device = stubs.Device();
      final lines = <String>[];
      runZoned(
        () => fakeAsync((async) {
          tour.callSite(stubs.Api(), device);
          async.flushTimers();
        }),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) =>
              lines.add('$line, the device plays ${device.playing}'),
        ),
      );
      expect(lines, ['playing Track(t-1), the device plays Track(t-1)']);
      expect(device.volumes, [0.4]);
      expect(device.onDisconnect, isNull, reason: 'onClose let it go');
    });

    test('a drain refuses new work at the call and runs what was queued', () {
      fakeAsync((async) {
        open();
        player.setVolume(0.4);
        var closed = false;
        player.close(mode: SoloCloseMode.drain).then((_) => closed = true);
        final late = player.setVolume(0.7);
        async.flushMicrotasks();
        expect('${late.outcome}', 'Cancelled(closed)');
        async.flushTimers();
        expect(device.volumes, [0.4]);
        expect(closed, isTrue);
      });
    });

    test('after the close a report of the device would throw', () {
      fakeAsync((async) {
        open();
        final report = device.onDisconnect!;
        player.close().ignore();
        async.flushTimers();
        expect(device.onDisconnect, isNull);
        expect(report, throwsStateError);
        device.pullCable();
        expect(player.currentState, isA<stubs.Idle>());
      });
    });
  });

  group('The rest of the page', () {
    test('equal states are not filtered', () {
      fakeAsync((async) {
        final numbers = _Numbers();
        var heard = 0;
        numbers
          ..addListener(() => heard++)
          ..set(1)
          ..set(1);
        expect(heard, 2);
        numbers.close().ignore();
        async.flushTimers();
      });
    });

    test('vs-bloc.md compares eleven scenarios, as the page says twice', () {
      // Every `## ` section after the correspondences is a scenario.
      final sections = RegExp(r'^## (.*)$', multiLine: true)
          .allMatches(File('doc/vs-bloc.md').readAsStringSync())
          .map((match) => match.group(1))
          .toList();
      expect(sections.first, 'Correspondences');
      expect(sections.length - 1, 11);
      expect(_page(), contains('| Eleven scenarios in both packages |'));
      expect(_page(), contains('compares eleven application scenarios'));
    });

    test('every piece of code on the page is a run of lines of these files',
        () {
      final missing = codeMissingFrom(
        'README.md',
        'test/support/readme_quick_start.dart',
        alsoIn: [
          'test/support/readme_reload.dart',
          'test/support/readme_player.dart',
        ],
      );
      // The one block whose body the page elides: `readme_stream.dart`
      // holds it with that body filled in.
      expect(missing, hasLength(1));
      expect(
        missing.single,
        startsWith(
          'final class ProfileController extends Solo<ProfileState> '
          'with SoloStream {\n  // ...same as above...\n}',
        ),
      );
    });

    test('the fences the checks do not read are the two install commands', () {
      expect(strayFences('README.md'), ['```sh', '```sh']);
      expect(
        RegExp(r'```sh\n(.*?)\n```', dotAll: true)
            .allMatches(_page())
            .map((match) => match.group(1)),
        ['dart pub add solo', 'flutter pub add flutter_solo'],
      );
    });
  });
}
