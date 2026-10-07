@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

void main() {
  test('an idle controller holds nothing', () {
    runSolo((solo, journal, async) {
      expect(solo.pending, isNull);
    });
  });

  test('a running body says so, and nobody has asked it to stop', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) => pause(ctx, 100));
      async.flushMicrotasks();
      final pending = solo.pending! as SoloPendingJob;
      expect(pending.phase, SoloPhase.body);
      expect(pending.job.key, 'job');
      expect(pending.cancellation, isNull);
      expect(pending.cancellationPending, isFalse);
      expect(pending.closing, isFalse);
      expect(pending.cancellable, isTrue);
      expect('$pending', 'SoloPending([job] in its body)');
      async.flushTimers();
    });
  });

  test('a job that turns cancellation down is nothing pending', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(
        key: 'job',
        cancellable: false,
        (ctx) => pause(ctx, 100),
      );
      async.flushMicrotasks();
      solo.close();
      final pending = solo.pending! as SoloPendingJob;
      expect(pending.closing, isTrue);
      expect(
        pending.cancellation,
        isNull,
        reason: 'close asked and this one turned it down',
      );
      expect(pending.cancellationPending, isFalse);
      expect(pending.cancellable, isFalse);
      expect(
        '$pending',
        'SoloPending([job] in its body, closing, '
            'created cancellable: false)',
      );
      async.flushTimers();
    });
  });

  test('a held cancellation is named without being a guess', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(
        key: 'job',
        (ctx) => ctx.uncancellable(() => delay(100)),
      );
      async.flushMicrotasks();
      solo.cancelAll();
      final pending = solo.pending! as SoloPendingJob;
      expect(pending.inUncancellableSection, isTrue);
      expect(
        pending.cancellation,
        isNull,
        reason: 'the job is not marked while the section holds it',
      );
      expect(pending.heldCancellation, isA<Cancelled>());
      expect(pending.cancellationPending, isTrue);
      expect(
        '$pending',
        'SoloPending([job] in its body, holding Cancelled(manual) back)',
      );
      async.flushTimers();
    });
  });

  test('a rule drops the cancellation a section holds', () {
    runSolo((solo, journal, async) {
      final job = solo.run<Initial, void>(
        key: 'job',
        (ctx) => ctx.uncancellable(() => delay(100)),
      );
      async.flushMicrotasks();
      solo.cancelAll();
      expect(
        (solo.pending! as SoloPendingJob).heldCancellation,
        isA<Cancelled>(),
      );
      solo.externalSetState(const Working(a: 1));
      final pending = solo.pending! as SoloPendingJob;
      expect(
        pending.heldCancellation,
        isNull,
        reason: 'the rule is accepted over it, and it will never land',
      );
      expect(pending.cancellation?.reason, isA<RulesCancelReason>());
      expect('$pending', contains('in its body'));
      async.flushTimers();
      expect((job.outcome! as Cancelled).reason, isA<RulesCancelReason>());
    });
  });

  test('an open section nobody asked to leave is only an open section', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(
        key: 'job',
        (ctx) => ctx.uncancellable(() => delay(100)),
      );
      async.flushMicrotasks();
      final pending = solo.pending! as SoloPendingJob;
      expect(pending.inUncancellableSection, isTrue);
      expect(pending.heldCancellation, isNull);
      expect(
        pending.cancellationPending,
        isFalse,
        reason: 'neither close nor cancel was called',
      );
      expect(
        '$pending',
        'SoloPending([job] in its body, in an uncancellable section)',
      );
      async.flushTimers();
    });
  });

  test('a body that ended with children waiting says how many', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        ctx
          ..each<int>(
            Stream<int>.periodic(const Duration(milliseconds: 20), (i) => i),
            (childCtx, event) async {},
          )
          ..each<int>(
            Stream<int>.periodic(const Duration(milliseconds: 30), (i) => i),
            (childCtx, event) async {},
          );
      });
      async.elapse(const Duration(milliseconds: 10));
      final pending = solo.pending! as SoloPendingJob;
      expect(pending.phase, SoloPhase.children);
      expect(pending.children, 2);
      expect('$pending', 'SoloPending([job] waiting for 2 children)');
      solo.cancelAll();
      async.flushTimers();
    });
  });

  test('a cleanup that takes its time is named', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        ctx.onDispose(() => delay(100));
      });
      async.flushMicrotasks();
      final pending = solo.pending! as SoloPendingJob;
      expect(pending.phase, SoloPhase.cleanup);
      expect('$pending', 'SoloPending([job] in its cleanup)');
      async.flushTimers();
    });
  });

  test('a job past its body and children reads as its cleanup', () {
    runSolo((solo, journal, async) {
      final phases = <SoloPhase?>[];
      solo.run<TestState, void>(
        key: 'job',
        (ctx) async => throw StateError('gone'),
        ifFailed: (state, error, stackTrace) {
          phases.add((solo.pending as SoloPendingJob?)?.phase);
          return state;
        },
      ).ignoreFailure();
      async.flushTimers();
      expect(phases, [SoloPhase.cleanup]);
    });
  });

  test('a body on a bare await is in its body, and no more is said', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(key: 'job', (ctx) async {
        // A bare await, past every checkpoint: the engine knows the body
        // is still out and nothing about what holds it.
        await delay(100);
      });
      async.flushMicrotasks();
      expect((solo.pending! as SoloPendingJob).phase, SoloPhase.body);
      async.flushTimers();
    });
  });

  group('a close held without a job names what holds it', () {
    test('a drain waits out a group still in the queue', () {
      runSolo((solo, journal, async) {
        solo
            .collect<TestState, int, void>(
              key: 'group',
              (ctx, values) async {},
              timing: AccumulationTiming.debounce(const Duration(seconds: 1)),
            )
            .add(1);
        async.flushMicrotasks();
        var returned = false;
        solo.close(mode: SoloCloseMode.drain).then((_) => returned = true);
        async.elapse(const Duration(milliseconds: 500));

        expect(returned, isFalse);
        final pending = solo.pending! as SoloPendingQueue;
        expect([for (final job in pending.jobs) job.key], ['group']);
        expect('$pending', 'SoloPending(draining, 1 queued: [group])');

        async.elapse(const Duration(milliseconds: 500));
        expect(returned, isTrue);
        expect(solo.pending, isNull);
      });
    });

    test('read at once, a drain names the ready job with the group', () {
      runSolo((solo, journal, async) {
        final gate = Completer<void>();
        solo.run<TestState, void>(
          key: 'ready',
          describe: () => 'gate',
          (ctx) => ctx.abandonable(() => gate.future),
        );
        solo
            .collect<TestState, int, void>(
              key: 'group',
              (ctx, values) async {},
              timing: AccumulationTiming.debounce(const Duration(seconds: 1)),
            )
            .add(1);
        solo.close(mode: SoloCloseMode.drain);
        // Synchronously: the engine has not come to the queue yet, so the
        // ready job is still in it. A microtask later it is running.
        final queued = solo.pending! as SoloPendingQueue;
        expect([for (final job in queued.jobs) job.key], ['ready', 'group']);
        expect(
          '$queued',
          'SoloPending(draining, 2 queued: [ready: gate], [group])',
        );

        async.flushMicrotasks();
        final running = solo.pending! as SoloPendingJob;
        expect(running.job.key, 'ready');
        expect(running.closing, isTrue);
        expect(running.draining, isTrue);
        expect('$running', 'SoloPending([ready: gate] in its body, draining)');

        gate.complete();
        async.flushMicrotasks();
        final left = solo.pending! as SoloPendingQueue;
        expect([for (final job in left.jobs) job.key], ['group']);
      });
    });

    test('a rule that drains the controller finds its own job first', () {
      runSolo((solo, journal, async) {
        final seen = <String>[];
        solo.run<TestState, void>(
          key: 'ruled',
          canStart: (state) {
            solo.close(mode: SoloCloseMode.drain);
            seen.add('${solo.pending}');
            return true;
          },
          (ctx) async {},
        );
        solo.run<TestState, void>(key: 'behind', (ctx) async {});
        async.flushMicrotasks();

        expect(seen, ['SoloPending(draining, 2 queued: [ruled], [behind])']);
      });
    });

    test('a snapshot keeps the queue it was taken with', () {
      runSolo((solo, journal, async) {
        solo
            .collect<TestState, int, void>(
              key: 'group',
              (ctx, values) async {},
              timing: AccumulationTiming.debounce(const Duration(seconds: 1)),
            )
            .add(1);
        solo.close(mode: SoloCloseMode.drain);
        async.flushMicrotasks();
        final snapshot = solo.pending! as SoloPendingQueue;

        // A plain close over the drain drops the queue at once.
        solo.close();
        expect(solo.pending, isNull);
        expect([for (final job in snapshot.jobs) job.key], ['group']);
        expect(snapshot.jobs.clear, throwsUnsupportedError);
      });
    });

    test('a group waiting for its window holds nothing without a close', () {
      runSolo((solo, journal, async) {
        solo
            .collect<TestState, int, void>(
              key: 'group',
              (ctx, values) async {},
              timing: AccumulationTiming.debounce(const Duration(seconds: 1)),
            )
            .add(1);
        async.flushMicrotasks();
        expect(solo.pending, isNull, reason: 'the controller is idle');
      });
    });

    test('a drain of nothing holds nothing, read at once or at the end', () {
      fakeAsync((async) {
        final idle = _Hooked();
        var returned = false;
        idle.close(mode: SoloCloseMode.drain).then((_) => returned = true);
        expect(idle.pending, isNull);
        expect(returned, isFalse);
        async.flushMicrotasks();
        expect(returned, isTrue);

        final last = _Hooked();
        final seen = <String>[];
        var lastReturned = false;
        // Recorded and checked outside: an `expect` failing inside a hook
        // would go to the zone and not fail the test.
        last.finished = (job) => seen.add('${last.pending} $lastReturned');
        last.run<TestState, void>(key: 'last', (ctx) async {});
        last.close(mode: SoloCloseMode.drain).then((_) => lastReturned = true);
        async.flushMicrotasks();
        expect(
          seen,
          ['null false'],
          reason: 'the close is still held, and nothing is left to name',
        );
        expect(lastReturned, isTrue);
      });
    });

    test('a job its rule has ended is no longer queued work', () {
      fakeAsync((async) {
        final rejected = _Hooked();
        final seen = <String>[];
        rejected.finished = (job) => seen.add('${rejected.pending}');
        rejected
            .run<TestState, void>(
              key: 'rejected',
              canStart: (state) => false,
              (ctx) async {},
            )
            .ignoreFailure();
        rejected.close(mode: SoloCloseMode.drain);
        async.flushMicrotasks();

        final cancelled = _Hooked();
        late final SoloJob<void> self;
        self = cancelled.run<TestState, void>(
          key: 'self',
          canStart: (state) {
            self.cancel();
            cancelled.close(mode: SoloCloseMode.drain);
            seen.add('${cancelled.pending}');
            return true;
          },
          (ctx) async {},
        )..ignoreFailure();
        async.flushMicrotasks();

        expect(
          seen,
          ['null', 'null'],
          reason: 'the rule ended the job: the drain has nothing left to run',
        );
      });
    });

    for (final release in ['resumed', 'cancelled']) {
      test('a paused subscription holds the stream until $release', () {
        runSoloStream((solo, journal, async) {
          final subscription = solo.stream.listen((_) {})..pause();
          var returned = false;
          solo.close().then((_) => returned = true);
          expect(
            solo.pending,
            isNull,
            reason: 'the engine has not closed yet, and it holds nothing',
          );
          async.flushTimers();

          expect(returned, isFalse);
          expect(solo.isFinished, isTrue, reason: 'the engine has closed');
          expect(solo.pending, isA<SoloPendingStream>());
          expect(
            '${solo.pending}',
            'SoloPending(stream: a subscription has not taken its done event)',
          );

          if (release == 'resumed') {
            subscription.resume();
            async.flushMicrotasks();
            expect(returned, isTrue);
          }
          unawaited(subscription.cancel());
          async.flushMicrotasks();
          expect(returned, isTrue);
          expect(solo.pending, isNull);
        });
      });
    }

    test('a drain names its queue, then the stream, then nothing', () {
      runSoloStream((solo, journal, async) {
        final subscription = solo.stream.listen((_) {})..pause();
        solo
            .collect<TestState, int, void>(
              key: 'group',
              (ctx, values) async {},
              timing: AccumulationTiming.debounce(const Duration(seconds: 1)),
            )
            .add(1);
        var returned = false;
        solo.close(mode: SoloCloseMode.drain).then((_) => returned = true);
        final seen = <String>[];
        async.flushMicrotasks();
        seen.add('${solo.pending.runtimeType}');
        async.elapse(const Duration(seconds: 1));
        seen.add('${solo.pending.runtimeType}');
        unawaited(subscription.cancel());
        async.flushMicrotasks();
        seen.add('${solo.pending}');

        expect(seen, ['SoloPendingQueue', 'SoloPendingStream', 'null']);
        expect(returned, isTrue);
      });
    });
  });
}

final class _Hooked extends Solo<TestState> with OpenSolo<TestState> {
  _Hooked() : super(const Initial());

  void Function(Job<Object?> job)? finished;

  @override
  void onFinish(Job<Object?> job) => finished?.call(job);
}
