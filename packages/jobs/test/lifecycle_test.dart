@Timeout(Duration(seconds: 5))
library;

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
}
