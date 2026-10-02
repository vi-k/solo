// The code of `doc/observing.md` as the page answers it, verbatim: every
// block of the page but its first attempts is a run of lines of this file,
// and `observing_rakes_test.dart` runs it. The first attempts live in
// `observing_first_attempts.dart`: the first `DatabaseErrors` has the name
// of the second, and a line of an answer turned into a line of a first
// attempt must not be found among the answers. A block that declares names
// another block declares too lives in a function of its own.
import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart' show isA;

import 'observing_stubs.dart';

/// How a test of the page is declared: `test` of `package:test`, or a
/// stand-in that runs the body at once.
typedef Declare = void Function(String description, void Function() body);

/// How a test of the page checks: `expect` of `package:test`, or a
/// stand-in that records the call.
typedef Check = void Function(Object? actual, Object? matcher);

final class Log extends JobObserver {
  @override
  void onFinish(Job<Object?> job) => print('$job: ${job.outcome}');

  @override
  void onLog(Job<Object?> job, Object? message) {
    final data = message is Object? Function() ? message() : message;
    print('$job: $data');
  }
}

Job<int> loading() {
  final job = Job<int>(
    key: 'load',
    observer: Log(),
    (ctx) async {
      ctx.log('loading');
      return ctx.wait(load);
    },
  );
  return job;
}

final class SlowCancellations extends JobObserver {
  final _since = Expando<Stopwatch>('cancellation');

  @override
  void onStart(Job<Object?> job) =>
      job.whenCancelled((_) => _since[job] = Stopwatch()..start());

  @override
  void onFinish(Job<Object?> job) {
    final watch = _since[job];
    if (watch != null) {
      print('$job ran ${watch.elapsedMilliseconds} ms past its cancellation');
    }
  }
}

/// The body of the log section: it migrates the database and, when the
/// migration fails, leaves the message to the observer.
Job<void> migration({JobObserver? observer}) => Job<void>(
      key: 'migrate',
      observer: observer,
      (ctx) async {
        try {
          await migrate();
        } on Object catch (error) {
          ctx.log(() => 'migration failed: $error');
        }
      },
    );

final class Reporter extends JobObserver {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onError: $error');
}

Job<Database> openingReported() {
  final job = Job<Database>(
    observer: Reporter(),
    (ctx) => ctx.join(
      Database.open,
      discard: (database) => database.close(),
    ),
  );
  return job;
}

Job<Database> openingShown() {
  final job = Job<Database>(
    observer: Reporter(),
    (ctx) async {
      try {
        return await ctx.join(Database.open);
        // ignore: avoid_catches_without_on_clauses
      } catch (error) {
        await showError(error);
        rethrow;
      }
    },
  );
  return job;
}

/// The job of the section on work the job does not wait for, with the work
/// handed to it.
Job<void> sendingHandedOver(JobObserver? observer) => Job<void>(
      observer: observer,
      (ctx) async {
        ctx.unattended(() => analytics.send('loaded'));
      },
    );

final class Answering extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onUnanswered: $error');
}

final class DatabaseErrors extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      Job.visitErrors(
        error,
        stackTrace,
        onFailure: (failure, failureStackTrace) {
          if (failure is DatabaseException) {
            print('onUnanswered: $failure');
          } else {
            super.onUnanswered(job, failure, failureStackTrace);
          }
        },
      );
}

/// The job of the first attempt, with the answer in place of its observer.
Job<void> saving() {
  final job = Job<void>(
    observer: DatabaseErrors(),
    (ctx) async {
      ctx.unattended(() => [saveDraft(), sendAnalytics()].wait);
    },
  );
  return job;
}

final class Crashes extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onUnanswered: $error');
}

Job<void> sendingToTheList() {
  final job = Job<void>(
    observer: JobObserver.all([Reporter(), Crashes()]),
    (ctx) async {
      ctx.unattended(() => analytics.send('loaded'));
    },
  );
  return job;
}

void timeMovedByTheTest(Declare test, Check expect) {
  test('a cancelled open still closes what it opened', () {
    fakeAsync((async) {
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
      job.cancel().ignore(); // nothing awaits inside `fakeAsync`
      async.flushTimers();

      expect(job.outcome, isA<Cancelled>());
      expect(closed, 1); // what the test is named for
    });
  });
}
