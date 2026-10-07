@Timeout(Duration(seconds: 5))
library;

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/cancel_reason.dart';
import 'support/delay.dart';
import 'support/error_observer.dart';
import 'support/probe_job.dart';

final class _BrokenLabelReason extends CancelReason {
  @override
  String get name => throw StateError('label unavailable');
}

void main() {
  for (final started in [false, true]) {
    test('custom cancellation data survives with started=$started', () {
      fakeAsync((async) {
        final error = StateError('network');
        final stack = StackTrace.current;
        final reason =
            TestCancelReason('network', error: error, stackTrace: stack);
        Cancelled? event;
        final job = Job<void>((ctx) => ctx.abandonable(() => delay(50)))
          ..whenCancelled((cancelled) => event = cancelled);
        if (started) async.flushMicrotasks();
        job.cancel(reason: reason).ignore();
        expect(event!.reason, same(reason));
        expect(event!.started, started);
        async.flushTimers();
        final outcome = job.outcome! as Cancelled;
        expect(outcome, same(event));
        switch (outcome.reason) {
          case TestCancelReason(:final error, :final stackTrace):
            expect(error, same(reason.error));
            expect(stackTrace, same(stack));
          default:
            fail('the custom reason was replaced');
        }
      });
    });
  }

  test('an uncancellable section keeps the first custom reason', () {
    fakeAsync((async) {
      final first = TestCancelReason('first', error: StateError('original'));
      const second = TestCancelReason('second');
      Cancelled? event;
      final job = Job<void>((ctx) => ctx.uncancellable(() => delay(50)))
        ..whenCancelled((cancelled) => event = cancelled);
      async.flushMicrotasks();
      job
        ..cancel(reason: first).ignore()
        ..cancel(reason: second).ignore();
      expect(event, isNull);
      async.flushTimers();
      expect(event!.reason, same(first));
      expect(job.outcome, same(event));
    });
  });

  test('a body can throw a cancellation carrying a custom reason', () {
    fakeAsync((async) {
      final reason = TestCancelReason('request', error: StateError('failed'));
      Cancelled? event;
      final job = Job<void>((ctx) async {
        throw Cancelled.by(reason: reason);
      })
        ..whenCancelled((cancelled) => event = cancelled);
      Object? valueError;
      job.value
          .then<void>(
            (_) {},
            onError: (Object error) => valueError = error,
          )
          .ignore();
      async.flushMicrotasks();
      expect(event!.reason, same(reason));
      expect(job.outcome, same(event));
      expect(valueError, same(event));
    });
  });

  test('the parent reason retains the cancellation that caused the cascade',
      () {
    fakeAsync((async) {
      final reason = TestCancelReason('network', error: StateError('failed'));
      late Job<void> child;
      final parent = Job<void>((ctx) async {
        child = Job.deferred<void>((ctx) => ctx.abandonable(() => delay(50)));
        ctx.run(child).ignore();
        await ctx.abandonable(() => delay(50));
      });
      async.flushMicrotasks();
      parent.cancel(reason: reason).ignore();
      async.flushTimers();
      final childReason =
          (child.outcome! as Cancelled).reason as ParentCancelReason;
      expect(childReason.cause, same(parent.outcome));
      expect(childReason.cause!.reason, same(reason));
    });
  });

  // `Cancelled.stackTrace` is where the cancellation came from, and for a
  // child the parent took down that is where the parent's came from.
  test('a cascade carries the stack trace of the cancel over to the child', () {
    fakeAsync((async) {
      late Job<void> child;
      final parent = Job<void>((ctx) async {
        child = Job.deferred<void>((ctx) => ctx.abandonable(() => delay(50)));
        ctx.run(child).ignore();
        await ctx.abandonable(() => delay(50));
      })
        ..ignoreFailure();
      async.flushMicrotasks();
      parent.cancel().ignore();
      async.flushTimers();
      final cause = parent.outcome! as Cancelled;
      expect(cause.stackTrace, isNotNull);
      expect((child.outcome! as Cancelled).stackTrace, same(cause.stackTrace));
    });
  });

  test('a cascade carries the stack trace of a body that gave up', () {
    fakeAsync((async) {
      late Job<void> child;
      final parent = Job<void>((ctx) async {
        child = Job.deferred<void>((ctx) => ctx.abandonable(() => delay(50)));
        ctx.run(child).ignore();
        await ctx.abandonable(() => delay(10));
        throw const Cancelled('gave up');
      })
        ..ignoreFailure();
      async.flushTimers();
      final cause = parent.outcome! as Cancelled;
      expect(cause.stackTrace, isNotNull);
      expect((child.outcome! as Cancelled).stackTrace, same(cause.stackTrace));
    });
  });

  test('a child turned away by a cancelled parent carries its stack trace', () {
    fakeAsync((async) {
      final child = Job.deferred<void>((ctx) async {});
      final parent = Job<void>((ctx) async {
        try {
          await ctx.abandonable(() => delay(50));
        } on Cancelled {
          ctx.run(child).ignore();
          rethrow;
        }
      })
        ..ignoreFailure();
      async.flushMicrotasks();
      parent.cancel().ignore();
      async.flushTimers();
      final cause = parent.outcome! as Cancelled;
      expect(cause.stackTrace, isNotNull);
      expect((child.outcome! as Cancelled).stackTrace, same(cause.stackTrace));
    });
  });

  test('a cancellation corrected to not started keeps its stack trace', () {
    fakeAsync((async) {
      final trace = StackTrace.current;
      final job = ProbeJob<void>((ctx) async {})
        ..cancelBy(
          Cancelled.by(
            reason: const TestCancelReason('engine'),
            stackTrace: trace,
          ),
        );
      async.flushMicrotasks();
      final outcome = job.outcome! as Cancelled;
      expect(outcome.started, isFalse, reason: 'the body never ran');
      expect(outcome.stackTrace, same(trace));
    });
  });

  test('a child cancellation escaping the body retains its original data', () {
    fakeAsync((async) {
      final reason = TestCancelReason('network', error: StateError('failed'));
      late Job<void> child;
      final parent = Job<void>((ctx) async {
        child = Job.deferred<void>((ctx) => ctx.abandonable(() => delay(50)));
        await ctx.run(child);
      });
      async.flushMicrotasks();
      child.cancel(reason: reason).ignore();
      async.flushTimers();
      final parentReason =
          (parent.outcome! as Cancelled).reason as HandlerCancelReason;
      expect(parentReason.cause, same(child.outcome));
      expect(parentReason.cause!.reason, same(reason));
    });
  });

  test('a custom reason named parent still reports an unattended failure', () {
    fakeAsync((async) {
      final errors = <Object>[];
      late Job<void> child;
      final parent = Job<void>(observer: ErrorObserver(errors), (ctx) async {
        child = Job.deferred<void>((ctx) => ctx.abandonable(() => delay(50)));
        ctx.run(child).ignore();
        ctx.unattended(() => child.value);
        await ctx.abandonable(() => delay(100));
      });
      async.flushMicrotasks();
      child.cancel(reason: const TestCancelReason('parent')).ignore();
      async.flushTimers();
      expect(errors, [same(child.outcome)]);
      expect(parent.outcome, isA<Done<void>>());
    });
  });
  test('a throwing label cannot prevent a parent from finishing cleanup', () {
    fakeAsync((async) {
      final errors = <Object>[];
      var disposed = false;
      late Job<void> child;
      final reason = _BrokenLabelReason();
      // Answering: the subject is the parent finishing, not where the
      // label's error goes after the observer.
      final parent =
          Job<void>(observer: ErrorObserver.answering(errors), (ctx) async {
        ctx.onDispose(() => disposed = true);
        child = Job.deferred<void>((ctx) => ctx.abandonable(() => delay(50)));
        await ctx.run(child);
      });
      async.flushMicrotasks();
      child.cancel(reason: reason).ignore();
      async.flushTimers();
      expect(parent.isFinished, isTrue);
      expect(disposed, isTrue);
      final parentReason =
          (parent.outcome! as Cancelled).reason as HandlerCancelReason;
      expect(parentReason.cause!.reason, same(reason));
      expect(errors, [isA<StateError>()]);
    });
  });

  test('a public parent reason is not proof of cancellation by the parent', () {
    fakeAsync((async) {
      final errors = <Object>[];
      late Job<void> child;
      final parent = Job<void>(observer: ErrorObserver(errors), (ctx) async {
        child = Job.deferred<void>((ctx) async {
          throw const Cancelled.by(
            reason: ParentCancelReason(),
          );
        });
        ctx.run(child).ignore();
        ctx.unattended(() => child.value);
        await ctx.abandonable(() => delay(50));
      });
      async.flushTimers();
      expect(errors, [same(child.outcome)]);
      expect(parent.outcome, isA<Done<void>>());
    });
  });
}
