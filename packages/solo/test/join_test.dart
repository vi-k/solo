@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('join waits for the action after the job is cancelled', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.join(() => delay(100));
        ctx.emit(const Preparing());
      });
      async.elapse(const Duration(milliseconds: 50));
      job.cancel();
      async.flushMicrotasks();
      expect(job.outcome, isNull, reason: 'the action is still in flight');
      async.elapse(const Duration(milliseconds: 50));
      expect(job.outcome, isA<Cancelled>());
      expect(async.elapsed, const Duration(milliseconds: 100));
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('join returns the value when nothing cancels', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, int>(key: 'job', (ctx) async {
        final value = await ctx.join(() async {
          await delay(50);
          return 7;
        });
        ctx.emit(const Preparing());
        return value;
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>().having((o) => o.value, 'value', 7));
      expect(journal.take(), [
        '[job] started',
        'state: Preparing(progress: 0)',
        '[job] finished Done(7)',
      ]);
    });
  });

  test('join gives up when a rule stopped holding meanwhile', () {
    runSolo((solo, journal, async) {
      solo.run<NotDisposed, void>(key: 'job', (ctx) async {
        await ctx.join(() => delay(100));
        ctx.emit(const Preparing());
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Disposed());
      async.elapse(const Duration(milliseconds: 50));
      expect(async.elapsed, const Duration(milliseconds: 100));
      expect(journal.take(), [
        '[job] started',
        'state: Disposed()',
        '[job] finished Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('close waits for a joined action and the job ends cancelled', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.join(() => delay(100));
        ctx.emit(const Preparing());
      });
      async.elapse(const Duration(milliseconds: 50));
      var closed = false;
      solo.close().then((_) => closed = true);
      async.flushMicrotasks();
      expect(closed, isFalse, reason: 'close waits for the body');
      expect(job.outcome, isNull);
      async.elapse(const Duration(milliseconds: 50));
      expect(closed, isTrue);
      expect(job.outcome, isA<Cancelled>());
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('an already cancelled job does not begin the action', () {
    runSolo((solo, journal, async) {
      var began = false;
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await delay(100);
        await ctx.join(() async => began = true);
      });
      async.elapse(const Duration(milliseconds: 50));
      job.cancel();
      async.flushTimers();
      expect(began, isFalse, reason: 'the call is not started at all');
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('an error from the action reaches the body as it is', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        try {
          await ctx.join(() async {
            await delay(50);
            throw const FormatException('the device said no');
          });
        } on FormatException {
          // The call failed; the job carries on and reports it itself.
          ctx.emit(const Preparing());
        }
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
      expect(journal.take(), [
        '[job] started',
        'state: Preparing(progress: 0)',
        '[job] finished Done(null)',
      ]);
    });
  });

  test('ifCancelled takes the value when the job is cancelled meanwhile', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.join(
          () async {
            await delay(100);
            return 7;
          },
          ifCancelled: (value) async {
            await delay(10);
            ctx.log('disposed $value');
          },
        );
        ctx.emit(const Preparing());
      });
      async.elapse(const Duration(milliseconds: 50));
      job.cancel();
      async.elapse(const Duration(milliseconds: 50));
      expect(job.outcome, isNull, reason: 'the value is being disposed of');
      async.elapse(const Duration(milliseconds: 10));
      expect(job.outcome, isA<Cancelled>());
      expect(async.elapsed, const Duration(milliseconds: 110));
      expect(journal.take(), [
        '[job] started',
        '[job] log disposed 7',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('ifCancelled takes the value when a rule stopped holding', () {
    runSolo((solo, journal, async) {
      solo.run<NotDisposed, void>(key: 'job', (ctx) async {
        await ctx.join(
          () async {
            await delay(100);
            return 7;
          },
          ifCancelled: (value) => ctx.log('disposed $value'),
        );
        ctx.emit(const Preparing());
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Disposed());
      async.flushTimers();
      expect(journal.take(), [
        '[job] started',
        'state: Disposed()',
        '[job] log disposed 7',
        '[job] finished Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('ifCancelled is not called when the action comes back in time', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, int>(key: 'job', (ctx) async {
        final value = await ctx.join(
          () async {
            await delay(50);
            return 7;
          },
          ifCancelled: (value) => ctx.log('disposed $value'),
        );
        return value;
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>().having((o) => o.value, 'value', 7));
      expect(journal.take(), [
        '[job] started',
        '[job] finished Done(7)',
      ]);
    });
  });

  test('close waits for ifCancelled before the job ends', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.join(
          () async {
            await delay(100);
            return 7;
          },
          ifCancelled: (value) async {
            await delay(10);
            ctx.log('disposed $value');
          },
        );
      });
      async.elapse(const Duration(milliseconds: 50));
      var closed = false;
      solo.close().then((_) => closed = true);
      async.elapse(const Duration(milliseconds: 50));
      expect(closed, isFalse, reason: 'close waits for the disposal');
      expect(job.outcome, isNull);
      async.elapse(const Duration(milliseconds: 10));
      expect(closed, isTrue);
      expect(journal.take(), [
        '[job] started',
        '[job] log disposed 7',
        '[job] finished Cancelled(closed)',
        'closed',
      ]);
    });
  });

  test('an error from ifCancelled goes to onError', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.join(
          () async {
            await delay(100);
            return 7;
          },
          ifCancelled: (value) => throw StateError('cannot dispose $value'),
        );
      });
      async.elapse(const Duration(milliseconds: 50));
      job.cancel();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(journal.take(), [
        '[job] started',
        '[job] error Bad state: cannot dispose 7',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('ifCancelled is not called when the action fails', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        await ctx.join<int>(
          () async {
            await delay(100);
            throw const FormatException('the device said no');
          },
          ifCancelled: (value) => ctx.log('disposed $value'),
        );
      });
      async.elapse(const Duration(milliseconds: 50));
      job.cancel();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(journal.take(), [
        '[job] started',
        '[job] error FormatException: the device said no',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });
}
