@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

void main() {
  test('cancel is idempotent', () {
    fakeAsync((async) {
      final job = Job<void>((ctx) => ctx.wait(() => delay(50)));
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      final first = job.outcome;
      job.cancel().ignore();
      async.flushTimers();
      expect(first, isNull, reason: 'the body is still unwinding');
      expect(job.outcome, isA<Cancelled>());
      expect((job.outcome! as Cancelled).reason, CancelReason.manual);
    });
  });

  test('cancel of a finished job does nothing', () {
    fakeAsync((async) {
      final job = Job<int>((ctx) async => 42);
      async.flushMicrotasks();
      expect(job.outcome, isA<Done<int>>());
      job.cancel().ignore();
      async.flushMicrotasks();
      expect(job.outcome, isA<Done<int>>());
      expect(job.isCancelled, isFalse);
    });
  });

  test('a job that is not cancellable refuses cancel and finishes', () {
    fakeAsync((async) {
      var settled = false;
      final job = Job<void>(
        cancellable: false,
        (ctx) => ctx.wait(() => delay(50)),
      );
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().then((_) => settled = true).ignore();
      async.elapse(const Duration(milliseconds: 10));
      expect(job.isCancelled, isFalse);
      expect(settled, isFalse, reason: 'the future still waits for the job');
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
      expect(settled, isTrue);
    });
  });

  test('uncancellable refuses the cancellation for one step', () {
    fakeAsync((async) {
      var reached = false;
      final job = Job<void>((ctx) async {
        await ctx.uncancellable(() => delay(50));
        reached = true;
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(reached, isTrue, reason: 'a refusal is final, not deferred');
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('uncancellable restores the answer that was in force', () {
    fakeAsync((async) {
      var reached = false;
      final job = Job<void>(
        cancellable: false,
        (ctx) async {
          await ctx.uncancellable(() => delay(10));
          await ctx.wait(() => delay(50));
          reached = true;
        },
      );
      async.elapse(const Duration(milliseconds: 20));
      job.cancel().ignore();
      async.flushTimers();
      expect(
        reached,
        isTrue,
        reason: 'the job was uncancellable before the section, and after it',
      );
    });
  });

  test('whenCancelled completes before the job does', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) => ctx.wait(() => delay(50)));
      job.whenCancelled.then((_) => order.add('cancelled')).ignore();
      job.done.then((_) => order.add('done')).ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['cancelled', 'done']);
    });
  });

  test('whenCancelled of a job dropped before start completes too', () {
    fakeAsync((async) {
      var completed = false;
      final job = Job<void>((ctx) async {})..cancel().ignore();
      job.whenCancelled.then((_) => completed = true).ignore();
      async.flushMicrotasks();
      expect(completed, isTrue);
      expect((job.outcome! as Cancelled).started, isFalse);
    });
  });

  test('a body that throws Cancelled ends as handler', () {
    fakeAsync((async) {
      final job = Job<void>((ctx) async => throw const Cancelled('no photo'));
      async.flushMicrotasks();
      final outcome = job.outcome! as Cancelled;
      expect(outcome.reason, CancelReason.handler);
      expect(outcome.description, 'no photo');
      expect(outcome.started, isTrue);
    });
  });

  test('the cancellation of a parent reaches a child', () {
    fakeAsync((async) {
      late final Job<void> child;
      final parent = Job<void>((ctx) async {
        child = ctx.run(
          Job.deferred<void>((ctx) => ctx.wait(() => delay(100))),
        );
        await child.done;
      });
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      async.flushTimers();
      expect((child.outcome! as Cancelled).reason, CancelReason.parent);
      expect(parent.outcome, isA<Cancelled>());
    });
  });

  test('the future of cancel completes after the job', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) => ctx.wait(() => delay(50)));
      job.done.then((_) => order.add('done')).ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().then((_) => order.add('cancel')).ignore();
      async.flushTimers();
      expect(order, ['done', 'cancel']);
    });
  });

  test('a cancellation between the return and the outcome still wins', () {
    fakeAsync((async) {
      // No children: the only gap between the body's return and `finish`
      // is the microtask of waiting for a list that is empty.
      late final Job<int> job;
      var returned = false;
      job = Job<int>((ctx) async {
        await ctx.wait(() => delay(10));
        returned = true;
        // The cancellation lands in the same synchronous stripe as the
        // return, after the body is past its last checkpoint.
        job.cancel().ignore();
        return 42;
      });
      async.flushTimers();
      expect(returned, isTrue);
      expect(job.outcome, isA<Cancelled>());
      expect(
        (job.outcome! as Cancelled).reason,
        CancelReason.manual,
        reason: 'the outcome is not rewritten by a value already computed',
      );
    });
  });

  test('uncancellable restores the answer even when the action throws', () {
    fakeAsync((async) {
      var reached = false;
      final job = Job<void>((ctx) async {
        try {
          await ctx.uncancellable(() async {
            await delay(10);
            throw const FormatException('inside');
          });
        } on FormatException {
          // Caught: the section is over, and the job is cancellable again.
        }
        await ctx.wait(() => delay(50));
        reached = true;
      });
      async.elapse(const Duration(milliseconds: 20));
      job.cancel().ignore();
      async.flushTimers();
      expect(reached, isFalse, reason: 'the section did not leave it off');
      expect(job.outcome, isA<Cancelled>());
    });
  });
}
