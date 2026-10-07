@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/cancellation_first_attempts.dart' as first;
import 'support/cancellation_page.dart' as page;
import 'support/cancellation_stubs.dart';
import 'support/page_code.dart';
import 'support/test_solo.dart';

/// The sentinel of `doc/cancellation.md`.
///
/// The code of the page stands verbatim in `test/support/cancellation_*.dart`:
/// the first and second attempts in one file, the versions that work and the
/// code the sections open with in another. The tests below run that code and
/// pin what the prose, the table and the comments of the page say about it.
/// What the page states of the engine and its code does not show is pinned on
/// `Bench`, a controller whose bodies are written where they are run.
///
/// Every call of a stub runs until the test ends it, so each trace is the
/// order the test set and no timer decides it; fake time moves only where
/// the page is about time, at a delay and at an accumulation window.

/// A controller with a group that waits for its accumulation window.
final class _Windowed extends Solo<AppState> with OpenSolo<AppState>, Desk {
  _Windowed() : super(const Ready());

  late final _lines = accumulate<Ready, String, void>(
    key: 'lines',
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 200)),
    merge: (previous, incoming) => '$previous+$incoming',
    (ctx, text) async => stage.trace.add('lines sent: $text'),
  );

  SoloJob<void> line(String text) => _lines.add(text);
}

/// The seek of "A deadline of a job" with `Future.timeout` on the call in
/// place of the `timeout` of `run`.
final class _CallDeadline extends Solo<AppState> with OpenSolo<AppState>, Desk {
  _CallDeadline() : super(const Ready());

  SoloJob<void> seek(Duration position) => run<Ready, void>(
        key: 'seek',
        policy: Policy.restart,
        onError: (state, error, stackTrace) => const Offline(),
        onCancel: (state, cancelled) => state,
        (ctx) async {
          await ctx.join(
            () => player.seek(position).timeout(const Duration(seconds: 2)),
          );
          ctx.emit(ctx.state.copyWith(position: position));
        },
      );
}

/// What a run under [_zone] left behind: the errors that reached the zone
/// uncaught, and the lines the code printed.
typedef _Left = ({List<String> errors, List<String> printed});

String _page() => File('doc/cancellation.md').readAsStringSync();

/// The page with every run of whitespace turned into one space, so that a
/// phrase is found wherever its lines were broken.
String _prose() => _page().replaceAll(RegExp(r'\s+'), ' ');

Duration _s(int seconds) => Duration(seconds: seconds);

/// Runs [body] under fake time, in a zone of its own. Nothing is asserted
/// inside: an `expect` that failed in there would be one more error of the
/// list.
_Left _zone(void Function(FakeAsync async) body) {
  final errors = <String>[];
  final printed = <String>[];
  fakeAsync((async) {
    runZonedGuarded(
      () => body(async),
      (error, stackTrace) => errors.add('$error'),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    async.flushTimers();
  });

  return (errors: errors, printed: printed);
}

/// Ends [call] of a stub the way it would end on its own, and lets whatever
/// waited for it go on.
void _end(FakeAsync async, String call) {
  stage.end(call);
  async.flushMicrotasks();
}

/// Fails [call] of a stub with [error].
void _fail(FakeAsync async, String call, Object error) {
  stage.fail(call, error);
  async.flushMicrotasks();
}

/// How [job] ended: the outcome, and for a cancellation whether the body
/// had started.
String _how(Job<Object?> job) => switch (job.outcome) {
      final Cancelled cancelled => '$cancelled, started: ${cancelled.started}',
      final other => '$other',
    };

/// The reason [job] was cancelled for.
CancelReason _reason(Job<Object?> job) => (job.outcome! as Cancelled).reason;

/// What an attempt to use a member of a context came to.
String _kind(Object error) => switch (error) {
      StateError() => 'StateError',
      Cancelled() => '$error',
      _ => 'another error',
    };

/// Calls [action] and writes under [name] what it came to: `returned`, or
/// what it threw. A future is followed to its end.
void _attempt(
  Map<String, String> into,
  String name,
  Object? Function() action,
) {
  try {
    final result = action();
    if (result is Future<Object?>) {
      into[name] = 'a future';
      result.then<void>(
        (_) {
          into[name] = 'returned';
        },
        onError: (Object error) {
          into[name] = _kind(error);
        },
      );
    } else {
      into[name] = 'returned';
    }
  } on Object catch (error) {
    into[name] = _kind(error);
  }
}

/// Tries every member of [ctx] and says what each came to.
Map<String, String> _tryEverything(
  SoloContext<AppState, Ready> ctx,
  Bench bench,
) {
  final came = <String, String>{};
  _attempt(came, 'state', () => ctx.state);
  _attempt(came, 'stateAs', () => ctx.stateAs<Ready>());
  _attempt(came, 'check', ctx.check);
  _attempt(came, 'emit', () => ctx.emit(const Ready()));
  _attempt(
    came,
    'run',
    () => ctx.run(bench.job<Ready, void>((child) async {})),
  );
  _attempt(
    came,
    'each',
    () => ctx.each(const Stream<int>.empty(), (child, event) {}),
  );
  _attempt(came, 'abandonable', () => ctx.abandonable(() async => 1));
  _attempt(came, 'join', () => ctx.join(() async => 1));
  _attempt(came, 'pause', ctx.pause);
  _attempt(came, 'uncancellable', () => ctx.uncancellable(() async => 1));
  _attempt(came, 'onCancel', () => ctx.onCancel(() {}));
  _attempt(came, 'log', () => ctx.log('a line'));
  _attempt(came, 'job', () => ctx.job);
  _attempt(came, 'onDispose', () => ctx.onDispose(() {}));
  _attempt(came, 'onDiscard', () => ctx.onDiscard(() {}));
  _attempt(came, 'disown', () => ctx.disown(bench));
  _attempt(came, 'unattended', () => ctx.unattended(() {}));

  return came;
}

void main() {
  setUp(() => stage = Stage());

  tearDown(() {
    Solo.observer = null;
    Solo.errorHandler = null;
    Solo.debug = null;
  });

  group('The table', () {
    test('abandonable throws Cancelled without waiting for the operation', () {
      fakeAsync((async) {
        Object? thrown;
        final job = Bench().run<Ready, void>((ctx) async {
          try {
            await ctx.abandonable(() => stage.start<void>('call', null));
          } on Cancelled catch (cancelled) {
            thrown = cancelled;
            rethrow;
          }
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();

        expect(thrown, isA<Cancelled>());
        expect(thrown, same(job.outcome));
        expect(stage.isRunning('call'), isTrue);
        _end(async, 'call');
      });
    });

    test('join waits for the operation, then throws Cancelled for the result',
        () {
      fakeAsync((async) {
        Object? thrown;
        String? value;
        final job = Bench().run<Ready, void>((ctx) async {
          try {
            value = await ctx.join(() => stage.start('call', 'value'));
          } on Cancelled catch (cancelled) {
            thrown = cancelled;
            rethrow;
          }
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        expect(thrown, isNull, reason: 'the operation is waited for');

        _end(async, 'call');
        expect(thrown, same(job.outcome));
        expect(value, isNull, reason: 'the successful result is not handed in');
      });
    });

    test('uncancellable returns its result, and the next checkpoint throws',
        () {
      fakeAsync((async) {
        final job = Bench().run<Ready, String>((ctx) async {
          final receipt = await ctx.uncancellable(
            () => stage.start('payment', 'receipt'),
          );
          stage.trace.add('after the section: $receipt');
          ctx.check();
          stage.trace.add('after the check');

          return receipt;
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();

        _end(async, 'payment');
        expect(
          stage.trace,
          ['payment start', 'payment end', 'after the section: receipt'],
          reason: 'the code after the call runs until the check',
        );
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('pause throws Cancelled at once, and cancels its timer', () {
      fakeAsync((async) {
        final job = Bench().run<Ready, void>((ctx) => ctx.pause(_s(1)));
        async
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 500));
        expect(async.pendingTimers, hasLength(1));

        unawaited(job.cancel());
        async.flushMicrotasks();
        expect('${job.outcome}', 'Cancelled(manual)');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('check throws when the job is already cancelled', () {
      fakeAsync((async) {
        final job = Bench().run<Ready, void>((ctx) async {
          await stage.start<void>('plain', null);
          stage.trace.add('the body went on');
          ctx.check();
          stage.trace.add('after the check');
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        expect(job.isCancelled, isTrue);

        _end(async, 'plain');
        expect(
          stage.trace,
          ['plain start', 'plain end', 'the body went on'],
          reason: 'the body goes on until its next checkpoint',
        );
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('check throws when the rules of the job no longer hold', () {
      fakeAsync((async) {
        final job = Bench().run<Ready, void>((ctx) async {
          ctx.emit(const Offline());
          stage.trace.add('cancelled by the emit: ${ctx.job.isCancelled}');
          ctx.check();
          stage.trace.add('after the check');
        });
        async.flushMicrotasks();

        expect(stage.trace, ['cancelled by the emit: false']);
        expect('${job.outcome}', 'Cancelled(rules: is not Ready)');
      });
    });

    test('names the checkpoints these tests run', () {
      final rows = RegExp(r'^\| `(ctx\.\w+\(\w*\))` \|', multiLine: true)
          .allMatches(_page())
          .map((row) => row.group(1));
      expect(rows, [
        'ctx.abandonable(action)',
        'ctx.join(action)',
        'ctx.uncancellable(action)',
        'ctx.pause(duration)',
        'ctx.check()',
      ]);
    });
  });

  group('The queue and a checkpoint', () {
    test(
        'a request that abandonable let go of outlives the job and the next '
        'one', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.run<Ready, void>(
          (ctx) => ctx.abandonable(() => stage.start<void>('request', null)),
        );
        final next = bench.work('next');
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();

        expect('${job.outcome}', 'Cancelled(manual)');
        expect(stage.trace, ['request start', 'next start']);
        _end(async, 'next');
        expect('${next.outcome}', 'Done(null)');
        expect(stage.isRunning('request'), isTrue);
        _end(async, 'request');
      });
    });

    test('the queue does not proceed past a call that join stays with', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.work('command');
        bench.work('next');
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        expect(stage.trace, ['command start']);

        _end(async, 'command');
        expect(stage.trace, ['command start', 'command end', 'next start']);
        _end(async, 'next');
      });
    });
  });

  group('Stopping the underlying operation', () {
    test(
        'the first attempt: by abandonable, three seeks are on the device at '
        'once', () {
      fakeAsync((async) {
        final player = first.AbandoningPlayer();
        final one = player.seek(_s(1));
        async.flushMicrotasks();
        final two = player.seek(_s(2));
        async.flushMicrotasks();
        final three = player.seek(_s(3));
        async.flushMicrotasks();

        expect(
          stage.trace,
          ['seek 1 start', 'seek 2 start', 'seek 3 start'],
          reason: 'the wait lets go of the call, and the call goes on',
        );
        expect('${one.outcome}', 'Cancelled(replaced)');
        expect('${two.outcome}', 'Cancelled(replaced)');

        // What the device makes of that is up to the device: here the last
        // seek comes back first.
        _end(async, 'seek 3');
        _end(async, 'seek 2');
        _end(async, 'seek 1');
        expect('${three.outcome}', 'Done(null)');
        expect(
          '${player.currentState}',
          'Ready(3 s, null)',
          reason: 'only the last job gets as far as emit',
        );
      });
    });

    test('the second attempt: by join, the seek dragged past runs to its end',
        () {
      fakeAsync((async) {
        final player = first.JoiningPlayer();
        final one = player.seek(_s(1));
        async.flushMicrotasks();
        final two = player.seek(_s(2));
        async.flushMicrotasks();
        final three = player.seek(_s(3));
        async.flushMicrotasks();

        expect(stage.trace, ['seek 1 start']);
        expect(one.isCancelled, isTrue);
        expect(one.outcome, isNull, reason: 'nothing told the device');
        expect(
          _how(two),
          'Cancelled(replaced), started: false',
          reason: 'restart removed the queued one before it started',
        );

        _end(async, 'seek 1');
        expect(
          stage.trace,
          ['seek 1 start', 'seek 1 end', 'seek 3 start'],
          reason: 'only then does the last seek begin',
        );
        expect('${one.outcome}', 'Cancelled(replaced)');
        expect(
          '${player.currentState}',
          'Ready(0 s, null)',
          reason: 'waiting the call out does not make its result count',
        );

        _end(async, 'seek 3');
        expect('${three.outcome}', 'Done(null)');
        expect('${player.currentState}', 'Ready(3 s, null)');
      });
    });

    test('the token: each seek stops before the next one starts', () {
      fakeAsync((async) {
        final player = page.TokenPlayer();
        final one = player.seek(_s(1));
        async.flushMicrotasks();
        player.seek(_s(2));
        async.flushMicrotasks();
        final three = player.seek(_s(3));
        async.flushMicrotasks();

        expect(stage.trace, [
          'seek 1 start',
          'token cancelled',
          'seek 1 stopped',
          'seek 2 start',
          'token cancelled',
          'seek 2 stopped',
          'seek 3 start',
        ]);
        expect('${one.outcome}', 'Cancelled(replaced)');

        _end(async, 'seek 3');
        expect('${three.outcome}', 'Done(null)');
        expect('${player.currentState}', 'Ready(3 s, null)');
        expect(player.heard, isEmpty);
      });
    });

    test('the callback of ctx.onCancel runs inside cancel()', () {
      fakeAsync((async) {
        final job = page.TokenPlayer().seek(_s(1));
        async.flushMicrotasks();
        unawaited(job.cancel());
        stage.trace.add('cancel() returned');

        expect(stage.trace, [
          'seek 1 start',
          'token cancelled',
          'seek 1 stopped',
          'cancel() returned',
        ]);
        async.flushMicrotasks();
      });
    });

    test(
        'a player that ignores the token puts the seek back at the second '
        'attempt', () {
      fakeAsync((async) {
        stage.hearsTokens = false;
        final player = page.TokenPlayer();
        final one = player.seek(_s(1));
        async.flushMicrotasks();
        player.seek(_s(2));
        async.flushMicrotasks();
        player.seek(_s(3));
        async.flushMicrotasks();
        expect(stage.trace, ['seek 1 start', 'token cancelled']);

        _end(async, 'seek 1');
        expect(
          stage.trace,
          ['seek 1 start', 'token cancelled', 'seek 1 end', 'seek 3 start'],
          reason: 'the seek dragged past ran to its end',
        );
        expect('${one.outcome}', 'Cancelled(replaced)');
        _end(async, 'seek 3');
      });
    });

    test(
        'a player that stops by throwing: the hook hears every seek dragged '
        'past', () {
      late page.TokenPlayer player;
      late List<Job<void>> jobs;
      final left = _zone((async) {
        stage.stopsByThrowing = true;
        player = page.TokenPlayer();
        jobs = [];
        for (final position in [1, 2, 3]) {
          jobs.add(player.seek(_s(position)));
          async.flushMicrotasks();
        }
        _end(async, 'seek 3');
      });

      expect(
        [for (final job in jobs) '${job.outcome}'],
        ['Cancelled(replaced)', 'Cancelled(replaced)', 'Done(null)'],
      );
      expect(player.heard, [isA<SeekStopped>(), isA<SeekStopped>()]);
      expect(player.unanswered, isEmpty);
      expect(left.errors, isEmpty);
    });

    test('a catch with ctx.check() first lets the cancellation out instead',
        () {
      late Bench bench;
      late Job<void> job;
      final left = _zone((async) {
        stage.stopsByThrowing = true;
        bench = Bench();
        job = bench.run<Ready, void>((ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          try {
            await ctx.join(() => player.seek(_s(1), cancelToken: token));
          } on SeekStopped {
            ctx.check();
            rethrow;
          }
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
      });

      expect(
        stage.trace,
        ['seek 1 start', 'token cancelled', 'seek 1 stopped'],
      );
      expect('${job.outcome}', 'Cancelled(manual)');
      expect(bench.heard, isEmpty);
      expect(left.errors, isEmpty);
    });

    test('the function ctx.onCancel returns unregisters the callback', () {
      fakeAsync((async) {
        final job = Bench().run<Ready, void>((ctx) async {
          final unregister = ctx.onCancel(() => stage.trace.add('callback'));
          await stage.start<void>('first', null);
          unregister();
          await ctx.join(() => stage.start<void>('second', null));
        });
        async.flushMicrotasks();
        _end(async, 'first');
        unawaited(job.cancel());
        async.flushMicrotasks();
        _end(async, 'second');

        expect(stage.trace, isNot(contains('callback')));
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('the onCancel of run computes the state once the job has cleaned up',
        () {
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.run<Ready, void>(
          onCancel: (state, cancelled) {
            stage.trace.add('the onCancel of run');

            return const Ready(receipt: 'corrected');
          },
          (ctx) async {
            ctx
              ..onCancel(() => stage.trace.add('the callback of ctx.onCancel'))
              ..onDispose(() => stage.trace.add('cleanup'));
            await ctx.join(() => stage.start<void>('call', null));
          },
        );
        job.done.then((_) => stage.trace.add('the job is over')).ignore();
        async.flushMicrotasks();
        unawaited(job.cancel());
        stage.trace.add('cancel() returned');
        async.flushMicrotasks();
        expect('${bench.currentState}', 'Ready(0 s, null)');

        _end(async, 'call');
        expect(stage.trace, [
          'call start',
          'the callback of ctx.onCancel',
          'cancel() returned',
          'call end',
          'cleanup',
          'the onCancel of run',
          'the job is over',
        ]);
        expect('${bench.currentState}', 'Ready(0 s, corrected)');
      });
    });
  });

  group('Protecting a step or a whole job', () {
    test('the first attempt: the payment goes through, nothing follows', () {
      fakeAsync((async) {
        final till = first.JoiningTill();
        final job = till.commit('entry');
        async.flushMicrotasks();
        unawaited(job.cancel());
        expect(job.isCancelled, isTrue, reason: 'join holds nothing back');
        async.flushMicrotasks();

        _end(async, 'payment');
        expect(
          stage.trace,
          ['payment start', 'payment end'],
          reason: 'join waited the payment out and threw Cancelled',
        );
        expect('${till.currentState}', 'Ready(0 s, null)');
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('a plain await on the calls: the emit between them throws', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.run<Ready, void>((ctx) async {
          final receipt = await payment.commit();
          ctx.emit(ctx.state.copyWith(receipt: receipt));
          await journal.write('entry');
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();

        _end(async, 'payment');
        expect(stage.trace, ['payment start', 'payment end']);
        expect('${bench.currentState}', 'Ready(0 s, null)');
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test(
        'emit is a checkpoint: on a cancelled job it throws and writes '
        'nothing', () {
      fakeAsync((async) {
        final bench = Bench();
        Object? thrown;
        final job = bench.run<Ready, void>((ctx) async {
          await payment.commit();
          try {
            ctx.emit(const Ready(receipt: 'receipt'));
          } on Cancelled catch (cancelled) {
            thrown = cancelled;
            rethrow;
          }
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();

        _end(async, 'payment');
        expect(thrown, isA<Cancelled>());
        expect(thrown, same(job.outcome));
        expect('${bench.currentState}', 'Ready(0 s, null)');
      });
    });

    test('the second attempt: the emit inside the join throws', () {
      fakeAsync((async) {
        final till = first.OneJoinTill();
        final job = till.commit('entry');
        async.flushMicrotasks();
        unawaited(job.cancel());
        expect(
          job.isCancelled,
          isTrue,
          reason: 'accepted the moment it arrives, not when the step is over',
        );

        _end(async, 'payment');
        expect(stage.trace, ['payment start', 'payment end']);
        expect('${till.currentState}', 'Ready(0 s, null)');
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('one section: the receipt reaches the state, the entry is written',
        () {
      fakeAsync((async) {
        final till = page.Till();
        final job = till.commit('entry');
        async.flushMicrotasks();
        unawaited(job.cancel());
        expect(job.isCancelled, isFalse, reason: 'the request is held');

        _end(async, 'payment');
        expect('${till.currentState}', 'Ready(0 s, receipt)');
        _end(async, 'journal');
        expect(stage.trace, [
          'payment start',
          'payment end',
          'journal start',
          'journal end',
        ]);
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('closing is held as well, and close() waits for the step', () {
      fakeAsync((async) {
        final till = page.Till();
        final job = till.commit('entry');
        async.flushMicrotasks();
        var closed = false;
        unawaited(till.close().then((_) => closed = true));
        async.flushMicrotasks();
        expect(job.isCancelled, isFalse);

        _end(async, 'payment');
        expect('${till.currentState}', 'Ready(0 s, receipt)');
        expect(closed, isFalse);
        _end(async, 'journal');
        expect(closed, isTrue);
        expect('${job.outcome}', 'Cancelled(closed)');
      });
    });

    test('the cancellation of a parent is held by a section of its child', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.run<Ready, void>(
          (ctx) => ctx.run(
            bench.job<Ready, void>((child) async {
              child.onCancel(() => stage.trace.add('child ctx.onCancel'));
              await child.uncancellable(
                () => stage.start<void>('step', null),
              );
            }),
          ),
        );
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        expect(job.isCancelled, isTrue);
        expect(stage.trace, ['step start']);

        _end(async, 'step');
        expect(stage.trace, ['step start', 'step end', 'child ctx.onCancel']);
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('the callbacks and the cascade wait for the end of the section', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.run<Ready, void>((ctx) async {
          ctx.onCancel(() => stage.trace.add('ctx.onCancel'));
          ctx.run(
            bench.job<Ready, void>((child) async {
              child.onCancel(() => stage.trace.add('child ctx.onCancel'));
              await child.abandonable(() => stage.start<void>('child', null));
            }),
          ).ignore();
          await ctx.uncancellable(() async {
            await stage.start<void>('payment', null);
            ctx.check();
            stage.trace.add('a checkpoint inside did not throw');
            await stage.start<void>('journal', null);
          });
          stage.trace.add('the code after the call ran');
          ctx.check();
          stage.trace.add('after the check');
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        expect(stage.trace, ['child start', 'payment start']);

        _end(async, 'payment');
        _end(async, 'journal');
        expect(stage.trace, [
          'child start',
          'payment start',
          'payment end',
          'a checkpoint inside did not throw',
          'journal start',
          'journal end',
          'child ctx.onCancel',
          'ctx.onCancel',
          'the code after the call ran',
        ]);
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('sections nest: the outermost one lets the held request through', () {
      fakeAsync((async) {
        final job = Bench().run<Ready, void>((ctx) async {
          await ctx.uncancellable(() async {
            await ctx.uncancellable(() => stage.start<void>('inner', null));
            stage.trace.add('inner closed: ${ctx.job.isCancelled}');
            await stage.start<void>('outer', null);
          });
          stage.trace.add('outer closed: ${ctx.job.isCancelled}');
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        _end(async, 'inner');
        _end(async, 'outer');

        expect(stage.trace, [
          'inner start',
          'inner end',
          'inner closed: false',
          'outer start',
          'outer end',
          'outer closed: true',
        ]);
      });
    });

    test('a section nobody awaits outlives the job and loses the request', () {
      fakeAsync((async) {
        final job = Bench().run<Ready, String>((ctx) async {
          unawaited(ctx.uncancellable(() => stage.start<void>('step', null)));
          await stage.start<void>('body', null);

          return 'done';
        });
        async.flushMicrotasks();
        var back = false;
        unawaited(job.cancel().then((_) => back = true));
        async.flushMicrotasks();

        _end(async, 'body');
        expect('${job.outcome}', 'Done(done)');
        expect(
          back,
          isTrue,
          reason: 'cancel() came back on a job that is Done',
        );
        expect(stage.isRunning('step'), isTrue);
        _end(async, 'step');
        expect('${job.outcome}', 'Done(done)');
      });
    });

    group('a whole job that is running refuses', () {
      for (final request in ['cancel()', 'cancelAll(force: true)', 'close()']) {
        test(request, () {
          fakeAsync((async) {
            final till = page.Till();
            final job = till.flush();
            async.flushMicrotasks();
            var back = false;
            final asked = switch (request) {
              'cancel()' => job.cancel(),
              'cancelAll(force: true)' => till.cancelAll(force: true),
              _ => till.close(),
            };
            unawaited(asked.then((_) => back = true));
            async.flushMicrotasks();
            expect(job.isCancelled, isFalse);
            expect(back, isFalse, reason: 'the request waits for the job');

            _end(async, 'flush');
            expect('${job.outcome}', 'Done(null)');
            expect(back, isTrue);
          });
        });
      }
    });

    group('a whole job that waits in the queue', () {
      // What each call does to the job, by name.
      void ask(page.Till till, Job<void> job, String call, {bool? force}) {
        final forced = force ?? false;
        switch (call) {
          case 'queue.remove':
            till.queue.remove(job, force: forced);
          case 'queue.removeWhere':
            till.queue.removeWhere(
              (queued) => identical(queued, job),
              force: forced,
            );
          case 'queue.clear':
            till.queue.clear(force: forced);
          case 'cancelAll()':
            unawaited(till.cancelAll(force: forced));
          default:
            unawaited(till.close());
        }
      }

      const calls = [
        'queue.remove',
        'queue.removeWhere',
        'queue.clear',
        'cancelAll()',
      ];
      for (final call in calls) {
        test('$call leaves it in place', () {
          fakeAsync((async) {
            final till = page.Till()..work('running');
            final job = till.flush();
            async.flushMicrotasks();
            ask(till, job, call);
            async.flushMicrotasks();

            expect(job.isQueued, isTrue);
            expect(job.outcome, isNull);
            if (stage.isRunning('running')) {
              _end(async, 'running');
            }
            _end(async, 'flush');
            expect('${job.outcome}', 'Done(null)');
          });
        });

        test('$call with force: true takes it out', () {
          fakeAsync((async) {
            final till = page.Till()..work('running');
            final job = till.flush();
            async.flushMicrotasks();
            ask(till, job, call, force: true);
            async.flushMicrotasks();

            expect(job.isQueued, isFalse);
            expect(_how(job), 'Cancelled(manual), started: false');
            if (stage.isRunning('running')) {
              _end(async, 'running');
            }
          });
        });
      }

      test('close() drops it from the queue too', () {
        fakeAsync((async) {
          final till = page.Till()..work('running');
          final job = till.flush();
          async.flushMicrotasks();
          ask(till, job, 'close()');
          async.flushMicrotasks();

          expect(_how(job), 'Cancelled(closed), started: false');
          _end(async, 'running');
        });
      });
    });

    test('a child created with cancellable: false refuses its parent', () {
      fakeAsync((async) {
        final bench = Bench();
        late Job<void> child;
        final job = bench.run<Ready, void>((ctx) {
          child = bench.job<Ready, void>(
            cancellable: false,
            (child) => stage.start<void>('child step', null),
          );

          return ctx.run(child);
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();
        expect(job.isCancelled, isTrue);
        expect(child.isCancelled, isFalse);

        _end(async, 'child step');
        expect('${child.outcome}', 'Done(null)');
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('the state leaving Ready cancels commit inside its section', () {
      fakeAsync((async) {
        final till = page.Till();
        final job = till.commit('entry');
        async.flushMicrotasks();
        till.reflect(const Offline());
        expect(job.isCancelled, isTrue, reason: 'the section does not hold it');

        _end(async, 'payment');
        expect(
          stage.trace,
          ['payment start', 'payment end'],
          reason: 'the next line of the section threw: no entry',
        );
        expect('${till.currentState}', 'Offline', reason: 'no receipt');
        expect('${job.outcome}', 'Cancelled(rules: is not Ready)');
      });
    });

    test('keepWhile cancels inside a section as well', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.run<Ready, void>(
          keepWhile: (state) => state.receipt == null,
          (ctx) => ctx.uncancellable(() async {
            await stage.start<void>('step', null);
            ctx.check();
            stage.trace.add('after the check');
          }),
        );
        async.flushMicrotasks();
        bench.reflect(const Ready(receipt: 'another'));
        expect(job.isCancelled, isTrue);

        _end(async, 'step');
        expect(stage.trace, ['step start', 'step end']);
        expect('${job.outcome}', 'Cancelled(rules: keepWhile)');
      });
    });

    test('the state rules cancel a job created with cancellable: false', () {
      fakeAsync((async) {
        final till = page.Till();
        final job = till.flush();
        async.flushMicrotasks();
        till.reflect(const Offline());
        expect(job.isCancelled, isTrue);

        _end(async, 'flush');
        expect('${job.outcome}', 'Cancelled(rules: is not Ready)');
      });
    });

    test('a job in the whole state type of the controller goes on', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.run<AppState, void>((ctx) async {
          await ctx.uncancellable(() async {
            final receipt = await payment.commit();
            if (ctx.state case final Ready ready) {
              ctx.emit(ready.copyWith(receipt: receipt));
            }
            await journal.write('entry');
          });
        });
        async.flushMicrotasks();
        bench.reflect(const Offline());
        expect(job.isCancelled, isFalse);

        _end(async, 'payment');
        _end(async, 'journal');
        expect(stage.trace, [
          'payment start',
          'payment end',
          'journal start',
          'journal end',
        ]);
        expect('${job.outcome}', 'Done(null)');
      });
    });
  });

  group('Ordinary await and context lifetime', () {
    test('the first attempt: close() waits for every chunk, nothing is flushed',
        () {
      late first.InvertedUploader uploader;
      late Job<void> job;
      late bool closedAfterTheThird;
      var closed = false;
      final left = _zone((async) {
        uploader = first.InvertedUploader();
        job = uploader.upload([1, 2, 3, 4]);
        async.flushMicrotasks();
        _end(async, 'write 1');
        unawaited(uploader.close().then((_) => closed = true));
        async.flushMicrotasks();
        _end(async, 'write 2');
        _end(async, 'write 3');
        closedAfterTheThird = closed;
        _end(async, 'write 4');
      });

      expect(closedAfterTheThird, isFalse);
      expect(closed, isTrue);
      expect(stage.trace, [
        'write 1 start',
        'write 1 end',
        'write 2 start',
        'write 2 end',
        'write 3 start',
        'write 3 end',
        'write 4 start',
        'write 4 end',
      ]);
      expect('${job.outcome}', 'Cancelled(closed)');
      expect(
        uploader.heard,
        [
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cleaning up after its body, cannot join'),
          ),
        ],
        reason: 'the join in the cleanup throws, and the flush never starts',
      );
      expect(
        left.errors,
        [contains('cannot join')],
        reason: 'no handler is set: the error reaches the zone',
      );
    });

    test('with Solo.errorHandler set the error goes there, not to the zone',
        () {
      final handled = <Object>[];
      late first.InvertedUploader uploader;
      final left = _zone((async) {
        Solo.errorHandler = (solo, job, error, stackTrace) {
          handled.add(error);
        };
        uploader = first.InvertedUploader()..upload([1]);
        async.flushMicrotasks();
        _end(async, 'write 1');
      });

      expect(uploader.heard, [isA<StateError>()]);
      expect(handled, [same(uploader.heard.single)]);
      expect(left.errors, isEmpty);
    });

    test('an upload that finished Done leaves the buffer unflushed as well',
        () {
      late first.InvertedUploader uploader;
      late Job<void> job;
      _zone((async) {
        uploader = first.InvertedUploader();
        job = uploader.upload([1]);
        async.flushMicrotasks();
        _end(async, 'write 1');
      });

      expect('${job.outcome}', 'Done(null)');
      expect(stage.trace, ['write 1 start', 'write 1 end']);
      expect(uploader.heard, [isA<StateError>()]);
    });

    test('each wait in its place: stops after the chunk in flight, flushes',
        () {
      fakeAsync((async) {
        final uploader = page.Uploader();
        final job = uploader.upload([1, 2, 3, 4]);
        async.flushMicrotasks();
        _end(async, 'write 1');
        var closed = false;
        unawaited(uploader.close().then((_) => closed = true));
        async.flushMicrotasks();

        _end(async, 'write 2');
        expect(closed, isFalse, reason: 'the cleanup is still flushing');
        _end(async, 'flush');
        expect(stage.trace, [
          'write 1 start',
          'write 1 end',
          'write 2 start',
          'write 2 end',
          'flush start',
          'flush end',
        ]);
        expect(closed, isTrue);
        expect('${job.outcome}', 'Cancelled(closed)');
        expect(uploader.heard, isEmpty);
      });
    });

    test('each wait in its place: an upload nobody cancels flushes too', () {
      fakeAsync((async) {
        final job = page.Uploader().upload([1, 2]);
        async.flushMicrotasks();
        _end(async, 'write 1');
        _end(async, 'write 2');
        expect(job.outcome, isNull, reason: 'the job waits for its cleanup');

        _end(async, 'flush');
        expect(stage.trace, containsAllInOrder(['write 2 end', 'flush start']));
        expect('${job.outcome}', 'Done(null)');
      });
    });

    test('a join checks before its operation as well as after it', () {
      fakeAsync((async) {
        final job = Bench().run<Ready, void>((ctx) async {
          await stage.start<void>('warm up', null);
          await ctx.join(() => stage.start<void>('write', null));
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();

        _end(async, 'warm up');
        expect(
          stage.trace,
          ['warm up start', 'warm up end'],
          reason: 'the gap after the plain await is covered by the join',
        );
        expect('${job.outcome}', 'Cancelled(manual)');
      });
    });

    test('in a disposer of a job that ended Done the body is out of reach', () {
      final bench = Bench();
      late Map<String, String> came;
      late Job<void> job;
      final left = _zone((async) {
        job = bench.run<Ready, void>((ctx) async {
          ctx.onDispose(() => came = _tryEverything(ctx, bench));
        });
        async.flushMicrotasks();
      });

      expect('${job.outcome}', 'Done(null)');
      expect(came, {
        // State reads...
        'state': 'StateError',
        'stateAs': 'StateError',
        'check': 'StateError',
        // ...and body operations are unavailable,
        'emit': 'StateError',
        'run': 'StateError',
        'each': 'StateError',
        'onCancel': 'StateError',
        // the waiting methods among them.
        'abandonable': 'StateError',
        'join': 'StateError',
        'pause': 'StateError',
        'uncancellable': 'StateError',
        // These remain available.
        'log': 'returned',
        'job': 'returned',
        'onDispose': 'returned',
        'onDiscard': 'returned',
        'disown': 'returned',
        'unattended': 'returned',
      });
      expect(left.errors, isEmpty);
    });

    test(
        'a delay written as await Future.delayed is sat out, and close() '
        'waits', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.run<Ready, void>((ctx) async {
          await Future<void>.delayed(_s(1));
        });
        async
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 500));
        var closed = false;
        unawaited(bench.close().then((_) => closed = true));
        async.flushMicrotasks();
        expect(job.outcome, isNull);
        expect(closed, isFalse);

        async.elapse(const Duration(milliseconds: 499));
        expect(closed, isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(closed, isTrue);
        expect('${job.outcome}', 'Cancelled(closed)');
      });
    });

    test(
        'ctx.pause ends the moment the cancellation is accepted, timer and '
        'all', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.run<Ready, void>((ctx) => ctx.pause(_s(1)));
        async
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 500));
        var closed = false;
        unawaited(bench.close().then((_) => closed = true));
        async.flushMicrotasks();

        expect('${job.outcome}', 'Cancelled(closed)');
        expect(closed, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('after its job has ended a context starts nothing', () {
      final bench = Bench();
      late SoloContext<AppState, Ready> kept;
      late Map<String, String> came;
      _zone((async) {
        bench.run<Ready, void>((ctx) async {
          kept = ctx;
        });
        async.flushMicrotasks();
        came = _tryEverything(kept, bench);
        async.flushMicrotasks();
      });

      final named = RegExp('Methods such as (.+?) then throw')
          .firstMatch(_prose())!
          .group(1)!;
      final members = [
        for (final member in RegExp(r'`(\w+)`').allMatches(named))
          member.group(1)!,
      ];
      expect(
        members,
        [
          'emit',
          'run',
          'each',
          'abandonable',
          'join',
          'pause',
          'uncancellable',
        ],
      );
      for (final member in members) {
        expect(came[member], 'StateError', reason: member);
      }
      expect(came['log'], 'returned');
    });

    test('reads and check remain available once the job is over', () {
      for (final failed in [false, true]) {
        final bench = Bench();
        late SoloContext<AppState, Ready> kept;
        late Map<String, String> came;
        late Job<void> job;
        _zone((async) {
          job = bench.run<Ready, void>((ctx) async {
            kept = ctx;
            if (failed) {
              throw StateError('the body failed');
            }
          })
            ..ignoreFailure();
          async.flushMicrotasks();
          came = _tryEverything(kept, bench);
          async.flushMicrotasks();
        });

        expect(job.outcome, failed ? isA<Failed>() : isA<Done<void>>());
        expect(came['state'], 'returned');
        expect(came['stateAs'], 'returned');
        expect(came['check'], 'returned');
      }
    });

    test('after a cancellation they throw that Cancelled, and log does not',
        () {
      fakeAsync((async) {
        final bench = Bench();
        late SoloContext<AppState, Ready> kept;
        final job = bench.run<Ready, void>((ctx) async {
          kept = ctx;
          await ctx.abandonable(() => stage.start<void>('call', null));
        });
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.flushMicrotasks();

        expect(job.outcome, isA<Cancelled>());
        expect(() => kept.state, throwsA(same(job.outcome)));
        expect(kept.check, throwsA(same(job.outcome)));
        expect(() => kept.log('a line'), returnsNormally);
        _end(async, 'call');
      });
    });

    test('after any other outcome they still ask the rules of the job', () {
      fakeAsync((async) {
        final bench = Bench();
        late SoloContext<AppState, Ready> kept;
        final job = bench.run<Ready, void>((ctx) async {
          kept = ctx;
        });
        async.flushMicrotasks();
        expect('${job.outcome}', 'Done(null)');

        bench.reflect(const Offline());
        Object? thrown;
        try {
          kept.check();
        } on Cancelled catch (cancelled) {
          thrown = cancelled;
        }
        expect('$thrown', 'Cancelled(rules: is not Ready)');
        expect(
          () => kept.state,
          throwsA(isA<Cancelled>()),
        );
        expect('${job.outcome}', 'Done(null)', reason: 'the outcome stays');
      });
    });
  });

  group('Cancellation details', () {
    test('a reason of your own carries its data from outside the job', () {
      late Job<void> job;
      final left = _zone((async) {
        job = Bench().work('seek');
        async.flushMicrotasks();
        unawaited(page.cancelFromOutside(job, _s(90)));
        async.flushMicrotasks();
        _end(async, 'seek');
        page.readOutcome(job);
      });

      expect(
        _reason(job),
        isA<page.OutOfRange>().having(
          (reason) => reason.position,
          'position',
          _s(90),
        ),
      );
      expect(left.printed, ['out of range at 0:01:30.000000']);
    });

    test('the reason is kept by identity', () {
      fakeAsync((async) {
        final job = Bench().work('seek');
        async.flushMicrotasks();
        final reason = page.OutOfRange(_s(90));
        unawaited(job.cancel(reason: reason));
        _end(async, 'seek');

        expect(_reason(job), same(reason));
      });
    });

    test('a reason of your own carries its data from inside the body', () {
      late Job<void> job;
      final left = _zone((async) {
        job = page.BoundedPlayer().seek(const Duration(minutes: 4));
        async.flushMicrotasks();
        page.readOutcome(job);
      });

      expect(_how(job), 'Cancelled(out of range), started: true');
      expect(left.printed, ['out of range at 0:04:00.000000']);
      expect(stage.trace, isEmpty, reason: 'the seek never reached the player');
    });

    test('a built-in reason on the way out, and a job nobody cancelled', () {
      late Job<void> queued;
      late Job<void> running;
      final left = _zone((async) {
        final bench = Bench();
        running = bench.work('running');
        queued = bench.work('queued');
        async.flushMicrotasks();
        unawaited(queued.cancel());
        async.flushMicrotasks();
        page.readOutcome(queued);
        _end(async, 'running');
        page.readOutcome(running);
      });

      expect(
        left.printed,
        ['cancelled by manual, started: false'],
        reason: 'the body never ran, and Done prints nothing',
      );
      expect('${running.outcome}', 'Done(null)');
    });

    test('Cancelled carries a description and the stack trace', () {
      fakeAsync((async) {
        final bench = Bench();
        final gaveUp = bench.run<Ready, void>(
          (ctx) async => throw const Cancelled('why'),
        );
        final asked = bench.work('work');
        async.flushMicrotasks();
        unawaited(asked.cancel());
        _end(async, 'work');

        expect((gaveUp.outcome! as Cancelled).description, 'why');
        expect((asked.outcome! as Cancelled).description, isNull);
        expect((asked.outcome! as Cancelled).stackTrace, isNotNull);
      });
    });

    test('name is a label: two reasons of one name are not equal', () {
      final one = page.OutOfRange(_s(1));
      final other = page.OutOfRange(_s(1));

      expect(one.name, other.name);
      expect(one, isNot(other));
    });

    group('the built-in reasons', () {
      test('ManualCancelReason: cancel()', () {
        fakeAsync((async) {
          final job = Bench().work('work');
          async.flushMicrotasks();
          unawaited(job.cancel());
          _end(async, 'work');

          expect(_reason(job), isA<ManualCancelReason>());
        });
      });

      test('ParentCancelReason: the child of a cancelled job, with the cause',
          () {
        fakeAsync((async) {
          final bench = Bench();
          late Job<void> child;
          final job = bench.run<Ready, void>((ctx) {
            child = bench.job<Ready, void>(
              (child) =>
                  child.abandonable(() => stage.start<void>('child', null)),
            );

            return ctx.run(child);
          });
          async.flushMicrotasks();
          unawaited(job.cancel());
          async.flushMicrotasks();

          expect(
            _reason(child),
            isA<ParentCancelReason>().having(
              (reason) => reason.cause,
              'cause',
              same(job.outcome),
            ),
          );
          _end(async, 'child');
        });
      });

      test('HandlerCancelReason: a body that throws Cancelled', () {
        fakeAsync((async) {
          final job = Bench().run<Ready, void>(
            (ctx) async => throw const Cancelled('reason'),
          );
          async.flushMicrotasks();

          expect('${job.outcome}', 'Cancelled(handler: reason)');
          expect(_reason(job), isA<HandlerCancelReason>());
        });
      });

      test(
          'HandlerCancelReason: a body that lets out the cancellation of a '
          'child, with the cause', () {
        fakeAsync((async) {
          final bench = Bench();
          late Job<void> child;
          final job = bench.run<Ready, void>((ctx) {
            child = bench.job<Ready, void>(
              (child) =>
                  child.abandonable(() => stage.start<void>('child', null)),
            );

            return ctx.run(child);
          });
          async.flushMicrotasks();
          unawaited(child.cancel());
          async.flushMicrotasks();

          expect(
            _reason(job),
            isA<HandlerCancelReason>().having(
              (reason) => reason.cause,
              'cause',
              same(child.outcome),
            ),
          );
          _end(async, 'child');
        });
      });

      test(
          'ChainCancelReason: the continuation of a cancelled job, with the '
          'cause', () {
        fakeAsync((async) {
          final job = Bench().work('source');
          final next = job.then<void>((ctx, _) {});
          async.flushMicrotasks();
          unawaited(job.cancel());
          _end(async, 'source');

          expect(
            _reason(next),
            isA<ChainCancelReason>().having(
              (reason) => reason.cause,
              'cause',
              same(job.outcome),
            ),
          );
        });
      });

      test(
          'SiblingCancelReason: a branch of a group that failed, with the '
          'cause', () {
        late Job<void> slow;
        late Job<void> group;
        final error = StateError('a branch failed');
        _zone((async) {
          final bench = Bench();
          group = bench.run<Ready, void>((ctx) {
            slow = bench.job<Ready, void>(
              (child) =>
                  child.abandonable(() => stage.start<void>('slow', null)),
            );

            return ctx.runAll([
              slow,
              bench.job<Ready, void>(
                (child) => child.join(() => stage.start<void>('quick', null)),
              ),
            ]);
          })
            ..ignoreFailure();
          async.flushMicrotasks();
          _fail(async, 'quick', error);
        });

        expect(
          _reason(slow),
          isA<SiblingCancelReason>().having(
            (reason) => reason.cause,
            'cause',
            same(error),
          ),
        );
        expect(group.outcome, isA<Failed>());
      });

      test('RulesCancelReason: the state left the working type', () {
        fakeAsync((async) {
          final bench = Bench();
          final job = bench.work('work');
          async.flushMicrotasks();
          bench.reflect(const Offline());
          _end(async, 'work');

          expect(_reason(job), isA<RulesCancelReason>());
          expect(_how(job), 'Cancelled(rules: is not Ready), started: true');
        });
      });

      test('ClosedCancelReason: close(), for the running job and the queue',
          () {
        fakeAsync((async) {
          final bench = Bench();
          final running = bench.work('running');
          final queued = bench.work('queued');
          async.flushMicrotasks();
          unawaited(bench.close());
          _end(async, 'running');

          expect(_reason(running), isA<ClosedCancelReason>());
          expect(_reason(queued), isA<ClosedCancelReason>());
        });
      });

      test('DuplicateCancelReason: a job dropped by Policy.droppable', () {
        fakeAsync((async) {
          final bench = Bench();
          final running = bench.work('load');
          final mine = bench.job<Ready, void>(key: 'load', (ctx) async {});
          final taken = bench.add(mine, policy: Policy.droppable);

          expect(taken, same(running));
          expect(_reason(mine), isA<DuplicateCancelReason>());
          async.flushMicrotasks();
          _end(async, 'load');
        });
      });

      test('ReplacedCancelReason: a job a newer one takes the place of', () {
        fakeAsync((async) {
          final bench = Bench();
          final running = bench.work('load');
          async.flushMicrotasks();
          final queued = bench.add(
            bench.job<Ready, void>(key: 'load', (ctx) async {}),
          );
          bench.add(
            bench.job<Ready, void>(key: 'load', (ctx) async {}),
            policy: Policy.restart,
          );

          expect(_reason(queued), isA<ReplacedCancelReason>());
          _end(async, 'load');
          expect(_reason(running), isA<ReplacedCancelReason>());
        });
      });

      test('are the ones the page names', () {
        final named = RegExp(r'The built-in types are (.+?)\. Inspect')
            .firstMatch(_prose())!
            .group(1)!;
        expect(
          [
            for (final type in RegExp(r'`(\w+)`').allMatches(named))
              type.group(1),
          ],
          [
            'ManualCancelReason',
            'ParentCancelReason',
            'HandlerCancelReason',
            'ChainCancelReason',
            'SiblingCancelReason',
            'RulesCancelReason',
            'ClosedCancelReason',
            'DuplicateCancelReason',
            'ReplacedCancelReason',
            'TimeoutCancelReason',
          ],
        );
      });
    });

    group('whenCancelled', () {
      test('is called inside cancel() when a running job accepts it', () {
        fakeAsync((async) {
          final heard = <Cancelled>[];
          final job = Bench().work('work')..whenCancelled(heard.add);
          async.flushMicrotasks();
          unawaited(job.cancel());

          expect(heard, hasLength(1));
          expect(job.outcome, isNull, reason: 'the job is still running');
          _end(async, 'work');
          expect(heard, [same(job.outcome)]);
        });
      });

      test('is called as the body throws Cancelled, before the job ends', () {
        fakeAsync((async) {
          final heard = <String>[];
          final bench = Bench();
          final job = bench.run<Ready, void>((ctx) async {
            ctx
                .run(
                  bench.job<Ready, void>(
                    cancellable: false,
                    (child) => stage.start<void>('child', null),
                  ),
                )
                .ignore();
            await stage.start<void>('step', null);
            throw const Cancelled('reason');
          })
            ..whenCancelled((cancelled) => heard.add('$cancelled'));
          async.flushMicrotasks();
          expect(heard, isEmpty);

          _end(async, 'step');
          expect(heard, ['Cancelled(handler: reason)']);
          expect(job.isFinished, isFalse, reason: 'its child still runs');
          _end(async, 'child');
          expect(job.outcome, isA<Cancelled>());
        });
      });

      group('is called when a job is dropped before starting', () {
        test('taken out of the queue', () {
          fakeAsync((async) {
            final heard = <String>[];
            final bench = Bench()..work('running');
            final queued = bench.work('queued')
              ..whenCancelled((cancelled) => heard.add('$cancelled'));
            async.flushMicrotasks();
            unawaited(queued.cancel());

            expect(heard, ['Cancelled(manual)']);
            _end(async, 'running');
          });
        });

        test('by close()', () {
          fakeAsync((async) {
            final heard = <String>[];
            final bench = Bench()..work('running');
            bench
                .work('queued')
                .whenCancelled((cancelled) => heard.add('$cancelled'));
            async.flushMicrotasks();
            unawaited(bench.close());

            expect(heard, ['Cancelled(closed)']);
            _end(async, 'running');
          });
        });

        test('as a duplicate', () {
          fakeAsync((async) {
            final heard = <String>[];
            final bench = Bench()..work('load');
            final mine = bench.job<Ready, void>(key: 'load', (ctx) async {})
              ..whenCancelled((cancelled) => heard.add('$cancelled'));
            bench.add(mine, policy: Policy.droppable);

            expect(heard, ['Cancelled(duplicate)']);
            async.flushMicrotasks();
            _end(async, 'load');
          });
        });

        test('by its start rule', () {
          fakeAsync((async) {
            final heard = <String>[];
            Bench()
                .run<Ready, void>(
                  canStart: (state) => state.receipt != null,
                  (ctx) async {},
                )
                .whenCancelled((cancelled) => heard.add('$cancelled'));
            expect(heard, isEmpty, reason: 'its turn has not come yet');

            async.flushMicrotasks();
            expect(heard, ['Cancelled(rules: canStart)']);
          });
        });
      });

      test(
          'registered on a job that is cancelled already, is called '
          'immediately', () {
        fakeAsync((async) {
          final heard = <String>[];
          final bench = Bench();
          final job = bench.work('work');
          async.flushMicrotasks();
          unawaited(job.cancel());
          job.whenCancelled((_) => heard.add('while it still runs'));
          expect(heard, ['while it still runs']);

          _end(async, 'work');
          job.whenCancelled((_) => heard.add('once it is over'));
          expect(heard, ['while it still runs', 'once it is over']);

          unawaited(bench.close());
          async.flushMicrotasks();
          bench.work('late').whenCancelled((_) => heard.add('on a closed one'));
          expect(heard.last, 'on a closed one');
        });
      });

      test(
          'registered while the cancellation passes to the children, is '
          'called in its turn', () {
        fakeAsync((async) {
          final heard = <String>[];
          final bench = Bench();
          final job = bench.run<Ready, void>(
            (ctx) => ctx.run(
              bench.job<Ready, void>((child) async {
                child.onCancel(
                  () => ctx.job.whenCancelled(
                    (_) => heard.add('registered in between'),
                  ),
                );
                await child.abandonable(() => stage.start<void>('child', null));
              }),
            ),
          )..whenCancelled((_) => heard.add('registered before'));
          async.flushMicrotasks();
          unawaited(job.cancel());

          expect(heard, ['registered before', 'registered in between']);
          _end(async, 'child');
        });
      });

      test('successful and failed jobs release the listeners without calling',
          () {
        late Job<void> done;
        late Job<void> failed;
        final heard = <String>[];
        _zone((async) {
          final bench = Bench();
          done = bench.work('work')..whenCancelled((_) => heard.add('done'));
          failed = bench.run<Ready, void>(
            (ctx) async => throw StateError('failed'),
          )
            ..whenCancelled((_) => heard.add('failed'))
            ..ignoreFailure();
          async.flushMicrotasks();
          _end(async, 'work');
          unawaited(done.cancel());
          done.whenCancelled((_) => heard.add('done, late'));
          failed.whenCancelled((_) => heard.add('failed, late'));
          async.flushMicrotasks();
        });

        expect('${done.outcome}', 'Done(null)');
        expect(failed.outcome, isA<Failed>());
        expect(heard, isEmpty);
      });

      test('the function it returns unregisters the listener', () {
        fakeAsync((async) {
          final heard = <String>[];
          final job = Bench().work('work');
          final unregister = job.whenCancelled((_) => heard.add('removed'));
          job.whenCancelled((_) => heard.add('kept'));
          unregister();
          async.flushMicrotasks();
          unawaited(job.cancel());

          expect(heard, ['kept']);
          _end(async, 'work');
        });
      });

      for (final handler in [false, true]) {
        final where = handler ? 'Solo.errorHandler' : 'the zone';

        test('what a listener throws goes to onError and on to $where', () {
          final handled = <Object>[];
          late Bench bench;
          late Job<void> job;
          final left = _zone((async) {
            if (handler) {
              Solo.errorHandler = (solo, job, error, stackTrace) {
                handled.add(error);
              };
            }
            bench = Bench();
            job = bench.work('work')
              ..whenCancelled((_) => throw StateError('the listener failed'))
              ..whenCancelled((_) => stage.trace.add('the next one ran'));
            async.flushMicrotasks();
            unawaited(job.cancel());
            _end(async, 'work');
          });

          expect(stage.trace, contains('the next one ran'));
          expect('${job.outcome}', 'Cancelled(manual)');
          expect(bench.heard, [isA<StateError>()]);
          expect(bench.unanswered, bench.heard);
          expect(handled, handler ? bench.heard : isEmpty);
          expect(
            left.errors,
            handler ? isEmpty : ['Bad state: the listener failed'],
          );
        });

        test(
            'what a ctx.onCancel callback throws goes to onError and on to '
            '$where', () {
          final handled = <Object>[];
          late Bench bench;
          final left = _zone((async) {
            if (handler) {
              Solo.errorHandler = (solo, job, error, stackTrace) {
                handled.add(error);
              };
            }
            bench = Bench();
            final job = bench.run<Ready, void>((ctx) async {
              ctx.onCancel(() => throw StateError('the callback failed'));
              await ctx.join(() => stage.start<void>('call', null));
            });
            async.flushMicrotasks();
            unawaited(job.cancel());
            _end(async, 'call');
          });

          expect(bench.heard, [isA<StateError>()]);
          expect(bench.unanswered, bench.heard);
          expect(handled, handler ? bench.heard : isEmpty);
          expect(
            left.errors,
            handler ? isEmpty : ['Bad state: the callback failed'],
          );
        });
      }

      test(
          'an async listener is not awaited, and its error goes straight to '
          'the zone', () {
        late Bench bench;
        final left = _zone((async) {
          bench = Bench();
          final job = bench.work('work')
            ..whenCancelled((_) async {
              await stage.start<void>('the work of the listener', null);
              throw StateError('the async listener failed');
            });
          async.flushMicrotasks();
          unawaited(job.cancel());
          _end(async, 'work');
          stage.trace.add('the job is over: ${job.isFinished}');
          _end(async, 'the work of the listener');
        });

        expect(
          stage.trace,
          containsAllInOrder([
            'the job is over: true',
            'the work of the listener end',
          ]),
        );
        expect(bench.heard, isEmpty, reason: 'past the hook');
        expect(left.errors, ['Bad state: the async listener failed']);
      });
    });
  });

  group('A deadline of a job', () {
    test(
        'a seek past its deadline stops at the token, and the player is '
        'offline', () {
      fakeAsync((async) {
        final player = page.DeadlinePlayer();
        final job = player.seek(_s(1));
        async.elapse(const Duration(milliseconds: 1999));
        expect(job.isFinished, isFalse);
        async.elapse(const Duration(milliseconds: 1));

        expect(stage.trace, [
          'seek 1 start',
          'token cancelled',
          'seek 1 stopped',
        ]);
        expect('${job.outcome}', 'Cancelled(timeout)');
        expect(
          _reason(job),
          isA<TimeoutCancelReason>()
              .having((reason) => reason.timeout, 'timeout', _s(2)),
        );
        expect('${player.currentState}', 'Offline');
        expect(player.heard, isEmpty, reason: 'onError hears no deadline');
      });
      expect(
        _prose(),
        contains(
          'The `timeout:` of `run` ends the job `Cancelled`, so `onCancel:` '
          'maps the state and `onError:` is not called.',
        ),
      );
    });

    test('Future.timeout on the call fails the job, and onError: maps', () {
      fakeAsync((async) {
        final player = _CallDeadline();
        final job = player.seek(_s(1))..ignoreFailure();
        async.elapse(_s(2));

        expect(stage.trace, ['seek 1 start']);
        expect(job.outcome, isA<Failed>());
        expect((job.outcome! as Failed).error, isA<TimeoutException>());
        expect('${player.currentState}', 'Offline');
      });
      expect(
        _prose(),
        contains(
          'A deadline that runs out is not the `TimeoutException` of '
          '`Future.timeout`. With `.timeout(...)` on the call of '
          '`_player.seek` the exception is thrown into the body, the job '
          'ends `Failed`, and it is the `onError:` of `run` that maps the '
          'state.',
        ),
      );
    });

    test('a seek dragged past leaves the state as it is', () {
      fakeAsync((async) {
        final player = page.DeadlinePlayer();
        final one = player.seek(_s(1));
        async.flushMicrotasks();
        final two = player.seek(_s(2));
        async.flushMicrotasks();

        expect('${one.outcome}', 'Cancelled(replaced)');
        expect('${player.currentState}', 'Ready(0 s, null)');
        _end(async, 'seek 2');
        expect('${two.outcome}', 'Done(null)');
        expect('${player.currentState}', 'Ready(2 s, null)');
      });
    });

    test('value throws the Cancelled, and on TimeoutException catches nothing',
        () {
      final caught = <String>[];
      fakeAsync((async) {
        final job = page.DeadlinePlayer().seek(_s(1));
        Future<void> wait() async {
          try {
            await job.value;
          } on TimeoutException {
            caught.add('TimeoutException');
          } on Cancelled catch (cancelled) {
            caught.add('$cancelled');
          }
        }

        unawaited(wait());
        async.elapse(_s(2));
      });

      expect(caught, ['Cancelled(timeout)']);
      expect(
        _prose(),
        contains(
          '`value` of such a job throws that `Cancelled`, and a clause '
          '`on TimeoutException` around it catches nothing',
        ),
      );
    });

    test('the deadline is counted from the start of the body, not the call',
        () {
      fakeAsync((async) {
        final player = page.DeadlinePlayer()..work('hold');
        final job = player.seek(_s(1));
        async.elapse(_s(5));
        expect(stage.trace, ['hold start']);
        _end(async, 'hold');
        async.elapse(const Duration(milliseconds: 1999));
        expect(job.isFinished, isFalse);
        async.elapse(const Duration(milliseconds: 1));

        expect('${job.outcome}', 'Cancelled(timeout)');
      });
      expect(
        _prose(),
        contains(
          'The deadline is counted from the start of the body, not from the '
          'call: the time a job waits in the queue does not count',
        ),
      );
    });

    test('the jobs queued behind it stay, and the next one starts', () {
      fakeAsync((async) {
        final player = page.DeadlinePlayer();
        final seek = player.seek(_s(1));
        // In the whole state type: the deadline leaves the player offline.
        final next = player.run<AppState, void>(
          (ctx) => ctx.join(() => stage.start<void>('next', null)),
        );
        async.elapse(_s(2));

        expect('${seek.outcome}', 'Cancelled(timeout)');
        expect(stage.trace, [
          'seek 1 start',
          'token cancelled',
          'seek 1 stopped',
          'next start',
        ]);
        _end(async, 'next');
        expect('${next.outcome}', 'Done(null)');
      });
      expect(
        _prose(),
        contains(
          'A deadline cancels its own job alone: the jobs queued behind it '
          'stay',
        ),
      );
    });

    test('a droppable call that finds a live job loses its own timeout', () {
      fakeAsync((async) {
        final player = page.DeadlinePlayer();
        final live = player.seek(_s(1));
        async.flushMicrotasks();
        final taken = player.run<Ready, void>(
          key: 'seek',
          policy: Policy.droppable,
          timeout: const Duration(milliseconds: 500),
          (ctx) async {},
        );

        expect(taken, same(live));
        async.elapse(const Duration(milliseconds: 1999));
        expect(live.isFinished, isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect('${live.outcome}', 'Cancelled(timeout)');
      });
      expect(
        _prose(),
        contains(
          'returns that job, and the `timeout` of the call is lost with the '
          'rest of the call',
        ),
      );
    });
  });

  group('Cancelling and closing a controller', () {
    test(
        'the first attempt: two batches never go out, the first ends '
        'Cancelled(closed)', () {
      fakeAsync((async) {
        final logs = Logs();
        first.sendThree(logs, 'first', 'second', 'third');
        // The first batch is on its way.
        async.flushMicrotasks();
        var closed = false;
        unawaited(first.closeTheScreen(logs).then((_) => closed = true));
        async.flushMicrotasks();

        expect(_how(logs.sent[1]), 'Cancelled(closed), started: false');
        expect(_how(logs.sent[2]), 'Cancelled(closed), started: false');
        expect(closed, isFalse);

        _end(async, 'send first');
        expect(closed, isTrue);
        expect(
          stage.trace,
          ['send first start', 'send first end'],
          reason: 'the first did go out',
        );
        expect(
          _how(logs.sent[0]),
          'Cancelled(closed), started: true',
          reason: 'the outcome records the cancellation, not the delivery',
        );
      });
    });

    test('run in one turn, the same lines drop the first batch as well', () {
      fakeAsync((async) {
        final logs = Logs();
        first.sendThree(logs, 'first', 'second', 'third');
        unawaited(first.closeTheScreen(logs));
        async.flushMicrotasks();

        expect(
          [for (final job in logs.sent) _how(job)],
          List.filled(3, 'Cancelled(closed), started: false'),
        );
        expect(stage.trace, isEmpty);
      });
    });

    group('cancelAll()', () {
      test('clears the queue, cancels the running job and waits for it', () {
        fakeAsync((async) {
          final logs = Logs();
          first.sendThree(logs, 'first', 'second', 'third');
          final refusing = logs.run<Ready, void>(
            cancellable: false,
            (ctx) => ctx.join(() => stage.start<void>('refusing', null)),
          );
          async.flushMicrotasks();
          var back = false;
          unawaited(page.stopByCancellingAll(logs).then((_) => back = true));
          async.flushMicrotasks();

          expect(_how(logs.sent[1]), 'Cancelled(manual), started: false');
          expect(_how(logs.sent[2]), 'Cancelled(manual), started: false');
          expect(refusing.isQueued, isTrue, reason: 'it is not cancellable');
          expect(back, isFalse);

          _end(async, 'send first');
          expect(back, isTrue);
          expect(_how(logs.sent[0]), 'Cancelled(manual), started: true');

          // The controller continues accepting work.
          expect(logs.isClosed, isFalse);
          final later = logs.send('later');
          _end(async, 'refusing');
          _end(async, 'send later');
          expect('${later.outcome}', 'Done(null)');
        });
      });

      test('the jobs it ends carry the reason passed to it', () {
        fakeAsync((async) {
          final logs = Logs();
          first.sendThree(logs, 'first', 'second', 'third');
          async.flushMicrotasks();
          final reason = page.OutOfRange(_s(5));
          unawaited(logs.cancelAll(reason: reason));
          _end(async, 'send first');

          expect(
            [for (final job in logs.sent) _reason(job)],
            everyElement(same(reason)),
          );
        });
      });

      test(
          'force takes the non-cancellable jobs out of the queue, and leaves '
          'the running one to refuse', () {
        fakeAsync((async) {
          final logs = Logs();
          Job<void> refusing(String name) => logs.run<Ready, void>(
                cancellable: false,
                (ctx) => ctx.join(() => stage.start<void>(name, null)),
              );
          final running = refusing('running');
          final queued = refusing('queued');
          async.flushMicrotasks();
          var back = false;
          unawaited(logs.cancelAll(force: true).then((_) => back = true));
          async.flushMicrotasks();

          expect(_how(queued), 'Cancelled(manual), started: false');
          expect(running.isCancelled, isFalse);
          expect(back, isFalse);
          _end(async, 'running');
          expect('${running.outcome}', 'Done(null)');
          expect(back, isTrue);
        });
      });
    });

    group('close()', () {
      test('stops accepting work and cancels every queued job', () {
        fakeAsync((async) {
          final logs = Logs()..send('first');
          final refusing = logs.run<Ready, void>(
            cancellable: false,
            (ctx) async {},
          );
          async.flushMicrotasks();
          unawaited(page.stopByClosing(logs));
          async.flushMicrotasks();

          expect(_how(refusing), 'Cancelled(closed), started: false');
          final later = logs.send('later');
          expect(
            _how(later),
            'Cancelled(closed), started: false',
            reason: 'already cancelled, and nothing was thrown',
          );
          expect(later.isQueued, isFalse);
          _end(async, 'send first');
        });
      });

      test('waits for the children and the cleanup, and pending says for what',
          () {
        fakeAsync((async) {
          final bench = Bench();
          bench.run<Ready, void>(key: 'send', (ctx) async {
            ctx
              ..onDispose(() => stage.start<void>('cleanup', null))
              ..run(
                bench.job<Ready, void>(
                  cancellable: false,
                  (child) => stage.start<void>('child', null),
                ),
              ).ignore();
            await ctx.join(() => stage.start<void>('call', null));
          });
          async.flushMicrotasks();
          var closed = false;
          unawaited(bench.close().then((_) => closed = true));
          async.flushMicrotasks();
          const cancelled = 'closing, cancelled by Cancelled(closed)';
          expect(
            '${bench.pending}',
            'SoloPending([send] in its body, $cancelled)',
          );

          _end(async, 'call');
          expect(
            '${bench.pending}',
            'SoloPending([send] waiting for 1 children, $cancelled)',
          );
          _end(async, 'child');
          expect(
            '${bench.pending}',
            'SoloPending([send] in its cleanup, $cancelled)',
          );
          expect(closed, isFalse);

          _end(async, 'cleanup');
          expect(closed, isTrue);
          expect(bench.pending, isNull);
        });
      });

      test('waits for a running job that refuses the cancellation', () {
        fakeAsync((async) {
          final logs = Logs();
          final job = logs.run<Ready, void>(
            cancellable: false,
            (ctx) => ctx.join(() => stage.start<void>('refusing', null)),
          );
          async.flushMicrotasks();
          var closed = false;
          unawaited(logs.close().then((_) => closed = true));
          async.flushMicrotasks();
          expect(closed, isFalse);
          expect(job.isCancelled, isFalse);

          _end(async, 'refusing');
          expect(closed, isTrue);
          expect('${job.outcome}', 'Done(null)');
        });
      });

      test('called again returns the same future', () {
        fakeAsync((async) {
          final logs = Logs()..send('first');
          async.flushMicrotasks();
          final closing = logs.close();

          expect(logs.close(), same(closing));
          expect(logs.close(mode: SoloCloseMode.drain), same(closing));
          _end(async, 'send first');
        });
      });

      test('publishes no state of its own, and the state it leaves is final',
          () {
        fakeAsync((async) {
          final logs = Logs();
          final states = <String>[];
          logs
            ..addListener(() => states.add('${logs.currentState}'))
            ..send('first');
          async.flushMicrotasks();
          unawaited(logs.close());
          _end(async, 'send first');

          expect(logs.isFinished, isTrue);
          expect(states, isEmpty);
          expect('${logs.currentState}', 'Ready(0 s, null)');
          expect(() => logs.reflect(const Offline()), throwsStateError);
        });
      });

      test('a state handler of the cancelled job still updates the state', () {
        fakeAsync((async) {
          final bench = Bench()
            ..run<Ready, void>(
              onCancel: (state, cancelled) => const Ready(receipt: 'corrected'),
              (ctx) => ctx.join(() => stage.start<void>('call', null)),
            );
          async.flushMicrotasks();
          unawaited(bench.close());
          async.flushMicrotasks();
          expect('${bench.currentState}', 'Ready(0 s, null)');

          _end(async, 'call');
          expect('${bench.currentState}', 'Ready(0 s, corrected)');
          expect(bench.isFinished, isTrue);
        });
      });
    });

    group('close(mode: SoloCloseMode.drain)', () {
      test('the three batches go out in order, and each ends Done', () {
        fakeAsync((async) {
          final logs = Logs();
          first.sendThree(logs, 'first', 'second', 'third');
          async.flushMicrotasks();
          var closed = false;
          unawaited(page.stopByDraining(logs).then((_) => closed = true));
          async.flushMicrotasks();
          _end(async, 'send first');
          _end(async, 'send second');
          expect(closed, isFalse);

          _end(async, 'send third');
          expect(closed, isTrue, reason: 'after the third');
          expect(stage.trace, [
            'send first start',
            'send first end',
            'send second start',
            'send second end',
            'send third start',
            'send third end',
          ]);
          expect(
            [for (final job in logs.sent) '${job.outcome}'],
            List.filled(3, 'Done(null)'),
          );
        });
      });

      test('no new root job is taken from the call onwards', () {
        fakeAsync((async) {
          final logs = Logs()..send('first');
          async.flushMicrotasks();
          unawaited(page.stopByDraining(logs));
          final later = logs.send('later');

          expect(_how(later), 'Cancelled(closed), started: false');
          _end(async, 'send first');
          expect(logs.isFinished, isTrue);
        });
      });

      test('children, cleanup and an accumulation window are waited out', () {
        fakeAsync((async) {
          final windowed = _Windowed();
          windowed.run<Ready, void>((ctx) async {
            ctx
              ..onDispose(() => stage.start<void>('cleanup', null))
              ..run(
                windowed.job<Ready, void>(
                  (child) => child.join(() => stage.start<void>('child', null)),
                ),
              ).ignore();
          });
          final line = windowed.line('a');
          windowed.line('b');
          async.flushMicrotasks();
          var closed = false;
          unawaited(
            windowed
                .close(mode: SoloCloseMode.drain)
                .then((_) => closed = true),
          );
          async.flushMicrotasks();
          _end(async, 'child');
          _end(async, 'cleanup');
          expect(closed, isFalse, reason: 'the window is still open');
          expect(line.outcome, isNull);

          async.elapse(const Duration(milliseconds: 200));
          expect(stage.trace.last, 'lines sent: a+b');
          expect(closed, isTrue);
        });
      });

      test('a drained job can still fail or be turned down by its rules', () {
        late Job<void> failing;
        late Job<void> ruled;
        late Bench bench;
        _zone((async) {
          bench = Bench()..work('running');
          failing = bench.run<Ready, void>(
            (ctx) async => throw StateError('the send failed'),
          )..ignoreFailure();
          ruled = bench.run<Ready, void>(
            canStart: (state) => state.receipt != null,
            (ctx) async {},
          );
          async.flushMicrotasks();
          unawaited(bench.close(mode: SoloCloseMode.drain));
          _end(async, 'running');
        });

        expect(failing.outcome, isA<Failed>());
        expect('${ruled.outcome}', 'Cancelled(rules: canStart)');
        expect(bench.isFinished, isTrue);
      });

      test('a plain close() over a running drain stops it', () {
        fakeAsync((async) {
          final logs = Logs();
          first.sendThree(logs, 'first', 'second', 'third');
          async.flushMicrotasks();
          var drained = false;
          unawaited(
            logs.close(mode: SoloCloseMode.drain).then((_) => drained = true),
          );
          async.flushMicrotasks();
          unawaited(logs.close());
          async.flushMicrotasks();

          expect(_how(logs.sent[1]), 'Cancelled(closed), started: false');
          expect(_how(logs.sent[2]), 'Cancelled(closed), started: false');
          expect(drained, isFalse);
          _end(async, 'send first');
          expect(
            drained,
            isTrue,
            reason: 'the future the drain returned completes after that',
          );
          expect(_how(logs.sent[0]), 'Cancelled(closed), started: true');
        });
      });
    });
  });

  group('Closing from a job', () {
    test('the first attempt never comes back', () {
      fakeAsync((async) {
        final session = first.SelfClosingSession();
        final job = session.logout();
        final behind = session.work('sync');
        async.flushMicrotasks();
        _end(async, 'logout');
        async.elapse(const Duration(hours: 1));

        expect(stage.trace, ['logout start', 'logout end']);
        expect(job.isFinished, isFalse);
        expect(
          '${session.pending}',
          'SoloPending([null] in its body, closing, '
              'cancelled by Cancelled(closed))',
          reason: 'close waits for this job, and this job waits for close',
        );
        expect(_how(behind), 'Cancelled(closed), started: false');
      });
    });

    test('cancelAll() awaited from the body waits the same way', () {
      fakeAsync((async) {
        final bench = Bench();
        final job = bench.run<Ready, void>((ctx) async {
          await ctx.join(api.logout);
          await bench.cancelAll();
        });
        async.flushMicrotasks();
        _end(async, 'logout');
        async.elapse(const Duration(hours: 1));

        expect(job.isFinished, isFalse);
        expect(job.isCancelled, isTrue);
      });
    });

    for (final call in ['close()', 'cancelAll()']) {
      test('$call awaited from the cleanup of the job waits the same way', () {
        fakeAsync((async) {
          final bench = Bench();
          final job = bench.run<Ready, void>((ctx) async {
            ctx.onDispose(call == 'close()' ? bench.close : bench.cancelAll);
            await ctx.join(api.logout);
          });
          async.flushMicrotasks();
          _end(async, 'logout');
          async.elapse(const Duration(hours: 1));

          expect(job.isFinished, isFalse);
          expect('${bench.pending}', contains('in its cleanup'));
        });
      });
    }

    test('a body that throws Cancelled ends its job the way cancel() does', () {
      fakeAsync((async) {
        final bench = Bench();
        late Job<void> child;
        final job = bench.run<Ready, void>((ctx) async {
          ctx.onCancel(() => stage.trace.add('ctx.onCancel'));
          child = bench.job<Ready, void>((child) async {
            child.onCancel(() => stage.trace.add('child ctx.onCancel'));
            await child.abandonable(() => stage.start<void>('child', null));
          });
          ctx.run(child).ignore();
          await ctx.join(api.logout);
          throw const Cancelled('reason');
        });
        async.flushMicrotasks();
        _end(async, 'logout');

        expect(stage.trace, [
          'child start',
          'logout start',
          'logout end',
          'child ctx.onCancel',
          'ctx.onCancel',
        ]);
        expect(_reason(child), isA<ParentCancelReason>());
        expect('${job.outcome}', 'Cancelled(handler: reason)');
        expect(bench.isClosed, isFalse, reason: 'no controller call was made');
        _end(async, 'child');
      });
    });

    test('the second attempt logs out and closes', () {
      fakeAsync((async) {
        final session = first.ClosingSession();
        var done = false;
        unawaited(session.logout().then((_) => done = true));
        async.flushMicrotasks();
        expect(done, isFalse);

        _end(async, 'logout');
        expect(done, isTrue);
        expect(session.isFinished, isTrue);
        expect('${session.currentState}', 'Ready(0 s, null)');
      });
    });

    test(
        'the second attempt: work submitted during the call starts, and is '
        'cancelled on the way', () {
      fakeAsync((async) {
        final session = first.ClosingSession();
        unawaited(session.logout());
        async.flushMicrotasks();
        final submitted = session.work('sync');
        expect(submitted.isQueued, isTrue, reason: 'the controller takes it');

        _end(async, 'logout');
        expect(
          stage.trace,
          ['logout start', 'logout end', 'sync start'],
          reason: 'the API hears a call nobody wanted',
        );
        expect(submitted.isCancelled, isTrue);
        _end(async, 'sync');
        expect(_how(submitted), 'Cancelled(closed), started: true');
      });
    });

    test('queue the job and drain: closes once the logout is over', () {
      fakeAsync((async) {
        final session = page.DrainingSession();
        var done = false;
        unawaited(session.logout().then((_) => done = true));
        async.flushMicrotasks();
        expect(done, isFalse);

        _end(async, 'logout');
        expect(done, isTrue);
        expect(session.isFinished, isTrue);
      });
    });

    test(
        'queue the job and drain: work submitted during the call never '
        'reaches the API', () {
      fakeAsync((async) {
        final session = page.DrainingSession();
        unawaited(session.logout());
        async.flushMicrotasks();
        final submitted = session.work('sync');

        expect(_how(submitted), 'Cancelled(closed), started: false');
        _end(async, 'logout');
        expect(stage.trace, ['logout start', 'logout end']);
      });
    });

    group('what stood in the queue before runs in either version', () {
      void check(
        FakeAsync async,
        Desk session,
        Future<void> Function() logout,
      ) {
        final earlier = session.work('sync');
        var done = false;
        unawaited(logout().then((_) => done = true));
        async.flushMicrotasks();
        _end(async, 'sync');
        expect(done, isFalse, reason: 'the method waits its turn');

        _end(async, 'logout');
        expect(done, isTrue);
        expect(stage.trace, [
          'sync start',
          'sync end',
          'logout start',
          'logout end',
        ]);
        expect('${earlier.outcome}', 'Done(null)');
      }

      test('the second attempt', () {
        fakeAsync((async) {
          final session = first.ClosingSession();
          check(async, session, session.logout);
        });
      });

      test('queue the job and drain', () {
        fakeAsync((async) {
          final session = page.DrainingSession();
          check(async, session, session.logout);
        });
      });
    });

    group('a logout that fails', () {
      test(
          'the second attempt reads done: the hook hears it, the zone does '
          'not', () {
        late first.ClosingSession session;
        var done = false;
        final left = _zone((async) {
          session = first.ClosingSession();
          unawaited(session.logout().then((_) => done = true));
          async.flushMicrotasks();
          _fail(async, 'logout', StateError('no network'));
        });

        expect(done, isTrue);
        expect(session.isFinished, isTrue, reason: 'it closes all the same');
        expect(session.heard, [isA<StateError>()]);
        expect(left.errors, isEmpty);
      });

      test('queue the job and drain: ignoreFailure() keeps it out of the zone',
          () {
        late page.DrainingSession session;
        var done = false;
        final left = _zone((async) {
          session = page.DrainingSession();
          unawaited(session.logout().then((_) => done = true));
          async.flushMicrotasks();
          _fail(async, 'logout', StateError('no network'));
        });

        expect(done, isTrue);
        expect(session.isFinished, isTrue, reason: 'it closes all the same');
        expect(session.heard, [isA<StateError>()]);
        expect(left.errors, isEmpty);
      });

      test('without ignoreFailure() it reaches the zone as an unhandled error',
          () {
        late Bench bench;
        final left = _zone((async) {
          bench = Bench()..run<Ready, void>((ctx) => ctx.join(api.logout));
          unawaited(bench.close(mode: SoloCloseMode.drain));
          async.flushMicrotasks();
          _fail(async, 'logout', StateError('no network'));
        });

        expect(bench.heard, [isA<StateError>()]);
        expect(left.errors, ['Bad state: no network']);
      });
    });
  });

  group('The page', () {
    test('four sections open with a first attempt, as the introduction says',
        () {
      expect(
        RegExp(r'^### The first attempt$', multiLine: true).allMatches(_page()),
        hasLength(4),
      );
      expect(_prose(), contains('Four sections below open with the version'));
    });

    test('one subsection opens with a first attempt of its own', () {
      expect(
        RegExp(r'^#### The first attempt$', multiLine: true)
            .allMatches(_page()),
        hasLength(1),
      );
    });

    test('three of them go on to a second attempt', () {
      expect(
        RegExp(r'^#{3,4} The second attempt$', multiLine: true)
            .allMatches(_page()),
        hasLength(3),
      );
    });

    test('names the numbers the tests use', () {
      expect(_prose(), contains('Drag through three positions'));
      expect(_prose(), contains('the second of four chunks'));
      expect(_prose(), contains('the three batches go out in order'));
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/cancellation.md'), isEmpty);
    });

    // Each version under its own file: an answer turned into its own first
    // attempt would still be found among all of them.
    const answers = 'test/support/cancellation_page.dart';
    const attempts = 'test/support/cancellation_first_attempts.dart';
    const holders = {
      '### The first attempt': attempts,
      '### The second attempt': attempts,
      '### The token': answers,
      '### One section for the step': answers,
      '### A whole job': answers,
      '### Each wait in its place': answers,
      '## Cancellation details': answers,
      '## A deadline of a job': answers,
      '### Three ways to stop': answers,
      '#### The first attempt': attempts,
      '#### The second attempt': attempts,
      '#### Queue the job and drain': answers,
    };
    for (final MapEntry(key: heading, value: holder) in holders.entries) {
      test('the code under "$heading" is a run of lines of $holder', () {
        expect(
          codeMissingFrom('doc/cancellation.md', holder, under: heading),
          isEmpty,
        );
      });
    }

    test('every piece of code on the page is a run of lines of these files',
        () {
      expect(
        codeMissingFrom('doc/cancellation.md', answers, alsoIn: [attempts]),
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

extension on Job<Object?> {
  /// The methods of the page declare `Job<T>`; whether the job still waits
  /// in the queue is on the `SoloJob<T>` the controller made.
  bool get isQueued => (this as SoloJob<Object?>).isQueued;
}
