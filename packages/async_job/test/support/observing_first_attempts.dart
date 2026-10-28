// The first attempts of `doc/observing.md`, `doc/errors.md` and
// `doc/testing.md`, verbatim: the versions their sections open with. They
// live apart from the answers in `observing_page.dart`, because a line of an
// answer turned into a line of a first attempt must not be found among the
// answers.
import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart' show isA;

import 'observing_page.dart' show Check, Crashes, Declare, Reporter;
import 'observing_stubs.dart';

/// The body of the log section, with the message built as a string.
Job<void> migrationLoggedAsAString({JobObserver? observer}) =>
    Job<void>(key: 'migrate', observer: observer, (ctx) async {
      try {
        await migrate();
      } on Object catch (error) {
        ctx.log('migration failed: $error');
      }
    });

/// The job of the section on where errors go, with the token wired as the
/// cancellation page wires it.
Job<void> migrating() {
  final job = Job<void>((ctx) async {
    final stop = CancelToken();
    ctx.onCancel(stop.cancel);

    await ctx.join(() => database.migrate(stop));
  });
  return job;
}

/// The job of the section on work the job does not wait for, with the work
/// left behind.
Job<void> sendingUnawaited() => Job<void>(observer: Reporter(), (ctx) async {
  unawaited(analytics.send('loaded'));
});

final class Both extends JobObserver with JobAnswerer {
  final _reporter = Reporter();
  final _crashes = Crashes();

  // The hooks the page leaves to its comment, handed on the same way.
  @override
  void onStart(Job<Object?> job) {
    _reporter.onStart(job);
    _crashes.onStart(job);
  }

  @override
  void onFinish(Job<Object?> job) {
    _reporter.onFinish(job);
    _crashes.onFinish(job);
  }

  @override
  void onLog(Job<Object?> job, Object? message) {
    _reporter.onLog(job, message);
    _crashes.onLog(job, message);
  }

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {
    _reporter.onError(job, error, stackTrace, answer: answer);
    _crashes.onError(job, error, stackTrace, answer: answer);
  }

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _crashes.onUnanswered(job, error, stackTrace);

  // onStart, onFinish and onLog the same way as onError.
}

/// The job of the section on several observers, with the hooks handed on
/// by hand.
Job<void> sendingWithBoth() {
  final job = Job<void>(observer: Both(), (ctx) async {
    ctx.unattended(() => analytics.send('loaded'));
  });
  return job;
}

void cancelledOpenAwaited(Declare test, Check expect) {
  test('a cancelled open still closes what it opened', () {
    fakeAsync((async) async {
      var closed = 0;
      final job = Job<Database>(
        (ctx) => ctx.join(
          Database.open,
          discard: (db) {
            closed++;
            return db.close();
          },
        ),
      );

      async.elapse(const Duration(milliseconds: 10));
      await job.cancel();

      expect(job.outcome, isA<Cancelled>());
      expect(closed, 1);
    });
  });
}

void failureLeftUnread(Declare test, Check expect) {
  test('a locked database fails the open', () {
    fakeAsync((async) {
      final job = Job<Database>((ctx) => ctx.join(Database.open));
      async.flushTimers();

      expect(job.outcome, isA<Failed>());
    });
  });
}

void comparedWithAnOutcome(Declare test, Check expect) {
  test('the job loads three', () {
    fakeAsync((async) {
      final job = Job<int>((ctx) => ctx.join(load));
      async.flushTimers();

      expect(job.outcome, const Done(3));
    });
  });
}
