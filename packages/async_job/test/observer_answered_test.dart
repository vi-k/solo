@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/probe_job.dart';

// The answer `JobObserver.onError` is handed says what the job does about the
// error: `answered` when it asks for an answer, `cancellation` when it never
// will because the error is a cancellation, `never` when it never will for
// another reason, and `later` when the outcome that carries the error may
// still be read and nothing is promised.

/// What an operation throws once the cancellation of its job stops it.
final class Stopped implements Exception {
  const Stopped();

  @override
  String toString() => 'Stopped';
}

/// Both hooks in one list, the answer beside each error; answers for every
/// error, so nothing reaches the zone through it.
class Heard extends JobObserver with JobAnswerer {
  final seen = <String>[];

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => seen.add('onError: $error, ${answer.name}');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      seen.add('onUnanswered: $error');
}

/// A [Heard] that also writes down where the job ends.
final class HeardToTheEnd extends Heard {
  @override
  void onFinish(Job<Object?> job) => seen.add('onFinish');
}

/// Both hooks in one list, each line with the key of the job.
final class HeardByKey extends JobObserver with JobAnswerer {
  final seen = <String>[];

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => seen.add('${job.key} onError: ${error.runtimeType}, ${answer.name}');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      seen.add('${job.key} onUnanswered: ${error.runtimeType}');
}

/// A [Heard] that cancels the job from `onError`.
final class Cancelling extends Heard {
  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {
    super.onError(job, error, stackTrace, answer: answer);
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
    required JobErrorAnswer answer,
  }) => seen.add('onError: $error, ${answer.name}');
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

/// A [Heard] that, hearing an error, sets a filter that names everything.
final class Swapping extends Heard {
  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {
    super.onError(job, error, stackTrace, answer: answer);
    Job.isCancellationError = (error) {
      asked.add('late: $error');
      return true;
    };
  }
}

/// A job that hears its cancellation and then fails with [error], the way an
/// operation the cancellation stopped throws; the body waits on a plain
/// future, so the error comes out of a body whose job is cancelled already.
/// Cancelled 10 ms in; returns what reached the zone.
List<String> stoppedAfterCancel(
  Object error,
  JobObserver observer, {
  bool ignore = false,
}) => zoneOf((async) {
  final stop = Completer<void>();
  final job = Job<void>(observer: observer, (ctx) async {
    ctx.onCancel(stop.complete);
    await stop.future;
    Error.throwWithStackTrace(error, StackTrace.current);
  });
  if (ignore) {
    job.ignoreFailure();
  }
  async.elapse(const Duration(milliseconds: 10));
  job.cancel().ignore();
  async.flushTimers();
});

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
}) => zoneOf((async) {
  final job = Job<void>(observer: observer, (ctx) async {
    ctx.onDispose(() => Error.throwWithStackTrace(error, StackTrace.current));
    await ctx.abandonable(() => delay(20));
  });
  async.elapse(const Duration(milliseconds: 10));
  if (cancel) {
    job.cancel().ignore();
  }
  async.flushTimers();
}, caught);

/// Runs a child whose body cancels its own job and then overflows before its
/// start has returned, with nothing to cut the start short; the filter names
/// an overflow when [named]. Returns what reached the zone.
Future<List<String>> overflowedWhole(
  JobObserver observer, {
  required bool named,
}) async {
  Job.isCancellationError = (error) {
    asked.add('${error.runtimeType}');
    return named && error is StackOverflowError;
  };
  final zone = <String>[];
  late Job<void> root;
  runZonedGuarded(() {
    final child = RulesJob<void>((ctx) {
      ctx.breakRule('gave up');
      throw const StackOverflowError();
    }, key: 'child');
    root = Job<void>(key: 'root', observer: observer, (ctx) async {
      try {
        await ctx.run(child);
      } on Object {
        // The child ends cancelled.
      }
    });
  }, (error, _) => zone.add('$error'));
  await root.done.timeout(const Duration(seconds: 5));
  await delay(1);
  return zone;
}

void main() {
  setUp(asked.clear);
  tearDown(() => Job.isCancellationError = null);

  group('answer', () {
    test('an error of ctx.onDispose, the answer right after', () {
      final heard = Heard();
      expect(disposing(StateError('disk full'), heard), isEmpty);
      expect(heard.seen, [
        'onError: Bad state: disk full, answered',
        'onUnanswered: Bad state: disk full',
      ]);
    });

    test('an error of ctx.onDispose with an observer that does not answer', () {
      final listening = Listening();
      expect(disposing(StateError('disk full'), listening), [
        'Bad state: disk full',
      ]);
      expect(listening.seen, ['onError: Bad state: disk full, answered']);
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
      expect(heard.seen, ['onError: Bad state: child, later']);
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
        'onError: Bad state: body, later',
        'onFinish',
        'onUnanswered: Bad state: body',
      ]);
      expect(zone, isEmpty);
    });

    test('a Cancelled a callback throws', () {
      const cancelled = Cancelled('from cleanup');
      final heard = Heard();
      expect(disposing(cancelled, heard), isEmpty);
      expect(heard.seen, ['onError: $cancelled, cancellation']);
    });

    test('a failure of a cancelled job the filter names, asked once', () {
      nameTheStop();
      final heard = Heard();
      expect(disposing(const Stopped(), heard, cancel: true), isEmpty);
      expect(asked, ['Stopped']);
      expect(heard.seen, ['onError: Stopped, cancellation']);
    });

    test(
      'a failure of a cancelled job the filter does not name, asked once',
      () {
        nameTheStop();
        final heard = Heard();
        expect(
          disposing(StateError('disk full'), heard, cancel: true),
          isEmpty,
        );
        expect(asked, ['Bad state: disk full']);
        expect(heard.seen, [
          'onError: Bad state: disk full, answered',
          'onUnanswered: Bad state: disk full',
        ]);
      },
    );

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
        'onError: $cancelled, cancellation',
        'onError: Stopped, cancellation',
        'onError: Bad state: disk full, answered',
        'onUnanswered: Bad state: disk full',
      ]);
    });

    test('JobObserver.all hands the answer to each observer', () {
      final listening = Listening();
      final heard = Heard();
      final zone = zoneOf((async) {
        Job<void>(observer: JobObserver.all([listening, heard]), (ctx) async {
          ctx.onDispose(() => throw StateError('disk full'));
          await delay(10);
          throw StateError('body');
        }).ignoreFailure();
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(listening.seen, [
        'onError: Bad state: body, never',
        'onError: Bad state: disk full, answered',
      ]);
      expect(heard.seen, [
        'onError: Bad state: body, never',
        'onError: Bad state: disk full, answered',
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
        'onError: Stopped, answered',
        'onUnanswered: Stopped',
      ]);
    });

    test(
      'the error of a filter that throws reaches the zone before onError',
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
          'onError: Bad state: disk full, answered',
          'Bad state: disk full',
        ]);
      },
    );

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
        'onError: Bad state: b, answered',
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
        'onError: Bad state: hook failed, answered',
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
        'onError: Bad state: late, answered',
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
      expect(heard.seen, ['onError: Bad state: late, never']);
    });

    test('a Failed handed to a running job: its outcome carries it', () {
      final heard = HeardToTheEnd();
      final zone = zoneOf((async) {
        final job = ProbeJob<int>(observer: heard, (ctx) async {
          await ctx.abandonable(() => delay(20));
          return 1;
        })..launch();
        async.elapse(const Duration(milliseconds: 10));
        job.drop(Failed(StateError('by hand'), StackTrace.current));
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(heard.seen, [
        'onError: Bad state: by hand, later',
        'onFinish',
        'onUnanswered: Bad state: by hand',
      ]);
    });

    test('a source that fails to stop, the answer right after', () {
      final heard = Heard();
      final zone = zoneOf((async) {
        UncancellableByBugJob<int>(
          (ctx) async => 1,
        ).then((ctx, value) => value, observer: heard).cancel().ignore();
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(heard.seen, [
        'onError: Bad state: engine failed to cancel, answered',
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
        'onError: Bad state: source, later',
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
        'onError: Bad state: source, later',
        'onFinish',
        'onUnanswered: Bad state: source',
      ]);
    });
  });

  group('the body of a job that is cancelled already', () {
    test('a failure the filter names: cancellation, asked once', () {
      nameTheStop();
      final heard = HeardToTheEnd();
      expect(stoppedAfterCancel(const Stopped(), heard), isEmpty);
      expect(asked, ['Stopped']);
      expect(heard.seen, ['onError: Stopped, cancellation', 'onFinish']);
    });

    test('a failure the filter does not name: answered, asked once', () {
      nameTheStop();
      final heard = HeardToTheEnd();
      expect(stoppedAfterCancel(StateError('disk full'), heard), isEmpty);
      expect(asked, ['Bad state: disk full']);
      expect(heard.seen, [
        'onError: Bad state: disk full, answered',
        'onFinish',
        'onUnanswered: Bad state: disk full',
      ]);
    });

    test('a failure with no filter: answered', () {
      final heard = HeardToTheEnd();
      expect(stoppedAfterCancel(const Stopped(), heard), isEmpty);
      expect(heard.seen, [
        'onError: Stopped, answered',
        'onFinish',
        'onUnanswered: Stopped',
      ]);
    });

    test(
      'a failure of a job that ignores its failure: never, nobody asked',
      () {
        nameTheStop();
        final heard = HeardToTheEnd();
        expect(
          stoppedAfterCancel(StateError('disk full'), heard, ignore: true),
          isEmpty,
        );
        expect(asked, isEmpty);
        expect(heard.seen, [
          'onError: Bad state: disk full, never',
          'onFinish',
        ]);
      },
    );

    test('a filter set after onError is not asked: the verdict stands', () {
      nameTheStop();
      final heard = Swapping();
      expect(stoppedAfterCancel(StateError('disk full'), heard), isEmpty);
      expect(asked, ['Bad state: disk full']);
      expect(heard.seen, [
        'onError: Bad state: disk full, answered',
        'onUnanswered: Bad state: disk full',
      ]);
    });
  });

  group('later', () {
    test('a failure of a body nobody cancelled: the filter is not asked', () {
      nameTheStop();
      final heard = HeardToTheEnd();
      final zone = zoneOf((async) {
        Job<void>(observer: heard, (ctx) async {
          await delay(10);
          throw const Stopped();
        });
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(asked, isEmpty);
      expect(heard.seen, [
        'onError: Stopped, later',
        'onFinish',
        'onUnanswered: Stopped',
      ]);
    });

    test('left over: a cancellation that lands after the body failed', () {
      nameTheStop();
      final heard = HeardToTheEnd();
      final zone = zoneOf((async) {
        final job = Job<void>(observer: heard, (ctx) async {
          ctx.start(Job.deferred<void>((ctx) => delay(30)));
          await delay(10);
          throw const Stopped();
        });
        async.elapse(const Duration(milliseconds: 20));
        job.cancel().ignore();
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(asked, ['Stopped']);
      // `later` promised nothing: the cancellation covers the failure, and
      // the filter names it. The child inherits the observer and ends first.
      expect(heard.seen, ['onError: Stopped, later', 'onFinish', 'onFinish']);
    });

    test('left over: an onError that cancels a continuation', () {
      nameTheStop();
      final heard = Cancelling();
      final zone = zoneOf((async) {
        Job<int>((ctx) async {
          await delay(10);
          throw const Stopped();
        }).then((ctx, value) => value, observer: heard);
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(asked, ['Stopped']);
      expect(heard.seen, ['onError: Stopped, later']);
    });
  });

  group('never', () {
    test('a continuation of a source answered for already', () {
      final heard = HeardToTheEnd();
      final zone = zoneOf((async) {
        final source = Job<int>((ctx) async {
          await delay(10);
          throw StateError('source');
        });
        async.flushTimers();
        source.then((ctx, value) => value, observer: heard);
        async.flushTimers();
      });
      expect(zone, ['Bad state: source']);
      expect(heard.seen, ['onError: Bad state: source, never', 'onFinish']);
    });

    test('a shared handle of a source answered for already', () {
      final heard = HeardToTheEnd();
      final zone = zoneOf((async) {
        final source = Job<int>((ctx) async {
          await delay(10);
          throw StateError('source');
        });
        async.flushTimers();
        source.shared(observer: heard);
        async.flushTimers();
      });
      expect(zone, ['Bad state: source']);
      expect(heard.seen, ['onError: Bad state: source, never', 'onFinish']);
    });

    test('a Failed handed to a running job that ignores its failure', () {
      final heard = HeardToTheEnd();
      final zone = zoneOf((async) {
        final job =
            ProbeJob<int>(observer: heard, (ctx) async {
                await ctx.abandonable(() => delay(20));
                return 1;
              })
              ..ignoreFailure()
              ..launch();
        async.elapse(const Duration(milliseconds: 10));
        job.drop(Failed(StateError('by hand'), StackTrace.current));
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(heard.seen, ['onError: Bad state: by hand, never', 'onFinish']);
    });
  });

  test(
    'notifyObserver, the door of an engine, says later even when ignored',
    () {
      final heard = Heard();
      final zone = zoneOf((async) {
        ProbeJob<int>(observer: heard, (ctx) async => 1)
          ..ignoreFailure()
          ..announce(StateError('engine'), StackTrace.current);
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(heard.seen, ['onError: Bad state: engine, later']);
    },
  );

  test('a torn start of a cancelled job whose body overflowed', () async {
    nameTheStop();
    final heard = HeardByKey();
    var scheduled = 0;
    final zone = <String>[];
    late Job<void> root;
    runZonedGuarded(() {
      // The body cancels its own job and then overflows, before its first
      // `await`; the zone has no stack for what the routine waits for
      // next, and the start is cut short. The core ends such a job
      // without an answer to the overflow: the body of the parent heard it.
      final child = RulesJob<void>((ctx) {
        ctx.breakRule('gave up');
        throw const StackOverflowError();
      }, key: 'child');
      root = Job<void>(key: 'root', observer: heard, (ctx) async {
        try {
          await runZoned(
            () => ctx.run(child),
            zoneSpecification: ZoneSpecification(
              scheduleMicrotask: (self, parent, zone, callback) {
                if (scheduled++ == 0) {
                  throw const StackOverflowError();
                }
                parent.scheduleMicrotask(zone, callback);
              },
            ),
          );
        } on Object {
          // The overflow the start throws.
        }
        await delay(1);
      });
    }, (error, _) => zone.add('$error'));
    await root.done.timeout(const Duration(seconds: 5));
    await delay(1);
    expect(zone, isEmpty);
    expect(asked, isEmpty, reason: 'an ignored failure is never put to it');
    // Told `later`, not `answered`: where the body was caught nothing could
    // tell an overflow that cuts the start short from one that does not.
    expect(heard.seen, ['child onError: StackOverflowError, later']);
  });

  test('a whole start of a cancelled job whose body overflowed', () async {
    final heard = HeardByKey();
    expect(await overflowedWhole(heard, named: false), isEmpty);
    // Told `later` where the body was caught, the filter asked once the job
    // has ended, and the answer follows.
    expect(asked, ['StackOverflowError']);
    expect(heard.seen, [
      'child onError: StackOverflowError, later',
      'child onUnanswered: StackOverflowError',
    ]);
  });

  test(
    'a whole start of a cancelled job whose body overflowed, named',
    () async {
      final heard = HeardByKey();
      expect(await overflowedWhole(heard, named: true), isEmpty);
      expect(asked, ['StackOverflowError']);
      expect(heard.seen, ['child onError: StackOverflowError, later']);
    },
  );

  test('the filter of cancellation errors is left as it was found', () {
    expect(Job.isCancellationError, isNull);
  });
}
