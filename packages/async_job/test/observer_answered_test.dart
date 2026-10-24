@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/probe_job.dart';

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

/// A [Heard] that cancels the job from `onError`.
final class Cancelling extends Heard {
  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required bool answered,
  }) {
    super.onError(job, error, stackTrace, answered: answered);
    job.cancel().ignore();
  }
}

/// Hears `onError` and answers for nothing: the answer is the zone.
final class Listening extends JobObserver {
  /// Writes into [seen] when given one, so a test can keep the zone in the
  /// same list.
  Listening([List<String>? seen]) : seen = seen ?? <String>[];

  final List<String> seen;

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

/// An envelope whose errors are other ones once [shifted] is set: a
/// second walk over it meets not what the first one met.
final class Shifting
    extends ParallelWaitError<List<Object?>, List<AsyncError?>> {
  Shifting(this._before, this._after) : super(const [], const []);

  final List<AsyncError?> _before;
  final List<AsyncError?> _after;
  bool shifted = false;

  @override
  List<AsyncError?> get errors => shifted ? _after : _before;
}

/// Runs [body] under fake time in a zone of its own and returns what
/// reached that zone, written into [caught] when given one.
List<String> zoneOf(
  void Function(FakeAsync async) body, [
  List<String>? caught,
]) {
  final into = caught ?? <String>[];
  runZonedGuarded(
    () => fakeAsync(body),
    (error, stackTrace) => into.add('$error'),
  );
  return into;
}

/// A job whose cleanup throws [error], cancelled 10 ms in unless [cancel] is
/// false; returns what reached the zone.
List<String> disposing(
  Object error,
  JobObserver observer, {
  bool cancel = false,
  List<String>? caught,
}) =>
    zoneOf(
      (async) {
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
      },
      caught,
    );

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

  group('settled before onError', () {
    test('an onError that cancels its job keeps the answer it was told of', () {
      nameTheStop();
      final heard = Cancelling();
      final zone = zoneOf((async) {
        Job<void>(observer: heard, (ctx) async {
          ctx.unattended(() async {
            await delay(10);
            throw const Stopped();
          });
          await ctx.abandonable(() => delay(20));
        });
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(asked, isEmpty);
      expect(heard.seen, [
        'onError: Stopped, answered: true',
        'onUnanswered: Stopped',
      ]);
    });

    test('the error of a filter that throws reaches the zone before onError',
        () {
      Job.isCancellationError = (error) => throw StateError('filter broke');
      final log = <String>[];
      disposing(
        StateError('disk full'),
        Listening(log),
        cancel: true,
        caught: log,
      );
      expect(log, [
        'Bad state: filter broke',
        'onError: Bad state: disk full, answered: true',
        'Bad state: disk full',
      ]);
    });

    test('an envelope that walks otherwise the second time', () {
      final a = StateError('a');
      final b = StateError('b');
      final envelope = Shifting(
        [AsyncError(a, StackTrace.empty), AsyncError(b, StackTrace.empty)],
        [AsyncError(b, StackTrace.empty)],
      );
      Job.isCancellationError = (error) {
        asked.add('$error');
        envelope.shifted = true;
        return false;
      };
      final heard = Heard();
      expect(disposing(envelope, heard, cancel: true), isEmpty);
      expect(asked, ['Bad state: a', 'Bad state: b']);
      expect(heard.seen, [
        'onError: Bad state: b, answered: true',
        'onUnanswered: Bad state: a',
        'onUnanswered: Bad state: b',
      ]);
    });
  });

  group('routes of the engine', () {
    test('an error of the finished hook, the answer right after', () {
      final heard = Heard();
      final zone = zoneOf((async) {
        FailingHookJob<int>(observer: heard, (ctx) async => 1).launch();
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(heard.seen, [
        'onError: Bad state: hook failed, answered: true',
        'onUnanswered: Bad state: hook failed',
      ]);
    });

    test('a Failed handed to a job that is over, the answer right after', () {
      final heard = Heard();
      final zone = zoneOf((async) {
        final job = ProbeJob<int>(observer: heard, (ctx) async => 1)..launch();
        async.flushTimers();
        job.drop(Failed(StateError('late'), StackTrace.current));
      });
      expect(zone, isEmpty);
      expect(heard.seen, [
        'onError: Bad state: late, answered: true',
        'onUnanswered: Bad state: late',
      ]);
    });

    test('a Failed handed to a job that is over and ignores its failure', () {
      final heard = Heard();
      final zone = zoneOf((async) {
        final job = ProbeJob<int>(observer: heard, (ctx) async => 1)
          ..ignoreFailure()
          ..launch();
        async.flushTimers();
        job.drop(Failed(StateError('late'), StackTrace.current));
      });
      expect(zone, isEmpty);
      expect(heard.seen, ['onError: Bad state: late, answered: false']);
    });

    test('a Failed handed to a running job: its outcome carries it', () {
      final heard = HeardToTheEnd();
      final zone = zoneOf((async) {
        final job = ProbeJob<int>(observer: heard, (ctx) async {
          await ctx.abandonable(() => delay(20));
          return 1;
        })
          ..launch();
        async.elapse(const Duration(milliseconds: 10));
        job.drop(Failed(StateError('by hand'), StackTrace.current));
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(heard.seen, [
        'onError: Bad state: by hand, answered: false',
        'onFinish',
        'onUnanswered: Bad state: by hand',
      ]);
    });

    test('a source that fails to stop, the answer right after', () {
      final heard = Heard();
      final zone = zoneOf((async) {
        UncancellableByBugJob<int>((ctx) async => 1)
            .then((ctx, value) => value, observer: heard)
            .cancel()
            .ignore();
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(heard.seen, [
        'onError: Bad state: engine failed to cancel, answered: true',
        'onUnanswered: Bad state: engine failed to cancel',
      ]);
    });

    test('the failure of the source of a continuation', () {
      final heard = HeardToTheEnd();
      final zone = zoneOf((async) {
        Job<int>((ctx) async {
          await delay(10);
          throw StateError('source');
        }).then((ctx, value) => value, observer: heard);
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(heard.seen, [
        'onError: Bad state: source, answered: false',
        'onFinish',
        'onUnanswered: Bad state: source',
      ]);
    });

    test('the failure of the source of a shared handle', () {
      final heard = HeardToTheEnd();
      final zone = zoneOf((async) {
        Job<int>((ctx) async {
          await delay(10);
          throw StateError('source');
        }).shared(observer: heard);
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(heard.seen, [
        'onError: Bad state: source, answered: false',
        'onFinish',
        'onUnanswered: Bad state: source',
      ]);
    });
  });

  test('the filter of cancellation errors is left as it was found', () {
    expect(Job.isCancellationError, isNull);
  });
}
