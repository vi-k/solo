@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/children_page.dart' as children;
import 'support/children_stubs.dart';
import 'support/page_code.dart';
import 'support/streams_first_attempts.dart' as first;
import 'support/streams_page.dart' as page;

/// The sentinel of `doc/streams.md`.
///
/// The code of the page stands verbatim in `test/support/streams_*.dart`: the
/// first attempts in one file, the versions that work in another. The tests
/// below run that code and pin what the prose and the comments of the page say
/// about it. The stubs are those of `doc/children.md`, whose opening block one
/// test runs as well. What the page states of the engine and its code does not
/// show is pinned on `Bench`, a controller whose bodies are written where they
/// are run.
///
/// Every call of a stub runs until the test ends it, so each trace is the
/// order the test set and no timer decides it. A test collects what it saw in
/// [_seen] and asserts once the zone it ran in has returned: an `expect` that
/// failed inside would be one more error of that zone.

/// What the test at hand saw, in order.
final _seen = <String>[];

/// Adds [line] to [_seen], one entry for each fact it names: the facts of a
/// line are set apart by `; `.
void _see(String line) => _seen.addAll(line.split('; '));

/// A job with a `>` for every level it stands under its root.
String _label(Job<Object?> job) =>
    '${'>' * job.level}${job.level == 0 ? '' : ' '}$job';

/// An observer that writes what it hears to [_seen].
final class _Watch extends SoloObserver {
  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      _see('${_label(job)} started');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      _see('${_label(job)} finished ${job.outcome}');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      _see('state ${transition.current} by ${transition.job}');
}

String _page() => File('doc/streams.md').readAsStringSync();

/// The page with every run of whitespace turned into one space, so that a
/// phrase is found wherever its lines were broken.
String _prose() => _page().replaceAll(RegExp(r'\s+'), ' ');

/// Holds the page to [phrase]: the test that calls this runs what the phrase
/// says, so a page that stops saying it leaves the test with nothing to
/// stand for.
void _says(String phrase) => expect(
      _prose(),
      contains(phrase),
      reason: 'doc/streams.md no longer says this',
    );

/// What the page quotes under its `text` fences, in order.
List<String> _quotes() => [
      for (final block
          in RegExp(r'```text\n(.*?)\n```', dotAll: true).allMatches(_page()))
        block.group(1)!,
    ];

/// Runs [body] under fake time, in a zone of its own, and returns the errors
/// that reached that zone uncaught. Nothing is asserted inside: an `expect`
/// that failed in there would be one more error of the list.
List<String> _zone(void Function(FakeAsync async) body) {
  final errors = <String>[];
  fakeAsync((async) {
    runZonedGuarded(
      () => body(async),
      (error, stackTrace) => errors.add('$error'),
    );
    async.flushTimers();
  });

  return errors;
}

/// Ends [call] of a stub the way it would end on its own, and lets whatever
/// waited for it go on.
void _end(FakeAsync async, String call) {
  stage.end(call);
  async.flushMicrotasks();
}

/// How [job] stands: its outcome, or that it has none yet.
String _how(Job<Object?> job) => '${job.outcome ?? 'no outcome'}';

Future<void> _delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// A controller that follows a session from a subscription of its own, and
/// queues a short job for each update.
final class _Queueing extends Solo<Screen> {
  final SoloStream<Session> session;
  late final StreamSubscription<Session> _link;

  _Queueing(this.session) : super(const Screen()) {
    _take(session.currentState);
    _link = session.stream.listen(_take);
  }

  void _take(Session next) => run<Screen, void>(
        key: 'take',
        (ctx) async => ctx.emit(ctx.state.copyWith(signedIn: next.signedIn)),
      );

  Job<void> other() => run<Screen, void>(
        key: 'other',
        (ctx) => ctx.join(() => stage.start<void>('other', null)),
      );

  @override
  void onClose() => unawaited(_link.cancel());
}

/// A controller that follows a session from a subscription of its own, and
/// writes each update with `externalSetState`.
final class _Reflecting extends Solo<Screen> {
  final SoloStream<Session> session;
  late final StreamSubscription<Session> _link;

  _Reflecting(this.session)
      : super(Screen(signedIn: session.currentState.signedIn)) {
    _link = session.stream.listen(
      (next) => externalSetState(
        currentState.copyWith(signedIn: next.signedIn),
      ),
    );
  }

  Job<void> other() => run<Screen, void>(
        key: 'other',
        (ctx) => ctx.join(() => stage.start<void>('other', null)),
      );

  @override
  void onClose() => unawaited(_link.cancel());
}

void main() {
  setUp(() {
    stage = Stage();
    _seen.clear();
  });

  tearDown(() {
    stage.dispose();
    Solo.observer = null;
    Solo.unansweredHandler = null;
  });

  group('Processing a stream', () {
    group('the first attempt', () {
      test('the job is over before the first position, and the queue moves on',
          () {
        final errors = _zone((async) {
          final solo = first.Listening();
          final job = solo.track();
          final next = solo.run<Ready, void>(key: 'next', (ctx) async {});
          async.flushMicrotasks();
          _see('track ${_how(job)}, next ${_how(next)}, '
              'listening ${stage.positions.hasListener}');
        });

        expect(errors, isEmpty);
        expect(_seen, ['track Done(null), next Done(null), listening true']);
        _says('The body subscribes and returns, so the job is over before '
            'the first position arrives, and the queue moves on.');
      });

      test('each position throws out of emit into the zone', () {
        final errors = _zone((async) {
          final solo = first.Listening()..track();
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2);
          async.flushMicrotasks();
          _see('${solo.currentState}');
        });

        expect(_seen, ['Ready(sent: 0, position: 0, path: )']);
        expect(errors, [_quotes().first, _quotes().first]);
        expect(
          _quotes().first,
          'Bad state: Job(track) has already finished, cannot emit',
        );
        _says('Each position it delivers throws out of `emit` into the zone, '
            'and the state never changes:');
      });

      test('close() leaves the subscription where it is', () {
        final errors = _zone((async) {
          final solo = first.Listening()..track();
          async.flushMicrotasks();
          var closed = false;
          solo.close().then((_) => closed = true);
          async.flushMicrotasks();
          _see('closed $closed, listening ${stage.positions.hasListener}');
          stage.positions.add(1);
          async.flushMicrotasks();
        });

        expect(_seen, ['closed true, listening true']);
        expect(errors, [_quotes().first]);
        _says('Nothing ends that subscription either: there is no job left '
            'to cancel, and `close()` knows nothing of it.');
      });
    });

    test('onDispose(sub.cancel) ends the subscription with the body', () {
      final errors = _zone((async) {
        final bench = Bench();
        final job = bench.run<Ready, void>(key: 'track', (ctx) async {
          final sub = hw.positions.listen(
            (p) => ctx.emit(ctx.state.copyWith(position: p)),
          );
          ctx.onDispose(sub.cancel);
        });
        async.flushMicrotasks();
        _see('track ${_how(job)}, listening ${stage.positions.hasListener}');
        stage.positions.add(1);
        async.flushMicrotasks();
        _see('${bench.currentState}');
      });

      expect(errors, isEmpty);
      expect(_seen, [
        'track Done(null), listening false',
        'Ready(sent: 0, position: 0, path: )',
      ]);
      _says('Registering `sub.cancel` with `ctx.onDispose` does not repair '
          'that: the cleanup runs as soon as the body returns, and it cancels '
          'the subscription before the first position arrives.');
    });

    group('a child that owns the subscription', () {
      test('positions go into the state, written by the child', () {
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final solo = page.Tracker()..track();
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2);
          async.flushMicrotasks();
          _see('${solo.currentState}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'Job(track) started',
          '> Job(each) started',
          'state Ready(sent: 0, position: 1, path: ) by Job(each)',
          'state Ready(sent: 0, position: 2, path: ) by Job(each)',
          'Ready(sent: 0, position: 2, path: )',
        ]);
        _says('Observers see it as a separate job, and the name is one '
            '`ctx.each` gives it: `Job(each)`.');
      });

      test('the callback gets a SoloContext, and the child is a SoloJob', () {
        final errors = _zone((async) {
          Bench().run<Ready, void>(key: 'track', (ctx) async {
            final child = ctx.each(hw.positions, (childCtx, p) {
              // `state` is a member of `SoloContext` alone.
              _see('the job of that context is ${childCtx.job}; '
                  'its state is ${childCtx.state}');
            });
            _see('SoloJob ${child is SoloJob}, child ${child.isChild}, '
                'level ${child.level}, key ${child.key}, '
                'describe ${child.describe()}');
          });
          async.flushMicrotasks();
          stage.positions.add(1);
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'SoloJob true, child true, level 1, key null, describe each',
          'the job of that context is Job(each)',
          'its state is Ready(sent: 0, position: 0, path: )',
        ]);
        _says("Each event callback receives that child's context.");
      });

      test('the job ends when the source sends onDone', () {
        final errors = _zone((async) {
          final job = page.Tracker().track();
          async.elapse(const Duration(hours: 1));
          _see('an hour later: track ${_how(job)}');
          unawaited(stage.positions.close());
          async.flushMicrotasks();
          _see('the source is done: track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour later: track no outcome',
          'the source is done: track Done(null)',
        ]);
        _says('The child ends when the source sends `onDone`');
      });

      test('value brings a stream error into the parent body', () {
        late page.Tracker solo;
        final errors = _zone((async) {
          solo = page.Tracker();
          final job = solo.track()..ignoreFailure();
          async.flushMicrotasks();
          stage.positions.addError(StateError('hardware broke'));
          async.flushMicrotasks();
          _see('track ${_how(job)}, '
              'listening ${stage.positions.hasListener}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'track Failed(Bad state: hardware broke), listening false',
        ]);
        expect(solo.heard, [
          'Job(each): Bad state: hardware broke',
          'Job(track): Bad state: hardware broke',
        ]);
        _says("Returning the child's `.value` makes stream and callback "
            'errors propagate into the parent body.');
      });

      test('value brings a callback error into the parent body', () {
        final errors = _zone((async) {
          final bench = Bench();
          final job = bench.run<Ready, void>(
            key: 'track',
            (ctx) => ctx.each(hw.positions, (childCtx, p) {
              if (p == 2) {
                throw StateError('callback failed');
              }
              childCtx.emit(childCtx.state.copyWith(position: p));
            }).value,
          )..ignoreFailure();
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2)
            ..add(3);
          async.flushMicrotasks();
          _see('track ${_how(job)}; state ${bench.currentState}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'track Failed(Bad state: callback failed)',
          'state Ready(sent: 0, position: 1, path: )',
        ]);
      });

      test('done gives the outcome, and cancel() stops this subscription alone',
          () {
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> following;
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            following = ctx.each(hw.positions, (childCtx, p) {});
            _see('done gave ${await following.done}, the parent is cancelled '
                '${ctx.job.isCancelled}');
            await ctx.join(() => stage.start<void>('more', null));
          });
          async.flushMicrotasks();
          following.cancel().ignore();
          async.flushMicrotasks();
          _see('listening ${stage.positions.hasListener}, '
              'track ${_how(job)}');
          _end(async, 'more');
          _see('track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'done gave Cancelled(manual), the parent is cancelled false',
          'listening false, track no outcome',
          'track Done(null)',
        ]);
        _says('Use `.done` to inspect the outcome, or retain the returned '
            'job and call its `cancel()` to stop only this subscription.');
        _says('Cancelling only the child does not directly cancel the '
            'parent.');
      });

      test('an uncaught Cancelled from value cancels the parent', () {
        late Job<void> job;
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> following;
          job = bench.run<Ready, void>(key: 'track', (ctx) async {
            following = ctx.each(hw.positions, (childCtx, p) {});
            await following.value;
          });
          async.flushMicrotasks();
          following.cancel().ignore();
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(
          '${job.outcome}',
          'Cancelled(handler: child null: Cancelled(manual))',
        );
        _says("An uncaught `Cancelled` from the child's `.value` does "
            'cancel the parent through its body.');
      });

      test('an open stream with no events holds the parent and the queue', () {
        final errors = _zone((async) {
          final bench = Bench();
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.each(hw.positions, (childCtx, p) {});
          });
          final next = bench.run<Ready, void>(key: 'next', (ctx) async {});
          async.elapse(const Duration(hours: 1));
          _see('an hour later: track ${_how(job)}, next queued '
              '${next.isQueued}');
          unawaited(stage.positions.close());
          async.flushMicrotasks();
          _see('the source is done: track ${_how(job)}, next ${_how(next)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour later: track no outcome, next queued true',
          'the source is done: track Done(null), next Done(null)',
        ]);
        _says('so an open stream with no events is a child still running; '
            'and the parent waits for its children with or without an '
            'explicit await, so it keeps running too, and holds the queue');
      });

      test('close() cancels the child', () {
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final bench = Bench()
            ..run<Ready, void>(key: 'track', (ctx) async {
              ctx.each(hw.positions, (childCtx, p) {});
            });
          async.flushMicrotasks();
          _seen.clear();
          var closed = false;
          bench.close().then((_) => closed = true);
          async.flushMicrotasks();
          _see('closed $closed, listening ${stage.positions.hasListener}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          '> Job(each) finished Cancelled(parent)',
          'Job(track) finished Cancelled(closed)',
          'closed true, listening false',
        ]);
        _says('Accepted parent cancellation, including during `close()`, '
            'cancels the child');
      });

      test('a draining close cancels nothing and waits for the stream to end',
          () {
        final errors = _zone((async) {
          final bench = Bench();
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.each(hw.positions, (childCtx, p) {});
          });
          async.flushMicrotasks();
          var closed = false;
          bench.close(mode: SoloCloseMode.drain).then((_) => closed = true);
          async.elapse(const Duration(hours: 1));
          _see('an hour into the drain: track ${_how(job)}; closed $closed; '
              'listening ${stage.positions.hasListener}');
          unawaited(stage.positions.close());
          async.flushMicrotasks();
          _see('the source is done: track ${_how(job)}, closed $closed');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour into the drain: track no outcome',
          'closed false',
          'listening true',
          'the source is done: track Done(null), closed true',
        ]);
        _says('a draining `close(mode: SoloCloseMode.drain)` cancels nothing '
            'and waits for the stream to end');
      });

      test('the child is cancellable even if the parent is not', () {
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> following;
          final job = bench.run<Ready, void>(
            key: 'track',
            cancellable: false,
            (ctx) async {
              following = ctx.each(hw.positions, (childCtx, p) {});
            },
          );
          async.flushMicrotasks();
          var closed = false;
          bench.close().then((_) => closed = true);
          async.elapse(const Duration(hours: 1));
          _see('close(): track ${_how(job)}, child ${_how(following)}, '
              'closed $closed');
          following.cancel().ignore();
          async.flushMicrotasks();
          _see('child.cancel(): track ${_how(job)}; '
              'child ${_how(following)}, closed $closed');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'close(): track no outcome, child no outcome, closed false',
          'child.cancel(): track Done(null)',
          'child Cancelled(manual), closed true',
        ]);
        _says('The child is cancellable even if the parent is not.');
      });

      test('the child keeps keepWhile of the parent and skips canStart', () {
        final errors = _zone((async) {
          final bench = Bench();
          var asked = 0;
          late Job<void> following;
          final job = bench.run<Ready, void>(
            key: 'track',
            canStart: (state) {
              asked++;

              return true;
            },
            keepWhile: (state) => !state.paused,
            (ctx) async {
              following = ctx.each(hw.positions, (childCtx, p) {});
            },
          );
          async.flushMicrotasks();
          _see('canStart was asked $asked time(s)');
          bench.reflect(const Ready(paused: true));
          async.flushMicrotasks();
          _see('child ${_how(following)}, track ${_how(job)}; '
              'listening ${stage.positions.hasListener}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'canStart was asked 1 time(s)',
          'child Cancelled(rules: keepWhile), track Done(null)',
          'listening false',
        ]);
        _says("It retains the parent's working type and `keepWhile` after "
            'the parent body returns, but does not repeat `canStart`.');
      });

      test('the child keeps the working type of the parent', () {
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> following;
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            following = ctx.each(hw.positions, (childCtx, p) {});
          });
          async.flushMicrotasks();
          bench.reflect(const Off());
          async.flushMicrotasks();
          _see('child ${_how(following)}, track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'child Cancelled(rules: is not Ready), track Done(null)',
        ]);
      });

      test(
          'a child nobody reads: its failure goes to the zone, not to the '
          'parent', () {
        late Bench bench;
        final errors = _zone((async) {
          bench = Bench();
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.each(
              hw.positions,
              (childCtx, p) => throw StateError('callback failed'),
            );
          });
          async.flushMicrotasks();
          _see('the body returned: track ${_how(job)}');
          stage.positions.add(1);
          async.flushMicrotasks();
          _see('track ${_how(job)}');
        });

        expect(_seen, [
          'the body returned: track no outcome',
          'track Done(null)',
        ]);
        expect(errors, ['Bad state: callback failed']);
        expect(bench.heard, ['Job(each): Bad state: callback failed']);
        expect(bench.unanswered, isEmpty);
        _says("still holds the parent, but its failure is not the parent's: "
            'the parent ends `Done`, and the failure goes where a failure '
            'nobody read goes, to the zone');
      });

      test('the progress in _sync is such a child', () {
        late children.Syncer solo;
        final errors = _zone((async) {
          solo = children.Syncer();
          final job = solo.sync(1);
          async.flushMicrotasks();
          stage.progress.addError(StateError('progress broke'));
          async.flushMicrotasks();
          _end(async, 'push 1');
          _see('sync ${_how(job)}');
        });

        expect(_seen, ['sync Done(path/1)']);
        expect(errors, ['Bad state: progress broke']);
        expect(solo.heard, ['Job(each): Bad state: progress broke']);
        _says('A child whose outcome nobody reads, like the progress in '
            '`_sync` at the top of [Children and streams](children.md)');
      });

      test('ignoreFailure() on the child keeps its failure out of the zone',
          () {
        late Bench bench;
        final errors = _zone((async) {
          bench = Bench()
            ..run<Ready, void>(key: 'track', (ctx) async {
              ctx.each(hw.positions, (childCtx, p) {
                throw StateError('callback failed');
              }).ignoreFailure();
            });
          async.flushMicrotasks();
          stage.positions.add(1);
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(bench.heard, ['Job(each): Bad state: callback failed']);
        _says('`ignoreFailure()` on the child keeps it out of the zone.');
      });

      test('events are delivered one at a time', () {
        final errors = _zone((async) {
          Bench().run<Ready, void>(
            key: 'track',
            (ctx) => ctx.each(hw.positions, (childCtx, p) async {
              await childCtx.join(() => stage.start<void>('handle $p', null));
            }).value,
          );
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2);
          async.flushMicrotasks();
          _see('${stage.trace}');
          _end(async, 'handle 1');
          _see('${stage.trace}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          '[handle 1 start]',
          '[handle 1 start, handle 1 end, handle 2 start]',
        ]);
        _says('Events are delivered one at a time, and a cancellation waits '
            'for the callback in flight.');
      });

      for (final waiting in ['a plain await', 'childCtx.abandonable']) {
        test('$waiting in the callback, and close()', () {
          final errors = _zone((async) {
            final bench = Bench();
            String? returned;
            String? closed;
            final job = bench.run<Ready, void>(
              key: 'track',
              (ctx) => ctx.each(hw.positions, (childCtx, p) async {
                try {
                  if (waiting == 'childCtx.abandonable') {
                    await childCtx.abandonable(() => _delay(1000));
                  } else {
                    await _delay(1000);
                  }
                } finally {
                  returned = '${async.elapsed.inMilliseconds} ms';
                }
              }).value,
            );
            final next = bench.run<Ready, void>(key: 'next', (ctx) async {});
            async.flushMicrotasks();
            stage.positions.add(1);
            async.elapse(const Duration(milliseconds: 50));
            bench
                .close()
                .then((_) => closed = '${async.elapsed.inMilliseconds} ms');
            async.flushMicrotasks();
            _see('at 50 ms: listening ${stage.positions.hasListener}; '
                'track ${_how(job)}, next ${_how(next)}');
            async.elapse(const Duration(seconds: 5));
            _see('the callback returned at $returned, close() at $closed');
          });

          final at = waiting == 'childCtx.abandonable' ? '50 ms' : '1000 ms';
          final track = waiting == 'childCtx.abandonable'
              ? 'Cancelled(closed)'
              : 'no outcome';
          expect(errors, isEmpty);
          expect(_seen, [
            'at 50 ms: listening false',
            'track $track, next Cancelled(closed)',
            'the callback returned at $at, close() at $at',
          ]);
          _says(
              '`childCtx.abandonable` ends with the cancellation the moment it '
              'arrives and leaves the action running alone, while a plain '
              '`await` ends only when its own future does');
          _says('until the callback returns, the child and the parent are '
              'still running, the queue is held and `close()` does not come '
              'back');
        });
      }

      for (final awaited in ['done', 'value', 'cancel()']) {
        test('a callback that awaits $awaited of its own child never returns',
            () {
          final errors = _zone((async) {
            final bench = Bench();
            late Job<void> following;
            var returned = false;
            final job = bench.run<Ready, void>(key: 'track', (ctx) async {
              following = ctx.each(hw.positions, (childCtx, p) async {
                switch (awaited) {
                  case 'done':
                    await following.done;
                  case 'value':
                    await following.value;
                  default:
                    await following.cancel();
                }
                returned = true;
              });
            });
            async.flushMicrotasks();
            stage.positions.add(1);
            async.flushMicrotasks();
            var closed = false;
            bench.close().then((_) => closed = true);
            async.elapse(const Duration(seconds: 100));
            _see('the callback returned $returned; '
                'child ${_how(following)}, track ${_how(job)}, '
                'closed $closed');
          });

          expect(errors, isEmpty);
          expect(_seen, [
            'the callback returned false',
            'child no outcome, track no outcome, closed false',
          ]);
          _says("Do not await the child's own completion or its `cancel()` "
              'inside an event callback: that is a deadlock.');
        });
      }

      test('a callback stops its own subscription with an unawaited cancel()',
          () {
        final errors = _zone((async) {
          final bench = Bench();
          late Job<void> following;
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            following = ctx.each(hw.positions, (childCtx, p) {
              _see('position $p');
              following.cancel().ignore();
            });
          });
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2);
          async.flushMicrotasks();
          _see('child ${_how(following)}, track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'position 1',
          'child Cancelled(manual), track Done(null)',
        ]);
        _says('To stop the subscription from inside a callback, call '
            '`cancel()` and do not await it.');
      });

      test('the child does not wait for the cleanup of the source', () {
        final errors = _zone((async) {
          final bench = Bench();
          final source = StreamController<int>(
            onCancel: () => Completer<void>().future,
          );
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.each(source.stream, (childCtx, p) {});
          });
          async.flushMicrotasks();
          job.cancel().ignore();
          async.flushMicrotasks();
          _see('track ${_how(job)}');
          unawaited(source.close());
        });

        expect(errors, isEmpty);
        expect(_seen, ['track Cancelled(manual)']);
        _says('The child does not wait for the source');
      });

      test(
          'a cleanup of the source that fails goes to onError and on to '
          'onUnanswered', () {
        late Bench bench;
        final errors = _zone((async) {
          bench = Bench();
          final source = StreamController<int>(
            onCancel: () => Future<void>.error(StateError('cleanup failed')),
          );
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.each(source.stream, (childCtx, p) {});
          });
          async.flushMicrotasks();
          job.cancel().ignore();
          async.flushMicrotasks();
          _see('track ${_how(job)}');
          unawaited(source.close());
        });

        expect(_seen, ['track Cancelled(manual)']);
        expect(bench.heard, ['Job(each): Bad state: cleanup failed']);
        expect(bench.unanswered, ['Job(each): Bad state: cleanup failed']);
        expect(errors, ['Bad state: cleanup failed']);
        _says('If that cleanup fails, its error goes to `Solo.onError` and '
            'on to `Solo.onUnanswered`, as an error no outcome carries does.');
      });

      test(
          'a job with the closing of its source on its cleanup stack ends '
          'after it', () {
        final errors = _zone((async) {
          final bench = Bench();
          final job = bench.run<Ready, void>(key: 'track', (ctx) async {
            ctx.onDispose(() => stage.start<void>('close the source', null));
            await ctx.each(hw.positions, (childCtx, p) {}).value;
          });
          async.flushMicrotasks();
          job.cancel().ignore();
          async.flushMicrotasks();
          _see('cancelled: track ${_how(job)}, ${stage.trace}');
          _end(async, 'close the source');
          _see('the source closed: track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'cancelled: track no outcome, [close the source start]',
          'the source closed: track Cancelled(manual)',
        ]);
        _says('A job that must not end before its source has closed waits '
            'for that itself');
      });

      test(
          'a child for the event, made with job(...), closes what the event '
          'opened before the next one', () {
        final errors = _zone((async) {
          final bench = Bench();
          SoloJob<void> forEvent(int p) =>
              bench.job<Ready, void>(key: 'event', (eventCtx) async {
                eventCtx.onDispose(() => stage.trace.add('close $p'));
                stage.trace.add('open $p');
              });
          bench.run<Ready, void>(
            key: 'track',
            (ctx) => ctx
                .each(hw.positions, (childCtx, p) => childCtx.run(forEvent(p)))
                .value,
          );
          async.flushMicrotasks();
          stage.positions
            ..add(1)
            ..add(2);
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(stage.trace, ['open 1', 'close 1', 'open 2', 'close 2']);
        _says('The rest of that page holds here as well, with `job(...)` '
            'where it writes `Job.deferred`');
      });

      test('a callback in several steps stops between them for a cancellation',
          () {
        final errors = _zone((async) {
          final bench = Bench();
          final job = bench.run<Ready, void>(
            key: 'track',
            (ctx) => ctx.each(hw.positions, (childCtx, p) async {
              await childCtx.join(() => stage.start<void>('first step', null));
              await childCtx.join(() => stage.start<void>('second step', null));
            }).value,
          );
          async.flushMicrotasks();
          stage.positions.add(1);
          async.flushMicrotasks();
          job.cancel().ignore();
          async.flushMicrotasks();
          _end(async, 'first step');
          _see('track ${_how(job)}');
        });

        expect(errors, isEmpty);
        expect(_seen, ['track Cancelled(manual)']);
        expect(stage.trace, ['first step start', 'first step end']);
      });
    });
  });

  group('Following another controller', () {
    group('the first attempt', () {
      test('a session already signed in sends nothing', () {
        final errors = _zone((async) {
          final session = SessionController(const Session(signedIn: true));
          final screen = first.ScreenController(session)..follow();
          async.elapse(const Duration(hours: 1));
          _see('an hour later: session ${session.currentState}; '
              'screen ${screen.currentState}');
          session.sign(signedIn: false);
          async.flushMicrotasks();
          session.sign(signedIn: true);
          async.flushMicrotasks();
          _see('the session changed: screen ${screen.currentState}');
          screen.close();
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour later: session Session(signedIn: true)',
          'screen Screen(signedIn: false)',
          'the session changed: screen Screen(signedIn: true)',
        ]);
        _says('A session that is already signed in when `follow()` starts '
            'sends nothing, and the screen goes on showing `signedIn: false` '
            'until the session changes.');
      });
    });

    group('the state first, then the stream', () {
      test('follow() takes what has already happened, then what happens next',
          () {
        final errors = _zone((async) {
          final session = SessionController(const Session(signedIn: true));
          final screen = page.ScreenController(session)..follow();
          async.flushMicrotasks();
          _see('started: ${screen.currentState}');
          session.sign(signedIn: false);
          async.flushMicrotasks();
          _see('signed out: ${screen.currentState}');
          session.sign(signedIn: true);
          async.flushMicrotasks();
          _see('signed in: ${screen.currentState}');
          screen.close();
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'started: Screen(signedIn: true)',
          'signed out: Screen(signedIn: false)',
          'signed in: Screen(signedIn: true)',
        ]);
      });

      test("the first write is the parent's, the later ones are the child's",
          () {
        final errors = _zone((async) {
          Solo.observer = _Watch();
          final session = SessionController(const Session(signedIn: true));
          page.ScreenController(session).follow();
          async.flushMicrotasks();
          session.sign(signedIn: false);
          async.flushMicrotasks();
        });

        expect(errors, isEmpty);
        expect(
          [
            for (final line in _seen)
              if (line.startsWith('state Screen')) line,
          ],
          [
            'state Screen(signedIn: true) by Job(follow)',
            'state Screen(signedIn: false) by Job(each)',
          ],
        );
      });

      test('a change right before the job starts and right after is not lost',
          () {
        final errors = _zone((async) {
          final session = SessionController();
          final screen = page.ScreenController(session);
          session.sign(signedIn: true);
          screen.follow();
          async.flushMicrotasks();
          _see('${session.currentState}, ${screen.currentState}');
          session.sign(signedIn: false);
          async.flushMicrotasks();
          _see('${session.currentState}, ${screen.currentState}');
          screen.close();
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'Session(signedIn: true), Screen(signedIn: true)',
          'Session(signedIn: false), Screen(signedIn: false)',
        ]);
        _says('so no change of the session falls between the two');
      });

      test('the job ends when the session closes its stream', () {
        final errors = _zone((async) {
          final session = SessionController();
          final screen = page.ScreenController(session);
          final following = screen.follow();
          final other = screen.other();
          async.elapse(const Duration(hours: 1));
          _see('an hour later: follow ${_how(following)}, '
              'other ${_how(other)}, ${stage.trace}');
          session.close();
          async.flushMicrotasks();
          _see('the session closed: follow ${_how(following)}; '
              'other ${_how(other)}, ${stage.trace}');
          screen.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour later: follow no outcome, other no outcome, []',
          'the session closed: follow Done(null)',
          'other Done(null), [other ran]',
        ]);
        _says('no other job of that controller starts before the session '
            'closes its stream');
      });

      test('closing the following controller cancels the job', () {
        final errors = _zone((async) {
          final session = SessionController();
          final screen = page.ScreenController(session);
          final following = screen.follow();
          async.flushMicrotasks();
          var closed = false;
          screen.close().then((_) => closed = true);
          async.flushMicrotasks();
          _see('follow ${_how(following)}, closed $closed');
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, ['follow Cancelled(closed), closed true']);
      });

      test('a draining close waits for the session to close', () {
        final errors = _zone((async) {
          final session = SessionController();
          final screen = page.ScreenController(session);
          final following = screen.follow();
          async.flushMicrotasks();
          var closed = false;
          screen.close(mode: SoloCloseMode.drain).then((_) => closed = true);
          async.elapse(const Duration(hours: 1));
          _see('an hour into the drain: follow ${_how(following)}, '
              'closed $closed');
          session.close();
          async.flushMicrotasks();
          _see('the session closed: follow ${_how(following)}, '
              'closed $closed');
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'an hour into the drain: follow no outcome, closed false',
          'the session closed: follow Done(null), closed true',
        ]);
        _says('and a draining `close` waits for the same');
      });

      test('a subscription of its own that queues a short job for each update',
          () {
        final errors = _zone((async) {
          final session = SessionController(const Session(signedIn: true));
          final screen = _Queueing(session);
          async.flushMicrotasks();
          _see('started: ${screen.currentState}');
          final other = screen.other();
          async.flushMicrotasks();
          session.sign(signedIn: false);
          async.flushMicrotasks();
          _see('while another job runs: ${screen.currentState}');
          _end(async, 'other');
          _see('that job is over: ${screen.currentState}, '
              'other ${_how(other)}');
          screen.close();
          async.flushMicrotasks();
          session.sign(signedIn: true);
          async.flushMicrotasks();
          _see('after onClose: ${screen.currentState}');
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'started: Screen(signedIn: true)',
          'while another job runs: Screen(signedIn: true)',
          'that job is over: Screen(signedIn: false), other Done(null)',
          'after onClose: Screen(signedIn: false)',
        ]);
        _says('made in its constructor and cancelled in `onClose`, and from '
            'it either queues a short job for each update');
      });

      test('a subscription of its own that writes with externalSetState', () {
        final errors = _zone((async) {
          final session = SessionController(const Session(signedIn: true));
          final screen = _Reflecting(session);
          final other = screen.other();
          async.flushMicrotasks();
          session.sign(signedIn: false);
          async.flushMicrotasks();
          _see('while another job runs: ${screen.currentState}, '
              'other ${_how(other)}');
          _end(async, 'other');
          screen.close();
          async.flushMicrotasks();
          session.sign(signedIn: true);
          async.flushMicrotasks();
          _see('after onClose: ${screen.currentState}');
          session.close();
        });

        expect(errors, isEmpty);
        expect(_seen, [
          'while another job runs: Screen(signedIn: false), other no outcome',
          'after onClose: Screen(signedIn: false)',
        ]);
        _says('when the update is a fact the running work has to hear at '
            'once, writes it with `externalSetState`');
      });
    });
  });

  group('The page', () {
    test('both sections open with a first attempt, as the introduction says',
        () {
      expect(
        RegExp(r'^### The first attempt$', multiLine: true).allMatches(_page()),
        hasLength(2),
      );
      _says('Both sections below open with the version');
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/streams.md'), isEmpty);
    });

    // Each version under its own file: an answer turned into its own first
    // attempt would still be found among all of them.
    const answers = 'test/support/streams_page.dart';
    const attempts = 'test/support/streams_first_attempts.dart';
    const holders = {
      '### The first attempt': attempts,
      '### A child that owns the subscription': answers,
      '### The state first, then the stream': answers,
    };
    for (final MapEntry(key: heading, value: holder) in holders.entries) {
      test('the code under "$heading" is a run of lines of $holder', () {
        expect(
          codeMissingFrom('doc/streams.md', holder, under: heading),
          isEmpty,
        );
      });
    }

    test('every piece of code on the page is a run of lines of these files',
        () {
      expect(
        codeMissingFrom('doc/streams.md', answers, alsoIn: [attempts]),
        isEmpty,
      );
    });

    test('every heading with code under it is held to a file', () {
      final withCode = [
        for (final part in _page().split(RegExp('^(?=#)', multiLine: true)))
          if (part.contains('```dart')) part.split('\n').first,
      ];
      expect(withCode.toSet(), holders.keys.toSet());
    });
  });
}
