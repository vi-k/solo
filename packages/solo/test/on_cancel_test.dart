@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('onCancel runs when the job is cancelled', () {
    runSolo((solo, journal, async) {
      final calls = <String>[];
      solo.run<TestState, void>(key: 'job', (ctx) async {
        ctx.onCancel(() => calls.add('stop'));
        await ctx.guard(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 50));
      expect(calls, isEmpty);
      solo.current!.cancel();
      async.flushMicrotasks();
      expect(calls, ['stop']);
      expect(journal.take(), [
        '[job] started',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('onCancel runs before the body learns about the cancellation', () {
    runSolo((solo, journal, async) {
      final order = <String>[];
      solo.run<TestState, void>(key: 'job', (ctx) async {
        ctx.onCancel(() => order.add('callback'));
        try {
          await ctx.guard(() => delay(100));
        } on Cancelled {
          order.add('body');
          rethrow;
        }
      });
      async.elapse(const Duration(milliseconds: 10));
      solo.current!.cancel();
      async.flushMicrotasks();
      expect(order, ['callback', 'body']);
    });
  });

  test('onCancel runs when a rule drops the running job', () {
    runSolo((solo, journal, async) {
      final calls = <String>[];
      solo.run<NotDisposed, void>(key: 'job', (ctx) async {
        ctx.onCancel(() => calls.add('stop'));
        await ctx.guard(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 10));
      solo.externalSetState(const Disposed());
      async.flushMicrotasks();
      expect(calls, ['stop']);
      expect(journal.take(), [
        '[job] started',
        'state: Disposed()',
        '[job] finished Cancelled(rules: is not NotDisposed)',
      ]);
    });
  });

  test('onCancel runs when the controller closes', () {
    runSolo((solo, journal, async) {
      final calls = <String>[];
      solo.run<TestState, void>(key: 'job', (ctx) async {
        ctx.onCancel(() => calls.add('stop'));
        await ctx.guard(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 10));
      solo.close();
      async.flushTimers();
      expect(calls, ['stop']);
    });
  });

  test('callbacks run in registration order', () {
    runSolo((solo, journal, async) {
      final calls = <String>[];
      solo.run<TestState, void>(key: 'job', (ctx) async {
        ctx
          ..onCancel(() => calls.add('first'))
          ..onCancel(() => calls.add('second'));
        await ctx.guard(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 10));
      solo.current!.cancel();
      async.flushMicrotasks();
      expect(calls, ['first', 'second']);
    });
  });

  test('the returned function unregisters the callback', () {
    runSolo((solo, journal, async) {
      final calls = <String>[];
      solo.run<TestState, void>(key: 'job', (ctx) async {
        final remove = ctx.onCancel(() => calls.add('stop'));
        await ctx.guard(() => delay(10));
        remove();
        await ctx.guard(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.flushMicrotasks();
      expect(calls, isEmpty);
    });
  });

  test('a throwing callback goes to onError and cancels all the same', () {
    runSolo((solo, journal, async) {
      final calls = <String>[];
      solo.run<TestState, void>(key: 'job', (ctx) async {
        ctx
          ..onCancel(() => throw StateError('boom'))
          ..onCancel(() => calls.add('second'));
        await ctx.guard(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 10));
      solo.current!.cancel();
      async.flushMicrotasks();
      expect(calls, ['second']);
      expect(journal.take(), [
        '[job] started',
        '[job] error Bad state: boom',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('onCancel on an already cancelled job throws Cancelled', () {
    runSolo((solo, journal, async) {
      Object? caught;
      solo.run<TestState, void>(key: 'job', (ctx) async {
        try {
          await ctx.guard(() => delay(100));
        } on Cancelled {
          try {
            ctx.onCancel(() {});
          } on Object catch (error) {
            caught = error;
          }
          rethrow;
        }
      });
      async.elapse(const Duration(milliseconds: 10));
      solo.current!.cancel();
      async.flushMicrotasks();
      expect(caught, isA<Cancelled>());
    });
  });

  test('onCancel after the job finished throws StateError', () {
    runSolo((solo, journal, async) {
      late JobContext<TestState, TestState> escaped;
      final job = solo.run<TestState, void>(key: 'job', (ctx) async {
        escaped = ctx;
      });
      async.flushMicrotasks();
      expect(job.isFinished, isTrue);
      expect(() => escaped.onCancel(() {}), throwsStateError);
    });
  });
}
