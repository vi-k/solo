@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';

void main() {
  test('wait ends the waiting, not the work', () {
    fakeAsync((async) {
      var finishedAt = Duration.zero;
      final job = Job<void>((ctx) async {
        await ctx.wait(() async {
          await delay(100);
          finishedAt = async.elapsed;
        });
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(
        finishedAt.inMilliseconds,
        100,
        reason: 'the action ran on; only the waiting ended',
      );
    });
  });

  test('wait hands a late value to the disposer', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<void>((ctx) async {
        await ctx.wait(
          () async {
            await delay(100);
            return 'db';
          },
          discard: closed.add,
        );
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(closed, ['db']);
    });
  });

  test('a late error of an abandoned action goes to the observer', () {
    fakeAsync((async) {
      final journal = JobJournal();
      final job = Job<void>(
        key: 'job',
        observer: journal,
        (ctx) async {
          await ctx.wait(() async {
            await delay(100);
            throw StateError('late');
          });
        },
      );
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(journal.take(), contains('[job] error Bad state: late'));
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('every member throws up front once the job is marked', () {
    fakeAsync((async) {
      final thrown = <Object>[];
      var began = false;
      final job = Job<void>((ctx) async {
        try {
          await ctx.wait(() => delay(10));
        } on Cancelled {
          // Caught on purpose: the body now asks the context again, and
          // that is the path this test is about — the entry, not the
          // waiting that was cut short above.
        }
        for (final call in <Future<void> Function()>[
          () => ctx.wait(() async => began = true),
          () => ctx.join(() async => began = true),
          () => ctx.uncancellable(() async => began = true),
        ]) {
          try {
            await call();
          } on Object catch (error) {
            thrown.add(error);
          }
        }
        for (final call in <void Function()>[
          () => ctx.onCancel(() {}),
          ctx.check,
        ]) {
          try {
            call();
          } on Object catch (error) {
            thrown.add(error);
          }
        }
      });
      async.elapse(const Duration(milliseconds: 5));
      job.cancel().ignore();
      async.flushTimers();
      expect(began, isFalse, reason: 'not one of them began its action');
      expect(thrown, hasLength(5));
      expect(thrown, everyElement(isA<Cancelled>()));
    });
  });

  test('wait returns a synchronous result as it is', () {
    fakeAsync((async) {
      int? seen;
      final job = Job<void>((ctx) async {
        seen = await ctx.wait(() => 7);
      });
      async.flushMicrotasks();
      expect(seen, 7);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('join waits for the whole action and gives up after it', () {
    fakeAsync((async) {
      var reached = false;
      var actionEndedAt = Duration.zero;
      final job = Job<void>((ctx) async {
        await ctx.join(() async {
          await delay(100);
          actionEndedAt = async.elapsed;
        });
        reached = true;
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(actionEndedAt.inMilliseconds, 100);
      expect(reached, isFalse, reason: 'it gives up after the action');
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('join hands the value to discard when the cancel arrived', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<void>((ctx) async {
        await ctx.join(
          () async {
            await delay(100);
            return 'db';
          },
          discard: closed.add,
        );
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(closed, ['db']);
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('onCancel callbacks run in registration order, once', () {
    fakeAsync((async) {
      final calls = <String>[];
      final job = Job<void>((ctx) async {
        ctx
          ..onCancel(() => calls.add('first'))
          ..onCancel(() => calls.add('second'));
        await ctx.wait(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      job.cancel().ignore();
      async.flushTimers();
      expect(calls, ['first', 'second']);
    });
  });

  test('onCancel returns a remover', () {
    fakeAsync((async) {
      final calls = <String>[];
      final job = Job<void>((ctx) async {
        final remove = ctx.onCancel(() => calls.add('gone'));
        ctx.onCancel(() => calls.add('kept'));
        remove();
        await ctx.wait(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(calls, ['kept']);
    });
  });

  test('a context that outlived its job writes nothing and reads fine', () {
    fakeAsync((async) {
      late final JobContext leaked;
      final job = Job<void>((ctx) async {
        leaked = ctx;
      });
      async.flushMicrotasks();
      expect(job.isFinished, isTrue);
      // The three are `async`, so the StateError arrives in the future
      // they return, not from the call itself.
      final errors = <Object>[];
      void record(Object error, StackTrace stackTrace) => errors.add(error);
      unawaited(leaked.wait(() async {}).then((_) {}, onError: record));
      unawaited(leaked.join(() async {}).then((_) {}, onError: record));
      unawaited(
        leaked.uncancellable(() async {}).then((_) {}, onError: record),
      );
      async.flushMicrotasks();
      expect(errors, hasLength(3));
      expect(errors, everyElement(isA<StateError>()));
      expect(leaked.check, returnsNormally);
      expect(() => leaked.log('still legal'), returnsNormally);
    });
  });
}
