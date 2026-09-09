@Timeout(Duration(seconds: 5))
library;

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/cancel_reason.dart';
import 'support/delay.dart';

void main() {
  test('same-named reasons keep distinct diagnostic data', () {
    final first = TestCancelReason('network', error: StateError('first'));
    final second = TestCancelReason('network', error: StateError('second'));
    final reports = <CancelReason, String>{first: 'first', second: 'second'};
    expect(reports, hasLength(2));
    expect(reports[first], 'first');
    expect(reports[second], 'second');
  });

  test('the public Cancelled constructor is a handler signal', () {
    const cancelled = Cancelled('no photo');
    expect(cancelled.reason, isA<HandlerCancelReason>());
    expect(cancelled.started, isTrue);
    expect(cancelled.description, 'no photo');
    expect(cancelled.stackTrace, isNull);
    expect(cancelled, isA<Exception>());
  });

  test('Cancelled.by carries a reason of its own', () {
    const cancelled = Cancelled.by(
      reason: TestCancelReason('rules'),
      started: true,
      description: 'is not Ready',
    );
    expect(cancelled.toString(), 'Cancelled(rules: is not Ready)');
  });

  test('toString shows the reason and the description', () {
    expect(const Cancelled().toString(), 'Cancelled(handler)');
    expect(const Done(42).toString(), 'Done(42)');
    expect(const Done<void>(null).toString(), 'Done(null)');
    expect(
      Failed(StateError('boom'), StackTrace.empty).toString(),
      'Failed(Bad state: boom)',
    );
  });

  test('a switch over Outcome<T> is exhaustive with three cases', () {
    String describe(Outcome<int> outcome) => switch (outcome) {
          Done(:final value) => 'done $value',
          Failed(:final error) => 'failed $error',
          Cancelled(:final reason) => 'cancelled $reason',
        };
    expect(describe(const Done(1)), 'done 1');
    expect(describe(const Cancelled()), 'cancelled handler');
    expect(
      describe(Failed(StateError('x'), StackTrace.empty)),
      'failed Bad state: x',
    );
  });

  test('value rethrows the error of a Failed job with its stack', () {
    fakeAsync((async) {
      final error = StateError('boom');
      final job = Job<int>((ctx) async => throw error);
      Object? caught;
      StackTrace? caughtStack;
      job.value.then<void>(
        (_) {},
        onError: (Object thrown, StackTrace stackTrace) {
          caught = thrown;
          caughtStack = stackTrace;
        },
      ).ignore();
      async.flushMicrotasks();
      expect(identical(caught, error), isTrue, reason: 'the same object');
      expect(
        caughtStack,
        same((job.outcome! as Failed).stackTrace),
        reason: 'and the same stack the outcome carries',
      );
    });
  });

  test('value throws the Cancelled of a cancelled job', () {
    fakeAsync((async) {
      final job = Job<int>((ctx) async {
        await ctx.wait(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        return 1;
      });
      Object? caught;
      job.value.then<void>(
        (_) {},
        onError: (Object thrown, StackTrace stackTrace) {
          caught = thrown;
        },
      ).ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(caught, isA<Cancelled>());
      expect(identical(caught, job.outcome), isTrue);
    });
  });
  test('value gives back what the body returned', () {
    fakeAsync((async) {
      final seen = <int>[];
      Job<int>((ctx) async {
        await ctx.wait(() => delay(10));

        return 7;
      }).value.then(seen.add).ignore();
      async.flushTimers();
      expect(seen, [7]);
    });
  });
}
