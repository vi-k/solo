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
      final job = Job<String>(
        ifCancelled: closed.add,
        (ctx) async {
          final resource = await ctx.join(() async {
            await delay(10);
            return 'db';
          });
          // The child keeps the job alive past the return.
          ctx.run(
            Job.deferred<void>(
                key: 'child', (ctx) => ctx.wait(() => delay(100))),
          );
          return resource;
        },
      );
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
      final job = Job<String>(
        ifCancelled: (value) => order.add('disposer'),
        (ctx) async {
          // Not started by hand: `run` starts it, and the cascade would
          // otherwise reach an already running child. Uncancellable, so the
          // cascade does not cut its wait short before it writes its line.
          ctx.run(
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
        },
      );
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
        ifCancelled: (value) => throw StateError('close failed'),
        (ctx) async {
          ctx.run(
            Job.deferred<void>(
                key: 'child', (ctx) => ctx.wait(() => delay(100))),
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
          final job = Job<String>(
            ifCancelled: (value) => throw StateError('close failed'),
            (ctx) async {
              ctx.run(
                Job.deferred<void>((ctx) => ctx.wait(() => delay(100))),
              );
              return 'db';
            },
          );
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

  test('a body that threw leaves the disposer alone', () {
    fakeAsync((async) {
      var called = false;
      final job = Job<String>(
        ifCancelled: (value) => called = true,
        (ctx) async {
          await ctx.wait(() => delay(10));
          throw StateError('boom');
        },
      )..ignore();
      async.flushTimers();
      expect(called, isFalse);
      expect(job.outcome, isA<Failed>());
    });
  });
}
