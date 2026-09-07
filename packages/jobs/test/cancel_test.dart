@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

/// Whether the job behind [ctx] is already marked cancelled.
bool _isMarked(JobContext ctx) => ctx.job.isCancelled;

/// Runs [action] [depth] microtasks from now.
void _afterMicrotasks(int depth, void Function() action) {
  if (depth <= 0) {
    action();
    return;
  }
  scheduleMicrotask(() => _afterMicrotasks(depth - 1, action));
}

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

  test('uncancellable holds the cancellation until the step is over', () {
    fakeAsync((async) {
      var stepEnded = false;
      var afterWait = false;
      final job = Job<void>((ctx) async {
        await ctx.uncancellable(() => delay(50));
        stepEnded = true;
        await ctx.wait(() => delay(10));
        afterWait = true;
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(stepEnded, isTrue, reason: 'the step ran to its end');
      expect(
        afterWait,
        isFalse,
        reason: 'the held cancellation lands at the next context call',
      );
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('nothing is marked while an uncancellable step runs', () {
    fakeAsync((async) {
      var callbackFired = false;
      late Job<void> job;
      late Job<void> child;
      var seenInsideStep = true;
      job = Job<void>((ctx) async {
        ctx.onCancel(() => callbackFired = true);
        child = ctx.run(
          Job.deferred<void>((childCtx) => childCtx.wait(() => delay(200))),
        );
        await ctx.uncancellable(() async {
          await delay(50);
          seenInsideStep = job.isCancelled;
        });
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.elapse(const Duration(milliseconds: 20));
      expect(job.isCancelled, isFalse, reason: 'the step is still running');
      expect(callbackFired, isFalse, reason: 'onCancel would stop the step');
      expect(child.outcome, isNull, reason: 'the cascade waits too');
      async.flushTimers();
      expect(seenInsideStep, isFalse);
      expect(callbackFired, isTrue, reason: 'the mark lands after the step');
      expect(job.outcome, isA<Cancelled>());
      expect(child.outcome, isA<Cancelled>());
    });
  });

  test('only the outermost uncancellable section lets it through', () {
    fakeAsync((async) {
      var innerEnded = false;
      var afterOuter = false;
      final job = Job<void>((ctx) async {
        await ctx.uncancellable(() async {
          await ctx.uncancellable(() => delay(30));
          innerEnded = true;
          expect(_isMarked(ctx), isFalse);
          await delay(30);
        });
        afterOuter = true;
        ctx.check();
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(innerEnded, isTrue);
      expect(afterOuter, isTrue, reason: 'check() is the first checkpoint');
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('a held cancellation lands even if the step throws', () {
    fakeAsync((async) {
      var caught = false;
      final job = Job<void>((ctx) async {
        try {
          await ctx.uncancellable(() async {
            await delay(50);
            throw const FormatException('declined');
          });
        } on FormatException {
          caught = true;
        }
        await ctx.wait(() => delay(10));
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(caught, isTrue);
      expect(job.outcome, isA<Cancelled>());
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

  test('a cancellation after the return still wins the outcome', () {
    // Without children the window is one microtask wide: the body has
    // returned, and the engine is waiting for a list of children that is
    // empty. Walking the depths pins that width instead of assuming it —
    // a kernel that read the mark before waiting for the children would
    // hand back Done at depth 1.
    final outcomes = <int, Outcome<int>>{};
    for (var depth = 0; depth <= 3; depth++) {
      fakeAsync((async) {
        late final Job<int> job;
        job = Job<int>((ctx) async {
          await ctx.wait(() => delay(10));
          _afterMicrotasks(depth, () => job.cancel().ignore());
          return 42;
        });
        async.flushTimers();
        outcomes[depth] = job.outcome!;
      });
    }
    expect(outcomes[0], isA<Cancelled>());
    expect(
      outcomes[1],
      isA<Cancelled>(),
      reason: 'the body had returned, and the cancellation still won',
    );
    expect(outcomes[2], isA<Done<int>>(), reason: 'the job was over by then');
    expect(outcomes[3], isA<Done<int>>());
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
  test('a cancel callback of a child that cancels the parent is not an error',
      () {
    fakeAsync((async) {
      // The cascade runs the callbacks of the children before the parent is
      // marked, so a callback that comes back for the parent used to find a
      // job that still looks uncancelled and mark it a second time.
      Object? thrown;
      late Job<void> parent;
      parent = Job<void>((ctx) async {
        ctx.run(
          Job.deferred<void>(key: 'child', (child) async {
            child.onCancel(() => parent.cancel().ignore());
            await child.wait(() => delay(100));
          }),
        );
        await ctx.wait(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 10));
      try {
        parent.cancel().ignore();
      } on Object catch (error) {
        thrown = error;
      }
      async.elapse(const Duration(milliseconds: 200));
      expect(thrown, isNull);
      expect(parent.outcome, isA<Cancelled>());
    });
  });
}
