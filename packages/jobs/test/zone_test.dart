@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';

void main() {
  test('an unobserved failure goes to the zone that created the job', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>((ctx) async => throw StateError('boom'));
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught.map((error) => '$error').toList(), ['Bad state: boom']);
  });

  test('a failure someone observed stays out of the zone', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>((ctx) async => throw StateError('boom')).ignore();
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught, isEmpty);
  });

  test('the body error reaches the observer once, not the zone twice', () {
    final journal = JobJournal();
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>(
            key: 'job',
            observer: journal,
            (ctx) async => throw StateError('boom'),
          ).ignore();
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(journal.take(), [
      '[job] started',
      '[job] error Bad state: boom',
      '[job] finished Failed(Bad state: boom)',
    ]);
    expect(caught, isEmpty, reason: 'the outcome was observed by ignore');
  });

  test('the homeless errors go to the zone without an observer', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>((ctx) async {
            ctx.onCancel(() => throw StateError('onCancel'));
            unawaited(
              ctx.wait(() async {
                await delay(20);
                throw StateError('late action');
              }),
            );
            await ctx.wait(() => delay(100));
          });
          async.elapse(const Duration(milliseconds: 5));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      containsAll(<String>['Bad state: onCancel', 'Bad state: late action']),
      // The abandoned `wait` also throws its own Cancelled into the zone:
      // nobody awaits the future it returned.
      reason: 'both errors have nowhere else to go',
    );
  });

  test('the same errors go to the observer when there is one', () {
    final journal = JobJournal();
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(
            key: 'job',
            observer: journal,
            (ctx) async {
              ctx.onCancel(() => throw StateError('onCancel'));
              // `ignore`, so the Cancelled thrown into the abandoned
              // future does not reach the zone on its own account.
              ctx.wait(() async {
                await delay(20);
                throw StateError('late action');
              }).ignore();
              await ctx.wait(() => delay(100));
            },
          );
          async.elapse(const Duration(milliseconds: 5));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      journal.take(),
      containsAll(<String>[
        '[job] error Bad state: onCancel',
        '[job] error Bad state: late action',
      ]),
    );
    expect(caught, isEmpty, reason: 'an observer takes the whole path');
  });
  test('an error a late cancellation covers still reaches the zone', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>((ctx) async {
            ctx.run(
              Job.deferred<void>(
                key: 'child',
                (child) => child.wait(() => delay(50)),
              ),
            );
            throw StateError('boom');
          });
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.elapse(const Duration(milliseconds: 100));
          expect(job.outcome, isA<Cancelled>());
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught.map((error) => '$error').toList(), ['Bad state: boom']);
  });

  test('an error a late cancellation covers goes where an uncovered one goes',
      () {
    final journal = JobJournal();
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(
            key: 'job',
            observer: journal,
            (ctx) async {
              ctx.run(
                Job.deferred<void>(
                  key: 'child',
                  (child) => child.wait(() => delay(50)),
                ),
              );
              throw StateError('boom');
            },
          );
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.elapse(const Duration(milliseconds: 100));
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      ['Bad state: boom'],
      reason: 'nobody looked at the outcome, so the zone hears — as it '
          'does for a failure no cancellation covered',
    );
    expect(
      journal.lines.where((line) => line.contains('error')).toList(),
      ['[job] error Bad state: boom'],
      reason: 'and the observer hears once, not twice',
    );
  });
  test('a join the body walked away from puts no cancellation in the zone', () {
    final caught = <Object>[];
    final closed = <String>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>((ctx) async {
            unawaited(
              ctx.join<String>(
                () => delay(50).then((_) => 'db'),
                discard: closed.add,
              ),
            );
            throw const Cancelled('enough');
          }).ignore();
          async.elapse(const Duration(milliseconds: 200));
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught, isEmpty);
    expect(closed, ['db'], reason: 'the value is still cleaned up');
  });
  test("a child's failure nobody looked at reaches the zone", () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>((ctx) async {
            ctx.run(
              Job.deferred<void>(key: 'child', (child) async {
                // Outlives the body, so the parent really waits for it: a
                // child that finished earlier is not on the waiting list
                // at all.
                await child.wait(() => delay(20));
                throw StateError('child boom');
              }),
            );
            await ctx.wait(() => delay(10));
          }).ignore();
          async.elapse(const Duration(milliseconds: 50));
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      ['Bad state: child boom'],
      reason: 'waiting for a child is not looking at its outcome',
    );
  });

  test('cancelling a job does not silence the failure it ends with', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>(cancellable: false, (ctx) async {
            await ctx.wait(() => delay(10));
            throw StateError('boom');
          });
          async.elapse(const Duration(milliseconds: 5));
          job.cancel().ignore();
          async.elapse(const Duration(milliseconds: 50));
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught.map((error) => '$error').toList(),
      ['Bad state: boom'],
      reason: 'the waiting of an engine is not observation',
    );
  });

  test('a listener that arrives one microtask later still counts', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          late Job<void> job;
          job = Job<void>(
            observer: _TouchAfterFinish(() => job.done.ignore()),
            (ctx) async => throw StateError('boom'),
          );
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught, isEmpty, reason: 'one microtask of grace, as Dart gives');
  });
  test('a body that turns its cancellation into an error keeps it in hand', () {
    // No observer: the zone is the only place such an error could land.
    final caught = <Object>[];
    late Job<void> job;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          job = Job<void>((ctx) async {
            try {
              await ctx.wait(() => delay(100));
            } on Cancelled {
              // The device said no in its own words, as a real one does
              // through the token it was handed.
              throw StateError('device aborted');
            }
          });
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught,
      isEmpty,
      reason: 'the job was already cancelled when the body threw',
    );
    expect(job.outcome, isA<Cancelled>());
  });

  test('ignore silences a failure a late cancellation covered', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = Job<void>((ctx) async {
            ctx.run(
              Job.deferred<void>(
                key: 'child',
                (child) => child.wait(() => delay(50)),
              ),
            );
            throw StateError('boom');
          })
            ..ignore();
          async.elapse(const Duration(milliseconds: 10));
          job.cancel().ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught, isEmpty);
  });
}

/// Touches the outcome one microtask after the job finished.
final class _TouchAfterFinish extends JobObserver {
  final void Function() _touch;

  _TouchAfterFinish(this._touch);

  @override
  void onFinish(Job<Object?> job) => scheduleMicrotask(_touch);
}
