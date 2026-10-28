@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/journal.dart';
import 'support/run_solo.dart';
import 'support/test_solo.dart';
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

  test('unattended work throws the string of an observed failure', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      var calls = 0;
      _inZone(errors, () {
        final job = solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: (error) => ++calls == 1,
          (ctx) async {
            ctx.unattended(() async {
              await delay(10);
              // ignore: only_throw_errors
              throw 'offline';
            });
            // ignore: only_throw_errors
            throw 'offline';
          },
        );
        unawaited(job.value.then<void>((_) {}, onError: (Object _) {}));
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(calls, 2);
      expect(journal.take(), [
        '[load] started',
        '[load] error offline (never)',
        '[load] finished Failed(offline)',
        '[load] error offline (answered)',
        '[load] unanswered offline',
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

  group('children', () {
    test('a ctx.child started and left fails with an expected error', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          solo.enqueue<TestState, void>(
            key: 'load',
            isExpectedError: _isApiError,
            (ctx) async {
              ctx.start(
                ctx.child(key: 'kid', (c) async => throw const ApiError()),
              );
            },
          );
        });
        async.flushTimers();
        expect(errors, isEmpty);
        expect(journal.take(), [
          '[load] started',
          '> [kid] started',
          '> [kid] error ApiError (never)',
          '> [kid] finished Failed(ApiError)',
          '[load] finished Done(null)',
        ]);
      });
    });

    test('two branches of runAll fail with expected errors', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          solo.enqueue<TestState, void>(
            key: 'load',
            isExpectedError: _isApiError,
            ifFailed: (state, error, stackTrace) => const Disposed(),
            (ctx) async {
              await ctx.runAll([
                ctx.child<void>(key: 'a', (c) async => throw const ApiError()),
                ctx.child<void>(key: 'b', (c) async => throw const ApiError()),
              ]);
            },
          );
        });
        async.flushTimers();
        expect(errors, isEmpty);
        expect(solo.currentState, const Disposed());
        expect(journal.take(), [
          '[load] started',
          '> [a] started',
          '> [b] started',
          '> [a] error ApiError (never)',
          '> [b] error ApiError (never)',
          '> [a] finished Failed(ApiError)',
          '> [b] finished Cancelled(sibling)',
          '[load] error ApiError (never)',
          'state: ${const Disposed()}',
          '[load] finished Failed(ApiError)',
        ]);
      });
    });

    test('each inside a ctx.child fails with an expected error', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        final source = StreamController<int>();
        addTearDown(source.close);
        _inZone(errors, () {
          solo.enqueue<TestState, void>(
            key: 'load',
            isExpectedError: _isApiError,
            (ctx) async {
              ctx.start(
                ctx.child<void>(key: 'kid', (c) async {
                  c.each(source.stream, (_, _) {
                    throw const ApiError();
                  });
                }),
              );
            },
          );
        });
        async.flushMicrotasks();
        source.add(1);
        async.flushTimers();
        expect(errors, isEmpty);
        expect(journal.take(), [
          '[load] started',
          '> [kid] started',
          '>> [null: each] started',
          '>> [null: each] error ApiError (never)',
          '>> [null: each] finished Failed(ApiError)',
          '> [kid] finished Done(null)',
          '[load] finished Done(null)',
        ]);
      });
    });

    test('a ctx.child made by one job and started by another', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          late final SoloJob<void> kid;
          solo
            ..enqueue<TestState, void>(
              key: 'maker',
              isExpectedError: _isApiError,
              (ctx) async {
                kid = ctx.child(
                  key: 'kid',
                  (c) async => throw const ApiError(),
                );
              },
            )
            ..enqueue<TestState, void>(key: 'starter', (ctx) async {
              ctx.start(kid);
            });
        });
        async.flushTimers();
        expect(errors, isEmpty);
        expect(journal.take(), [
          '[maker] started',
          '[maker] finished Done(null)',
          '[starter] started',
          '> [kid] started',
          '> [kid] error ApiError (later)',
          '> [kid] finished Failed(ApiError)',
          '[starter] finished Done(null)',
          '> [kid] unanswered ApiError',
        ]);
      });
    });

    test('a child of job(...) with a predicate of its own', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          solo.enqueue<TestState, void>(
            key: 'load',
            isExpectedError: _isApiError,
            (ctx) async {
              ctx.start(
                solo.job<TestState, void>(
                  key: 'kid',
                  isExpectedError: (e) => e is StateError,
                  (c) async => throw const ApiError(),
                ),
              );
            },
          );
        });
        async.flushTimers();
        expect(errors, isEmpty);
        expect(journal.take(), [
          '[load] started',
          '> [kid] started',
          '> [kid] error ApiError (later)',
          '> [kid] finished Failed(ApiError)',
          '[load] finished Done(null)',
          '> [kid] unanswered ApiError',
        ]);
      });
    });

    test('a child of job(...) without a predicate', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          solo.enqueue<TestState, void>(
            key: 'load',
            isExpectedError: _isApiError,
            (ctx) async {
              ctx.start(
                solo.job<TestState, void>(
                  key: 'kid',
                  (c) async => throw const ApiError(),
                ),
              );
            },
          );
        });
        async.flushTimers();
        expect(errors, isEmpty);
        expect(journal.take(), [
          '[load] started',
          '> [kid] started',
          '> [kid] error ApiError (never)',
          '> [kid] finished Failed(ApiError)',
          '[load] finished Done(null)',
        ]);
      });
    });

    test('a child under a parent without a predicate', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          solo.enqueue<TestState, void>(key: 'load', (ctx) async {
            ctx.start(
              ctx.child(key: 'kid', (c) async => throw const ApiError()),
            );
          });
        });
        async.flushTimers();
        expect(errors, isEmpty);
        expect(journal.take(), [
          '[load] started',
          '> [kid] started',
          '> [kid] error ApiError (later)',
          '> [kid] finished Failed(ApiError)',
          '[load] finished Done(null)',
          '> [kid] unanswered ApiError',
        ]);
      });
    });
  });

  group('listeners', () {
    test('a whenFinished listener throws an ApiError', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          solo
              .enqueue<TestState, void>(
                key: 'load',
                isExpectedError: _isApiError,
                (ctx) async {},
              )
              .whenFinished((_) => throw const ApiError());
        });
        async.flushTimers();
        expect(errors, isEmpty);
        expect(journal.take(), [
          '[load] started',
          '[load] finished Done(null)',
          '[load] error ApiError (answered)',
          '[load] unanswered ApiError',
        ]);
      });
    });

    test('a whenCancelled listener throws an ApiError', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          final job = solo.enqueue<TestState, void>(
            key: 'load',
            isExpectedError: _isApiError,
            (ctx) async {
              await delay(10);
            },
          )..whenCancelled((_) => throw const ApiError());
          async.flushMicrotasks();
          unawaited(job.cancel());
        });
        async.flushTimers();
        expect(errors, isEmpty);
        expect(journal.take(), [
          '[load] started',
          '[load] error ApiError (answered)',
          '[load] unanswered ApiError',
          '[load] finished Cancelled(manual)',
        ]);
      });
    });

    test('a listener throws a ParallelWaitError of an ApiError', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          solo
              .enqueue<TestState, void>(
                key: 'load',
                isExpectedError: _isApiError,
                (ctx) async {},
              )
              .whenFinished((_) {
                throw ParallelWaitError<List<Object?>, List<AsyncError?>>(
                  [null],
                  [AsyncError(const ApiError(), StackTrace.empty)],
                );
              });
        });
        async.flushTimers();
        expect(errors, isEmpty);
        expect(journal.take(), [
          '[load] started',
          '[load] finished Done(null)',
          '[load] error ApiError (answered)',
          '[load] unanswered ApiError',
        ]);
      });
    });

    test('a listener rethrows the expected failure of its job', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          solo
              .enqueue<TestState, void>(
                key: 'load',
                isExpectedError: _isApiError,
                (ctx) async => throw const ApiError(),
              )
              .whenFinished((outcome) {
                if (outcome case Failed(:final error, :final stackTrace)) {
                  Error.throwWithStackTrace(error, stackTrace);
                }
              });
        });
        async.flushTimers();
        expect(errors, isEmpty);
        expect(journal.take(), [
          '[load] started',
          '[load] error ApiError (never)',
          '[load] finished Failed(ApiError)',
          '[load] error ApiError (answered)',
          '[load] unanswered ApiError',
        ]);
      });
    });

    test('a listener error while another one is answered for', () {
      fakeAsync((async) {
        final journal = JournalObserver(answers: true);
        Solo.observer = journal;
        Solo.unansweredHandler = journal.answerForErrors;
        final solo = _Nesting();
        try {
          final errors = <String>[];
          _inZone(errors, () {
            final job = solo.enqueue<TestState, void>(
              key: 'load',
              isExpectedError: _isApiError,
              (ctx) async {},
            );
            solo.watched = job;
            job.whenFinished((_) => throw const ApiError());
          });
          async.flushTimers();
          expect(errors, isEmpty);
          expect(journal.take(), [
            '[load] started',
            '[load] finished Done(null)',
            '[load] error ApiError (answered)',
            '[load] error Bad state: inner (answered)',
            '[load] unanswered Bad state: inner',
            '[load] unanswered ApiError',
          ]);
        } finally {
          solo.close();
          async.flushTimers();
          Solo.observer = null;
          Solo.unansweredHandler = null;
        }
      });
    });

    test('a listener of a job without a predicate throws', () {
      runSolo(answers: true, (solo, journal, async) {
        final errors = <String>[];
        _inZone(errors, () {
          solo
              .enqueue<TestState, void>(key: 'load', (ctx) async {})
              .whenFinished((_) => throw const ApiError());
        });
        async.flushTimers();
        expect(errors, isEmpty);
        expect(journal.take(), [
          '[load] started',
          '[load] finished Done(null)',
          '[load] error ApiError (answered)',
          '[load] unanswered ApiError',
        ]);
      });
    });
  });
}

/// A controller whose [onError] registers a failing listener on [watched] at
/// the first error it hears.
final class _Nesting extends Solo<TestState> with OpenSolo<TestState> {
  _Nesting() : super(const Initial());

  Job<Object?>? watched;
  var _registered = false;

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {
    if (_registered) return;
    _registered = true;
    watched?.whenFinished((_) => throw StateError('inner'));
  }
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
