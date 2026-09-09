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
  test('the body does not start inside the constructor', () {
    fakeAsync((async) {
      var started = false;
      final job = Job<void>((ctx) async => started = true);
      expect(started, isFalse);
      expect(job.isRunning, isFalse);
      async.flushMicrotasks();
      expect(started, isTrue);
    });
  });

  test('a job cancelled before its microtask never runs', () {
    fakeAsync((async) {
      var started = false;
      final job = Job<void>((ctx) async => started = true)..cancel().ignore();
      async.flushMicrotasks();
      expect(started, isFalse);
      expect(job.outcome, isA<Cancelled>());
      expect((job.outcome! as Cancelled).started, isFalse);
    });
  });

  test('a deferred job waits for start', () {
    fakeAsync((async) {
      var started = false;
      final job = Job.deferred<void>((ctx) async => started = true);
      async.flushMicrotasks();
      expect(started, isFalse);
      job.start();
      async.flushMicrotasks();
      expect(started, isTrue);
    });
  });

  test('start of a job that already ran throws', () {
    fakeAsync((async) {
      final job = Job.deferred<void>((ctx) async {})..start();
      async.flushMicrotasks();
      expect(job.start, throwsStateError);
    });
  });

  test('a job that starts itself cannot be a child', () {
    fakeAsync((async) {
      // Made inside the parent's body, before its own microtask came
      // round: `run` would still have found it `created` and adopted it.
      late final Job<void> orphan;
      Object? thrown;
      final parent = Job<void>((ctx) async {
        orphan = Job<void>((ctx) async {});
        try {
          ctx.run(orphan);
        } on Object catch (error) {
          thrown = error;
        }
      });
      async.flushMicrotasks();
      expect(thrown, isA<ArgumentError>());
      expect(orphan.isChild, isFalse);
      expect(
        orphan.outcome,
        isA<Done<void>>(),
        reason: 'refused, and left to start itself as the root it is',
      );
      expect(parent.isFinished, isTrue);
    });
  });

  test('a job that already started itself cannot be a child either', () {
    fakeAsync((async) {
      final early = Job<void>((ctx) async {});
      async.flushMicrotasks();
      // `ignore` before the microtasks run: an unobserved Failed would
      // otherwise reach the zone and fail the test on its own.
      final parent = Job<void>((ctx) async => ctx.run(early))..ignore();
      async.flushMicrotasks();
      expect(parent.outcome, isA<Failed>());
      // The same answer as in the stripe above: which of the two got
      // here first is nothing the reader of that body could see.
      expect((parent.outcome! as Failed).error, isA<ArgumentError>());
    });
  });

  test('finish on a job that has already finished does nothing', () {
    fakeAsync((async) {
      final journal = JobJournal();
      final job = ProbeJob<int>(
        key: 'job',
        observer: journal,
        (ctx) async => 1,
      )..launch();
      async.flushMicrotasks();
      expect((job.outcome! as Done<int>).value, 1);
      journal.take();
      job.drop(const Done(2));
      async.flushMicrotasks();
      expect(
        (job.outcome! as Done<int>).value,
        1,
        reason: 'the outcome of a finished job does not change',
      );
      expect(journal.take(), isEmpty, reason: 'and nothing is announced');
    });
  });

  test('a job finished by hand keeps its cleanup stack', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = ProbeJob<void>((ctx) async {
        ctx.onDispose(() => order.add('cleanup'));
        await ctx.wait(() => Future<void>.delayed(const Duration(seconds: 1)));
      })
        ..launch();
      async.elapse(const Duration(milliseconds: 10));
      // An engine of a domain ended the job itself: the outcome is not
      // ours, nobody waited for the children, and the stack stays where it
      // is — as the dartdoc of `finish` promises.
      job
        ..drop(const Done(null))
        ..ignore();
      async.flushTimers();
      expect(order, isEmpty);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('start of a job cancelled before it ran throws', () {
    fakeAsync((async) {
      final job = Job.deferred<void>((ctx) async {})..cancel().ignore();
      async.flushMicrotasks();
      expect((job.outcome! as Cancelled).started, isFalse);
      expect(job.start, throwsStateError);
    });
  });

  test('toString names the job by key, and by description when given', () {
    fakeAsync((async) {
      final plain = Job.deferred<void>(key: 'open', (ctx) async {});
      final described = Job.deferred<void>(
        key: 'zoom',
        describe: () => 'x2',
        (ctx) async {},
      );
      expect(plain.toString(), 'Job(open)');
      expect(described.toString(), 'Job(zoom: x2)');
      expect(
        Job.deferred<void>((ctx) async {}).toString(),
        'Job()',
        reason: 'a job without a key prints no null',
      );
      expect(
        Job.deferred<void>(describe: () => 'what it does', (ctx) async {})
            .toString(),
        'Job(what it does)',
        reason: 'a description stands in for the key it has not got',
      );
    });
  });

  test('the body runs where it started, the failure where it was made', () {
    final caught = <String>[];
    String? bodyZone;
    fakeAsync((async) {
      late final DeferredJob<void> job;
      runZonedGuarded(
        () {
          job = Job.deferred<void>((ctx) async {
            bodyZone = Zone.current[#name] as String?;
            throw StateError('boom');
          });
        },
        (error, stackTrace) => caught.add('creator'),
        zoneValues: {#name: 'creator'},
      );
      runZonedGuarded(
        job.start,
        (error, stackTrace) => caught.add('starter'),
        zoneValues: {#name: 'starter'},
      );
      async.flushMicrotasks();
    });
    expect(bodyZone, 'starter', reason: 'the body runs where it was started');
    expect(
      caught,
      ['creator'],
      reason: 'an unobserved failure goes where the job was made',
    );
  });

  test('an outcome is not replaced by whatever the body returns later', () {
    fakeAsync((async) {
      final journal = JobJournal();
      final job = ProbeJob<int>(
        key: 'job',
        observer: journal,
        (ctx) async {
          await ctx.wait(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          return 1;
        },
      )..launch();
      async.elapse(const Duration(milliseconds: 10));
      // An engine of a domain ends the job while its body is still going.
      job.drop(const Done(99));
      async.flushTimers();
      expect((job.outcome! as Done<int>).value, 99);
      expect(
        journal.take().where((line) => line.contains('finished')).toList(),
        ['[job] finished Done(99)'],
        reason: 'announced once, and the body did not overwrite it',
      );
    });
  });
  test('a finished hook that throws still lets the job finish', () {
    fakeAsync((async) {
      final journal = JobJournal();
      var done = false;
      final job = FailingHookJob<int>(
        key: 'job',
        observer: journal,
        (ctx) async => 7,
      )..launch();
      job.done.then((_) => done = true).ignore();
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(job.outcome, isA<Done<int>>());
      expect(
        journal.lines.where((line) => line.contains('error')).toList(),
        ['[job] error Bad state: hook failed'],
      );
    });
  });
  test('the lifecycle hooks bracket the body', () {
    fakeAsync((async) {
      final job = ProbeJob<int>((ctx) async {
        await ctx.wait(() => delay(10));

        return 1;
      })
        ..launch();
      async.flushTimers();
      expect(job.hooks, ['started', 'finished']);
    });
  });

  test('a job dropped before it started gets finished without started', () {
    fakeAsync((async) {
      final job = ProbeJob<int>((ctx) async => 1)..cancel().ignore();
      async.flushTimers();
      expect(job.hooks, ['finished']);
    });
  });
}
