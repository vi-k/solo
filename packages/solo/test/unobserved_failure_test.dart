@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('a failure nobody observed reaches the zone', () {
    runSolo((solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.run<TestState, void>(key: 'bad', (ctx) async {
          throw StateError('boom');
        });
      });
      async.flushMicrotasks();
      expect(errors, ['Bad state: boom']);
      expect(journal.take(), [
        '[bad] started',
        '[bad] error Bad state: boom',
        '[bad] finished Failed(Bad state: boom)',
      ]);
    });
  });

  test('awaiting done before the job finishes keeps the zone quiet', () {
    runSolo((solo, journal, async) {
      final errors = <String>[];
      Outcome<void>? outcome;
      _inZone(errors, () {
        final job = solo.run<TestState, void>(key: 'bad', (ctx) async {
          await delay(10);
          throw StateError('boom');
        });
        Future<void> watch() async => outcome = await job.done;
        unawaited(watch());
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(outcome, isA<Failed>());
    });
  });

  test('catching the error of value keeps the zone quiet', () {
    runSolo((solo, journal, async) {
      final errors = <String>[];
      Object? caught;
      _inZone(errors, () {
        final job = solo.run<TestState, void>(key: 'bad', (ctx) async {
          throw StateError('boom');
        });
        Future<void> watch() async {
          try {
            await job.value;
          } on Object catch (error) {
            caught = error;
          }
        }

        unawaited(watch());
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(caught, isA<StateError>());
    });
  });

  test('ignore keeps the zone quiet', () {
    runSolo((solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.run<TestState, void>(key: 'bad', (ctx) async {
          throw StateError('boom');
        }).ignore();
      });
      async.flushMicrotasks();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[bad] started',
        '[bad] error Bad state: boom',
        '[bad] finished Failed(Bad state: boom)',
      ]);
    });
  });

  test('a child failure the parent never looks at reaches the zone', () {
    runSolo((solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.run<TestState, void>(key: 'parent', (ctx) async {
          ctx.run(
            solo.job<TestState, void>(key: 'child', (ctx) async {
              throw StateError('boom');
            }),
          );
        });
      });
      async.flushTimers();
      expect(errors, ['Bad state: boom']);
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        '> [child] error Bad state: boom',
        '> [child] finished Failed(Bad state: boom)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  test('a child failure the parent handles stays out of the zone', () {
    runSolo((solo, journal, async) {
      final errors = <String>[];
      Object? caught;
      _inZone(errors, () {
        solo.run<TestState, void>(key: 'parent', (ctx) async {
          final child = solo.job<TestState, void>(key: 'child', (ctx) async {
            throw StateError('boom');
          });
          try {
            await ctx.run(child).value;
          } on Object catch (error) {
            caught = error;
          }
        });
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(caught, isA<StateError>());
      expect(journal.take(), [
        '[parent] started',
        '> [child] started',
        '> [child] error Bad state: boom',
        '> [child] finished Failed(Bad state: boom)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  test('a body that throws after cancellation stays out of the zone', () {
    runSolo((solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.run<TestState, void>(key: 'job', (ctx) async {
          await delay(100);
          throw StateError('late');
        });
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.current!.cancel();
      async.elapse(const Duration(milliseconds: 50));
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[job] started',
        '[job] error Bad state: late',
        '[job] finished Cancelled(manual)',
      ]);
    });
  });

  test('close waiting for a failing job is not observation', () {
    runSolo((solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.run<TestState, void>(
          key: 'job',
          cancellable: Cancellable.never,
          (ctx) async {
            await delay(10);
            throw StateError('boom');
          },
        );
      });
      async.flushMicrotasks();
      solo.close();
      async.flushTimers();
      expect(errors, ['Bad state: boom']);
      expect(journal.take(), [
        '[job] started',
        '[job] error Bad state: boom',
        '[job] finished Failed(Bad state: boom)',
        'closed',
      ]);
    });
  });

  test('cancel waiting for a failing job is not observation', () {
    runSolo((solo, journal, async) {
      final errors = <String>[];
      late Job<void> job;
      _inZone(errors, () {
        job = solo.run<TestState, void>(
          key: 'job',
          cancellable: Cancellable.never,
          (ctx) async {
            await delay(10);
            throw StateError('boom');
          },
        );
      });
      async.flushMicrotasks();
      job.cancel();
      async.flushTimers();
      expect(errors, ['Bad state: boom']);
      expect(journal.take(), [
        '[job] started',
        '[job] error Bad state: boom',
        '[job] finished Failed(Bad state: boom)',
      ]);
    });
  });
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
