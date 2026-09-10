@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';
import 'support/probe_job.dart';

void main() {
  test('a failure of unattended work reaches the observer', () {
    final journal = JobJournal();
    fakeAsync((async) {
      Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() async {
          await delay(10);
          throw StateError('abandoned boom');
        });
        await ctx.wait(() => delay(1));
      });
      async.flushTimers();
    });
    expect(journal.take(), [
      '[j] started',
      '[j] finished Done(null)',
      '[j] error Bad state: abandoned boom',
    ]);
  });

  test(
      'without an observer the failure goes to the zone that created the '
      'job', () {
    final caught = <String>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>(key: 'j', (ctx) async {
            ctx.unattended(() async {
              await delay(10);
              throw StateError('abandoned boom');
            });
            await ctx.wait(() => delay(1));
          });
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add('$error'),
    );
    expect(caught, ['Bad state: abandoned boom']);
  });

  test('the failure arrives after the job has finished', () {
    final journal = JobJournal();
    fakeAsync((async) {
      Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() async {
          await delay(10);
          throw StateError('abandoned boom');
        });
        await ctx.wait(() => delay(1));
      });
      async.elapse(const Duration(milliseconds: 5));
      expect(journal.take(), ['[j] started', '[j] finished Done(null)']);
      async.elapse(const Duration(milliseconds: 5));
      expect(journal.take(), ['[j] error Bad state: abandoned boom']);
    });
  });

  test(
      'a synchronous throw of the action goes to the observer, not to the '
      'body', () {
    final journal = JobJournal();
    late final Job<void> job;
    fakeAsync((async) {
      job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() => throw StateError('sync boom'));
        await ctx.wait(() => delay(1));
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
    });
    expect(journal.take(), [
      '[j] started',
      '[j] error Bad state: sync boom',
      '[j] finished Done(null)',
    ]);
  });

  test("the job's own cancellation seen inside the work is not an error", () {
    final journal = JobJournal();
    fakeAsync((async) {
      final job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() async {
          await ctx.wait(() => delay(50));
        });
        await ctx.wait(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 5));
      job.cancel();
      async.flushTimers();
    });
    expect(journal.take().where((line) => line.contains('error')), isEmpty);
  });

  test('a body cancelling itself leaves nothing at the observer', () {
    final journal = JobJournal();
    fakeAsync((async) {
      Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() async {
          await ctx.wait(() => delay(50));
          ctx.check();
        });
        await delay(5);
        throw const Cancelled('enough');
      });
      async.flushTimers();
    });
    expect(journal.take().where((line) => line.contains('error')), isEmpty);
  });

  test('a Cancelled built inside the work is an error like any other', () {
    final journal = JobJournal();
    late final Job<void> job;
    fakeAsync((async) {
      job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() => throw const Cancelled('mine'));
        await ctx.wait(() => delay(1));
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
    });
    expect(journal.take(), [
      '[j] started',
      '[j] error Cancelled(handler: mine)',
      '[j] finished Done(null)',
    ]);
  });

  test(
      "a child cancelled by this job's cascade is not an error, a child "
      'cancelling itself is', () {
    List<String> run({required bool own}) {
      final journal = JobJournal();
      fakeAsync((async) {
        final job = Job<void>(key: 'j', observer: journal, (ctx) async {
          final child = Job.deferred<void>(key: 'child', (c) async {
            await c.wait(() => delay(own ? 10 : 100));
            if (own) {
              throw const Cancelled('child quits');
            }
          });
          ctx.run(child).ignore();
          ctx.unattended(() async {
            await child.value;
          });
          await ctx.wait(() => delay(own ? 100 : 30));
        });
        if (!own) {
          async.elapse(const Duration(milliseconds: 5));
          job.cancel();
        }
        async.flushTimers();
      });
      return journal.take().where((line) => line.contains('error')).toList();
    }

    expect(run(own: false), isEmpty);
    expect(run(own: true), ['[j] error Cancelled(handler: child quits)']);
  });

  test('a child of another job cancelled by its own parent is an error', () {
    final journalA = JobJournal();
    final journalB = JobJournal();
    fakeAsync((async) {
      late final Job<void> c;
      final b = Job<void>(key: 'b', observer: journalB, (ctx) async {
        c = Job.deferred<void>(key: 'c', (cc) async {
          await cc.wait(() => delay(100));
        });
        ctx.run(c).ignore();
        await ctx.wait(() => delay(100));
      });
      async.flushMicrotasks();
      final a = Job<void>(key: 'a', observer: journalA, (ctx) async {
        ctx.unattended(() async {
          await c.value;
        });
        await ctx.wait(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 5));
      a.cancel();
      b.cancel();
      async.flushTimers();
    });
    expect(
      journalA.take().where((line) => line.contains('error')),
      ['[a] error Cancelled(parent)'],
    );
  });

  test('unattended after the job has finished throws and names itself', () {
    late final JobContext leaked;
    fakeAsync((async) {
      Job<void>(key: 'j', (ctx) async {
        leaked = ctx;
      });
      async.flushTimers();
    });
    expect(
      () => leaked.unattended(() {}),
      throwsA(
        isA<StateError>()
            .having((e) => '$e', 'message', contains('unattended')),
      ),
    );
  });

  test('a disposer may start unattended work', () {
    final journal = JobJournal();
    fakeAsync((async) {
      Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.onDispose(
          () => ctx.unattended(() async {
            await delay(10);
            throw StateError('late');
          }),
        );
        await ctx.wait(() => delay(1));
      });
      async.flushTimers();
    });
    expect(journal.take(), [
      '[j] started',
      '[j] finished Done(null)',
      '[j] error Bad state: late',
    ]);
  });

  test('unattended on a cancelled but still running job does not throw', () {
    var ran = false;
    fakeAsync((async) {
      final job = Job<void>(key: 'j', (ctx) async {
        try {
          await ctx.wait(() => delay(100));
        } finally {
          ctx.unattended(() => ran = true);
        }
      });
      async.elapse(const Duration(milliseconds: 5));
      job.cancel();
      async.flushTimers();
    });
    expect(ran, isTrue);
  });

  test('a late failure of a wait made in the work reports as it always does',
      () {
    final journal = JobJournal();
    fakeAsync((async) {
      final job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() async {
          await ctx.wait(() async {
            await delay(50);
            ctx.check();
          });
        });
        await ctx.wait(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 5));
      job.cancel();
      async.flushTimers();
    });
    // The filter covers what the work leaves uncaught, and nothing else: a
    // `wait` made in here keeps its own rules, and an action it was left
    // holding reports its late failure as it does anywhere — a `Cancelled`
    // included. Pinned so the two rules are not confused for one.
    expect(journal.take(), [
      '[j] started',
      '[j] finished Cancelled(manual)',
      '[j] error Cancelled(manual)',
    ]);
  });

  test('a cancellation the engine finished the job with is not an error', () {
    final journal = JobJournal();
    fakeAsync((async) {
      final job = ProbeJob<void>(
        key: 'j',
        observer: journal,
        (ctx) async {
          ctx.unattended(() async {
            await delay(30);
            // The job was ended by hand, so it was never marked: the
            // cancellation lives in the outcome alone. Thrown the way the
            // core throws an outcome itself, which is also how a test
            // throws one without tripping `only_throw_errors`.
            Error.throwWithStackTrace(ctx.job.outcome!, StackTrace.current);
          });
          await ctx.wait(() => delay(100));
        },
      )..launch();
      async.elapse(const Duration(milliseconds: 5));
      job.drop(
        const Cancelled.by(reason: ManualCancelReason(), started: true),
      );
      async.flushTimers();
    });
    expect(journal.take().where((line) => line.contains('error')), isEmpty);
  });

  test('an outcome that is not a cancellation is an error like any other', () {
    final journal = JobJournal();
    fakeAsync((async) {
      final job = ProbeJob<void>(
        key: 'j',
        observer: journal,
        (ctx) async {
          ctx.unattended(() async {
            await delay(30);
            Error.throwWithStackTrace(ctx.job.outcome!, StackTrace.current);
          });
          await ctx.wait(() => delay(100));
        },
      )..launch();
      async.elapse(const Duration(milliseconds: 5));
      job.drop(const Done<void>(null));
      async.flushTimers();
    });
    expect(
      journal.take().where((line) => line.contains('error')),
      ['[j] error Done(null)'],
    );
  });

  test('onCancel may hand an asynchronous stop to unattended work', () {
    final journal = JobJournal();
    var stopped = false;
    fakeAsync((async) {
      final job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.onCancel(
          () => ctx.unattended(() async {
            stopped = true;
            await delay(10);
            throw StateError('device.stop failed');
          }),
        );
        await ctx.wait(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 5));
      job.cancel();
      async.flushTimers();
    });
    expect(stopped, isTrue);
    expect(
      journal.take().where((line) => line.contains('error')),
      ['[j] error Bad state: device.stop failed'],
    );
  });

  test('unattended work cannot start an each child', () {
    final journal = JobJournal();
    fakeAsync((async) {
      final source = StreamController<int>();
      Object? caught;
      final job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() {
          try {
            ctx.each(source.stream, (_, event) {});
          } on Object catch (error) {
            caught = error;
          }
        });
        await ctx.wait(() => delay(1));
      });
      async.flushTimers();
      expect(
        caught,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('inside unattended work'),
        ),
      );
      expect(source.hasListener, isFalse);
      expect(job.outcome, isA<Done<void>>());
      source.close();
      async.flushTimers();
    });
    expect(journal.take(), [
      '[j] started',
      '[j] finished Done(null)',
    ]);
  });
}
