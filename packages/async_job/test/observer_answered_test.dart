@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

// `answered` of `JobObserver.onError` says whether the job asks for an answer
// to the error right after the call: `JobAnswerer.onUnanswered` of an observer
// that answers, or the zone. An error of cleanup or of a callback is answered
// that way unless it is a cancellation or the filter of cancellation errors
// names it; a failure of a body is answered later, if at all, once the job
// has ended.

/// What an operation throws once the cancellation of its job stops it.
final class Stopped implements Exception {
  const Stopped();

  @override
  String toString() => 'Stopped';
}

/// Both hooks in one list, the flag beside each error; answers for every
/// error, so nothing reaches the zone through it.
class Heard extends JobObserver with JobAnswerer {
  final seen = <String>[];

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required bool answered,
  }) =>
      seen.add('onError: $error, answered: $answered');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      seen.add('onUnanswered: $error');
}

/// A [Heard] that also writes down where the job ends.
final class HeardToTheEnd extends Heard {
  @override
  void onFinish(Job<Object?> job) => seen.add('onFinish');
}

/// Hears `onError` and answers for nothing: the answer is the zone.
final class Listening extends JobObserver {
  final seen = <String>[];

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required bool answered,
  }) =>
      seen.add('onError: $error, answered: $answered');
}

/// What the filter was asked about, in order.
final asked = <String>[];

/// Names [Stopped] and writes down every question.
void nameTheStop() {
  Job.isCancellationError = (error) {
    asked.add('$error');
    return error is Stopped;
  };
}

/// Runs [body] under fake time in a zone of its own and returns what
/// reached that zone.
List<String> zoneOf(void Function(FakeAsync async) body) {
  final caught = <String>[];
  runZonedGuarded(
    () => fakeAsync(body),
    (error, stackTrace) => caught.add('$error'),
  );
  return caught;
}

/// A job whose cleanup throws [error], cancelled 10 ms in unless [cancel] is
/// false; returns what reached the zone.
List<String> disposing(
  Object error,
  JobObserver observer, {
  bool cancel = false,
}) =>
    zoneOf((async) {
      final job = Job<void>(observer: observer, (ctx) async {
        ctx.onDispose(
          () => Error.throwWithStackTrace(error, StackTrace.current),
        );
        await ctx.abandonable(() => delay(20));
      });
      async.elapse(const Duration(milliseconds: 10));
      if (cancel) {
        job.cancel().ignore();
      }
      async.flushTimers();
    });

void main() {
  setUp(asked.clear);
  tearDown(() => Job.isCancellationError = null);

  group('answered', () {
    test('an error of ctx.onDispose, the answer right after', () {
      final heard = Heard();
      expect(disposing(StateError('disk full'), heard), isEmpty);
      expect(heard.seen, [
        'onError: Bad state: disk full, answered: true',
        'onUnanswered: Bad state: disk full',
      ]);
    });

    test('an error of ctx.onDispose with an observer that does not answer', () {
      final listening = Listening();
      expect(
        disposing(StateError('disk full'), listening),
        ['Bad state: disk full'],
      );
      expect(listening.seen, ['onError: Bad state: disk full, answered: true']);
    });

    test('a failure of the body of a child the parent reads', () {
      final heard = Heard();
      final caught = <String>[];
      final zone = zoneOf((async) {
        Job<void>((ctx) async {
          try {
            await ctx.run(
              Job.deferred<void>(observer: heard, (ctx) async {
                await delay(10);
                throw StateError('child');
              }),
            );
          } on Object catch (error) {
            caught.add('$error');
          }
        });
        async.flushTimers();
      });
      expect(caught, ['Bad state: child']);
      expect(heard.seen, ['onError: Bad state: child, answered: false']);
      expect(zone, isEmpty);
    });

    test('a failure of a body nobody reads: the answer comes later', () {
      final heard = HeardToTheEnd();
      final zone = zoneOf((async) {
        Job<void>(observer: heard, (ctx) async {
          await delay(10);
          throw StateError('body');
        });
        async.flushTimers();
      });
      expect(heard.seen, [
        'onError: Bad state: body, answered: false',
        'onFinish',
        'onUnanswered: Bad state: body',
      ]);
      expect(zone, isEmpty);
    });

    test('a Cancelled a callback throws', () {
      const cancelled = Cancelled('from cleanup');
      final heard = Heard();
      expect(disposing(cancelled, heard), isEmpty);
      expect(heard.seen, ['onError: $cancelled, answered: false']);
    });

    test('a failure of a cancelled job the filter names, asked once', () {
      nameTheStop();
      final heard = Heard();
      expect(disposing(const Stopped(), heard, cancel: true), isEmpty);
      expect(asked, ['Stopped']);
      expect(heard.seen, ['onError: Stopped, answered: false']);
    });

    test('a failure of a cancelled job the filter does not name, asked once',
        () {
      nameTheStop();
      final heard = Heard();
      expect(disposing(StateError('disk full'), heard, cancel: true), isEmpty);
      expect(asked, ['Bad state: disk full']);
      expect(heard.seen, [
        'onError: Bad state: disk full, answered: true',
        'onUnanswered: Bad state: disk full',
      ]);
    });

    test('a ParallelWaitError of cleanup, each error with its own', () {
      nameTheStop();
      const cancelled = Cancelled('a branch');
      final heard = Heard();
      final zone = disposing(
        ParallelWaitError<List<Object?>, List<AsyncError?>>(
          [null, null, null],
          [
            AsyncError(cancelled, StackTrace.empty),
            AsyncError(const Stopped(), StackTrace.empty),
            AsyncError(StateError('disk full'), StackTrace.empty),
          ],
        ),
        heard,
        cancel: true,
      );
      expect(zone, isEmpty);
      expect(asked, ['Stopped', 'Bad state: disk full']);
      expect(heard.seen, [
        'onError: $cancelled, answered: false',
        'onError: Stopped, answered: false',
        'onError: Bad state: disk full, answered: true',
        'onUnanswered: Bad state: disk full',
      ]);
    });

    test('JobObserver.all hands the flag to each observer', () {
      final listening = Listening();
      final heard = Heard();
      final zone = zoneOf((async) {
        Job<void>(
          observer: JobObserver.all([listening, heard]),
          (ctx) async {
            ctx.onDispose(() => throw StateError('disk full'));
            await delay(10);
            throw StateError('body');
          },
        ).ignoreFailure();
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(listening.seen, [
        'onError: Bad state: body, answered: false',
        'onError: Bad state: disk full, answered: true',
      ]);
      expect(heard.seen, [
        'onError: Bad state: body, answered: false',
        'onError: Bad state: disk full, answered: true',
        'onUnanswered: Bad state: disk full',
      ]);
    });
  });

  test('the filter of cancellation errors is left as it was found', () {
    expect(Job.isCancellationError, isNull);
  });
}
