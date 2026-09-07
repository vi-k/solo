@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';

void main() {
  test('a value returned after cancellation goes to the disposer', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<String>((ctx) async {
        final resource = await ctx.join(() async {
          await delay(10);
          return 'db';
        });
        ctx
          ..onDiscard(() => closed.add(resource))
          // The child keeps the job alive past the return.
          ..run(
            Job.deferred<void>(
              key: 'child',
              (ctx) => ctx.wait(() => delay(100)),
            ),
          );
        return resource;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 30));
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(closed, ['db']);
    });
  });

  test('the disposer runs after the children and before the outcome', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<String>((ctx) async {
        ctx
          ..onDiscard(() => order.add('disposer'))
          // Not started by hand: `run` starts it, and the cascade would
          // otherwise reach an already running child. Uncancellable, so
          // the cascade does not cut its wait short before it writes its
          // line.
          ..run(
            Job.deferred<void>(
              key: 'child',
              cancellable: false,
              (ctx) async {
                await ctx.wait(() => delay(50));
                order.add('child');
              },
            ),
          );
        return 'db';
      });
      job.done.then((_) => order.add('done')).ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['child', 'disposer', 'done']);
    });
  });

  test('an error of the disposer goes to the observer', () {
    fakeAsync((async) {
      final journal = JobJournal();
      final job = Job<String>(
        key: 'job',
        observer: journal,
        (ctx) async {
          ctx
            ..onDiscard(() => throw StateError('close failed'))
            ..run(
              Job.deferred<void>(
                key: 'child',
                (ctx) => ctx.wait(() => delay(100)),
              ),
            );
          return 'db';
        },
      );
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(
        journal.take(),
        contains('[job] error Bad state: close failed'),
      );
    });
  });

  test('without an observer the disposer error goes to the zone', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<String>((ctx) async {
            ctx
              ..onDiscard(() => throw StateError('close failed'))
              ..run(
                Job.deferred<void>((ctx) => ctx.wait(() => delay(100))),
              );
            return 'db';
          });
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
          expect(job.outcome, isA<Cancelled>());
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught.map((error) => '$error').toList(), [
      'Bad state: close failed',
    ]);
  });
  test('a value that arrives during the cleanup is released before the end',
      () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        // Walked away from: the cancellation ends the wait, and the value
        // turns up later, while the engine is still unwinding the stack.
        // `ignore`, not `unawaited`: a `wait` left behind still completes
        // with the job's cancellation, and nobody is there to catch it.
        ctx.wait<String>(
          () => delay(50).then((_) => 'db'),
          discard: (value) async {
            order.add('discard starts');
            await delay(100);
            order.add('discard ends');
          },
        ).ignore();
        ctx.onDispose(() async {
          order.add('dispose starts');
          await delay(50);
          order.add('dispose ends');
        });
        await ctx.wait(() => delay(200));
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 10));
      job
        ..cancel().ignore()
        ..done.then((_) => order.add('done')).ignore();
      async.flushTimers();
      expect(order, [
        'dispose starts',
        'dispose ends',
        'discard starts',
        'discard ends',
        'done',
      ]);
    });
  });
}
