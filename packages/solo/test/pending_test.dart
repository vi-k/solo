@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
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
      final pending = solo.pending!;
      expect(pending.phase, SoloPhase.body);
      expect(pending.job.key, 'job');
      expect(pending.cancellation, isNull);
      expect(pending.cancellationPending, isFalse);
      expect(pending.closing, isFalse);
      expect(pending.refusesCancellation, isFalse);
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
      final pending = solo.pending!;
      expect(pending.closing, isTrue);
      expect(
        pending.cancellation,
        isNull,
        reason: 'close asked and this one turned it down',
      );
      expect(pending.cancellationPending, isFalse);
      expect(pending.refusesCancellation, isTrue);
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
      final pending = solo.pending!;
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

  test('an open section nobody asked to leave is only an open section', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>(
        key: 'job',
        (ctx) => ctx.uncancellable(() => delay(100)),
      );
      async.flushMicrotasks();
      final pending = solo.pending!;
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
      final pending = solo.pending!;
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
      final pending = solo.pending!;
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
        onError: (state, error, stackTrace) {
          phases.add(solo.pending?.phase);
          return state;
        },
      ).ignore();
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
      expect(solo.pending!.phase, SoloPhase.body);
      async.flushTimers();
    });
  });

  group('a close held with nothing pending', () {
    test('a drain waits out a group still in the queue', () {
      runSolo((solo, journal, async) {
        solo
            .collect<TestState, int, void>(
              (ctx, values) async {},
              timing: AccumulationTiming.debounce(const Duration(seconds: 1)),
            )
            .add(1);
        async.flushMicrotasks();
        var returned = false;
        solo.close(mode: SoloCloseMode.drain).then((_) => returned = true);
        async.elapse(const Duration(milliseconds: 500));

        expect(returned, isFalse);
        expect(solo.pending, isNull, reason: 'no job is running');
        expect(solo.isDraining, isTrue, reason: 'the queue still holds one');

        async.elapse(const Duration(milliseconds: 500));
        expect(returned, isTrue);
      });
    });

    for (final release in ['resumed', 'cancelled']) {
      test('a paused subscription holds the stream until $release', () {
        runSoloStream((solo, journal, async) {
          final subscription = solo.stream.listen((_) {})..pause();
          var returned = false;
          solo.close().then((_) => returned = true);
          async.flushTimers();

          expect(returned, isFalse);
          expect(solo.isFinished, isTrue, reason: 'the engine has closed');
          expect(solo.pending, isNull);

          if (release == 'resumed') {
            subscription.resume();
            async.flushMicrotasks();
            expect(returned, isTrue);
          }
          unawaited(subscription.cancel());
          async.flushMicrotasks();
          expect(returned, isTrue);
        });
      });
    }
  });
}
