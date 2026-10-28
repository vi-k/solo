@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

/// An error the jobs of these tests expect.
final class ApiError implements Exception {
  const ApiError();

  @override
  String toString() => 'ApiError';
}

bool _isApiError(Object error) => error is ApiError;

void main() {
  tearDown(() {
    Job.isCancellationError = null;
    Solo.debug = null;
  });

  test('an expected failure nobody observed', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: (error) => error is ApiError,
          (ctx) async => throw const ApiError(),
        );
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (never)',
        '[load] finished Failed(ApiError)',
      ]);
    });
  });

  test('a bug in a job that names its expected errors', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: _isApiError,
          (ctx) async => throw StateError('bug'),
        );
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[load] started',
        '[load] error Bad state: bug (later)',
        '[load] finished Failed(Bad state: bug)',
        '[load] unanswered Bad state: bug',
      ]);
    });
  });

  test('a failure observed through value', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      final caught = <Object>[];
      _inZone(errors, () {
        final job = solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: _isApiError,
          (ctx) async => throw const ApiError(),
        );
        Future<void> watch() async {
          try {
            await job.value;
          } on Object catch (error) {
            caught.add(error);
          }
        }

        unawaited(watch());
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(caught, [isA<ApiError>()]);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (never)',
        '[load] finished Failed(ApiError)',
      ]);
    });
  });

  test('an expected failure and a bug in one ParallelWaitError', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: _isApiError,
          (ctx) async {
            await (
              Future<void>.error(const ApiError()),
              Future<void>.error(StateError('bug')),
            ).wait;
          },
        );
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (never)',
        '[load] error Bad state: bug (later)',
        contains('[load] finished Failed(ParallelWaitError'),
        '[load] unanswered Bad state: bug',
      ]);
    });
  });

  test('an expected failure of the body after a cancel', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        final job = solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: _isApiError,
          (ctx) async {
            await delay(10);
            throw const ApiError();
          },
        );
        async.flushMicrotasks();
        unawaited(job.cancel());
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (never)',
        '[load] finished Cancelled(manual)',
      ]);
    });
  });

  test('an expected late failure of an abandonable call', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        final job = solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: _isApiError,
          (ctx) async {
            await ctx.abandonable(() async {
              await delay(10);
              throw const ApiError();
            });
          },
        );
        async.flushMicrotasks();
        unawaited(job.cancel());
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[load] started',
        '[load] finished Cancelled(manual)',
        '[load] error ApiError (never)',
      ]);
    });
  });

  test('an expected failure of a disposer', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: _isApiError,
          (ctx) async {
            ctx.onDispose(() => throw const ApiError());
          },
        );
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (never)',
        '[load] finished Done(null)',
      ]);
    });
  });

  test('an expected failure after keepWhile revoked the correction', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.enqueue<TestState, void>(
          key: 'load',
          keepWhile: (state) => state is! Disposed,
          ifFailed: (state, error, stackTrace) => const Preparing(),
          isExpectedError: _isApiError,
          (ctx) async {
            await delay(10);
            throw const ApiError();
          },
        );
        async.flushMicrotasks();
        solo.externalSetState(const Disposed());
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(solo.currentState, const Disposed());
      expect(journal.take(), [
        '[load] started',
        'state: ${const Disposed()}',
        '[load] error ApiError (never)',
        '[load] finished Cancelled(rules: keepWhile)',
      ]);
    });
  });

  test('a job without ifFailed names its expected errors', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: _isApiError,
          (ctx) async => throw const ApiError(),
        );
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (never)',
        '[load] finished Failed(ApiError)',
      ]);
    });
  });

  test('a predicate that throws', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: (error) => throw StateError('predicate'),
          (ctx) async => throw const ApiError(),
        );
      });
      async.flushTimers();
      expect(errors, ['Bad state: predicate']);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (later)',
        '[load] finished Failed(ApiError)',
        '[load] unanswered ApiError',
      ]);
    });
  });

  test('a predicate that throws inside unattended work', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      var asked = 0;
      _inZone(errors, () {
        final job = solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: (error) {
            asked++;
            throw StateError('predicate');
          },
          (ctx) async {
            ctx.unattended(() async {
              await ctx.abandonable(() async {
                await delay(10);
                throw const ApiError();
              });
            });
            await delay(20);
          },
        );
        async.flushMicrotasks();
        unawaited(job.cancel());
      });
      async.flushTimers();
      expect(errors, ['Bad state: predicate']);
      expect(asked, 1);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (answered)',
        '[load] unanswered ApiError',
        '[load] finished Cancelled(manual)',
      ]);
    });
  });

  test('an impure predicate', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      var calls = 0;
      _inZone(errors, () {
        solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: (error) => ++calls == 1,
          (ctx) async => throw const ApiError(),
        );
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(calls, 1);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (never)',
        '[load] finished Failed(ApiError)',
      ]);
    });
  });

  test('a string thrown as an expected error', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: (error) => error is String,
          // ignore: only_throw_errors
          (ctx) async => throw 'offline',
        );
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[load] started',
        '[load] error offline (never)',
        '[load] finished Failed(offline)',
      ]);
    });
  });

  test('an error Job.isCancellationError names', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      var asked = 0;
      Job.isCancellationError = _isApiError;
      _inZone(errors, () {
        final job = solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: (error) {
            asked++;
            return true;
          },
          (ctx) async {
            await delay(10);
            throw const ApiError();
          },
        );
        async.flushMicrotasks();
        unawaited(job.cancel());
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(asked, 0);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (cancellation)',
        '[load] finished Cancelled(manual)',
      ]);
    });
  });

  test('an expected failure of a collect group', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo
            .collect<TestState, int, void>(
              key: 'load',
              isExpectedError: _isApiError,
              (ctx, events) async => throw const ApiError(),
            )
            .add(1);
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (never)',
        '[load] finished Failed(ApiError)',
      ]);
    });
  });

  test('an expected failure of an accumulate group', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo
            .accumulate<TestState, int, void>(
              key: 'load',
              merge: (accumulated, incoming) => accumulated + incoming,
              isExpectedError: _isApiError,
              (ctx, value) async => throw const ApiError(),
            )
            .add(1);
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (never)',
        '[load] finished Failed(ApiError)',
      ]);
    });
  });

  test('an expected failure under Solo.debug', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      final lines = <String>[];
      Solo.debug = lines.add;
      _inZone(errors, () {
        solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: _isApiError,
          (ctx) async => throw const ApiError(),
        );
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(
        lines,
        contains('Job(load) expected ApiError: nobody is asked to answer'),
      );
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (never)',
        '[load] finished Failed(ApiError)',
      ]);
    });
  });

  test(
    'an expected failure of a droppable job continued with shared and dropped',
    () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          solo
              .enqueue<TestState, void>(
                key: 'load',
                policy: Policy.droppable,
                isExpectedError: _isApiError,
                (ctx) async => throw const ApiError(),
              )
              .shared();
        });
        async.flushTimers();
        expect(errors, ['ApiError']);
        expect(journal.take(), [
          '[load] started',
          '[load] error ApiError (never)',
          '[load] finished Failed(ApiError)',
        ]);
      });
    },
  );
}

/// Runs [body] in a zone that collects uncaught errors into [errors].
///
/// A job remembers the zone it was created in, so a job created inside
/// [body] reports its unobserved failure here instead of failing the test.
void _inZone(List<String> errors, void Function() body) {
  Zone.current
      .fork(
        specification: ZoneSpecification(
          handleUncaughtError: (self, parent, zone, error, stackTrace) =>
              errors.add('$error'),
        ),
      )
      .run<void>(body);
}
