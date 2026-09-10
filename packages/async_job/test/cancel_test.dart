@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/probe_job.dart';

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
      expect((job.outcome! as Cancelled).reason, isA<ManualCancelReason>());
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
        child = Job.deferred<void>(
          (childCtx) => childCtx.wait(() => delay(200)),
        );
        ctx.run(child).ignore();
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

  test('whenCancelled notifies before the job finishes', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) => ctx.wait(() => delay(50)))
        ..whenCancelled((_) => order.add('cancelled'));
      job.done.then((_) => order.add('done')).ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['cancelled', 'done']);
    });
  });

  test('whenCancelled of a job dropped before start notifies too', () {
    fakeAsync((async) {
      var completed = false;
      final job = Job<void>((ctx) async {})
        ..cancel().ignore()
        ..whenCancelled((_) => completed = true);
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
      expect(outcome.reason, isA<HandlerCancelReason>());
      expect(outcome.description, 'no photo');
      expect(outcome.started, isTrue);
    });
  });

  test('the cancellation of a parent reaches a child', () {
    fakeAsync((async) {
      late final Job<void> child;
      final parent = Job<void>((ctx) async {
        child = Job.deferred<void>((ctx) => ctx.wait(() => delay(100)));
        await ctx.run(child);
      });
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      async.flushTimers();
      expect((child.outcome! as Cancelled).reason, isA<ParentCancelReason>());
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
        ctx
            .run(
              Job.deferred<void>(key: 'child', (child) async {
                child.onCancel(() => parent.cancel().ignore());
                await child.wait(() => delay(100));
              }),
            )
            .ignore();
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
  test('a child started from a cancel callback is dropped, not run', () {
    fakeAsync((async) {
      // The callbacks of the children run inside the cascade, before the
      // parent used to be marked: a `run` from one of them found a parent
      // that still looked alive and started a job under an outcome that
      // was already decided.
      Object? thrown;
      final late_ = Job.deferred<void>(
        key: 'late',
        (late) => late.wait(() => delay(50)),
      );
      late Job<void> parent;
      parent = Job<void>((ctx) async {
        ctx
            .run(
              Job.deferred<void>(key: 'child', (child) async {
                child.onCancel(() {
                  try {
                    ctx.run(late_);
                  } on Object catch (error) {
                    thrown = error;
                  }
                });
                await child.wait(() => delay(100));
              }),
            )
            .ignore();
        await ctx.wait(() => delay(100));
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 10));
      parent.cancel().ignore();
      async.flushTimers();
      expect(thrown, isA<Cancelled>());
      expect(parent.outcome, isA<Cancelled>());
      expect(
        late_.outcome,
        isA<Cancelled>().having((c) => c.started, 'started', isFalse),
        reason: 'the child went down with the refusal, it did not run',
      );
    });
  });

  test('a job dropped before it started says it is cancelled', () {
    fakeAsync((async) {
      final job = Job<void>((ctx) async {})..cancel().ignore();
      expect(job.isCancelled, isTrue);
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('a cancel callback that removes another one does not break the pass',
      () {
    fakeAsync((async) {
      final seen = <String>[];
      final job = Job<void>((ctx) async {
        late void Function() removeSecond;
        ctx.onCancel(() {
          seen.add('first');
          removeSecond();
        });
        removeSecond = ctx.onCancel(() => seen.add('second'));
        await ctx.wait(() => delay(100));
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.elapse(const Duration(milliseconds: 10));
      expect(seen, ['first', 'second'], reason: 'the pass goes by a copy');
    });
  });

  test('the first cancellation a section holds is the one that lands', () {
    fakeAsync((async) {
      Cancelled held(String description) => Cancelled.by(
            reason: const ManualCancelReason(),
            started: true,
            description: description,
            stackTrace: StackTrace.current,
          );
      final job = ProbeJob<void>((ctx) async {
        await ctx.uncancellable(() => delay(50));
        await ctx.wait(() => delay(50));
      })
        ..ignore()
        ..launch();
      async.elapse(const Duration(milliseconds: 10));
      job
        ..cancelBy(held('first'))
        ..cancelBy(held('second'));
      async.flushTimers();
      expect((job.outcome! as Cancelled).description, 'first');
    });
  });

  test('the rules of a domain reach a job inside an uncancellable section', () {
    fakeAsync((async) {
      final marks = <bool>[];
      final job = RulesJob<void>((ctx) async {
        await ctx.uncancellable(() async {
          ctx.breakRule('is not Ready');
          marks.add(ctx.job.isCancelled);
          await delay(10);
        });
      })
        ..ignore()
        ..launch();
      async.flushTimers();
      expect(marks, [true], reason: 'a section holds no rule of a domain');
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('the rules of a domain reach a job that refuses cancellation', () {
    fakeAsync((async) {
      final job = RulesJob<void>(cancellable: false, (ctx) async {
        ctx.breakRule('is not Ready');
        await ctx.wait(() => delay(100));
      })
        ..ignore()
        ..launch();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect((job.outcome! as Cancelled).description, 'is not Ready');
    });
  });
  test('an engine that finishes the job from a cancel callback', () {
    fakeAsync((async) {
      // The callbacks of the children run inside the cascade, and one of
      // them reaches the engine of a domain, which ends the job by hand.
      Object? thrown;
      late ProbeJob<void> parent;
      parent = ProbeJob<void>((ctx) async {
        ctx
            .run(
              Job.deferred<void>(key: 'child', (child) async {
                child.onCancel(
                  () => parent.drop(
                    Cancelled.by(
                      reason: const ManualCancelReason(),
                      started: true,
                      description: 'by the engine',
                      stackTrace: StackTrace.current,
                    ),
                  ),
                );
                await child.wait(() => delay(100));
              }),
            )
            .ignore();
        await ctx.wait(() => delay(100));
      })
        ..ignore()
        ..launch();
      async.elapse(const Duration(milliseconds: 10));
      try {
        parent.cancel().ignore();
      } on Object catch (error) {
        thrown = error;
      }
      async.flushTimers();
      expect(thrown, isNull);
      expect((parent.outcome! as Cancelled).description, 'by the engine');
    });
  });

  test(
      'a section nobody awaited can outlive the job and lose the '
      'cancellation', () {
    // The section belongs to the job, not to the future: it opens on the
    // call and holds a cancellation whether the body waits for it or not.
    // A body that walked on can end first, and then the held cancellation
    // arrives at a job that is already over. This is what the dartdoc of
    // `uncancellable` tells the reader to avoid by awaiting the call.
    final order = <String>[];
    late Job<void> job;
    fakeAsync((async) {
      job = Job<void>((ctx) async {
        // ignore: unawaited_futures
        ctx.uncancellable(() async {
          await delay(50);
          order.add('section ends');
        });
        await ctx.wait(() => delay(20));
        order.add('body ends');
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().then((_) => order.add('cancel returned')).ignore();
      async.flushTimers();
    });
    expect(
      order,
      ['body ends', 'cancel returned', 'section ends'],
      reason: 'the body did not wait for the section and ended under it',
    );
    expect(
      job.outcome,
      isA<Done<void>>(),
      reason: 'the cancellation was held past the end of the job and then '
          'dropped, and `cancel()` returned saying nothing of it',
    );
  });
}
