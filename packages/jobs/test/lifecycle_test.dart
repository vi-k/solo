@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

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

  test('a job created in the same stripe can still be a child', () {
    fakeAsync((async) {
      // Inside the parent's body: a job made before it would have started
      // on its own microtask, and could not be adopted.
      late final Job<void> child;
      final parent = Job<void>((ctx) async {
        child = Job<void>((ctx) async {});
        await ctx.run(child).done;
      });
      async.flushMicrotasks();
      expect(child.isChild, isTrue);
      expect(child.level, 1);
      expect(parent.isFinished, isTrue);
    });
  });

  test('a job started by its own microtask cannot be adopted', () {
    fakeAsync((async) {
      final early = Job<void>((ctx) async {});
      async.flushMicrotasks();
      // `ignore` before the microtasks run: an unobserved Failed would
      // otherwise reach the zone and fail the test on its own.
      final parent = Job<void>((ctx) async => ctx.run(early))..ignore();
      async.flushMicrotasks();
      expect(parent.outcome, isA<Failed>());
      expect((parent.outcome! as Failed).error, isA<StateError>());
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
        'Job(null)',
        reason: 'a job without a key still prints',
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
}
