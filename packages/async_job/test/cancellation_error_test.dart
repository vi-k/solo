@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/probe_job.dart';

// `Job.isCancellationError` names the errors an operation throws because
// the cancellation of its job stopped it. The job answers for every failure
// of the body of a job that ends `Cancelled`, and the filter keeps the named
// ones out of that answer: `onError` hears them, nobody is asked to answer
// for them. It is asked about the failures of a job that has accepted a
// cancellation and about nothing else.

/// What an operation throws once the cancellation of its job stops it.
final class Stopped implements Exception {
  const Stopped();

  @override
  String toString() => 'Stopped';
}

/// Both hooks in one list, in order; with [answers] it answers and stops the
/// error, without it `super` sends the error on.
final class Heard extends JobObserver with JobAnswerer {
  final bool answers;
  final seen = <String>[];

  Heard({this.answers = false});

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      seen.add('onError: $error');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    seen.add('onUnanswered: $error');
    if (!answers) {
      super.onUnanswered(job, error, stackTrace);
    }
  }
}

/// Hears `onError` and answers for nothing.
final class Listening extends JobObserver {
  final seen = <String>[];

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      seen.add('onError: $error');
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

/// A job whose operation throws [error] 20 ms in, the way an operation
/// stopping at a token of the job does.
Job<void> stopping(Object error, {JobObserver? observer}) => Job<void>(
      observer: observer,
      (ctx) => ctx.join(() async {
        await delay(20);
        Error.throwWithStackTrace(error, StackTrace.current);
      }),
    );

/// Makes the job with [make], cancels it 10 ms in unless [cancel] is
/// false, and returns what reached the zone.
List<String> run(Job<void> Function() make, {bool cancel = true}) =>
    zoneOf((async) {
      final job = make();
      async.elapse(const Duration(milliseconds: 10));
      if (cancel) {
        job.cancel().ignore();
      }
      async.flushTimers();
    });

void main() {
  setUp(asked.clear);
  tearDown(() => Job.isCancellationError = null);

  group('what the filter is asked about', () {
    test('a failure of a cancelled job, and no further than onError', () {
      nameTheStop();
      final heard = Heard();
      expect(run(() => stopping(const Stopped(), observer: heard)), isEmpty);
      expect(asked, ['Stopped']);
      expect(heard.seen, ['onError: Stopped']);
    });

    test('a failure thrown before the cancellation, asked about after it', () {
      nameTheStop();
      final heard = Heard();
      late Job<void> job;
      final zone = zoneOf((async) {
        job = Job<void>(observer: heard, (ctx) async {
          // The body fails at 20 ms and the job waits for this child until
          // 50 ms; the cancellation comes at 30 ms, in between.
          ctx.run(Job.deferred<void>((ctx) => delay(50))).ignore();
          await delay(20);
          throw const Stopped();
        });
        async.elapse(const Duration(milliseconds: 30));
        job.cancel().ignore();
        async.flushTimers();
      });
      expect('${job.outcome}', 'Cancelled(manual)');
      expect(asked, ['Stopped']);
      expect(heard.seen, ['onError: Stopped']);
      expect(zone, isEmpty);
    });

    test('a child it names: the parent gets Cancelled, nobody answers', () {
      nameTheStop();
      final heard = Heard();
      final caught = <Object>[];
      final zone = run(
        () => Job<void>((ctx) async {
          try {
            await ctx.run(
              Job.deferred<void>(
                observer: heard,
                (ctx) => ctx.join(() async {
                  await delay(20);
                  throw const Stopped();
                }),
              ),
            );
          } on Cancelled catch (cancelled) {
            caught.add(cancelled);
          }
        }),
      );
      expect(caught, [isA<Cancelled>()]);
      expect(asked, ['Stopped']);
      expect(heard.seen, ['onError: Stopped']);
      expect(zone, isEmpty);
    });

    test('a failure it does not name goes on to the answer', () {
      nameTheStop();
      final heard = Heard();
      final zone = run(
        () => stopping(StateError('database locked'), observer: heard),
      );
      expect(asked, ['Bad state: database locked']);
      expect(heard.seen, [
        'onError: Bad state: database locked',
        'onUnanswered: Bad state: database locked',
      ]);
      expect(zone, ['Bad state: database locked']);
    });

    test('an answering observer is not asked about a named one', () {
      nameTheStop();
      final heard = Heard(answers: true);
      expect(run(() => stopping(const Stopped(), observer: heard)), isEmpty);
      expect(heard.seen, ['onError: Stopped']);
    });

    test('a failure of a job nobody cancelled is not asked about', () {
      nameTheStop();
      final listening = Listening();
      final zone = run(
        () => stopping(const Stopped(), observer: listening),
        cancel: false,
      );
      expect(asked, isEmpty);
      expect(listening.seen, ['onError: Stopped']);
      expect(zone, ['Stopped']);
    });

    test('nor is an error with no outcome of a job nobody cancelled', () {
      nameTheStop();
      final zone = run(
        () => Job<void>((ctx) async {
          ctx.onDispose(() => throw const Stopped());
        }),
        cancel: false,
      );
      expect(asked, isEmpty);
      expect(zone, ['Stopped']);
    });

    test('a late failure of a job an engine ended Cancelled by hand', () {
      nameTheStop();
      late ProbeJob<void> job;
      final zone = zoneOf((async) {
        job = ProbeJob<void>((ctx) async {
          ctx.unattended(() async {
            await delay(20);
            throw const Stopped();
          });
          await ctx.abandonable(() => delay(100));
        })
          ..launch();
        async.elapse(const Duration(milliseconds: 10));
        job.drop(const Cancelled('engine'));
        async.flushTimers();
      });
      expect(job.isCancelled, isTrue);
      expect(asked, ['Stopped']);
      expect(zone, isEmpty);
    });

    test('nor is a job that refused the cancellation', () {
      nameTheStop();
      final zone = run(
        () => Job<void>(
          cancellable: false,
          (ctx) => ctx.join(() async {
            await delay(20);
            throw const Stopped();
          }),
        ),
      );
      expect(asked, isEmpty);
      expect(zone, ['Stopped']);
    });

    test('a Cancelled never: an envelope is walked failure by failure', () {
      nameTheStop();
      final heard = Heard();
      final zone = run(
        () => Job<void>(observer: heard, (ctx) async {
          await ctx.join(() => delay(20));
        }),
      );
      expect(zone, isEmpty);
      expect(asked, isEmpty, reason: 'the job gave up, nothing failed');

      final enveloped = Heard();
      final envelopeZone = run(
        () => Job<void>(observer: enveloped, (ctx) async {
          try {
            await ctx.join(() => delay(20));
          } on Cancelled catch (cancelled, stackTrace) {
            throw ParallelWaitError<List<Object?>, List<AsyncError?>>(
              [null, null, null],
              [
                AsyncError(cancelled, stackTrace),
                AsyncError(const Stopped(), stackTrace),
                AsyncError(StateError('database locked'), stackTrace),
              ],
            );
          }
        }),
      );
      expect(asked, ['Stopped', 'Bad state: database locked']);
      expect(enveloped.seen, [
        'onError: Stopped',
        'onError: Bad state: database locked',
        'onUnanswered: Bad state: database locked',
      ]);
      expect(envelopeZone, ['Bad state: database locked']);
    });

    test('the errors no outcome carries of a cancelled job', () {
      nameTheStop();
      final heard = Heard();
      final zone = run(
        () => Job<void>(observer: heard, (ctx) async {
          ctx
            ..onCancel(() {
              throw const Stopped();
            })
            ..onDispose(() {
              throw const Stopped();
            })
            ..unattended(() async {
              await delay(15);
              throw const Stopped();
            });
          await ctx.abandonable(() async {
            await delay(30);
            throw const Stopped();
          });
        }),
      );
      expect(asked, ['Stopped', 'Stopped', 'Stopped', 'Stopped']);
      expect(heard.seen, List.filled(4, 'onError: Stopped'));
      expect(zone, isEmpty);
    });
  });

  group('what the filter leaves alone', () {
    test('the outcome', () {
      nameTheStop();
      late Job<void> job;
      run(() => job = stopping(const Stopped()));
      expect('${job.outcome}', 'Cancelled(manual)');

      late Job<void> failed;
      run(() => failed = stopping(const Stopped()), cancel: false);
      expect('${failed.outcome}', 'Failed(Stopped)');
    });

    test('ignoreFailure takes the answer away before the filter is asked', () {
      nameTheStop();
      final heard = Heard();
      final zone = run(
        () => stopping(StateError('database locked'), observer: heard)
          ..ignoreFailure(),
      );
      expect(asked, isEmpty);
      expect(heard.seen, ['onError: Bad state: database locked']);
      expect(zone, isEmpty);
    });

    test('ignoreFailure on a parent silences no failure of a child', () {
      final zone = run(
        () => Job<void>((ctx) async {
          await ctx.run(
            Job.deferred<void>(
              (ctx) => ctx.join(() async {
                await delay(20);
                throw StateError('database locked');
              }),
            ),
          );
        })
          ..ignoreFailure(),
      );
      expect(zone, ['Bad state: database locked']);
    });

    test('every observer of JobObserver.all hears it, none answers', () {
      nameTheStop();
      final listening = Listening();
      final heard = Heard();
      expect(
        run(
          () => stopping(
            const Stopped(),
            observer: JobObserver.all([listening, heard]),
          ),
        ),
        isEmpty,
      );
      expect(listening.seen, ['onError: Stopped']);
      expect(heard.seen, ['onError: Stopped']);
    });
  });

  group('the filter itself', () {
    test('is read when the answer is asked for', () {
      final zone = zoneOf((async) {
        final job = stopping(const Stopped());
        async.elapse(const Duration(milliseconds: 10));
        job.cancel().ignore();
        nameTheStop();
        async.flushTimers();
      });
      expect(zone, isEmpty);
      expect(asked, ['Stopped']);
    });

    test(
        'one that throws hands its error to the zone the job was created '
        'in, and the failure goes on', () {
      Job.isCancellationError = (error) => throw StateError('filter failed');
      final heard = Heard();
      final zone = run(() => stopping(const Stopped(), observer: heard));
      expect(zone, ['Bad state: filter failed', 'Stopped']);
      expect(heard.seen, ['onError: Stopped', 'onUnanswered: Stopped']);
    });

    test(
        'asked from unattended work, its error still goes to the zone the '
        'job was created in', () {
      Job.isCancellationError = (error) => throw StateError('filter failed');
      final heard = Heard(answers: true);
      final zone = run(
        () => Job<void>(observer: heard, (ctx) async {
          ctx.unattended(() async {
            await delay(15);
            throw const Stopped();
          });
          await ctx.join(() => delay(20));
        }),
      );
      expect(zone, ['Bad state: filter failed']);
      expect(heard.seen, ['onError: Stopped', 'onUnanswered: Stopped']);
    });

    test('a Cancelled it throws is dropped', () {
      Job.isCancellationError = (error) => throw const Cancelled('filter');
      final heard = Heard(answers: true);
      expect(run(() => stopping(const Stopped(), observer: heard)), isEmpty);
      expect(heard.seen, ['onError: Stopped', 'onUnanswered: Stopped']);
    });
  });

  group('the debug channel', () {
    List<String> printed(Object error) {
      final lines = <String>[];
      Job.debug = lines.add;
      try {
        run(() => stopping(error));
      } finally {
        Job.debug = null;
      }
      return lines;
    }

    test('says the error went no further', () {
      nameTheStop();
      final lines = printed(const Stopped());
      expect(
        lines,
        contains('Job() kept a cancellation error out of the answer: Stopped'),
      );
      expect(
        lines.where((line) => line.contains('nobody answered for')),
        isEmpty,
      );
    });

    test('says once that nobody answered for what is left', () {
      nameTheStop();
      final lines = printed(StateError('database locked'));
      expect(
        lines.where((line) => line.contains('nobody answered for')),
        ['Job() error nobody answered for: Bad state: database locked'],
      );
      expect(
        lines.where((line) => line.contains('kept a cancellation error')),
        isEmpty,
      );
    });

    test('says it once for an envelope of two', () {
      nameTheStop();
      final lines = printed(
        ParallelWaitError<List<Object?>, List<AsyncError?>>(
          [null, null],
          [
            AsyncError(StateError('database locked'), StackTrace.empty),
            AsyncError(StateError('disk full'), StackTrace.empty),
          ],
        ),
      );
      expect(
        lines.where((line) => line.contains('nobody answered for')),
        hasLength(1),
      );
      expect(
        lines.where((line) => line.contains('went to the zone')),
        hasLength(2),
      );
    });
  });

  test('the filter of cancellation errors is left as it was found', () {
    expect(Job.isCancellationError, isNull);
    expect(Job.debug, isNull);
  });
}
